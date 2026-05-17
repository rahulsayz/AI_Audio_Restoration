"""
Unit tests for audio feature extraction.
Verifies soundfile structural analysis and safety exceptions.
"""
import os
import tempfile
import numpy as np
import pytest
import soundfile as sf

from sangeet_inference.features import extract_audio_features

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
        # Verify optional fields are defaults
        assert not features.hum_50hz_present
        assert not features.hum_60hz_present
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
