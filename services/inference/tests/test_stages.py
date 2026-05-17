"""
Unit tests for restoration stages.
Validates the PassthroughStage against the exact mathematical bounds.
"""
import numpy as np
import pytest

from sangeet_inference.stages.passthrough import PassthroughStage

def test_passthrough_stage_metadata() -> None:
    """
    Validates general structural metadata of PassthroughStage.
    """
    stage = PassthroughStage()
    assert stage.name == "passthrough"
    assert not stage.requires_mono
    assert stage.sample_rate == 48000
    assert stage.is_applicable(None)
    assert stage.estimate_cost(10.0) == pytest.approx(0.01)

def test_passthrough_stage_signal_integrity(make_signal) -> None:
    """
    Validates that PassthroughStage returns output matching input within -90 dB.
    Uses np.allclose with rtol=0 and atol=10**(-90/20).
    """
    stage = PassthroughStage()
    atol_90db = 10 ** (-90 / 20)  # ~3.162e-5

    # Test all synthetic signal types
    for kind in ["silence", "sine", "pink_noise", "impulse", "swept_sine"]:
        input_audio = make_signal(kind, duration=2.0, sr=48000)
        output_audio = stage.process(input_audio, {})
        
        # Verify shape integrity
        assert output_audio.shape == input_audio.shape
        
        # Verify within -90 dB tolerance bounds
        assert np.allclose(output_audio, input_audio, rtol=0.0, atol=atol_90db), \
            f"Passthrough stage output exceeded -90 dB discrepancy limit for signal kind '{kind}'"
        
        # For passthrough, it must actually be bitwise identical (error is 0.0)
        assert np.array_equal(output_audio, input_audio), \
            f"Passthrough did not return bit-exact copy for signal kind '{kind}'"
