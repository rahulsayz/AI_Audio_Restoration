---
trigger: always_on
---

---
name: licensing-and-ip
description: Rules for handling third-party models, datasets, audio samples, and IP cleanliness
activation: always
---

# Licensing and IP Rules

This is a commercial product. A single license violation can sink the company. These rules exist to make license problems impossible to commit by accident.

## Three categories of third-party assets

Every external asset falls into one of three buckets:

1. **Code dependencies** (libraries, frameworks)
2. **Model weights** (pretrained ML models)
3. **Audio data** (training corpora, evaluation samples, reference recordings)

Each has different rules.

## Code dependencies

### Accepted licenses (commercial use, no copyleft burden)

- MIT
- Apache 2.0
- BSD (2-clause, 3-clause)
- ISC
- Mozilla Public License 2.0 (file-level copyleft — acceptable if we don't modify the library file)
- Unlicense / public domain

### Conditional acceptance (requires review)

- LGPL — acceptable only if dynamically linked. Not acceptable for the Python daemon if it bundles via PyInstaller (which effectively static-links).
- EPL — review case by case.

### Hard rejects

- GPL / AGPL of any version — incompatible with closed-source distribution.
- CC-BY-NC of any kind — non-commercial only.
- "Research only" licenses — not for commercial products.
- Custom licenses that include any of: field-of-use restrictions, revenue thresholds triggering payment, advertising clauses, source-disclosure requirements.

### Process

1. Before adding a new dependency, run `scripts/check-license.py <package-name>` which queries PyPI/SPM for the declared license.
2. If the license is in the accepted list, proceed. If conditional, file a one-page ADR. If hard reject, find an alternative.
3. The dependency's license file is committed to `licenses/` in the repo.
4. The "About" screen in the app lists every dependency with its license. Updated by `make licenses` from the lockfiles.

## Model weights

This is the highest-risk category. Many "open-source" ML models have research-only or non-commercial license terms on the weights even when the code is permissively licensed.

### V1 model audit

| Model | Code License | Weights License | Commercial use? | Status |
|-------|-------------|------------------|------------------|--------|
| Demucs v4 | MIT | MIT | yes | approved |
| DeepFilterNet 3 | Apache 2.0 / MIT | Apache 2.0 | yes | approved |
| NVSR | MIT | MIT | yes | approved |
| AudioSR | (varies) | CC-BY-NC | **no** | rejected for V1 |
| Facebook Denoiser | (varies) | CC-BY-NC | **no** | rejected |
| VoiceFixer | MIT | MIT | yes | approved (vocal-only contexts) |
| MERT-95M | (varies) | CC-BY-NC-SA | training use only | acceptable for Phase 3 training, not for shipped inference |

### Process for adding a new model

1. Find the weights license — not just the code license. They are often different.
2. Check the dataset the model was trained on. If the model was trained on a dataset that prohibits commercial derivatives, the model weights inherit that restriction in most jurisdictions.
3. File an ADR with: model name, version, code license, weights license, training data license, intended use, alternative considered.
4. ADR must be approved before integration.

### What to do if a license changes after integration

Some projects change licenses (e.g., Meta's research models occasionally tighten restrictions). We pin model versions by SHA-256 of weights. If upstream changes terms, we continue using the pinned version under the terms in effect when we obtained it, with documentation of the original terms and date of acquisition. Do not auto-update model versions.

## Audio data

The most legally fraught area. Indian music copyright is complex; expect ambiguity.

### Training data

- Phase 2 training data must come from one of:
  - Recordings we have explicit written license to use (label deals)
  - Creative Commons (CC-BY, CC-BY-SA, CC0) music with clear attribution
  - Music we record ourselves with performer agreements
  - Public domain works where the recording is also public domain (rare for music; the composition expiry does not free the recording)
- Synthetic degradation of clean modern recordings is acceptable training data **only if we own or license the clean source**.
- "Found on the internet" is not a source. YouTube rips, Spotify rips, archive.org rips of unknown provenance — never used for training.

### Evaluation corpus

- We may use recordings under fair use for internal evaluation (private, non-distributed, transformative comparison). Mark these segments with `internal_only: true` in metadata.
- Distributable evaluation segments must be from sources we have rights to share.
- Reference remasters (used for "what does good sound like") are listened to, never bundled with the application. They live in `eval/corpus/references/` with a do-not-distribute flag.

### User audio

- User-uploaded audio is owned by the user. We process it on their device, locally, and never transmit it.
- Telemetry never includes audio content. Not even spectral summaries that could be reverse-engineered to identify a recording.
- If we add cloud processing in Phase 4, encrypt at rest, auto-delete after 24 hours, and require explicit user consent.

### Opt-in data contribution

- Users can opt in to contribute their (degraded, restored) pairs to our training corpus.
- Default is opt-out. The consent UI is plain English: "Help improve Sangeet by sharing this restoration anonymously. Your audio leaves your Mac encrypted and is deleted from our servers after training is complete."
- Contribution metadata: degradation type, restoration parameters, user rating. No filenames, no metadata that could identify the recording.
- Users can revoke and request deletion of any contributions; this works for up to 90 days, after which contributions are mixed into training data and cannot be individually removed.

## Patent considerations

- We do not implement audio algorithms that are subject to patents still in force without a license.
- MP3 patents expired in 2017; AAC patents still partially in force — we use Apple's bundled AAC encoder, which carries a license through macOS.
- Avoid algorithms specifically patented in audio restoration (some iZotope patents may apply to specific de-clipping and spectral repair approaches). When implementing a stage from scratch, search prior art and document the search in the ADR.

## Trademark

- "Sangeet AI" — trademark search in progress (Week 1 task per the development plan).
- Do not use names of real artists (Rafi, Lata, etc.) in product UI, marketing copy, or example screenshots beyond fair editorial use.
- Do not use record label logos or names without permission.

## Distribution licensing

- Our application is distributed under a commercial EULA, not open-source.
- The EULA prohibits redistribution, decompilation, and use to develop competing products.
- A separate open-source license might apply to extracted platform components in Phase 4 — that decision is deferred and requires legal review.

## When in doubt

If you are unsure whether a license is compatible, the default is **do not commit the dependency or asset.** Surface the question to Rahul or the project's legal review. A one-day delay is cheaper than a takedown notice.

## What we do not do

- We do not bundle GPL-licensed code, no matter how clever the LD_PRELOAD trick is.
- We do not use scraped or pirated music for any purpose. Not for training. Not for evaluation. Not for testing.
- We do not assume "fair use" without legal review for any distributed content.
- We do not strip license headers from third-party source files. They stay attached.
- We do not commit pretrained model weights to git (use git-lfs or a separate model registry).