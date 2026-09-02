# Plan 09-06d deferred items

Out-of-scope discoveries from the corrective task that stabilized the loss against forward-pass
overflow, removed stopping-rule selection, and published the co-bps trajectory. Logged, not fixed.

Written to a plan-scoped file rather than the shared `deferred-items.md` for the same reason 09-06,
09-06b and 09-06c were: a shared append caused an add/add conflict earlier in this phase.

## Status of what 09-06c deferred

**Item 1, the forward-pass overflow in `masked_poisson_nll`: CLOSED.** Authorized and implemented
as specified. `ndt1.loss.stable_exp` linearizes `exp` above `LOG_RATE_LINEARIZE_ABOVE = 20.0`, the
tangent line at that point, so an escaped log-rate produces a large finite loss with the finite
positive gradient `exp(C) - target`. `torch.clamp` was rejected for the reason 09-06c gave, and the
reason is now an assertion rather than an argument: above a clamp bound the derivative of the
clamped `exp` is zero, the surviving `- target * x` term leaves a gradient of `-target`, and a
descent step therefore drives an already-escaped rate FURTHER up.
`Decoder/tests/test_loss_stability.py` holds it in place, including the `torch.equal` no-op pair
that proves the change is bit-identical below the threshold in value and in gradient.

**Item 2, the co-bps gate's disposition: still open, and now it is Plan 09-09's to make.** See
item 1 below for what this task's stabilization changed about the gate's behaviour, which is
material to the recommendation 09-06c left.

**Item 3, the clip binds on ordinary steps: unchanged.** Nothing in this task moved
`grad_clip_norm`, which is still the a-priori 1.0.

**Item 4, the stopping rule is too lax for co-bps: CLOSED by removal rather than by replacement.**
09-06c asked for a rule defined on a held-out quantity that "must fire on a FLAT trajectory
regardless of level, never on a high value". This task did not write that rule. Any rule that stops
somewhere inside the curve is a selection, and a selection designed after seeing that a longer
budget gives a better number is a tuned budget however carefully it is worded. The rule was removed
instead: the run goes to a fixed cap, the whole co-bps-versus-epoch trajectory is published, and
the headline is the value at the cap. The 09-06c rule remains in the codebase behind
`--plateau-stop`, with its tests, because deleting it would erase the arm the new numbers are
compared against.

## 1. The stabilizer changes what the committed slow gate does, and 09-09 should know before it decides

`Decoder/tests/test_heldout_cobps.py::test_heldout_cobps_beats_mean_rate_null` failed in 09-06b and
09-06c because its training path went non-finite before the assertion was ever reached. **The gate
itself was NOT executed under 09-06d**, so what follows is inference from a replay, not a verdict.

`diagnose_divergence.py` reproduces that test's exact training path -- the same concatenation, the
same single chronological split, `lr = 2e-3`, `seed = 0`, `batch_size = 16` -- and under 09-06d it
went from `nan` at epoch 4 to a finite transient at epoch 4 followed by a recovery that kept
descending through epoch 8 (0.5805, 0.5790, 0.5767, 0.5759). Its epochs 1 to 3 match 09-06c's to
six decimal places, so it is the same run up to the excursion. The failure mode "it cannot finish
training" is therefore very likely gone. Whether the gate now reaches its assertion, and whether it
then clears the re-derived 0.054 margin, was not measured.

The gate's SECOND problem is untouched and is the one that matters. `_load_binned()` still
concatenates the four sessions into one matrix and splits it once chronologically, which cuts
32-bin windows across session boundaries weeks apart -- the thing the committed headline path
explicitly forbids as a fabricated neural sequence (D-12, `ndt1.sessions.pooled_splits`) -- and
which makes the test half essentially one held-out session rather than four chronological tails.

**The 09-06c recommendation therefore stands, with one clause weakened.** Split the gate into a
stability assertion on the D-12 splits and a reproduction check against the committed JSON. The
clause that probably no longer applies is "it cannot finish training". Plan 09-09 owns this
decision; this task did not take it, did not run the gate, and did not lower its threshold -- the
margin was re-derived UPWARD from 0.0094 to 0.054 by the unchanged rule. The gate's disposition is
recorded in `09-training-evidence.md` rather than changed here.

Note for whoever runs it: the observation is now 7.6x the margin and the lowest sample anywhere on
the published post-plateau trajectory still clears it by 4.5x, so a threshold gate at 0.054 is no
longer at risk of flaking on the metric's own sampling noise the way its two predecessors were.

## 2. The rotation ran at a smaller budget than the headline, and closing that is a compute decision

The pooled run went to its 200-epoch cap. The four LOSO folds ran at 60 epochs each, which was
pre-registered before the run as a COST decision and is labeled as one everywhere it appears: a
full-cap rotation is 21,396 training windows against the pooled 7,132, so it would have cost
roughly 11.5 h of CPU on top of the 3.9 h headline.

The consequence is a real limitation, not a bookkeeping detail: **the folds are less trained than
the headline model, so the cross-session numbers are floors for a 60-epoch budget and are not
comparable to the pooled figure as though both had been trained equally.** Closing it needs about
half a day of CPU and nothing else -- no new code, no new decision, just `--only-loso
--loso-epoch-cap 200`. It is the cheapest remaining improvement to the artifact's completeness and
the most expensive in wall clock.

## 3. The per-session picture is still the weakest part of the claim, and it is a data question

Whatever the pooled number does, the per-session table scores each session against its OWN test
mean, which is the strongest constant per-channel predictor available, and that is where this
artifact's claim is thinnest. The structural reasons are unchanged from 09-06c and none of them is
fixable by training longer:

- The corpus is four sessions spanning 83 days, so a pooled per-channel mean is a poor constant
  predictor for any single session and an easy null to beat for reasons that have nothing to do
  with neural dynamics.
- `indy_20160627_01` is 59% of the corpus, so the pooled training set is dominated by one session.
- `indy_20160915_01` is 6.7% of it and 119 held-out windows, so any number from it carries far more
  sampling noise than the others and no error bar was computed for any session.

**What would actually close it is more sessions, not more epochs.** Zenodo record 3854034 has
dozens; this phase pinned four. That is a scope decision for a future plan, not a defect in this
one, and it is the single change most likely to move the per-session verdict.

## 4. No error bar on any co-bps in this artifact

Every co-bps here is a point estimate from one seeded mask on one run. There is no confidence
interval, no seed sweep and no bootstrap over held-out windows, so "0.2 on 119 windows" and "-0.15
on 1,050 windows" are printed with the same apparent precision and are not the same kind of
statement. The evidence says so in prose wherever it matters, but prose is not an interval.

The cheap version is a bootstrap over held-out windows on the committed checkpoint: it trains
nothing, it reuses the scoring path that already exists, and it would put a spread on every cell of
the per-session table. It is deferred because this task's mandate was the budget and the numerics,
and because an interval derived after seeing which cells are near zero would need its own
pre-registration to be worth anything.

## Note on pre-existing items

The two entries in the shared `deferred-items.md` still stand and were not re-logged. Item 2 (`ty`
reports `unresolved-import` on every file under `Decoder/`) reproduced on both new test modules in
this task; it is a tool-configuration gap, and `uv run --project Decoder ruff check Decoder` and the
quick pytest run both exit 0.
