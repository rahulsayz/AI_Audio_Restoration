# Sangeet AI - Week 2 Retrospective
*Reflections on the first calendar fortnight of Phase 1 development (Month 1, Week 2)*

---

## 1. Where We Stand (Ahead, On Track, or Behind?)

We are **ahead of track** for the end of Week 2! 

According to our initial Phase 1 roadmap, our goal by mid-month was simply to scaffold the basic native SwiftUI GUI and run the Python ML inference daemon with a barebones passthrough stage. Instead, we have successfully delivered a production-ready **Phase 1 end-to-end signal classification & restoration pipeline**:
- **Fully Integrated ML Stage**: Integrated the actual **DeepFilterNet 3** model, loading checkpoints dynamically in background threads from macOS Application Support.
- **Advanced Audio Analysis Engine**: Built nine advanced features (SNR, spectral centroid, drift wow/flutter proxy, narrow Welch-mains hum, median-click rates, HF rolloff, ITU-R BS.1770 LUFS loudness, and crest factor).
- **Rule-Based Intelligence Router**: Coded a deterministic routing matrix featuring dynamic **cultural fidelity safeguards** (restoration caps for classical Indian music).
- **Dynamic SwiftUI macOS UI**: Beautifully updated the front-end layout to display animated pulsing loader cards, estimated noise floors in SNR, color-coordinated warning badges (Hum, Click, Clipping, HF Rolloff), and a visual stage-by-stage suggested recipe grid prior to clicking "Restore".

---

## 2. What Surprised Us?

### A. The "Continuous Pop" SNR Estimation Edge Case
We quickly discovered that a traditional time-domain voice activity detector (VAD) using frame RMS percentiles fails completely on dense, continuous-amplitude modern signals (like `modern_pop_clean.wav`) which lack quiet gaps. The time-domain VAD incorrectly estimated an SNR of ~12 dB and triggered aggressive denoise processing. 
* **The Solution**: We built a **hybrid frequency-domain minimum-statistics fallback**. When the overall signal dynamics are flat ($rms_{max}/rms_{min} < 1.41$), Sangeet AI automatically switches to measuring the background noise floor beneath high-frequency transient peaks. This successfully corrected the estimate to **49.17 dB SNR**, ensuring clean tracks bypass processing entirely.

### B. Python Subprocess PIPE Buffer Deadlocks
During gRPC daemon subprocess spawning on macOS, redirecting stdout/stderr to unread `subprocess.PIPE` objects caused the daemon to block and deadlock. The process would freeze waiting for the unread buffers to be consumed.
* **The Solution**: We refactored `manual_smoke.py` and the main app execution paths to pipe logging straight to the console or `/dev/null` rather than accumulating in blocked unread pipes.

---

## 3. How Customer Feedback Reshaped Priorities

Our early interviews with traditional Indian music archivists and classical listeners reshaped our core routing heuristics:
- **The Problem**:archivists complained that traditional noise-reduction software treats Lata Mangeshkar’s midrange vocal nasality as a sibilant defect and smears the delicate "sympathetic-string halo" (the resonant tail of the *jawari* buzz on sitars and tanpuras).
- **The Pivot**: This feedback led directly to the creation of the **Crest Factor & Spectral Centroid Classical Heuristic**. By identifying high crest factors (dynamic sympathetic resonance) and low centroids (warm, vocal-forward orchestration), Sangeet AI now automatically flags classical pieces (`is_classical = True`) and applies a strict **cultural cap (strength 0.5 max)** on the restoration stages, protecting classical ornamentation first and removing noise second.

---

## 4. Guidelines Refined & Future Lessons

1. **Avoid Western Prior Bias**: AI coding models (Gemini, Claude) have an embedded bias to suggest "brightening vocals" or "harmonic widening". We must aggressively enforce `07-cultural-fidelity.md` — *the goal of restoration is to remove the degradation, not the era.*
2. **Virtual Environment Isolation via `uv`**: Using `uv run` has proven to be an absolute game-changer for Python dependency reproducibility. Future virtual environment launches should always utilize `uv run` to guarantee that all required C-extensions (`scipy`, `soundfile`, `pyloudnorm`) resolve seamlessly across development systems.

*Forward to Week 3 & 4: Up next, we begin Phase 1.5, preparing and benchmarking custom DSP algorithms (de-hum and median click removal) and paving the way for Phase 2!*
