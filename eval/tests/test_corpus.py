import tempfile
from pathlib import Path
import pytest
import yaml
from pydantic import ValidationError

from eval.harness.corpus import (
    AudioProperties,
    SegmentMetadata,
    CorpusLoader,
    CorpusCategory,
    SourceFormat,
    LicenseStatus,
)


def test_audio_properties_validation():
    # Valid properties
    props = AudioProperties(sample_rate=48000, channels=2, duration_s=30.0)
    assert props.sample_rate == 48000
    assert props.channels == 2
    assert props.duration_s == 30.0

    # Invalid sample rate
    with pytest.raises(ValidationError) as excinfo:
        AudioProperties(sample_rate=44100, channels=2, duration_s=30.0)
    assert "Evaluation corpus audio MUST be at 48000 Hz" in str(excinfo.value)

    # Invalid channels
    with pytest.raises(ValidationError) as excinfo:
        AudioProperties(sample_rate=48000, channels=3, duration_s=30.0)
    assert "mono (1) or stereo (2)" in str(excinfo.value)

    # Invalid duration
    with pytest.raises(ValidationError) as excinfo:
        AudioProperties(sample_rate=48000, channels=2, duration_s=10.0)
    assert "duration must be approximately 30 seconds" in str(excinfo.value)


def test_segment_metadata_validation():
    # Valid metadata
    meta = SegmentMetadata(
        id="lata_1963_vocal",
        name="Lata 1963 Vocal Segment",
        category=CorpusCategory.TAPE_1950S_1960S,
        source_format=SourceFormat.MAGNETIC_TAPE,
        year=1963,
        dominant_instruments=["vocals", "harmonium"],
        known_degradations=["broadband_hiss"],
        license_status=LicenseStatus.COPYRIGHTED_INTERNAL_ONLY,
        do_not_share=True,
        audio_properties=AudioProperties(sample_rate=48000, channels=1, duration_s=30.0),
    )
    assert meta.id == "lata_1963_vocal"
    assert meta.category == CorpusCategory.TAPE_1950S_1960S
    assert meta.source_format == SourceFormat.MAGNETIC_TAPE

    # Invalid snake_case ID
    with pytest.raises(ValidationError) as excinfo:
        SegmentMetadata(
            id="lata-1963-vocal",  # hyphens not allowed
            name="Lata 1963 Vocal Segment",
            category=CorpusCategory.TAPE_1950S_1960S,
            source_format=SourceFormat.MAGNETIC_TAPE,
            license_status=LicenseStatus.COPYRIGHTED_INTERNAL_ONLY,
            audio_properties=AudioProperties(sample_rate=48000, channels=1, duration_s=30.0),
        )
    assert "Segment ID must be an alphanumeric snake_case identifier" in str(excinfo.value)


def test_loader_skip_on_missing():
    # Set up a temporary directory representing the repo root
    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir_path = Path(tmpdir)
        corpus_dir = tmpdir_path / "eval" / "corpus"
        corpus_dir.mkdir(parents=True)

        # 1. Create a mock manifest
        manifest_data = {
            "generated_at": "2026-05-17T17:16:31Z",
            "total_segments": 2,
            "categories": {
                "synthetic": 1,
                "tape_1950s_1960s": 1,
            },
            "segments": [
                {
                    "id": "synth_test_file",
                    "name": "Synthetic test file",
                    "category": "synthetic",
                    "path": "eval/corpus/synth_test_file.wav",
                    "reference_path": "eval/corpus/synth_test_file_ref.wav",
                    "is_synthetic": True,
                    "sample_rate": 48000,
                    "channels": 2,
                    "duration_s": 30.0,
                },
                {
                    "id": "proprietary_missing_file",
                    "name": "Proprietary missing file",
                    "category": "tape_1950s_1960s",
                    "path": "eval/corpus/tape_1950s_1960s/missing/source.wav",
                    "meta_path": "eval/corpus/tape_1950s_1960s/missing/meta.yaml",
                }
            ]
        }

        with open(corpus_dir / "manifest.yaml", "w", encoding="utf-8") as f:
            yaml.safe_dump(manifest_data, f)

        # Initialize Loader
        loader = CorpusLoader(repo_root=tmpdir_path)

        # Available segments should only be the synthetic one
        # (even if the WAV doesn't exist, is_synthetic/synthetic category treats it as present because run.py creates it on-demand)
        available = loader.available_segments()
        assert len(available) == 1
        assert available[0].id == "synth_test_file"

        # Skipped segments should be the proprietary missing one (since WAV doesn't exist and not synthetic)
        skipped = loader.skipped_segments()
        assert len(skipped) == 1
        assert skipped[0].id == "proprietary_missing_file"
