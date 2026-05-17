# Sangeet AI listening Test Template

This template establishes a standardized, rigorous framework for manual listening tests. In Sangeet AI, automated metrics (SI-SDR, NISQA-MOS) serve as signals, but **the ear of the audio engineer is the ultimate decider**. 

Use this template to audit any stage addition, DSP modification, or release candidate.

---

## 1. Test Overview

* **Stage/Feature Audited**: `[e.g., Stage 4 - DeepFilterNet 3 Denoising]`
* **Pull Request / Commit SHA**: `[e.g., 573db41]`
* **Listener Name**: `[e.g., Rahul Chaturvedi]`
* **Date**: `[e.g., 2026-05-17]`
* **Playback Equipment**: `[e.g., Sennheiser HD600 Open-Back Monitors / MacBook Pro 16" Built-in Speakers]`

---

## 2. Test Material Checklist

Always test at least three distinct profiles to verify dynamic range, transients, and frequency responses:

1. **Profile A**: Golden-era playback vocal recording with audible tape/disc hiss (protects vocal nasality).
2. **Profile B**: Classical Indian instrumental (sitar, sarangi, or flute) with quiet sections and drone background (protects sympathetic resonance and meend).
3. **Profile C**: Modern recording with a very low noise floor (asserts transparent bypass and zero digital degradation).

---

## 3. Auditing Guidelines (What to listen for)

### A. Denoising Effectiveness
* **Hiss/Noise Reduction**: Does the noise floor drop meaningfully? Is the hiss removal continuous, or does it sound "gated" (abruptly turning off during silence)?
* **Spectral Hum/Dehum**: Are the 50/60 Hz mains hum and its harmonics completely eliminated without affecting the musical low end (tabla bayan)?

### B. Cultural & Vocal Fidelity
* **Vocal Nasality & Midrange**: Do the vocals of Lata, Rafi, or Kishore retain their forward, bright, chest-to-nasal signature? Or do they sound artificially warmed up, muffled, or pushed back in the mix?
* **Microtonal Glides (Meend/Gamak)**: Listen closely to pitch bends, slides, and ornaments. Are the transitions continuous and fluid, or does the processing make them sound quantized or stepped?
* **Sympathetic Halo**: Sitar and sarangi have a rich harmonic "halo" from sympathetic strings. Does this halo survive, or is it gated out and treated as background noise?

### C. Transient Integrity
* **Attack Transients**: Do percussion attacks (tabla slap, dholak rimshots, sitar plectrum/mizrab clicks) remain sharp and punchy? Or do they sound softened, blurred, or smeared?
* **Vocal Consonants**: Are the high-frequency sibilants (`s`, `sh`, `t`, `p`) crisp and clear? Or do they sound lisped or muffled?

### D. Digital Artifacts (The "Red Flags")
* **Metallic Resonances**: Do you hear a high-frequency "ring" or metallic echo added to quiet decays?
* **Watery/Phasey Swirling**: Does the residual background noise sound like it's "swirling" under water (spectral musical noise)?
* **Robotic Gating**: Does the voice or instrument sound slightly synthesised or electronic?

---

## 4. Evaluation Records

### Segment 1: Golden-Era Playback (Vocal-Forward)
* **File Name**: `vocal_rafi_hiss.wav`
* **routed Stage(s) & Strength**: `[e.g., deep_filter_net (0.50)]`

| Dimension | Rating (1-5) | Notes & Observations |
|---|---|---|
| **Noise Reduction** | `[ ]` | |
| **Vocal Diction & Nasality** | `[ ]` | |
| **Consonant Sharpness** | `[ ]` | |
| **Artifact Safety** | `[ ]` | |

* **Subjective Verdict**: `[PASS | FAIL | CONCERNING]`
* **Detailed Notes**:
  > *Write qualitative observations here. E.g., Hiss is effectively pushed down by ~15dB. Consonants stay extremely clear. Nasal forwardness of vocal is fully intact. No watery artifacts heard.*

---

### Segment 2: Classical Instrumental (Acoustic & Dynamics)
* **File Name**: `sitar_ravi_quiet.wav`
* **routed Stage(s) & Strength**: `[e.g., deep_filter_net (0.30)]`

| Dimension | Rating (1-5) | Notes & Observations |
|---|---|---|
| **Noise Floor Gating** | `[ ]` | |
| **Sympathetic Halo** | `[ ]` | |
| **Attack Transient (Mizrab)** | `[ ]` | |
| **Glide Continuity (Meend)** | `[ ]` | |

* **Subjective Verdict**: `[PASS | FAIL | CONCERNING]`
* **Detailed Notes**:
  > *Write qualitative observations here. E.g., Checked sitar plectrum attack—stays extremely sharp. Sympathetic string ring-out is preserved well at 0.3 strength. Microtonal slide sounds fluid.*

---

### Segment 3: Modern Recording (Transparency/Bypass)
* **File Name**: `modern_pop_clean.wav`
* **routed Stage(s) & Strength**: `[e.g., passthrough (1.00)]`

| Dimension | Rating (1-5) | Notes & Observations |
|---|---|---|
| **Transparency (Bit-Exact)** | `[ ]` | |
| **No Added Artifacts** | `[ ]` | |
| **Sub-Bass Preservation** | `[ ]` | |

* **Subjective Verdict**: `[PASS | FAIL]`
* **Detailed Notes**:
  > *Write qualitative observations here. E.g., Clean bypass. Restored output matches input exactly. Zero processing artifacts.*

---

## 5. Scoring Guide

* **5 (Excellent)**: Completely transparent processing; no visible or audible regressions; exceptional fidelity.
* **4 (Good)**: High quality restoration; extremely subtle loss in upper transients; fully ready for production.
* **3 (Acceptable)**: Satisfactory denoising; slight reduction in sympathetic ring-out; acceptable fallback.
* **2 (Degraded)**: Audible muffling of vocals or transient smearing; requires strength optimization.
* **1 (Unusable)**: Severe digital artifacts (metallic ringing, watery swirling) or vocal gating; must fail.

---

## 6. Final Recommendation

* **Status**: `[APPROVED | DEFERRED | REJECTED]`
* **Sign-off Comments**:
  > *Provide final remarks here.*
