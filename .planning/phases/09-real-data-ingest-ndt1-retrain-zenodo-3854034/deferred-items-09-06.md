# Plan 09-06 deferred items

Out-of-scope discoveries from the RD-03 / RD-04 retrain. Logged, not fixed: this plan's declared
`files_modified` covers `Decoder/scripts/report_sessions.py`, `Decoder/scripts/train_real.py`,
`Decoder/tests/test_heldout_cobps.py`, `Decoder/tests/test_cobps_margin.py` and the two artifacts.
Both items below would require editing `Decoder/src/ndt1/train.py` or changing the D-14-locked
training config, and both are decisions rather than repairs.

Written to a plan-scoped file rather than the shared `deferred-items.md` on purpose: a shared append
caused an add/add conflict earlier in this phase.

## 1. The masked-modeling objective does not hide what it scores

**Severity: high. This is the single largest caveat on the number this plan publishes.**

`ndt1.train.train_ndt1` builds the loss mask and then calls `model(targets)` on the UNMASKED counts:

```python
targets = reshape_to_bc1s(window)
mask = random_mask(targets.shape, mask_ratio, generator=mask_gen).to(dev)
rates = model(targets)                                   # <- unmasked input
loss = masked_poisson_nll(rates, targets, mask, log_input=log_input)
```

`NDT1ANE.forward` performs no input masking either; it stores `mask_ratio` as an attribute for the
trainer and never applies it. So the encoder can read the observed count at every position it is
scored on, and the objective is reconstruction over a random subset of positions rather than the
BERT-style masked prediction the module docstrings describe ("a fraction `mask_ratio` of bins is
masked"). The code contradicts its own documented contract.

Consequence, measured rather than asserted: `train_real.py --diagnostic` re-scores the committed
checkpoint with the scored positions zeroed in the encoder input and records both values in
`09-decoder-metrics.json` under `co_bps.input_visibility_diagnostic`. The gap is reported in
`09-training-evidence.md`.

**Why it was not fixed here.** Three independent reasons, any one of which is sufficient:

- It changes `Decoder/src/ndt1/train.py`, which is outside this plan's `files_modified`.
- D-14 requires the Phase-4 config verbatim so the real number is directly comparable to the
  synthetic 0.3804 it replaces. Changing the objective destroys that comparability.
- It is an objective change, not a local bug fix, so it is an architectural decision for the user
  rather than an executor auto-fix.

**What closing it looks like:** zero (or replace with a learned mask token) the selected positions in
the encoder input, retrain, and publish the new number beside this one as a separate measurement.
Phase 4's synthetic number would also need re-deriving under the corrected objective before the two
could be compared. Worth its own plan.

## 2. One leave-one-session-out fold diverges numerically under the Phase-4 config

The fold holding out `indy_20160624_03` (training on the other three sessions, 6,508 windows) trains
normally for eleven epochs and then loses the twelfth to a non-finite loss:

```
per-epoch loss: 0.4157 0.3305 0.2942 0.2748 0.2631 0.2573 0.2529 0.2485 0.2467 0.2455 0.2437 nan
```

The other three folds and the pooled run complete all twelve epochs cleanly. The divergence is
deterministic: it reproduced identically across two independent runs at `seed = 0`.

The likely mechanism is an overflow in the `log_input=True` Poisson NLL, whose model term is
`exp(rate) - target * rate`: once a predicted log-rate spikes, `exp` overflows to `inf` and the
gradients become `nan`. AdamW at `lr = 2e-3` with no gradient clipping has nothing to arrest it.

**Why it was not fixed here.** The standard remedies are gradient-norm clipping (a change to
`ndt1/train.py`, outside `files_modified`) or a lower learning rate (a config change D-14 does not
authorize). Note also that an 11-epoch budget would have produced a finite number for this fold;
choosing 11 BECAUSE it avoids the NaN would be tuning toward a result, which D-22 and D-25 forbid.
The fold is reported as diverged and contributes nothing to the rotation summary, which is
recomputed over the three folds that produced a value.

**What closing it looks like:** add `torch.nn.utils.clip_grad_norm_` to `train_ndt1` behind an
explicit argument, re-run the rotation, and document the config change with its rationale under
D-14. That also makes the pooled run more trustworthy, since it currently sits closer to the
stability edge than the loss curve alone suggests.

## Note on pre-existing items

The two entries in the shared `deferred-items.md` still stand and were not re-logged here. Item 2
(`ty` reports `unresolved-import` on every file under `Decoder/`) reproduced on both new scripts in
this plan; it is a tool-configuration gap, and `uv run --project Decoder ruff check Decoder` and the
quick pytest run both exit 0.
