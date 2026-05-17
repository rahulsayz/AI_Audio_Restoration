---
trigger: always_on
---

---
name: swift-macos
description: Swift, SwiftUI, and macOS-specific rules for the front-end and audio engine
activation: globs
globs: ["**/*.swift", "**/Package.swift", "**/*.xcodeproj/**", "**/Info.plist"]
---

# Swift and macOS Rules

Applies to the SwiftUI front-end (`apps/macos/`) and the audio engine package (`packages/audio-engine/`).

## Language and SDK

- Swift 5.10 features only. No Swift 6 strict concurrency yet — we will adopt deliberately when Xcode 16 is stable for our toolchain.
- Deployment target: **macOS 13 Ventura**. Do not use macOS 14+ APIs without a fallback or an `if #available` guard.
- Apple Silicon native + Intel via Rosetta is acceptable for V1. Universal binary for the release build.

## SwiftUI patterns

- Views are small. If a view body exceeds 50 lines, extract subviews. `body` should read like a layout diagram, not like business logic.
- State lives in `@Observable` view models (or `@ObservableObject` if targeting macOS 13 strictly — we are, so `ObservableObject` it is). Views consume state, they do not own business logic.
- No `@State` for anything beyond ephemeral view-local state (toggle expanded, hovering, etc.). Persistent app state goes through view models.
- Bindings flow down, actions flow up. Do not pass closures more than two levels deep — refactor into a view model method instead.
- Use `Preview` macros for every non-trivial view. A view without a working preview is a bug.

## Concurrency

- `async/await` is the default. No completion handlers in new code — wrap legacy APIs with `withCheckedContinuation` if needed.
- `@MainActor` annotations on UI-touching code. The audio engine code is *not* `@MainActor` and must never block the main thread.
- Use `Task` for fire-and-forget; use structured `async let` or `TaskGroup` for parallel work. Do not use `Task.detached` without an explicit reason.
- The restoration pipeline is long-running. UI must reflect progress via a published progress value, not by awaiting the entire restoration.

## Audio engine specifics

- All audio buffers are float32 internally. Conversion happens at the I/O boundary, never in the middle of the pipeline.
- Sample rates: 44.1 kHz and 48 kHz are first-class. 96 kHz is supported but processed via downsampling for ML stages (the models are not trained on 96k).
- Channel layouts: mono and stereo only for V1. Multichannel is a hard reject until Phase 4.
- Chunking: 30-second windows with 1-second overlap and equal-power crossfade. This is non-negotiable — restoration models have boundary artifacts that the overlap absorbs.
- Use `Accelerate.framework` for any DSP operation that processes more than ~1000 samples. Hand-written loops on float arrays are a performance bug.

## File I/O

- `AVAudioFile` for reading and writing. Never use `Data` to read full audio files into memory — stream them.
- Temporary files in `NSTemporaryDirectory()`, cleaned up in `defer` blocks or via `withTemporaryFile` helpers.
- The user's original file is never modified. Output goes to a sibling file with `-restored` suffix unless the user picks a different location.

## Error handling

- Errors are `enum` types conforming to `LocalizedError` with user-facing `errorDescription`.
- Do not use `try!` outside of test code and resource loading from the app bundle (where failure means a broken build).
- `try?` is acceptable only when the failure case is truly recoverable and the absence of a value is meaningful. Comment why.

## Testing

- XCTest for unit tests. One test target per package.
- Audio engine tests use the synthetic test signals in `Tests/AudioEngineTests/Resources/`: sine sweeps, impulse trains, pink noise. Real music goes through the eval harness, not unit tests.
- UI tests via XCUITest for critical flows only: file drop → restoration → export. Do not write XCUITest for every button — they are slow and flaky.
- Test naming: `test_<unit>_<condition>_<expectedOutcome>`. Example: `test_chunker_with30SecondInput_produces1ChunkWithCorrectOverlap`.

## Dependencies

- Swift Package Manager only. No CocoaPods, no Carthage.
- Approved dependencies for V1:
  - `Sparkle` (auto-updates)
  - `grpc-swift` (IPC to inference daemon)
  - `SwiftLint` (lint, build-time only)
- New SPM dependencies require ADR.

## App lifecycle and the inference daemon

- The Python inference daemon runs as a launch agent installed at `~/Library/LaunchAgents/ai.sangeet.inference.plist`.
- The app launches the daemon on first use, not on app start. Startup time matters; ML model loading should not block UI.
- The Swift side connects to the daemon's Unix socket at `~/Library/Application Support/SangeetAI/inference.sock`.
- If the daemon is unreachable, show a clear recovery UI ("Sangeet's audio engine isn't running — would you like to restart it?"). Never show a generic connection error.
- On graceful app quit, send a `Shutdown` RPC and wait up to 5 seconds before forcing termination.

## Code signing and notarization

- Developer ID Application certificate for direct distribution. Not Mac App Store in V1.
- Hardened Runtime: enabled. Entitlements: only what we strictly need — file access (user-selected files only), microphone access only if we add live input (we don't, in V1).
- Notarization via `notarytool`. Stapling required for offline-friendly launches.
- The Python daemon is signed and notarized as a separate executable bundled inside `Resources/`.

## What we do not do

- We do not use UIKit-compatible APIs that have macOS equivalents (e.g., no `UIColor` bridging — use `NSColor` or SwiftUI `Color`).
- We do not use `Combine` for new code. `async/await` and `AsyncSequence` cover our needs.
- We do not use third-party reactive frameworks. SwiftUI's built-in state is sufficient.
- We do not block the main thread for any operation that could take more than 16 ms.