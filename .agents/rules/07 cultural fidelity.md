---
trigger: always_on
---

---
name: cultural-fidelity
description: Rules for preserving the cultural and timbral character of Indian music during restoration
activation: manual
---

# Cultural Fidelity Rules

This rule is referenced explicitly when working on restoration stages, mastering presets, or evaluation. It encodes domain knowledge that does not exist in generic audio restoration documentation.

The core principle: **the goal of restoration is to remove the degradation, not the era.** A 1957 Mohammed Rafi recording should sound like a clean 1957 Mohammed Rafi recording, not like a 2026 pop production.

## The signatures we protect

### Vocal placement and timbre

Golden-era Indian playback singers were recorded close-miked with specific compression and EQ choices that gave each singer a recognizable signature. These choices were artistic, not technical limitations. Specifically:

- **Lata Mangeshkar's** upper-midrange forwardness — do not de-ess aggressively; do not "open up" the midrange via bandwidth extension.
- **Mohammed Rafi's** chest-voice warmth and breath audibility — preserve the 200–500 Hz body; do not high-pass above 80 Hz.
- **Kishore Kumar's** scoop in the lower-midrange — characteristic, not a defect.
- **Manna Dey's** classical-trained vibrato — denoise stages can smooth this; use conservative strength on vocal-forward material.
- **Asha Bhosle's** characteristic edge and dynamic range — do not over-compress in mastering.

Operationally: every PR that touches denoise or bandwidth extension strength must include before/after listening notes on at least one vocal-forward reference segment.

### Classical music ornamentation

Hindustani and Carnatic classical music depend on microtonal pitch movement that cannot be transcribed in Western notation:

- **Meend** (continuous slide between notes) — denoise stages with temporal smoothing can blur the slide into discrete steps. Use models without aggressive temporal context windows for classical material.
- **Gamak** (oscillating ornament) — rapid pitch oscillation can be mistaken for vibrato by pitch-correction-adjacent processing. We have no such processing in the chain, but stay alert if any future stage operates on pitch.
- **Andolan** (slow controlled wave) — preserve.
- **Kan** (grace note touch) — very brief; transient-aware processing is needed.
- **Khatka** and **murki** (cluster ornaments) — short rapid figures; click-removal must not classify them as clicks. Calibrate the click detector against `eval/corpus/classical/` material.

### Instrument-specific protections

| Instrument | What to preserve | What can damage it |
|-----------|------------------|---------------------|
| Sitar | Sympathetic-string halo, jawari buzz | Aggressive denoise (treats halo as noise), bandwidth extension (adds fake top end) |
| Sarangi | Bow noise, sympathetic resonance, glides | Click removal (mistakes bow articulation), temporal smoothing |
| Tabla | Sharp transients (sam strokes), bayan slides | Click removal (false-positives transients), broadband denoise (smears attack) |
| Tanpura | Sustained drone, jawari buzz character | Denoise (treats drone as steady noise), normalization (squashes dynamics) |
| Harmonium | Reed buzz, pump noise (artistic) | Denoise (removes reed character), dehum (50 Hz drone overlaps mains hum) |
| Sarod | Metallic plectrum attack, sympathetic strings | Click removal, bandwidth limiting |
| Bansuri | Breath noise, attack chiff | Denoise removes breath; over-smoothing kills attack |
| Ghungroo | Bright transient cluster | Click removal classifies as crackle |
| Dholak | Dual-headed dynamics, slap accents | Transient softening |
| Shehnai | Reed buzz, nasal sustain | Denoise removes buzz character |

When in doubt about an instrument, default to lower processing strength and reference the corpus segment featuring that instrument.

### Period orchestration character

Indian film music orchestration has era-specific sonic signatures that are part of what listeners love:

- **1940s–early 1950s**: thin frequency range, prominent harmonium, choir-style backing. Do not "fix" the frequency response — it is the sound.
- **Mid 1950s–1960s (Naushad, SD Burman, Shankar-Jaikishan)**: large orchestras recorded in single takes, characteristic room reverb, dynamic compression from tape. Preserve the compressed character.
- **1970s (RD Burman, Laxmikant-Pyarelal)**: fusion arrangements, electric guitars, brass sections, dholak. Bigger frequency range; bandwidth extension may be appropriate at low strength.
- **1980s**: synthesizer keyboards, drum machines mixed with traditional ensemble. Be careful — synths from this era have specific bandwidth that bandwidth extension can make sound wrong.
- **1990s–2000s (AR Rahman early period, post-Roja)**: cleaner digital recordings; minimal restoration needed unless source is degraded.

The "remaster" mastering preset is intentionally subtle for pre-1980s material. Modern hyper-loud mastering destroys the dynamic intent of these recordings.

## What "remastering" means here

We are not remixing. We are not re-arranging. We are not adding stereo width to mono recordings (this destroys the original mix intent). We are not adding fake reverb. We are not pitch-correcting.

Remastering, for us, means:

1. Removing degradations introduced by storage and transfer (noise, hum, crackle, dropouts)
2. Restoring frequency content lost to bandwidth limiting (cautiously)
3. Applying loudness normalization to modern targets
4. Subtle dynamic shaping to translate to modern playback systems

Anything beyond this list is out of scope unless the user explicitly requests it as a separate "Modernize" mode (Phase 3+).

## Validation requirements

Any change that affects the restoration chain must be evaluated against the classical and golden-era subsets of `eval/corpus/` before merge. The PR description must include:

- Specific reference segments listened to
- Subjective notes on at least three of the protected signatures above
- A statement of whether the change improves, neutral-affects, or risks each signature

A PR that does not address this section for restoration-chain changes is not ready for review.

## When the AI is wrong about Indian music

Antigravity (Gemini), Claude, and other models have generic Western-music-biased priors about what "good audio" sounds like. They will sometimes suggest:

- "Brightening" vocals → reject for golden-era material
- "Opening up" the midrange → reject for pre-1970s material
- "Adding warmth" to bass → reject for pre-1970s recordings (the bass content does not exist)
- "Stereo widening" of mono recordings → always reject
- "De-essing" classical vocals → reject; the sibilants are part of the diction
- "Normalizing" period reverb → reject; the room is part of the recording

If an agent suggests any of these, push back and reference this rule.

## Reference recordings to listen to

Before tuning a restoration parameter, listen to the original and to a known-good professional remaster of these reference tracks (stored in `eval/corpus/references/`):

- Saregama's 2010 remasters of Rafi/Lata duets
- Times Music's classical Hindustani remaster series
- Sony's Carnatic classical reissues
- Original LP rips for "what the source sounds like" baselines

If you cannot hear the difference between these professional remasters and what our pipeline produces, you have not listened carefully enough or you have not listened on accurate monitors.