"""
Unit and integration tests for the pipeline orchestrator.
Validates perfect reconstruction, chunk overlap-adds, and cancellation safety.
"""
import os
import tempfile
import threading
import numpy as np
import pytest
import soundfile as sf

from sangeet.v1.restoration_pb2 import RestorationRecipe, StageInvocation
from sangeet_inference.pipeline import RestorationPipeline

def test_pipeline_perfect_reconstruction(make_signal) -> None:
    """
    Validates that chunking followed by overlap-add reassembly using equal-power cosine fades
    and perfect reconstruction normalization yields a bit-exact identical signal.
    """
    pipeline = RestorationPipeline()
    sr = 48000
    
    # Test on a sine wave signal longer than one chunk (e.g. 75 seconds)
    audio = make_signal("sine", duration=75.0, sr=sr)
    
    # Chunk the audio
    chunks = pipeline.chunk_audio(audio, sr, window_s=30.0, overlap_s=1.0)
    
    # Assert chunking counts: 75 seconds with 30s window and 1s overlap (step = 29s)
    # Chunk 0: 0-30s
    # Chunk 1: 29-59s
    # Chunk 2: 58-88s (padded)
    # Total chunks = 3
    assert len(chunks) == 3
    assert chunks[0]["data"].shape == (1, 30 * sr)
    assert chunks[0]["is_first"]
    assert not chunks[0]["is_last"]
    assert chunks[2]["is_last"]

    # Assemble back
    reconstructed = pipeline.assemble_chunks(chunks, original_len=audio.shape[1], sr=sr)
    
    # Assert shape is exactly preserved
    assert reconstructed.shape == audio.shape
    
    # Assert floating-point reconstruction identity within high precision bounds
    assert np.allclose(reconstructed, audio, rtol=1e-6, atol=1e-6), \
        "Overlap-add reassembly with equal-power cosine crossfade failed perfect reconstruction"

def test_pipeline_process_audio_end_to_end(make_signal) -> None:
    """
    Tests end-to-end pipeline execution from file decode to file export.
    """
    pipeline = RestorationPipeline()
    sr = 44100
    duration = 5.0
    
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as in_file, \
         tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as out_file:
        in_path = in_file.name
        out_path = out_file.name

    try:
        # Generate 5.0s sine wave and write to temp input
        input_data = make_signal("sine", duration=duration, sr=sr)
        sf.write(in_path, input_data.T, sr)

        recipe = RestorationRecipe()
        recipe.stages.append(StageInvocation(stage_name="passthrough", strength=1.0))

        cancel_event = threading.Event()
        
        # Track progress callback invocations
        progress_calls = []
        def progress_cb(stage: str, progress: float) -> None:
            progress_calls.append((stage, progress))

        pipeline.process_audio(
            input_path=in_path,
            output_path=out_path,
            recipe=recipe,
            cancel_event=cancel_event,
            progress_callback=progress_cb
        )

        # Assert output file exists and can be loaded
        assert os.path.exists(out_path)
        output_data, output_sr = sf.read(out_path, dtype="float32")
        
        assert output_sr == sr
        # output soundfile loads as [samples] or [samples, channels]
        output_data = output_data.reshape(1, -1)
        assert output_data.shape == input_data.shape
        
        # Verify progress callbacks were made and reached 100%
        assert len(progress_calls) > 0
        assert progress_calls[-1][1] == 100.0
    finally:
        if os.path.exists(in_path):
            os.unlink(in_path)
        if os.path.exists(out_path):
            os.unlink(out_path)

def test_pipeline_cancellation(make_signal) -> None:
    """
    Verifies that setting the cancel_event breaks execution gracefully and raises a RuntimeError.
    """
    pipeline = RestorationPipeline()
    sr = 44100
    
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as in_file, \
         tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as out_file:
        in_path = in_file.name
        out_path = out_file.name

    try:
        input_data = make_signal("sine", duration=65.0, sr=sr)
        sf.write(in_path, input_data.T, sr)

        recipe = RestorationRecipe()
        recipe.stages.append(StageInvocation(stage_name="passthrough", strength=1.0))

        cancel_event = threading.Event()
        
        def cancel_trigger(stage: str, progress: float) -> None:
            # Set cancellation event during first chunk completion callback
            cancel_event.set()

        with pytest.raises(RuntimeError) as exc_info:
            pipeline.process_audio(
                input_path=in_path,
                output_path=out_path,
                recipe=recipe,
                cancel_event=cancel_event,
                progress_callback=cancel_trigger
            )

        assert "cancelled" in str(exc_info.value)
    finally:
        if os.path.exists(in_path):
            os.unlink(in_path)
        if os.path.exists(out_path):
            os.unlink(out_path)
