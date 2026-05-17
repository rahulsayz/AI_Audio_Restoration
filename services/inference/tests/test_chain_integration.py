"""
Integration test suite for the full sequential restoration chain.
Executes Dehum (Stage 3) -> DeepFilterNet 3 (Stage 4) -> Declick (Stage 5)
sequentially and asserts strict signal preservation and attenuation metrics.
"""
import tempfile
import threading
from pathlib import Path

import numpy as np
import soundfile as sf
from sangeet.v1.restoration_pb2 import RestorationRecipe, StageInvocation

from sangeet_inference.pipeline import RestorationPipeline


def test_full_restoration_chain_integration() -> None:
    """
    Synthesizes a combined degraded signal:
      - Clean fundamental sine wave at 440 Hz
      - 50 Hz mains hum at -20 dB
      - Pink noise floor at -30 dB
      - Deterministic click impulse spikes at -10 dB
    Applies a 100ms cosine fade to bypass boundary transients and lets the dehum notch settle.
    Processes this through the full Stage 3 -> 4 -> 5 sequential restoration chain.
    Asserts strict, high-fidelity compliance metrics.
    """
    sr = 48000
    duration = 12.0
    num_samples = int(duration * sr)
    t = np.linspace(0, duration, num_samples, endpoint=False)

    # 1. Synthesize signal components
    # A. Clean 440 Hz fundamental (amplitude 0.5 = -6 dBFS peak)
    sine_440 = 0.5 * np.sin(2 * np.pi * 440.0 * t)

    # B. 50 Hz mains hum at -20 dB (amplitude 0.1)
    hum_50 = 0.1 * np.sin(2 * np.pi * 50.0 * t)

    # C. Pink noise floor calibrated precisely to -30 dB RMS
    uneven = np.random.default_rng(seed=42).standard_normal(num_samples)
    f = np.fft.rfftfreq(num_samples)
    f[0] = 1.0  # Avoid division by zero at DC
    scaling = 1.0 / np.sqrt(f)
    filtered_noise = np.fft.irfft(np.fft.rfft(uneven) * scaling, n=num_samples)
    
    current_rms = np.sqrt(np.mean(filtered_noise**2))
    target_noise_rms = 10 ** (-30.0 / 20.0)  # -30 dB RMS
    pink_noise = filtered_noise * (target_noise_rms / current_rms)

    # D. Apply 100ms cosine window boundary fade to continuous signals
    # This prevents abrupt start/stop transients and lets the notch filters settle perfectly.
    fade_len = int(0.1 * sr)  # 100ms
    fade_window = np.ones(num_samples, dtype=np.float32)
    fade_in = 0.5 * (1.0 - np.cos(np.pi * np.arange(fade_len) / fade_len))
    fade_out = fade_in[::-1]
    fade_window[:fade_len] = fade_in
    fade_window[-fade_len:] = fade_out

    continuous_mixture = (sine_440 + hum_50 + pink_noise) * fade_window

    # E. Impulse clicks at spaced intervals at -10 dB (amplitude 0.316)
    clicks = np.zeros(num_samples, dtype=np.float32)
    click_times = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0]
    click_indices = [int(ct * sr) for ct in click_times]
    click_amp = 10 ** (-10.0 / 20.0)  # -10 dB peak amplitude
    for idx in click_indices:
        clicks[idx] = click_amp

    # Assemble final test signals
    input_signal = continuous_mixture + clicks
    input_audio = input_signal.reshape(1, -1).astype(np.float32)

    # Reference click-free signal to isolate click residuals
    reference_audio = continuous_mixture.reshape(1, -1).astype(np.float32)

    # 2. Setup full RestorationPipeline and temporary files
    pipeline = RestorationPipeline()
    recipe = RestorationRecipe()
    # Chain: Stage 3 (dehum) -> Stage 4 (deep_filter_net) -> Stage 5 (declick)
    recipe.stages.append(StageInvocation(stage_name="dehum", strength=0.5))
    recipe.stages.append(StageInvocation(stage_name="deep_filter_net", strength=0.5))
    recipe.stages.append(StageInvocation(stage_name="declick", strength=0.5))

    cancel_event = threading.Event()

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as in_file, \
         tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as ref_in_file, \
         tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as out_file, \
         tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as ref_out_file:
        
        in_path = in_file.name
        ref_in_path = ref_in_file.name
        out_path = out_file.name
        ref_out_path = ref_out_file.name

    try:
        # Write temporary inputs
        sf.write(in_path, input_audio.T, sr)
        sf.write(ref_in_path, reference_audio.T, sr)

        # Execute sequential restoration chain on both files
        pipeline.process_audio(in_path, out_path, recipe, cancel_event)
        pipeline.process_audio(ref_in_path, ref_out_path, recipe, cancel_event)

        # Load results
        output_audio, output_sr = sf.read(out_path, dtype="float32")
        output_audio = output_audio.reshape(1, -1)
        assert output_sr == sr

        ref_output_audio, ref_output_sr = sf.read(ref_out_path, dtype="float32")
        ref_output_audio = ref_output_audio.reshape(1, -1)
        assert ref_output_sr == sr

        # 3. Rigorous verification metrics
        # Compute spectral FFT magnitudes
        freqs = np.fft.rfftfreq(num_samples, d=1.0 / sr)
        in_fft = np.abs(np.fft.rfft(input_audio[0])) / num_samples
        out_fft = np.abs(np.fft.rfft(output_audio[0])) / num_samples

        # A. Fundamental Preservation (440 Hz within 1 dB)
        idx_440 = int(np.argmin(np.abs(freqs - 440.0)))
        energy_in_440 = in_fft[idx_440 - 1] + in_fft[idx_440] + in_fft[idx_440 + 1]
        energy_out_440 = out_fft[idx_440 - 1] + out_fft[idx_440] + out_fft[idx_440 + 1]
        db_diff_440 = 20 * np.log10(energy_out_440 / max(1e-10, energy_in_440))
        assert np.abs(db_diff_440) < 1.0, (
            f"Fundamental (440 Hz) was modified by {db_diff_440:.2f} dB (expected < 1.0 dB)."
        )

        # B. Mains Hum Attenuation (50 Hz hum attenuated by at least 30 dB)
        idx_50 = int(np.argmin(np.abs(freqs - 50.0)))
        energy_in_50 = in_fft[idx_50 - 1] + in_fft[idx_50] + in_fft[idx_50 + 1]
        energy_out_50 = out_fft[idx_50 - 1] + out_fft[idx_50] + out_fft[idx_50 + 1]
        attenuation_50 = 20 * np.log10(energy_in_50 / max(1e-10, energy_out_50))
        assert attenuation_50 >= 30.0, (
            f"Mains hum (50 Hz) attenuation was {attenuation_50:.2f} dB (expected >= 30.0 dB)."
        )

        # C. Broadband Noise Reduction (reduced by at least 8 dB in the 5k-15k band)
        mask_noise = (freqs >= 5000.0) & (freqs <= 15000.0)
        energy_in_noise = np.sum(in_fft[mask_noise]**2)
        energy_out_noise = np.sum(out_fft[mask_noise]**2)
        noise_reduction = 10 * np.log10(energy_in_noise / max(1e-10, energy_out_noise))
        assert noise_reduction >= 8.0, (
            f"Noise floor reduction was {noise_reduction:.2f} dB (expected >= 8.0 dB)."
        )

        # D. Click Removal (isolated peak click residue < -25 dB)
        residue = output_audio - ref_output_audio
        window_size = int(0.005 * sr)  # 5ms neighborhood
        for idx in click_indices:
            start = max(0, idx - window_size // 2)
            end = min(num_samples, idx + window_size // 2)
            local_peak = np.max(np.abs(residue[0, start:end]))
            local_peak_db = 20 * np.log10(max(1e-10, local_peak))
            assert local_peak_db < -25.0, (
                f"Impulse click at index {idx} was not successfully removed. "
                f"Peak residual: {local_peak_db:.2f} dB (expected < -25.0 dB)."
            )

        # E. Spectral Artifact Prevention (no new artifacts > -50 dBFS outside 430-450 Hz guard)
        guard_band_mask = (freqs >= 430.0) & (freqs <= 450.0)
        unexpected_fft = out_fft[~guard_band_mask]
        peak_artifact_amp = np.max(unexpected_fft)
        peak_artifact_db = 20 * np.log10(max(1e-10, peak_artifact_amp))
        assert peak_artifact_db < -50.0, (
            f"Detected unexpected spectral artifact at "
            f"{freqs[~guard_band_mask][np.argmax(unexpected_fft)]:.2f} Hz "
            f"with amplitude {peak_artifact_db:.2f} dB (expected < -50.0 dB)."
        )

    finally:
        # Clean up temporary files
        for p in [in_path, ref_in_path, out_path, ref_out_path]:
            path_obj = Path(p)
            if path_obj.exists():
                try:
                    path_obj.unlink()
                except Exception:
                    pass
