# Plan 09-06b deferred items

Out-of-scope discoveries from the corrective task that fixed the masked-modeling objective and
re-derived every number that depended on it. Logged, not fixed.

Written to a plan-scoped file rather than the shared `deferred-items.md` for the same reason 09-06
was: a shared append caused an add/add conflict earlier in this phase.

## Status of the two items 09-06 deferred

**Item 1, the masked-modeling objective does not hide what it scores: CLOSED by this task.**
`ndt1.train.masked_forward` now runs the encoder on `ndt1.loss.hide_scored_positions(targets, mask)`
in both the training loop and every scoring path, and
`Decoder/tests/test_masked_input_isolation.py` fails if that is ever reversed. See
`09-training-evidence.md`.

**Item 2, the LOSO fold that diverges: still open.** Its status under the corrected objective is
recorded in `09-training-evidence.md` and in `09-decoder-metrics.json` under `loso[].diverged`.
Nothing was clipped, shortened or re-seeded to change it: choosing an 11-epoch budget because it
avoids the NaN is tuning toward a result (D-22, D-25). The remedy remains a decision, below.

## 1. Gradient-norm clipping in `train_ndt1` is a decision, not a repair

The `log_input=True` Poisson NLL has model term `exp(rate) - target * rate`. Once a predicted
log-rate spikes, `exp` overflows and the gradients go non-finite; AdamW at `lr = 2e-3` with no
clipping has nothing to arrest it. `torch.nn.utils.clip_grad_norm_` behind an explicit argument to
`train_ndt1` is the standard remedy and would very likely make the rotation complete.

It is not applied here for the same reason 09-06 did not apply it, and for one more:

- It changes the training dynamics of every run in the repository, so every committed number would
  have to be re-derived again.
- Adding it in the same task that corrects the objective would confound the two changes. This task
  exists to make the objective the only variable; introducing a second one would leave no way to
  attribute a difference to either.

**It now fires in two places, not one.** Besides the LOSO fold, the committed slow gate
`Decoder/tests/test_heldout_cobps.py::test_heldout_cobps_beats_mean_rate_null` diverges outright:
seven clean epochs, 21301.74 at epoch 8, then 4.68e22 by epoch 12, deterministic across two
executions. **That gate is RED on main and this task deliberately left it red**, because the
remedies are exactly the change being deferred here. Under the superseded objective it passed; the
corrected objective is measurably less stable at `lr = 2e-3`.

**What closing it looks like:** add the argument, re-run the rotation AND the slow gate, publish the
clipped and unclipped curves side by side, and record the config change with its rationale under
D-14. Until then the repository has a known-red slow gate, which is excluded from the quick CI run
(`-m "not slow"`) and is a human-run runbook artifact under D-21, so it does not block CI.

## 2. `co_bps` and the assertion margin can both be legitimately non-positive now

Under the corrected objective the model predicts a scored bin from context alone, so a co-bps at or
below zero is a possible and meaningful outcome rather than a symptom. Two consequences the
repository is not yet fully set up for:

- `train_real.py --derive-margin` handles a non-positive observation (margin 0.0, with a rationale
  saying the gate then proves only that the model is not worse than the null). That path is
  implemented and unit-reachable but has never run on a committed number.
- `Decoder/tests/test_heldout_cobps.py` asserts `heldout_co_bps > CO_BPS_MARGIN`. With a margin of
  0.0 that becomes "strictly better than the null", which is the honest gate for that case, but the
  test would then be a genuine pass/fail on model quality rather than a regression guard. Whether
  that is the gate the repository wants is a decision for `decoder-policy.sh` (Plan 09-09).

## 3. The train/serve mismatch introduced by 100% zero-masking

Every scored position is zeroed during training, but at inference the decoder sees uncorrupted
counts (Phase 5's velocity path runs the encoder on real spikes with no mask at all). BERT and NDT
leave a fraction of masked positions unchanged partly to reduce exactly this mismatch. That fraction
is the leak this task removed, so it was not reproduced.

The mismatch is accepted and recorded in `09-training-evidence.md` rather than engineered away. If
Plan 09-07's velocity R^2 comes in below expectation, this is the first thing to test: fine-tune or
evaluate the encoder on uncorrupted inputs and compare.

## Note on pre-existing items

The two entries in the shared `deferred-items.md` still stand and were not re-logged. Item 2 (`ty`
reports `unresolved-import` on every file under `Decoder/`) reproduced on the new test module in
this task; it is a tool-configuration gap, and `uv run --project Decoder ruff check Decoder` and the
quick pytest run both exit 0.
