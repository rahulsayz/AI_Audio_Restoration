"""
Sangeet AI Inference package.
Injects the generated proto directory into sys.path to resolve internal Protobuf imports smoothly.
"""
import os
import sys

# Compute path to sangeet_inference/proto
PROTO_DIR = os.path.join(os.path.dirname(__file__), "proto")

if PROTO_DIR not in sys.path:
    sys.path.insert(0, PROTO_DIR)
