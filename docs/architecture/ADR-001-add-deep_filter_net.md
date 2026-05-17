# ADR-001: Add DeepFilterNet 3 for Broadband Denoising

Date: 2026-05-17
Status: Proposed

## Context
Old Indian music recordings (shellac 78rpm discs, magnetic tape) suffer from high levels of broadband noise, tape hiss, and stationary surface noise. Standard Western noise reduction solutions tend to over-process these signals.

We need a broadband denoise stage as Stage 4 in our restoration chain that satisfies the following constraints:
1. **Fidelity:** Preserves vocal nasality, microtonal slides (meends), and sympathetic resonances of classical Indian instruments (sitar, sarangi, tanpura).
2. **Performance:** Runs at least 2x realtime on an Apple M2 baseline system (restoration chain budget).
3. **License Cleanliness:** The model weights and code must be compatible with commercial closed-source distribution (no GPL, research-only, or CC-BY-NC licenses).

## Decision
We will add `deep_filter_net` as Stage 4 of our restoration chain using DeepFilterNet 3 (version 0.5.6). 

DeepFilterNet 3 uses a deep filtering approach in the frequency domain, combining low-latency deep learning with classical linear prediction. This hybrid approach makes it incredibly efficient and keeps the frequency resolution sharp.

We will configure the stage with a runtime `strength` parameter [0.0, 1.0] that controls wet/dry mixing. The intelligence router will set this strength dynamically based on estimated signal-to-noise ratio (SNR).

### Weight and License Audit
- **Code License:** Dual-licensed under MIT / Apache 2.0.
- **Model Weights License:** Apache 2.0.
- **Upstream License Source:** [DeepFilterNet LICENSE](https://github.com/Rikorose/DeepFilterNet/blob/main/LICENSE-APACHE)
- **Commercial Use Compliance:** Approved. No copyleft or non-commercial restrictions.

### Performance Budget
- **Model Size:** Under 10 MB.
- **RAM Usage:** ~50 MB during active processing.
- **Processing Speed:** DeepFilterNet 3 achieves a Real-Time Factor (RTF) of ~0.02 on a single M2 CPU core.
- **Target Budget:** Less than 1.5 seconds of processing time per minute of stereo 48 kHz input audio on an M2 baseline system.

### Indian Music Cultural Risks
Broadband noise reduction models are biased toward Western speech and pop music. In Indian music, this bias poses severe risks to key timbral signatures, which we must protect under [.agents/rules/07-cultural-fidelity.md](file:///Users/rahulchaturvedi/AI_Audio_Restoration/.agents/rules/07-cultural-fidelity.md):
1. **Risk to Vocal Nasality (Golden-Era Playback):** Playback singers like Lata Mangeshkar have a highly characteristic nasal brightness and forward midrange placement. Aggressive denoising smoothing filters can treat this unique upper-midrange edge as high-frequency noise, dampening the vocal presence and flattening their acoustic signature.
2. **Risk to Microtonal Ornamentation:** Classical vocal and instrumental ornamentation—including *meend* (continuous microtonal slides), *gamak* (rapid pitch oscillations), and *andolan*—depends on precise microtonal pitch variations. Aggressive temporal context smoothing in deep learning models can blur or artificially segment these transitions, turning smooth glides into discrete steps.
3. **Risk to Harmonium Reed Buzz Character:** The harmonium's characteristic reed buzz and pump noise are vital to the period aesthetic of golden-era recordings. Generic denoisers misclassify this steady reed buzz as mechanical hum or noise and aggressively suppress it, resulting in a thin, sterile harmonium timbre.
4. **Risk to Sympathetic Resonance and Transients:** The sustained acoustic drone of the tanpura and the *jawari* (sympathetic-string halo) of the sitar or sarangi are easily mistaken for stationary background noise and suppressed. Similarly, transient detectors can mistake the sharp *sam* strike of the tabla or the metallic attack of a sarod plectrum for click-like noise and soften them.

### Mitigation Strategies
- **Wet/Dry Mixing:** We will use linear interpolation between the clean input and denoised output based on the `strength` parameter.
- **Conservative Defaults:** The intelligence router will default to a conservative strength (0.2 to 0.5) for classical and vocal-forward material to protect resonances and slides.
- **Resampling Protection:** The stage will process natively at 48 kHz and use polyphase resampling to protect against aliasing.

#### Cultural Mitigation & Verification Guidelines
To protect the acoustic properties defined in [.agents/rules/07-cultural-fidelity.md](file:///Users/rahulchaturvedi/AI_Audio_Restoration/.agents/rules/07-cultural-fidelity.md), the following strict mitigation rules apply:
1. **Conservative Strength Constraints:** V1 will enforce a highly conservative strength profile (0.3 to 0.5 max) when processing vocal-forward and classical music recordings. Any processing exceeding a strength of 0.5 is forbidden for these genres to prevent timbral flattening.
2. **Harness Verification:** The automated evaluation harness must include at least 5 classical music reference segments (encompassing Hindustani vocal meend, sitar sympathetic strings, and prominent harmonium reed buzz). This guarantees that any noise-suppression regression is immediately captured before release.


## Consequences
- **What gets better:** Broadband tape hiss and shellac surface noise are substantially reduced without introducing the standard "bubbly" musical noise of classical spectral subtraction.
- **What gets worse:** Aggressive processing (strength > 0.7) will attenuate sympathetic instrument resonances and vocal vibratos.
- **What we are now committed to:** Integrating the `deepfilternet` Python package, managing its local weights in `~/Library/Application Support/SangeetAI/models/`, and evaluating the stage on the Hindustani and Carnatic segments in our 100-song corpus.

## Alternatives considered

### 1. Rule-Based Spectral Subtraction (e.g., standard Wiener filtering or WebRTC NS)
- **Why rejected:** This approach was rejected because it introduces severe "musical noise" (warbling/bubbling artifacts) at higher noise-reduction levels. It also strips the delicate high-frequency *jawari* buzz of sitars and tanpuras, resulting in an unnatural, hollow sound.

### 2. Meta Denoiser (Facebook)
- **Why rejected:** The model weights are licensed under CC-BY-NC 4.0 (Non-Commercial), which violates Sangeet AI licensing policies (Rule 08). It is also computationally heavier and slower to run.

### 3. VoiceFixer
- **Why rejected as primary denoiser:** VoiceFixer is vocal-only and reconstructs speech from severe degradation. It is completely unsuitable for instrumental passages or rich orchestration, though we may consider it in Phase 3 for specific vocal-only restoration pathways.

### 4. Demucs v4 (used as denoiser)
- **Why rejected:** Although excellent for source separation, using Demucs v4 as a direct denoiser is computationally expensive (often exceeding our 2x realtime budget), prone to phase distortion on period acoustic instruments, and inefficient compared to dedicated denoising models.

### 5. DeepFilterNet 2 (older version)
- **Why rejected:** We selected DeepFilterNet 3 over DeepFilterNet 2 because version 3 provides significantly improved audio quality, better transient preservation, lower computational latency, and native support for modern 48kHz audio without the artifacting and band-limiting seen in the older version.
