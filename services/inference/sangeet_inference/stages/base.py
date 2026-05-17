"""
Restoration stage abstract contract.
Declares the protocol defining interfaces and requirements for all audio DSP/ML stages.
"""
from typing import Any, Protocol, runtime_checkable

import numpy as np


@runtime_checkable
class RestorationStage(Protocol):
    """
    Protocol enforcing structural correctness on all Sangeet AI restoration stages.
    Enforces statelessness across process invocations.
    """
    name: str
    requires_mono: bool
    sample_rate: int  # Standard sampling rate expected by processing (e.g. 48000)

    def is_applicable(self, features: Any) -> bool:
        """
        Evaluates extracted degradation features to see if this stage is needed.
        
        Args:
            features: AudioFeatures protobuf message.
        """
        ...

    def estimate_cost(self, duration_s: float) -> float:
        """
        Calculates the estimated processing cost (in seconds) on an Apple M2 baseline system.
        
        Args:
            duration_s: Audio length in seconds.
        """
        ...

    def process(self, chunk: np.ndarray[Any, Any], params: dict[str, Any]) -> np.ndarray[Any, Any]:
        """
        Executes core DSP/ML algorithms on a float32 NumPy array of shape [channels, samples].
        Must return a float32 NumPy array of shape [channels, samples] scaled to [-1.0, 1.0].
        
        Args:
            chunk: Numpy array [channels, samples] containing audio samples.
            params: Dictionary of parameters mapping options to floats/ints.
        """
        ...
