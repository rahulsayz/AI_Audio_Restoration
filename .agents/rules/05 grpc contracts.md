---
trigger: always_on
---

---
name: grpc-contracts
description: Rules for gRPC proto definitions and the contract between Swift and Python
activation: globs
globs: ["proto/**/*.proto", "**/proto/**/*.py", "**/proto/**/*.swift"]
---

# gRPC Contract Rules

The gRPC contract is the boundary between Swift and Python. It is the *only* coupling between them. Get this right and we can swap the inference daemon for Core ML in Phase 3 without touching the front-end.

## Source of truth

- The `.proto` files in `/proto` are the single source of truth.
- Generated stubs (`*_pb2.py`, `*_pb2_grpc.py`, Swift generated files) are committed to the repo for reproducibility but **never edited by hand**.
- Regenerate with `make proto`. This runs `protoc` for both languages and updates both sides atomically.
- CI verifies that generated stubs match what `make proto` produces. A mismatch fails the build.

## Versioning

- Proto package: `sangeet.v1`, `sangeet.v2`, etc.
- Breaking changes require a new version namespace. We do not break `v1` once it ships.
- Additive changes (new fields with new tag numbers, new RPCs, new enum values) within a major version are fine.
- Never reuse a tag number. Never renumber existing tags. Never change the type of an existing field.
- Mark deprecated fields with `[deprecated = true]` rather than removing them.

## Schema style

- Field names: `snake_case`. Generated Swift converts to `camelCase` automatically.
- Message names: `PascalCase`. Service names: `PascalCase` ending in `Service` (e.g., `RestorationService`).
- RPCs: verb-first, `PascalCase` (e.g., `StartRestoration`, `GetProgress`, `CancelJob`).
- Use `oneof` for mutually exclusive fields rather than overloading semantics across multiple optional fields.
- Use proto3 `optional` for fields where "not set" is distinct from "default value". Important for restoration parameters where 0.0 is a valid strength.

## Message size and streaming

- Hard limit on request and response size: **50 MB**. Larger payloads pass file paths, not bytes.
- Audio file content is never sent over RPC. Always pass a file path that both sides can read.
- Long-running operations use server-streaming RPCs for progress updates, not polling.
- Status updates flow at most 10 per second. More frequent updates are a UI bug, not a backend feature.

## Error semantics

- Use gRPC status codes correctly:
  - `INVALID_ARGUMENT` — client sent malformed request (bad file path, invalid parameters)
  - `NOT_FOUND` — referenced job ID or file does not exist
  - `FAILED_PRECONDITION` — daemon not ready (model still loading, license not accepted)
  - `RESOURCE_EXHAUSTED` — out of memory, disk full
  - `UNAVAILABLE` — daemon shutting down, retry possible
  - `INTERNAL` — bug; should be reported with a request ID
- Error messages are user-facing-quality. The Swift side may pass them through to the UI verbatim.
- Every error includes a `request_id` in `Status.details` for log correlation.

## Backward compatibility

- A new daemon version must work with an old Swift client until the next major version. The reverse is also true.
- Add new fields with sensible defaults. Old clients ignore them; old daemons see zero values.
- Add new RPCs freely. Old clients do not call them.
- Adding new required behavior (e.g., a license-acceptance handshake) is breaking. Use a new RPC and gate it via a feature flag returned from `GetCapabilities`.

## Core RPCs (V1 contract)

The V1 service contract is:

```protobuf
service RestorationService {
  // Daemon capabilities and version info
  rpc GetCapabilities(Empty) returns (Capabilities);

  // List loaded models and their status
  rpc ListModels(Empty) returns (ModelList);

  // Trigger model download/load; streams progress
  rpc PrepareModels(PrepareRequest) returns (stream PrepareProgress);

  // Analyze a file and return the recipe the router would choose
  rpc AnalyzeAudio(AnalyzeRequest) returns (AnalysisResult);

  // Start a restoration job; streams progress until done
  rpc StartRestoration(RestorationRequest) returns (stream RestorationProgress);

  // Cancel a running job
  rpc CancelJob(JobId) returns (Empty);

  // Graceful shutdown
  rpc Shutdown(Empty) returns (Empty);
}
```

Do not add RPCs to this service without ADR. The surface area is intentionally small.

## Field naming conventions

- File paths: `input_path`, `output_path`. Always absolute paths.
- Job identifiers: `job_id`, `request_id`. UUIDs as strings.
- Audio properties: `sample_rate` (Hz, int32), `channel_count` (int32), `duration_s` (double).
- Loudness: `loudness_lufs` (double, negative values), `true_peak_dbtp` (double).
- Stage parameters: nested in a `StageParams` message keyed by stage name.

## Stub regeneration

To regenerate stubs:

```bash
make proto
```

This runs:

```bash
protoc \
  --proto_path=proto \
  --python_out=services/inference/sangeet_inference/proto \
  --grpc_python_out=services/inference/sangeet_inference/proto \
  --swift_out=packages/audio-engine/Sources/AudioEngine/Generated \
  --grpc-swift_out=packages/audio-engine/Sources/AudioEngine/Generated \
  proto/sangeet/v1/*.proto
```

Both sides must regenerate together. A PR touching the proto without regenerating stubs is rejected.

## Testing the contract

- Each RPC has a contract test in both languages: `tests/test_contract_<rpc_name>.{py,swift}`.
- Contract tests run against a real daemon process started by the test harness, not a mock. Mocks lie about gRPC semantics.
- Round-trip tests: encode a representative message in Swift, decode in Python, verify equality. And vice versa.
- Streaming tests verify partial-progress delivery and cancellation behavior.

## What we do not do

- We do not use gRPC reflection. The contract is static; we ship the proto files.
- We do not use Protobuf `Any` types. They erase the schema.
- We do not version via field renaming (`name`, `name_v2`, `name_v3`). Use a new version namespace.
- We do not embed JSON inside proto strings. If a field is structured, define a message for it.
- We do not transmit audio sample data over gRPC. File paths only.