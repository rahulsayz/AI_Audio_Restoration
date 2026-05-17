# AGENTS.md — Sangeet AI

> Cross-tool agent instructions for this project. Compatible with Antigravity (v1.20.3+), Cursor, Claude Code, and Windsurf. Workspace-specific rules live in `.agents/rules/`.

---

## 1. Project Identity

**Sangeet AI** is a macOS desktop application that restores and remasters old Indian music recordings using AI. The user drops in an audio file, the application classifies the degradation profile, routes the audio through a restoration chain, and outputs a professionally remastered file.

**Primary differentiation:** cultural specialization — preserve the timbral signatures of Indian music (nasal playback vocals, microtonal classical ornamentation, sympathetic-string resonance, period-appropriate orchestration) rather than flattening them to a Western pop aesthetic.

**Status:** Phase 1, building V1. Phase 1 ships a working app using orchestrated open-source models. A specialized Indian-music model arrives in Phase 3.

---

## 2. Architecture in One Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    macOS Application Bundle                      │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  SwiftUI Front-End  (apps/macos/)                          │ │
│  │  - File drop, project library, waveform preview, A/B       │ │
│  └─────────────────────┬──────────────────────────────────────┘ │
│                        │                                         │
│  ┌─────────────────────▼──────────────────────────────────────┐ │
│  │  Audio Engine in Swift  (packages/audio-engine/)           │ │
│  │  - AVFoundation decode, chunking, mastering chain          │ │
│  │  - Accelerate.framework DSP                                │ │
│  └─────────────────────┬──────────────────────────────────────┘ │
│                        │ gRPC over Unix Domain Socket            │
│  ┌─────────────────────▼──────────────────────────────────────┐ │
│  │  Inference Daemon in Python  (services/inference/)         │ │
│  │  - Launch agent, gRPC server                               │ │
│  │  - Restoration pipeline orchestrator                       │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │ Intelligence Router  →  Restoration Chain            │  │ │
│  │  │   ├─ DeepFilterNet 3 (denoise)                       │  │ │
│  │  │   ├─ Click/Crackle (custom DSP, then CNN in P2)      │  │ │
│  │  │   ├─ NVSR (bandwidth extension)                      │  │ │
│  │  │   └─ Demucs v4 (optional source separation)          │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

**Three-layer split rationale:** native Swift for UI and audio I/O, Python for ML to use upstream model code directly. The gRPC boundary lets us convert hot-path models to Core ML in Phase 3 without touching the front-end.

---

## 3. Repository Layout

```
sangeet-ai/
├── AGENTS.md                          ← you are here
├── .agents/
│   ├── rules/                         ← workspace rules (auto-loaded by Antigravity)
│   │   ├── 01-coding-standards.md
│   │   ├── 02-swift-macos.md
│   │   ├── 03-python-inference.md
│   │   ├── 04-audio-dsp.md
│   │   ├── 05-grpc-contracts.md
│   │   ├── 06-testing-and-eval.md
│   │   ├── 07-cultural-fidelity.md
│   │   ├── 08-licensing-and-ip.md
│   │   └── 09-writing-and-comms.md
│   └── workflows/                     ← slash-command workflows
│       ├── add-restoration-stage.md
│       ├── benchmark-pipeline.md
│       ├── ship-release.md
│       └── debug-audio-quality.md
│
├── apps/
│   └── macos/                         ← SwiftUI application
│       ├── SangeetAI.xcodeproj
│       ├── Sources/
│       └── Tests/
│
├── packages/
│   └── audio-engine/                  ← Swift audio I/O and mastering
│       ├── Package.swift
│       ├── Sources/AudioEngine/
│       └── Tests/AudioEngineTests/
│
├── services/
│   └── inference/                     ← Python inference daemon
│       ├── pyproject.toml
│       ├── sangeet_inference/
│       │   ├── daemon.py              ← gRPC server entry point
│       │   ├── router.py              ← intelligence router
│       │   ├── pipeline.py            ← orchestration
│       │   ├── stages/                ← one file per restoration stage
│       │   ├── mastering/             ← final mastering DSP (server-side fallback)
│       │   └── proto/                 ← generated gRPC stubs
│       └── tests/
│
├── proto/                             ← single source of truth for gRPC contracts
│   └── sangeet/v1/restoration.proto
│
├── eval/                              ← evaluation harness and test corpus
│   ├── corpus/                        ← (gitignored, large files)
│   ├── harness/
│   └── reports/
│
├── scripts/                           ← build, packaging, signing
│   ├── build-daemon.sh                ← PyInstaller build
│   ├── codesign.sh
│   └── notarize.sh
│
└── docs/
    ├── architecture/                  ← ADRs
    ├── audio-engineering/             ← restoration theory and tuning notes
    └── playbooks/
```

---

## 4. Operating Principles for Agents

These principles override generic coding assistant behaviour. They are in priority order — if two principles conflict, the higher one wins.

1. **Audio quality is the product.** Code that ships fast but degrades audio output is worse than slow code that preserves quality. When in doubt, prefer fidelity over performance, and surface the trade-off to the user.

2. **Cultural fidelity is non-negotiable.** Indian music has timbral signatures that generic restoration models are biased to "fix" — nasal vocal resonance, microtonal pitch ornaments, sympathetic-string halo, tabla transient character. Any change that affects the restoration chain must be reviewed against `.agents/rules/07-cultural-fidelity.md`.

3. **Plan before coding for non-trivial work.** Use Antigravity's Planning mode for anything that touches more than one file, changes a gRPC contract, modifies the restoration chain, or alters DSP parameters. Save the plan as a comment in the relevant issue before opening a PR.

4. **Tests before merges, evaluation before releases.** Unit tests gate merges. The full evaluation harness on the 100-song corpus gates every release. Never bypass the eval — a regression on subjective quality is treated as a P0 bug.

5. **One restoration stage at a time.** When adding or modifying a restoration stage, change exactly one stage per PR. Do not bundle a denoise tweak with a bandwidth extension change. This rule exists because audio quality issues compound and become impossible to bisect when multiple changes land together.

6. **License hygiene is a hard gate.** Every third-party model, dataset, or audio sample is license-audited before integration. CC-BY-NC and research-only licenses block commercial use — flag these explicitly and find replacements. See `.agents/rules/08-licensing-and-ip.md`.

7. **Privacy by default.** User audio never leaves the device in Phase 1. Telemetry is opt-out, never opt-in. No analytics SDK that phones home to a third party. We are not Big Tech; we behave better than them.

8. **Communicate like the project owner would.** Rahul writes conversationally and directly. No corporate jargon, no AI-sounding filler, no passive voice in user-facing copy, error messages, or documentation. See `.agents/rules/09-writing-and-comms.md`.

---

## 5. Tech Stack (Locked for Phase 1)

| Layer | Choice | Version |
|------|------|--------|
| macOS UI | SwiftUI + AppKit bridges | Swift 5.10, macOS 13+ deployment target |
| Audio engine | AVFoundation + AVAudioEngine + Accelerate | Apple SDK current |
| ML runtime | PyTorch + torchaudio | PyTorch 2.3, torchaudio 2.3 |
| IPC | gRPC over Unix Domain Socket | grpc 1.62 (Python), grpc-swift 1.21 |
| Schema | Protocol Buffers | proto3 |
| Python | CPython | 3.11 (pinned — do not upgrade without ADR) |
| Build (daemon) | PyInstaller | 6.x |
| Updates | Sparkle | 2.x |
| Telemetry | self-hosted PostHog | latest |
| Test | XCTest (Swift), pytest (Python) | current |
| Lint | SwiftLint, ruff, black, mypy strict | current |

Do not introduce new top-level dependencies without an ADR in `docs/architecture/`. "It would be convenient to use X" is not sufficient justification.

---

## 6. Phase 1 Scope Discipline

We are in Phase 1. The temptation to scope-creep into Phase 2 or 3 features is the biggest risk to shipping. The following are explicitly **out of scope** for Phase 1 — do not implement them, do not refactor for them, do not add abstractions to "make them easier later":

- Custom-trained Indian-music restoration model (Phase 3)
- Cloud inference backend (Phase 4)
- Source separation as default-on (Phase 2 decision)
- Batch processing of multiple files (Phase 3)
- Multi-format export beyond WAV/FLAC/MP3/M4A (Phase 3)
- Era-aware mastering presets beyond "streaming" and "remaster" (Phase 3)
- A mobile companion app (never, unless explicitly approved)
- iCloud sync, sharing, collaboration features (Phase 4 if at all)

If the user asks for these features in Phase 1, the correct response is to flag the scope conflict and propose deferring.

---

## 7. Definition of Done

A task is "done" only when **all** of these are true:

- Code compiles with zero warnings in the relevant linter (SwiftLint, ruff)
- All new code has unit tests; coverage on touched files does not drop
- For any change touching the restoration chain: ran the evaluation harness on the standard 100-song corpus and posted the delta in the PR
- For UI changes: tested on macOS 13, 14, and 15 (or the current minimum + latest two)
- For changes affecting the gRPC contract: regenerated stubs on both sides, version bumped in the proto file
- For dependency additions: ADR written and merged separately
- PR description explains the *why*, not just the *what*

---

## 8. Where to Look First

When picking up a new task, read in this order:

1. This file (you are here)
2. The specific rule files in `.agents/rules/` matching the area of work
3. Any ADRs in `docs/architecture/` referenced by the task
4. Existing tests for the module — they often encode constraints not documented elsewhere
5. Recent PRs to the same area — patterns and review feedback are signal

Do not start coding before completing step 4. The 15 minutes spent reading saves hours of rework.
