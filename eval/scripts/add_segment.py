#!/usr/bin/env python3
"""
Sangeet AI - Evaluation Corpus Segment Ingestor CLI.
Interactive tool to add a new audio segment to the evaluation harness.
"""

import os
import shutil
import sys
import time
from pathlib import Path
from typing import List, Optional

import numpy as np
import soundfile as sf
import yaml

# Add repository root to python search path
repo_root = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(repo_root))

from eval.harness.corpus import (
    CorpusLoader,
    SegmentMetadata,
    CorpusCategory,
    SourceFormat,
    LicenseStatus,
    AudioProperties,
    MetricsBaseline,
)


def print_header(title: str) -> None:
    print("\n" + "=" * 60)
    print(f" {title.upper()} ".center(60, "="))
    print("=" * 60)


def prompt_choice(label: str, choices: list) -> str:
    print(f"\nSelect {label}:")
    for idx, choice in enumerate(choices):
        print(f"  [{idx + 1}] {choice}")
    while True:
        try:
            val = input(f"Enter choice [1-{len(choices)}]: ").strip()
            num = int(val)
            if 1 <= num <= len(choices):
                return choices[num - 1]
        except ValueError:
            pass
        print(f"Invalid input. Please choose a number between 1 and {len(choices)}.")


def prompt_string(label: str, required: bool = True, default: str = "") -> str:
    prompt_text = f"\nEnter {label}"
    if default:
        prompt_text += f" [Default: {default}]"
    prompt_text += ": "

    while True:
        val = input(prompt_text).strip()
        if not val and default:
            return default
        if not val and required:
            print(f"{label} is required.")
            continue
        return val


def prompt_bool(label: str, default: bool = False) -> bool:
    default_str = "Y/n" if default else "y/N"
    val = input(f"\n{label} ({default_str}): ").strip().lower()
    if not val:
        return default
    return val.startswith("y")


def prompt_int(label: str, required: bool = False) -> Optional[int]:
    while True:
        val = input(f"\nEnter {label} (optional, press Enter to skip): ").strip()
        if not val:
            if required:
                print(f"{label} is required.")
                continue
            return None
        try:
            return int(val)
        except ValueError:
            print("Please enter a valid integer.")


def prompt_file_path(label: str, required: bool = True) -> Optional[Path]:
    while True:
        val = input(f"\nEnter path to {label} file: ").strip()
        if not val:
            if required:
                print(f"{label} file is required.")
                continue
            return None
        path = Path(val).resolve()
        if path.exists() and path.is_file():
            return path
        print(f"File not found at: {path}. Please verify the path.")


def compute_spectral_centroid(signal: np.ndarray, sr: int) -> float:
    # Average channels if stereo
    if len(signal.shape) > 1:
        signal = np.mean(signal, axis=1)

    n = len(signal)
    frequencies = np.fft.rfftfreq(n, 1.0 / sr)
    magnitude = np.abs(np.fft.rfft(signal))
    centroid = np.sum(frequencies * magnitude) / (np.sum(magnitude) + 1e-8)
    return float(centroid)


def compute_crest_factor(signal: np.ndarray) -> float:
    peak = np.max(np.abs(signal))
    rms = np.sqrt(np.mean(signal**2) + 1e-8)
    return float(peak / rms)


def compute_snr_estimate(signal: np.ndarray) -> float:
    # A basic RMS power-ratio estimation for SNR (signal relative to quietest 1-second block)
    if len(signal.shape) > 1:
        signal = np.mean(signal, axis=1)

    sr = 48000  # standardised
    total_len = len(signal)
    block_size = sr  # 1 second
    
    # Calculate RMS in 1-second chunks
    rms_values = []
    for start in range(0, total_len, block_size):
        block = signal[start : start + block_size]
        if len(block) < block_size // 2:
            continue
        rms_values.append(np.sqrt(np.mean(block**2) + 1e-8))
    
    if not rms_values:
        return 20.0
        
    rms_values = sorted(rms_values)
    noise_rms = rms_values[0]  # quietest block
    signal_rms = rms_values[-1]  # loudest block
    
    snr = 20.0 * np.log10(signal_rms / noise_rms)
    return float(max(min(snr, 50.0), 3.0))


def main() -> None:
    print_header("Sangeet AI - Add Corpus Segment")
    print("This CLI tool will guide you through registering a new audio segment")
    print("into Sangeet's quality evaluation harness.")

    # 1. Prompt interactive metadata
    segment_id = prompt_string("Segment ID (snake_case, e.g. rafi_1957_chaudhvin)")
    # Basic snake_case validation
    if not segment_id.replace("_", "").isalnum():
        print("Error: Segment ID must be alphanumeric snake_case.")
        sys.exit(1)

    name = prompt_string("Human-readable Segment Name (e.g. Chaudhvin Ka Chand Title)")

    category_choices = [cat.value for cat in CorpusCategory if cat != CorpusCategory.SYNTHETIC]
    # Allow synthetic for convenience if requested
    category_choices.append(CorpusCategory.SYNTHETIC.value)
    category_str = prompt_choice("Corpus Category", category_choices)
    category = CorpusCategory(category_str)

    format_choices = [fmt.value for fmt in SourceFormat]
    format_str = prompt_choice("Source Format", format_choices)
    source_format = SourceFormat(format_str)

    year = prompt_int("Approximate Recording Year")

    instruments_str = prompt_string("Dominant Instruments (comma-separated, e.g., vocals, tabla, sitar)", required=False)
    dominant_instruments = [i.strip().lower() for i in instruments_str.split(",") if i.strip()]

    degradations_str = prompt_string("Known Degradations (comma-separated, e.g., hiss, crackle, clipping)", required=False)
    known_degradations = [d.strip().lower() for d in degradations_str.split(",") if d.strip()]

    license_choices = [lic.value for lic in LicenseStatus]
    license_str = prompt_choice("License Status", license_choices)
    license_status = LicenseStatus(license_str)

    do_not_share = prompt_bool("Do Not Share publicly (sensitive / copyrighted)", default=True)

    # 2. Get and validate audio files
    source_file_path = prompt_file_path("source (degraded) audio")
    reference_file_path = prompt_file_path("reference (clean / remastered) audio", required=False)

    print("\nReading audio properties...")
    try:
        source_data, source_sr = sf.read(source_file_path)
    except Exception as e:
        print(f"Error reading source audio file: {e}")
        sys.exit(1)

    # Audio property validation
    if source_sr != 48000:
        print(f"WARNING: Segment sample rate is {source_sr} Hz. The pipeline standardizes on 48000 Hz.")
        resample_ok = prompt_bool("Would you like to resample this file to 48000 Hz automatically?", default=True)
        if not resample_ok:
            print("Ingestion cancelled. Ingested files must be at 48000 Hz.")
            sys.exit(1)
        
        # Simple linear/numpy resampling for the CLI helper
        import scipy.signal as sig
        print("Resampling source file to 48000 Hz...")
        num_samples = int(len(source_data) * 48000 / source_sr)
        source_data = sig.resample(source_data, num_samples)
        source_sr = 48000

    channels = 1 if len(source_data.shape) == 1 else source_data.shape[1]
    duration_s = float(len(source_data) / source_sr)

    print(f"  * Sample Rate: {source_sr} Hz")
    print(f"  * Channels: {channels}")
    print(f"  * Duration: {duration_s:.3f} seconds")

    if not (20.0 <= duration_s <= 40.0):
        print(f"WARNING: Duration is {duration_s:.1f}s. Standard segments should be ~30 seconds (20s - 40s).")
        proceed_ok = prompt_bool("Do you want to proceed anyway?", default=False)
        if not proceed_ok:
            print("Ingestion cancelled.")
            sys.exit(1)

    # Reference file checks if provided
    ref_data = None
    if reference_file_path:
        try:
            ref_data, ref_sr = sf.read(reference_file_path)
            if ref_sr != 48000:
                print(f"Resampling reference file from {ref_sr} to 48000 Hz...")
                import scipy.signal as sig
                num_samples = int(len(ref_data) * 48000 / ref_sr)
                ref_data = sig.resample(ref_data, num_samples)
        except Exception as e:
            print(f"Error reading reference audio file: {e}")
            sys.exit(1)

    # Compute baseline metrics
    print("\nComputing baseline metrics (RMS, Spectral Centroid, Crest Factor)...")
    centroid = compute_spectral_centroid(source_data, source_sr)
    crest = compute_crest_factor(source_data)
    snr = compute_snr_estimate(source_data)

    print(f"  * Estimated SNR: {snr:.2f} dB")
    print(f"  * Spectral Centroid: {centroid:.1f} Hz")
    print(f"  * Crest Factor: {crest:.2f}")

    # Build Pydantic model
    audio_properties = AudioProperties(
        sample_rate=source_sr,
        channels=channels,
        duration_s=round(duration_s, 3)
    )

    metrics_baseline = MetricsBaseline(
        snr_estimate_db=round(snr, 1),
        spectral_centroid_hz=round(centroid, 1),
        crest_factor=round(crest, 2)
    )

    meta = SegmentMetadata(
        id=segment_id,
        name=name,
        category=category,
        source_format=source_format,
        year=year,
        dominant_instruments=dominant_instruments,
        known_degradations=known_degradations,
        license_status=license_status,
        do_not_share=do_not_share,
        audio_properties=audio_properties,
        metrics_baseline=metrics_baseline
    )

    # 3. Create folders and copy files
    # Subdirectory structure: eval/corpus/<category>/<segment-id>/
    target_dir = repo_root / "eval" / "corpus" / category.value / segment_id
    target_dir.mkdir(parents=True, exist_ok=True)

    dest_source_path = target_dir / "source.wav"
    dest_ref_path = target_dir / "reference.wav" if reference_file_path else None
    dest_meta_path = target_dir / "meta.yaml"

    print(f"\nWriting files to target directory: {target_dir.relative_to(repo_root)}...")
    sf.write(dest_source_path, source_data, source_sr)
    if dest_ref_path and ref_data is not None:
        sf.write(dest_ref_path, ref_data, source_sr)

    # Save meta.yaml using pyyaml via Pydantic model export
    # Convert Pydantic model to dictionary
    meta_dict = meta.model_dump()
    with open(dest_meta_path, "w", encoding="utf-8") as f:
        yaml.safe_dump(meta_dict, f, sort_keys=False, allow_unicode=True)
    print("  * Wrote meta.yaml successfully.")

    # 4. Update manifest.yaml registry
    manifest_path = repo_root / "eval" / "corpus" / "manifest.yaml"
    print(f"Registering segment in master manifest: {manifest_path.relative_to(repo_root)}...")

    loader = CorpusLoader(repo_root=repo_root)
    # Check if segment already exists in manifest
    manifest_entries = loader.all_entries()
    
    # We will build a new list of entries, replacing existing one if ID matches
    new_entries = []
    found_existing = False
    for entry in manifest_entries:
        if entry.id == segment_id:
            found_existing = True
            # Overwrite with fresh paths
            new_entry = {
                "id": segment_id,
                "category": category.value,
                "path": str(dest_source_path.relative_to(repo_root)),
                "reference_path": str(dest_ref_path.relative_to(repo_root)) if dest_ref_path else None,
                "meta_path": str(dest_meta_path.relative_to(repo_root))
            }
            new_entries.append(new_entry)
        else:
            # Keep as dict for simple serialization
            new_entries.append(entry.model_dump())

    if not found_existing:
        new_entry = {
            "id": segment_id,
            "category": category.value,
            "path": str(dest_source_path.relative_to(repo_root)),
            "reference_path": str(dest_ref_path.relative_to(repo_root)) if dest_ref_path else None,
            "meta_path": str(dest_meta_path.relative_to(repo_root))
        }
        new_entries.append(new_entry)

    # Sort manifest segments by category then ID to keep it tidy
    new_entries = sorted(new_entries, key=lambda x: (x.get("category", ""), x.get("id", "")))

    # Save manifest.yaml
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest_data = yaml.safe_load(f) or {}

    manifest_data["segments"] = new_entries
    manifest_data["generated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    manifest_data["total_segments"] = len(new_entries)

    # Calculate categories count
    cat_counts = {}
    for entry in new_entries:
        cat = entry.get("category", "synthetic")
        cat_counts[cat] = cat_counts.get(cat, 0) + 1
    manifest_data["categories"] = cat_counts

    with open(manifest_path, "w", encoding="utf-8") as f:
        yaml.safe_dump(manifest_data, f, sort_keys=False)
    print("  * Registered segment in manifest.yaml successfully.")

    # 5. Success summary and instructions
    print_header("Ingestion Completed Successfully")
    print(f"Segment ID   : {segment_id}")
    print(f"Segment Name : {name}")
    print(f"Category     : {category.value}")
    print(f"Private?     : {'Yes (Gitignored)' if do_not_share else 'No (Public)'}")
    print(f"Audio Path   : {dest_source_path.relative_to(repo_root)}")
    if dest_ref_path:
        print(f"Ref Audio    : {dest_ref_path.relative_to(repo_root)}")

    if do_not_share:
        print("\n" + ">" * 60)
        print("  NOTE: Since this segment is marked 'do_not_share', its WAV")
        print("  files are gitignored. To share them with other developers")
        print("  or CI runners, upload them to the private S3 bucket:")
        print(f"  aws s3 cp {dest_source_path.relative_to(repo_root)} s3://sangeet-eval-corpus/{category.value}/{segment_id}/source.wav")
        if dest_ref_path:
            print(f"  aws s3 cp {dest_ref_path.relative_to(repo_root)} s3://sangeet-eval-corpus/{category.value}/{segment_id}/reference.wav")
        print(">" * 60 + "\n")


if __name__ == "__main__":
    main()
