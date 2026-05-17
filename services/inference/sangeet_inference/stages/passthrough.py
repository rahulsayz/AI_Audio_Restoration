"""
Passthrough restoration stage.
Returns the input audio unmodified, providing a transparent baseline for testing.
"""
from typing import Dict, Any
import numpy as np

class PassthroughStage:
    """
    A transparent restoration stage.
    Preserves signal exactness, returning input completely unchanged.
    """
    name: str = "passthrough"
    requires_mono: bool = False
    sample_rate: int = 48000

    def is_applicable(self, features: Any) -> bool:
        """
        Always applicable for V1 as a baseline fallback.
        """
        return True

    def estimate_cost(self, duration_s: float) -> float:
        """
        Passthrough is virtually free, estimating near-zero latency.
        """
        return 0.001 * duration_s

    def process(self, chunk: np.ndarray, params: Dict[str, Any]) -> np.ndarray:
        """
        Returns the input chunk unchanged.
        
        Args:
            chunk: Float32 NumPy array of shape [channels, samples].
            params: Optional stage parameters.
            
        Returns:
            The exact same NumPy array chunk.
        """
        return chunk
