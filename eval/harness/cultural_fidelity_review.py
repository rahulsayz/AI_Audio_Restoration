# ruff: noqa: E402, E501
"""
Sangeet AI Cultural Fidelity Review.
Verifies fundamental, harmonic, and microtonal vibrato preservation on a synthetic Indian vocal mimic.
"""

import sys
from pathlib import Path

import numpy as np

# Add services/inference directory and proto generated directories to sys.path
repo_root = Path(__file__).resolve().parent.parent.parent
inference_dir = repo_root / "services/inference"
proto_dir = inference_dir / "sangeet_inference" / "proto"

for d in [str(inference_dir), str(proto_dir)]:
    if d not in sys.path:
        sys.path.insert(0, d)

from sangeet_inference.stages.deep_filter_net import DeepFilterNetStage


def generate_pink_noise(samples: int) -> np.ndarray:
    """
    Generates normalized pink noise.
    """
    white = np.random.normal(0.0, 1.0, samples)
    f = np.fft.rfft(white)
    frequencies = np.fft.rfftfreq(samples)
    frequencies[0] = frequencies[1]
    scaling = 1.0 / np.sqrt(frequencies)
    scaling[0] = 0.0
    pink = np.fft.irfft(f * scaling, n=samples)
    return pink / np.max(np.abs(pink))


def compute_spectral_centroid(sig: np.ndarray, sr: int) -> float:
    """
    Computes the spectral centroid of a mono signal.
    """
    n = len(sig)
    fft_mag = np.abs(np.fft.rfft(sig))
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    return float(np.sum(freqs * fft_mag) / (np.sum(fft_mag) + 1e-8))


def compute_band_power(sig: np.ndarray, f_start: float, f_end: float, sr: int) -> float:
    """
    Computes absolute signal power in a specific frequency band.
    """
    n = len(sig)
    fft_mag = np.abs(np.fft.rfft(sig))
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    idx = (freqs >= f_start) & (freqs <= f_end)
    return float(np.sum(fft_mag[idx] ** 2))


def compute_instantaneous_frequency(data: np.ndarray, sr: int) -> np.ndarray:
    """
    Computes instantaneous frequency using Hilbert transform via FFT.
    """
    n = len(data)
    f = np.fft.fft(data)
    h = np.zeros(n)
    if n % 2 == 0:
        h[0] = 1
        h[n // 2] = 1
        h[1 : n // 2] = 2
    else:
        h[0] = 1
        h[1 : (n + 1) // 2] = 2
    analytic = np.fft.ifft(f * h)
    phase = np.unwrap(np.angle(analytic))
    return np.diff(phase) / (2.0 * np.pi) * sr


def bandpass_and_compute_inst_freq(
    data: np.ndarray, f_start: float, f_end: float, sr: int
) -> np.ndarray:
    """
    Bandpasses a signal and calculates instantaneous frequency.
    """
    n = len(data)
    f = np.fft.rfft(data)
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    idx = (freqs < f_start) | (freqs > f_end)
    f[idx] = 0.0
    filtered = np.fft.irfft(f, n=n)
    return compute_instantaneous_frequency(filtered, sr)


def run_review() -> None:
    sr = 48000
    duration = 5.0
    samples = int(sr * duration)

    print("=" * 80)
    print("SANGEET AI CULTURAL FIDELITY REVIEW -- AUTOMATED SIGNAL PROFILING")
    print("=" * 80)

    # 1. Generate Synthetic Vocal Mimic with Vibrato
    # fundamental: 220 Hz, vibrato frequency: 5 Hz, vibrato depth: +/- 6 Hz
    f0 = 220.0
    f_vib = 5.0
    depth = 6.0

    t = np.linspace(0.0, duration, samples, endpoint=False)
    # Integral of instantaneous frequency f(t) = f0 + depth * sin(2*pi*f_vib*t)
    phi = 2.0 * np.pi * f0 * t - (depth / f_vib) * np.cos(2.0 * np.pi * f_vib * t)

    fundamental = np.sin(phi)
    harmonic_5 = np.sin(5.0 * phi)
    harmonic_7 = np.sin(7.0 * phi)

    # Blend mimicking an Indian vocal structure (fundamental + 5th + 7th)
    clean = fundamental + 0.5 * harmonic_5 + 0.25 * harmonic_7
    clean /= np.max(np.abs(clean))

    # Add pink noise at -20 dB (noise amplitude of 0.1)
    pink = generate_pink_noise(samples)
    noisy = clean + 0.1 * pink
    noisy /= np.max(np.abs(noisy))

    # Channels first stereo shape [2, samples]
    clean_stereo = np.stack([clean, clean], axis=0).astype(np.float32)
    noisy_stereo = np.stack([noisy, noisy], axis=0).astype(np.float32)

    # Load DeepFilterNetStage
    print("Loading DeepFilterNet 3 Stage...")
    stage = DeepFilterNetStage()

    results = {}

    for strength in [0.0, 0.3, 0.5, 0.7]:
        print(f"\nProcessing at Strength: {strength:.1f}")
        if strength == 0.0:
            restored = noisy_stereo
        else:
            restored = stage.process(noisy_stereo, {"strength": strength})

        # Calculations
        centroid = compute_spectral_centroid(restored[0], sr)

        # Power integration bands
        pow_fund = compute_band_power(restored[0], 200, 240, sr)
        pow_5th = compute_band_power(restored[0], 1050, 1150, sr)
        pow_7th = compute_band_power(restored[0], 1480, 1600, sr)

        # Instantaneous vibrato peak detection
        # Extract instantaneous frequency in the fundamental band
        inst_f = bandpass_and_compute_inst_freq(restored[0], 200, 240, sr)
        inst_f_ac = inst_f - np.mean(inst_f)
        
        # FFT of instantaneous frequency to verify 5 Hz vibrato peak
        n_if = len(inst_f_ac)
        fft_if = np.abs(np.fft.rfft(inst_f_ac))
        freqs_if = np.fft.rfftfreq(n_if, 1.0 / sr)
        
        # Search for peak close to 5 Hz (vibrato frequency)
        idx_vib = (freqs_if >= 4.5) & (freqs_if <= 5.5)
        peak_vib_power = np.max(fft_if[idx_vib]) if np.any(idx_vib) else 0.0
        total_if_power = np.sum(fft_if) + 1e-8
        vibrato_index = (peak_vib_power / total_if_power) * 100.0

        results[strength] = {
            "centroid": centroid,
            "pow_fund": pow_fund,
            "pow_5th": pow_5th,
            "pow_7th": pow_7th,
            "vibrato_index": vibrato_index,
        }

    # Reference powers
    ref_fund = compute_band_power(clean_stereo[0], 200, 240, sr)
    ref_5th = compute_band_power(clean_stereo[0], 1050, 1150, sr)
    ref_7th = compute_band_power(clean_stereo[0], 1480, 1600, sr)

    print("\n" + "=" * 80)
    print("CULTURAL FIDELITY ANALYSIS FINDINGS")
    print("=" * 80)
    print(f"Clean Reference Spectral Centroid: {compute_spectral_centroid(clean_stereo[0], sr):.2f} Hz")
    print(f"Noisy Input Spectral Centroid: {compute_spectral_centroid(noisy_stereo[0], sr):.2f} Hz")

    print("\n--- Harmonic Preservation Profile (relative to Clean Reference) ---")
    for s in [0.3, 0.5, 0.7]:
        fund_db = 10.0 * np.log10(results[s]["pow_fund"] / ref_fund)
        fifth_db = 10.0 * np.log10(results[s]["pow_5th"] / ref_5th)
        seventh_db = 10.0 * np.log10(results[s]["pow_7th"] / ref_7th)
        print(f"Strength {s:.1f}:")
        print(f"  * Fundamental (220 Hz) Survival: {fund_db:+.2f} dB")
        print(f"  * 5th Harmonic (1100 Hz) Survival: {fifth_db:+.2f} dB")
        print(f"  * 7th Harmonic (1540 Hz) Survival: {seventh_db:+.2f} dB")

    print("\n--- Microtonal Vibrato Verification (instantaneous frequency 5 Hz index) ---")
    print(f"Clean Reference Vibrato Index: {results[0.0]['vibrato_index']:.2f}%")
    for s in [0.3, 0.5, 0.7]:
        print(f"Strength {s:.1f}: Vibrato Index = {results[s]['vibrato_index']:.2f}% (Status: {'PASSED' if results[s]['vibrato_index'] > 5.0 else 'ATTENUATED'})")

    print("\n" + "=" * 80)


if __name__ == "__main__":
    run_review()
