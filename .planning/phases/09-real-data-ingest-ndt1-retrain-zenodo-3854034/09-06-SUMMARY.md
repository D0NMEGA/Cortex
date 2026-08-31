---
status: PARTIAL
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 06
subsystem: decoder
tags: [ndt1, co-bps, indy, loso, poisson-nll, torch, provenance, evidence, sha256]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 04
    provides: "ndt1.sessions (available_sessions, pooled_splits, loso_folds, SessionLoad) and ndt1.qc (firing_rate_stats, band_violations)"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 05
    provides: "1,767,820,363 bytes of real Indy M1 data under Decoder/data/ with four 64-hex sha256 pins and zero PENDING"
  - phase: 04-ndt1-training-on-indy-loco-synthetic-replay
    provides: "train_ndt1, co_bps, mean_firing_rate, NDT1ANE, and the Phase-4 config that D-14 requires verbatim"
provides:
  - "The first decoder number in this repository measured on real primate M1 spikes: pooled held-out co-bps 1.9116 (train-split null) / 1.8834 (test-mean null)"
  - "Decoder/scripts/report_sessions.py: the RD-02e per-session ingest report with a manifest cross-check that exits nonzero on an unpinned .mat"
  - "Decoder/scripts/train_real.py: pooled retrain, three-null per-session scoring, four-fold LOSO, the input-visibility diagnostic, and the code-derived D-22 margin"
  - "09-decoder-metrics.json: data_source real, four manifest-copied sha256 pins, checkpoint sha256, both nulls, the rotation, and strict-JSON-safe nulls for the diverged fold"
  - "09-training-evidence.md: the artifact that supersedes the synthetic co-bps 0.3804"
  - "CO_BPS_MARGIN re-derived to 0.25 and bound to the published number by three quick tests"
  - "Two measured findings that constrain how the number may be quoted: the objective does not hide what it scores, and one LOSO fold diverges under the locked config"
affects: [09-07, 09-08, 09-09, 09-10, 09-11, RD-05 palettization delta, RD-06 ANE re-measurement, decoder-policy.sh]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "The assertion margin is computed by code FROM the committed observation (`--derive-margin`), never typed by a human who has seen the number"
    - "The training pass writes `margin: null` on every run, so a margin can never outlive the measurement it was derived from"
    - "Non-finite results are recorded as JSON null, never as the bare NaN token that JSON.parse rejects, so a failure is auditable rather than unparseable"
    - "A caveat that would change how a number is read is MEASURED and published beside it, not left as prose"
    - "A wiring-check mode writes to its own checkpoint filename so it cannot clobber the artifact whose sha256 is published"

key-files:
  created:
    - Decoder/scripts/report_sessions.py
    - Decoder/scripts/train_real.py
    - Decoder/tests/test_cobps_margin.py
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-decoder-metrics.json
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-training-evidence.md
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/deferred-items-09-06.md
  modified:
    - Decoder/tests/test_heldout_cobps.py

key-decisions:
  - "Windows are cut PER SESSION and then concatenated, not cut across a concatenation, so no training window straddles two recordings weeks apart. Costs 2 windows of 7,134"
  - "A third null, the session's own train mean, was added beside the two the plan required. Without it the gap between the gate null and the drift-robust null has two possible causes and no way to tell them apart; with it the answer is measured (cross-session heterogeneity, up to 0.5632, not within-session drift, at most 0.0516)"
  - "The input-visibility caveat was measured rather than asserted. train_ndt1 feeds the encoder unmasked counts, so a scored position is visible to the model predicting it; --diagnostic quantifies that instead of leaving a reader to find it in the source"
  - "The diverged LOSO fold is reported, not repaired. An 11-epoch budget would have produced a number for it, and choosing 11 because it avoids the NaN is tuning toward a result (D-22, D-25)"
  - "The full pipeline was executed twice end to end rather than once, turning a 60-minute cost into bit-for-bit reproducibility evidence including an identical checkpoint sha256"

patterns-established:
  - "Derive-then-assert: `--derive-margin` reads the observation off disk and computes the constant, so D-22 compliance is structural rather than a promise"
  - "Publish the ceiling and the floor: every co-bps is reported against both the leakage-free gate null and the drift-robust NLB-convention null, and the flattering one is never quoted alone"
  - "A second parse used for reporting cross-checks itself against the primary path (in-window spike count versus the binned matrix total), so duplicated dereference logic cannot drift silently"

requirements-completed: [RD-02, RD-03, RD-04]

# Metrics
duration: 3h 16m
completed: 2026-08-31
---

# Phase 9 Plan 06: NDT1 retrained on real Indy M1 spikes Summary

> **SUPERSEDED, 2026-08-31.** Every co-bps in this document was produced by a training objective in
> which the encoder could read the positions it was scored on, the defect this summary itself logged
> as deferred item 1. The corrected pooled value is **0.0062** (train-split null) and **-0.0219**
> (test-mean null), not 1.9116 and 1.8834. See the CORRECTION section at the end of this file, and
> `09-training-evidence.md`. This document is retained as the record of what Plan 09-06 measured.

**The decoder has now seen real primate M1 spikes: pooled held-out co-bps is 1.9116 bits/spike against the train-split mean-rate null and 1.8834 against the drift-robust test-mean null, reproduced bit-for-bit across two full executions, with the two caveats that constrain how it may be quoted measured and published beside it rather than left for a reader to discover.**

## Performance

- **Duration:** 3h 16m (2026-08-31T05:42:22Z to 2026-08-31T08:58:46Z), of which roughly 2h 40m was CPU training
- **Tasks:** 3 of 3
- **Files:** 6 created, 1 modified
- **Commits:** 4

## Accomplishments

### The number, and what produced it

| Quantity | Value | Null |
|---|---|---|
| Pooled held-out co-bps | **1.9116** | pooled train-split mean rate (the D-22 gate) |
| Pooled held-out co-bps | **1.8834** | test mean (NLB convention, drift-robust) |
| Per-session held-out range | 1.6500 to 1.9540 | test mean |
| LOSO, 3 of 4 folds | 1.5110 mean, 1.2991 to 1.9137 | test mean |
| LOSO, 4th fold | diverged to a non-finite loss in epoch 12 | not applicable |
| Superseded synthetic value | 0.3804 | `04-training-evidence.md` |

Trained with the Phase-4 config verbatim (12 epochs, lr 2e-3, batch 16, seq_len 32, seed 0, AdamW
wd 0.01, mask_ratio 0.25, CPU) on 7,132 windows from the four sessions' train halves, 5,352 steps in
836 s. Loss 0.4309 to 0.2439, with epochs 10 to 12 oscillating inside 0.0018, so the curve converged
and D-14's raise-the-budget branch did not fire.

### RD-04's generalization answer

Under the drift-robust null, holding a session out entirely costs 1.7723 to 1.5110, about 15%. The
model transfers to an unseen session at a measurable cost, and the weakest finite fold still sits at
1.2991. That comparison is deliberately made under `test_mean_null` and not under `train_null`: a
fold's `train_null` is the mean of three sessions the evaluated one is not among, so it is an even
worse constant predictor and would have made LOSO look BETTER than in-pool (2.2271 versus 2.1010),
which is an artifact rather than a result.

### The three-null decomposition

The pooled gate null and the drift-robust null differ by up to 0.5632 bits/spike per session. The
third null (that session's own train mean) localizes the cause: the `train_null` to
`session_train_null` gap runs to 0.5632 while the `session_train_null` to `test_mean_null` gap never
exceeds 0.0516. So the gap is cross-session heterogeneity, not the measured 8.1% within-session rate
drift. `indy_20160627_01` shows the smallest gap (0.0336) because it is 59% of the corpus and the
pooled mean is essentially its own.

### Two caveats, measured rather than asserted

1. **The objective does not hide what it scores.** `train_ndt1` calls `model(targets)` on the
   unmasked counts and uses the mask only to select which positions the Poisson NLL is summed over;
   `NDT1ANE.forward` performs no input masking. `--diagnostic` re-scores the committed checkpoint
   with the scored positions zeroed: 1.9116 becomes -5.5266. So 1.9116 measures self-reconstruction
   plus context, not context alone. The -5.53 is explicitly NOT published as "the honest number":
   the checkpoint never saw zeroed inputs, so it is out of distribution and understates a properly
   masked model by an unknown amount. The context-only quantity was not measured and cannot be
   without retraining under a corrected objective.
2. **One LOSO fold diverges** under the locked config: eleven clean epochs then a non-finite twelfth.
   Deterministic; reproduced identically in all three executions.

### Reproducibility (T-09-06-01)

The pipeline was executed end to end twice, an hour apart. Compared programmatically, not by eye:
every per-epoch loss, every per-session co-bps under all three nulls, the pooled values to 16
significant figures, all three finite folds, and the pooled checkpoint's SHA-256
(`0e5c174dd1d3112ca1d7fbfb9da8d14962b3a2f66ac9bffb8c2c789b87c72841`) are identical. An identical
checkpoint hash is the strongest available form of the claim: the optimizer visited the same states
in the same order, not merely that two summary statistics agreed.

### The margin, derived rather than chosen

`CO_BPS_MARGIN` moved from 0.05 to **0.25**, computed by `train_real.py --derive-margin`, which reads
the observed pooled value off disk and applies the fraction Phase 4 used (0.05/0.3804 = 13.1441%),
rounded to two significant figures. The committed slow gate was then executed against it on real
data: `1 passed, 150 deselected in 1201.01s`, `held_out_co_bps = 2.3993`, source
`real sessions [...]`, so the synthetic fallback branch is no longer taken.

## Task Commits

1. **Task 1: the RD-02e per-session ingest report** - `891132b` (feat)
2. **Task 2: pooled retrain, per-session co-bps, four-fold LOSO, metrics JSON** - `16c898e` (feat)
3. **Task 3: evidence artifact, re-derived margin, guard tests** - `6fd2442` (docs)
4. **Post-task fix: smoke mode no longer clobbers the published checkpoint** - `4189024` (fix)

## Files Created/Modified

- `Decoder/scripts/report_sessions.py` (created, 340 lines) - per-session bins, duration, rate
  statistics, channel yield, `finger_pos` width, P10 out-of-window spike accounting, band verdict,
  exclusions, totals, and a manifest cross-check that exits nonzero on an unpinned or PENDING `.mat`.
- `Decoder/scripts/train_real.py` (created, 790 lines) - the runbook. Five modes: the full run,
  `--smoke`, `--skip-loso`, `--diagnostic`, `--derive-margin`.
- `Decoder/tests/test_cobps_margin.py` (created, 85 lines) - three quick tests binding the constant,
  the committed JSON and its rationale.
- `Decoder/tests/test_heldout_cobps.py` (modified, +7/-3) - `CO_BPS_MARGIN` 0.05 to 0.25 with the
  re-derivation recorded in its comment. Nothing else touched.
- `09-decoder-metrics.json` (created, 280 lines) - `data_source: "real"`, four manifest-copied
  sha256 pins, checkpoint sha256, env, config, losses, three nulls per session, the rotation with
  per-fold loss curves, the visibility diagnostic, the margin and its rationale.
- `09-training-evidence.md` (created, 572 lines) - the published artifact.
- `deferred-items-09-06.md` (created) - the two out-of-scope findings.

## Decisions Made

Recorded in the frontmatter `key-decisions`. The two worth restating:

- **Executing the pipeline twice was a deliberate cost.** The first run's JSON had a defect (the
  NaN-poisoned summary, see deviation 3), so the code was fixed and the run repeated. Rather than
  discard the first run, it became the reproducibility reference, which is stronger evidence than
  anything a single run could have produced.
- **Nothing was tuned, and the places where tuning would have helped are named.** An 11-epoch budget
  would have rescued the diverged fold; a per-session train null would have made every per-session
  number look better than the pooled one; quoting `train_null` alone would have made LOSO look
  better than in-pool. All three are stated in the evidence as roads not taken.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 2 - Missing critical] Windows are cut per session, not across the concatenation**

- **Found during:** Task 2
- **Issue:** The plan specified `IndySpikeDataset(pooled_train, seq_len=SEQ_LEN)` over the
  concatenated train halves. That produces up to three windows straddling a boundary between
  recordings days or months apart, which is a fabricated neural sequence fed as a training example.
  In a phase whose entire purpose is removing fabricated inputs, adding three is the wrong trade.
- **Fix:** Each session's train half is windowed independently and the window tensors are
  concatenated. Costs 2 windows of 7,134 (0.03%) and no cross-session window exists.
- **Verification:** Window counts per session (624 / 4203 / 1829 / 476) sum to 7,132 against
  `floor(228288/32) = 7134` for the naive path.
- **Committed in:** `16c898e`

**2. [Rule 2 - Missing critical] A third null, and the input-visibility diagnostic**

- **Found during:** Task 2
- **Issue:** Two gaps in what the plan's two nulls could establish. First, the pooled `train_null`
  conflates within-session drift with cross-session heterogeneity and there is no way to separate
  them from two numbers. Second, and much more serious: reading `train_ndt1` while wiring the
  evaluation showed it passes UNMASKED counts to the encoder, so the model can see the values it is
  scored on. Publishing 1.9116 next to NLB'21's 0.147-0.192 without that disclosure would invite
  exactly the "10x state of the art" misreading this phase exists to prevent.
- **Fix:** `session_train_null` added to the per-session scoring (one extra `co_bps` call on rates
  already computed). `--diagnostic` added: loads the committed checkpoint through
  `load_checkpoint` (`weights_only=True`) and re-scores it with the scored positions zeroed,
  recording both values under `co_bps.input_visibility_diagnostic`. Both are additive; the two
  required nulls and the JSON schema the plan specified are unchanged.
- **Verification:** `visible_*` reproduces the committed values to full double precision on an
  independently constructed mask and a checkpoint reloaded from disk.
- **Committed in:** `16c898e`, published in `6fd2442`

**3. [Rule 1 - Bug] A diverged fold poisoned the summary and emitted invalid JSON**

- **Found during:** Task 2, first execution
- **Issue:** One LOSO fold produced `nan`. Two consequences. `_summarize` used `np.mean` over all
  folds, so one `nan` turned every summary statistic into `nan` and hid the three folds that did
  produce values. And `json.dumps` writes a bare `NaN` token, which is not valid JSON: confirmed
  that Node's `JSON.parse` rejects the file (`Unexpected token 'N'`), which matters because the
  repository's gate tooling is Node-based. `jq` happens to accept it, which is worse, because the
  defect would have survived a jq-based check.
- **Fix:** `_summarize` computes over the finite folds and reports `folds`, `finite_folds` and
  `diverged_folds` beside the statistics. A `_json_float` helper writes `null` for any non-finite
  value. Every fold now records its full per-epoch loss curve and a `diverged` flag, so the epoch a
  divergence happened at is auditable from the committed record. The run then had to be repeated to
  produce a JSON written by the fixed code.
- **Verification:** `node -e "JSON.parse(...)"` accepts the committed file; `grep -c NaN` returns 0;
  the summary reports mean 2.2271 over 3 finite folds with `diverged_folds: 1`.
- **Committed in:** `16c898e`

**4. [Rule 1 - Bug] `--smoke` overwrote the checkpoint whose sha256 is published**

- **Found during:** post-task verification
- **Issue:** The smoke mode saved a 1-epoch, 2-session model over `ndt1_real_pooled.pt`. Anyone
  running the documented smoke step after the real run would have silently invalidated the
  provenance in `09-decoder-metrics.json`, with nothing to indicate it.
- **Fix:** smoke writes `ndt1_real_pooled.smoke.pt`.
- **Verification:** ran a full smoke pass after the artifact run; the artifact checkpoint's sha256
  is unchanged and still equals the published value.
- **Committed in:** `4189024`

### Deliberate departures from the plan's literal text

**5. `--smoke` uses the two smallest sessions, not "first session only".** One session cannot form a
LOSO rotation (`loso_folds` requires at least two), so the plan's smoke mode would have skipped the
40-minute code path entirely. A wiring check that does not exercise the expensive path is not a
wiring check. Two sessions and 1 epoch run in about 50 s and cover pooled training, three-null
per-session scoring, a two-fold rotation and the JSON write. The smoke JSON is marked
`data_source: "real-smoke"` and `smoke: true` so it can never pass the `data_source == "real"` gate.

**6. `loso_summary` carries the flat `mean/std/min/max/folds` keys the plan's schema specifies, for
the gate null, with the drift-robust null's spread nested beneath.** The plan's verification snippet
reads `m['loso_summary']['mean']`, so the flat shape is load-bearing; both nulls still get a full
summary.

**7. Per-session window counts moved from `co_bps.per_session` to the `sessions[]` records.** A
`co_bps` block whose values are a mix of bits-per-spike figures and window counts invites a
downstream reader to average a count. The counts belong with the session provenance.

---

**Total deviations:** 4 auto-fixed (2 missing-critical, 2 bugs), 3 deliberate departures. No
architectural change, no config change, no scope creep. Nothing was tuned toward a threshold.

## Issues Encountered

**A 64-minute background run was killed by the harness mid-fold.** The second execution (the one
with the fixed recording code) was stopped by the task runner during its final LOSO fold, after the
first run had completed cleanly at 57 minutes. Relaunched with `nohup` detached from the harness's
process group, which completed. No data was lost: the killed run had already reproduced the pooled
result and three of four folds, which became part of the reproducibility comparison.

**The `ty` `unresolved-import` noise reproduced on both new scripts.** Pre-existing, repo-wide, and
already logged as `deferred-items.md` entry 2. `ruff check Decoder` and the quick pytest run both
exit 0. Not re-logged.

## Deferred Items

Two, in `deferred-items-09-06.md`, both requiring a change this plan's `files_modified` does not
cover:

1. **The masked-modeling objective does not hide what it scores** (`ndt1/train.py`). High severity:
   it is the largest caveat on the published number. Closing it means masking the encoder input,
   retraining, and re-deriving Phase 4's number too so the two remain comparable. That is an
   objective change and a user decision, not an executor auto-fix.
2. **The LOSO divergence.** Gradient-norm clipping or a lower learning rate would very likely fix it;
   both are changes to `ndt1/train.py` or to the D-14-locked config.

## Known Stubs

None. No placeholder value, hardcoded empty result, mock payload or unwired path was introduced.
`co_bps.margin` is `null` only in the window between the training pass and `--derive-margin`, which
is deliberate D-22 behavior with a test asserting the committed file is not left in that state.

Every number in this summary and in `09-training-evidence.md` came from a run that actually executed
on the four manifest-pinned real sessions. None is estimated, extrapolated, or carried from another
document. The one figure that could be mistaken for a corrected result, the -5.53 from the
visibility diagnostic, is explicitly published as a bound that understates by an unknown amount
rather than as a number this artifact claims.

## Threat Flags

None. The work stays inside the plan's register and closes its six `mitigate` dispositions:
T-09-06-01 by two bit-identical executions plus an identical checkpoint hash; T-09-06-02 by
manifest-copied checksums, a PENDING abort, and the recorded checkpoint sha256; T-09-06-03 by
per-session `chronological_split` before any pooling, per-session windowing, and zero-exposure LOSO
evaluation; T-09-06-04 by committing both nulls plus a third that localizes the cause of their gap;
T-09-06-05 by machine-deriving the margin from the observation after the fact; T-09-06-06 by
state-dict-only checkpoints loaded through `weights_only=True`. T-09-06-07 gained a demonstrated
negative control: a `.mat` on disk but absent from the manifest makes `report_sessions.py` print a
loud WARNING and exit 1, verified on a scratch copy of the committed fixture.

No new network endpoint, auth path, or trust boundary. No dataset byte entered git.

## Verification

```
uv sync --project Decoder --extra dev                                  -> 0
uv run --project Decoder python Decoder/scripts/report_sessions.py     -> 0 (4 sessions, band ok x4)
uv run --project Decoder python Decoder/scripts/report_sessions.py --data-dir /nonexistent-dir -> 0
uv run --project Decoder python Decoder/scripts/train_real.py --smoke  -> 0
uv run --project Decoder python Decoder/scripts/train_real.py          -> 0 (3302 s)
uv run --project Decoder pytest Decoder/tests -m "not slow" -q         -> 0 (145 passed, 9 deselected)
uv run --project Decoder pytest -m slow -k test_heldout_cobps -q       -> 0 (1 passed, 1201 s)
uv run --project Decoder ruff check Decoder                            -> 0
```

Both plan verification snippets pass verbatim (`metrics JSON OK`, `evidence OK`). All acceptance
criteria across the three tasks pass, including every negative grep: no bare `except` or
`except Exception` in either script, `CO_BPS_MARGIN: float = 0.05` absent, `April to June 2016`
absent, the two forbidden mc_rtt phrasings absent, `photodiode|24.7` absent from the evidence, and
`git status --porcelain Decoder/checkpoints` returning 0 lines. The only tracked `.mat` is
`Decoder/tests/fixtures/tiny_v73.mat`. Artifact minimums met: `report_sessions.py` 340 lines
(min 90), `train_real.py` 790 (min 200), `09-training-evidence.md` 572 (min 150).

## User Setup Required

None.

## Next Phase Readiness

- **Plan 09-07 (velocity readout)** has the pooled real-data checkpoint at
  `Decoder/checkpoints/ndt1_real_pooled.pt`, sha256 recorded in the metrics JSON, plus
  `ndt1.kinematics` from 09-03. The per-session train/test window counts are published so its lag
  sweep can use the same split boundaries.
- **Plans 09-08 (CoreML, ANE) and 09-09 (`decoder-policy.sh`)** have what they need:
  `09-decoder-metrics.json` carries `data_source`, the four session ids with their manifest sha256
  values, and the checkpoint hash, and it is strict-JSON parseable so a Node or `jq` gate can read
  it. Note for 09-09: `co_bps.margin` is `null` between a training run and `--derive-margin`, so a
  policy assertion on it should say which state it expects.
- **Plan 09-10 (citation sweep)** should point `04-training-evidence.md`'s superseded banner at
  `09-training-evidence.md`. The synthetic 0.3804 is named there as the value being replaced.
- **Open constraint on everything downstream:** 1.9116 must not be quoted without the visibility
  caveat. Any document that cites it should carry, or link to, the "What this number is NOT" section.

## Status rationale

`PARTIAL`, not `PASS`. Every task completed, every artifact exists, every acceptance criterion and
both verification snippets are green, and nothing was left unfinished. Two flagged gaps prevent a
clean `PASS`: one of the four LOSO folds produced no value (a measured, deterministic, reported
finding rather than an incomplete task), and two out-of-scope items are deferred, one of which
materially bounds how the headline number may be read.

## Self-Check: PASSED

Files claimed, verified present:
- `Decoder/scripts/report_sessions.py` FOUND (340 lines)
- `Decoder/scripts/train_real.py` FOUND (790 lines)
- `Decoder/tests/test_cobps_margin.py` FOUND (85 lines)
- `Decoder/tests/test_heldout_cobps.py` FOUND (modified)
- `.planning/phases/09-.../09-decoder-metrics.json` FOUND (280 lines)
- `.planning/phases/09-.../09-training-evidence.md` FOUND (572 lines)
- `.planning/phases/09-.../deferred-items-09-06.md` FOUND

Commits claimed, verified in `git log`:
- `891132b` FOUND, `16c898e` FOUND, `6fd2442` FOUND, `4189024` FOUND

Working tree clean apart from this summary. `Decoder/data/` and `Decoder/checkpoints/` unstaged and
untracked throughout; no `.mat` entered git.

---
*Phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034*
*Completed: 2026-08-31*

---

# CORRECTION (Plan 09-06b, 2026-08-31): every co-bps in this summary is superseded

**Do not quote 1.9116, 1.8834, the per-session range 1.6500 to 1.9540, the LOSO mean 1.5110, or the
margin 0.25 from this document.** They were all produced by the defect this summary itself recorded
as deferred item 1, and they have been re-measured. The corrected numbers and the full account are
in `09-training-evidence.md` and `09-decoder-metrics.json`; the superseded ones are preserved in the
JSON under `superseded_visible_input_objective`.

## What was wrong

`ndt1.train.train_ndt1` ran the encoder on the UNMASKED counts and used the mask only to select
which positions the Poisson NLL was summed over, so every position the objective scored was also an
input to the prediction of that same position. `evaluate_co_bps` and `train_real.py`'s scoring path
did the same. This summary measured the caveat (see "Two caveats, measured rather than asserted"
above) and published it beside the number rather than closing it, because closing it meant changing
the objective. The user authorized that change as a corrective task.

## What changed

`ndt1.train.masked_forward` is now the single place the encoder input is built, in training and in
every scoring path, and it runs the model on `ndt1.loss.hide_scored_positions(targets, mask)`, which
zeroes the scored positions while leaving `targets` intact for the loss. The masking choice was
zeroing rather than a learned mask embedding, so that `NDT1ANE.forward` stays a single tensor in and
single tensor out and the Core ML conversion path and the guarded 1,292,544 parameter count are both
untouched. `Decoder/tests/test_masked_input_isolation.py`, written RED against the defective code
first, makes the defect impossible to reintroduce silently.

## The corrected numbers

| Quantity | This summary (visible input) | Corrected (hidden input) |
|---|---|---|
| Pooled held-out co-bps, `train_null` | 1.9116 | **0.0062** |
| Pooled held-out co-bps, `test_mean_null` | 1.8834 | **-0.0219** |
| Per-session range, `test_mean_null` | 1.6500 to 1.9540 | -0.3820 to 0.2084 |
| LOSO mean, finite folds, `test_mean_null` | 1.5110 | **-0.4852** |
| Final training loss | 0.2439 (43% reduction) | 0.5584 (6% reduction) |
| `CO_BPS_MARGIN` | 0.25 | **0.00082** |

With the scored positions hidden, this NDT1 does not beat a constant per-channel mean firing rate.
Nothing was tuned toward or away from that; the hyperparameters are byte-for-byte the ones this plan
used, so the objective is the only variable.

## What else this changes in the text above

- **"Every session beats every null. The lowest value anywhere in the table is 1.6500."** Withdrawn.
  Three of four sessions are negative under the drift-robust null.
- **"RD-04's generalization answer: the model transfers to an unseen session at a measurable cost of
  about 15%."** Withdrawn. Every finite LOSO fold is negative under the drift-robust null; the
  D-15 prior's "channel identity did not transfer" branch is the one that fired.
- **The three-null decomposition survives unchanged.** The `train_null` to `session_train_null` gaps
  are 0.2010, 0.0336, 0.5632, 0.4310 under the corrected objective against 0.2011, 0.0336, 0.5632,
  0.4309 here. A difference between two co-bps values on the same mask cancels the model term
  exactly, so those gaps are a property of the data. The conclusion that the gap is cross-session
  heterogeneity rather than within-session drift stands.
- **The diverged LOSO fold moved.** It was the fold holding out `indy_20160624_03`, failing silently
  at epoch 12. It is now the fold holding out `indy_20160627_01`, blowing up visibly at epoch 7
  (268623.80) and reaching NaN by epoch 12. Still one fold of four, still reported and not repaired.
- **The D-14 comparability rationale is void.** Phase 4's 0.3804 was produced by the same defective
  objective, so comparability with it was never meaningful. The hyperparameters were kept anyway, for
  a different reason: so the objective is the only variable.
- **The reproducibility evidence is unaffected as a claim about the pipeline** (two bit-identical
  executions, identical checkpoint SHA-256) but the numbers it reproduced are superseded.

## What is unchanged

The ingest report, the per-session bin counts and split boundaries, the manifest sha256 pins, the
per-session windowing decision, the three-null design, the D-12 split discipline, the D-23 protocol
disclaimer and the C-03 mc_rtt correction all stand. So does this summary's status as the record of
what Plan 09-06 measured and when; per D-24 it is annotated rather than rewritten.

*Correction executed 2026-08-31. See `09-06b-SUMMARY.md`.*
