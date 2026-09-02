---
status: PARTIAL
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 06d
subsystem: decoder
tags: [ndt1, poisson-nll, numerical-stability, convergence, co-bps, trajectory, loso, indy, evidence, tdd, pre-registration]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 06c
    provides: "the diagnosed forward-pass overflow and its specification, the stopping rule this task removes, and the 0.0713 / 12-epoch numbers it supersedes"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 05
    provides: "1,767,820,363 bytes of manifest-pinned real Indy M1 data under Decoder/data/"
provides:
  - "ndt1.loss.stable_exp and LOG_RATE_LINEARIZE_ABOVE = 20.0: the Poisson NLL linearized above a threshold no healthy run reaches, PROVEN bit-identical below it in value and gradient by torch.equal over a 2,054-point grid"
  - "The first numerically complete artifact in this phase: a 200-epoch pooled run and a four-fold rotation with ZERO divergences, where 09-06b and 09-06c each lost a fold"
  - "co_bps.trajectory: the full 21-point co-bps-versus-epoch curve against both nulls, published instead of a stopping rule's output"
  - "The headline finding: 4 of 4 sessions POSITIVE within-session (+0.1661 to +0.2455 vs their own test mean) and 4 of 4 LOSO folds NEGATIVE across sessions (mean -0.3498)"
  - "The falsification of this artifact's previous claim: the per-session negative verdict carried through 09-06b and 09-06c was an epoch-budget artifact, not a property of the model"
  - "A new pooled checkpoint at Decoder/checkpoints/ndt1_real_pooled.pt, sha256 f95b257bf2479b49102a2d8afee3c46d9008c51ba754d42a60a26762b7d3af8e, for Waves 4-7"
  - "train_real.py --only-loso: a rotation that merges into a JSON the pooled pass already wrote, so a multi-hour run cannot lose its headline to a later failure"
  - "train_real.py --plateau-stop: the 09-06c stopping rule preserved as an opt-in reproduction arm"
  - "max_log_rate_per_epoch on every model trained, which turned the stabilizer's inertness from an argument into a measurement, and reported it coming back NEGATIVE"
  - "CO_BPS_MARGIN re-derived to 0.054 by the four-times-unchanged rule"
affects: [09-07, 09-08, 09-09, 09-10, 09-11, RD-05, RD-06, decoder-policy.sh]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A numerical guard is made FREE by proving it bit-identical in value AND gradient over the whole regime healthy runs occupy, so it can only change a step that would otherwise be non-finite"
    - "Remove a selection rather than replace it: publish the whole metric-versus-epoch trajectory and report the value at a pre-registered cap, so no epoch is ever chosen after the fact"
    - "Pre-register the CAVEAT criterion, not just the number, so the wording of 'this is a floor' cannot be picked after seeing the shape of the curve"
    - "Pre-register a check that can come back against you, then report it when it does: the stabilizer was expected to be inert and was not"
    - "Declare a reduced budget as a COST decision before the run and label it as one everywhere it appears, rather than presenting it as a result"
    - "Split a multi-hour run into stages that each land on disk, so a failure in hour five costs one stage rather than the headline"
    - "Prove an in-training probe cannot perturb the run it measures, by asserting the loss curve is identical with and without it"

key-files:
  created:
    - Decoder/tests/test_loss_stability.py
    - Decoder/tests/test_cobps_trajectory.py
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/deferred-items-09-06d.md
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-06d-SUMMARY.md
  modified:
    - Decoder/src/ndt1/loss.py
    - Decoder/src/ndt1/train.py
    - Decoder/scripts/train_real.py
    - Decoder/tests/test_heldout_cobps.py
    - Decoder/tests/test_cobps_margin.py
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-decoder-metrics.json
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-training-evidence.md

key-decisions:
  - "The stopping rule was REMOVED rather than replaced. 09-06c asked for a better rule; any rule that stops inside the curve is a selection, and one designed after seeing that longer is better is a tuned budget however it is worded"
  - "C = 20 was fixed by the data range and by float32, not by a result: 812x beyond the largest log-rate healthy training has produced, and far enough below the 88.7 overflow that the linear branch and the clip's own norm computation both stay finite"
  - "torch.clamp was rejected and the rejection is an assertion, not an argument: above a clamp bound the gradient is -target, which drives an escaped rate FURTHER up"
  - "The checkpoint saved is the model at the cap, never the epoch that scored best, so there is no epoch selection anywhere in the run including in what is shipped"
  - "The LOSO budget of 60 epochs is a cost decision, pre-registered, inherited from 09-06c's already-committed cap rather than chosen for this run, and labeled as a cost everywhere it appears"
  - "The pre-registered headline was kept at the cap value even though the plateau mean is a better estimator, because averaging a plateau after seeing its shape is a post-hoc estimator with no pre-registration"
  - "The stabilizer's non-inertness was reported as a second variable rather than glossed, even though it weakens the attribution the pre-registration hoped for"
  - "The committed slow gate was NOT run, and the summary says the failure mode is 'very likely' gone rather than claiming a verdict it did not measure"
  - "The margin was re-derived UPWARD by the unchanged rule, from 0.0094 to 0.054; it was never lowered to whatever would pass"

patterns-established:
  - "When a pre-registered inertness check fails, the correct move is to publish the failure and downgrade the attribution claim, not to argue the guard was inert anyway"
  - "Report the sampling spread of a metric over its plateau alongside the single reported sample, so a reader knows how many of the printed digits are real"

requirements-completed: []

# Metrics
duration: about 9h 20m wall, of which 8h 18m was CPU
completed: 2026-09-02
---

# Phase 9 Plan 06d: the trajectory, the stabilizer, and what 200 epochs actually showed Summary

**Trained to a 200-epoch cap with no stopping rule and published the whole co-bps-versus-epoch
curve, and the answer to this phase's central question turned out to be two answers: the model
beats a per-channel mean firing rate on held-out data from sessions it trained on, on all four
sessions, and loses to it on every session it has never seen. The per-session negative verdict this
artifact carried through two corrections was an artifact of the 12-epoch budget. The cross-session
negative verdict was not: sixteen times the budget flipped every within-session sign and not one
LOSO fold.**

## Performance

- **Duration:** about 9h 20m wall (2026-09-01 11:15 to 2026-09-02 18:40 local, with a two-hour
  machine sleep and a session interruption in the middle), of which 8h 18m was CPU: a 15,043 s
  pooled run, a 14,836 s four-fold rotation, a 25-minute divergence replay, and short smoke,
  diagnostic and margin passes
- **Tasks:** 5 of 5 (stabilize, pre-register, run, re-derive, report)
- **Files:** 4 created, 7 modified
- **Commits:** 8

## Accomplishments

### The loss stabilized against forward-pass overflow, and proven free

`ndt1.loss.masked_poisson_nll`'s `log_input=True` branch is now `stable_exp(x) - target * x`, where
`stable_exp` is `exp` below `C = 20` and the tangent line to `exp` at `C` above it. Above the
threshold the loss grows linearly instead of exponentially and the derivative is the finite
positive constant `exp(C)`, so an escaped log-rate is pulled back toward the data.

**The load-bearing claim is that the change is inert, and it is an assertion rather than an
argument.** `Decoder/tests/test_loss_stability.py` proves with `torch.equal` that below `C` the
stabilized loss is bit-identical to the unmodified `nn.PoissonNLLLoss` formulation **in value and
in gradient**, over a 2,054-point grid running from -40 up to one thousandth below the threshold.
`C` itself was fixed by two measured bounds and not by any result: the largest log-rate healthy
training has ever produced here is 13.3, `exp(20)` is 4.85e8 spikes per 20 ms bin against a corpus
maximum of 5, and float32 `exp` overflows at 88.7.

The RED was behavioural, following the 09-06c pattern: `stable_exp` and its constant were added
first WITHOUT being wired into the objective, which changed no existing number (173 quick tests
stayed green), and the failing tests were the ones on `masked_poisson_nll` itself.

```
3 failed, 7 passed
- masked_poisson_nll is inf at the observed 97.33 log-rate
- its gradient there is non-finite
- SGD cannot walk an escaped rate back to the data regime
```

The 7 that passed included the bit-identity pair, which pins the pre-existing loss so the fix has
to keep it, and the control that makes the design choice explicit: **`torch.clamp` is not merely
useless above the bound, it is actively harmful.** Its clamped `exp` contributes zero to the
derivative, so the surviving `- target * x` term leaves a gradient of `-target`, and a descent step
drives an already-escaped rate further up. That wrong sign is asserted with `pytest.approx`.

### Verified against the real failure, which is where it earned its place

`Decoder/scripts/diagnose_divergence.py` replays the committed slow gate's exact training path. All
three arms, same path, same seed:

| Run | Epochs 1-3 | Epoch 4 | Epochs 5-8 |
|---|---|---|---|
| 09-06b, no clipping | 0.6034 0.5941 0.5848 | 0.5850 | blows up at epoch 8, 1.49e22, never recovers |
| 09-06c, clip 1.0 | 0.5982 0.5879 0.5826 | **nan** | nan, nan, nan, nan |
| **09-06d, clip + linearized exp** | **0.5982 0.5879 0.5826** | **18128.3** | **0.5805 0.5790 0.5767 0.5759** |

Epochs 1 to 3 are identical to 09-06c to six decimal places, which is the no-op claim measured on
real data. At the same step 1365 the same excursion happens, and where 09-06c produced `nan` and
lost the run, 09-06d produces a finite 7.68e6 and descends for four more epochs.

**And it mattered on the published run.** The rotation's fold holding out `indy_20160915_01` -- the
same fold 09-06c lost -- hit a log-rate of **149.32** at epoch 7. That is 1.68x the float32 `exp`
overflow bound, so `exp` of it is `inf` and the old objective returns `nan` there. It produced a
finite 26,374.18, recovered to 0.5661 on the next epoch, and finished with a usable number. **This
is the first complete four-fold rotation in this phase: 4 folds, 4 finite results, 0 divergences.**

### The stopping rule removed, not replaced, and the trajectory published

09-06c pre-registered a rule on the training loss, applied it without modification, and it still
fired at its own 12-epoch floor. 09-06c's deferred item asked for a better rule. This task refused
to write one: any rule that stops inside the curve is a selection, and a selection designed after
seeing that a longer budget gives a better number is a tuned budget however carefully worded.

The selection was removed instead. 200 epochs to a pre-registered cap, held-out co-bps sampled at
epoch 1, every 10th epoch and at the cap, the whole 21-point curve committed as `co_bps.trajectory`
and rendered as a table in the evidence. The checkpoint saved is the model at the cap, not the
epoch that scored best, so there is no epoch selection anywhere in the run.

The probe runs inside training, so `Decoder/tests/test_cobps_trajectory.py` asserts that a probed
run's loss curve is bit-identical to an unprobed one. A trajectory that perturbs the run it
describes is not a record of that run.

### The result, in the shape the data actually has

| | Against each held-out set's OWN mean firing rate | Verdict |
|---|---|---|
| **Within session** (pooled model, chronological tails) | +0.2127, +0.1661, +0.2062, +0.2455 | **4 of 4 positive** |
| **Across sessions** (leave-one-session-out) | -0.1238, -0.3060, -0.7805, -0.1890 | **4 of 4 negative**, mean -0.3498 |

| Arm | Budget | Pooled `train_null` | Pooled `test_mean_null` | Sessions below own mean | Finite folds |
|---|---|---|---|---|---|
| 09-06, defective objective | 12 | 1.9116 | 1.8834 | n/a | n/a |
| 09-06b, corrected, unclipped | 12 | 0.0062 | -0.0219 | 3 of 4 | 3 of 4 |
| 09-06c, clipped, rule at its floor | 12 | 0.0713 | 0.0432 | 3 of 4 | 3 of 4 |
| **09-06d, no stopping rule** | **200** | **0.4096** | **0.3814** | **0 of 4** | **4 of 4** |

**The rotation's `train_null` mean is +0.2446 and the evidence explicitly refuses to headline it.**
That null is the mean of the three sessions the fold trained on, so it cannot track the held-out
session's rate level; it is the weakest constant predictor in the artifact applied to the hardest
task in it. Against the held-out session's own mean the same four folds give -0.3498. The 0.59
bits/spike gap between the two columns IS the cross-session heterogeneity.

### The headline is one sample from a noisy plateau, and the evidence says so

The trajectory climbs monotonically to about epoch 70 and then oscillates for 130 epochs with no
trend, while the loss goes flat.

| Post-plateau, epochs 70 to 200, 14 samples | `train_null` | `test_mean_null` |
|---|---|---|
| Mean / std | 0.3562 / 0.0524 | 0.3281 / 0.0524 |
| Min to max (half-range) | 0.2437 to 0.4209 (+/-0.0886) | 0.2155 to 0.3928 (+/-0.0886) |
| Reported value at the cap | **0.4096** (12th of 14) | **0.3814** (12th of 14) |

**A single-epoch sample of this metric carries about +/-0.09 of noise once plateaued, and the
epoch-200 sample lands high in the band.** The cap value is reported unchanged because the
pre-registration said so and because averaging the plateau after seeing its shape would be a
post-hoc estimator; but the evidence states that quoting 0.4096 to four figures is quoting three
figures of noise. A stopping rule on held-out stability -- the replacement 09-06c asked for -- would
have returned anything from 0.2437 to 0.4209 depending on where it landed. That 0.18-wide spread is
the argument for publishing the curve.

The pre-registered floor criterion (labeled a floor unless co-bps moves under 1% over the last 50
epochs) fires at 24.1% and 25.9%, so the headline is labeled a floor. The evidence adds what the
criterion cannot see: that 24% is oscillation, not a climb, since the loss moves 0.31% over the
same span.

### CO_BPS_MARGIN, fourth re-derivation, same rule

`0.4095688409 * 0.131441 = 0.053834`, so **0.054**, replacing 0.0094, 0.00082, 0.25 and the
Phase-4 0.05. Machine-derived by `--derive-margin` from the number already on disk. This is the
first margin in the chain with real room under it: the observation is 7.6x the margin and the
lowest post-plateau sample still clears it by 4.5x, so unlike its two predecessors it would not
flake on the metric's own sampling noise. Eleven quick tests bind the four-link chain.

## Task Commits

1. **RED for the forward-pass overflow, plus inert `stable_exp` plumbing** - `e079218` (test)
2. **The linearized `exp` wired into the objective** - `f3dd2a2` (fix)
3. **The trajectory, the 200-epoch cap, `--only-loso`, `--plateau-stop`** - `033393e` (feat)
4. **The run plan pre-registered, committed before the run** - `06eb61f` (docs)
5. **The 09-06c numbers labeled superseded, by code, before re-running** - `f2835e0` (docs)
6. **Every co-bps re-measured at the cap, with the trajectory** - `967f38e` (feat)
7. **The evidence rewritten around what the trajectory shows** - `15c9817` (docs)
8. **This summary and the deferred items** - see `git log`

Commit ordering is the audit trail: `06eb61f` (the pre-registration) precedes `967f38e` (the
numbers), and the run did not start until 11:22 on 2026-09-01.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 3 - Blocking] A 7-hour run had nothing on disk until it finished**

- **Found during:** planning the launch
- **Issue:** the metrics JSON is written once, at the very end, so an interruption anywhere in a
  7-hour run would have cost every measured point. An earlier task in this phase was killed by a
  session rate limit mid-rotation.
- **Fix:** two changes, both minimal. `--only-loso` merges a rotation into a JSON the pooled pass
  already wrote, so the run is two stages that each land on disk; and the trajectory probe appends
  each row to a gitignored JSONL sidecar as it is measured.
- **Verification:** `--only-loso` was validated end to end against a scratch JSON at
  `--loso-epoch-cap 1` before the real run was launched.
- **Committed in:** `033393e`

**2. [Rule 3 - Blocking] The machine slept for two hours mid-run**

- **Found during:** polling the pooled run at epoch 30
- **Issue:** `time.monotonic()` had advanced 144 s while the wall clock advanced two hours, so the
  host had suspended. The run survived because it was detached, but the wall clock was lost.
- **Fix:** `caffeinate -dimsu -w <pid>` held against the run's PID for the rest of the job.
- **Consequence, reported rather than hidden:** the JSON's top-level `wall_clock_s` of 22,385.3 s
  is `time.time()` and includes the sleep; the trajectory's per-epoch elapsed times are
  `time.monotonic()` and exclude it. The evidence quotes the monotonic figures as the compute time
  and explains the discrepancy.

### Deliberate departures

**3. The pre-registered inertness check came back NEGATIVE and is published as such.** The
pre-registration said that if `max_log_rate_per_epoch` stayed below 20 the stabilizer provably
never activated and the epoch budget would be the only variable. It did not stay below 20: it hit
69.94 at pooled epoch 6 and 149.32 in a fold. So this run has two variables, not one, and the
movement from 0.0713 to 0.4096 is not attributable to the budget alone. The evidence says that
outright rather than leaning on the bit-identity proof to imply otherwise.

**4. The headline was NOT changed to the plateau mean**, which is the better estimator. The
pre-registration said the headline is the value at the cap. Switching to an average after seeing
that the curve oscillates would be choosing an estimator from the data. The spread is published
beside the value instead, so a reader can do the averaging with full information.

**5. The rotation ran at 60 epochs against the pooled 200**, pre-registered as a cost decision and
labeled as one in the JSON (`loso_summary.budget_note`), in the evidence and here. A full-cap
rotation is about 11.5 h of CPU on top of the 4.2 h headline.

**6. The committed slow gate was NOT executed.** The evidence and the deferred items say the
failure mode is "very likely" gone on the evidence of the replay, and that whether the gate reaches
and passes its assertion was not measured. Its threshold was not lowered; the margin was re-derived
upward by the unchanged rule.

## Issues Encountered

**The stabilizer was supposed to be a free guard and turned out to be a second variable.** That is
the one thing this task hoped to avoid and did not. It is bounded rather than unbounded -- the
guard is bit-identical below its threshold and epochs 1 to 5 reproduce 09-06c exactly -- but the
attribution the pre-registration wanted is not available, and no experiment can recover it, because
the counterfactual run is the one that produces `nan`.

**The metric is much noisier than any previous arm could have revealed.** Every earlier arm reported
a single number from inside the monotone climb, where the curve is well behaved. At the plateau the
sample-to-sample spread is +/-0.09, which is larger than the entire measured difference between
several pairs of arms in this chain's history. Any future comparison of two co-bps values from this
setup that differ by less than about 0.1 should be treated as indistinguishable.

**A session limit interrupted the task twice**, once mid-run and once between the rotation
finishing and the write-up. No compute was lost either time: the run was detached with `nohup`, the
JSON and the JSONL sidecar were already on disk, and the trajectory in the committed JSON was
checked against the run log before anything was built on it.

## Deferred Items

Four, in `deferred-items-09-06d.md`: the slow gate's disposition, updated with what the replay
shows and what it does not; the reduced rotation budget and the roughly 11.5 h of CPU that would
close it; the per-session structural limits, where the argument is now that more SESSIONS rather
than more epochs is the binding constraint; and the absence of any error bar anywhere in this
artifact. `deferred-items-09-06c.md` items 1 and 4 are closed by this task, item 1 by
implementation and item 4 by removal; its items 2 and 3 remain open.

## Known Stubs

None. No placeholder value, hardcoded empty result, mock payload or unwired path was introduced.
Every number in this summary and in `09-training-evidence.md` came from a run that executed on the
four manifest-pinned real sessions. Values that could be mistaken for results are labeled where
they appear: the `visible_*` diagnostic columns (out of distribution for a checkpoint trained on
hidden inputs), the LOSO `train_null` column (the wrong null for the transfer question), and the
smoke-mode outputs (`data_source: real-smoke`, never committed).

## Threat Flags

None. No new network endpoint, auth path, file access pattern or schema change at a trust boundary.
No dataset byte and no checkpoint entered git. Checkpoints remain state-dict only, gitignored, and
loaded through `torch.load(weights_only=True)`.

T-09-06-05 (tuning toward a threshold) is the disposition this task was most exposed to, and the
mitigations are structural rather than intentional: the run has no stopping rule to tune, the cap
and the sampling interval and the rotation budget were committed before the run, the checkpoint
saved is the model at the cap rather than the best epoch, the loss threshold was fixed by the data
range and float32 rather than by any co-bps, the margin was re-derived upward by a rule unchanged
across four applications, the red gate was not made green by lowering its threshold, and the
pre-registered inertness check was reported when it failed.

## Verification

```
uv run --project Decoder pytest Decoder/tests/test_loss_stability.py -q        -> 3 failed, 7 passed (RED, before the fix)
uv run --project Decoder pytest Decoder/tests/test_loss_stability.py -q        -> 10 passed (after)
uv run --project Decoder pytest Decoder/tests -m "not slow" -q                 -> 189 passed, 9 deselected
uv run --project Decoder ruff check Decoder                                    -> All checks passed
uv run --project Decoder python Decoder/scripts/train_real.py --smoke          -> 0
uv run --project Decoder python Decoder/scripts/train_real.py --only-loso ...  -> 0 (validation at --loso-epoch-cap 1)
uv run --project Decoder python Decoder/scripts/train_real.py --skip-loso      -> 0 (15,043 s, 200 epochs)
uv run --project Decoder python Decoder/scripts/train_real.py --only-loso      -> 0 (14,836 s, 4 folds x 60 epochs)
uv run --project Decoder python Decoder/scripts/train_real.py --diagnostic     -> 0
uv run --project Decoder python Decoder/scripts/train_real.py --derive-margin  -> 0 (0.054)
uv run --project Decoder python Decoder/scripts/diagnose_divergence.py --epochs 8 -> 0 (finite through epoch 8)
git status --porcelain Decoder/checkpoints Decoder/data                        -> 0 lines
```

The slow gate was NOT run under this plan; see "Deliberate departures" item 6.

Plan 09-06's verification greps still hold: `April to June 2016` absent, the two forbidden `mc_rtt`
phrasings absent, `photodiode|24.7` absent, `0.3804` present, `indy_20170202_02` present.

## Next Phase Readiness

- **Plan 09-07 (velocity readout)** inherits a substantially different encoder:
  `Decoder/checkpoints/ndt1_real_pooled.pt`, sha256
  `f95b257bf2479b49102a2d8afee3c46d9008c51ba754d42a60a26762b7d3af8e`, 200 epochs instead of 12 and
  a pooled co-bps 5.7x higher. Any lag sweep or readout fit against the 09-06c checkpoint must be
  re-run. It should also size its own budget from this run's trajectory rather than from Phase 4's
  12 epochs, which this work has now shown to be far short.
- **Plan 09-09 (`decoder-policy.sh`)** inherits a red slow gate whose training path very likely
  survives now, plus a margin at 0.054 with real room under it. The recommendation and its one
  weakened clause are in `deferred-items-09-06d.md` item 1.
- **Plan 09-10 (citation sweep)** has a four-link chain to label AND a falsified claim to find:
  any document asserting that NDT1 does not beat a mean-rate null on real M1 spikes is now
  contradicted by this file.
- **Open constraint on everything downstream:** 0.4096 / 0.3814 may be quoted only as the POOLED,
  200-epoch, WITHIN-POOL held-out values, with the +/-0.09 sampling caveat and with the
  cross-session result attached. The LOSO `train_null` mean of +0.2446 must never be quoted as
  cross-session transfer. 0.0713, 0.0062 and 1.9116 keep the restrictions their supersession
  records state. Nothing here may be set against NLB'21's 0.147 to 0.192 as a comparison, in
  either direction.

## Status rationale

`PARTIAL`, not `PASS`. Every step of the corrective task completed: the loss was stabilized and
proven bit-identical below its threshold, the run plan was pre-registered and committed before the
run, the full 200-epoch run and a complete four-fold rotation executed, the trajectory was
published, every dependent number was re-derived by code, and the four-link supersession chain is
intact. Four flagged gaps prevent a clean `PASS`:

1. **The stabilizer was not inert**, so this run carries two changes and the movement from 0.0713
   is not attributable to the budget alone. The counterfactual cannot be run.
2. **The reported value is one sample from a plateau with +/-0.09 of spread**, and the
   pre-registered cap value happens to sit 12th of 14 in that band. A precise headline would need a
   pre-registered plateau estimator this run does not have.
3. **The rotation ran at 30% of the headline's budget**, a declared cost decision, so the four
   cross-session numbers are floors.
4. **The committed slow gate is still RED and was not executed**, so its disposition rests on a
   replay rather than on a run of the test.

## Self-Check: PASSED

Files claimed, verified present:
- `Decoder/tests/test_loss_stability.py` FOUND
- `Decoder/tests/test_cobps_trajectory.py` FOUND
- `.planning/phases/09-.../deferred-items-09-06d.md` FOUND
- `.planning/phases/09-.../09-06d-SUMMARY.md` FOUND
- `Decoder/src/ndt1/loss.py`, `Decoder/src/ndt1/train.py`, `Decoder/scripts/train_real.py` FOUND (modified)
- `Decoder/tests/test_heldout_cobps.py`, `test_cobps_margin.py` FOUND (modified)
- `.planning/phases/09-.../09-decoder-metrics.json`, `09-training-evidence.md` FOUND (modified)

Commits claimed, verified in `git log`: `e079218`, `f3dd2a2`, `033393e`, `06eb61f`, `f2835e0`,
`967f38e`, `15c9817` all FOUND.

Commit ORDERING verified, which is the load-bearing claim of this task:
`git merge-base --is-ancestor 06eb61f 967f38e` exits 0, so the run plan was committed before the
commit carrying the numbers it produced, and the training process did not start until after.

Number provenance verified rather than trusted: the committed `co_bps.trajectory` array was checked
against the 21 `co-bps @ epoch` lines in the run log; the trajectory's epoch-200 row equals the
post-training pooled score to full double precision; and `--diagnostic`'s `hidden_*` columns
reproduce every published per-session and pooled figure to full double precision from a checkpoint
reloaded off disk.

`git status --porcelain Decoder/checkpoints Decoder/data` returns 0 lines. `git ls-files` matches no
`.pt` and exactly one `.mat`, `Decoder/tests/fixtures/tiny_v73.mat`, the Plan 09-02 CI fixture,
untouched by this task.
