"""
Declick restoration stage.
Removes impulsive noise (clicks, crackle) using median filter difference detection
and autoregressive (AR) spectral inpainting.
"""
from typing import Any

import numpy as np
import scipy.signal
import structlog

logger = structlog.get_logger()


class DeclickStage:
    """
    A classical DSP restoration stage that detects and repairs click and crackle artifacts.
    Uses a 3-tap median filter difference for high-precision detection, filtered by a
    local energy check to avoid false positives on musical transients (e.g. tabla strokes).
    Repairs damaged windows using autoregressive (AR) interpolation.
    """

    name: str = "declick"
    requires_mono: bool = False
    sample_rate: int = 48000

    def is_applicable(self, features: Any) -> bool:
        """
        Declick is applicable if features are missing or if click_rate_per_s > 0.0.
        """
        if features is None:
            return True
        if not hasattr(features, "click_rate_per_s") or not features.HasField(
            "click_rate_per_s"
        ):
            return True
        return float(features.click_rate_per_s) > 0.0

    def estimate_cost(self, duration_s: float) -> float:
        """
        Classical DSP is fast, estimating a low RTF cost of 0.05.
        """
        return 0.05 * duration_s

    def process(
        self, chunk: np.ndarray[Any, Any], params: dict[str, Any]
    ) -> np.ndarray[Any, Any]:
        """
        Detects and repairs clicks in a float32 chunk [channels, samples].

        Args:
            chunk: Float32 NumPy array of shape [channels, samples].
            params: Dictionary containing "strength" float [0.0, 1.0].

        Returns:
            The restored float32 NumPy array of shape [channels, samples].
        """
        strength: float = params.get("strength", 0.5)
        if strength <= 0.0:
            return chunk

        # N threshold multiplier tuned in router, defaulting to 5.0
        threshold_multiplier: float = params.get("threshold_multiplier", 5.0)

        # Lower threshold = more aggressive detection at high strength
        eff_threshold_multiplier = threshold_multiplier * (1.5 - strength)

        # Local energy transient check multiplier (default to 4.0)
        local_multiplier: float = params.get("local_multiplier", 4.0)

        out_chunk = chunk.copy()
        channels, num_samples = chunk.shape

        # Define window lengths
        window_len = int(0.003 * self.sample_rate)  # 3ms repair window (144 samples at 48k)
        half_win = window_len // 2
        local_win = int(0.020 * self.sample_rate)  # 20ms local energy window
        half_local = local_win // 2
        max_gap_len = int(0.010 * self.sample_rate)  # 10ms maximum AR gap

        for ch in range(channels):
            x = out_chunk[ch]

            # 1. 3-tap median filter
            try:
                # Kernel size must be an odd integer
                med = scipy.signal.medfilt(x, kernel_size=3)
            except Exception as e:
                logger.error("Failed to compute median filter in declick", error=str(e))
                continue

            diff = x - med
            rms_global = float(np.sqrt(np.mean(x**2)))

            # Global threshold with a small floor to prevent triggers in complete silence
            global_threshold = max(1e-4, eff_threshold_multiplier * rms_global)

            # Candidate click indices (global check)
            candidate_indices = np.where(np.abs(diff) > global_threshold)[0]
            if len(candidate_indices) == 0:
                continue

            # Filter candidate indices with the high-precision local energy check
            click_indices = []
            for idx in candidate_indices:
                # Extract surrounding local window, bounded by signal edges
                local_start = max(0, idx - half_local)
                local_end = min(num_samples, idx + half_local)

                # Exclude the 3ms click center from the local RMS computation
                click_start = max(0, idx - half_win)
                click_end = min(num_samples, idx + half_win)

                # Build slices of samples outside the click center but inside local window
                left_slice = x[local_start:click_start]
                right_slice = x[click_end:local_end]
                x_local = np.concatenate((left_slice, right_slice))

                if len(x_local) > 0:
                    rms_local = float(np.sqrt(np.mean(x_local**2)))
                else:
                    rms_local = 0.0

                peak_diff = float(np.abs(diff[idx]))

                # High-precision transient rejection test
                if rms_local > 0.0:
                    if peak_diff > local_multiplier * rms_local:
                        click_indices.append(idx)
                else:
                    # If local region is completely silent but we have a peak, it's a click
                    click_indices.append(idx)

            if not click_indices:
                continue

            # Group clicks into contiguous/overlapping repair intervals
            intervals: list[tuple[int, int]] = []
            for idx in click_indices:
                a = max(0, idx - half_win)
                b = min(num_samples, idx + half_win)

                if not intervals:
                    intervals.append((a, b))
                else:
                    prev_a, prev_b = intervals[-1]
                    if a <= prev_b:
                        # Merge overlapping or adjacent intervals
                        intervals[-1] = (prev_a, max(prev_b, b))
                    else:
                        intervals.append((a, b))

            # Repair each interval
            for a, b in intervals:
                M = b - a
                if M <= 0:
                    continue

                # If the gap is too large, fall back to simple linear interpolation
                # to prevent unstable AR solver behaviors
                if M > max_gap_len:
                    t_missing = np.arange(M)
                    x_left = float(x[a - 1]) if a > 0 else 0.0
                    x_right = float(x[b]) if b < num_samples else 0.0
                    x[a:b] = x_left + (x_right - x_left) * (t_missing + 1) / (M + 1)
                    continue

                # Retrieve surrounding clean samples for AR training (3 * window size)
                L_pad = max(3 * M, 100)
                x_past = x[max(0, a - L_pad) : a]
                x_future = x[b : min(num_samples, b + L_pad)]
                z = np.concatenate((x_past, x_future))

                # Estimate AR coefficients (p = 10)
                p = 10
                a_coeffs = self._estimate_ar_coefficients(z, p)

                # Run autoregressive interpolation
                x[a:b] = self._ar_interpolate(x, a, b, a_coeffs, p)

        # Clip back to [-1.0, 1.0] range to prevent any clipping artifacts
        return np.clip(out_chunk, -1.0, 1.0, dtype=np.float32)

    def _estimate_ar_coefficients(self, z: np.ndarray[Any, Any], p: int) -> np.ndarray[Any, Any]:
        """
        Estimates AR coefficients [a_1, ..., a_p] from clean signal z using least squares.
        """
        L = len(z)
        if L <= p:
            return np.zeros(p, dtype=np.float32)

        X = np.zeros((L - p, p), dtype=np.float32)
        for i in range(p):
            X[:, i] = z[p - 1 - i : L - 1 - i]

        y = -z[p:]

        try:
            a, _, _, _ = np.linalg.lstsq(X, y, rcond=None)
            return a.astype(np.float32)
        except np.linalg.LinAlgError:
            return np.zeros(p, dtype=np.float32)

    def _ar_interpolate(
        self, x: np.ndarray[Any, Any], a: int, b: int, a_coeffs: np.ndarray[Any, Any], p: int
    ) -> np.ndarray[Any, Any]:
        """
        Interpolates the range [a, b) in signal x using estimated AR coefficients.
        """
        M = b - a
        a_all = np.concatenate(([1.0], a_coeffs))

        H = np.zeros((M + p, M), dtype=np.float32)
        c = np.zeros(M + p, dtype=np.float32)

        for i in range(M + p):
            for j in range(p + 1):
                idx = a + i - j
                # Check bounds
                if idx < 0 or idx >= len(x):
                    continue
                if a <= idx < b:
                    k = idx - a
                    H[i, k] += a_all[j]
                else:
                    c[i] += a_all[j] * x[idx]

        try:
            x_missing = np.linalg.solve(H.T @ H, -H.T @ c)
            return x_missing.astype(np.float32)
        except np.linalg.LinAlgError:
            # Fallback to linear interpolation in case of singular matrices
            t_missing = np.arange(M)
            x_left = float(x[a - 1]) if a > 0 else 0.0
            x_right = float(x[b]) if b < len(x) else 0.0
            return x_left + (x_right - x_left) * (t_missing + 1) / (M + 1)
