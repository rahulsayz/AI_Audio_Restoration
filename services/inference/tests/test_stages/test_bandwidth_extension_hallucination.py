"""
Diagnostic Hallucination Probe Test for BandwidthExtensionStage.
Validates spectral purity and quantifies hallucinated top-end energy.
This test is diagnostic (does not fail the build unless code crashes).
"""
import sys
import numpy as np
import pytest

from sangeet_inference.stages.bandwidth_extension import BandwidthExtensionStage


def make_strict_bandlimited_signal(kind: str, duration: float, sr: int, cutoff_hz: float = 5000.0) -> np.ndarray:
    """
    Generates a signal that is guaranteed to have exactly ZERO energy above cutoff_hz.
    Uses FFT brickwall filtering to ensure zero leakage.
    """
    num_samples = int(duration * sr)
    t = np.linspace(0, duration, num_samples, endpoint=False)

    if kind == "pure_tone":
        # Pure 1 kHz sine wave
        y = np.sin(2 * np.pi * 1000.0 * t) * 0.3
    elif kind == "harmonics":
        # 500 Hz fundamental + 2500 Hz (5th harmonic)
        y1 = np.sin(2 * np.pi * 500.0 * t) * 0.2
        y5 = np.sin(2 * np.pi * 2500.0 * t) * 0.1
        y = y1 + y5
    elif kind == "pink_noise":
        # Pink noise
        uneven = np.random.default_rng(seed=123).standard_normal(num_samples)
        f = np.fft.rfftfreq(num_samples)
        f[0] = 1.0
        scaling = 1.0 / np.sqrt(f)
        y = np.fft.irfft(np.fft.rfft(uneven) * scaling, n=num_samples)
        # Normalize
        max_val = np.max(np.abs(y))
        if max_val > 0:
            y = (y / max_val) * 0.3
    else:
        raise ValueError(f"Unknown kind: {kind}")

    y_mono = y.reshape(1, -1).astype(np.float32)

    # Apply absolute brickwall filter at cutoff_hz in FFT domain
    n_fft = num_samples
    freqs = np.fft.rfftfreq(n_fft, d=1.0 / sr)
    cutoff_bin = np.searchsorted(freqs, cutoff_hz)

    x_fft = np.fft.rfft(y_mono[0], n=n_fft)
    x_fft[cutoff_bin:] = 0.0  # Zero out stopband completely

    filtered_y = np.fft.irfft(x_fft, n=n_fft).reshape(1, -1).astype(np.float32)
    
    # Double-check: verify stopband is absolutely silent (within float32 quantization and boundary leakage)
    verif_fft = np.fft.rfft(filtered_y[0], n=n_fft)
    assert np.allclose(verif_fft[cutoff_bin:], 0.0, atol=1e-4), "Sanity check failed: signal has stopband energy before BWE."

    return filtered_y


def test_bandwidth_extension_hallucination_probe() -> None:
    """
    Runs the BWE Hallucination Probe.
    Quantifies the synthesized high-frequency energy above 5 kHz.
    Prints a detailed Markdown-formatted report directly to stdout.
    """
    stage = BandwidthExtensionStage()
    sr = stage.sample_rate
    duration = 1.0
    num_samples = int(duration * sr)
    cutoff_hz = 5000.0

    n_fft = num_samples
    freqs = np.fft.rfftfreq(n_fft, d=1.0 / sr)
    cutoff_bin = np.searchsorted(freqs, cutoff_hz)

    # Dictionary to hold our report logs
    results = {}

    # Signal definitions
    kinds = ["pure_tone", "harmonics", "pink_noise"]
    strengths = [0.3, 0.5, 0.7]

    for kind in kinds:
        results[kind] = {}
        input_audio = make_strict_bandlimited_signal(kind, duration, sr, cutoff_hz)
        input_rms = float(np.sqrt(np.mean(input_audio[0] ** 2)))

        for strg in strengths:
            # Process BWE
            output_audio = stage.process(input_audio, {"strength": strg, "cutoff_frequency_hz": cutoff_hz})
            
            # Analyze FFT above 5 kHz
            out_fft = np.fft.rfft(output_audio[0], n=n_fft)
            stopband_fft = out_fft[cutoff_bin:]

            # Compute added RMS above 5 kHz in the time domain representation of the stopband
            # To isolate, zero out lowpass bins and IFFT
            stopband_full_fft = np.zeros_like(out_fft)
            stopband_full_fft[cutoff_bin:] = stopband_fft
            stopband_waveform = np.fft.irfft(stopband_full_fft, n=n_fft)
            added_rms = float(np.sqrt(np.mean(stopband_waveform ** 2)))

            # Calculate dB level of stopband relative to input rms
            if input_rms > 0:
                added_db = 20 * np.log10(added_rms / input_rms)
            else:
                added_db = -100.0

            # Distinguish harmonic vs inharmonic for pure_tone and harmonics
            inharmonic_db = -100.0
            harmonic_db = -100.0

            if kind in ["pure_tone", "harmonics"]:
                # Pure tone (1 kHz fundamental): harmonics are at 2k, 3k, 4k, 5k, 6k, 7k, 8k, etc.
                # Harmonics signal (500 Hz fund): harmonics are at 1k, 1.5k, 2k, 2.5k, 3k, ..., 5.5k, 6k, etc.
                fund_hz = 1000.0 if kind == "pure_tone" else 500.0
                
                # Identify harmonic and inharmonic bins in the stopband
                harmonic_mask = np.zeros(len(freqs), dtype=bool)
                for f_harm in np.arange(fund_hz, sr / 2, fund_hz):
                    # Bins within 50 Hz of a harmonic frequency
                    harmonic_mask |= (np.abs(freqs - f_harm) <= 50.0)

                # Split stopband into harmonic and inharmonic
                stopband_harmonic_fft = np.zeros_like(out_fft)
                stopband_inharmonic_fft = np.zeros_like(out_fft)

                # Only evaluate bins in the stopband
                for idx in range(cutoff_bin, len(freqs)):
                    if harmonic_mask[idx]:
                        stopband_harmonic_fft[idx] = out_fft[idx]
                    else:
                        stopband_inharmonic_fft[idx] = out_fft[idx]

                harmonic_waveform = np.fft.irfft(stopband_harmonic_fft, n=n_fft)
                inharmonic_waveform = np.fft.irfft(stopband_inharmonic_fft, n=n_fft)

                harmonic_rms = float(np.sqrt(np.mean(harmonic_waveform ** 2)))
                inharmonic_rms = float(np.sqrt(np.mean(inharmonic_waveform ** 2)))

                if input_rms > 0:
                    harmonic_db = 20 * np.log10(harmonic_rms / input_rms) if harmonic_rms > 0 else -100.0
                    inharmonic_db = 20 * np.log10(inharmonic_rms / input_rms) if inharmonic_rms > 0 else -100.0

            results[kind][strg] = {
                "added_db": added_db,
                "harmonic_db": harmonic_db,
                "inharmonic_db": inharmonic_db,
                "warning": (kind == "pure_tone" and added_db > -80.0)  # Red flag if > 10 dB above -90 dB noise floor
            }

    # Write a beautiful markdown report to stdout
    print("\n" + "=" * 80)
    print("        SANGEET AI BANDWIDTH EXTENSION HALLUCINATION PROBE REPORT")
    print("=" * 80)
    print("Diagnostic probe measuring synthesized high-frequency energy (> 5 kHz)")
    print("on strictly bandlimited inputs (fundamental cutoff = 5000 Hz).")
    print("Noise floor reference = -90.0 dB. Red Flag threshold for Pure Tone = -80.0 dB.")
    print("-" * 80)

    for kind in kinds:
        print(f"\n### Signal Class: {kind.upper()}")
        print("| Strength | Total stopband (dB) | Harmonic stopband (dB) | Inharmonic stopband (dB) | Status |")
        print("|----------|---------------------|------------------------|--------------------------|--------|")
        for strg in strengths:
            res = results[kind][strg]
            status = "🚨 RED FLAG" if res["warning"] else "✅ OK"
            h_str = f"{res['harmonic_db']:.2f}" if res["harmonic_db"] > -99 else "N/A"
            ih_str = f"{res['inharmonic_db']:.2f}" if res["inharmonic_db"] > -99 else "N/A"
            print(f"| {strg:.1f}      | {res['added_db']:.2f} dB          | {h_str}               | {ih_str}                 | {status}  |")

    print("\n" + "=" * 80)
    print("Report completed successfully.")
    print("=" * 80 + "\n")

    # This test is diagnostic and non-blocking, so we flush and exit with success.
    sys.stdout.flush()
