# Plan 09-06c deferred items

Out-of-scope discoveries from the corrective task that added gradient clipping, pre-registered a
convergence rule on the training loss, and retrained to it. Logged, not fixed.

Written to a plan-scoped file rather than the shared `deferred-items.md` for the same reason 09-06
and 09-06b were: a shared append caused an add/add conflict earlier in this phase.

## Status of what 09-06b deferred

**Item 1, gradient-norm clipping: APPLIED, and it did NOT do what the write-up predicted.**
`torch.nn.utils.clip_grad_norm_` at `max_norm = 1.0` is now on by default in
`ndt1.train.train_ndt1` and `Decoder/tests/test_grad_clipping.py` holds it in place.
`deferred-items-09-06b.md` said it "would very likely make the rotation complete". Measured, it
does not resolve the committed slow gate's divergence; it moves it earlier. See item 1 below for
the diagnosis, which is the substantive finding of this task's stability work.

**Item 2, `co_bps` and the assertion margin can both be legitimately non-positive: still open, and
now live.** See item 2 below and `09-training-evidence.md`.

**Item 3, the train/serve mismatch from 100% zero-masking: untouched.** Nothing in this task
changed the masking, so that item stands exactly as written.

## 1. The remaining instability is a forward-pass overflow, and clipping cannot reach it

Gradient clipping was applied as authorized and then verified rather than assumed. On the committed
slow gate, which is the one reproducible real-data divergence this repository has, it made the
failure worse:

| Run | Per-epoch loss | Outcome |
|---|---|---|
| 09-06b, no clipping | 0.6034 0.5941 0.5848 0.5850 0.5825 0.5801 0.5782 21301.74 26.63 22.93 1.49e22 4.68e22 | finite, never recovers |
| 09-06c, clip 1.0 | 0.5982 0.5879 0.5826 nan nan nan nan nan nan nan nan nan | non-finite from epoch 4 |

An instrumented replay of that exact training path (per-step loss, pre-clip gradient norm, and
`max |log-rate|`) locates the mechanism to the step:

```
epoch 1: mean loss 0.598218  max pre-clip grad norm 4.67403  max |lograte| 10.49
epoch 2: mean loss 0.587946  max pre-clip grad norm 7.99201  max |lograte| 13.32
epoch 3: mean loss 0.582616  max pre-clip grad norm 7.99201  max |lograte| 13.33
  !! step 1365 (epoch 4): loss=nan max|lograte|=97.33 pre_clip_grad_norm=nan
     grad_nonfinite=True param_nonfinite=True
  top pre-clip grad norms so far: 4.153e+10 (step1357), 7.992, 4.674, 3.883, 3.707
  top max|lograte| so far: 97.33 (step1365), 43.73 (step1357), 17.25, 16.35, 15.05
```

For 1,356 steps the gradient norms peak at 8.0 and the predicted log-rates at 13.3. At step 1357
the model emits a log-rate of 43.7 on a batch it had already seen three times without incident, and
the gradient norm for that one step is 4.15e10. The clip fires and bounds that step, but the
excursion is in the FORWARD pass: over the next eight steps the log-rate climbs to 97.33, `exp`
overflows float32 (which happens above 88.7), the loss becomes `nan`, and every parameter follows.

**So the ordering is: log-rate excursion first, exploding gradient second.** Gradient clipping acts
on the symptom, one step after the cause, which is why it cannot prevent this and why it changed
the failure's character rather than removing it. It does prevent the other half of the problem (an
outlier gradient poisoning AdamW's moment estimates), which `tests/test_grad_clipping.py` measures
directly.

**What closing it looks like, and why it is not done here.** The remedy is to bound the Poisson NLL
so a large predicted log-rate produces a large FINITE loss with a finite, correctly-signed gradient
that pulls the rate back down: linearize `exp(x)` above a threshold `C` well outside the data
regime (real 20 ms bins here carry 0 to 5 spikes, so healthy log-rates sit near `log(0.3)`, and the
observed healthy maximum is 13.3). A plain `torch.clamp` is the wrong tool: its gradient above the
bound is zero, so a model that has escaped would get no signal to return.

That is a change to `ndt1.loss.masked_poisson_nll`, which is the objective. This task's mandate was
to change the epoch budget and add gradient clipping, and to document both as the only deliberate
changes. Changing the loss as well would put three variables in one measurement and make the
converged number attributable to none of them. It is the single most actionable item on this list.

## 2. The co-bps gate can no longer assert what it was written to assert

`Decoder/tests/test_heldout_cobps.py::test_heldout_cobps_beats_mean_rate_null` is red on main and
stays red after this task, for the reason in item 1. Two separate problems are now tangled in one
test and they should be separated:

- **It cannot finish training.** Its own training path diverges before the co-bps assertion is
  reached, so the assertion has not actually been evaluated on real spikes under the corrected
  objective in either 09-06b or 09-06c.
- **Its training path is not the one the evidence uses.** `_load_binned()` concatenates the four
  sessions into one matrix and splits it once chronologically. That cuts 32-bin windows across
  session boundaries weeks apart, which the committed headline path explicitly forbids as "a
  fabricated neural sequence" (D-12, `ndt1.sessions.pooled_splits`), and it makes the test half
  essentially one held-out session rather than four chronological tails.

**Recommendation, for Plan 09-09 / `decoder-policy.sh` to decide, not this task.** Split it into
two assertions with different jobs:

1. A **stability gate** that trains on the D-12 per-session splits and asserts only that the loss
   stayed finite and ended below where it started. That is a real regression guard, it does not
   depend on a threshold anyone has to justify, and it would have caught every divergence in this
   phase.
2. A **reproduction check** that asserts the committed pooled co-bps in `09-decoder-metrics.json`
   is reproduced by re-scoring the committed checkpoint, to a tolerance. That is what the repository
   actually wants to defend, and unlike a margin it does not become vacuous when the observation is
   near zero.

The margin was NOT lowered to whatever would pass. It was re-derived from the new observation by
the unchanged rule (`train_real.py --derive-margin`), exactly as 09-06b re-derived it, and the
evidence states plainly what a gate at that size does and does not assert.

## 3. The clip binds on ordinary steps, so it is not an inert safety net

Pre-clip gradient norms on the real training path routinely exceed the 1.0 cap (4.67 in the first
epoch, 8.0 in the second and third, on the slow gate's path). The clip therefore rescales most
steps, not just the rare exploding one, and the loss trajectory differs from the unclipped run's
from epoch 1 onward.

That is expected with AdamW, whose per-coordinate normalization makes a uniform rescale close to a
no-op in the update, but "close to" is not "exactly", and it means gradient clipping is a second
variable in this task rather than a pure guard. Both changes are named as deliberate in
`09-training-evidence.md` and neither is presented as free. Quantifying how much of the change from
0.0062 is the budget and how much is the clip would need a third run (clipped at the old 12-epoch
budget), which was not done.

## Note on pre-existing items

The two entries in the shared `deferred-items.md` still stand and were not re-logged. Item 2 (`ty`
reports `unresolved-import` on every file under `Decoder/`) reproduced on both new test modules in
this task; it is a tool-configuration gap, and `uv run --project Decoder ruff check Decoder` and the
quick pytest run both exit 0.
