# ADR-002: Add Neural Vocoder Super Resolution (NVSR) for Bandwidth Extension

Date: 2026-05-17
Status: Proposed

## Context
Many historical Indian music recordings (e.g., shellac 78rpm discs, AM radio broadcasts, early magnetic tapes) suffer from severe high-frequency roll-off. This bandlimiting is typically characterized by cutoffs at 3.4 kHz (telephone/narrowband transmission), 5 kHz (AM radio), or 10–12 kHz (early magnetic tape). The result is a muffled, dark, and indistinct sound that lacks the "air" and clarity of modern releases.

We need a bandwidth extension (BWE) stage as Stage 6 of our restoration chain (after de-clicking and before optional source separation) that satisfies three core constraints:
1. **Licensing:** The model and its pretrained weights must be 100% compliant with commercial use (no CC-BY-NC, GPL, or research-only licenses).
2. **Performance:** Runs efficiently on an Apple M2 baseline system under our shared restoration chain budget.
3. **Cultural Fidelity:** Does not hallucinate artificial, unnatural high-frequency textures that corrupt the specific timbral signatures of Indian instruments and classical vocal ornaments.

## Decision
We will add `bandwidth_extension` as Stage 6 of our restoration chain using the Neural Vocoder Super Resolution (NVSR) model architecture.

NVSR employs a dual-stage neural approach:
1. **Mel-Spectrogram Predictor:** Infers the missing high-frequency log-mel spectrogram bands from the bandlimited low-frequency inputs.
2. **Neural Vocoder (BigVGAN/HiFi-GAN):** Translates the completed mel-spectrogram back into a high-fidelity waveform at a target sampling rate of 44.1 kHz (which our pipeline will resample to 48 kHz).

To mitigate the inherent risk of generative model hallucinations, this stage will be configured with a conservative strength-capped wet/dry mix, a high-precision crossover network, and a default-off intelligence router rule.

### Weight and License Audit
- **Code License:** MIT License.
- **Model Weights License:** MIT License.
- **Upstream Source:** [haoheliu/ssr_eval GitHub](https://github.com/haoheliu/ssr_eval)
- **Commercial Use Compliance:** Approved. The MIT license allows unrestricted commercial modification and distribution.

### Performance Budget
- **Model Size:** ~85 MB.
- **RAM Usage:** ~250 MB during active chunk processing.
- **Processing Speed:** NVSR achieves a Real-Time Factor (RTF) of ~0.06 on Apple Silicon GPU (MPS) under Apple M2 baseline systems.
- **Target Budget:** Less than 4.0 seconds of processing time per minute of stereo input audio on an M2 baseline system.

### Indian Music Cultural Risks
Generative bandwidth extension models are inherently prone to "hallucinating" high-frequency energy. They are trained predominantly on Western speech and contemporary multi-track pop music. When applied to historical Indian music, this bias poses critical risks to the core timbral signatures protected under [.agents/rules/07-cultural-fidelity.md](file:///Users/rahulchaturvedi/AI_Audio_Restoration/.agents/rules/07-cultural-fidelity.md):

1. **Risk of Sitar and Sarangi Sympathetic String Corruption:** The *jawari* (buzzing resonance) of the sitar and the rich sympathetic string halo of the sarangi are delicate acoustic textures. NVSR can misinterpret these dense mid-frequency overtones, generating metallic, out-of-tune, or synthetic high-frequency "halo" artifacts that destroy the authentic acoustic space.
2. **Risk of Tanpura Drone Distortion:** The tanpura provides a continuous, harmonically complex drone. Generative vocoders are prone to introducing mechanical-sounding whistles or inharmonic sidebands into long, sustained tones, which ruins the foundation of classical Indian recordings.
3. **Risk of Vocal Sibilant Over-Processing:** For golden-era playback vocals (e.g., Lata Mangeshkar, Mohammed Rafi), NVSR can hallucinate an unnatural, detached high-frequency "air" or exaggerated sibilance (hissing "s" sounds), making close-miked recordings sound artificial, lispy, and sterile.

### Mitigation & Verification Plan

To guarantee the protection of these cultural signatures, we will implement four strict technical mitigations directly in the stage and the intelligence router:

1. **Zero-Touch Crossover Network (Spectral Crossover):**
   We will never pass the full-band audio through the vocoder. Instead, we will implement a brickwall crossover filter at the detected input cutoff frequency ($f_c$).
   - **Low Band ($< f_c$):** The original input remains completely untouched, preserving the core vocal range, fundamental pitches, and phase relationships.
   - **High Band ($\ge f_c$):** Only the newly generated high frequencies from the NVSR model are high-passed and mixed back in.
2. **Strict V1 Strength Capping:**
   The router will limit the maximum wet/dry mix strength for NVSR to **0.5** for all standard tracks, and further cap it to **0.3** for classical/solo acoustic recordings. Strength values above 0.5 are locked out in V1 to keep processing highly conservative.
3. **Default-OFF Routing Rule:**
   The bandwidth extension stage will default to **OFF** (bypassed) for all processed files. The intelligence router will only activate Stage 6 if the computed high-frequency rolloff feature is below 8000 Hz (`features.hf_rolloff_hz < 8000`), indicating clear bandlimiting.
4. **Harness & Listening Verification:**
   - **Automated Harness:** We will include 3 specific high-fidelity references of sitar, sarangi, and classical playback vocals in the test harness to measure spectral distortion (STFT loss) and ensure we do not inject noise.
   - **Subjective Panel Gate:** The listening panel must sign off on the absence of synthetic vocoder artifacts on at least two solo classical instrumental tracks (sitar/tanpura) before merge.

## Consequences
- **What gets better:** Severely bandlimited recordings (AM radio, 78rpm shellac) regain harmonic brightness, vocal clarity, and transient definition.
- **What gets worse:** BWE adds a computational overhead of ~4s per minute of stereo input. If not heavily constrained by the crossover network, it can introduce synthetic "sheen" or vocoder coloration.
- **What we are now committed to:** Building and packaging the `ssr_eval` dependency (or extracting the core NVSR network to eliminate unused packaging overhead), maintaining its weights, and strictly enforcing the crossover boundaries.

## Alternatives considered

### 1. AudioSR
- **Why rejected:** Although AudioSR produces excellent high-fidelity results, its pretrained weights are distributed under a **CC-BY-NC 4.0** (Non-Commercial) license. This violates [.agents/rules/08-licensing-and-ip.md](file:///Users/rahulchaturvedi/AI_Audio_Restoration/.agents/rules/08-licensing-and-ip.md) and blocks commercial distribution.

### 2. Traditional Harmonic Exciters (DSP-Based)
- **Why rejected:** Traditional exciters generate high-frequency harmonics by applying non-linear distortion (rectification, squaring) to the mid-band. While safe and extremely fast, they cannot reconstruct complex high-frequency details (such as distinct vocal sibilants or detailed plectrum attacks) from severely bandlimited sources (e.g. AM radio cut off at 5 kHz), resulting in a harsh, buzzy, and artificial top-end rather than true restoration.

### 3. VoiceFixer BWE
- **Why rejected:** VoiceFixer is highly effective for speech restoration but its vocoder is heavily optimized for vocal formants. When applied to multi-instrumental Indian music, it introduces severe intermodulation distortion, completely destroying backing instrumentation.
