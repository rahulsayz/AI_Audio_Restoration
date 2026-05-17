---
trigger: always_on
---

# Workflow: Add Restoration Stage

Triggered by: `/add-restoration-stage <stage_name>`

A guided multi-step workflow for adding a new restoration stage to the pipeline. Follow each step in order. Do not skip steps.

## Step 1 — Gather requirements

Pause and ask the user:

1. What degradation does this stage address? (broadband noise, hum, clicks, bandwidth limit, dropouts, other)
2. What model or DSP technique are we using? (provide name, version, source URL)
3. What is the weights license? (Reference `.agents/rules/08-licensing-and-ip.md` for accepted licenses.)
4. Where in the chain order does it sit? (Reference `.agents/rules/04-audio-dsp.md` §"Restoration chain order")
5. Is this stage optional or default-on?

Do not proceed until all five are answered. Save the answers as a comment block at the top of the planning doc.

## Step 2 — Write an ADR

Create `docs/architecture/ADR-NNN-add-<stage_name>.md` following the template in `.agents/rules/09-writing-and-comms.md` §ADRs.

Cover:
- Why this stage now
- Alternatives considered (other models, classical DSP versions)
- License audit summary (link to the license file in the upstream repo)
- Performance budget (target seconds per minute of input on M2 baseline)
- Risks specific to Indian music — what timbral signatures could this damage?

Wait for ADR approval before writing code.

## Step 3 — Add the proto changes if needed

If the stage needs new parameters not covered by the existing `StageParams` message:

1. Add fields to `proto/sangeet/v1/restoration.proto`. Use new tag numbers; do not reuse.
2. Run `make proto`.
3. Verify both Swift and Python sides compile with the regenerated stubs.

Most stages do not need new proto fields — they use the generic `StageParams` key-value map.

## Step 4 — Implement the Python stage

Create `services/inference/sangeet_inference/stages/<stage_name>.py`.

Implement the `RestorationStage` protocol from `stages/base.py`:

```python
class <StageName>Stage:
    name = "<stage_name>"
    requires_mono = False
    sample_rate = 48000

    def __init__(self, model_path: Path) -> None:
        # load model in __init__
        ...

    def is_applicable(self, features: AudioFeatures) -> bool: ...
    def estimate_cost(self, duration_s: float) -> float: ...
    def process(self, chunk: np.ndarray, params: dict) -> np.ndarray: ...
```

Follow `.agents/rules/03-python-inference.md` strictly. The stage must be stateless across calls.

## Step 5 — Update the intelligence router

In `services/inference/sangeet_inference/router.py`, add the decision logic:

- When does this stage activate? (Add to the rule table.)
- What strength values does the router pick for what degradation severity?
- Does this stage interact with any other stage's decision? (e.g., "do not apply both source separation and bandwidth extension at maximum strength on the same chunk")

Add unit tests for the new router decisions in `tests/test_router.py`.

## Step 6 — Add unit tests

Create `tests/test_stages/test_<stage_name>.py` covering:

- Bypass test: strength=0.0 returns input unchanged within -90 dB
- Silence test: silence in, silence out
- Bounded behavior: RMS within 2 dB of input on representative signal
- Sample rate test: rejects non-48kHz input or resamples cleanly
- Channel handling: mono and stereo both work
- Chunk continuity: two consecutive chunks have no audible discontinuity at the boundary

See `.agents/rules/06-testing-and-eval.md` for the full test pyramid.

## Step 7 — Add eval harness coverage

The new stage must show up in eval reports:

1. Add stage-level metrics to `eval/harness/metrics.py`.
2. Run the full harness on a sampled subset (10 segments) to confirm the stage does not regress quality on segments where it should not activate.
3. Run the harness on segments where the stage *should* activate (e.g., a click-removal stage on shellac transfers); confirm it improves the metrics.

Post the eval delta as a comment in the PR.

## Step 8 — Cultural fidelity review

Before requesting code review, listen to the stage's output on:

- Three vocal-forward golden-era references (Rafi, Lata, Kishore)
- Two classical references with ornamentation (one Hindustani vocal, one Carnatic instrumental)
- One tabla-heavy reference
- One dense orchestration reference (RD Burman track recommended)

Write notes in the PR description on what you heard. If any of the protected signatures (`.agents/rules/07-cultural-fidelity.md`) are affected, flag it explicitly.

## Step 9 — Update Swift side if user-visible

If the new stage is user-visible (toggleable, has user-tunable parameters in advanced mode):

1. Add the toggle and parameter UI in `apps/macos/Sources/Views/`.
2. Wire it through the view model to the gRPC request builder.
3. Add a SwiftUI preview that exercises the new control.
4. Add a UI test for the toggle behavior.

Most stages are not user-visible in V1 — the router handles them automatically.

## Step 10 — Documentation

Update:

- `docs/audio-engineering/restoration-chain.md` with the new stage's position and purpose
- The "About" screen license list if the stage adds a new dependency or model
- The Phase 1 milestone document with completion

## Step 11 — Open PR

PR description template:

```
## What
Adds the <stage_name> stage to the restoration pipeline.

## Why
<one paragraph from the ADR>

## How to verify
1. `make proto` — confirm no diff in generated stubs
2. `pytest services/inference/tests/test_stages/test_<stage_name>.py` — unit tests pass
3. `make eval -- --segments classical --baseline main` — eval delta posted below
4. Run the app, drop a test file from `eval/corpus/shellac_samples/`, confirm restoration completes

## Eval delta vs main
<paste the harness summary>

## Cultural fidelity notes
<listening notes per Step 8>

## Risks
- <risk 1>
- <risk 2>

Closes SAI-NNN.
```

## Step 12 — Post-merge

After merge:

- Tag the eval baseline as `<stage_name>-baseline` for future regression detection
- Update the Phase 1 progress dashboard
- If the stage materially improves quality, write a short LinkedIn post about the technique (per `.agents/rules/09-writing-and-comms.md`)