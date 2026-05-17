"""
Unit tests for the DeepFilterNet 3 restoration stage.
Validates processing, wet/dry strength mapping, and bounds.
"""
import numpy as np
import pytest

from sangeet_inference.stages.deep_filter_net import DeepFilterNetStage


def test_deep_filter_net_stage_metadata() -> None:
    """
    Validates stage structural metadata.
    """
    stage = DeepFilterNetStage()
    assert stage.name == "deep_filter_net"
    assert not stage.requires_mono
    assert stage.sample_rate == 48000
    assert stage.is_applicable(None)
    assert stage.estimate_cost(10.0) == pytest.approx(4.0)


def test_deep_filter_net_stage_is_applicable() -> None:
    """
    Validates stage applicability based on estimated SNR.
    """

    class MockFeatures:
        def __init__(self, snr: float | None = None, has_snr: bool = True):
            self.snr_estimate_db = snr
            self._has_snr = has_snr

        def HasField(self, name: str) -> bool:  # noqa: N802
            if name == "snr_estimate_db":
                return self._has_snr
            return False

    stage = DeepFilterNetStage()
    assert stage.is_applicable(None)
    assert stage.is_applicable(MockFeatures(snr=None, has_snr=False))
    assert stage.is_applicable(MockFeatures(snr=25.0, has_snr=True))
    assert not stage.is_applicable(MockFeatures(snr=35.0, has_snr=True))


def test_deep_filter_net_stage_silence(make_signal) -> None:
    """
    Validates that silence in produces silence out.
    """
    stage = DeepFilterNetStage()
    # DeepFilterNet expects 48kHz
    input_audio = make_signal("silence", duration=1.0, sr=48000)
    output_audio = stage.process(input_audio, {"strength": 1.0})

    assert output_audio.shape == input_audio.shape
    # Output must be close to silence (within -60 dB to be robust against numerical drift in DL)
    atol_60db = 10 ** (-60 / 20)  # ~1e-3
    assert np.allclose(output_audio, 0.0, rtol=0.0, atol=atol_60db), (
        "DeepFilterNet stage processing of silence produced audible artifacts"
    )


def test_deep_filter_net_stage_bypass(make_signal) -> None:
    """
    Validates that strength=0.0 acts as a perfect bypass (returns input bit-exactly).
    """
    stage = DeepFilterNetStage()

    for kind in ["sine", "pink_noise"]:
        input_audio = make_signal(kind, duration=1.0, sr=48000)
        output_audio = stage.process(input_audio, {"strength": 0.0})

        assert output_audio.shape == input_audio.shape
        assert np.array_equal(output_audio, input_audio), (
            f"Bypass (strength=0.0) did not return bit-exact copy for signal '{kind}'"
        )


def test_deep_filter_net_stage_stereo_support(make_signal) -> None:
    """
    Validates that the stage handles stereo input successfully and processes both channels.
    """
    stage = DeepFilterNetStage()
    mono_signal = make_signal("sine", duration=1.0, sr=48000)
    stereo_signal = np.repeat(mono_signal, 2, axis=0)

    output_audio = stage.process(stereo_signal, {"strength": 0.5})
    assert output_audio.shape == (2, stereo_signal.shape[1])


def test_deep_filter_net_stage_bounded_rms(make_signal) -> None:
    """
    Validates that the output RMS remains bounded when we specify an attenuation limit.
    An attenuation limit of 3 dB (strength=0.5, attenuation_db=6.0) caps the suppression
    so that the output RMS remains within ~3 dB (ratio >= 0.70).
    """
    stage = DeepFilterNetStage()
    input_audio = make_signal("sine", duration=2.0, sr=48000)

    # Process with 3 dB attenuation limit
    output_audio = stage.process(input_audio, {"strength": 0.5, "attenuation_db": 6.0})

    input_rms = np.sqrt(np.mean(input_audio**2))
    output_rms = np.sqrt(np.mean(output_audio**2))

    ratio = output_rms / input_rms
    # Capped at 3 dB attenuation, so ratio must be at least ~0.70 (with some numerical buffer)
    assert 0.65 <= ratio <= 1.10, (
        f"DeepFilterNet output RMS drifted outside expected limits (ratio: {ratio})"
    )
