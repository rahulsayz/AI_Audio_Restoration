---
trigger: always_on
---

---
name: audio-dsp
description: Audio DSP rules covering signal handling, restoration chain design, and mastering
activation: globs
globs: ["**/audio-engine/**/*.swift", "services/inference/sangeet_inference/stages/**/*.py", "services/inference/sangeet_inference/mastering/**/*.py", "eval/**/*.py"]
---

# Audio DSP Rules

The signal chain is sacred. These rules exist because audio bugs are often inaudible to the developer but obvious to the user — and because restoration artifacts are sticky: once a user hears a "metallic" or "phasey" output, trust is lost.

## Signal representation

- Internal format: **float32, range [-1.0, 1.0], non-interleaved (channels-first for stereo)**.
- No int16 or int24 anywhere internally. Conversion at the I/O boundary only.
- No conversion to dB inside DSP code without converting back. Use linear amplitude for arithmetic, dB for thresholds and metering.
- Stereo layout: `[2, N]` shape. Mono: `[1, N]`, not `[N]`. The leading channel dimension is always present — this prevents broadcasting bugs.

## Sample rates

- Internal pipeline rate: **48 kHz**. Input is resampled to 48 kHz on entry, output is resampled to user's chosen rate on export.
- Resampling: use polyphase filters (SciPy `resample_poly`, or AVAudioConverter in Swift). Never use linear interpolation — it aliases.
- Validation: SR conversion preserves RMS within 0.1 dB. Test this in CI.

## Chunking and overlap

- Chunk size: **30 seconds**. This is a balance between memory and boundary artifacts.
- Overlap: **1 second** between adjacent chunks.
- Crossfade: **equal-power** cosine fade in the overlap region. Linear crossfade is rejected (causes a -3 dB dip).
- Edge chunks: pad with reflection, not zeros. Zero-padding creates discontinuities the models hallucinate around.

## Loudness and metering

- LUFS measurement per ITU-R BS.1770-4 with EBU R128 gating.
- Target loudness presets:
  - **Streaming**: -14 LUFS integrated, -1 dBTP true peak
  - **Remaster**: -9 LUFS integrated, -1 dBTP true peak (for the punchy modern Indian re-release sound)
- True peak detection with 4x oversampling. Sample peak is not sufficient.
- No clipping at any stage output. Stages must apply soft clipping (tanh) or report a clip error if they cannot meet this.

## Restoration chain order

Order matters. Do not reorder stages without ADR and audio engineer review. The current order is:

1. **Decode and resample** to 48 kHz float32
2. **De-clip** (if input was clipped at digitization)
3. **De-hum** (50/60 Hz and harmonics if detected)
4. **Broadband denoise** (DeepFilterNet 3, strength from router)
5. **Click and crackle removal** (impulsive noise)
6. **Bandwidth extension** (NVSR, only if HF rolloff detected)
7. **(Optional) Source separation** (Demucs v4, only on user request in V1)
8. **Mastering** (multiband compression, harmonic exciter, LUFS normalization)
9. **Encode and write** to output format

Reason for this order: denoise before declick (clicks survive denoise as artifacts), bandwidth extension after denoise (otherwise we extend the noise), mastering last so loudness targets are met on the final signal.

## Stage strength values

- Stages accept a `strength` parameter in `[0.0, 1.0]`. The router decides this value based on degradation severity.
- `0.0` is bypass — the stage returns input unchanged. `1.0` is maximum processing.
- Default strength values come from the router, never hardcoded in the stage.
- Conservative defaults: when in doubt, the router picks lower strength. Over-processing is more audible than under-processing.

## What to preserve

Indian music has features that generic restoration models routinely damage. The following are protected:

- **Vocal nasality and forward placement** of golden-era playback singers. Do not "warm up" or "broaden" these vocals — they were recorded close-miked for a reason.
- **Microtonal pitch ornaments** (meend, gamak, andolan, kan). Denoise stages with aggressive smoothing flatten these. Use the conservative DeepFilterNet preset, not the maximum.
- **Sympathetic-string resonance** (sitar, sarangi, tanpura). Bandwidth extension models can add unnatural top end here. Validate against reference recordings.
- **Tabla transients**. Click removal can mistake them for clicks. Calibrate the click detector against a tabla-heavy reference recording.
- **Harmonium reed buzz**. Denoise models classify this as noise. Use the harmonium-aware preset (Phase 2) or low denoise strength when detected.
- **Period orchestration character**. Brass and string sections from the 1950s have a specific compressed quality. Mastering should preserve, not "open up", this character.

When a change risks any of these, the PR description must call it out explicitly and the eval harness must include the relevant reference recordings.

## What is fair game to remove

- Broadband hiss above -45 dB
- Hum at 50/60 Hz and harmonics
- Surface noise crackle from disc transfers
- Tape dropouts (brief amplitude drops)
- Digital clipping artifacts (declipping)
- Mains buzz and electrical interference

## Validation signals

Every restoration stage is tested against these synthetic signals during development:

- **Silence** in, silence out (within -90 dB)
- **Pink noise** in, expect known SNR improvement for denoise stages
- **Sine sweep** in, expect flat magnitude response within ±0.5 dB for transparent stages
- **Impulse train** in, expect impulses preserved for non-click stages
- **Tabla loop** (real recording) in, expect transients within 1 ms of original

A stage that fails any of these in CI cannot be merged.

## Audio file format support

V1 supports:

| Format | Read | Write | Notes |
|--------|------|-------|-------|
| WAV | yes | yes | 16/24/32-bit PCM, float32 |
| FLAC | yes | yes | 16/24-bit |
| MP3 | yes | yes | 320 kbps default for export |
| M4A (AAC) | yes | yes | 256 kbps default for export |
| AIFF | yes | no | read-only convenience |
| OGG Vorbis | no | no | rejected — not common in our target market |

Default export format mirrors the input format unless the user changes it.

## Performance targets

- Throughput on M2 MacBook Pro (16 GB): **at least 2x realtime** for the default restoration chain on a stereo 48 kHz 4-minute song.
- Latency to first audio preview after file drop: **under 5 seconds** including model warm-up.
- Memory: pipeline working set under 2 GB excluding loaded models.

Stages that bust these targets need profiling and optimization before merge. Hand-wave estimates are not acceptable; provide before/after numbers from `eval/benchmark.py`.

## Common pitfalls (real bugs we want to prevent)

- **DC offset accumulation**. ML models can introduce small DC bias. Apply a high-pass at 20 Hz at the end of the chain.
- **Phase inversion across chunks**. Some models output sign-flipped audio on certain chunks. Verify chunk continuity in unit tests.
- **Stereo widening artifacts**. Per-channel processing can desynchronize channels. Process stereo as `[2, N]` arrays through the same model call when possible, or use mid-side decomposition.
- **Loudness drift across the file**. Each chunk's processing should not introduce loudness deltas across chunk boundaries. Test with a long sustained note (alaap recording is ideal).
- **Aliasing from naive resampling**. Always polyphase. Always.
- **Hallucinated content**. Bandwidth extension models can invent harmonics that were not in the source. Use the conservative preset and document audible cases in `docs/audio-engineering/known-artifacts.md`.