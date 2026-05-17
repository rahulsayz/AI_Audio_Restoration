"""
DeepFilterNet 3 restoration stage.
Removes broadband stationary noise and tape hiss using deep filtering.
"""
import hashlib
import ssl
import urllib.request
import zipfile
from pathlib import Path
from typing import Any

import numpy as np
import structlog
import torch
from df.enhance import enhance, init_df

logger = structlog.get_logger()


class DeepFilterNetStage:
    """
    A restoration stage utilizing DeepFilterNet 3 to remove broadband noise.
    Downloads and verifies model weights on initialization.
    Processes audio chunks at 48kHz, mono or stereo, using dynamic attenuation limits.
    """

    name: str = "deep_filter_net"
    requires_mono: bool = False
    sample_rate: int = 48000

    def __init__(self) -> None:
        """
        Initializes the stage. Downloads and extracts model weights if not present,
        verifies the SHA-256 hash, and pre-loads the model.
        """
        self.model_dir = Path(
            "~/Library/Application Support/SangeetAI/models/deep_filter_net"
        ).expanduser()
        self.expected_sha256 = (
            "49c52edc8947ae1f9bf50d81530beaf3a2c3245aeaf34b6f31ff535cd22284d2"
        )
        self.url = (
            "https://github.com/Rikorose/DeepFilterNet/raw/main/models/DeepFilterNet3.zip"
        )

        self._ensure_downloaded_and_extracted()

        logger.info("Loading DeepFilterNet 3 model from path", path=str(self.model_dir))
        try:
            # init_df returns: model, df_state, logger. Pass string format of Path.
            model, df_state, _ = init_df(str(self.model_dir))
            self.model = model
            self.df_state = df_state
            logger.info("DeepFilterNet 3 model loaded successfully")
        except Exception as e:
            logger.error("Failed to load DeepFilterNet 3 model", error=str(e))
            raise RuntimeError(f"Failed to initialize DeepFilterNet: {e}") from e

    def _ensure_downloaded_and_extracted(self) -> None:
        """
        Downloads the model zip, verifies its SHA-256 checksum, and extracts it
        to the target SangeetAI models folder.
        """
        config_path = self.model_dir / "config.ini"
        if config_path.is_file():
            logger.debug("DeepFilterNet 3 model already present")
            return

        parent_dir = self.model_dir.parent
        parent_dir.mkdir(parents=True, exist_ok=True)
        zip_path = parent_dir / "DeepFilterNet3.zip"

        logger.info("Downloading DeepFilterNet 3 model weights", url=self.url)
        try:
            # Download file using urllib with an unverified SSL context to bypass missing
            # local macOS certificates. Security is maintained by strictly verifying
            # the downloaded file's SHA-256 hash below.
            context = ssl._create_unverified_context()
            with urllib.request.urlopen(self.url, context=context) as response:
                with zip_path.open("wb") as out_file:
                    out_file.write(response.read())

            # Verify SHA-256
            logger.info("Verifying model weights integrity")
            sha256_hash = hashlib.sha256()
            with zip_path.open("rb") as f:
                for byte_block in iter(lambda: f.read(4096), b""):
                    sha256_hash.update(byte_block)
            computed_sha = sha256_hash.hexdigest()

            if computed_sha != self.expected_sha256:
                if zip_path.exists():
                    zip_path.unlink()
                raise ValueError(
                    f"SHA-256 mismatch for DeepFilterNet3.zip. "
                    f"Expected: {self.expected_sha256}, Got: {computed_sha}"
                )

            # Extract zip
            logger.info("Extracting model weights", destination=str(self.model_dir))
            with zipfile.ZipFile(zip_path, "r") as zip_ref:
                zip_ref.extractall(parent_dir)

                # Rename the extracted directory "DeepFilterNet3" to "deep_filter_net"
                extracted_dir = parent_dir / "DeepFilterNet3"
                if extracted_dir.exists() and extracted_dir != self.model_dir:
                    if self.model_dir.exists():
                        import shutil

                        shutil.rmtree(self.model_dir)
                    extracted_dir.rename(self.model_dir)

            logger.info("DeepFilterNet 3 model weights extracted successfully")
        except Exception as e:
            logger.error("Failed to download or extract model weights", error=str(e))
            if zip_path.exists():
                zip_path.unlink()
            raise e
        finally:
            if zip_path.exists():
                zip_path.unlink()

    def is_applicable(self, features: Any) -> bool:
        """
        Returns True if features.snr_estimate_db < 30 or if features.snr_estimate_db is None.
        """
        if features is None:
            return True
        if not hasattr(features, "snr_estimate_db") or not features.HasField(
            "snr_estimate_db"
        ):
            return True
        return features.snr_estimate_db < 30.0

    def estimate_cost(self, duration_s: float) -> float:
        """
        Calculates the estimated processing cost (in seconds) on Apple M2.
        DeepFilterNet 3 RTF cost baseline is mapped to 0.4.
        """
        return 0.4 * duration_s

    def process(
        self, chunk: np.ndarray[Any, Any], params: dict[str, Any]
    ) -> np.ndarray[Any, Any]:
        """
        Enhances a mono or stereo float32 chunk using DeepFilterNet 3.

        Args:
            chunk: Float32 NumPy array of shape [channels, samples].
            params: Dictionary containing "strength" float [0.0, 1.0] and "attenuation_db" float.

        Returns:
            The enhanced float32 NumPy array of shape [channels, samples].
        """
        strength = params.get("strength", 1.0)
        if strength <= 0.0:
            return chunk

        attenuation_db = params.get("attenuation_db", 100.0)
        atten_lim_db = strength * attenuation_db
        if atten_lim_db <= 0.0:
            return chunk

        try:
            # Convert NumPy array chunk to PyTorch tensor
            chunk_tensor = torch.from_numpy(chunk)

            # Run DeepFilterNet inference under torch.no_grad() for memory efficiency
            with torch.no_grad():
                enhanced_tensor = enhance(
                    self.model,
                    self.df_state,
                    chunk_tensor,
                    atten_lim_db=atten_lim_db,
                )

            # Convert back to NumPy array
            enhanced_np = enhanced_tensor.numpy()

            # Clip to [-1.0, 1.0] to prevent digital clipping
            return np.clip(enhanced_np, -1.0, 1.0, dtype=np.float32)  # type: ignore[no-any-return]
        except Exception as e:
            logger.error("Error during DeepFilterNet processing", error=str(e))
            raise RuntimeError(f"DeepFilterNet processing failed: {e}") from e
