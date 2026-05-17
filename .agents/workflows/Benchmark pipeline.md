---
trigger: always_on
---

# Workflow: Benchmark Pipeline

Triggered by: `/benchmark-pipeline [--baseline <git-ref>]`

Run a full performance and quality benchmark of the restoration pipeline. Use before any release and after any change to the restoration chain.

## Step 1 — Confirm environment

Verify:

- Running on macOS host (not a CI container — wall-clock numbers must come from real hardware)
- Mac model is recorded (`system_profiler SPHardwareDataType | grep Model`)
- No other heavy processes running (Activity Monitor under 30% CPU)
- Daemon is built from the current commit, not a stale build

If any check fails, pause and report. Do not proceed.

## Step 2 — Define baseline

Default baseline: latest `main`.

Override with `--baseline <git-ref>` for comparing against a specific commit.

Check out the baseline in a separate worktree:

```bash
git worktree add ../sangeet-baseline <baseline-ref>
cd ../sangeet-baseline && make build-daemon
```

## Step 3 — Run the performance benchmark

Use the standard performance corpus (10 segments, 4 minutes each, varied content):

```bash
python -m eval.benchmark \
  --corpus eval/corpus/performance \
  --pipeline current,baseline \
  --output eval/reports/benchmark-<timestamp>.json
```

The benchmark measures, for each segment:

- Total wall-clock time
- Realtime ratio (segment duration / wall-clock)
- Peak memory (resident set)
- Per-stage breakdown
- Time-to-first-audio (latency to first preview chunk)

Report failures if any segment is below 2x realtime on the M2 baseline.

## Step 4 — Run the quality eval harness

See `.agents/rules/06-testing-and-eval.md` for the harness. Run on the full 100-song corpus:

```bash
make eval -- --baseline <baseline-ref> --candidate HEAD
```

Report the per-segment delta and any segments where:

- SI-SDR regressed by more than 0.5 dB
- NISQA-MOS regressed by more than 0.1
- True peak compliance was lost
- A new artifact was introduced (per the artifact classifier in the harness)

## Step 5 — Summarize

Produce a one-page Markdown summary at `eval/reports/benchmark-summary-<timestamp>.md`:

```markdown
# Benchmark — <date>

## Performance (M2 MacBook Pro, 16GB)

| Metric | Baseline (<ref>) | Current (HEAD) | Delta |
|---|---|---|---|
| Avg realtime ratio | x.xx | y.yy | +/- |
| Peak memory | x GB | y GB | +/- |
| Time to first audio | x s | y s | +/- |

## Quality (100-song eval corpus)

| Metric | Baseline | Current | Delta |
|---|---|---|---|
| Mean SI-SDR | x.x dB | y.y dB | +/- |
| Mean NISQA-MOS | x.xx | y.yy | +/- |
| Segments with regression | N | M | +/- |

## Notable changes

- <stage>: <observation>
- ...

## Recommendation

[Ship / Hold / Investigate]
```

## Step 6 — Decide

If performance OR quality regresses materially, the workflow ends with a "Hold" recommendation. Do not auto-merge. Surface the regression and propose investigation.

If both are flat or improved, the workflow ends with a "Ship" recommendation.

## Step 7 — Archive

Commit `eval/reports/benchmark-<timestamp>.json` and the summary Markdown to the repo. These build the historical record of quality and performance over time.