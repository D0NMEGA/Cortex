---
status: PARTIAL
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 06c
subsystem: decoder
tags: [ndt1, gradient-clipping, convergence, pre-registration, co-bps, poisson-nll, loso, indy, evidence, tdd]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 06b
    provides: "the corrected input-masking objective, the 12-epoch unclipped numbers this task supersedes, and the deferred gradient-clipping decision it acts on"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 05
    provides: "1,767,820,363 bytes of manifest-pinned real Indy M1 data under Decoder/data/"
provides:
  - "Gradient-norm clipping on by default in ndt1.train.train_ndt1 (DEFAULT_GRAD_CLIP_NORM = 1.0), guarded by Decoder/tests/test_grad_clipping.py"
  - "ndt1.train.loss_plateaued: a convergence rule defined on the training loss alone, which structurally cannot see the metric being reported"
  - "A stopping rule PRE-REGISTERED in 09-training-evidence.md and committed before the run that reads it, with the commit ordering as the check"
  - "The first co-bps this repository has measured with the numerics named and guarded: pooled 0.0713 (train null) / 0.0432 (pooled test-mean null)"
  - "A diagnosed root cause for the remaining instability: a forward-pass log-rate excursion that overflows float32 exp above 88.7, with the exploding gradient as its consequence one step later"
  - "Decoder/scripts/diagnose_divergence.py: a committed, re-runnable per-step probe for that diagnosis"
  - "convergence.fired_at_floor and the per-epoch relative changes in 09-decoder-metrics.json, so a stopping decision is recomputable rather than taken on trust"
  - "train_real.py --supersede-current and prefix-based carry, so a supersession chain cannot lose a link across a re-run"
  - "CO_BPS_MARGIN re-derived to 0.0094 by the thrice-unchanged rule"
  - "09-budget-probe.json: a pre-registered 60-epoch probe showing the published budget left a 4.2x co-bps increase on the table, and that a plateau rule on the masked Poisson NLL is a poor proxy for convergence of co-bps"
affects: [09-07, 09-08, 09-09, 09-10, 09-11, RD-05, RD-06, decoder-policy.sh]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A stopping rule is pre-registered in a committed artifact BEFORE the run, and is defined on a quantity that is not the one being reported, so it structurally cannot be tuned toward the result"
    - "A predicted fix is verified against the real failure it was predicted to fix, and the verification is allowed to come back negative"
    - "The probe that produced a diagnosis is committed as a script, so the transcript in the evidence is re-runnable rather than trusted"
    - "A stopping decision records the numbers the rule inspected, plus whether it fired at its own floor, so a weak stop cannot be read as a strong one"
    - "A superseded record is carried by key PREFIX rather than by name, so the next correction only has to write its own block"
    - "A pre-registered rule that turns out to be wrong is reported as wrong and left in place for the run it governed, with the replacement deferred, rather than retuned once its output is visible"

key-files:
  created:
    - Decoder/tests/test_grad_clipping.py
    - Decoder/tests/test_plateau_stop.py
    - Decoder/scripts/diagnose_divergence.py
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/deferred-items-09-06c.md
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-budget-probe.json
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-06c-SUMMARY.md
  modified:
    - Decoder/src/ndt1/train.py
    - Decoder/scripts/train_real.py
    - Decoder/tests/test_heldout_cobps.py
    - Decoder/tests/test_cobps_margin.py
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-decoder-metrics.json
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-training-evidence.md

key-decisions:
  - "The stopping rule is defined on the training loss and takes no other argument, so loss_plateaued cannot see a co-bps. Stopping where the headline metric peaks is the exact failure this task existed to avoid, and making it impossible beats promising not to do it"
  - "The rule was written into the evidence and committed BEFORE the run, in its own commit, so git log is the audit trail rather than a claim in prose"
  - "max_norm = 1.0 was kept as the a-priori convention even after it was measured NOT to fix the failure it was deferred for. Choosing a clip value from observed gradient norms after seeing the divergence would be tuning a knob against the thing being reported"
  - "The rule fired at MIN_EPOCHS. The floor was NOT moved afterwards; a subordinate budget probe was pre-registered instead, and the pre-registered run stays the headline whichever number is larger"
  - "The diverged LOSO fold was allowed to run out its full 60-epoch cap producing nan rather than being killed early, because terminating a run early is a protocol change and the pre-registration said otherwise"
  - "masked_poisson_nll was NOT changed even though the diagnosis points straight at it. This task already changes two things; a third would make the number attributable to none of them"
  - "The margin was re-derived by the unchanged rule, not chosen. Third re-derivation, same multiplication, only the observation moves"
  - "The slow gate was left RED and was not made green by lowering its threshold. It fails before reaching the threshold at all"
  - "The stopping rule was NOT retuned after the probe showed it fires far too early. It was applied as written, its failure was measured and published, and the replacement was deferred with the property a replacement must preserve"
  - "The 12-epoch run stays the published headline even though the 60-epoch probe is a much better number, because the pre-registration said so before either was known and because the checkpoint, margin and rotation all correspond to it"

patterns-established:
  - "Verify a deferred fix against the real failure before believing the write-up that deferred it: the 09-06b prediction that clipping would fix the rotation was checked and was wrong"
  - "Record whether a convergence rule fired at its own floor, because 'stopped on the plateau criterion' and 'stopped at the earliest epoch allowed' read identically in a stop_reason field and mean very different things"

requirements-completed: []

# Metrics
duration: about 7h 50m wall, of which 5h 30m was CPU
completed: 2026-09-01
---

# Phase 9 Plan 06c: convergence, clipping, and what the numbers actually support Summary

**The answer to "does NDT1 beat a per-channel mean firing rate on real M1 spikes" turns out to
depend on how long it is trained: at the 12 epochs the pre-registered rule stopped at, pooled
co-bps is 0.0713 (from 0.0062) but the model still loses to each session's own mean on three
sessions of four; at 60 epochs, in a supplementary probe pre-registered before it was run, pooled
co-bps is 0.3002 and it loses on only one of four. The rule fired at its floor, so the entire
published gain is the gradient clip and none of it is the budget, and the probe shows the budget
was worth about three and a half times more than the clip.**

## Performance

- **Duration:** about 7h 50m wall (2026-08-31 22:40 to 2026-09-01 04:00 local, with a
  rate-limit interruption in the middle), of which about 5h 30m was CPU: a 2h 43m full training
  run (9777.7 s), a 69-minute budget probe (4137.8 s), a 15-minute slow-gate verification, a
  12-minute per-step divergence diagnosis, and short diagnostic and margin passes
- **Tasks:** 5 of 5 (clip, pre-register, retrain, re-derive, gate disposition)
- **Files:** 6 created, 6 modified
- **Commits:** 12

## Accomplishments

### Gradient clipping, applied and then actually checked

`torch.nn.utils.clip_grad_norm_` at `max_norm = 1.0` on every optimizer step, on by default.
`Decoder/tests/test_grad_clipping.py` (5 quick tests) holds it in place with a spy that proves the
clip runs on every step, at the documented norm, and is binding rather than decorative, plus a
behavioural pair on a batch where the guard changes the outcome and a control proving the unclipped
loop fails on it.

The RED was behavioural, not an `ImportError`: opt-in clipping was plumbed through first with the
default OFF, which changed no existing number (152 quick tests stayed green), and only then was the
default flipped. The RED run:

```
2 failed, 2 passed
- training went non-finite with the default clip: per-epoch loss [34614185984.53748, nan, nan, nan, nan, nan]
- clip_grad_norm_ ran 0 times for 12 optimizer steps
```

**`deferred-items-09-06b.md` predicted clipping "would very likely" fix the divergences. It was
verified rather than assumed, and the prediction was wrong.** On the committed slow gate the clip
moves the failure from epoch 8 to epoch 4 and turns a finite blow-up into a `nan`.
`Decoder/scripts/diagnose_divergence.py` is committed so the diagnosis is re-runnable:

```
epoch 1: mean loss 0.598218  max pre-clip grad norm 4.67403  max |lograte| 10.49
epoch 2: mean loss 0.587946  max pre-clip grad norm 7.99201  max |lograte| 13.32
epoch 3: mean loss 0.582616  max pre-clip grad norm 7.99201  max |lograte| 13.33
  !! step 1365 (epoch 4): loss=nan max|lograte|=97.33 pre_clip_grad_norm=nan
  top pre-clip grad norms so far: 4.153e+10 (step 1357), 7.992, 4.674, 3.883, 3.707
  top max|lograte| so far: 97.33 (step 1365), 43.73 (step 1357), 17.25, 16.35, 15.05
```

For 1,356 steps gradient norms peak at 8.0 and log-rates at 13.3. At step 1357 the model emits a
log-rate of 43.7 and that step's gradient norm is 4.15e10; the clip bounds the step, but the
excursion is in the FORWARD pass, and eight steps later `exp(97.33)` overflows float32. **The
ordering is log-rate excursion first, exploding gradient second**, so clipping acts on the symptom
one step after the cause.

The stability ledger, all four cases checked rather than inferred:

| Divergence | Under clipping |
|---|---|
| LOSO fold holding out `indy_20160627_01`, blow-up at epoch 7 | **fixed**, trains cleanly to 30 epochs |
| The committed slow gate, blow-up at epoch 8 | **worse**, non-finite at epoch 4 |
| LOSO fold holding out `indy_20160624_03` | still clean, 26 epochs |
| New: LOSO fold holding out `indy_20160915_01`, clean before | **introduced**, non-finite at epoch 8 |

One quarter of the rotation is still lost. It is a different quarter.

### The stopping rule, pre-registered in its own commit

`ndt1.train.loss_plateaued` takes the loss curve and no other argument. It cannot see a co-bps,
because stopping at the epoch where the headline metric peaks is the exact tuning this task existed
to avoid, and making that structurally impossible is stronger than promising not to do it.

> Stop at the first epoch at which `|(L[i-1] - L[i]) / L[i-1]| < 0.001` has held for each of the
> last 3 epochs and at least 12 epochs have run; otherwise stop at 60 and report that the curve had
> not converged.

Every parameter was justified against a measured quantity: the tolerance against 09-06b's own
per-epoch improvements, the patience against the 3-epoch window 09-06 already used to judge
convergence by eye, the floor so the converged run is never shorter than the truncated one it
replaces, and the cap against measured wall clock. Three arithmetic choices are each fixed by a
test: per-epoch rather than the window mean, on the absolute value so a worsening run is never
called converged, and relative so the rule means the same thing at any loss scale. It is pinned
against the committed 09-06b curve, where it correctly says "not converged at 12".

Commit `247372b` (the rule) precedes commit `2f63312` (the numbers). `git log` is the check.

### The run, and the honest reading of it

2.72 h of CPU: pooled training plus the full four-fold rotation on the four manifest-pinned
sessions, `seed = 0`, CPU only.

| Comparison | 09-06b, 12 unclipped | 09-06c published, 12 clipped | Budget probe, 60 clipped |
|---|---|---|---|
| Pooled, `train_null` | 0.0062 | **0.0713** | **0.3002** |
| Pooled, `test_mean_null` | -0.0219 | **0.0432** | **0.2721** |
| Sessions below their own test mean | 3 of 4 | 3 of 4 | **1 of 4** |
| Per session, window-weighted, own test mean | -0.2192 | -0.1499 | **+0.0790** |
| LOSO, `test_mean_null`, finite folds | -0.4852 | **-0.4427** | not measured |
| `CO_BPS_MARGIN` | 0.00082 | **0.0094** | not derived (probe) |

Every published number moved up and no cell changed sign at 12 epochs. **The pooled figures are
the highest of the columns because pooling computes the null across four recordings spanning 83
days, which makes it a worse constant predictor for any individual session than that session's own
mean.** The evidence says outright that a reader quoting only +0.0713 is quoting the weakest null
measured, and that neither 0.0713 nor 0.3002 is converged.

### The rule fired at its floor, and that is recorded rather than glossed

```
 10    0.5577   relative change 0.000794   inside the 0.001 band
 11    0.5572   relative change 0.000827   inside the 0.001 band
 12    0.5571   relative change 0.000309   inside the 0.001 band -> RULE FIRES
```

`MIN_EPOCHS = 12`, so the pooled run stopped at the earliest epoch available to it, on three
changes sitting just inside the band. Three LOSO folds under the identical rule ran 16, 26 and 30
epochs. `09-decoder-metrics.json` records `convergence.fired_at_floor = true` alongside the rule,
every per-epoch relative change, and the three the rule inspected, so the decision is recomputable
from the committed curve rather than taken on trust.

**The floor was not moved afterwards.** A subordinate budget probe was pre-registered in its own
commit instead, with the pre-registered run staying the headline whichever number is larger.

**The attribution came out clean by luck.** Because the rule stopped at 12, the published run and
the run it supersedes have the SAME budget, so the movement from 0.0062 to 0.0713 is the clip
alone. Had the rule fired at epoch 40 the two changes would have been inseparable without a third
run.

### The budget probe, and the methodological finding it produced

The probe was pre-registered in its own commit before it was run, and it answers the budget
question decisively: **the published run stopped far too early.** Identical configuration, rule
disabled, 60 epochs, `--skip-loso`, scratch directory, 69 minutes of CPU. Committed as
`09-budget-probe.json`.

Between epochs 12 and 60 the training loss falls only **1.3%** (0.5571 to 0.5500) while pooled
co-bps rises **4.2x** (0.0713 to 0.3002), and the count of sessions losing to their own mean drops
from 3 of 4 to 1 of 4.

**A 0.001-relative plateau criterion on the masked Poisson NLL is a poor proxy for convergence of
co-bps in this regime, and the run demonstrated it rather than assuming it.** The corpus is 71 to
80% empty bins, so the loss is dominated by the easy bulk and goes quiet long before the model
stops improving on the normalized comparison against a null that co-bps measures.

**The rule was not retuned afterwards.** Moving its tolerance or floor having seen which setting
gives a better number is the exact tuning the pre-registration exists to prevent. What it should
become is logged in `deferred-items-09-06c.md` item 4, with the property that must be preserved: a
replacement rule must fire on a FLAT trajectory regardless of level, never on a high value.

The probe is not a rescue. Its own `stop_reason` is `epoch_cap` and `convergence.converged` is
`false`, so 0.3002 is a floor too; it has no LOSO rotation, no derived margin, and its checkpoint is
not the committed one.

### Supersession chain, three links, none deleted

`train_real.py --supersede-current` snapshots the currently published blocks under a new
`superseded_*` key by code rather than by retyping, and `_carry_superseded` now carries every
`superseded_*` record by prefix, so a future correction only has to write its own block.

```
superseded_visible_input_objective   1.9116   defective objective, 12 epochs
superseded_truncated_budget          0.0062   corrected objective, 12 unclipped epochs
(top level)                          0.0713   corrected objective, clipped, stopped by the rule
```

Eight quick tests bind the margin to the JSON, reject all three superseded constants by name, and
assert every superseded record carries a note saying how it may be used and a pointer to what
replaced it.

## Task Commits

1. **RED: the failing gradient-clipping test plus behaviour-preserving opt-in plumbing** - `4c78025` (test)
2. **The clip on by default at max_norm 1.0** - `763739c` (fix)
3. **The loss-only convergence rule** - `8044eb5` (feat)
4. **The pre-registered stopping rule, committed before the run** - `247372b` (docs)
5. **The 09-06b numbers labeled superseded, by code, before re-running** - `0ff1659` (docs)
6. **Per-epoch progress logging for a multi-hour run** - `287779c` (chore)
7. **The divergence diagnosis clipping did not fix, and its committed probe** - `e9c0bdd` (fix)
8. **The supplementary budget probe, pre-registered before running** - `8e0b092` (docs)
9. **Every co-bps re-measured under the clipped, rule-stopped run** - `2f63312` (feat)
10. **The evidence rewritten around what the run showed** - `0354a55` (docs)
11. **The budget-probe result and the rewrite it forced** - `bfd2523` (docs)
12. **This summary** - see `git log`

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 3 - Blocking] A multi-hour run was unobservable while it ran**

- **Found during:** the first launch of the retrain
- **Issue:** `_train_pool` logged the loss curve only after training finished, so a run with a
  60-epoch cap gave no signal for over an hour and its stopping decision was invisible until the end.
- **Fix:** a read-only `on_epoch_end(epoch, loss)` hook in `train_ndt1`, logged by `train_real.py`.
  Read-only by contract: it touches neither the RNG nor the optimizer, so the log cannot become a
  variable.
- **Verification:** the run was restarted one minute in, and the budget probe later reproduced all
  12 of the restarted run's epoch losses to full double precision, including the
  460088591144.742004 transient, so the hook changed nothing.
- **Committed in:** `287779c`

**2. [Rule 2 - Missing critical] `stop_reason` could not distinguish a real plateau from a floor**

- **Found during:** reading the completed run
- **Issue:** the pooled run recorded `stop_reason = "plateau"`, which reads as "the curve
  converged". It had in fact stopped at `MIN_EPOCHS`, the earliest epoch the rule can fire. Those
  are very different claims and the JSON could not tell them apart.
- **Fix:** a `convergence` block recording the rule, every per-epoch relative change, the three the
  rule inspected, and `fired_at_floor`. Computed by a shared helper used by the payload builder and
  by `--annotate-convergence`, so the record for this run was derived from the committed curve
  rather than typed.
- **Committed in:** `2f63312`

**3. [Rule 2 - Missing critical] `_carry_superseded` would have dropped the middle link**

- **Found during:** preparing to re-run
- **Issue:** it carried one hard-coded key, so the second supersession would have silently deleted
  the first on the next re-run.
- **Fix:** carry every `superseded_*` key by prefix, plus a quick test that every superseded record
  says what replaced it.
- **Committed in:** `247372b`

### Deliberate departures

**4. `max_norm = 1.0` was kept after it was measured NOT to fix the failure it was deferred for.**
Choosing a clip value from observed gradient norms after seeing the divergence would be tuning a
knob against the thing being reported. The a-priori convention was kept and the negative result
published.

**5. The diverged LOSO fold ran out its full 60-epoch cap producing `nan`**, about an hour of
wasted CPU, rather than being killed early. Terminating a run early is a protocol change and the
pre-registration said otherwise.

**6. `masked_poisson_nll` was not changed**, although the diagnosis points straight at it. Logged
as `deferred-items-09-06c.md` item 1.

**7. The slow gate was left RED** and its threshold was not lowered to whatever would pass. It
fails before reaching the threshold at all.

## Issues Encountered

**The task's central question has a budget-dependent answer, and that dependence is the finding.**
"Does NDT1 beat a per-channel mean-firing-rate null on real primate M1 spikes?" At the published
12-epoch budget: pooled yes (0.0713 / 0.0432), per session no on three of four, across sessions no
on every LOSO fold that finished. At 60 epochs: pooled yes by 4.2x more (0.3002 / 0.2721), per
session yes on three of four. Cross-session was not measured at the longer budget at all.

**The pre-registered stopping rule was wrong, and it is published as wrong rather than replaced.**
It fired at its 12-epoch floor on a curve that had 48 more useful epochs in it. This was not
predicted; it was measured by a probe that was itself pre-registered before it ran. The rule stands
as applied for the run it governed, and its replacement is deferred with the property that
replacement must preserve.

**The model was not trained to convergence, and neither was the probe.** Both `stop_reason` values
are committed. This is why the status below is `PARTIAL`.

**Reproducibility is slightly weaker than 09-06b's, but stronger than expected.** That run trained
the pooled configuration twice and compared checkpoint SHA-256 byte for byte. This one did not
compare a final hash, because the second invocation is the budget probe which continues past epoch
12. What it did establish: the probe reproduces **all 12** of the published run's per-epoch losses
to full double precision from a separate process an hour later, including the 16.56512170355149 and
460088591144.742004 transients. Reproducing a transient of that magnitude bit for bit means the
optimizer visited the same states in the same order over the whole span the committed checkpoint
was trained for. The rotation was executed once.

**A session rate limit interrupted the task** between the completion of the training run and the
write-up. No compute was lost: the run had already written `09-decoder-metrics.json`, and on
resumption the committed `losses` array was verified byte-identical to the run log before anything
was built on it.

## Deferred Items

Three, in `deferred-items-09-06c.md`: the forward-pass overflow in `masked_poisson_nll` that
clipping cannot reach, with the diagnosis and the reason `torch.clamp` is the wrong tool; the slow
gate's disposition, with a concrete two-assertion recommendation for Plan 09-09; and the fact that
the clip binds on ordinary steps and so is a second variable rather than an inert guard.
`deferred-items-09-06b.md` item 1 is closed by this task (applied, and the prediction in it
disproved); its items 2 and 3 remain open.

## Known Stubs

None. No placeholder value, hardcoded empty result, mock payload or unwired path was introduced.
Every number in this summary and in `09-training-evidence.md` came from a run that actually executed
on the four manifest-pinned real sessions. Three figures that could be mistaken for results are
labeled as such where they appear: the `visible` column of the diagnostic (out of distribution for a
checkpoint trained on hidden inputs), the diverged fold's `nan`, and the budget probe (subordinate
to the pre-registered run by its own pre-registration).

## Threat Flags

None. No new network endpoint, auth path, file access pattern or schema change at a trust boundary.
No dataset byte and no checkpoint entered git. Checkpoints remain state-dict only, gitignored, and
loaded through `torch.load(weights_only=True)`.

T-09-06-05 (tuning toward a threshold) is the disposition this task was most exposed to, and it was
mitigated structurally rather than by intention: the stopping rule takes the loss and cannot see the
metric, it was committed before the run in its own commit, the epoch floor was not moved after it
fired, the margin was re-derived by an unchanged rule for the third time, the clip norm was kept at
its a-priori value after being measured not to work, and the red gate was not made green by lowering
its threshold.

## Verification

```
uv run --project Decoder pytest Decoder/tests/test_grad_clipping.py -q      -> 2 failed, 2 passed (RED, before the fix)
uv run --project Decoder pytest Decoder/tests/test_grad_clipping.py -q      -> 5 passed (after)
uv run --project Decoder pytest Decoder/tests -m "not slow" -q              -> 173 passed, 9 deselected
uv run --project Decoder ruff check Decoder                                 -> All checks passed
uv run --project Decoder python Decoder/scripts/train_real.py --smoke       -> 0
uv run --project Decoder python Decoder/scripts/train_real.py               -> 0 (9777.7 s)
uv run --project Decoder python Decoder/scripts/train_real.py --annotate-convergence -> 0
uv run --project Decoder python Decoder/scripts/train_real.py --diagnostic  -> 0
uv run --project Decoder python Decoder/scripts/train_real.py --derive-margin -> 0 (0.0094)
uv run --project Decoder python Decoder/scripts/diagnose_divergence.py      -> 0
uv run --project Decoder python Decoder/scripts/train_real.py --no-plateau-stop --skip-loso ... -> 0 (4137.8 s)
uv run --project Decoder pytest -m slow -k test_heldout_cobps -q            -> 1 FAILED (non-finite from epoch 4)
git status --porcelain Decoder/checkpoints Decoder/data                     -> 0 lines
```

Plan 09-06's verification greps still hold: `April to June 2016` absent, the two forbidden `mc_rtt`
phrasings absent, `photodiode|24.7` absent, `0.3804` present, `indy_20170202_02` present.

## Next Phase Readiness

- **Plan 09-07 (velocity readout)** has a new pooled checkpoint at
  `Decoder/checkpoints/ndt1_real_pooled.pt`, sha256
  `af704a93848d2ea6efb69f356e52485693d0ab7da0b9acc94d7390654f316a2d`. It is a different model from
  the one 09-06b produced and any lag sweep must be re-run against it.
- **Plan 09-09 (`decoder-policy.sh`)** inherits a red slow gate with a concrete recommendation in
  `deferred-items-09-06c.md` item 2: split it into a stability gate on the D-12 splits and a
  reproduction check against the committed JSON, rather than repairing a threshold assertion that
  the training path never reaches.
- **Plan 09-10 (citation sweep)** now has a three-link chain to label, not two.
- **Plan 09-07 should read the budget probe before sizing its own training.** A velocity readout
  trained on top of a 12-epoch encoder is being handed a checkpoint the probe shows is badly
  under-trained.
- **Open constraint on everything downstream:** 0.0713 may be quoted only as the POOLED,
  12-EPOCH value with the per-session and LOSO qualifiers attached. 0.3002 may be quoted only as
  the 60-epoch probe, which has no rotation and did not converge either. 0.0062 may be quoted as
  what a 12-epoch unclipped run gave. 1.9116 is not a decoder result and must not be quoted as one.

## Status rationale

`PARTIAL`, not `PASS`. Every step of the corrective task completed: clipping was added and
verified (and the verification came back partly negative, which is reported rather than buried), the
stopping rule was pre-registered and committed before the run, the retrain executed, every dependent
number was re-derived by code, and the supersession chain is intact. Four flagged gaps prevent a
clean `PASS`:

1. **The model is still not converged, and the published number is measurably far from it.** The
   rule fired at its 12-epoch floor; the probe then showed 48 more epochs are worth a 4.2x increase
   in pooled co-bps. The published headline is a 12-epoch number and the probe is a 60-epoch floor.
2. **The committed slow gate is still RED**, and clipping made its failure earlier. The root cause is
   diagnosed and the fix is deferred with a reason.
3. **One of four LOSO folds diverged**, so the rotation summary again rests on three folds; and the
   rotation was executed once.
4. **The headline question has a budget-dependent answer**, and the better-trained arm of it has no
   LOSO rotation, no derived margin and no committed checkpoint. Closing that needs a re-run under a
   stopping rule this task deliberately did not invent after the fact.

## Self-Check: PASSED

Files claimed, verified present:
- `Decoder/tests/test_grad_clipping.py` FOUND
- `Decoder/tests/test_plateau_stop.py` FOUND
- `Decoder/scripts/diagnose_divergence.py` FOUND
- `.planning/phases/09-.../deferred-items-09-06c.md` FOUND
- `.planning/phases/09-.../09-budget-probe.json` FOUND
- `Decoder/src/ndt1/train.py`, `Decoder/scripts/train_real.py` FOUND (modified)
- `Decoder/tests/test_heldout_cobps.py`, `test_cobps_margin.py` FOUND (modified)
- `.planning/phases/09-.../09-decoder-metrics.json` FOUND (modified)
- `.planning/phases/09-.../09-training-evidence.md` FOUND (modified)

Commits claimed, verified in `git log`: `4c78025`, `763739c`, `8044eb5`, `247372b`, `0ff1659`,
`287779c`, `e9c0bdd`, `8e0b092`, `2f63312`, `0354a55` all FOUND.

Commit ORDERING verified, which is the load-bearing claim of this task:
`git merge-base --is-ancestor 247372b 2f63312` exits 0, so the stopping rule was committed
(23:08:09) before the commit carrying the numbers it produced (02:26:52). The budget probe's
pre-registration `8e0b092` (23:35:32) is likewise an ancestor of the numbers, and the probe process
did not start until 02:25:06.

Number provenance verified rather than trusted: the committed `losses` array was checked
byte-identical to the run log's pooled curve after the session interruption, before anything was
built on it, and it differs from the `superseded_truncated_budget` curve at both ends.

`git status --porcelain Decoder/checkpoints Decoder/data` returns 0 lines. `git ls-files` matches no
`.pt` and exactly one `.mat`, `Decoder/tests/fixtures/tiny_v73.mat`, which is the Plan 09-02 CI
fixture committed in `eb66745` and untouched by this task.
