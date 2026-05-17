"""
Pytest configuration and fixtures.
Provides the standard synthetic audio signal generator for unit and integration testing.
"""
import sys
from pathlib import Path

# Ensure sangeet_inference/proto is in sys.path so generated stubs are importable
proto_dir = Path(__file__).parent.parent / "sangeet_inference" / "proto"
if proto_dir.exists() and str(proto_dir) not in sys.path:
    sys.path.insert(0, str(proto_dir))
import numpy as np
import pytest


def make_test_signal(kind: str, duration: float, sr: int) -> np.ndarray:
    """
    Generates high-precision synthetic audio signals for Sangeet AI testing.
    
    Args:
        kind: 'silence', 'sine', 'pink_noise', 'impulse', 'swept_sine'
        duration: Length of signal in seconds.
        sr: Sampling rate in Hz.
        
    Returns:
        Float32 NumPy array of shape [1, N] representing mono audio.
    """
    num_samples = int(duration * sr)
    t = np.linspace(0, duration, num_samples, endpoint=False)

    if kind == "silence":
        return np.zeros((1, num_samples), dtype=np.float32)
        
    if kind == "sine":
        # 1 kHz reference sine wave
        y = np.sin(2 * np.pi * 1000.0 * t)
        return y.reshape(1, -1).astype(np.float32)
        
    if kind == "pink_noise":
        # Standard white noise filtered with 1/f spectral envelope
        uneven = np.random.default_rng(seed=42).standard_normal(num_samples)
        f = np.fft.rfftfreq(num_samples)
        # Avoid division by zero at DC component
        f[0] = 1.0
        scaling = 1.0 / np.sqrt(f)
        filtered = np.fft.irfft(np.fft.rfft(uneven) * scaling, n=num_samples)
        # Normalize to peak amplitude of 0.5
        max_val = np.max(np.abs(filtered))
        if max_val > 0:
            filtered = (filtered / max_val) * 0.5
        return filtered.reshape(1, -1).astype(np.float32)
        
    if kind == "impulse":
        # Single Dirac impulse centered in the window
        y = np.zeros(num_samples, dtype=np.float32)
        y[num_samples // 2] = 1.0
        return y.reshape(1, -1).astype(np.float32)
        
    if kind == "swept_sine":
        # Logarithmic chirp sweep from 20 Hz to 20 kHz
        f0, f1 = 20.0, 20000.0
        beta = np.log(f1 / f0) / duration
        y = np.sin(2 * np.pi * f0 * (np.exp(beta * t) - 1.0) / beta)
        return y.reshape(1, -1).astype(np.float32)
        
    raise ValueError(f"Unknown signal kind: {kind}")

@pytest.fixture
def make_signal():
    """
    Fixture returning the signal generator function.
    """
    return make_test_signal
