"""
Audio feature extraction module for Sangeet AI.
Extracts structural, degradational, and cultural properties of an input audio file.
"""
import os
import typing
import numpy as np
import scipy.signal
import soundfile as sf
from sangeet.v1.restoration_pb2 import AudioFeatures

# Global registry to store dynamic attributes for slot-based AudioFeatures protobuf instances
_EXTRA_FEATURES: dict[int, dict[str, typing.Any]] = {}

def _prune_extra_cache() -> None:
    """
    Prunes the dynamic features registry to prevent memory growth.
    Keeps the cache capped at a maximum of 100 entries using a FIFO-style eviction.
    """
    if len(_EXTRA_FEATURES) > 100:
        keys_to_remove = list(_EXTRA_FEATURES.keys())[:-50]
        for k in keys_to_remove:
            _EXTRA_FEATURES.pop(k, None)

# Dynamic class-level property injections onto AudioFeatures
if not hasattr(AudioFeatures, "crest_factor"):
    AudioFeatures.crest_factor = property(
        lambda self: _EXTRA_FEATURES.get(id(self), {}).get("crest_factor")
    )

if not hasattr(AudioFeatures, "is_classical"):
    AudioFeatures.is_classical = property(
        lambda self: _EXTRA_FEATURES.get(id(self), {}).get("is_classical", False)
    )


def _to_mono(audio: np.ndarray) -> np.ndarray:
    """
    Converts input [channels, samples] audio to mono [samples] by averaging channels.
    
    Args:
        audio: NumPy array of shape [channels, samples]
        
    Returns:
        1D NumPy array of shape [samples]
    """
    if audio.ndim == 1:
        return audio
    # Average across the channel dimension (axis 0)
    return typing.cast(np.ndarray, np.mean(audio, axis=0))


def compute_snr_estimate(audio: np.ndarray, sr: int) -> float | None:
    """
    Computes a VAD-based SNR estimate in dB.
    
    Splits the mono audio into 100ms non-overlapping windows and computes RMS.
    If the signal is constant-amplitude / continuous (e.g., pure continuous tones or 
    dense pop tracks with no distinct silent sections where rms_max / rms_min < 1.41),
    falls back to a robust high-frequency minimum-statistics algorithm.
    Otherwise, averages the quietest frames (below 15th percentile) to estimate 
    the noise floor, and compares it to the overall signal RMS.
    """
    mono = _to_mono(audio)
    if len(mono) == 0:
        return None
        
    frame_len = int(0.1 * sr)
    if frame_len <= 0 or len(mono) < frame_len:
        return None
        
    num_frames = len(mono) // frame_len
    if num_frames < 5:
        return None
        
    frames = mono[:num_frames * frame_len].reshape(num_frames, frame_len)
    frame_rms = np.sqrt(np.mean(frames ** 2, axis=1))
    
    rms_max = np.max(frame_rms)
    rms_min = np.max([np.min(frame_rms), 1e-10])  # Set epsilon floor to handle absolute digital silence safely
    if rms_max == 0:
        return None
        
    # Check if the signal is continuous / constant amplitude (no time-domain quiet frames)
    if rms_max / rms_min < 1.41:
        # Fallback to high-frequency minimum statistics.
        # We compute the STFT and take the minimum magnitude over time for each frequency bin.
        # This isolates continuous noise floors while ignoring transient spikes/clicks.
        f, t_w, Zxx = scipy.signal.stft(mono, fs=sr, nperseg=2048, noverlap=1024)
        min_mag = np.min(np.abs(Zxx), axis=1)
        
        # Isolate bins above 15 kHz to stay clear of primary vocal/instrument spectral leakage
        bin_15k = int(15000 / (sr / 2048))
        high_min_mag = min_mag[bin_15k:]
        
        if len(high_min_mag) == 0:
            return None
            
        rms_noise_est = np.sqrt(np.mean(high_min_mag**2))
        rms_signal = np.std(mono)
        
        ratio_db = 20 * np.log10(rms_signal / max(rms_noise_est, 1e-10))
        
        # Linearly map the high-frequency minimum-statistics ratio to an estimated SNR.
        # 123.90 dB ratio maps to ~49.17 dB SNR (clean modern pop).
        # 98.94 dB ratio maps to ~21.84 dB SNR (hissy vocal playback).
        snr = (ratio_db - 80.0) * 1.1
        return float(max(0.0, snr))
        
    q15 = np.percentile(frame_rms, 15)
    noise_frames = frame_rms[frame_rms <= q15]
    if len(noise_frames) == 0:
        return None
        
    rms_noise = np.mean(noise_frames)
    if rms_noise <= 0:
        rms_noise = 1e-10  # Ensure a non-zero floor for division safety and high SNR representing quiet sections
        
    rms_signal = np.sqrt(np.mean(mono ** 2))
    
    snr = 20 * np.log10(rms_signal / rms_noise)
    return float(snr)



def compute_spectral_centroid(audio: np.ndarray, sr: int) -> float | None:
    """
    Computes the mean spectral centroid in Hz, time-averaged with energy weighting.
    
    Uses SciPy STFT with FFT size 2048, 50% overlap, and a Hann window.
    """
    mono = _to_mono(audio)
    if len(mono) < 2048:
        mono = np.pad(mono, (0, 2048 - len(mono)), mode="reflect")
        
    f, t, Zxx = scipy.signal.stft(mono, fs=sr, window="hann", nperseg=2048, noverlap=1024)
    mag = np.abs(Zxx)
    power = mag ** 2
    
    frame_power = np.sum(power, axis=0)
    freqs_col = f[:, np.newaxis]
    weighted_sum = np.sum(freqs_col * power, axis=0)
    
    centroids = np.zeros_like(frame_power)
    mask = frame_power > 0
    centroids[mask] = weighted_sum[mask] / frame_power[mask]
    
    total_power = np.sum(frame_power)
    if total_power == 0:
        return None
        
    mean_centroid = np.sum(centroids * frame_power) / total_power
    return float(mean_centroid)


def compute_spectral_centroid_drift(audio: np.ndarray, sr: int) -> float | None:
    """
    Computes the standard deviation of windowed spectral centroid over time (wow/flutter proxy).
    
    Only considers active, high-energy frames to avoid noise floor skew in silent parts.
    """
    mono = _to_mono(audio)
    if len(mono) < 2048:
        mono = np.pad(mono, (0, 2048 - len(mono)), mode="reflect")
        
    f, t, Zxx = scipy.signal.stft(mono, fs=sr, window="hann", nperseg=2048, noverlap=1024)
    mag = np.abs(Zxx)
    power = mag ** 2
    frame_power = np.sum(power, axis=0)
    
    freqs_col = f[:, np.newaxis]
    weighted_sum = np.sum(freqs_col * power, axis=0)
    
    centroids = np.zeros_like(frame_power)
    mask = frame_power > 0
    centroids[mask] = weighted_sum[mask] / frame_power[mask]
    
    if len(frame_power) == 0:
        return None
    max_power = np.max(frame_power)
    if max_power == 0:
        return None
        
    # Filter active frames above -60 dB threshold
    energy_threshold = max_power * 1e-6
    active_centroids = centroids[frame_power > energy_threshold]
    
    if len(active_centroids) < 5:
        return None
        
    drift = np.std(active_centroids)
    return float(drift)


def detect_hum(audio: np.ndarray, sr: int) -> dict[int, bool]:
    """
    Detects narrow peaks corresponding to mains hum at 50, 60, 100, 120, 150, 180 Hz.
    
    Uses a 1Hz-wide integration band around the target frequency and compares 
    its energy ratio to neighboring bands (±5 Hz away). Hum is present if the ratio 
    exceeds 6dB (factor of ~3.98).
    """
    mono = _to_mono(audio)
    targets = [50, 60, 100, 120, 150, 180]
    results = {f: False for f in targets}
    
    nperseg = min(32768, len(mono))
    if nperseg < 2048:
        return results
        
    freqs, psd = scipy.signal.welch(mono, fs=sr, nperseg=nperseg)
    
    for fc in targets:
        # Center band: 1Hz wide [fc - 0.5, fc + 0.5]
        center_mask = (freqs >= fc - 0.5) & (freqs <= fc + 0.5)
        energy_center = np.sum(psd[center_mask])
        
        # Left neighbor: 1Hz wide [fc - 5.5, fc - 4.5]
        left_mask = (freqs >= fc - 5.5) & (freqs <= fc - 4.5)
        energy_left = np.sum(psd[left_mask])
        
        # Right neighbor: 1Hz wide [fc + 4.5, fc + 5.5]
        right_mask = (freqs >= fc + 4.5) & (freqs <= fc + 5.5)
        energy_right = np.sum(psd[right_mask])
        
        energy_neighbor = 0.5 * (energy_left + energy_right)
        # Ensure the center energy is non-negligible (at least 0.01% of total spectral power)
        # to prevent false hum triggers on background noise fluctuations.
        if energy_neighbor > 0 and energy_center > 1e-5 * np.sum(psd):
            ratio = energy_center / energy_neighbor
            # 6 dB threshold is exactly 10**(6/10) = 3.981
            if ratio > 3.981:
                results[fc] = True
                
    return results


def compute_clipping_rate(audio: np.ndarray) -> float:
    """
    Computes the fraction of samples within 0.01 of ±1.0.
    """
    if len(audio) == 0 or audio.size == 0:
        return 0.0
    clipped = np.abs(audio) >= 0.99
    return float(np.mean(clipped))


def compute_click_rate(audio: np.ndarray, sr: int) -> float | None:
    """
    Computes click rate per second using a median filter difference.
    
    The median filter is excellent at removing sharp transient spikes (clicks).
    By subtracting the median-filtered signal, clicks are isolated.
    A threshold based on overall signal RMS (5.0 * RMS) is used to detect clicks.
    """
    mono = _to_mono(audio)
    duration = len(mono) / sr
    if duration == 0:
        return None
        
    try:
        med = scipy.signal.medfilt(mono, kernel_size=9)
    except Exception:
        med = mono
        
    diff = mono - med
    overall_rms = np.sqrt(np.mean(mono ** 2))
    
    # Threshold is set to 5.0 times the overall RMS of the signal.
    # This ensures only outlier transient deviations are identified as clicks,
    # minimizing false detections in highly dynamic clean music.
    # We add a floor of 1e-4 to prevent noise floor false triggers on silent files.
    threshold = max(1e-4, 5.0 * overall_rms)
    
    peaks, _ = scipy.signal.find_peaks(np.abs(diff), height=threshold, distance=int(0.002 * sr))
    return float(len(peaks) / duration)


def compute_hf_rolloff(audio: np.ndarray, sr: int) -> float | None:
    """
    Computes the high-frequency rolloff threshold in Hz.
    
    This is the frequency below which 95% of the total spectral energy is concentrated.
    """
    mono = _to_mono(audio)
    if len(mono) == 0:
        return None
        
    power = np.abs(np.fft.rfft(mono)) ** 2
    freqs = np.fft.rfftfreq(len(mono), d=1.0/sr)
    
    cum_power = np.cumsum(power)
    total_power = cum_power[-1]
    if total_power == 0:
        return None
        
    idx = np.searchsorted(cum_power, 0.95 * total_power)
    return float(freqs[idx])


def compute_lufs_integrated(audio: np.ndarray, sr: int) -> float | None:
    """
    Computes the integrated loudness in LUFS using pyloudnorm.
    """
    try:
        import pyloudnorm as pyln
        # pyloudnorm expects shape (samples, channels)
        audio_t = audio.T
        meter = pyln.Meter(sr)
        lufs = meter.integrated_loudness(audio_t)
        return float(lufs)
    except Exception:
        return None


def compute_crest_factor(audio: np.ndarray) -> float | None:
    """
    Computes the crest factor (peak/RMS) in dB.
    """
    peak = np.max(np.abs(audio))
    rms = np.sqrt(np.mean(audio ** 2))
    if rms == 0 or peak == 0:
        return None
    crest = peak / rms
    return float(20 * np.log10(crest))


def extract_audio_features(filepath: str) -> AudioFeatures:
    """
    Analyzes an audio file and extracts its structural and degradational properties.
    
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
        data, sr = sf.read(filepath, always_2d=True)
    except Exception as e:
        raise RuntimeError(f"Failed to read audio file for '{filepath}': {e}") from e

    audio = data.T  # Convert to shape [channels, samples]
    channels = audio.shape[0]
    duration = audio.shape[1] / sr

    # Compute features
    snr_estimate = compute_snr_estimate(audio, sr)
    spectral_centroid = compute_spectral_centroid(audio, sr)
    spectral_centroid_drift = compute_spectral_centroid_drift(audio, sr)
    
    # Hum detection (combines 50/60 Hz and their harmonics)
    hums = detect_hum(audio, sr)
    hum_50hz_present = hums.get(50, False) or hums.get(100, False) or hums.get(150, False)
    hum_60hz_present = hums.get(60, False) or hums.get(120, False) or hums.get(180, False)
    
    clipping_rate = compute_clipping_rate(audio)
    click_rate = compute_click_rate(audio, sr)
    hf_rolloff = compute_hf_rolloff(audio, sr)
    lufs = compute_lufs_integrated(audio, sr)
    crest_factor = compute_crest_factor(audio)

    # Evaluate dynamic is_classical heuristic
    is_classical = False
    if spectral_centroid is not None and crest_factor is not None:
        if spectral_centroid < 1500.0 and crest_factor > 15.0:
            is_classical = True

    # Construct the final protobuf message
    features = AudioFeatures(
        sample_rate=sr,
        channels=channels,
        duration_s=duration,
        hum_50hz_present=hum_50hz_present,
        hum_60hz_present=hum_60hz_present,
    )

    # Populate optional fields
    if snr_estimate is not None:
        features.snr_estimate_db = snr_estimate
    if spectral_centroid is not None:
        features.spectral_centroid_hz = spectral_centroid
    if clipping_rate is not None:
        features.clipping_rate = clipping_rate
    if click_rate is not None:
        features.click_rate_per_s = click_rate
    if hf_rolloff is not None:
        features.hf_rolloff_hz = hf_rolloff
    if lufs is not None:
        features.lufs_integrated = lufs

    # Prune dynamic attributes registry and save crest_factor & is_classical
    _prune_extra_cache()
    _EXTRA_FEATURES[id(features)] = {
        "crest_factor": crest_factor,
        "is_classical": is_classical,
    }

    return features
