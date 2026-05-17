"""
Audio feature extraction module for Sangeet AI.
Extracts structural and cultural properties of an input audio file.
"""
import os
import soundfile as sf
from sangeet.v1.restoration_pb2 import AudioFeatures

def extract_audio_features(filepath: str) -> AudioFeatures:
    """
    Analyzes an audio file and extracts its structural properties.
    
    Args:
        filepath: Absolute path to target audio file.
        
    Returns:
        An AudioFeatures protobuf object with metadata populated.
        
    Raises:
        FileNotFoundError: If the file does not exist.
        RuntimeError: If libsndfile fails to parse the file or its metadata.
    """
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"Audio file not found at path: {filepath}")

    try:
        info = sf.info(filepath)
    except Exception as e:
        raise RuntimeError(f"Failed to read audio file metadata for '{filepath}': {e}") from e

    return AudioFeatures(
        sample_rate=info.samplerate,
        channels=info.channels,
        duration_s=info.duration,
        # The remaining indicators are stubbed out for Phase 1
        snr_estimate_db=None,
        spectral_centroid_hz=None,
        hum_50hz_present=False,
        hum_60hz_present=False,
        clipping_rate=None,
        click_rate_per_s=None,
        hf_rolloff_hz=None,
        lufs_integrated=None,
    )
