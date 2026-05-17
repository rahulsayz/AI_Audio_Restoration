"""
Unit tests for the DeclickStage restoration stage.
Verifies protocol conformity, signal transparency, click restoration,
and critical tabla transient rejection.
"""
import numpy as np
import pytest

from sangeet_inference.stages.declick import DeclickStage


def test_declick_stage_metadata() -> None:
    """
    Validates the protocol metadata structure of DeclickStage.
    """
    stage = DeclickStage()
    assert stage.name == "declick"
    assert not stage.requires_mono
    assert stage.sample_rate == 48000
    assert stage.is_applicable(None)
    assert stage.estimate_cost(10.0) == pytest.approx(0.5)


def test_declick_transparency_on_clean_signals(make_signal) -> None:
    """
    Asserts that clean signals (silence, sine wave, pink noise) pass through
    completely unmodified because no clicks are present.
    """
    stage = DeclickStage()

    # In clean signals, zero clicks should be detected or repaired.
    # The output must be bitwise identical to the input.
    for kind in ["silence", "sine", "pink_noise"]:
        input_audio = make_signal(kind, duration=1.0, sr=48000)
        output_audio = stage.process(input_audio, {"strength": 0.5})

        assert output_audio.shape == input_audio.shape
        assert np.array_equal(output_audio, input_audio), (
            f"Declick stage modified clean signal of kind '{kind}', "
            f"violating signal transparency requirements."
        )


def test_declick_restoration_effectiveness(make_signal) -> None:
    """
    Injects loud click spikes into a clean sine wave and asserts that DeclickStage
    successfully detects and repairs them using AR interpolation.
    """
    stage = DeclickStage()
    sr = 48000
    sine = make_signal("sine", duration=2.0, sr=sr) * 0.15

    # Inject three distinct impulsive click spikes
    click_indices = [5000, 30000, 75000]
    damaged_sine = sine.copy()
    for idx in click_indices:
        # A typical severe impulsive click
        damaged_sine[0, idx] = 0.95

    # Process through the declick stage with strong parameters
    restored_sine = stage.process(damaged_sine, {"strength": 0.8, "threshold_multiplier": 5.0})

    assert restored_sine.shape == sine.shape

    # Verify that the clicks were repaired and the signal is restored close to original
    for idx in click_indices:
        original_val = sine[0, idx]
        damaged_val = damaged_sine[0, idx]
        restored_val = restored_sine[0, idx]

        # The click spike (0.95) must have been removed
        assert abs(restored_val) < 0.5, f"Click at index {idx} was not attenuated (val: {restored_val})."

        # The restored sample should be close to the original sine wave sample
        error_db = 20 * np.log10(max(1e-6, abs(restored_val - original_val)))
        assert error_db < -20.0, (
            f"Click at index {idx} was not successfully restored close to the original sine wave. "
            f"Original: {original_val}, Damaged: {damaged_val}, Restored: {restored_val}."
        )


def test_declick_tabla_transient_rejection() -> None:
    """
    CRITICAL CULTURAL FIDELITY TEST.
    Simulates a sharp tabla transient ("tun" or "ta" stroke) which has a very sharp
    onset/attack followed by decaying resonant oscillations.
    Asserts that the local energy check successfully identifies this as a musical
    structure (rather than a click) and leaves the signal entirely unmodified.
    """
    stage = DeclickStage()
    sr = 48000
    duration = 0.25
    num_samples = int(duration * sr)
    t = np.linspace(0, duration, num_samples, endpoint=False)

    # 1. Simulate a sharp tabla transient: 200 Hz resonance with rapid decay
    y = np.sin(2 * np.pi * 200.0 * t)
    decay = np.exp(-t / 0.02)  # 20ms decay time constant

    # Extremely sharp linear attack over the first 0.8ms (typical drum strike)
    attack_samples = int(0.0008 * sr)
    attack = np.ones(num_samples)
    attack[:attack_samples] = np.linspace(0.0, 1.0, attack_samples)

    tabla_transient = y * decay * attack
    # Normalize peak to 0.85
    tabla_transient = (tabla_transient / np.max(np.abs(tabla_transient))) * 0.85

    input_audio = tabla_transient.reshape(1, -1).astype(np.float32)

    # 2. Process through the declick stage
    # Strength set to maximum (1.0) to make the test extremely rigorous
    output_audio = stage.process(input_audio, {"strength": 1.0, "threshold_multiplier": 5.0})

    # 3. Assert that the transient is protected and returned completely unchanged
    assert np.array_equal(output_audio, input_audio), (
        "Declick stage false-triggered on a simulated tabla transient, "
        "modifying musical content and violating cultural fidelity constraints."
    )
