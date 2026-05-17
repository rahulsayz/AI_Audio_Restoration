"""
Unit tests for audio feature extraction.
Verifies soundfile structural analysis, signal safety, and exact DSP metric extraction.
"""
import os
import tempfile
import numpy as np
import pytest
import soundfile as sf

from sangeet_inference.features import (
    extract_audio_features,
    compute_snr_estimate,
    compute_spectral_centroid,
    compute_spectral_centroid_drift,
    detect_hum,
    compute_clipping_rate,
    compute_click_rate,
    compute_hf_rolloff,
    compute_lufs_integrated,
    compute_crest_factor,
)

# Use our standard make_signal fixture from conftest.py

def test_extract_features_valid_wav() -> None:
    """
    Verifies feature extraction parses standard properties correctly.
    """
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_file:
        temp_path = temp_file.name

    try:
        # Write a 2.5 second stereo silent WAV file at 44.1 kHz
        sr = 44100
        duration = 2.5
        samples = int(sr * duration)
        data = np.zeros((samples, 2), dtype=np.float32)
        sf.write(temp_path, data, sr)

        features = extract_audio_features(temp_path)
        
        assert features.sample_rate == 44100
        assert features.channels == 2
        assert features.duration_s == pytest.approx(2.5)
        # Verify optional fields are defaults/calculated correctly on silence
        assert not features.hum_50hz_present
        assert not features.hum_60hz_present
        assert getattr(features, "crest_factor", None) is None
        assert getattr(features, "is_classical", False) is False
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def test_extract_features_missing_file() -> None:
    """
    Asserts FileNotFoundError when target path is missing.
    """
    with pytest.raises(FileNotFoundError):
        extract_audio_features("/nonexistent/file/path/audio.wav")


def test_extract_features_corrupted_file() -> None:
    """
    Asserts RuntimeError when parsing invalid/garbage data.
    """
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_file:
        temp_path = temp_file.name
        temp_file.write(b"GARBAGE_HEADER_NOT_A_VALID_WAV_FILE_AT_ALL_12345")

    try:
        with pytest.raises(RuntimeError):
            extract_audio_features(temp_path)
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def test_compute_snr_estimate() -> None:
    """
    Verifies VAD-based SNR estimate for clean, noisy, and non-quiet signals.
    """
    sr = 16000
    # Clean signal: pure constant sine wave has no quiet sections, so it should return None
    t = np.linspace(0, 1.0, sr, endpoint=False)
    sine = (0.5 * np.sin(2 * np.pi * 1000.0 * t)).reshape(1, -1)
    assert compute_snr_estimate(sine, sr) is None

    # Mixed signal: 1 sec sine, 1 sec pure silence (has a very clear quiet section)
    silence = np.zeros(sr)
    mixed = np.concatenate([0.5 * np.sin(2 * np.pi * 1000.0 * t), silence]).reshape(1, -1)
    snr_clean = compute_snr_estimate(mixed, sr)
    assert snr_clean is not None
    assert snr_clean > 30.0  # High SNR on zero-noise quiet floor

    # Noisy signal: 1 sec sine, 1 sec white noise
    noise = np.random.default_rng(seed=42).standard_normal(sr) * 0.05
    mixed_noisy = np.concatenate([0.5 * np.sin(2 * np.pi * 1000.0 * t), noise]).reshape(1, -1)
    snr_noisy = compute_snr_estimate(mixed_noisy, sr)
    assert snr_noisy is not None
    assert snr_noisy < snr_clean  # SNR must degrade with added noise


def test_compute_spectral_centroid(make_signal) -> None:
    """
    Verifies mean spectral centroid calculation for standard signals.
    """
    sr = 16000
    # 1. Sine wave at 1000 Hz
    sine_1k = make_signal("sine", duration=1.5, sr=sr)
    centroid_1k = compute_spectral_centroid(sine_1k, sr)
    assert centroid_1k is not None
    assert abs(centroid_1k - 1000.0) < 50.0

    # 2. Sine wave at 3000 Hz
    t = np.linspace(0, 1.5, int(1.5 * sr), endpoint=False)
    sine_3k = (0.5 * np.sin(2 * np.pi * 3000.0 * t)).reshape(1, -1)
    centroid_3k = compute_spectral_centroid(sine_3k, sr)
    assert centroid_3k is not None
    assert abs(centroid_3k - 3000.0) < 100.0
    assert centroid_3k > centroid_1k


def test_compute_spectral_centroid_drift(make_signal) -> None:
    """
    Verifies centroid drift standard deviation (wow/flutter proxy).
    """
    sr = 16000
    # Clean steady sine: should have near-zero drift
    sine_1k = make_signal("sine", duration=1.5, sr=sr)
    drift_steady = compute_spectral_centroid_drift(sine_1k, sr)
    assert drift_steady is not None
    assert drift_steady < 5.0

    # Swept sine (chirp): high fluctuation in centroid over time
    sweep = make_signal("swept_sine", duration=1.5, sr=sr)
    drift_swept = compute_spectral_centroid_drift(sweep, sr)
    assert drift_swept is not None
    assert drift_swept > 100.0


def test_detect_hum() -> None:
    """
    Verifies hum detection at 50/60 Hz and harmonics with a 1Hz bandpass energy ratio.
    """
    sr = 8000
    duration = 2.0
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)

    # 1. Clean silence: no hum
    silence = np.zeros_like(t).reshape(1, -1)
    res_clean = detect_hum(silence, sr)
    for f in res_clean:
        assert not res_clean[f]

    # 2. Hum signal: 50 Hz mains hum and its harmonics
    # Generate sharp narrow sinusoidal hum components at 50, 100, 150 Hz
    hum = (
        0.1 * np.sin(2 * np.pi * 50.0 * t) +
        0.05 * np.sin(2 * np.pi * 100.0 * t) +
        0.02 * np.sin(2 * np.pi * 150.0 * t)
    )
    # Add a quiet noise floor to ensure stability of ratio calculations
    noise = np.random.default_rng(seed=42).standard_normal(len(t)) * 0.001
    hum_signal = (hum + noise).reshape(1, -1)

    res_hum = detect_hum(hum_signal, sr)
    assert res_hum[50] is True
    assert res_hum[100] is True
    assert res_hum[150] is True
    assert res_hum[60] is False
    assert res_hum[120] is False
    assert res_hum[180] is False


def test_compute_clipping_rate(make_signal) -> None:
    """
    Verifies calculation of clipped sample fractions.
    """
    sr = 16000
    # Clean sine peak 0.5: zero clipping
    t = np.linspace(0, 1.0, sr, endpoint=False)
    clean_sine = (0.5 * np.sin(2 * np.pi * 1000.0 * t)).reshape(1, -1)
    assert compute_clipping_rate(clean_sine) == 0.0

    # Manually clipped signal (flat-topped at 1.0)
    fully_clipped = np.ones((1, 1000))
    assert compute_clipping_rate(fully_clipped) == 1.0

    # Partially clipped signal (half flat-topped)
    partial = np.zeros((1, 1000))
    partial[0, :500] = 1.0
    assert compute_clipping_rate(partial) == 0.5


def test_compute_click_rate(make_signal) -> None:
    """
    Verifies click rate detection via median filter difference.
    """
    sr = 16000
    # Silence: zero clicks
    silence = make_signal("silence", duration=1.0, sr=sr)
    assert compute_click_rate(silence, sr) == 0.0

    # Signal with 4 sharp impulsive click transients
    t = np.linspace(0, 1.0, sr, endpoint=False)
    audio = (0.1 * np.sin(2 * np.pi * 100.0 * t)).reshape(1, -1)
    
    # Inject clicks (impulsive spikes to 1.0)
    audio[0, 2000] = 1.0
    audio[0, 5000] = -1.0
    audio[0, 8000] = 1.0
    audio[0, 11000] = -1.0

    click_rate = compute_click_rate(audio, sr)
    assert click_rate is not None
    # Click rate should be exactly 4 clicks / 1.0 second = 4.0
    assert abs(click_rate - 4.0) < 0.5


def test_compute_hf_rolloff(make_signal) -> None:
    """
    Verifies 95% high-frequency energy concentration threshold.
    """
    sr = 16000
    # 1 kHz sine wave: rolloff should be close to 1 kHz
    sine_1k = make_signal("sine", duration=1.0, sr=sr)
    rolloff = compute_hf_rolloff(sine_1k, sr)
    assert rolloff is not None
    assert rolloff < 1100.0


def test_compute_lufs_integrated(make_signal) -> None:
    """
    Verifies BS.1770 integrated loudness using pyloudnorm.
    """
    sr = 16000
    sine = make_signal("sine", duration=1.0, sr=sr)
    lufs = compute_lufs_integrated(sine, sr)
    assert lufs is not None
    # Sine wave should be in standard audible range, not infinite digital silence (-inf)
    assert -100.0 < lufs < 0.0


def test_compute_crest_factor(make_signal) -> None:
    """
    Verifies dynamic crest factor calculation (peak/RMS in dB).
    """
    sr = 16000
    # Pure sine wave has Peak/RMS ratio of sqrt(2) which is 3.01 dB
    sine = make_signal("sine", duration=1.0, sr=sr)
    cf = compute_crest_factor(sine)
    assert cf is not None
    assert abs(cf - 3.01) < 0.1


def test_dynamic_features_injection() -> None:
    """
    Verifies slot-based AudioFeatures protobuf class can successfully 
    support and resolve dynamic properties through the custom descriptor registry.
    """
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_file:
        temp_path = temp_file.name

    try:
        # Write a 1.0 second 1 kHz high-dynamic range sine sweep at 16 kHz
        sr = 16000
        t = np.linspace(0, 1.0, sr, endpoint=False)
        # Create a dynamic classical-like signal: high crest factor, low centroid
        signal = 0.5 * np.sin(2 * np.pi * 400.0 * t)
        sf.write(temp_path, signal, sr)

        features = extract_audio_features(temp_path)
        
        # Verify dynamic attributes are correctly exposed
        cf = getattr(features, "crest_factor", None)
        is_class = getattr(features, "is_classical", False)

        assert cf is not None
        assert abs(cf - 3.01) < 0.2
        # is_classical = (spectral_centroid < 1500 and crest_factor > 15 dB)
        # Centroid is around 400 Hz (< 1500), but crest factor is 3 dB (< 15 dB), so False
        assert is_class is False

    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
