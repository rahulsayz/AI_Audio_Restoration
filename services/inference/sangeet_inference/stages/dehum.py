"""
Classical DSP dehum restoration stage.
Removes mains hum at 50Hz, 60Hz and harmonics through 200Hz.
Protects the 250Hz harmonium fundamental using a strict Safe Frequency Table.
Ensures zero phase shift using forward-backward (filtfilt) filtering.
"""
from typing import Any

import numpy as np
import scipy.signal
import structlog

logger = structlog.get_logger()


def _to_mono(audio: np.ndarray) -> np.ndarray:
    """
    Converts multi-channel [channels, samples] audio to mono [samples].
    """
    if audio.ndim == 1:
        return audio
    return np.mean(audio, axis=0)


class DehumStage:
    """
    A restoration stage utilizing adaptive narrow notch filters
    to surgically eliminate active safe mains hum frequencies.
    """

    name: str = "dehum"
    requires_mono: bool = False
    sample_rate: int = 48000

    def is_applicable(self, features: Any) -> bool:
        """
        Applicable if 50Hz or 60Hz hum is detected, or if features is missing/None.
        """
        if features is None:
            return True
        hum_50 = getattr(features, "hum_50hz_present", True)
        hum_60 = getattr(features, "hum_60hz_present", True)
        return bool(hum_50 or hum_60)

    def estimate_cost(self, duration_s: float) -> float:
        """
        Notch filtering is computationally cheap, estimating 0.01x realtime.
        """
        return 0.01 * duration_s

    def _detect_active_frequencies(self, mono: np.ndarray) -> list[int]:
        """
        Dynamically scans the chunk to identify active safe hum frequencies.
        Uses a Welch PSD peak-to-neighbor ratio check on closest discrete bins.
        """
        targets = [50, 60, 100, 120, 150, 180, 200]
        active = []

        nperseg = min(32768, len(mono))
        if nperseg < 2048:
            return active

        freqs, psd = scipy.signal.welch(mono, fs=self.sample_rate, nperseg=nperseg)
        psd_sum = np.sum(psd)

        for fc in targets:
            # Find the bin index closest to the target frequency
            idx = int(np.argmin(np.abs(freqs - fc)))
            if idx <= 1 or idx >= len(freqs) - 2:
                continue

            # Sum 3 bins around the center to capture main lobe energy
            energy_center = psd[idx - 1] + psd[idx] + psd[idx + 1]

            # Find neighbor bins 5 Hz away
            idx_left = int(np.argmin(np.abs(freqs - (fc - 5.0))))
            idx_right = int(np.argmin(np.abs(freqs - (fc + 5.0))))

            if idx_left <= 0 or idx_right >= len(freqs) - 1:
                continue

            # Sum 3 bins around left and right neighbors
            energy_left = psd[idx_left - 1] + psd[idx_left] + psd[idx_left + 1]
            energy_right = psd[idx_right - 1] + psd[idx_right] + psd[idx_right + 1]

            energy_neighbor = 0.5 * (energy_left + energy_right)

            # Check ratio (10dB threshold = 10.0) and energy presence (> 0.001% of total power)
            if energy_neighbor > 0 and energy_center > 1e-5 * psd_sum:
                ratio = energy_center / energy_neighbor
                if ratio > 10.0:
                    active.append(fc)

        return active

    def process(self, chunk: np.ndarray, params: dict[str, Any]) -> np.ndarray:
        """
        Applies narrow notch filters to the chunk on active safe hum frequencies.
        """
        strength = params.get("strength", 0.5)
        if strength <= 0.0:
            return chunk

        # Map strength linearly to Q quality factor [10, 60]
        Q = float(np.clip(10.0 + strength * 50.0, 10.0, 60.0))

        # Check if frequencies were explicitly passed in params
        frequencies = params.get("frequencies", None)
        if frequencies is None:
            # Dynamically profile chunk to detect active safe frequencies
            mono = _to_mono(chunk)
            frequencies = self._detect_active_frequencies(mono)

        # Strict safe frequencies table to prevent false notches on musical content (e.g. 250Hz harmonium fundamental)
        safe_targets = {50, 60, 100, 120, 150, 180, 200}
        filtered_freqs = [f for f in frequencies if f in safe_targets]

        if not filtered_freqs:
            logger.debug("No active safe hum frequencies found to notch in chunk.")
            return chunk

        logger.info(
            "Applying zero-phase notch filters to hum frequencies",
            frequencies=filtered_freqs,
            Q=Q,
        )

        out_chunk = chunk.copy()
        for fc in filtered_freqs:
            # Normalized center frequency
            w0 = fc / (self.sample_rate / 2.0)
            b, a = scipy.signal.iirnotch(w0, Q)

            # zero-phase forward-backward filter applied channel-independently (axis=-1)
            out_chunk = scipy.signal.filtfilt(b, a, out_chunk, axis=-1)

        # Clip output to prevent out-of-bounds floating point values and ensure float32
        return np.clip(out_chunk, -1.0, 1.0).astype(np.float32)
