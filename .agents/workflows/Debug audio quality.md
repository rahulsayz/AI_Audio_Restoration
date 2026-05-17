---
trigger: always_on
---

# Workflow: Debug Audio Quality

Triggered by: `/debug-audio-quality <issue-description>`

Use when a user, the listening panel, or the eval harness reports that a specific recording sounds wrong after restoration. Audio bugs are subtle and often surface long after the offending change shipped — this workflow exists to bisect them efficiently.

## Step 1 — Reproduce

Ask for or locate:

1. The input audio file
2. The output audio file (or the parameters used so we can regenerate it)
3. The exact symptom the listener heard (in their words)
4. Timestamps in the audio where the issue is most audible

If any of these are missing, do not proceed by guessing. Ask for them.

Save all three to `eval/debug/<ticket-id>/` for permanent reference.

## Step 2 — Classify the symptom

Map the user's description to one of the known artifact categories:

| Symptom | Likely category | Likely stage(s) |
|---------|----------------|------------------|
| "Metallic" / "phasey" / "warbly" | Phase or magnitude artifact | denoise, bandwidth extension |
| "Robotic" / "underwater" | Over-smoothing | denoise (too strong) |
| "Crackly" / "ticky" | Click-removal missed or transient mis-classified | declick stage |
| "Hollow" / "thin" | Spectral hole | denoise removed too much |
| "Sibilance distorted" / "sharp s/sh sounds" | High-frequency artifact | bandwidth extension, mastering |
| "Drum hits softened" / "tabla muddy" | Transient smearing | denoise temporal smoothing |
| "Tinny on top" / "fake high end" | Hallucinated content | bandwidth extension |
| "Pumping" / "breathing" | Compression artifact | mastering multiband compressor |
| "Stereo image collapsed" or "widened weirdly" | Channel processing bug | stereo pipeline |
| "Vocal too forward" or "too far back" | Level imbalance | source separation, mastering |
| "Vocal nasality lost" | Cultural-fidelity bug | denoise on golden-era material |
| "Microtonal slides flattened" | Temporal smoothing on classical | denoise on classical material |

If the symptom does not map, document the new category in `docs/audio-engineering/known-artifacts.md` after diagnosis.

## Step 3 — Run the stage-by-stage probe

The pipeline has a debug mode that exports the intermediate output after every stage:

```bash
python -m sangeet_inference.debug \
  --input <input-file> \
  --output-dir eval/debug/<ticket-id>/intermediates \
  --params <params-file>
```

Listen to each intermediate. The first intermediate where the symptom appears is your suspect stage.

This is the most important step. Do not skip it. Diagnosing from the final output alone wastes hours.

## Step 4 — Bisect within the suspect stage

Once the suspect stage is identified, vary its strength parameter:

```bash
for s in 0.0 0.25 0.5 0.75 1.0; do
  python -m sangeet_inference.debug \
    --input <input-file> \
    --output-dir eval/debug/<ticket-id>/strength-$s \
    --override <suspect-stage>=$s
done
```

Listen at each strength. Three patterns are common:

- **Linear** — symptom scales with strength → the stage is doing too much
- **Nonlinear** — symptom appears suddenly at a threshold → the stage has a regime change, probably a model artifact
- **Independent** — symptom present even at strength=0 → not this stage; suspect was wrong

For nonlinear cases, check whether the input audio has features the model was not trained on (sample rate, channel count, content type).

## Step 5 — Git bisect if recent regression

If the symptom is new and was not present in an earlier version:

```bash
git bisect start
git bisect bad HEAD
git bisect good <last-known-good-tag>
```

At each bisect step, rebuild the daemon and rerun the stage-by-stage probe. The bisect script is in `scripts/bisect-audio.sh` — it automates the rebuild and probe per commit.

Bisect time is dominated by build time. Use the bisect-binary mode if performance matters.

## Step 6 — Cultural-fidelity check

For any quality bug on Indian music material, before fixing, consult `.agents/rules/07-cultural-fidelity.md`:

- Is the symptom one of the protected signatures we expect to preserve?
- Is the user reporting the loss of a real feature of the recording, not an artifact?

If yes, the bug is in the restoration chain damaging the input, not in the user's expectation. Fix the chain.

If the "bug" is actually the user wanting modernization that we deliberately do not do, document the expectation and explain it in the release notes — but do not change the chain to satisfy this expectation.

## Step 7 — Propose a fix

Once the offending stage and parameter are identified, propose one of:

- **Tune the router** — change when this stage activates or at what strength. Lowest-risk fix.
- **Tune the stage** — change defaults, add a guard against the problematic input type. Medium risk.
- **Replace the model** — last resort. Requires ADR.

Open a PR following the `/add-restoration-stage` workflow's later steps (ADR if material, tests, eval harness delta).

## Step 8 — Add a regression test

Whatever the fix, add a regression test to prevent the bug from returning:

1. Add the offending audio segment (or a representative synthetic equivalent) to `eval/corpus/regressions/`
2. Tag it in the eval harness with the ticket ID
3. The harness's per-segment regression detection will now flag this case in future runs

If the segment cannot be shared (user privacy, licensing), create a synthetic equivalent that exhibits the same root cause and use that as the regression test.

## Step 9 — Document in known-artifacts.md

Update `docs/audio-engineering/known-artifacts.md` with:

- The symptom in plain English (so future engineers find it via search)
- The root cause
- The fix that was applied
- Whether the fix is complete or a workaround

This document is the institutional memory of every audio bug we have hit. Treat it with care.

## Step 10 — Communicate to the reporter

If the bug came from a user report, reply to them:

- Acknowledge what they heard (validate; do not minimize)
- Explain what we found, in plain English (no jargon, no defensiveness)
- State what changes, in which version
- Offer to verify the fix with them after release

If the user's recording is something we cannot share publicly, ask permission to keep it privately for regression testing.