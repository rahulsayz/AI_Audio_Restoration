# ADR-003: Disable Bandwidth Extension unconditionally in V1

Date: 2026-05-17
Status: Proposed

## Context
We added neural vocoder super resolution (NVSR) in ADR-002 to handle severe high-frequency roll-off in historical Indian music.
However, a critical routing bug was discovered: the V1 audio feature `hf_rolloff_hz` measures spectral energy concentration (e.g., 95% spectral energy threshold) rather than actual high-frequency bandwidth cutoff.
As a result, clean wideband audio with heavy low-frequency or high-mid energy concentration (common in classical Indian vocals and dense instrumental pieces) registers a false positive low `hf_rolloff_hz`. The router triggers bandwidth extension, which strips the natural top-end above the false crossover frequency and generates synthetic harmonics, degrading clean audio.

## Decision
We will unconditionally disable `bandwidth_extension` in V1 by forcing `bwe_strength = 0.0` inside `services/inference/sangeet_inference/router.py`.
We will preserve the `BandwidthExtensionStage` class itself and the surrounding pipeline integration in the codebase to make Phase 2 reactivation straightforward.
We will revisit this in Phase 2 by:
1. Researching and implementing a robust, pitch-and-noise-resilient bandwidth-cutoff detector that measures actual brickwall bandlimiting rather than energy concentration.
2. Introducing a user-facing toggle in the SwiftUI application settings, allowing users to opt-in/opt-out of bandwidth extension rather than relying purely on automated routing.

## Consequences
- **What gets better:** Clean wideband music is completely safe from generative vocoder smearing and synthetic "air" artifacts. Protecting core vocal placement (Lata, Rafi) and instrument signatures (sitar sympathetic strings, tabla transients) is fully guaranteed.
- **What gets worse:** Historical recordings with genuine severe roll-off (such as AM radio or shellac transfers) will not receive high-frequency reconstruction in V1, sounding darker.
- **What we are now committed to:** Improving our spectral analysis features module in Phase 2 to accurately detect brickwall cutoffs, and developing the settings page frontend toggle.

## Alternatives considered
- **Implement a quick fix for `hf_rolloff_hz` (e.g. lowering thresholds):** Rejected. Finding the actual brickwall cutoff frequency in noisy, highly dynamic historical music is a complex, research-grade task. Ad-hoc adjustments would only shift the failure boundary without resolving the core false-positive issue.
- **Convert BWE to an opt-in manual stage immediately in V1:** Rejected. This would require altering the gRPC protocol contract, changing SwiftUI view models, and adding UI elements under severe time constraints, which introduces significant scope creep and release instability.

## User-Facing Message (for Beta Users / PR Body)
"We've updated Sangeet AI to ensure your wideband, modern, and clean tracks retain 100% of their natural high-frequency details. Sangeet's neural bandwidth extension (which restores high-frequency detail on old shellac/AM radio files) was occasionally running on clean tracks due to an overly aggressive automated detector, replacing real high frequencies with synthetic ones. We have bypassed this automated tool in V1. A fully manual, opt-in/opt-out High Frequency Restoration switch will return in Phase 2 alongside a highly accurate cutoff detector."
