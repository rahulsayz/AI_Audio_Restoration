# ruff: noqa: E402, E501
"""
Sangeet AI Smoke Test Generator and Pipeline Runner.
Generates 3 highly authentic synthetic music signals, places them in a gitignored corpus directory,
and runs them end-to-end through the Sangeet AI pipeline.
"""

import sys
import threading
from pathlib import Path

import numpy as np
import soundfile as sf

# Add services/inference directory and proto generated directories to sys.path
repo_root = Path(__file__).resolve().parent.parent.parent
inference_dir = repo_root / "services/inference"
proto_dir = inference_dir / "sangeet_inference" / "proto"

for d in [str(inference_dir), str(proto_dir)]:
    if d not in sys.path:
        sys.path.insert(0, d)

from sangeet.v1.restoration_pb2 import AudioFeatures

from sangeet_inference.pipeline import RestorationPipeline
from sangeet_inference.router import route_features


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


def generate_hum(samples: int, fundamental: float, sr: int) -> np.ndarray:
    """
    Generates 50Hz hum with odd harmonics.
    """
    t = np.linspace(0.0, float(samples) / sr, samples, endpoint=False)
    hum = (
        1.0 * np.sin(2.0 * np.pi * fundamental * t)
        + 0.3 * np.sin(2.0 * np.pi * 3.0 * fundamental * t)
        + 0.1 * np.sin(2.0 * np.pi * 5.0 * fundamental * t)
    )
    return hum / np.max(np.abs(hum))


def run_smoke_test_generation() -> None:
    sr = 48000
    duration = 5.0
    samples = int(sr * duration)
    t = np.linspace(0.0, duration, samples, endpoint=False)

    smoke_dir = repo_root / "eval/corpus/manual-smoke"
    smoke_dir.mkdir(parents=True, exist_ok=True)

    print("=" * 80)
    print("SANGEET AI - MANUAL SMOKE TEST ASSET GENERATION")
    print("=" * 80)

    # --- Recording 1: Golden-Era Playback Mimic (vocal_rafi_hiss.wav) ---
    print("Generating Recording 1: Golden-Era Playback with heavy hiss...")
    f0 = 330.0  # lata high vocal register
    phi_vocal = 2.0 * np.pi * f0 * t - (8.0 / 5.5) * np.cos(2.0 * np.pi * 5.5 * t)
    vocal = (
        1.0 * np.sin(phi_vocal)
        + 0.6 * np.sin(3.0 * phi_vocal)
        + 0.4 * np.sin(5.0 * phi_vocal)
        + 0.2 * np.sin(7.0 * phi_vocal)
    )
    vocal /= np.max(np.abs(vocal))
    # Mix with pink hiss at -25 dB (amplitude 0.056)
    noise_vocal = generate_pink_noise(samples)
    noisy_vocal = vocal + 0.056 * noise_vocal
    noisy_vocal /= np.max(np.abs(noisy_vocal))
    
    # --- Recording 2: Classical Instrumental (sitar_ravi_quiet.wav) ---
    print("Generating Recording 2: Classical Sitar pluck with hum and quiet sections...")
    # Pluck transients at D4 (293.66Hz) and A4 (440Hz) decaying exponentially
    pluck1 = np.sin(2.0 * np.pi * 293.66 * t) * np.exp(-3.0 * t)  # rapid decay
    pluck2 = np.sin(2.0 * np.pi * 440.00 * t) * np.exp(-1.5 * t)  # slow decay
    
    # Sympathetic drone (sustained sitar halo)
    drone = 0.1 * np.sin(2.0 * np.pi * 293.66 * t) + 0.05 * np.sin(2.0 * np.pi * 146.83 * t)
    
    sitar = pluck1 + pluck2 + drone
    sitar /= np.max(np.abs(sitar))
    
    # Mix with tape hum at 50 Hz (-35 dB, amp 0.018) + moderate hiss (-30 dB, amp 0.031)
    hum_sig = generate_hum(samples, 50.0, sr)
    noise_sitar = generate_pink_noise(samples)
    noisy_sitar = sitar + 0.018 * hum_sig + 0.031 * noise_sitar
    noisy_sitar /= np.max(np.abs(noisy_sitar))

    # --- Recording 3: Modern Pop Clean (modern_pop_clean.wav) ---
    print("Generating Recording 3: Modern clean pop signal (bypass test)...")
    # Sub bass (55Hz) + Snare transient clicks + Sawtooth lead synth
    sub_bass = np.sin(2.0 * np.pi * 55.0 * t)
    
    # Snare clicks at 1s, 2s, 3s, 4s (filtered noise bursts)
    clicks = np.zeros(samples)
    for second in [1, 2, 3, 4]:
        click_idx = int(second * sr)
        click_len = int(0.05 * sr)
        clicks[click_idx : click_idx + click_len] = np.random.normal(0.0, 1.0, click_len) * np.exp(-np.linspace(0.0, 5.0, click_len))
        
    synth_lead = 0.2 * np.sin(2.0 * np.pi * 880.0 * t) + 0.1 * np.sin(2.0 * np.pi * 1760.0 * t)
    modern = sub_bass + clicks + synth_lead
    modern /= np.max(np.abs(modern))
    # Very clean background noise floor at -60 dB (amplitude 0.001)
    noisy_modern = modern + 0.001 * generate_pink_noise(samples)
    noisy_modern /= np.max(np.abs(noisy_modern))

    # --- Save Input WAV Files (soundfile expects [samples, channels] shape) ---
    sf.write(smoke_dir / "vocal_rafi_hiss.wav", np.stack([noisy_vocal, noisy_vocal], axis=-1), sr)
    sf.write(smoke_dir / "sitar_ravi_quiet.wav", np.stack([noisy_sitar, noisy_sitar], axis=-1), sr)
    sf.write(smoke_dir / "modern_pop_clean.wav", np.stack([noisy_modern, noisy_modern], axis=-1), sr)
    print("All input signals saved successfully under eval/corpus/manual-smoke/.")

    # --- Pipeline End-to-End Execution ---
    print("\nRunning Sangeet AI Pipeline over all smoke test inputs...")
    pipeline = RestorationPipeline()

    # Define mock features corresponding to the 3 profiles
    class AudioFeaturesWrapper:
        def __init__(self, pb: AudioFeatures, crest: float | None = None, classical: bool = False):
            self._pb = pb
            self.crest_factor = crest
            self.is_classical = classical

        def HasField(self, name: str) -> bool:  # noqa: N802
            return self._pb.HasField(name)

        def __getattr__(self, name: str) -> getattr:
            return getattr(self._pb, name)

    profiles = [
        {
            "in": "vocal_rafi_hiss.wav",
            "out": "vocal_rafi_hiss_restored.wav",
            "feats": AudioFeaturesWrapper(
                AudioFeatures(
                    sample_rate=sr,
                    channels=2,
                    duration_s=duration,
                    snr_estimate_db=25.0,  # routes DFN strength 0.50
                    spectral_centroid_hz=1800,
                    hum_50hz_present=False,
                    hum_60hz_present=False,
                )
            )
        },
        {
            "in": "sitar_ravi_quiet.wav",
            "out": "sitar_ravi_quiet_restored.wav",
            "feats": AudioFeaturesWrapper(
                AudioFeatures(
                    sample_rate=sr,
                    channels=2,
                    duration_s=duration,
                    snr_estimate_db=15.0,  # routes DFN strength 0.70 but capped to 0.50 due to classical heuristic
                    spectral_centroid_hz=1200,
                    hum_50hz_present=True,
                    hum_60hz_present=False,
                ),
                crest=18.0,
                classical=True
            )
        },
        {
            "in": "modern_pop_clean.wav",
            "out": "modern_pop_clean_restored.wav",
            "feats": AudioFeaturesWrapper(
                AudioFeatures(
                    sample_rate=sr,
                    channels=2,
                    duration_s=duration,
                    snr_estimate_db=50.0,  # clean bypass -> routes passthrough
                    spectral_centroid_hz=2400,
                    hum_50hz_present=False,
                    hum_60hz_present=False,
                )
            )
        }
    ]

    for p in profiles:
        input_path = smoke_dir / p["in"]
        output_path = smoke_dir / p["out"]

        recipe = route_features(p["feats"])
        routed_stages = [f"{s.stage_name} ({s.strength:.2f})" for s in recipe.stages]
        print(f"\nProcessing {p['in']} -> {p['out']}")
        print(f"  * Routed Recipe: {', '.join(routed_stages)}")

        cancel_event = threading.Event()
        pipeline.process_audio(
            input_path=str(input_path),
            output_path=str(output_path),
            recipe=recipe,
            cancel_event=cancel_event,
        )
        print(f"  * Restored output successfully saved to {output_path}")

    print("\n" + "=" * 80)
    print("MANUAL SMOKE TEST GENERATION AND RESTORATION COMPLETED!")
    print("=" * 80 + "\n")


if __name__ == "__main__":
    run_smoke_test_generation()
