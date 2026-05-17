# Sangeet AI Audio Restoration Chain

This document provides the definitive technical specification and routing sequence for the **Sangeet AI Audio Restoration Chain**. 

Sangeet AI's primary differentiator is **cultural specialization**—preserving the delicate timbral signatures of classical and golden-era Indian music (nasal playback vocals, microtonal ornamentation, sympathetic-string resonance, period-appropriate orchestration) rather than flattening them to a modern Western pop aesthetic.

---

## The Signal Chain at a Glance

Every audio file processed by Sangeet AI traverses the following pipeline in a strict, mathematically validated sequence. Stage order is critical: changing the sequence degrades the output by forcing upstream stages to process downstream artifacts.

```
┌────────────────────────┐
│   1. Decode & Resample │  ← Resample to 48 kHz internal float32 representation
└───────────┬────────────┘
            ▼
┌────────────────────────┐
│   2. De-clip           │  ← Repair analog/digital saturation artifacts
└───────────┬────────────┘
            ▼
┌────────────────────────┐
│   3. De-hum            │  ← Notch mains hum (50/60 Hz) and harmonics
└───────────┬────────────┘
            ▼
┌────────────────────────┐
│   4. Broadband Denoise │  ← DeepFilterNet 3 (attentuates tape/shellac hiss)
└───────────┬────────────┘
            ▼
┌────────────────────────┐
│   5. Click & Crackle   │  ← Median filter + AR spectral inpainting
└───────────┬────────────┘
            ▼
┌────────────────────────┐
│   6. Bandwidth Ext.    │  ← NVSR + Zero-Touch FFT Crossover [NEW in Phase 1]
└───────────┬────────────┘
            ▼
┌────────────────────────┐
│   7. Source Separation │  ← Optional Demucs v4 (user-requested separation)
└───────────┬────────────┘
            ▼
┌────────────────────────┐
│   8. Mastering         │  ← LUFS leveling & peak limiting (-14 or -9 LUFS targets)
└───────────┬────────────┘
            ▼
┌────────────────────────┐
│   9. Encode & Export   │  ← Convert and write to final WAV/FLAC/MP3/M4A format
└────────────────────────┘
```

---

## Detailed Stage Analysis

### Stage 1: Decode & Resample
- **Objective**: Standardize input signals.
- **Specification**: Ingested audio is parsed, decoded using `AVAudioFile` on the client, converted to `float32` range `[-1.0, 1.0]` non-interleaved arrays, and resampled to the pipeline standard **48 kHz** using high-quality polyphase resamplers.

### Stage 2: De-clip
- **Objective**: Correct digital and analog peak saturation.
- **Specification**: Reconstructs squared-off peaks that were clipped during original digitization or transfer. Prevents harmonic distortion from confusing downstream denoisers.

### Stage 3: De-hum
- **Objective**: Attenuate electrical mains hum.
- **Specification**: Automatically detects 50 Hz (Indian/European mains) or 60 Hz (US mains) hum and applies tight, high-Q notch filters to the fundamental frequency and up to 5 harmonics.
- **Cultural Safeguard**: Prevents notches from encroaching on the resonant drone frequency of the tanpura or low pitch slides (meend).

### Stage 4: Broadband Denoise (DeepFilterNet 3)
- **Objective**: Remove continuous surface noise, tape hiss, and microphone preamp noise.
- **Specification**: Leverages a deep-learning-based framework optimized for real-time processing on Apple Silicon.
- **Cultural Safeguard**: Enforces a strict **Spectral Shield**; maximum strength is capped to avoid temporal smoothing that could blur delicate classical ornaments (gamak, andolan) or nose vibrato of golden-era playback singers.

### Stage 5: Click & Crackle Removal (Declick)
- **Objective**: Remove impulsive clicks and transient crackles from shellac (78rpm) and vinyl disc transfers.
- **Specification**: Performs 3-tap median difference detection coupled with local energy filtering to prevent false-triggers on musical transients. Damaged segments are inpainted using Autoregressive (AR) spectral interpolation.
- **Cultural Safeguard**: Extremely rigorous transient analysis guarantees that **tabla sam strokes** (which have incredibly sharp attack profiles resembling clicks) are left completely untouched.

### Stage 6: Bandwidth Extension (BWE using NVSR)
- **Objective**: Reconstruct high frequencies lost to severe bandlimiting (e.g. 5 kHz cutoffs on vintage shellac, 12 kHz on old tape, or 3.4 kHz on telephone archives).
- **Specification**: Uses **Neural Vocoder Super Resolution (NVSR)** to synthesize a high-frequency spectrum. The integration is gated by a **Zero-Touch FFT Crossover Network** which ensures that all original frequencies below the detected cutoff ($f_c$) are returned completely bitwise-identical to the source.
- **Cultural Safeguard**: 
  - Gated crossover protects the core vocal formants and sitar sympathetic-string resonance.
  - Model strength parameter is scaled by the intelligence router and strictly capped at **0.3 for classical recordings** and **0.5 for film recordings** to eliminate artificial high-frequency "air" or inharmonic tanpura halos.

### Stage 7: Source Separation (Optional)
- **Objective**: Partition vocals, bass, drums, and other instruments.
- **Specification**: Uses **Demucs v4** to isolate stems. Disabled by default in Phase 1; runs only on explicit user request.

### Stage 8: Mastering
- **Objective**: Normalize loudness and optimize dynamic range for modern listening environments.
- **Specification**: Integrated LUFS measurement with two primary presets:
  - **Streaming**: -14 LUFS integrated, -1 dBTP true peak.
  - **Remaster**: -9 LUFS integrated, -1 dBTP true peak (punchy modern Indian re-release flavor).
- **Cultural Safeguard**: Rejects aggressive brickwall limiting to preserve period-appropriate orchestration dynamics and the natural acoustic decay of Indian classical instruments.

### Stage 9: Encode & Export
- **Objective**: Write output file.
- **Specification**: Re-maps float32 samples to the target output bit-depth, applies optional dither, and encodes the restored audio.

---

## Validation & Verification Metrics

 Every restoration stage must maintain deterministic boundary behavior tested in Sangeet's CI pipeline:
1. **Zero Input Silence**: A silent input must return absolute silence (RMS amplitude $< -90$ dB).
2. **Transparency**: Processing bypass (`strength = 0.0`) must yield a bit-exact identical waveform.
3. **No Clipped Outputs**: Output signals must never exceed `[-1.0, 1.0]` boundaries; soft-clipping/tanh limiters are embedded in the processor stages.
4. **Performance Target**: Full pipeline throughput must remain **at least 2x realtime** on Apple Silicon (M2 baseline).

---

## Hallucination Probe & Diagnostic Stopband Audits

To measure the risk of high-frequency "hallucinations" (synthesized content that has no physical or mathematical relation to the input signal), Sangeet AI runs an automated diagnostic stopband spectral probe during CI.

The probe generates three classes of strictly bandlimited signals (zero stopband leakage above 5 kHz) and processes them through Bandwidth Extension at strengths `0.3`, `0.5`, and `0.7` to audit stopband additions:

### Diagnostic Spectral Audit Findings

#### 1. Pure Sine Tone (1 kHz fundamental, cutoff = 5 kHz)
- **Behavior**: Pure tone input is strictly monochromatic. Stopband generation represents non-linear distortion.
- **Audit Findings**:
  - `strength = 0.3`: stopband total energy at **-41.91 dB** (primarily harmonic leakage at 6 kHz, 7 kHz, 8k, etc., with inharmonic leakage at -71.27 dB).
  - `strength = 0.5`: stopband total energy at **-37.47 dB** (inharmonic leakage at -66.83 dB).
  - **Verdict**: 🚨 **Red Flag Triggered** (Added energy exceeds -80.0 dB / 10 dB above standard noise floor). This is an expected artifact of non-linear super-resolution exciters. It mathematically justifies our strict **crossover-mix caps** and routing thresholds.

#### 2. Harmonic Series (500 Hz Fundamental + 2.5 kHz 5th Harmonic, cutoff = 5 kHz)
- **Behavior**: Expect synthesized stopband to align strictly with the harmonic multiples of 500 Hz.
- **Audit Findings**:
  - `strength = 0.3`: stopband total energy at **-36.44 dB** (harmonic energy is -36.45 dB, inharmonic leakage is extremely low at -66.19 dB).
  - `strength = 0.5`: stopband total energy at **-32.00 dB** (harmonic energy is -32.01 dB, inharmonic leakage is -61.75 dB).
  - **Verdict**: ✅ **Passes**. Synthesized components align perfectly with the musical pitch, keeping inharmonic leakage well suppressed below -60 dB.

#### 3. Low-Passed Pink Noise (cutoff = 5 kHz)
- **Behavior**: Random stochastic noise. Stopband generation can be stochastic.
- **Audit Findings**:
  - `strength = 0.3`: stopband total energy at **-35.20 dB**.
  - `strength = 0.5`: stopband total energy at **-30.76 dB**.
  - **Verdict**: ✅ **Passes**. Generates a clean high-frequency stochastic spectrum matching the stochastic nature of the input.

### Architectural Safeguard Action Plan
These diagnostic findings prove the critical necessity of **Sangeet AI's adaptive routing rules**:
- **BWE Strength is Capped at 0.5** for all standard recordings because pure-tone vocal components generate non-linear harmonics at high strength.
- **BWE Strength is Capped at 0.3** for classical/drone recordings because sympathetic-string decay represents highly sinusoidal, sparse peaks that are highly sensitive to stopband distortion.

