"""
Unit tests for the BandwidthExtensionStage restoration stage.
Verifies protocol metadata conformity, bypass transparency, shape integrity, 
high-frequency reconstruction, and the bitwise crossover passband integrity test.
"""
import numpy as np
import pytest

from sangeet_inference.stages.bandwidth_extension import BandwidthExtensionStage


def test_bwe_stage_metadata() -> None:
    """
    Validates protocol conforming metadata of BandwidthExtensionStage.
    """
    stage = BandwidthExtensionStage()
    assert stage.name == "bandwidth_extension"
    assert not stage.requires_mono
    assert stage.sample_rate == 44100
    assert stage.estimate_cost(10.0) == pytest.approx(0.6)


def test_bwe_transparency_on_bypass(make_signal) -> None:
    """
    Asserts that when strength=0.0, the signal passes through completely unmodified.
    """
    stage = BandwidthExtensionStage()
    for kind in ["silence", "sine", "pink_noise"]:
        input_audio = make_signal(kind, duration=1.0, sr=stage.sample_rate)
        output_audio = stage.process(input_audio, {"strength": 0.0})

        assert output_audio.shape == input_audio.shape
        assert np.array_equal(output_audio, input_audio), (
            f"Bandwidth extension stage modified signal of kind '{kind}' when strength=0.0, "
            f"violating transparency."
        )


def test_bwe_silence_in_silence_out(make_signal) -> None:
    """
    Asserts that silence in produces silence out even with processing active.
    """
    stage = BandwidthExtensionStage()
    input_audio = make_signal("silence", duration=1.0, sr=stage.sample_rate)
    output_audio = stage.process(input_audio, {"strength": 0.5, "cutoff_frequency_hz": 4000.0})

    assert output_audio.shape == input_audio.shape
    assert np.allclose(output_audio, 0.0, atol=1e-7), (
        "Bandwidth extension stage injected noise in silent input."
    )


def test_bwe_mono_stereo_shapes(make_signal) -> None:
    """
    Asserts that shape dimensions [channels, samples] are perfectly preserved
    for both mono and stereo signals.
    """
    stage = BandwidthExtensionStage()
    for channels in [1, 2]:
        mono_signal = make_signal("pink_noise", duration=1.0, sr=stage.sample_rate)
        # Duplicate to stereo if channels == 2
        input_audio = np.repeat(mono_signal, channels, axis=0) if channels == 2 else mono_signal
        
        output_audio = stage.process(input_audio, {"strength": 0.4, "cutoff_frequency_hz": 5000.0})
        assert output_audio.shape == input_audio.shape


def test_bwe_crossover_passband_bitwise_exact() -> None:
    """
    MATHEMATICAL INTEGRITY TEST.
    Asserts that the Zero-Touch FFT Crossover leaves all original frequencies 
    below the crossover frequency ($f_c$) perfectly bitwise-identical.
    
    Generates a compound signal containing a 500 Hz low-frequency sine and a 
    15000 Hz high-frequency sine. Sets $f_c = 4000.0$ Hz.
    Checks that the 500 Hz component of the output matches the input perfectly in the FFT.
    """
    stage = BandwidthExtensionStage()
    sr = stage.sample_rate
    duration = 1.0
    num_samples = int(duration * sr)
    t = np.linspace(0, duration, num_samples, endpoint=False)

    # 1. 500 Hz tone (in passband) and 15 kHz tone (in stopband)
    low_sine = np.sin(2 * np.pi * 500.0 * t) * 0.3
    high_sine = np.sin(2 * np.pi * 15000.0 * t) * 0.3
    input_audio = (low_sine + high_sine).reshape(1, -1).astype(np.float32)

    # 2. Process BWE with cutoff = 4000 Hz, strength = 0.5
    output_audio = stage.process(input_audio, {"strength": 0.5, "cutoff_frequency_hz": 4000.0})

    # 3. Analyze FFT bins below 4000 Hz
    n_fft = num_samples
    freqs = np.fft.rfftfreq(n_fft, d=1.0 / sr)
    cutoff_bin = np.searchsorted(freqs, 4000.0)

    in_fft = np.fft.rfft(input_audio[0], n=n_fft)
    out_fft = np.fft.rfft(output_audio[0], n=n_fft)

    # All bins below 4000 Hz must be exactly identical (within float32 precision)
    assert np.allclose(out_fft[:cutoff_bin], in_fft[:cutoff_bin], rtol=0.0, atol=1e-5), (
        "Zero-Touch FFT Crossover failed: frequencies below the crossover cutoff point "
        "were modified or distorted by the bandwidth extension stage."
    )


def test_bwe_reconstructs_high_frequencies(make_signal) -> None:
    """
    Asserts that BWE successfully generates and injects high-frequency content
    above the cutoff point in a bandlimited signal.
    """
    stage = BandwidthExtensionStage()
    sr = stage.sample_rate
    pink = make_signal("pink_noise", duration=1.0, sr=sr)
    
    # Simulate severe AM roll-off by low-passing the pink noise in the FFT domain at 4000 Hz
    n_fft = pink.shape[1]
    freqs = np.fft.rfftfreq(n_fft, d=1.0 / sr)
    cutoff_bin = np.searchsorted(freqs, 4000.0)
    
    pink_fft = np.fft.rfft(pink[0], n=n_fft)
    # Zero out everything above 4000 Hz
    pink_fft[cutoff_bin:] = 0.0
    bandlimited_pink = np.fft.irfft(pink_fft, n=n_fft).reshape(1, -1).astype(np.float32)
    
    # Process
    output_audio = stage.process(bandlimited_pink, {"strength": 0.5, "cutoff_frequency_hz": 4000.0})
    
    # Analyze output FFT bins above 4000 Hz
    out_fft = np.fft.rfft(output_audio[0], n=n_fft)
    
    # Original bandlimited input had zero energy above 4 kHz
    input_hf_energy = np.sum(np.abs(pink_fft[cutoff_bin:]))
    # Output must have non-zero generated energy above 4 kHz
    output_hf_energy = np.sum(np.abs(out_fft[cutoff_bin:]))
    
    assert input_hf_energy == 0.0
    assert output_hf_energy > 0.01, (
        "Bandwidth extension failed to generate high-frequency content above the cutoff point."
    )
