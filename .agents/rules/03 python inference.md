---
trigger: always_on
---

---
name: python-inference
description: Rules for the Python inference daemon, ML pipeline, and restoration stages
activation: globs
globs: ["services/inference/**/*.py", "services/inference/pyproject.toml", "eval/**/*.py"]
---

# Python Inference Daemon Rules

Applies to all Python code in `services/inference/` and `eval/`.

## Language and runtime

- Python 3.11 only. Do not introduce 3.12+ syntax. Pinning matters for PyInstaller reproducibility.
- Type hints on every public function and method signature. Internal helpers can omit them if obvious.
- `mypy --strict` passes on `services/inference/sangeet_inference/`. Pre-commit hook enforces this.
- `ruff` for lint, `black` for format. Line length 100. No exceptions for "readability" — black wins.

## Project layout discipline

- `sangeet_inference/daemon.py` — gRPC server, process lifecycle only. No DSP, no ML.
- `sangeet_inference/router.py` — intelligence router. Pure function from features to recipe. No I/O.
- `sangeet_inference/pipeline.py` — orchestration. Coordinates stages, manages chunking and crossfade on the Python side when needed.
- `sangeet_inference/stages/` — one file per restoration stage. Each stage implements the `RestorationStage` protocol.
- `sangeet_inference/mastering/` — server-side mastering DSP (used as fallback; primary mastering is Swift-side).
- `sangeet_inference/proto/` — generated gRPC stubs. **Never edit by hand.** Regenerate from `proto/` with `make proto`.

## The RestorationStage protocol

Every restoration stage implements this exact interface (defined in `sangeet_inference/stages/base.py`):

```python
class RestorationStage(Protocol):
    name: str                                       # stable identifier, snake_case
    requires_mono: bool                             # does the model accept stereo?
    sample_rate: int                                # required SR in Hz; pipeline resamples

    def is_applicable(self, features: AudioFeatures) -> bool: ...
    def estimate_cost(self, duration_s: float) -> float: ...   # seconds on M2 baseline
    def process(self, chunk: np.ndarray, params: dict) -> np.ndarray: ...
```

- Stages must be stateless across calls. Model weights live in the stage instance; per-call state is forbidden.
- `process` is called once per chunk. The pipeline handles chunking, overlap, and reassembly.
- Stages must accept and return `np.float32` in the range `[-1.0, 1.0]`. Clipping is the stage's responsibility.
- Stages must not write to disk inside `process`. Logging via the stage's logger is fine.

## Model loading

- Models load once at daemon startup, in a background thread, with progress reported via gRPC `Status` stream.
- Model weights live in `~/Library/Application Support/SangeetAI/models/`. Downloaded on first use, not bundled in the app.
- Each model has a manifest JSON: name, version, SHA-256, license, download URL. The manifest is bundled in the app; weights are downloaded.
- Verify SHA-256 after download. A mismatch is a hard error, not a warning.

## GPU and acceleration

- The daemon detects MPS (Apple Silicon Metal) at startup and uses it where supported.
- Fall back to CPU silently for stages where MPS is broken (some PyTorch ops have MPS gaps). Log the fallback as `info`.
- Never use CUDA paths. Strip CUDA-dependent code from upstream model integrations.
- For Phase 3 Core ML conversion, the converted models live in `sangeet_inference/stages/coreml/` and are loaded via `coremltools`.

## Memory discipline

- The daemon's resident set should stay under 4 GB during steady-state. Models that exceed this are loaded on demand and unloaded after use.
- Use `torch.no_grad()` for all inference. `eval()` mode on every model after load.
- Free tensors explicitly when processing chunks larger than 30 seconds. Python's GC is not enough on Apple Silicon.
- No `np.copy()` or `torch.clone()` unless you have a concrete reason. Document why.

## Audio I/O in Python

- `soundfile` (libsndfile) for reading and writing inside the daemon. Not `librosa.load` (uses audioread, slow).
- `torchaudio` for in-pipeline operations that need autograd or GPU. Otherwise NumPy + Accelerate via SciPy.
- Default to float32 throughout. Convert to int16/int24 only at the export boundary, and only when explicitly requested.
- Sample rate handling: the pipeline standardizes to 48 kHz internally. Stages declare their required SR; the pipeline resamples around them.

## The intelligence router

- The router is a pure function. Inputs: an `AudioFeatures` dataclass. Outputs: a `RestorationRecipe` dataclass.
- No model inference, no I/O. Features are pre-computed and passed in.
- V1 router is rule-based — explicit thresholds and decision logic in code, not loaded from config. This makes it debuggable.
- V2 router (Phase 2) may use a small sklearn classifier loaded from a pickle. The interface does not change.
- Decision logic is unit-tested with synthetic feature vectors covering all branches.

## gRPC server

- One server, one socket, no TLS (Unix domain socket — kernel does the auth).
- Streaming RPCs for restoration progress. Unary RPCs for everything else.
- Request size limit: 50 MB. Larger payloads are passed by file path (the Swift side writes to a temp file, the daemon reads it).
- Graceful shutdown on `SIGTERM`. Finish in-flight RPCs up to 30 seconds, then force exit.
- Health check endpoint returns daemon version, loaded models, and current memory usage.

## Logging

- `structlog` configured to write JSON to stderr. The Swift parent process captures and surfaces relevant lines.
- Three levels (matches `01-coding-standards.md`): `debug`, `info`, `error`.
- Every log line includes `request_id` for restoration-related logs. Generate via `uuid4` at RPC entry.
- Never log audio data, even partial. Log shapes, durations, and SR. Never sample values.

## Testing

- `pytest` with `pytest-asyncio` for the gRPC server tests.
- Stage tests use synthetic signals: a function `make_test_signal(kind, duration, sr)` in `tests/fixtures/`. Kinds: `silence`, `sine`, `pink_noise`, `impulse`, `swept_sine`.
- Restoration stage tests assert *bounded behavior*: output RMS within 2 dB of input, no clipping, expected SR. They do not assert exact sample values — ML stages are not bit-exact.
- The full eval harness on real music is separate from unit tests — it lives in `eval/` and runs in CI as a slow job.

## Packaging

- PyInstaller `--onedir` build. `--onefile` is rejected (slow startup, harder to debug).
- The build produces `dist/sangeet-inference/` which is copied into the macOS app's `Resources/`.
- `pyproject.toml` lists exact pinned versions for every transitive dependency. We use `uv` or `pip-tools` to lock.
- The build is reproducible: same inputs produce byte-identical outputs. Verify with two builds in CI.

## What we do not do

- We do not use `librosa` for production code paths. Acceptable in eval harness scripts only.
- We do not use `multiprocessing` inside the daemon. We have a single inference process; concurrency is handled by gRPC's thread pool.
- We do not use `requests` or any network library inside the inference daemon. The daemon never makes outbound connections.
- We do not write to user directories outside `~/Library/Application Support/SangeetAI/` and explicitly-passed file paths.
- We do not call `print()`. Use the logger.