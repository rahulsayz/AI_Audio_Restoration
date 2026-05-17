from enum import Enum
from pathlib import Path
from typing import List, Optional, Dict, Any
import yaml
from pydantic import BaseModel, Field, field_validator

# 1. Categories and Formats based on the testing-and-eval / cultural-fidelity rules
class CorpusCategory(str, Enum):
    SHELLAC_78RPM = "shellac_78rpm"
    TAPE_1950S_1960S = "tape_1950s_1960s"
    ORCHESTRAL_1970S_1980S = "orchestral_1970s_1980s"
    CLASSICAL_VOCAL = "classical_vocal"
    CLASSICAL_INSTRUMENTAL = "classical_instrumental"
    REGIONAL_FOLK = "regional_folk"
    DIFFICULT_CASES = "difficult_cases"
    SYNTHETIC = "synthetic"  # Retained for backwards compatibility with synthetic tests


class SourceFormat(str, Enum):
    SHELLAC = "shellac"
    MAGNETIC_TAPE = "magnetic_tape"
    VINYL = "vinyl"
    DIGITAL = "digital"
    SYNTHETIC = "synthetic"


class LicenseStatus(str, Enum):
    PUBLIC_DOMAIN = "public_domain"
    CREATIVE_COMMONS = "creative_commons"
    COPYRIGHTED_INTERNAL_ONLY = "copyrighted_internal_only"
    PROPRIETARY = "proprietary"


# 2. Schema Models
class AudioProperties(BaseModel):
    sample_rate: int = Field(48000, description="Sample rate in Hz (must be 48000)")
    channels: int = Field(..., description="Number of channels (1=mono, 2=stereo)")
    duration_s: float = Field(30.0, description="Duration of segment in seconds")

    @field_validator("sample_rate")
    @classmethod
    def validate_sample_rate(cls, v: int) -> int:
        if v != 48000:
            raise ValueError("Evaluation corpus audio MUST be at 48000 Hz sample rate")
        return v

    @field_validator("channels")
    @classmethod
    def validate_channels(cls, v: int) -> int:
        if v not in (1, 2):
            raise ValueError("Audio must be mono (1) or stereo (2)")
        return v

    @field_validator("duration_s")
    @classmethod
    def validate_duration_s(cls, v: float) -> float:
        if not (20.0 <= v <= 40.0):  # Allow some wiggle room for synthetic/real limits
            raise ValueError("Audio duration must be approximately 30 seconds (20.0s - 40.0s)")
        return v


class MetricsBaseline(BaseModel):
    snr_estimate_db: Optional[float] = None
    spectral_centroid_hz: Optional[float] = None
    crest_factor: Optional[float] = None


class SegmentMetadata(BaseModel):
    id: str = Field(..., description="Unique alphanumeric identifier (snake_case)")
    name: str = Field(..., description="Human-readable segment name")
    category: CorpusCategory = Field(..., description="One of the standard categories")
    source_format: SourceFormat = Field(..., description="Original recording medium")
    year: Optional[int] = Field(None, description="Approximate year of recording")
    dominant_instruments: List[str] = Field(default_factory=list, description="Primary instruments")
    known_degradations: List[str] = Field(default_factory=list, description="Degradations present")
    license_status: LicenseStatus = Field(..., description="Licensing information")
    do_not_share: bool = Field(default=False, description="Flag for private distribution")
    audio_properties: AudioProperties = Field(..., description="Audio sample properties")
    metrics_baseline: Optional[MetricsBaseline] = Field(
        default_factory=MetricsBaseline, description="Estimated baseline metrics"
    )

    @field_validator("id")
    @classmethod
    def validate_id(cls, v: str) -> str:
        if not v.replace("_", "").isalnum():
            raise ValueError("Segment ID must be an alphanumeric snake_case identifier")
        return v


# 3. Registry Manifest Model
class ManifestSegmentEntry(BaseModel):
    id: str
    name: Optional[str] = None
    category: CorpusCategory = Field(default=CorpusCategory.SYNTHETIC)
    path: str
    reference_path: Optional[str] = None
    meta_path: Optional[str] = None

    # Fields for backwards compatibility with flat manifest structures
    is_synthetic: Optional[bool] = None
    sample_rate: Optional[int] = None
    channels: Optional[int] = None
    duration_s: Optional[float] = None
    snr_estimate_db: Optional[float] = None
    spectral_centroid_hz: Optional[float] = None
    crest_factor: Optional[float] = None
    is_classical: Optional[bool] = None


class Manifest(BaseModel):
    segments: List[ManifestSegmentEntry]


# 4. Corpus Loader Implementation
class CorpusLoader:
    """
    Manages loading the evaluation corpus from manifest.yaml and category directories.
    Handles skip-on-missing logic for gitignored audio files.
    """

    def __init__(self, repo_root: Optional[Path] = None):
        if repo_root is None:
            # Resolve repo root relative to this file
            self.repo_root = Path(__file__).resolve().parent.parent.parent
        else:
            self.repo_root = Path(repo_root)

        self.corpus_dir = self.repo_root / "eval" / "corpus"
        self.manifest_path = self.corpus_dir / "manifest.yaml"
        self._manifest: Optional[Manifest] = None
        self._loaded_segments: Dict[str, SegmentMetadata] = {}
        self._missing_segments: List[ManifestSegmentEntry] = []

    @property
    def manifest(self) -> Manifest:
        if self._manifest is None:
            self.load_manifest()
        assert self._manifest is not None
        return self._manifest

    def load_manifest(self) -> None:
        if not self.manifest_path.exists():
            raise FileNotFoundError(f"Manifest not found at {self.manifest_path}")

        with open(self.manifest_path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)

        # Parse the raw manifest YAML into Pydantic
        self._manifest = Manifest(segments=data.get("segments", []))
        self._loaded_segments.clear()
        self._missing_segments.clear()

        # Load metadata and check file existence
        for entry in self._manifest.segments:
            source_wav = self.repo_root / entry.path

            # Skip-on-missing mechanism:
            # If the audio file is missing (not synced from S3 or gitignored),
            # we track it as missing and skip loading its meta.yaml.
            # However, for synthetic test signals, run.py creates them on-demand.
            # So if is_synthetic is true and the file is missing, we do NOT skip it,
            # because run.py will generate it in the next step.
            is_synth = entry.is_synthetic or (entry.category == CorpusCategory.SYNTHETIC)
            if not source_wav.exists() and not is_synth:
                self._missing_segments.append(entry)
                continue

            # Load the metadata
            if entry.meta_path:
                meta_yaml_path = self.repo_root / entry.meta_path
                if not meta_yaml_path.exists():
                    raise FileNotFoundError(
                        f"Metadata file missing for segment {entry.id} at {meta_yaml_path}"
                    )

                with open(meta_yaml_path, "r", encoding="utf-8") as f:
                    meta_data = yaml.safe_load(f)

                try:
                    segment_meta = SegmentMetadata(**meta_data)
                    self._loaded_segments[entry.id] = segment_meta
                except Exception as e:
                    raise ValueError(
                        f"Metadata validation failed for segment {entry.id} in {meta_yaml_path}: {e}"
                    )
            else:
                # Backwards-compatibility fallback: Construct segment metadata dynamically
                # from the manifest entry fields if it has no separate meta.yaml.
                try:
                    sr = entry.sample_rate or 48000
                    ch = entry.channels or 2
                    dur = entry.duration_s or 30.0
                    source_fmt = SourceFormat.SYNTHETIC if is_synth else SourceFormat.DIGITAL
                    lic = LicenseStatus.PUBLIC_DOMAIN if is_synth else LicenseStatus.PROPRIETARY
                    
                    segment_meta = SegmentMetadata(
                        id=entry.id,
                        name=entry.name or entry.id,
                        category=entry.category,
                        source_format=source_fmt,
                        year=None,
                        dominant_instruments=["synthesizer"] if is_synth else [],
                        known_degradations=[],
                        license_status=lic,
                        do_not_share=False,
                        audio_properties=AudioProperties(
                            sample_rate=sr,
                            channels=ch,
                            duration_s=dur
                        ),
                        metrics_baseline=MetricsBaseline(
                            snr_estimate_db=entry.snr_estimate_db,
                            spectral_centroid_hz=entry.spectral_centroid_hz,
                            crest_factor=entry.crest_factor
                        )
                    )
                    self._loaded_segments[entry.id] = segment_meta
                except Exception as e:
                    raise ValueError(
                        f"Fallback validation failed for flat manifest entry {entry.id}: {e}"
                    )

    def all_entries(self) -> List[ManifestSegmentEntry]:
        """Returns all entries listed in manifest.yaml, whether locally available or not."""
        if self._manifest is None:
            self.load_manifest()
        return self.manifest.segments

    def available_segments(self) -> List[SegmentMetadata]:
        """Returns metadata of all segments whose audio files exist locally (or are synthetic)."""
        if self._manifest is None:
            self.load_manifest()
        return list(self._loaded_segments.values())

    def skipped_segments(self) -> List[ManifestSegmentEntry]:
        """Returns manifest entries of segments missing their local source audio."""
        if self._manifest is None:
            self.load_manifest()
        return self._missing_segments

    def get_segment(self, segment_id: str) -> Optional[SegmentMetadata]:
        """Retrieves metadata for a specific available segment."""
        if self._manifest is None:
            self.load_manifest()
        return self._loaded_segments.get(segment_id)

    def get_paths(self, segment_id: str) -> Optional[Dict[str, Path]]:
        """Gets local absolute paths for source, reference, and metadata files of a segment."""
        if self._manifest is None:
            self.load_manifest()

        for entry in self.manifest.segments:
            if entry.id == segment_id:
                return {
                    "source": self.repo_root / entry.path,
                    "reference": self.repo_root / entry.reference_path if entry.reference_path else None,
                    "meta": self.repo_root / entry.meta_path if entry.meta_path else None,
                }
        return None
