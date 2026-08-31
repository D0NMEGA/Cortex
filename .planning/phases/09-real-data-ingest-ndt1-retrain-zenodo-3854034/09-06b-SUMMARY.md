---
status: PARTIAL
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 06b
subsystem: decoder
tags: [ndt1, masked-modeling, co-bps, poisson-nll, tdd, regression-test, indy, loso, evidence]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 06
    provides: "the pooled real-data retrain, train_real.py, 09-decoder-metrics.json, 09-training-evidence.md, and the deferred item this task closes"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 05
    provides: "1,767,820,363 bytes of manifest-pinned real Indy M1 data under Decoder/data/"
provides:
  - "A masked-modeling objective that actually hides what it scores: ndt1.train.masked_forward + ndt1.loss.hide_scored_positions, applied identically in training and in every scoring path"
  - "Decoder/tests/test_masked_input_isolation.py: a perturbation-based regression test that fails if a scored position's own value can influence its own prediction, plus an anti-degenerate check"
  - "The first context-only co-bps this repository has measured: pooled 0.0062 (train-split null) / -0.0219 (test-mean null) on real primate M1 spikes"
  - "A four-fold LOSO rotation under the corrected objective: -0.4852 mean over three finite folds, every one negative under the drift-robust null"
  - "CO_BPS_MARGIN re-derived to 0.00082 by unchanged code from the new observation"
  - "superseded_visible_input_objective in 09-decoder-metrics.json: the 09-06 numbers preserved, labeled, and carried across re-runs by train_real.py"
  - "A measured account of what the defect was worth: leaking the scored counts buys 0.064 bits/spike on the corrected checkpoint against about 7.4 on the superseded one"
affects: [09-07, 09-08, 09-09, 09-10, 09-11, RD-05, RD-06, decoder-policy.sh, 04-training-evidence.md citations]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One function builds the encoder input for training and for every scoring path, so train/eval consistency is structural rather than a convention two call sites have to remember"
    - "A structural property is guarded by a perturbation probe, not a source grep: change the input at the positions under test and assert the output cannot move"
    - "Every regression test for an isolation property carries its anti-degenerate twin, so a model that ignores its input cannot satisfy the property for the wrong reason"
    - "A superseded number is preserved under a named key with the defect, a warning and a pointer to its replacement, and the runbook carries that key across re-runs so it cannot be lost by re-executing"
    - "Assertions that establish a result is meaningful run BEFORE assertions about its value, so a diverged run reports the divergence instead of a meaningless number"

key-files:
  created:
    - Decoder/tests/test_masked_input_isolation.py
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/deferred-items-09-06b.md
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-06b-SUMMARY.md
  modified:
    - Decoder/src/ndt1/loss.py
    - Decoder/src/ndt1/train.py
    - Decoder/src/ndt1/model_ane.py
    - Decoder/scripts/train_real.py
    - Decoder/tests/test_heldout_cobps.py
    - Decoder/tests/test_cobps_margin.py
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-decoder-metrics.json
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-training-evidence.md
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-06-SUMMARY.md

key-decisions:
  - "Zero-masking rather than a learned mask embedding. It keeps NDT1ANE.forward a single tensor in and single tensor out, so the Phase-5 Core ML conversion path and the guarded 1,292,544 parameter count are untouched; the cost is that zero is a legitimate spike count, which biases predictions downward and makes the reported co-bps a lower bound"
  - "Every scored position is corrupted, not the 80% NDT and BERT use. The unchanged fraction is precisely the leak being removed; the train/serve mismatch it would have bought back is accepted and recorded"
  - "The RED commit is a real one. masked_forward was extracted with the defective body first so the new test failed on numbers rather than on a missing import, which is what proves the probe discriminates"
  - "The epoch budget was NOT raised even though the loss curve has not converged and D-14's raise-the-budget branch would fire. A longer budget is a second variable in a task designed to change one, and it moves the number in the flattering direction"
  - "Gradient clipping was NOT added despite three observed divergences. It would change every number in this file and confound the objective correction with an optimization change; it is written up as a decision instead"
  - "The margin derivation RULE is unchanged; only the observation it reads moved. Re-deriving under a rule chosen after seeing the corrected number is the tuning D-22 exists to prevent"
  - "D-14 comparability with Phase 4's 0.3804 is deliberately abandoned rather than preserved, because 0.3804 came out of the same defective objective"

patterns-established:
  - "Correct a published number by labeling the old one, never by deleting it: superseded_visible_input_objective carries the defect, the warning and the replacement, and a quick test fails if the record is removed"
  - "When a generated rationale makes a claim the number no longer supports, fix the generator rather than the number"

requirements-completed: []

# Metrics
duration: 2h 20m
completed: 2026-08-31
---

# Phase 9 Plan 06b: the masked-modeling objective, corrected Summary

**The encoder could read every position it was scored on, so co-bps 1.9116 was measuring
self-reconstruction; with the scored positions hidden and every other hyperparameter unchanged, the
pooled held-out value is 0.0062 against the gate null and -0.0219 against the drift-robust null,
which means this NDT1 does not beat a constant per-channel mean firing rate.**

## Performance

- **Duration:** about 2h 20m (2026-08-31, 09:50 to 12:10 local CDT; first commit 10:04:39, last
  12:07:50), of which roughly 1h 50m was CPU: a 61-minute full run, a 14-minute reproducibility
  re-run, and two 15-minute slow-gate executions
- **Tasks:** 4 of 4 (fix, regression test, retrain, re-derive)
- **Files:** 3 created, 9 modified
- **Commits:** 6 task commits (listed below), plus metadata corrections to this summary

## Accomplishments

### The defect, confirmed and closed

`ndt1.train.train_ndt1` drew a mask and then ran the encoder on the unmasked counts:

```python
mask = random_mask(targets.shape, mask_ratio, generator=mask_gen).to(dev)
rates = model(targets)                                    # the true counts, at every position
loss = masked_poisson_nll(rates, targets, mask, log_input=log_input)
```

`evaluate_co_bps` and `train_real.py`'s `_score` did the same, and `NDT1ANE.forward` performs no
input masking. `random_mask` returns `True` where the loss IS computed, so the mask selected what
was scored and nothing else. Every co-bps this repository had published measured self-reconstruction
plus context.

`ndt1.train.masked_forward` is now the single place the encoder input is built, in training and in
every scoring path, and it runs the model on `ndt1.loss.hide_scored_positions(targets, mask)`.
`targets` is untouched, so the loss still scores against the true counts.

### The regression test, genuinely RED first

`Decoder/tests/test_masked_input_isolation.py`, five quick tests, no dataset. The discriminating
probe perturbs the counts at the scored positions and asserts the prediction there does not move by
a single bit. To make the RED behavioural rather than an ImportError, `masked_forward` was extracted
with the defective body first, wired into both call sites with no behaviour change (145 pre-existing
tests stayed green), and only then fixed. The RED run:

```
3 failed, 2 passed
- a scored position's own count moved its prediction
- 23 of 28 scored positions reached the encoder during training
- 40 of 51 scored positions reached the encoder during evaluation
```

The two that already passed are the anti-degenerate direction, so a model that ignored its input
entirely could not have satisfied the isolation property for the wrong reason. The trainer and
evaluator are checked by recording what actually reached the encoder, not by grepping source, so a
fix applied to one call site and not the other fails.

### The corrected numbers

| Quantity | Superseded (visible input) | Corrected (hidden input) |
|---|---|---|
| Pooled held-out co-bps, `train_null` | 1.9116 | **0.0062** |
| Pooled held-out co-bps, `test_mean_null` | 1.8834 | **-0.0219** |
| Per-session range, `test_mean_null` | 1.6500 to 1.9540 | -0.3820 to 0.2084 |
| LOSO mean, finite folds, `test_mean_null` | 1.5110 | **-0.4852** |
| Final training loss | 0.2439 (43% reduction) | 0.5584 (6% reduction) |
| Gain from leaking the scored counts back in | about 7.4 bits/spike | 0.064 bits/spike |
| `CO_BPS_MARGIN` | 0.25 | **0.00082** |

Three of the four sessions are negative under the drift-robust null; only `indy_20160915_01` is
positive, and it is the smallest session at 119 held-out windows. Every finite LOSO fold is negative.
Hyperparameters are byte-for-byte the ones Plan 09-06 used, so the objective is the only variable.

### What the defect was worth, measured

`--diagnostic` re-scores a checkpoint with the scored counts leaked back into the encoder. On the
corrected checkpoint that leak buys **0.064** bits/spike pooled (0.0062 to 0.0701). On the superseded
checkpoint the same leak was worth about **7.4** (-5.5266 to 1.9116). A model trained with the
answers visible learns to copy them and collapses when they are taken away; one trained without them
gains almost nothing when they are handed back. The superseded 1.9116 was almost entirely
self-reconstruction.

### A free internal check on the re-measurement

The `train_null` to `session_train_null` gaps are 0.2010, 0.0336, 0.5632, 0.4310 under the corrected
objective and were 0.2011, 0.0336, 0.5632, 0.4309 before. A difference between two co-bps values
scored against different nulls on the same mask cancels the model term exactly, so those gaps are a
property of the data. Their invariance is evidence that the re-measurement changed the model and
nothing else, and it preserves 09-06's three-null conclusion that the gap between the gate null and
the drift-robust null is cross-session heterogeneity rather than within-session drift.

### Reproducibility

The pooled training run was executed twice, an hour apart, the second time into a scratch checkpoint
directory. The checkpoint SHA-256 is byte-identical
(`0496a72cc0878bc01e77968b28a9dfeee68f0ac4fd09c8d0537a95b801b4b209`), as are all 12 per-epoch losses
and every per-session and pooled co-bps. The LOSO rotation was executed once and has no independent
replication here; that is stated in the evidence rather than glossed.

## Task Commits

1. **RED: the failing isolation test plus the behaviour-preserving extraction** - `186f710` (test)
2. **The objective fix in train and eval** - `2866ce4` (fix)
3. **The scoring paths that produce the published numbers** - `94fcdbd` (fix)
4. **The retrain and every re-derived number** - `6fc194f` (feat)
5. **A relative --checkpoint-dir aborting the run at the JSON write** - `29a415c` (fix)
6. **The corrected artifacts, and the red slow gate reported** - `4d3f6b1` (docs)

## Files Created/Modified

- `Decoder/src/ndt1/loss.py` - `hide_scored_positions`, whose docstring records the masking choice
  and its cost. Module docstring corrected: it described an objective the code did not implement.
- `Decoder/src/ndt1/train.py` - `masked_forward`; both call sites routed through it. Module
  docstring corrected.
- `Decoder/src/ndt1/model_ane.py` - one docstring line: `forward` never applies `mask_ratio`, and
  why the input corruption belongs to the objective rather than to the graph.
- `Decoder/scripts/train_real.py` - `_score` hides the scored positions; the `--diagnostic` labels
  swap roles and its note is rewritten; `_carry_superseded` preserves the old record across re-runs;
  `_repo_relative` fixes the crash; the D-14 comparability rationale is replaced.
- `Decoder/tests/test_masked_input_isolation.py` (created, 205 lines) - the regression test.
- `Decoder/tests/test_heldout_cobps.py` - scores through `masked_forward`; `CO_BPS_MARGIN` 0.25 to
  0.00082; the "did it train" assertions moved ahead of the co-bps assertion.
- `Decoder/tests/test_cobps_margin.py` - two tests added: the margin is not the superseded 0.25, and
  the superseded record is still present and labeled.
- `09-decoder-metrics.json` - corrected `co_bps`, `losses`, `loso`, `loso_summary`, `checkpoint`;
  the old numbers under `superseded_visible_input_objective` with the defect and a warning.
- `09-training-evidence.md` - a correction section, and every number section re-derived.
- `09-06-SUMMARY.md` - a superseded banner at the top and a correction section at the end.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 1 - Bug] The margin rationale generator asserted something the number did not support**

- **Found during:** the margin re-derivation
- **Issue:** `--derive-margin` emitted, unconditionally, that the margin was "high enough above the
  0.0 null to mean something, low enough below the observation that run-to-run variation cannot
  flake the gate". That was true of 0.25 against 1.9116. Applied to 0.00082 it is false, and it
  would have had the committed artifact vouch for a gate the number does not support.
- **Fix:** the generator now states what the derivation did and what the gate therefore asserts, and
  leaves the judgment to the reader with the observation printed beside it. **The margin value and
  the derivation rule are unchanged.**
- **Committed in:** `6fc194f`

**2. [Rule 1 - Bug] A relative `--checkpoint-dir` aborted the run at the JSON write**

- **Found during:** the training-path determinism check
- **Issue:** `Path.relative_to` compares the literal string against an absolute root, so
  `--checkpoint-dir Decoder/checkpoints/repro` raised `ValueError` while building the payload, after
  15 minutes of training. The checkpoint survived; the JSON did not.
- **Fix:** `_repo_relative` resolves first and falls back to the absolute path outside the repo.
- **Verification:** the reproducibility numbers were recovered from the log and the saved
  checkpoint; nothing was re-run to produce them.
- **Committed in:** `29a415c`

**3. [Rule 2 - Missing critical] A diverged run reported a meaningless co-bps as a verdict**

- **Found during:** the slow real-data gate
- **Issue:** the gate's `heldout_co_bps > CO_BPS_MARGIN` assertion ran before its "did it train"
  assertion, so a diverged run failed with "held-out co_bps -1576.77256 did not beat the mean-rate
  null", which reads as a catastrophic model rather than as a training blow-up.
- **Fix:** the two "did it train" checks (a finiteness check, and the `losses[-1] < losses[0]`
  assertion that was already in the test) now run first. **The co-bps assertion and the margin are
  unchanged and the test still fails.** Only the reported first cause changed.
- **Verification:** the gate was re-executed after the change rather than having its new output
  predicted. It reproduced the divergence to full precision and now reports "the loop did not
  train: final loss 4.67701e+22 is not below the first epoch's 0.603385".
- **Committed in:** `4d3f6b1`

### Deliberate departures

**4. The epoch budget was not raised, although D-14 says it should be.** The loss curve descends
monotonically to the last epoch at about 0.0007 per epoch with no oscillation, so by the criterion
09-06 used it has not converged and D-14's raise-the-budget branch fires. It was not raised: a
longer budget is a second variable in a task whose mandate was to change exactly one, and it moves
the number upward. 0.0062 is a 12-epoch number under an objective that had not finished fitting, not
an asymptote. Stated in the evidence as the first gap.

**5. Gradient clipping was not added, although three runs diverged.** Written up as a decision in
`deferred-items-09-06b.md` instead. Applying it inside the objective correction would confound two
changes and leave no way to attribute a difference to either.

**6. D-14 comparability with Phase 4's 0.3804 was abandoned rather than preserved.** Authorized by
the task: 0.3804 came out of the same defective objective, so comparability to it was never
meaningful. Every hyperparameter is still Phase-4-verbatim, for a different reason.

## Issues Encountered

**The slow real-data gate is RED, and the reason is divergence rather than model quality.**
`test_heldout_cobps_beats_mean_rate_null` trained cleanly for seven epochs, blew up at epoch 8
(21301.74), partially recovered (26.63, 22.93), then exploded to 1.49e22 and 4.68e22, and produced
`held_out_co_bps = -1576.77256`. That number describes the divergence, not the model. Reported, not
repaired: the remedies are gradient clipping or a lower learning rate, both of which this task is
explicitly forbidden from applying, and both of which would move every other number in the artifact.

This is the third instance of the same instability. The `log_input=True` Poisson NLL has model term
`exp(rate) - target * rate`, so a predicted log-rate excursion overflows, and AdamW at `lr = 2e-3`
with no clipping has nothing to arrest it. It appeared once under the superseded objective (one LOSO
fold, silent NaN at epoch 12) and twice under the corrected one (a different LOSO fold, blowing up
at epoch 7; and this gate at epoch 8). **The corrected objective is measurably less stable at this
learning rate**, which is the expected consequence of a harder prediction problem and is itself a
finding.

**The divergence moved between objectives.** Under the superseded objective the fold holding out
`indy_20160624_03` diverged; under the corrected one that fold completes and the fold holding out
`indy_20160627_01` diverges instead. So it is not a property of one session's data.

## Deferred Items

Three, in `deferred-items-09-06b.md`: gradient-norm clipping as a decision rather than a repair; the
fact that co-bps and its margin can now both be legitimately non-positive and that
`decoder-policy.sh` needs to say which it expects; and the train/serve mismatch introduced by 100%
zero-masking. Item 1 of `deferred-items-09-06.md` is closed by this task; its item 2 remains open.

## Known Stubs

None. No placeholder value, hardcoded empty result, mock payload or unwired path was introduced.
Every number in this summary and in `09-training-evidence.md` came from a run that actually executed
on the four manifest-pinned real sessions. None is estimated or extrapolated. The two figures that
could be mistaken for results and are not are labeled as such in the evidence: the `visible` column
of the diagnostic (out of distribution for a checkpoint trained on hidden inputs) and the slow
gate's -1576.77 (a divergence artifact).

## Threat Flags

None. No new network endpoint, auth path, file access pattern or schema change at a trust boundary.
No dataset byte entered git. Checkpoints remain state-dict only, gitignored, and loaded through
`torch.load(weights_only=True)`.

Two of Plan 09-06's `mitigate` dispositions were strengthened rather than weakened. T-09-06-01
(reproducibility) now rests on a byte-identical checkpoint SHA-256 across two independent training
runs plus an independent evaluation-path replay. T-09-06-05 (tuning toward a threshold) is the one
this task was most exposed to, and the places where tuning would have helped are all named and all
declined: the epoch budget, gradient clipping, the choice of null, and the margin derivation rule.

## Verification

```
uv run --project Decoder pytest Decoder/tests/test_masked_input_isolation.py -q   -> 3 failed, 2 passed (RED, before the fix)
uv run --project Decoder pytest Decoder/tests/test_masked_input_isolation.py -q   -> 5 passed (after)
uv run --project Decoder pytest Decoder/tests -m "not slow" -q                    -> 152 passed, 9 deselected
uv run --project Decoder ruff check Decoder                                       -> 0
uv run --project Decoder python Decoder/scripts/train_real.py --smoke             -> 0
uv run --project Decoder python Decoder/scripts/train_real.py                     -> 0 (3673 s)
uv run --project Decoder python Decoder/scripts/train_real.py --diagnostic        -> 0
uv run --project Decoder python Decoder/scripts/train_real.py --derive-margin     -> 0
uv run --project Decoder pytest -m slow -k test_heldout_cobps -q                  -> 1 FAILED (training diverged)
node -e "JSON.parse(09-decoder-metrics.json)"                                     -> parses, 0 NaN tokens
git status --porcelain Decoder/checkpoints Decoder/data                           -> 0 lines
```

Both of Plan 09-06's verification snippets still pass verbatim (`metrics JSON OK`, `evidence OK`),
as do its negative greps: `April to June 2016` absent, the two forbidden mc_rtt phrasings absent,
`photodiode|24.7` absent, `0.3804` present, `indy_20170202_02` present.

## Next Phase Readiness

- **Plan 09-07 (velocity readout)** has a new pooled checkpoint at
  `Decoder/checkpoints/ndt1_real_pooled.pt`, sha256
  `0496a72cc0878bc01e77968b28a9dfeee68f0ac4fd09c8d0537a95b801b4b209`. It is a different model from
  the one 09-06 produced and any lag sweep must be re-run against it. A near-zero reconstruction
  co-bps does not by itself predict a poor velocity decode, and 09-07 is the number that speaks to
  the project's goal. If its R^2 disappoints, `deferred-items-09-06b.md` item 3 (the train/serve
  mismatch from 100% zero-masking) is the first thing to test.
- **Plan 09-09 (`decoder-policy.sh`)** needs a decision this task surfaced: `co_bps.margin` is now
  0.00082 and the observation it guards is 0.0062, so a threshold gate on co-bps asserts almost
  nothing. Whether that is the right shape of assertion is logged in `deferred-items-09-06b.md`.
- **Plan 09-10 (citation sweep)** has more to do than it was planned for. `04-training-evidence.md`'s
  0.3804 is now superseded twice over, on synthetic data AND under the defective objective, and any
  document quoting 1.9116 must point at `09-training-evidence.md`. `.planning/PROJECT.md`,
  `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md` and the Phase 4 and Phase 5 artifacts were
  deliberately left untouched.
- **Open constraint on everything downstream:** 1.9116 is not a decoder result and must not be
  quoted as one. 0.0062 may be quoted, with the budget caveat attached.

## Status rationale

`PARTIAL`, not `PASS`. Every step of the corrective task completed: the objective is fixed in train
and eval, the regression test discriminates and was RED first, the retrain ran with one variable
changed, and every dependent number was re-derived by code. Three flagged gaps prevent a clean
`PASS`:

1. **The slow real-data gate is red** because its training run diverged. Reported rather than
   repaired, because the remedies are the ones this task is forbidden to apply.
2. **The loss curve had not converged** at the 12-epoch budget, so 0.0062 is a floor at this budget
   rather than an asymptote, and D-14's raise-the-budget branch was declined on purpose.
3. **One of four LOSO folds diverged**, so the rotation summary rests on three folds; and the
   rotation itself was executed once, without the independent replication the pooled run has.

## Self-Check: PASSED

Files claimed, verified present:
- `Decoder/tests/test_masked_input_isolation.py` FOUND
- `Decoder/src/ndt1/loss.py`, `train.py`, `model_ane.py` FOUND (modified)
- `Decoder/scripts/train_real.py` FOUND (modified)
- `Decoder/tests/test_heldout_cobps.py`, `test_cobps_margin.py` FOUND (modified)
- `.planning/phases/09-.../09-decoder-metrics.json` FOUND
- `.planning/phases/09-.../09-training-evidence.md` FOUND
- `.planning/phases/09-.../09-06-SUMMARY.md` FOUND (corrected)
- `.planning/phases/09-.../deferred-items-09-06b.md` FOUND

Commits claimed, verified in `git log`: `186f710`, `2866ce4`, `94fcdbd`, `6fc194f`, `29a415c` all
FOUND. `Decoder/data/` and `Decoder/checkpoints/` untracked throughout; no `.mat` and no `.pt`
entered git.

---
*Phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034*
*Completed: 2026-08-31*
