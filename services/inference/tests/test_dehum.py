"""
Unit tests for the DehumStage restoration stage.
Verifies protocol conformity, clean signal transparency,
50/150Hz hum attenuation, and the critical protection of the harmonium fundamental.
"""
import numpy as np
import pytest

from sangeet_inference.stages.dehum import DehumStage


def test_dehum_stage_metadata() -> None:
    """
    Validates the protocol metadata structure of DehumStage.
    """
    stage = DehumStage()
    assert stage.name == "dehum"
    assert not stage.requires_mono
    assert stage.sample_rate == 48000
    assert stage.is_applicable(None)
    assert stage.estimate_cost(10.0) == pytest.approx(0.1)


def test_dehum_transparency_on_clean_signals(make_signal) -> None:
    """
    Asserts that clean signals (silence, sine wave, pink noise) pass through
    completely unmodified because no hum is present.
    """
    stage = DehumStage()

    for kind in ["silence", "sine", "pink_noise"]:
        input_audio = make_signal(kind, duration=1.0, sr=48000)
        output_audio = stage.process(input_audio, {"strength": 0.5})

        assert output_audio.shape == input_audio.shape
        assert np.array_equal(output_audio, input_audio), (
            f"Dehum stage modified clean signal of kind '{kind}', "
            f"violating signal transparency requirements."
        )


def test_dehum_attenuation_effectiveness() -> None:
    """
    Injects loud mains hum (50Hz fundamental + 150Hz harmonic) and asserts
    that DehumStage successfully detects, notches, and attenuates the hum
    by at least 25 dB.
    """
    stage = DehumStage()
    sr = 48000
    duration = 12.0
    num_samples = int(duration * sr)
    t = np.linspace(0, duration, num_samples, endpoint=False)

    # 1. Generate a hum mixture: 50 Hz fundamental and 150 Hz harmonic
    hum_50 = np.sin(2 * np.pi * 50.0 * t)
    hum_150 = 0.5 * np.sin(2 * np.pi * 150.0 * t)
    raw_signal = hum_50 + hum_150

    # 2. Apply a 100ms fade-in/fade-out to eliminate startup/shutdown transients
    fade_len = int(0.1 * sr)
    window = np.ones(num_samples, dtype=np.float32)
    window[:fade_len] = np.sin((np.pi / 2.0) * (np.arange(fade_len) / fade_len))
    window[-fade_len:] = np.cos((np.pi / 2.0) * (np.arange(fade_len) / fade_len))

    input_audio = (raw_signal * window).reshape(1, -1).astype(np.float32)
    input_rms = np.sqrt(np.mean(input_audio**2))

    # 3. Process through dehum with default parameters (strength = 0.5)
    output_audio = stage.process(input_audio, {"strength": 0.5})
    output_rms = np.sqrt(np.mean(output_audio**2))

    assert output_audio.shape == input_audio.shape

    # 4. Assert attenuation of at least 25 dB
    attenuation_db = 20 * np.log10(input_rms / max(1e-10, output_rms))
    assert attenuation_db > 25.0, (
        f"Dehum stage failed to sufficiently attenuate hum. "
        f"Input RMS: {input_rms:.4f}, Output RMS: {output_rms:.4f}, "
        f"Attenuation: {attenuation_db:.2f} dB (expected > 25 dB)."
    )


def test_dehum_harmonium_protection() -> None:
    """
    CRITICAL CULTURAL FIDELITY TEST.
    Simulates a 250 Hz tone, which represents the standard harmonium fundamental frequency.
    Asserts that the Safe Frequency Table prevents this frequency from being notched,
    meaning the signal is returned completely unmodified and untouched.
    """
    stage = DehumStage()
    sr = 48000
    duration = 1.0
    num_samples = int(duration * sr)
    t = np.linspace(0, duration, num_samples, endpoint=False)

    # 1. Create pure 250 Hz tone
    input_audio = np.sin(2 * np.pi * 250.0 * t).reshape(1, -1).astype(np.float32)

    # 2. Process with extreme strength (1.0) to ensure maximum selectivity verification
    output_audio = stage.process(input_audio, {"strength": 1.0})

    # 3. Assert that the harmonium fundamental is left completely untouched
    assert np.array_equal(output_audio, input_audio), (
        "Dehum stage notched or altered a 250 Hz tone representing the harmonium fundamental, "
        "violating strict safe frequency constraints."
    )
