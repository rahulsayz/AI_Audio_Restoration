---
trigger: always_on
---

---
name: testing-and-eval
description: Rules for unit tests, integration tests, and the audio quality evaluation harness
activation: globs
globs: ["**/Tests/**", "**/tests/**", "eval/**", "**/*Test*.swift", "**/test_*.py"]
---

# Testing and Evaluation Rules

We have two parallel concerns: traditional software tests (correctness of code) and audio quality evaluation (perceptual correctness of output). Both are mandatory; they catch different bugs.

## Testing pyramid

```
                  ┌─────────────────────┐
                  │  Listening Panel    │   manual, weekly, sign-off for releases
                  ├─────────────────────┤
                  │  Eval Harness       │   automated, 100-song corpus, runs on PR + nightly
                  ├─────────────────────┤
                  │  Contract Tests     │   Swift↔Python gRPC round-trips
                  ├─────────────────────┤
                  │  Integration Tests  │   stages working together on synthetic signals
                  ├─────────────────────┤
                  │  Unit Tests         │   functions, isolated, fast
                  └─────────────────────┘
```

Each layer catches bugs the layer above cannot afford to catch. Do not skip layers because the layer above will catch it.

## Unit tests

- One test per behavior, not one test per method. Tests describe what the code does, not what it has.
- Test names are sentences: `test_router_with_clean_input_skips_denoise` is good; `test_router1` is not.
- AAA structure: Arrange, Act, Assert. Visually separated by blank lines.
- One assertion per test as a strong default. If you find yourself writing five assertions, you have five tests.
- No conditional logic in tests. No loops over test cases — use parameterized tests (`@pytest.mark.parametrize` or `XCTestCase` data sets).
- Tests are deterministic. Seed any random generator. Mock the clock if time matters.
- Run time: a unit test runs in under 100 ms. Anything slower is an integration test, file it accordingly.

## Integration tests

- Live in `tests/integration/` (Python) or `Tests/IntegrationTests/` (Swift).
- Use real components, real models on small inputs. No mocks for the unit under test.
- Run separately from unit tests in CI: `pytest tests/integration` and a dedicated Xcode scheme.
- Expected runtime: 1–30 seconds per test. Beyond 30 seconds, move to the eval harness.

## Contract tests

- Cover every RPC in `proto/sangeet/v1/*.proto`.
- Start a real daemon subprocess in a fixture. Tear it down in cleanup.
- Cover happy path, every error code, cancellation, and streaming progress delivery.
- These tests are slow (1–10 seconds each) and run in a dedicated CI job, not on every commit.

## The evaluation harness

This is the thing that prevents shipping a regression in restoration quality. It is more important than any single unit test suite.

### Corpus

- Standard corpus: **100 song segments**, 30 seconds each, stored in `eval/corpus/` (gitignored, distributed via private S3).
- Coverage:
  - 20 segments: 78rpm shellac transfers (classical and early film)
  - 20 segments: 1950s–1960s magnetic tape (Mohammed Rafi, Lata Mangeshkar, Kishore Kumar era)
  - 20 segments: 1970s–1980s film orchestral (RD Burman, Laxmikant-Pyarelal, KC Dey)
  - 15 segments: classical vocal (Hindustani khayal, Carnatic, ghazal)
  - 10 segments: classical instrumental (sitar, sarangi, tabla solo, flute)
  - 10 segments: regional film and folk recordings
  - 5 segments: known difficult cases (heavy clipping, severe wow/flutter, dropouts)

Each segment has metadata: source format, approximate year, dominant instruments, known degradations, license status, do-not-share flag.

### Metrics

The harness computes per-segment:

- **Objective**: SNR delta, spectral centroid delta, LUFS delta, true-peak compliance, RMS preservation across silence regions.
- **Reference-based** (where we have a known-good remaster): SI-SDR, multi-resolution STFT loss against reference.
- **Perceptual proxy**: NISQA-MOS estimate (open-source MOS predictor). Treated as a signal, not a verdict.
- **Subjective**: nothing automated; sent to listening panel for releases.

### Reports

- Each harness run produces `eval/reports/<commit-sha>.json` and a Markdown summary in `eval/reports/<commit-sha>.md`.
- The Markdown summary is posted as a PR comment. The summary highlights deltas from the baseline run on `main`.
- A regression of more than 0.5 dB SI-SDR or more than 0.1 NISQA-MOS on any segment is flagged.
- Three or more flagged segments blocks the merge. The reviewer can override with explicit approval and a comment explaining why.

### Running the harness

```bash
# Full run (takes 30–60 minutes)
make eval

# Single segment for debugging
python -m eval.harness --segment rafi_1957_chaudhvin_ka_chand --baseline main

# Compare two commits
python -m eval.harness --baseline 7a3f1b2 --candidate HEAD
```

The harness is a normal Python project under `eval/`. It does not depend on the inference daemon being installed — it imports the pipeline directly from `services/inference/`.

## Listening panel

- Three audio engineers, one of whom is a domain expert in Indian music recording.
- Releases require sign-off from at least two panel members on a randomized A/B/X test of 20 segments from the corpus.
- Panel feedback is logged in `eval/listening-panel/<release>.md` with anonymized scores and qualitative notes.
- A panel rejection blocks the release. Engineering does not override the panel.

## Snapshot testing

- For deterministic stages, snapshot the output bytes and store the hash in `tests/snapshots/`.
- A hash change requires explicit acknowledgment in the PR description ("intentional: changed FFT size to 2048").
- Non-deterministic stages (any ML model on MPS) do not use snapshots — they use bounded behavior tests (output within tolerance).

## What we do not do

- We do not write tests that mock the unit under test (testing a mock is testing nothing).
- We do not write tests that depend on system time, network, or external services.
- We do not write tests that "pass on my machine but fail in CI" without immediately investigating. Flaky tests are deleted, not retried.
- We do not have a "smoke test only" PR policy for restoration-chain changes. The eval harness is mandatory.
- We do not commit large audio files to the repo. Corpus storage is separate.