#!/usr/bin/env python3
"""
CLI tool to analyze an audio file and print its AudioFeatures (including dynamic cultural metrics) as YAML.
"""
import os
import sys
import argparse
import yaml

# Resolve paths correctly relative to script location
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
if PROJECT_DIR not in sys.path:
    sys.path.insert(0, PROJECT_DIR)

import sangeet_inference  # Injects sangeet_inference/proto into sys.path
from sangeet_inference.features import extract_audio_features
from sangeet_inference.router import route_features

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Analyze an audio file and output its Sangeet AI AudioFeatures as YAML."
    )
    parser.add_argument(
        "file_path",
        help="Path to the audio file to analyze."
    )
    args = parser.parse_args()

    file_path = os.path.abspath(args.file_path)
    if not os.path.exists(file_path):
        print(f"Error: File not found at {file_path}", file=sys.stderr)
        sys.exit(1)

    try:
        features = extract_audio_features(file_path)
        
        # Build clean dict representation for YAML output
        features_dict = {
            "sample_rate": features.sample_rate,
            "channels": features.channels,
            "duration_s": round(float(features.duration_s), 3),
            "snr_estimate_db": round(float(features.snr_estimate_db), 2) if features.HasField("snr_estimate_db") else None,
            "spectral_centroid_hz": round(float(features.spectral_centroid_hz), 2) if features.HasField("spectral_centroid_hz") else None,
            "hum_50hz_present": bool(features.hum_50hz_present),
            "hum_60hz_present": bool(features.hum_60hz_present),
            "clipping_rate": round(float(features.clipping_rate), 4) if features.HasField("clipping_rate") else None,
            "click_rate_per_s": round(float(features.click_rate_per_s), 2) if features.HasField("click_rate_per_s") else None,
            "hf_rolloff_hz": round(float(features.hf_rolloff_hz), 2) if features.HasField("hf_rolloff_hz") else None,
            "lufs_integrated": round(float(features.lufs_integrated), 2) if features.HasField("lufs_integrated") else None,
            "crest_factor": round(float(features.crest_factor), 2) if getattr(features, "crest_factor", None) is not None else None,
            "is_classical": bool(getattr(features, "is_classical", False)),
        }
        
        # Also get router suggestion for completeness
        recipe = route_features(features)
        recipe_list = []
        for stage in recipe.stages:
            stage_dict = {
                "stage_name": stage.stage_name,
                "strength": round(float(stage.strength), 2) if stage.HasField("strength") else 1.0
            }
            recipe_list.append(stage_dict)
            
        output = {
            "audio_features": features_dict,
            "suggested_recipe": recipe_list
        }
        
        print(yaml.dump(output, default_flow_style=False, sort_keys=False))
        
    except Exception as e:
        print(f"Error during audio analysis: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
