#!/bin/bash
# Builds the standalone Python inference daemon binary via PyInstaller
set -e

# Resolve absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFERENCE_DIR="${WORKSPACE_DIR}/services/inference"

echo "=================================================="
echo "Starting Sangeet AI Daemon Compilation"
echo "Workspace:  $WORKSPACE_DIR"
echo "Inference:  $INFERENCE_DIR"
echo "=================================================="

# Check if CONFIGURATION env var is provided by Xcode, default to Debug
CONFIG="${CONFIGURATION:-Debug}"
echo "Build Configuration: $CONFIG"

# Change directory to services/inference
cd "${INFERENCE_DIR}"

# 1. Determine if a rebuild is necessary
NEEDS_BUILD=false
BINARY_PATH="dist/sangeet-inference/sangeet-inference"

if [ ! -f "${BINARY_PATH}" ]; then
    echo "Compiled binary not found. Triggering fresh compile..."
    NEEDS_BUILD=true
elif [ "$CONFIG" = "Release" ]; then
    echo "Release configuration detected. Triggering forced recompilation..."
    NEEDS_BUILD=true
else
    # Check if pyproject.toml is newer than the binary
    if [ "pyproject.toml" -nt "${BINARY_PATH}" ]; then
        echo "pyproject.toml modified since last build. Recompiling..."
        NEEDS_BUILD=true
    # Check if any python file in sangeet_inference is newer than the binary
    elif [ -n "$(find sangeet_inference -name "*.py" -newer "${BINARY_PATH}" 2>/dev/null)" ]; then
        echo "Python source files modified since last build. Recompiling..."
        NEEDS_BUILD=true
    fi
fi

# 2. Run PyInstaller if required
if [ "$NEEDS_BUILD" = true ]; then
    echo "Running PyInstaller compilation..."
    
    # Clean old build/dist files to prevent cache pollution
    rm -rf build dist
    
    # Run PyInstaller with optimized settings for Apple Silicon/macOS
    # Exclude heavy CUDA modules to save bundle size
    # Collect soundfile binaries and PyTorch metadata as per requirements
    PYINSTALLER_DEBUG=1 ./.venv/bin/pyinstaller \
        --onedir \
        --name sangeet-inference \
        --clean \
        --paths sangeet_inference/proto \
        --exclude-module torch.cuda \
        --exclude-module caffe2 \
        --exclude-module triton \
        --exclude-module tensorboard \
        --exclude-module torchvision \
        --exclude-module torchaudio.lib.libtorchaudio_cuda \
        --collect-all torch \
        --collect-all sangeet \
        --collect-all df \
        --collect-all deepfilternet \
        --collect-binaries soundfile \
        --copy-metadata torch \
        --copy-metadata torchaudio \
        --hidden-import torch \
        --hidden-import torchaudio \
        --hidden-import soundfile \
        --hidden-import structlog \
        --hidden-import grpcio \
        --hidden-import numpy \
        --hidden-import scipy \
        --hidden-import deepfilternet \
        --hidden-import pyloudnorm \
        --hidden-import ssr_eval \
        --hidden-import sangeet \
        --hidden-import sangeet.v1 \
        --hidden-import sangeet.v1.restoration_pb2 \
        --hidden-import sangeet.v1.restoration_pb2_grpc \
        --hidden-import df \
        --hidden-import df.deepfilternet3 \
        --hidden-import df.enhance \
        --hidden-import df.model \
        --hidden-import df.io \
        sangeet_inference/daemon.py

    echo "PyInstaller compilation completed successfully."
else
    echo "Lazy Compile: Daemon binary is up to date. Skipping PyInstaller execution."
fi

# 3. Codesign the compiled daemon folder
# Uses active target's EXPANDED_CODE_SIGN_IDENTITY from Xcode, fallback to ad-hoc ("-")
SIGN_ID="${EXPANDED_CODE_SIGN_IDENTITY:--}"
echo "Signing compiled daemon directory..."
"${SCRIPT_DIR}/codesign.sh" "dist/sangeet-inference" "${SIGN_ID}"

# 4. Copy build artifacts to the Built Products app bundle if running inside Xcode build context
if [ -n "${BUILT_PRODUCTS_DIR}" ] && [ -n "${PRODUCT_NAME}" ]; then
    TARGET_RESOURCES_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources"
    echo "Xcode context detected. Embedding daemon into app bundle..."
    echo "Target Resources: $TARGET_RESOURCES_DIR"

    mkdir -p "${TARGET_RESOURCES_DIR}"

    # Remove previous copy to ensure clean overwrite
    rm -f "${TARGET_RESOURCES_DIR}/sangeet-inference"
    rm -rf "${TARGET_RESOURCES_DIR}/_internal"

    # Copy the executable file directly to Resources/sangeet-inference
    cp "dist/sangeet-inference/sangeet-inference" "${TARGET_RESOURCES_DIR}/sangeet-inference"
    # Copy the entire internal dependencies directory to Resources/_internal
    cp -R "dist/sangeet-inference/_internal" "${TARGET_RESOURCES_DIR}/_internal"

    # Verify and sign inside the final app bundle to satisfy Gatekeeper
    echo "Signing embedded binaries in final app bundle..."
    "${SCRIPT_DIR}/codesign.sh" "${TARGET_RESOURCES_DIR}/sangeet-inference" "${SIGN_ID}"
    "${SCRIPT_DIR}/codesign.sh" "${TARGET_RESOURCES_DIR}/_internal" "${SIGN_ID}"
    
    echo "Daemon embedded and signed successfully."
else
    echo "Local manual run (no Xcode context). Standalone binary is available at:"
    echo "  ${INFERENCE_DIR}/dist/sangeet-inference/sangeet-inference"
fi

echo "=================================================="
echo "Sangeet AI Daemon Build Process Complete!"
echo "=================================================="
