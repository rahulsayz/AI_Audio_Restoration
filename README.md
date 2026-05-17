# Sangeet AI

A macOS desktop application that restores and remasters old Indian music recordings using AI.

Sangeet AI removes historical recording degradations like tape hiss, 78rpm surface noise, mains hum, and digital clipping while preserving the unique cultural and timbral characteristics of Indian music. It is designed to protect nasal playback vocal forwardness, microtonal ornamentation (meend, andolan), and classical string resonances (sitar, sarangi, tanpura) that generic Western-tuned restoration software typically strips away.

## Project Architecture

Sangeet AI is built as a native macOS application bundle containing:
1. **SwiftUI Front-End (`apps/macos/`)**: Provides the user interface, file drop area, and waveform visualization.
2. **Audio Engine (`packages/audio-engine/`)**: A Swift package using AVFoundation and Accelerate.framework for high-performance audio I/O and final mastering.
3. **Python Inference Daemon (`services/inference/`)**: An orchestrator that loads deep learning models (DeepFilterNet 3, NVSR, Demucs v4) and runs inference locally on Apple Silicon.

The front-end and daemon communicate via **gRPC** over a local Unix domain socket.

## Prerequisites

- macOS 13.0 (Ventura) or later
- Apple Silicon Mac (recommended) or Intel Mac
- Python 3.11.x
- Xcode 15.0 or later (with Swift 5.10)
- `protoc` (for gRPC stub generation)

## Getting Started

1. **Clone the repository:**
   ```bash
   git clone https://github.com/rahulchaturvedi/AI_Audio_Restoration.git
   cd AI_Audio_Restoration
   ```

2. **Generate gRPC Stubs:**
   Make sure `protoc` and Python dependencies are ready, then run:
   ```bash
   make proto
   ```

3. **Install Inference Daemon Dependencies:**
   ```bash
   cd services/inference
   python3.11 -m venv .venv
   source .venv/bin/activate
   pip install --upgrade pip
   pip install -e ".[dev]"
   ```

4. **Run Code Verification:**
   ```bash
   make lint
   make test
   ```

## Development Commands

All common tasks are automated through the root `Makefile`:
- `make proto`: Regenerate Python and Swift gRPC stubs.
- `make lint`: Run ruff, mypy, and swiftlint.
- `make format`: Auto-format Python and Swift code.
- `make test`: Run the test suites.
- `make build`: Package the Python daemon into a standalone executable.

## License

This software is distributed under a commercial End User License Agreement (EULA). See [LICENSE](LICENSE) for details.
