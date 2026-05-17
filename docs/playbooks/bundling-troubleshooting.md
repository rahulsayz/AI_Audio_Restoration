# Bundling and Packaging Troubleshooting Playbook — Sangeet AI

This playbook documents the design constraints, solved runtime issues, and packaging configurations for compilation and codesigning of Sangeet AI's Python inference daemon as a standalone executable embedded inside the macOS application bundle.

---

## 1. Resolved Packaging Architecture Surprises

### 1.1 macOS Codesigning & Team ID Mismatch (`dlopen` mapping validation)
* **Symptom:** Running the compiled standalone binary returned a Gatekeeper crash:
  ```
  Failed to load Python shared library: dlopen(...): ... not valid for use in process:
  mapping process and mapped file (non-platform) have different Team IDs
  ```
* **Cause:** By default, local developers use the ad-hoc (`-`) signature identity. However, when signing using `--options runtime` (Hardened Runtime), macOS enforces strict Team ID matching. Because local ad-hoc binaries have no Team ID, strict library validation fails.
* **Resolution:** In [codesign.sh](file:///Users/rahulchaturvedi/AI_Audio_Restoration/scripts/codesign.sh), we implemented a conditional check. If the signature identity is ad-hoc (`-`), we sign the binaries without the `--options runtime` flag. When using a real Developer ID/Team identity for production/notarization, we apply `--options runtime` and `--timestamp`. This provides developer speed locally and maximum security compliance for release builds.

### 1.2 Missing Dynamically Loaded Modules (`df.deepfilternet3`)
* **Symptom:** Frozen daemon threw an unhandled runtime error:
  ```
  ModuleNotFoundError: No module named 'df.deepfilternet3'
  ```
* **Cause:** DeepFilterNet dynamically imports its model class at runtime via `importlib.import_module(f"df.{model_name}")` where `model_name` is `"deepfilternet3"`. Because this is resolved at runtime, PyInstaller's static analyzer missed it entirely and skipped packaging it.
* **Resolution:** In [build-daemon.sh](file:///Users/rahulchaturvedi/AI_Audio_Restoration/scripts/build-daemon.sh), we added `--collect-all df` and `--collect-all deepfilternet`, along with explicit hidden import declarations for:
  * `df`
  * `df.deepfilternet3`
  * `df.enhance`
  * `df.model`
  * `df.io`

### 1.3 Missing Dynamic Proto Modules (`sangeet.v1`)
* **Symptom:** Frozen daemon threw:
  ```
  ModuleNotFoundError: No module named 'sangeet'
  ```
* **Cause:** The gRPC generated stubs are located under `sangeet_inference/proto/sangeet/v1` and imported via `from sangeet.v1 import ...`. Since this path is dynamically appended to `sys.path` in `daemon.py` at runtime, PyInstaller did not search it during analysis.
* **Resolution:** In [build-daemon.sh](file:///Users/rahulchaturvedi/AI_Audio_Restoration/scripts/build-daemon.sh), we added `--paths sangeet_inference/proto` to PyInstaller's import paths list, forced package collection via `--collect-all sangeet`, and added `--hidden-import sangeet` to guarantee it compiles into the PYZ/frozen binary package.

---

## 2. Size & Performance Optimizations

### 2.1 CUDA Exclusions
To optimize the bundle footprint from the expected `1-2 GB` down to a sleek **700 MB**, we explicitly excluded massive, redundant CUDA/tensorboard components in `build-daemon.sh`:
* `--exclude-module torch.cuda`
* `--exclude-module caffe2`
* `--exclude-module triton`
* `--exclude-module tensorboard`
* `--exclude-module torchvision`
* `--exclude-module torchaudio.lib.libtorchaudio_cuda`

### 2.2 Lazy Compilation Check
To avoid introducing compilation latencies to Swift developers, we implemented an optimized timestamp checker in `build-daemon.sh`. It skips PyInstaller invocation entirely and immediately links from local caches if source Python files under `sangeet_inference/` are older than the existing compiled binary.

---

## 3. Playbook Checklist for Verification

When modifying imports or updating model architectures:
1. Run local standalone binary verification:
   ```bash
   ./services/inference/dist/sangeet-inference/sangeet-inference --help
   ```
2. Check that the UDS socket file is correctly unlinked and bound:
   ```bash
   ls -la "~/Library/Application Support/SangeetAI/inference.sock"
   ```
3. Verify that the inner bundle Resources contain:
   * `Contents/Resources/sangeet-inference` (Executable)
   * `Contents/Resources/_internal` (Shared library directory)
