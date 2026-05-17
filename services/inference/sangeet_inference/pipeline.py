"""
Sangeet AI Pipeline Orchestration.
Processes full-length and chunked audio data sequentially through the chosen DSP/ML models.
"""
import time
import threading
from typing import Callable, Optional, Dict, Any, List
import numpy as np
import soundfile as sf
import structlog
import torch
import torchaudio

from sangeet.v1.restoration_pb2 import RestorationRecipe
from sangeet_inference.stages.base import RestorationStage
from sangeet_inference.stages.passthrough import PassthroughStage

logger = structlog.get_logger()

class RestorationPipeline:
    """
    Orchestrates the sequence of restoration stages on audio files.
    Handles high-quality resampling, overlap-add chunking, equal-power fading,
    and thread-safe graceful cancellation.
    """

    def __init__(self) -> None:
        """
        Loads all available restoration stages.
        """
        # Register available stages. V1 starts with PassthroughStage.
        self.stages: Dict[str, RestorationStage] = {
            "passthrough": PassthroughStage()
        }
        logger.info("RestorationPipeline initialized", loaded_stages=list(self.stages.keys()))

    def _resample(self, audio: np.ndarray, orig_sr: int, target_sr: int) -> np.ndarray:
        """
        Resamples a float32 audio array [channels, samples] using high-quality sinc polyphase filters.
        """
        if orig_sr == target_sr:
            return audio

        logger.info("Resampling audio inside pipeline", orig_sr=orig_sr, target_sr=target_sr)
        tensor = torch.from_numpy(audio)
        resampler = torchaudio.transforms.Resample(orig_freq=orig_sr, new_freq=target_sr)
        resampled_tensor = resampler(tensor)
        return resampled_tensor.numpy()

    def chunk_audio(
        self,
        audio: np.ndarray,
        sr: int,
        window_s: float = 30.0,
        overlap_s: float = 1.0
    ) -> List[Dict[str, Any]]:
        """
        Chunks the input audio array into overlapping windows.
        Pads the rightmost boundary using reflection padding if the length
        is not an exact multiple.
        
        Args:
            audio: Float32 NumPy array of shape [channels, samples].
            sr: Input sample rate in Hz.
            window_s: Window size in seconds (default 30s).
            overlap_s: Overlap size in seconds (default 1s).
            
        Returns:
            A list of dicts containing:
                "data": NumPy array of shape [channels, chunk_len]
                "start_idx": Start index of the chunk in the padded signal
                "is_first": Boolean indicating first chunk
                "is_last": Boolean indicating last chunk
        """
        channels, total_samples = audio.shape
        chunk_len = int(window_s * sr)
        overlap_len = int(overlap_s * sr)
        step_len = chunk_len - overlap_len

        if step_len <= 0:
            raise ValueError(f"Overlap ({overlap_s}s) must be strictly less than window ({window_s}s)")

        # Determine number of chunks needed to cover the entire signal
        if total_samples <= chunk_len:
            num_chunks = 1
        else:
            num_chunks = int(np.ceil((total_samples - overlap_len) / step_len))

        total_padded_len = step_len * (num_chunks - 1) + chunk_len
        pad_len = total_padded_len - total_samples

        if pad_len > 0:
            # Pad the right boundary using reflection to avoid edge artifacts
            padded_audio = np.pad(audio, ((0, 0), (0, pad_len)), mode="reflect")
        else:
            padded_audio = audio

        chunks = []
        for i in range(num_chunks):
            start_idx = i * step_len
            end_idx = start_idx + chunk_len
            chunk_data = padded_audio[:, start_idx:end_idx]
            
            chunks.append({
                "data": chunk_data.copy(),
                "start_idx": start_idx,
                "is_first": (i == 0),
                "is_last": (i == num_chunks - 1)
            })

        logger.debug(
            "Audio chunking complete",
            original_samples=total_samples,
            padded_samples=total_padded_len,
            num_chunks=num_chunks
        )
        return chunks

    def assemble_chunks(
        self,
        chunks: List[Dict[str, Any]],
        original_len: int,
        sr: int,
        window_s: float = 30.0,
        overlap_s: float = 1.0
    ) -> np.ndarray:
        """
        Reassembles individual chunks back into a continuous signal.
        Uses equal-power cosine crossfades in the overlap region and applies normalization
        to achieve perfect reconstruction of identical/unmodified signals.
        """
        if not chunks:
            return np.zeros((1, 0), dtype=np.float32)

        channels = chunks[0]["data"].shape[0]
        chunk_len = int(window_s * sr)
        overlap_len = int(overlap_s * sr)
        step_len = chunk_len - overlap_len

        # Determine final padded length
        num_chunks = len(chunks)
        total_padded_len = step_len * (num_chunks - 1) + chunk_len

        # Allocate arrays for reconstructed audio and window weight sums
        reconstructed = np.zeros((channels, total_padded_len), dtype=np.float32)
        window_sum = np.zeros(total_padded_len, dtype=np.float32)

        # Precompute equal-power cosine fade-in and fade-out curves
        n = np.arange(overlap_len)
        fade_in = np.sin((np.pi / 2.0) * (n / (overlap_len - 1)))
        fade_out = np.cos((np.pi / 2.0) * (n / (overlap_len - 1)))

        for i, chunk in enumerate(chunks):
            start_idx = chunk["start_idx"]
            data = chunk["data"]
            
            # Construct standard equal-power window weight for this chunk
            w = np.ones(chunk_len, dtype=np.float32)
            if not chunk["is_first"]:
                w[:overlap_len] = fade_in
            if not chunk["is_last"]:
                w[-overlap_len:] = fade_out

            # Accumulate window weight and weighted audio data
            reconstructed[:, start_idx:start_idx + chunk_len] += data * w
            window_sum[start_idx:start_idx + chunk_len] += w

        # Avoid division-by-zero on boundaries where no window has non-zero weight
        window_sum[window_sum == 0] = 1.0

        # Perfect reconstruction normalization
        reconstructed /= window_sum

        # Truncate any reflection padding back to original duration
        return reconstructed[:, :original_len]

    def process_audio(
        self,
        input_path: str,
        output_path: str,
        recipe: RestorationRecipe,
        cancel_event: threading.Event,
        progress_callback: Optional[Callable[[str, float], None]] = None,
        request_id: str = "unknown"
    ) -> None:
        """
        Executes the restoration pipeline.
        Reads file, resamples to 48kHz, chunks, applies stages, reassembles, and writes output.
        
        Args:
            input_path: Source audio path.
            output_path: Target restored audio path.
            recipe: RestorationRecipe specifying stages to run.
            cancel_event: threading.Event checked to exit gracefully on cancel.
            progress_callback: Optional callback for progress monitoring (stage_name, percent).
            request_id: Unique UUID correlating this job.
        """
        log = logger.bind(request_id=request_id)
        log.info("Starting audio restoration pipeline", input_path=input_path, output_path=output_path)

        # 1. Decode audio file using soundfile
        try:
            audio_data, samplerate = sf.read(input_path, dtype="float32")
        except Exception as e:
            log.error("Failed to decode audio file", error=str(e))
            raise RuntimeError(f"Could not read input audio: {e}") from e

        # Transpose to channels-first [channels, samples]
        if len(audio_data.shape) == 1:
            audio_data = audio_data.reshape(1, -1)
        else:
            audio_data = audio_data.T

        channels, original_samples = audio_data.shape
        log.info("Audio decoded", channels=channels, samples=original_samples, samplerate=samplerate)

        # 2. Resample to standard pipeline rate (48 kHz)
        pipeline_sr = 48000
        working_audio = self._resample(audio_data, samplerate, pipeline_sr)
        working_samples = working_audio.shape[1]

        # 3. Check for immediate cancellation
        if cancel_event.is_set():
            log.info("Restoration cancelled before chunk processing")
            raise RuntimeError("Restoration job was cancelled by the user.")

        # 4. Process each stage in the recipe sequentially
        stages_to_run = recipe.stages if recipe.stages else []
        if not stages_to_run:
            log.info("No stages specified in recipe. Performing default bypass.")
            stages_to_run = [PassthroughStage()]

        for stage_idx, invocation in enumerate(stages_to_run):
            stage_name = invocation.stage_name if hasattr(invocation, "stage_name") else "passthrough"
            strength = invocation.strength if hasattr(invocation, "strength") else 1.0
            
            if stage_name not in self.stages:
                log.error("Invalid stage requested", stage_name=stage_name)
                raise ValueError(f"Restoration stage '{stage_name}' is not registered in this pipeline.")

            stage = self.stages[stage_name]
            log.info("Running stage", stage_name=stage_name, strength=strength)

            # Stage-specific sample rate and mono requirements
            stage_sr = stage.sample_rate
            stage_audio = self._resample(working_audio, pipeline_sr, stage_sr)
            
            # Perform mono downmixing if required by the stage/model
            is_downmixed = False
            if stage.requires_mono and stage_audio.shape[0] > 1:
                log.info("Downmixing stereo audio to mono for stage", stage_name=stage_name)
                original_channels_audio = stage_audio
                stage_audio = np.mean(stage_audio, axis=0, keepdims=True)
                is_downmixed = True

            # Chunk the stage input
            chunks = self.chunk_audio(stage_audio, stage_sr)
            processed_chunks = []
            num_chunks = len(chunks)

            # Process chunks sequentially
            for c_idx, chunk in enumerate(chunks):
                if cancel_event.is_set():
                    log.info("Restoration cancelled during chunk processing", stage=stage_name, chunk=c_idx)
                    raise RuntimeError("Restoration job was cancelled by the user.")

                # Retrieve stage process params
                params: Dict[str, Any] = {}
                if hasattr(invocation, "params") and invocation.params:
                    params = dict(invocation.params.params)

                # Process current chunk
                processed_chunk_data = stage.process(chunk["data"], params)
                processed_chunks.append({
                    "data": processed_chunk_data,
                    "start_idx": chunk["start_idx"],
                    "is_first": chunk["is_first"],
                    "is_last": chunk["is_last"]
                })

                # Report progress
                if progress_callback:
                    # Scale based on stage index and current chunk completion
                    chunk_progress = (c_idx + 1) / num_chunks
                    overall_progress = ((stage_idx + chunk_progress) / len(stages_to_run)) * 100.0
                    progress_callback(stage_name, overall_progress)

            # Reassemble processed chunks
            stage_out = self.assemble_chunks(processed_chunks, stage_audio.shape[1], stage_sr)

            # Restore original multi-channel state if it was downmixed (Phase 1 simplistic fallback)
            if is_downmixed:
                # Duplicate the mono output across all original channels to preserve structural shape
                stage_out = np.repeat(stage_out, original_channels_audio.shape[0], axis=0)

            # Resample stage output back to standard 48 kHz
            working_audio = self._resample(stage_out, stage_sr, pipeline_sr)

        # 5. Resample back to original sample rate before export
        final_audio = self._resample(working_audio, pipeline_sr, samplerate)

        # Check for final cancellation before disk write
        if cancel_event.is_set():
            log.info("Restoration cancelled before final write")
            raise RuntimeError("Restoration job was cancelled by the user.")

        # 6. Write final restored audio to disk
        try:
            # soundfile expects [samples, channels] on write
            sf.write(output_path, final_audio.T, samplerate)
            log.info("Restoration file written successfully", output_path=output_path)
        except Exception as e:
            log.error("Failed to write restored audio file", error=str(e))
            raise RuntimeError(f"Could not write output audio file: {e}") from e
