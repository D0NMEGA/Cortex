# Phase 9 RD-03 / RD-04 evidence: NDT1 trained on real primate M1 spikes

**Date:** 2026-08-31, revised 2026-09-01 (Plan 09-06c). Read the pre-registration below before the
numbers.
**Result:** pooled held-out **co-bps = 0.0713 bits/spike** against the train-split per-channel
mean-firing-rate null and **0.0432** against the pooled test-mean null, measured on **real
O'Doherty/Makin Indy M1 spikes (Zenodo record 3854034)**, four sessions, CPU only, with the scored
positions hidden from the encoder and gradients norm-clipped.

**The answer to "does this NDT1 beat a per-channel mean firing rate" depends on how long it is
trained, and that dependence is the main result of this work.**

| Comparison | Published run, 12 epochs | Budget probe, 60 epochs |
|---|---|---|
| Pooled, `train_null` (the D-22 gate) | **+0.0713** | **+0.3002** |
| Pooled, `test_mean_null` | **+0.0432** | **+0.2721** |
| Per session, against each session's OWN test mean | -0.2146, -0.1565, -0.2076, +0.2156 | -0.0777, +0.0590, +0.1375, +0.2361 |
| Sessions below their own test mean | **3 of 4** | **1 of 4** |
| Per session, window-weighted, own test mean | **-0.1499** | **+0.0790** |
| Leave-one-session-out, `test_mean_null`, 3 finite folds | **-0.4427** (-0.7580 to -0.2250) | not measured |

**At the published 12-epoch budget: pooled yes, per session no on three of four, across sessions no
on every fold that finished. At 60 epochs: pooled yes by 4x more, and per session yes on three of
four.** Both were measured; neither is an estimate.

**Which is the headline, and why.** The 12-epoch run is this artifact's published measurement,
because it is what the committed checkpoint, the derived margin and the LOSO rotation correspond to,
and because a pre-registration committed before the run said the pre-registered run stays the
headline whichever number is larger. The 60-epoch figure is a supplementary probe, also
pre-registered before it was run, with no rotation and no margin. **A reader asking what this model
can do should weigh the 60-epoch numbers; a reader asking what this repository has fully measured
and gated should use the 12-epoch ones.**

**The published run stopped far too early, and this artifact says so rather than presenting it as
converged.** The pre-registered rule fired at `MIN_EPOCHS = 12`, its floor, on three relative
changes (0.000794, 0.000827, 0.000309) sitting just inside a 0.001 band; three LOSO folds under the
identical rule ran 16, 26 and 30 epochs; and the probe shows the loss falls only a further 1.3% from
epoch 12 to 60 while pooled co-bps rises 4.2x. **A plateau criterion on a masked Poisson NLL that is
dominated by near-zero bins is a poor proxy for convergence of co-bps**, which is a methodological
finding this run demonstrated rather than assumed. `convergence.fired_at_floor = true` is committed
in `09-decoder-metrics.json`. The rule was NOT retuned after the fact; retuning it having seen which
setting gives a better number is the exact tuning the pre-registration exists to prevent.

**Neither number is converged.** The probe's own `stop_reason` is `epoch_cap` and its
`convergence.converged` is `false`; its loss was still falling at epoch 60. Both figures are floors.

**Attribution, at the published budget.** Because the rule stopped the run at 12 epochs, the
published run and the run it supersedes have the SAME budget, so the movement from 0.0062 to 0.0713
is attributable to gradient clipping alone and no third run is needed to separate them. The probe
then shows the budget is worth considerably more than the clip: 12 to 60 epochs is worth +0.229 on
the pooled gate null against the clip's +0.065.

### The three numbers this file supersedes

All three are preserved, labeled, in `09-decoder-metrics.json`, and quick tests fail if any is
deleted. Correcting a published number means labeling the old one.

| Value | Where | What was wrong with it |
|---|---|---|
| **0.3804** | `04-training-evidence.md` | Measured on a **synthetic Poisson fallback**: no real `.mat` was under `Decoder/data/` when Phase 4 ran. Doubly superseded, because it used the defective objective too. |
| **1.9116** | this file, first version | The encoder could read the value at every position it was scored on, so it measured self-reconstruction. `superseded_visible_input_objective`. |
| **0.0062** | this file, second version | Objective already correct; the run was 12 unclipped epochs on a curve that had not flattened, and one LOSO fold and the committed slow gate diverged. `superseded_truncated_budget`. |

**This is not a hardware-gated claim.** It is CPU-only decoder R&D that reproduces on any Mac CPU
with the pinned wheels. There is no Neural Engine, Core ML, palettization or latency number in this
file; those are Plans 09-07 and 09-08.

## Plan 09-06c: pre-registration, written before the run

**This section was written and committed BEFORE the run it describes was started.** Its commit
precedes the commit that carries the numbers, and `git log` is the check. It exists because a
stopping rule chosen after seeing the curve is a tuned budget with extra steps, and the whole point
of this correction chain is that the number is not shaped by the person reporting it.

### What is being changed, and only this

Two deliberate changes from the 09-06b run. Everything else is byte-for-byte identical:
`lr = 2e-3`, `batch_size = 16`, `seq_len = 32`, `mask_ratio = 0.25`, `seed = 0`, `test_frac = 0.2`,
`weight_decay = 0.01`, `log_input = true`, the architecture, and the corrected input-masking
objective.

1. **Gradient-norm clipping**, `torch.nn.utils.clip_grad_norm_` at `max_norm = 1.0`, applied on
   every optimizer step. This is a numerical-stability fix, not tuning: 09-06b observed three
   divergences under this objective (two LOSO folds and the committed slow gate, which is red on
   main) and deferred the remedy. 1.0 is the a-priori convention (the HuggingFace `Trainer`
   default, and what BERT and GPT-2 style loops use); it was not swept.
2. **The fixed 12-epoch budget is replaced by the stopping rule below.** The 12 came from Phase 4,
   where it was calibrated against the DEFECTIVE objective that let the model copy its input and
   reached a 43% loss reduction. Under the corrected objective the same budget yields 6% and the
   curve was still descending at 0.0007 per epoch when it ran out. D-14 permits raising the budget
   when the curve has clearly not converged; 09-06b declined on purpose, and this task takes it.

### The stopping rule

**Defined on the TRAINING LOSS and nothing else.** `ndt1.train.loss_plateaued` takes the loss curve
and no other argument; it cannot see a co-bps. Stopping at the epoch where the reported metric
happens to peak is precisely the tuning D-22 and D-25 exist to prevent.

Let `r_i = (L[i-1] - L[i]) / |L[i-1]|` be the relative change in mean training loss at epoch `i`.

> **Stop at the first epoch at which `|r_i| < 0.001` has held for each of the last 3 epochs, and at
> least 12 epochs have run. Otherwise stop at 60 epochs and report that the curve had not
> converged.**

| Parameter | Value | Why this value |
|---|---|---|
| `PLATEAU_REL_TOL` | 0.001 | A tenth of a percent per epoch. The 09-06b run's first-epoch relative improvement was 3.9% and its last three were 0.071%, 0.125% and 0.143%, so the tolerance sits just below where that run stopped; the rule agrees it had not converged, which is pinned by a test. Twenty further epochs inside the band move the loss by under 2%, against the 6% that run achieved in twelve. |
| `PLATEAU_PATIENCE` | 3 | One quiet epoch cannot end a run that is still learning. Three is also the window 09-06 used when it judged convergence by eye ("epochs 10 to 12 oscillating inside 0.0018"), so the criterion is continuous with the one this repository already applied. |
| `MIN_EPOCHS` | 12 | The converged run is never SHORTER than the truncated run it replaces, so the new number can never be "we stopped earlier and got a different answer". |
| `EPOCH_CAP` | 60 | A compute bound, not a result-shaped choice. 09-06b measured 844 s for 12 pooled epochs (70 s/epoch), and the four rotation folds together are 21,396 training windows to the pooled 7,132, so a full run costs about 281 s per epoch. Sixty epochs is about 4.7 h of CPU worst case, the largest single run this artifact can afford. |

Three properties of the arithmetic, each fixed by a test in `Decoder/tests/test_plateau_stop.py`:

- **Every epoch in the window must be flat, not their mean.** A window averaging one large
  improvement against two equal regressions has a mean near zero while the run is visibly bouncing.
- **The comparison is on `|r_i|`.** A run that is getting worse has a negative relative change,
  which is trivially "below" a positive tolerance, so a signed comparison would report a
  destabilizing run as converged and a diverging one most of all.
- **The change is relative, not absolute**, so the rule means the same thing at any loss scale.

The pooled run and each of the four LOSO folds get the same rule and stop independently under it.
Every stopping epoch and its reason is committed per run in `09-decoder-metrics.json`.

### What will be reported, whichever way it comes out

- The epoch at which the run actually stopped, and the loss curve that triggered the rule.
- **If the run hits the 60-epoch cap without meeting the plateau criterion, that is stated
  explicitly and the number is still labeled a floor**, exactly as the 12-epoch number was.
- Per-session co-bps against BOTH nulls, and the pooled value against both. The drift-robust
  `test_mean_null` is reported beside the gate null every time; the more flattering of the two is
  not promoted to headline.
- The full four-fold LOSO rotation with mean and spread.
- `CO_BPS_MARGIN` recomputed by the same unchanged derivation rule, from whatever the new
  observation is.

**A negative result is a result.** A converged NDT1 at 1.29M parameters on about 95 minutes of
real primate M1 spikes may still fail to beat a constant per-channel mean firing rate. If that is
what the run produces, it is reported without hedging. Nothing about the learning rate, the mask
ratio, the architecture, the seed or the choice of null will be changed to move it, and the run
will not be stopped at an epoch where the co-bps happens to look better: the rule above cannot see
the co-bps at all.

### Addendum, pre-registered while the main run was still executing

The pooled run stopped at **epoch 12 with `stop_reason=plateau`**, which is the earliest epoch the
rule can fire, because `MIN_EPOCHS = 12` is its floor. So the converged run is exactly as long as
the truncated run it replaces, and the rule terminated at its floor rather than at a visibly flat
asymptote. **That means the budget question 09-06b raised is not answered by the main run.**

Rather than move the floor, which after seeing the result would be exactly the tuning this
pre-registration exists to prevent, a second and clearly subordinate run is registered here:

> **Supplementary budget probe.** The identical pooled configuration with the plateau rule
> DISABLED, run to a fixed 60 epochs, `--skip-loso`, writing to a scratch checkpoint directory and
> a scratch JSON so it cannot touch the published artifact. Its purpose is the one
> `09-training-evidence.md` named as the way to close gap 1: "re-run at a longer budget with
> everything else fixed, and publish the 12-epoch and the longer-budget numbers side by side so the
> effect of the budget is visible rather than substituted."

Committed before that run was started. Three constraints on how it may be used:

- **The pre-registered run stays the headline**, whichever of the two numbers is larger. The
  supplementary run answers "what does a longer budget give", not "what does this repository
  report".
- Its result is published whichever direction it goes, including if the loss rises or the co-bps
  falls with more epochs.
- It does not re-derive the margin, does not replace the checkpoint, and does not enter
  `09-decoder-metrics.json` as a measurement; it is reported as a probe.

## The correction (Plan 09-06b)

> **Historical section.** Everything below describes the objective correction and the numbers it
> produced on 2026-08-31. Its bolded values (0.0062, -0.0219, -0.4852, 0.00082) are the
> `superseded_truncated_budget` record, not this artifact's current numbers. The correction itself
> stands and is still in force; only the run that measured under it has been replaced. Kept in full
> because the objective defect is the most important thing this phase found.


### What was wrong

`ndt1.train.train_ndt1` drew a BERT-style mask, then ran the encoder on the **unmasked** counts:

```python
mask = random_mask(targets.shape, mask_ratio, generator=mask_gen).to(dev)
rates = model(targets)                                    # the true counts, at every position
loss = masked_poisson_nll(rates, targets, mask, log_input=log_input)
```

`evaluate_co_bps` and `train_real.py`'s scoring path did the same, and `NDT1ANE.forward` performs no
input masking either. `random_mask` returns `True` where the loss IS computed, so the mask selected
which positions were scored and nothing else: the model received the observed spike count at every
position it was asked to predict. The module docstrings claimed a "BERT-style masked
spike-RECONSTRUCTION objective", but BERT corrupts its input and this never did.

Consequence: every co-bps this repository had published measured self-reconstruction plus context,
not context alone. That is why 1.9116 sat about 10x above the NLB'21 `mc_rtt` range of 0.147 to
0.192. Plan 09-06 measured the caveat and published it beside the number; it did not close it,
because closing it meant changing the objective, which is a decision rather than an executor fix.

### What was changed

`ndt1.train.masked_forward` is now the single place the encoder input is built, in training and in
every scoring path:

```python
def masked_forward(model, targets, mask):
    return model(hide_scored_positions(targets, mask))
```

`ndt1.loss.hide_scored_positions(targets, mask)` returns `targets` with the scored positions set to
zero. `targets` itself is untouched, so the Poisson NLL still scores against the true counts.
Training and evaluation share the function, because a fix applied to one and not the other would
report a number produced under one objective and scored under another, and the mismatch would be
invisible in the result.

### The masking choice, and why

Masked positions are **zeroed**, not replaced by a learned mask embedding.

- **It keeps the correction inside the objective, where the defect was.** `NDT1ANE.forward(x)`
  stays a single tensor in, single tensor out. A learned embedding needs either a 97th input channel
  or a new `nn.Parameter`: the first changes the `read_in` 1x1 Conv2d and the Core ML input
  signature the Phase-5 conversion path depends on, and both move the parameter count away from the
  1,292,544 that `Decoder/tests/test_param_count.py` guards.
- **It is what NDT does** with the bulk of its masked bins (Ye and Pandarinath 2021,
  snel-repo/neural-data-transformers).

**The cost, stated rather than hidden.** Zero is a legitimate spike count, and most bins in this
corpus are zero, so a masked position is indistinguishable from a genuinely silent one. The model
cannot condition on "this bin is hidden"; it predicts under the possibility that the bin really was
empty. That biases predictions at scored positions downward, so the co-bps below is a **lower bound**
on what a mask-token model of the same size would reach. That is the safe direction for a number
this repository publishes: the ambiguity can only understate the result, never inflate it. How much
it understates by was not measured and is recorded as a gap.

**Every scored position is corrupted, not 80% of them.** NDT and BERT leave a fraction of masked
positions unchanged, partly to reduce train/serve skew. That fraction is exactly the leak this
correction removes, so it was not reproduced. The train/serve mismatch it would have bought back is
accepted: at inference the decoder sees uncorrupted counts and no mask at all. It is recorded in
`deferred-items-09-06b.md` as the first thing to test if Plan 09-07's velocity readout underperforms.

### What holds it in place

`Decoder/tests/test_masked_input_isolation.py`, five quick tests, no dataset. The discriminating
probe perturbs the observed counts at the scored positions and asserts the prediction there does not
move by a single bit. Under the defect it moves, because the value is an input; under the fix the
corrupted input is identical, so the two forward passes are bit-identical. Written RED against the
defective code first, and it failed on numbers rather than on a missing import:

```
3 failed, 2 passed
- a scored position's own count moved its prediction
- 23 of 28 scored positions reached the encoder during training
- 40 of 51 scored positions reached the encoder during evaluation
```

The two that already passed are the anti-degenerate direction: perturbing the UNMASKED context must
still move the predictions at the scored positions, so a model that ignored its input entirely
cannot satisfy the isolation property for the wrong reason. The trainer and evaluator are checked by
recording what actually reached the encoder, not by grepping the source, so a fix applied to one
call site and not the other fails.

### Before and after

| Quantity (as measured on 2026-08-31) | Visible input | Hidden input, 12 unclipped epochs |
|---|---|---|
| Pooled held-out co-bps, `train_null` | 1.9116 | **0.0062** |
| Pooled held-out co-bps, `test_mean_null` | 1.8834 | **-0.0219** |
| Per-session range, `test_mean_null` | 1.6500 to 1.9540 | -0.3820 to 0.2084 |
| LOSO mean over finite folds, `test_mean_null` | 1.5110 | **-0.4852** |
| Final training loss (epoch 12) | 0.2439 | 0.5584 |
| Loss reduction over 12 epochs | 43% | 6% |
| Gain from leaking the scored counts back in | about 7.4 bits/spike | 0.064 bits/spike |
| `CO_BPS_MARGIN` | 0.25 | **0.00082** |

The last two rows are the ones that explain the first. A model trained with the answers visible
learns to copy them, and loses about 7.4 bits/spike when they are taken away. A model trained
without them gains only 0.064 when they are handed back, because it never learned to use them. The
1.9116 was almost entirely self-reconstruction.

### What this does to D-14 comparability

D-14 required the Phase-4 config verbatim so the real number would be directly comparable to the
synthetic 0.3804. **That comparability is deliberately broken and is not being recovered.** Phase 4's
0.3804 was produced by this same defective objective, so comparing to it was never meaningful.
Every hyperparameter is still Phase-4-verbatim, for a different reason: so that the objective is the
only variable between the superseded numbers and these.

Plan 09-10's citation sweep now has more to say than it was planned for. It should record that
`04-training-evidence.md`'s 0.3804 is superseded twice over, on synthetic data AND under a defective
objective, and that any document quoting 1.9116 must point here. Nothing outside this plan's files
was edited: PROJECT.md, ROADMAP.md, REQUIREMENTS.md and the Phase 4 and Phase 5 artifacts are 09-10's
scope and are untouched.

## At a glance

| Quantity | Value | Null |
|---|---|---|
| Pooled held-out co-bps | **0.0713** bits/spike | pooled train-split mean rate (the D-22 gate) |
| Pooled held-out co-bps | **0.0432** bits/spike | pooled test mean (NLB convention) |
| Per-session held-out range | -0.2146 to 0.2156 bits/spike | that session's own test mean |
| Per-session, window-weighted mean | **-0.1499** bits/spike | that session's own test mean |
| Leave-one-session-out, 3 of 4 folds | **-0.4427** mean, -0.7580 to -0.2250 | test mean |
| Leave-one-session-out, 4th fold | diverged; non-finite from epoch 8, ran to the 60-epoch cap | not applicable |
| Pooled stopping epoch | **12 of a 60 cap**, `stop_reason=plateau`, **fired at the rule's floor** | not applicable |
| Supplementary budget probe, 60 epochs, pooled | **0.3002** / **0.2721**, 1 of 4 sessions negative | train null / pooled test mean |
| LOSO stopping epochs | 26, 30, 16, and 60 (the diverged fold) | not applicable |
| Re-derived assertion margin | 0.0094 bits/spike | 13.1% of the observation (D-22) |
| Committed slow gate | **RED**: its own training path diverges, now at epoch 4 rather than 8 | not applicable |
| Superseded, 12 unclipped epochs | 0.0062 bits/spike | this file, previous version |
| Superseded, visible input | 1.9116 bits/spike | this file, first version |
| Superseded, synthetic data | 0.3804 bits/spike | `04-training-evidence.md` |

Every value in that table was produced on this machine's CPU from the four manifest-pinned real
sessions. None is estimated, extrapolated, or carried over from another document.

## Environment

| Field | Value |
|-------|-------|
| Machine | Apple M5 Pro, 18 cores, 24 GB. `Darwin 25.5.0` (`xnu-12377.121.6~2/RELEASE_ARM64_T6050`), `arm64` |
| OS | macOS 26.5 (build 25F71) |
| Compute | CPU only, `device="cpu"`. No ANE, no GPU, no `computeUnits` targeting |
| Interpreter | CPython 3.12.13 (uv-managed) |
| torch | 2.12.1 (CPU) |
| numpy | 2.4.6 |
| h5py | 3.16.0 |
| coremltools | 9.0 (installed, unused in this plan) |
| Determinism | `seed = 0` for the global RNG, model init, the training mask generator and every evaluation mask |

The machine identity above is `uname -a` / `sw_vers` / `sysctl machdep.cpu.brand_string` on the host
that produced every number in this file. The M5 Pro is a corroborating development machine, not the
project's canonical iPad Pro M4 capture device; that distinction does not matter here because
nothing in this file is a hardware-gated performance claim.

## Data

Four 96-channel M1-only Indy sessions, materialized under the gitignored `Decoder/data/` and pinned
by SHA-256 in `Decoder/manifests/indy_sessions.json` (Plan 09-05, `09-ingest-evidence.md`). Total
1,767,820,363 bytes, 285,359 bins at 20 ms, calendar span **2016-06-24 to 2016-09-15** (83 days).

Produced by `uv run --project Decoder python Decoder/scripts/report_sessions.py`, verbatim:

| session_id | sha256[:12] | bins | duration_s | mean_rate_hz | median_rate_hz | max_rate_hz | dead_ch | sub_1hz_ch | live_ch | max_count_per_bin | zero_fraction | finger_pos_cols | band |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| indy_20160624_03 | 65937e0cea18 | 24999 | 500.0 | 15.69 | 11.83 | 59.48 | 4 | 4 | 92 | 5 | 0.7533 | 6 | ok |
| indy_20160627_01 | b1a2404f2510 | 168147 | 3362.9 | 19.12 | 15.00 | 53.78 | 4 | 6 | 91 | 5 | 0.7141 | 6 | ok |
| indy_20160630_01 | 2ca8f6b7fcfc | 73161 | 1463.2 | 14.84 | 6.63 | 51.65 | 6 | 9 | 89 | 5 | 0.7870 | 6 | ok |
| indy_20160915_01 | 76175e5bf851 | 19052 | 381.0 | 12.09 | 9.95 | 32.45 | 8 | 8 | 88 | 3 | 0.7992 | 3 | ok |

Full committed SHA-256 pins, copied from the manifest by `train_real.py` at run time and written
into `09-decoder-metrics.json` (never recomputed there, so the published number cites the committed
pin):

| session_id | sha256 |
|---|---|
| indy_20160624_03 | `65937e0cea184b3307a19f84b4d9b44530c95e756e6b42bfad6cc8d55c3bf93f` |
| indy_20160627_01 | `b1a2404f2510475f244077bfc30efbd80148e784ea9263b88f348a8bb15c71e8` |
| indy_20160630_01 | `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8` |
| indy_20160915_01 | `76175e5bf851c123af29178fa7c483588e911a000615438bff97d6f2f2591408` |

Zero sessions were excluded: all four `.mat` files loaded and passed the 96-channel width gate and
the `ndt1.qc` plausibility band. `finger_pos` is six rows wide on three sessions and **three** on
`indy_20160915_01`, so both branches of the loader's `(3, k)` / `(6, k)` handling are exercised by
real data rather than assumed.

### Out-of-window spikes (09-RESEARCH P10)

`bin_spikes` drops every timestamp outside `[t_start, t_end)`, where the window is the behavior
clock's first and last sample. That is correct behavior, and the counts belong in the record rather
than being invisible. `report_sessions.py` re-parses each session to count them and cross-checks the
in-window total against the binned matrix's own sum; all four agree exactly.

| session_id | t_start_s | t_end_s | dropped before | dropped after | in window | matches binned total |
|---|---|---|---|---|---|---|
| indy_20160624_03 | 680.000 | 1179.996 | 5116 | 4229 | 721606 | yes |
| indy_20160627_01 | 105.936 | 3468.880 | 8476 | 4090 | 5852908 | yes |
| indy_20160630_01 | 148.984 | 1612.216 | 6076 | 3300 | 1932293 | yes |
| indy_20160915_01 | 282.956 | 664.000 | 5183 | 3487 | 405497 | yes |

The `indy_20160630_01` row (6076 before, 3300 after) reproduces 09-RESEARCH's independently measured
counts exactly, which is the cross-check that the report's re-parse walks the cell array the same way
`ndt1.data.load_session` does.

### Raw counts, no normalization (D-04)

These are raw spike counts. There is no per-session rate normalization, because the Poisson NLL
objective and co-bps are both defined on actual counts: normalizing would break the metric and its
comparability to Phase 4 and to NLB'21. Session heterogeneity is surfaced instead, as the channel
yield columns above (4 to 8 dead channels per session, 88 to 92 live of 96).

### Unit aggregation: u1 through u5 are SUMMED

Each session's `spikes` cell array is 5 unit rows by 96 channels. `load_session` sums all five into
one multiunit train per channel. This is the correct reconstruction of the total threshold-crossing
count, because Zenodo documents u1 as a **residual**: it "contains the threshold crossings which
remained after the spikes on that channel were sorted into other units". u1 alone is therefore not
the full threshold-crossing train.

Measured share of timestamps in unit row u1, per session (`h5py` walk over the same references the
loader dereferences):

| session_id | u1 | u2 | u3 | u4 | u5 |
|---|---|---|---|---|---|
| indy_20160624_03 | 55.0% | 12.0% | 18.5% | 10.1% | 4.4% |
| indy_20160627_01 | 56.3% | 11.0% | 15.8% | 10.8% | 6.0% |
| indy_20160630_01 | 57.9% | 8.0% | 15.7% | 12.9% | 5.5% |
| indy_20160915_01 | 41.3% | 32.7% | 18.5% | 5.7% | 1.8% |

Choosing u1-only would cut every firing rate roughly in half and therefore move co-bps. 09-RESEARCH
measured that directly on `indy_20160630_01`: 13.82 Hz mean per channel for u1..u5 against 8.00 Hz
for u1 alone (57.9%, matching the timestamp share above) and 5.82 Hz for u2..u5. The aggregation is
u1..u5 and is not a free parameter.

## Methodology

### Split discipline (D-12)

Each session is split independently into a chronological head and tail, `test_frac = 0.2`, and only
then pooled. There is no shuffle split and no pooling before splitting, so no future bin and no
cross-session bin can leak into training (04-RESEARCH pitfall #10). `ndt1.sessions.pooled_splits`
is the single implementation of this.

| session_id | train bins | train windows | test bins | test windows |
|---|---|---|---|---|
| indy_20160624_03 | 19999 | 624 | 5000 | 156 |
| indy_20160627_01 | 134518 | 4203 | 33629 | 1050 |
| indy_20160630_01 | 58529 | 1829 | 14632 | 457 |
| indy_20160915_01 | 15242 | 476 | 3810 | 119 |
| **pooled** | **228288** | **7132** | **57071** | **1782** |

Windows are cut PER SESSION and then concatenated, never cut across a concatenation of sessions. A
32-bin window straddling the boundary between two recordings three days apart would be a fabricated
neural sequence; there are 7132 windows and this discipline costs 2 of them.

**The pool is dominated by one session.** `indy_20160627_01` alone is 168,147 of 285,359 bins, 59%
of the data and 59% of the training windows. Every pooled number below is therefore weighted toward
that session, and the LOSO fold that holds it out trains on only 41% of the corpus. That is stated
here rather than hidden inside a mean.

### Objective

BERT-style masked-modeling Poisson prediction, **corrected from Phase 4 and from the first version
of this artifact** (see "The correction" above). A random 25% of `(bin, channel)` positions is
selected; those positions are zeroed in the encoder input
(`ndt1.loss.hide_scored_positions`, applied by `ndt1.train.masked_forward`); the model emits
log-rates from what remains; and the Poisson NLL is summed over the selected positions only against
the TRUE counts (`ndt1.loss.masked_poisson_nll`, `log_input = True`).

The mask therefore does two jobs, and both are load-bearing: it chooses what is scored, and it
removes what is scored from the input. The model predicts a hidden bin from its surrounding context
and from the other 95 channels at the same timepoint, and never from its own observed value.
Training and every scoring path share one function, so they cannot drift apart.

Gradients are norm-clipped at 1.0 between `backward()` and `AdamW.step()` (Plan 09-06c,
`ndt1.train.DEFAULT_GRAD_CLIP_NORM`). That is a change to the optimization, not to the objective:
the loss, the mask and the input corruption are identical to the previous run's.

There is no velocity or kinematics head in this artifact; the readout is Plan 09-07.

### Config: Phase-4 verbatim except for two named changes (D-14)

| Parameter | Value | Phase-4 verbatim? |
|---|---|---|
| epochs | **12 run, 60 cap, stopped by the pre-registered rule** | **no, deliberately** |
| grad_clip_norm | **1.0** | **no, deliberately** |
| lr | 2e-3 | yes |
| optimizer | AdamW, weight_decay 0.01 | yes |
| batch_size | 16 | yes |
| seq_len | 32 bins (640 ms) | yes |
| mask_ratio | 0.25 | yes |
| test_frac | 0.2 | yes |
| bin_ms | 20.0 | yes |
| seed | 0 | yes |
| device | cpu | yes |
| log_input | true | yes |
| params | 1,292,544 | yes |

Two changes from the previous run and no others. Both were declared in the pre-registration above
before the run started, and neither is presented as free.

**1. Gradient clipping is a second variable, not a free guard.** Pre-clip gradient norms on the
real training path routinely exceed the 1.0 cap (4.67 in the first epoch and 8.0 in the second and
third, measured by `scripts/diagnose_divergence.py`), so the clip rescales ordinary steps and not
only the rare exploding one. With AdamW's per-coordinate normalization a uniform rescale is close
to a no-op in the update, but "close to" is not "exactly", and the trajectory differs from the
unclipped run's from epoch 1 onward. It is named as a change to the configuration under D-14.

**2. The epoch budget was raised in principle and not in practice.** D-14 permits raising the
budget when the curve has clearly not converged and forbids lowering it. The cap went from a fixed
12 to 60 under a rule that decides where inside it to stop. **The rule then stopped the pooled run
at 12**, so the number below was produced at the same budget as the one it supersedes.

**That coincidence is what makes the attribution clean.** Both runs are 12 epochs on the same data
with the same seed under the same objective. The only difference is the clip. So the movement from
0.0062 to 0.0713 is the clip, not the budget, and no third run is needed to separate them. What
remains unmeasured by the headline run is what a LONGER budget would give, which is what the
supplementary probe below is for.

### The two nulls, and why both are reported (P8, T-09-06-04)

co-bps scores the model against a constant per-channel rate predictor, so the choice of constant
moves the number. Three constants are reported:

- **`train_null`** is the per-channel mean of the POOLED TRAIN split. This is the D-22 gate. It is
  leakage-free (fit only on data the model trained on) but it cannot adapt to within-session drift
  or to cross-session heterogeneity. Measured drift on `indy_20160630_01` is 8.1% BELOW the train
  head's mean rate in the test tail, which is the direction that makes this null worse and therefore
  INFLATES co-bps.
- **`test_mean_null`** is the per-channel mean of the evaluation spikes themselves, which is the
  NLB'21 convention. A null fit on the evaluation data is strictly stronger, so this is the
  drift-robust floor.
- **`session_train_null`** is the per-channel mean of that session's OWN train half, reported for
  the per-session held-out evaluation. It sits between the other two and separates within-session
  drift from cross-session heterogeneity, which the pooled `train_null` otherwise conflates. It is
  not required by the plan; it is reported because without it the gap between the other two has two
  possible explanations and no way to tell them apart.

All three are computed on one shared, `seed = 0` mask and one shared forward pass, so they differ
only in the baseline.

## Result

### Pooled held-out co-bps (RD-03)

| Null | Pooled held-out co-bps | 12 unclipped epochs | Visible input |
|---|---|---|---|
| `train_null`, the pooled train-split per-channel mean (the D-22 gate) | **0.0713** | 0.0062 | 1.9116 |
| `test_mean_null`, the pooled test-set per-channel mean (NLB convention) | **0.0432** | -0.0219 | 1.8834 |

Scored on 1,782 held-out windows (57,071 bins, 19.0 minutes of recording) drawn from the four
sessions' chronological tails, on one seeded mask at `mask_ratio = 0.25`. Apple M5 Pro, CPU only,
`seed = 0`. Full precision: 0.07133016502133391 and 0.04319443994223179.

**How to read it.** co-bps is the improvement over a constant per-channel rate predictor, in bits
per spike, so 0 means "exactly as good as predicting each channel's mean rate everywhere". Both
pooled values are above 0 for the first time in this artifact's history. In absolute terms they are
still small: 0.07 bits/spike is roughly a third of the 0.192 AutoLFADS reports on NLB'21 `mc_rtt`,
under a protocol that differs on every axis (see "The protocol is not NLB'21's" below).

**And the pooled null is the weakest one measured here.** It is a per-channel mean taken across
four recordings spanning 83 days, so it cannot track any session's own rate level; a session whose
channels fire above or below the pooled average is easy to beat for a reason that has nothing to do
with modeling the neural dynamics. The per-session table immediately below scores against each
session's own test mean, which is the strongest constant per-channel predictor available, and the
verdict there is different. Both are reported because reporting only the first would be reporting
the more flattering of two numbers that were both measured.

### Per-session held-out co-bps (RD-04a)

| session_id | test windows | `train_null` | `session_train_null` | `test_mean_null` | 12-epoch `test_mean_null` |
|---|---|---|---|---|---|
| indy_20160624_03 | 156 | 0.0019 | -0.1992 | -0.2146 | -0.2338 |
| indy_20160627_01 | 1050 | -0.0713 | -0.1050 | -0.1565 | -0.1946 |
| indy_20160630_01 | 457 | 0.3667 | -0.1965 | -0.2076 | -0.3820 |
| indy_20160915_01 | 119 | 0.6543 | 0.2233 | 0.2156 | 0.2084 |
| unweighted mean | | 0.2379 | -0.0693 | -0.0908 | -0.1505 |
| **window-weighted mean** | | 0.0959 | -0.1148 | **-0.1499** | -0.2192 |
| **pooled** | **1782** | **0.0713** | not applicable | **0.0432** | -0.0219 |

Six things this table says, none of which is visible from the pooled number alone.

1. **Three of the four sessions are negative under both session-specific nulls**, exactly as in the
   12-epoch run. Only `indy_20160915_01` is positive, at 0.2156 to 0.6543. Every cell improved, and
   no cell changed sign.
2. **The pooled value is not any kind of average of the per-session values, and it is larger than
   all of the summaries.** co-bps is a ratio of summed quantities, so pooling weights by held-out
   spike count; but the decisive difference is the NULL, not the weighting. Scored against the
   pooled mean the model is +0.0432; scored against each session's own mean and re-aggregated by
   held-out windows it is -0.1499. The same predictions, the same mask, two nulls, opposite signs.
3. **The one positive session is the smallest.** `indy_20160915_01` is 19,052 bins, 6.7% of the
   corpus, and 119 of 1,782 held-out windows. It is also the width-3 `finger_pos` outlier. One
   number on 119 windows carries far more sampling noise than `indy_20160627_01`'s 1,050, and no
   error bar was computed, so this is not evidence that the model works on that session.
4. **The largest session is the one the model does worst on relative to its own mean.**
   `indy_20160627_01` is 59% of the corpus and scores -0.1565. That is the session the pooled
   training set is dominated by, so it is not a generalization failure; the model simply does not
   beat a constant rate there.
5. **The null-to-null gaps are unchanged from the 12-epoch run to four decimal places.** The
   `train_null` to `session_train_null` gap is 0.2010, 0.0336, 0.5632, 0.4310 here and was 0.2010,
   0.0336, 0.5632, 0.4310 before. A difference between two co-bps values scored against different
   nulls on the same mask cancels the model term exactly, so those gaps are a property of the DATA.
   Their invariance across a completely different checkpoint is a free internal check that the
   re-measurement changed the model and nothing else, and it preserves the earlier conclusion that
   the gap between the gate null and the drift-robust null is cross-session heterogeneity rather
   than the measured 8.1% within-session rate drift.
6. **Improvement is real but partial.** The window-weighted per-session mean moved from -0.2192 to
   -0.1499, about a third of the way to zero. Nothing here supports the statement "NDT1 beats a
   per-channel mean firing rate on this data" without the qualifier "pooled".

### Training loss curve (masked-position Poisson NLL, mean per epoch)

```
epoch  loss              relative change   note
  1    16.5651                             a large first-epoch transient
  2     0.5693           0.965633          recovered
  3     0.5660           0.005869
  4     0.5629           0.005393
  5     0.5615           0.002436
  6    460088591144.74   8.19e+11          a second transient, arrested by the clip
  7     0.5613           1.000000          recovered
  8     0.5590           0.004083
  9     0.5581           0.001496
 10     0.5577           0.000794          inside the 0.001 band
 11     0.5572           0.000827          inside the 0.001 band
 12     0.5571           0.000309          inside the 0.001 band -> RULE FIRES, run stops
```

**The run stopped at epoch 12 with `stop_reason=plateau`, which is `MIN_EPOCHS`, the earliest epoch
the rule can fire.** `09-decoder-metrics.json` records this as `convergence.fired_at_floor = true`,
together with the rule, every per-epoch relative change, and the three the rule inspected, so the
decision can be recomputed from the committed curve without re-running anything.

**This is not a converged asymptote and this artifact does not present it as one.** Three separate
pieces of evidence say so:

- The rule fired at its floor, on three epochs sitting just inside the band (0.000794, 0.000827,
  0.000309 against a 0.001 tolerance). One epoch slightly noisier and it would have continued.
- Three LOSO folds under the **identical** rule, on subsets of the same data, ran 16, 26 and 30
  epochs before flattening. A pooled run that stops at 12 while its own folds take up to 30 has
  more likely hit a quiet stretch than an asymptote.
- The supplementary budget probe below measures directly what more epochs give.

**The curve is also not monotonic, and that matters for how the "did it train" check reads.** Epoch
1 is a 16.57 transient and epoch 6 is 4.6e11. The clip arrested both and the model recovered to
0.5613 by epoch 7, but a `losses[-1] < losses[0]` check on this curve passes partly because epoch 1
was itself an excursion. The honest summary of the descent is 0.5693 (epoch 2, the first clean one)
to 0.5571, a 2.1% reduction, against the 12-epoch unclipped run's 0.5939 to 0.5584, 6%. The clipped
run reaches a LOWER final loss from a worse start.

### Supplementary budget probe (pre-registered above, subordinate to the run reported here)

**The probe answers the budget question decisively, and the answer is that the pre-registered run
stopped far too early.** Identical pooled configuration, identical seed, gradient clipping on, the
convergence rule DISABLED, run to the full 60-epoch cap, `--skip-loso`, into a scratch directory.
69 minutes of CPU. Committed as `09-budget-probe.json`.

| Quantity | Pre-registered run, 12 epochs | Budget probe, 60 epochs |
|---|---|---|
| Pooled, `train_null` | 0.0713 | **0.3002** |
| Pooled, `test_mean_null` | 0.0432 | **0.2721** |
| indy_20160624_03, own test mean | -0.2146 | -0.0777 |
| indy_20160627_01, own test mean | -0.1565 | **+0.0590** |
| indy_20160630_01, own test mean | -0.2076 | **+0.1375** |
| indy_20160915_01, own test mean | 0.2156 | **+0.2361** |
| Per-session, window-weighted, own test mean | -0.1499 | **+0.0790** |
| Sessions negative against their own test mean | 3 of 4 | **1 of 4** |
| Final training loss | 0.5571 | 0.5500 |

**At 60 epochs the model beats each session's own per-channel mean firing rate on three sessions of
four, and the window-weighted per-session mean crosses zero.** That is a different answer to this
artifact's central question than the 12-epoch run gives, and it is the one a reader should weigh
most heavily when asking what this model can do.

### What the probe says about the stopping rule, which is the methodological finding

The probe's first twelve epochs are byte-identical to the headline run's, so the rule would have
fired at epoch 12 on it too. From there the loss falls only from 0.5571 to 0.5500, a further **1.3%**
over 48 epochs, while pooled co-bps rises from 0.0713 to 0.3002, a factor of **4.2**.

**A 0.001-relative plateau criterion on the training loss is a poor proxy for convergence of the
metric being reported, in this regime, and the run demonstrated it rather than assumed it.** The
masked Poisson NLL is dominated by the bulk of easy near-zero bins (the corpus is 71 to 80% empty
bins), so it goes quiet long before the model stops improving on the normalized comparison against
a null that co-bps measures. Tiny loss changes map to large co-bps changes.

The rule was pre-registered honestly and applied without modification, and it was too lax. That is
recorded here rather than repaired after the fact: **moving the tolerance or the floor now, having
seen which setting gives a better number, is exactly the tuning the pre-registration exists to
prevent.** What the rule should become is logged in `deferred-items-09-06c.md` item 4.

### What the probe does NOT establish

- **0.3002 is not converged either.** Its `stop_reason` is `epoch_cap` and
  `convergence.converged = false` is committed in its JSON. The loss was still falling at epoch 60.
  It is a floor, exactly as 0.0713 is.
- **It has no rotation.** `--skip-loso`, so it says nothing about cross-session generalization. The
  only LOSO evidence in this artifact is the 12-to-30-epoch rotation, which is negative on every
  finite fold.
- **It is not the committed checkpoint** and it did not re-derive the margin. Both remain those of
  the pre-registered run, per the pre-registration.
- **It is one seeded run with no error bars**, like everything else here.


### Re-derived assertion margin (D-22)

`CO_BPS_MARGIN` is now **0.0094**, replacing **0.00082**, and before that **0.25**, and before that
the Phase-4 **0.05**.

The value was derived by code from the measurement, not typed by a human who had seen the number:
`train_real.py --derive-margin` reads the observed pooled `train_null` out of the committed metrics
JSON and multiplies it by the fraction Phase 4 used (`0.05 / 0.3804 = 13.1441%`), then rounds to two
significant figures. `0.0713301650 * 0.131441 = 0.009376`, so 0.0094. The generated rationale is
committed at `co_bps.margin_rationale` and mirrored into the constant's comment in
`Decoder/tests/test_heldout_cobps.py`.

**The derivation rule has now survived three re-derivations without being touched.** That is the
point of it. Re-deriving under a rule chosen after seeing a new number is exactly the tuning D-22
exists to prevent, so the same multiplication that produced 0.25 from 1.9116 and 0.00082 from
0.0062 produced 0.0094 from 0.0713. All three predecessors are named in the tests so a regression
says why each is superseded: 0.05 was calibrated on a purpose-built learnable synthetic sinusoid,
0.25 on a self-reconstruction score, and 0.00082 on a truncated unclipped run.

**What a 0.0094 gate is worth, said plainly.** It asserts that the model beats the constant
per-channel mean-rate null by more than 0.0094 bits/spike against the POOLED train-split null, and
nothing more. It is an order of magnitude more meaningful than the 0.00082 it replaces and still
far too small to demonstrate "non-trivial reconstruction" in any strong sense, and it says nothing
at all about the per-session picture where the model is negative on three sessions of four. It is
not inflated to look like a pass. Whether a threshold gate on co-bps is the right shape of
assertion is a question for `decoder-policy.sh` in Plan 09-09; a concrete recommendation is in
`deferred-items-09-06c.md` item 2.

Eight quick tests (`Decoder/tests/test_cobps_margin.py`) hold this in place: the constant is none of
the three superseded values, the JSON carries both the margin and its rationale, the two agree, both
superseded records are still present and labeled, and every superseded record says what replaced
it. The training pass deliberately writes `co_bps.margin = null` on every run, so a re-run without a
re-derivation fails those tests loudly rather than leaving a stale assertion guarding a number that
no longer exists.

### The committed slow gate is still RED, and clipping made its failure earlier

`Decoder/tests/test_heldout_cobps.py` was re-executed on real data with the clip on, and **it still
fails**. It fails earlier than before:

```
uv run --project Decoder pytest Decoder/tests -m slow -k test_heldout_cobps -q
1 failed, 164 deselected in 886.17s (0:14:46)

AssertionError: training did not stay finite, so the co-bps below is a divergence artifact and not
a measure of anything: per-epoch loss [0.5982183587524389, 0.5879459611637176, 0.5826163998232828,
nan, nan, nan, nan, nan, nan, nan, nan, nan]
```

| Run | Per-epoch loss | Outcome |
|---|---|---|
| unclipped | 0.6034 0.5941 0.5848 0.5850 0.5825 0.5801 0.5782 21301.74 26.63 22.93 1.49e22 4.68e22 | finite, never recovers |
| clip 1.0 | 0.5982 0.5879 0.5826 nan nan nan nan nan nan nan nan nan | non-finite from epoch 4 |

**The prediction in `deferred-items-09-06b.md` that clipping "would very likely" fix this was
wrong, and it was checked rather than assumed.** `Decoder/scripts/diagnose_divergence.py` is
committed so the diagnosis is re-runnable rather than a transcript nobody can reproduce. It replays
that exact training path one step at a time:

```
epoch 1: mean loss 0.598218  max pre-clip grad norm 4.67403  max |lograte| 10.49
epoch 2: mean loss 0.587946  max pre-clip grad norm 7.99201  max |lograte| 13.32
epoch 3: mean loss 0.582616  max pre-clip grad norm 7.99201  max |lograte| 13.33
  !! step 1365 (epoch 4): loss=nan max|lograte|=97.33 pre_clip_grad_norm=nan
     grad_nonfinite=True param_nonfinite=True
  top pre-clip grad norms so far: 4.153e+10 (step 1357), 7.992, 4.674, 3.883, 3.707
  top max|lograte| so far: 97.33 (step 1365), 43.73 (step 1357), 17.25, 16.35, 15.05
```

For 1,356 steps the gradient norms peak at 8.0 and the predicted log-rates at 13.3. At step 1357
the model emits a log-rate of 43.7 on a batch it had already seen three times without incident, and
that step's gradient norm is 4.15e10. The clip fires and bounds the step, but the excursion is in
the FORWARD pass: over the next eight steps the log-rate climbs to 97.33, `exp` overflows float32
(above about 88.7), the loss becomes `nan`, and every parameter follows.

**So the ordering is: log-rate excursion first, exploding gradient second.** Gradient clipping acts
on the symptom one step after the cause, which is why it cannot prevent this failure and why it
changed the failure's character instead of removing it. What it does prevent is the other half of
the problem, an outlier gradient poisoning AdamW's moment estimates, and
`Decoder/tests/test_grad_clipping.py` measures that directly on a proxy batch.

The remedy is to bound the Poisson NLL so a large predicted log-rate produces a large FINITE loss
with a finite, correctly-signed gradient that pulls the rate back down: linearize `exp(x)` above a
threshold far outside the data regime. A plain `torch.clamp` is the wrong tool because its gradient
above the bound is zero, so a model that has escaped would get no signal to return. That touches
`ndt1.loss.masked_poisson_nll`, which is the objective, and this task already changes two things;
a third would make the number attributable to none of them. It is logged as
`deferred-items-09-06c.md` item 1 and is the most actionable item this phase has produced.

Note also that this test trains on a **naive concatenation** of the four sessions with a single
chronological split, so its 32-bin windows straddle session boundaries weeks apart, which the
headline path explicitly forbids as a fabricated neural sequence (D-12). It is a gate and never the
headline, and `deferred-items-09-06c.md` item 2 recommends splitting it into a stability gate and a
reproduction check rather than repairing the threshold assertion.

### Input-visibility diagnostic

`train_real.py --diagnostic` loads the committed checkpoint from disk and re-scores it twice on the
same seeded mask: once with the scored positions hidden, as training and scoring both do, and once
with them visible, as the defective objective did on every forward pass. `hidden` is the published
path; `visible` is the probe.

| Eval set | hidden, `train_null` | visible, `train_null` | hidden, `test_mean_null` | visible, `test_mean_null` |
|---|---|---|---|---|
| indy_20160624_03 | 0.0019 | 0.0388 | -0.2146 | -0.1777 |
| indy_20160627_01 | -0.0713 | -0.0192 | -0.1565 | -0.1044 |
| indy_20160630_01 | 0.3667 | 0.4904 | -0.2076 | -0.0838 |
| indy_20160915_01 | 0.6543 | 0.6109 | 0.2156 | 0.1722 |
| pooled | **0.0713** | 0.1334 | **0.0432** | 0.1053 |

Three things.

- **The `hidden` columns reproduce the committed values to full double precision**
  (0.07133016502133391 and 0.04319443994223179), on an independently constructed mask and a
  checkpoint reloaded from disk through `torch.load(weights_only=True)`. That is the
  evaluation-path determinism check (T-09-06-01).
- **Leaking the scored counts back in buys 0.062 bits/spike pooled** (0.0713 to 0.1334), against
  0.064 for the 12-epoch checkpoint and about **7.4** for the checkpoint trained under the
  defective objective. The model still gains almost nothing from being handed the answers, which is
  what a model that never learned to copy them looks like. The gain being essentially unchanged
  from the 12-epoch run is a further sign the clip changed the optimization and not the objective.
- **The `visible` column is not a better number.** This checkpoint never saw uncorrupted inputs at
  scored positions during training, so feeding them is out of distribution. It is a probe, not an
  alternative result, and it must not be quoted as one. It is not uniformly higher either:
  `indy_20160915_01` scores lower with the input visible.

### Reproducibility (T-09-06-01)

| Check | Result |
|---|---|
| Training path | The supplementary budget probe is an independent invocation of the same pooled configuration from the same seed, in a separate process an hour later. **All 12 of the published run's per-epoch losses are reproduced to full double precision**, including the 16.56512170355149 first-epoch transient and the 460088591144.742004 sixth-epoch one. Reproducing a transient of that magnitude bit for bit means the optimizer visited the same states in the same order. |
| Evaluation path | `--diagnostic` reloads the committed checkpoint from disk, builds a fresh `seed = 0` mask, and reproduces every per-session and pooled figure to full double precision. |
| Null-to-null gaps | 0.2010, 0.0336, 0.5632, 0.4310, identical to four decimal places across two checkpoints trained under different numerics. These cancel the model term algebraically, so their invariance is a property of the data and a check on the measurement code. |
| Checkpoint SHA-256 | `af704a93848d2ea6efb69f356e52485693d0ab7da0b9acc94d7390654f316a2d` |

**Slightly weaker than the previous version's claim, and stated as such.** Plan 09-06b executed the
full pooled run twice and compared checkpoint SHA-256 byte for byte. This task did not compare a
final hash: the second invocation is the budget probe, which deliberately continues past epoch 12,
so what is established is that the two runs are numerically identical over the whole span the
published checkpoint was trained for, not that a second file hashed the same. The LOSO rotation was
executed once and has no replication at all.

Scope of the claim: this machine, these pinned wheel versions, CPU, this thread count.
Cross-platform determinism was not tested.

## Multi-session generalization (RD-04)

### The four-fold rotation (D-13)

Each fold retrains from scratch on three sessions' train halves with the identical config and the
identical stopping rule, then evaluates on the held-out session's FULL binned matrix. The full
matrix, not just its test tail, because a held-out session had zero exposure, so every one of its
bins is legitimately held out. Each session is held out exactly once. **Every fold stops
independently under the same rule**, and its stopping epoch is committed.

| Fold (held out) | trained on | train windows | eval windows | epochs | stop | `train_null` | `test_mean_null` | final loss |
|---|---|---|---|---|---|---|---|---|
| indy_20160624_03 | 0627, 0630, 0915 | 6508 | 781 | 26 | plateau | 0.0042 | -0.2250 | 0.5524 |
| indy_20160627_01 | 0624, 0630, 0915 | 2929 | 5254 | 30 | plateau | 0.1245 | -0.3451 | 0.4838 |
| indy_20160630_01 | 0624, 0627, 0915 | 5303 | 2286 | 16 | plateau | 0.4182 | -0.7580 | 0.5864 |
| indy_20160915_01 | 0624, 0627, 0630 | 6656 | 595 | 60 | **epoch_cap** | **diverged** | **diverged** | non-finite (epoch 8) |

Summary over the three folds that produced a value:

| Null | mean | std | min | max | folds | finite | diverged |
|---|---|---|---|---|---|---|---|
| `train_null` | 0.1823 | 0.2130 | 0.0042 | 0.4182 | 4 | 3 | 1 |
| `test_mean_null` | **-0.4427** | 0.2796 | -0.7580 | -0.2250 | 4 | 3 | 1 |

**The meaningful cross-comparison is under `test_mean_null`, not `train_null`.** A LOSO fold's
`train_null` is the mean of three sessions the evaluated session is not among, so it is an even
worse constant predictor than the pooled null, and it inflates the fold's co-bps for a reason that
has nothing to do with generalization. Quoting +0.1823 as "the model generalizes across sessions"
would be quoting the weakest null in this artifact against the hardest task in it.

Under the drift-robust null the comparison is honest:

| Evaluation | mean `test_mean_null` co-bps | 12 unclipped epochs |
|---|---|---|
| in-pool, per-session held-out tails, window-weighted | -0.1499 | -0.2192 |
| leave-one-session-out, three finite folds | **-0.4427** | -0.4852 |

**Every finite fold is negative under the drift-robust null.** On a session it has never seen, this
model is worse than that session's own constant per-channel mean rate, by 0.23 to 0.76 bits/spike.
Every fold improved on its 12-epoch counterpart and none changed sign. D-15 named this outcome in
advance as a legitimate result: a LOSO number near zero or negative means channel identity did not
transfer across sessions. It is what the rotation produced, for the second time.

Three of the four folds ran 16, 26 and 30 epochs before the rule fired, all above the 12-epoch
floor, with `convergence.fired_at_floor = false`. That is direct evidence that the pooled run's
stop at 12 was a quiet stretch rather than an asymptote.

### The fold that diverged, and the fold that stopped diverging

**Clipping relocated the instability rather than removing it. One quarter of the rotation is still
lost, as in the previous run, but it is a different quarter.**

The fold holding out `indy_20160627_01` blew up at epoch 7 in the unclipped run (268,623.80, then
non-finite by epoch 12). With the clip it trains cleanly for 30 epochs and produces a value:

```
0.5259 0.5044 0.5022 0.4986 0.4996 0.4998 0.4961 0.4934 0.4911 0.4924 0.4894 0.4891 0.4874 0.4858
0.4870 0.4857 0.4855 0.4854 0.4849 0.4849 0.4843 0.4873 0.4846 0.4845 0.4847 0.4842 0.4832 0.4836
0.4835 0.4838
```

**That is a real, verified fix: one of the three observed divergences is closed by gradient
clipping.** It is also the hardest fold, trained on the fewest windows (2,929) and evaluated on the
most (5,254), because it holds out the session that is 59% of the corpus.

The fold holding out `indy_20160915_01` was clean in the unclipped run (final loss 0.5654). With
the clip it goes non-finite at epoch 8 and, because the rule can never report a non-finite curve as
converged, runs the full 60-epoch cap producing `nan`. It contributes nothing to the summary and
its loss curve is committed so the epoch is auditable.

So the ledger on the three divergences 09-06b reported, checked rather than assumed:

| Divergence | Under clipping |
|---|---|
| LOSO fold holding out `indy_20160627_01`, blow-up at epoch 7 | **fixed**, trains to 30 epochs |
| The committed slow gate, blow-up at epoch 8 | **worse**, non-finite at epoch 4 |
| LOSO fold holding out `indy_20160624_03` (a silent NaN under the DEFECTIVE objective) | already fixed by 09-06b; still clean, 26 epochs |
| New: LOSO fold holding out `indy_20160915_01` | **introduced**, non-finite at epoch 8 |

The pooled run itself survived two large transients, at epoch 1 (16.57) and epoch 6 (4.6e11), and
recovered from both. Under the unclipped objective the pooled run had neither.

The mechanism is unchanged and is diagnosed to the step in "The committed slow gate is still RED"
above: the `log_input=True` Poisson NLL has model term `exp(rate) - target * rate`, `exp` overflows
float32 above about 88.7, and a predicted log-rate excursion therefore destroys the run before the
gradient clip can see the gradient it produces. **The honest reading is that this configuration sits
close to the numerical stability edge on real spikes under both objectives and both numerics, that
gradient clipping moves which run falls off it rather than moving the edge, and that a rotation
summary resting on three of four folds is weaker evidence than one resting on four.**

### The cross-session assumption, stated as a prior (D-15, corrected by C-04)

Pooling raw 96-channel spike counts across sessions spanning **2016-06-24 to 2016-09-15**, a span of
83 days, assumes stable channel-to-neuron identity across electrode drift. Utah-array unit identity
is not stable across days: extracellular waveforms change within a single day and performance
instability is attributed to electrode drift plus neuroplasticity. Channel 37 in June and channel 37
in September are the same electrode, not reliably the same neuron.

That assumption is exactly what session-conditioned modeling relaxes. **NDT2** conditions on session
identity so that a per-session embedding absorbs the drift instead of the shared weights having to
average over it. NDT2 is explicitly out of scope for v0 and v1 of this project, which is why the
assumption is stated here rather than engineered away.

This paragraph is a statement of prior expectation, written before any of these numbers were known,
in the plan that preceded the superseded run, and not retrofitted to either set:

- A pooled number BELOW the per-session numbers is an expected and reportable outcome, not a defect.
  (Observed under the corrected objective: the pooled value, -0.0219, is ABOVE the per-session mean
  of -0.1505, because co-bps pools by held-out spike count rather than by session.)
- A LOSO number near zero or negative is a legitimate result meaning channel identity did not
  transfer. (Observed under the corrected objective: **every finite fold is negative**, mean -0.4852
  under the drift-robust null. This is the branch the prior named, and it is what happened.)

Neither outcome would have changed what was reported. Under the superseded objective the second
branch appeared not to fire; under the corrected one it does. That is worth stating explicitly,
because a prior that names an outcome in advance and then observes it is the strongest form of
evidence this artifact can offer that the number was not shaped after the fact.

## What this number is NOT (D-23)

### It is not a converged number, and the probe proves it rather than suggesting it

The pooled run stopped at 12 epochs because the pre-registered rule fired at its floor, on three
relative changes sitting just inside a 0.001 band, while three LOSO folds under the identical rule
ran 16 to 30 epochs. **The budget probe then measured what was left on the table: a further 1.3%
of training loss between epochs 12 and 60, worth a 4.2x increase in pooled co-bps.**
`convergence.fired_at_floor = true` is committed in the metrics JSON for exactly this reason.
0.0713 is a 12-epoch number and 0.3002 is a 60-epoch number that also hit its cap without
converging. Both are floors.

### It is not a statement that NDT1 beats a mean-rate null on this data, without a budget attached

At 12 epochs it beats the POOLED null and loses to each session's own test mean on three sessions
of four, and to a held-out session's own mean on every fold that finished. At 60 epochs it beats
each session's own test mean on three of four. **Any one-line quotation of either number without
the epoch count and the null attached misrepresents what was measured.** The cross-session result
is the one that did not get a longer-budget measurement at all: the only rotation in this artifact
is negative on every finite fold.

### It does not establish that NDT1 cannot do better

The run had two large loss transients, one quarter of the rotation diverged, the zero-masking
choice biases predictions at scored positions downward by an unmeasured amount, and no learning
rate, mask ratio, architecture, seed or schedule was explored. None of that was tried, on purpose:
this task changed two named things and reported both.

### It does not establish that masked modeling is the wrong pretraining task

co-bps here is a reconstruction score, and a model can be a poor bin-level reconstructor and still
learn representations that decode velocity well. The kinematic decode is Plan 09-07 and is the
number that speaks to the project's actual goal. Nothing in this file should be read as predicting
it.

What the number does establish is narrow and worth having: **under a correct masked objective, with
gradient clipping, at 12 epochs, this model extracts a little more about a hidden 20 ms bin from
its surrounding context than a pooled per-channel mean rate provides, and less than the session's
own per-channel mean rate provides on three of the four sessions.**

### The superseded numbers, and how they may be used

Three are retained in `09-decoder-metrics.json` and quick tests fail if any is removed.

- **1.9116**, under `superseded_visible_input_objective`. It may be cited as a historical record of
  what this repository measured and when. It **must not** be cited as a decoder result, a co-bps, or
  a comparison against any benchmark: about 7.4 of its span came from the model reading the values
  it was scored on.
- **0.0062**, under `superseded_truncated_budget`. Its objective was already correct, so unlike the
  1.9116 it is not a self-reconstruction score. It may be cited as what a 12-epoch unclipped run
  produced under the corrected objective. It must not be cited as this repository's current number.
- **0.3804**, in `04-training-evidence.md`, measured on synthetic data under the defective
  objective.

### The protocol is not NLB'21's

NLB'21's `mc_rtt` task is cited here for scale only. Its protocol differs from this one on every
axis that matters:

| Axis | NLB'21 mc_rtt co-bps | This repo's `ndt1.metrics.co_bps` |
|---|---|---|
| Session | `indy_20170202_02` | `indy_2016*` M1-only sessions |
| Units | 130 sorted single units, 98 held-in / 32 held-out | 96 channels of summed threshold crossings |
| Bin | 5 ms | 20 ms |
| Segments | 600 ms trials, overlap allowed | 32-bin (640 ms) non-overlapping windows |
| What is held out | neurons (co-smoothing) | a random 25% of (bin, channel) positions |
| Is the held-out value visible to the model | no | no (zeroed in the encoder input) |
| Scored over | held-out neurons, all timepoints | selected positions across all channels |
| Null rate source | mean of the evaluation spikes | mean of the train split (both reported here) |

The bits arithmetic is the same in both: `(NLL_null - NLL_model) / (masked spike count * ln 2)` under
a Poisson likelihood. So the units are the same and the protocols are not.

Published NLB'21 `mc_rtt` baselines, for scale and never as a leaderboard comparison: Smoothing
0.147, GPFA 0.155, SLDS 0.165, NDT 0.160, AutoLFADS 0.192 bits/spike.

The table above is why no version of this number was ever a like-for-like comparison. The superseded
1.9116 sat an order of magnitude ABOVE those baselines, which should have been read as a warning
rather than a result, and was: it is what motivated the audit that found the defect. The current
0.0713 sits at roughly a third to a half of them under the pooled null, and the per-session values
sit below zero. Neither fact says this decoder is better or worse than AutoLFADS, because the
protocols differ on session, units, bin width, segmentation, and what is held out. The baselines are
here to answer "what magnitude of co-bps do people report on primate M1 reach data", and the answer,
roughly 0.15 to 0.2, is the context in which 0.0713 should be read.

**Correction, stated plainly (C-03).** NLB'21's `mc_rtt` task uses `indy_20170202_02`, recorded
2017-02-02, per DANDI dandiset 000129 asset metadata. That session is not in Zenodo record 3854034
at all. This repository previously asserted that `indy_20160630_01` was the session behind that
benchmark; that claim was false and is retracted here. None of the four sessions used in this
artifact appears in NLB'21.

## Supersedes

Three numbers, for three different reasons, none of them deleted.

**0.0062, published in the previous version of this file.** Real spikes, correct objective, but a
fixed 12-epoch budget inherited from Phase 4 (where it had been calibrated against the DEFECTIVE
objective) and no gradient clipping, on a curve still descending when the budget ran out and with
one LOSO fold and the committed slow gate diverging. Retained as `superseded_truncated_budget`.
Everything derived from it is superseded with it: the per-session range, the LOSO mean -0.4852, and
the assertion margin 0.00082.

**1.9116, published in the first version of this file.** Real spikes, but under an objective in
which the encoder received the true count at every position it was scored on. Retained as
`superseded_visible_input_objective`.

**0.3804, from `04-training-evidence.md`.** Measured on a synthetic Poisson fallback because no real
`.mat` was present under `Decoder/data/` when Phase 4 ran. Superseded twice over: synthetic data AND
the defective objective.

Per D-24 no historical artifact is retroactively rewritten: it records what that phase actually
measured, and rewriting it would destroy the record rather than correct it. **Note for Plan 09-10:**
its citation sweep now has a three-link chain to label. `04-training-evidence.md` needs a superseded
banner; no document may quote 1.9116 as a decoder result; and any document quoting 0.0062 must
point here. `.planning/PROJECT.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md` and the
Phase 4 and Phase 5 artifacts were deliberately not touched by this correction; they are 09-10's
scope.

`Decoder/tests/test_heldout_cobps.py` also changes meaning: with `Decoder/data/` materialized its
`_load_binned()` takes the real-session branch, so the slow gate it enforces is a real-data gate;
it scores through `masked_forward`; and its `CO_BPS_MARGIN` was re-derived from the corrected
observation. It remains RED for the reason given above.

## Gaps and what would close them (D-25)

A low honest number completes this phase; so does a higher one that is honestly qualified. D-25 was
written for exactly this: **the deliverable is that the decoder has seen real primate M1 spikes and
that every number is measured under an objective and a numerical regime that mean what they say.**
These are the gaps, recorded as backlog and not as scheduled scope.

0. **CLOSED: the objective does not hide what it scores.** Plan 09-06b. `ndt1.train.masked_forward`
   hides the scored positions in training and in every scoring path, and
   `Decoder/tests/test_masked_input_isolation.py` fails if that is reversed.

1. **PARTLY CLOSED: numerical instability.** Gradient clipping at `max_norm = 1.0` is on by default
   and it verifiably fixed one of the three observed divergences (the LOSO fold holding out
   `indy_20160627_01`, which now trains to 30 epochs). It did not fix the committed slow gate, it
   made that failure earlier, and it introduced a new divergence in a fold that had been clean.
   **Closing the rest:** linearize `exp(x)` in `masked_poisson_nll` above a threshold far outside
   the data regime, so an escaped log-rate yields a finite correctly-signed gradient instead of an
   overflow. Diagnosed to the step, with a committed re-runnable probe, in
   `deferred-items-09-06c.md` item 1. **This is the most actionable item in the phase**, and it
   also blocks gap 2, because a run that cannot survive more epochs cannot answer a budget question.

2. **MEASURED, NOT CLOSED: the budget, and it is worth more than anything else changed here.** The
   rule fired at its 12-epoch floor, so the published number was produced at the same budget as the
   one it supersedes. The supplementary probe measures 60 epochs on the pooled path: pooled co-bps
   0.0713 to 0.3002, and sessions below their own mean 3 of 4 down to 1 of 4. **Closing it:** re-run
   the full rotation and the margin derivation at a budget the probe justifies, under a stopping
   rule that is not the one this task pre-registered (see gap 3). Not done here, because a rule
   retuned after seeing which setting gives a better number is the tuning the pre-registration
   exists to prevent, and because the probe itself hit its cap without converging.

3. **NEW: the pre-registered stopping rule is too lax for this metric, demonstrated rather than
   suspected.** Between epochs 12 and 60 the training loss falls 1.3% while pooled co-bps rises 4.2x.
   The masked Poisson NLL is dominated by the 71 to 80% of bins that are empty, so it goes quiet long
   before the model stops improving on a normalized comparison against a null. **Closing it:** define
   convergence on a held-out quantity rather than the training loss, or on the reported metric's own
   stability with the same "cannot see the value" discipline (for example, stop when the held-out
   co-bps has changed by less than X for K epochs, which is a rule on stability rather than on
   level). `deferred-items-09-06c.md` item 4.

4. **Budget and clipping are two changes, but the attribution happens to be clean.** Because the
   rule stopped the run at 12 epochs, the headline run and the run it supersedes have the SAME
   budget, so the movement from 0.0062 to 0.0713 is attributable to the clip alone. That was luck,
   not design: had the rule fired at epoch 40 the two changes would have been inseparable without a
   third run.

5. **The zero-masking ambiguity is unquantified.** Zeroing a masked bin is indistinguishable from a
   genuinely silent bin, which biases predictions at scored positions downward by an amount this
   work did not measure. The reported values are therefore a lower bound. **Closing it:** train a
   variant with a learned mask embedding and compare. That needs either a 97th input channel or a
   new `nn.Parameter`, both of which touch the Core ML conversion path or the guarded parameter
   count, so it is its own plan.

6. **Four sessions, one dominant.** 59% of the corpus is one recording, and the one session with a
   positive co-bps is the smallest (119 held-out windows). More sessions of comparable length would
   make both the pooled number and the rotation more even.

7. **No error bars anywhere.** Every number here is a single seeded run. The per-session values,
   resting on 119 to 1,050 windows, have sampling variability that was not quantified. **Closing
   it:** multiple seeds, or a bootstrap over held-out windows. This matters most for
   `indy_20160915_01`, the only positive session and the smallest.

8. **Reproducibility is weaker than the previous version's.** That run trained the pooled
   configuration twice and compared checkpoint SHA-256 byte for byte. This one did not; its
   corroboration is a first-epochs match from the budget probe plus a full evaluation-path replay.

9. **No session conditioning.** See the D-15 statement in the generalization section. It is the
   modeling change most directly aimed at the negative LOSO result.

10. **No velocity readout in this artifact.** The kinematic decode number is Plan 09-07; this file is
   reconstruction only, and a poor reconstruction co-bps does not by itself predict a poor velocity
   decode.

11. **Determinism is verified for this machine and these wheel versions**, not across platforms.
    The config and the pinned versions are committed so a divergence elsewhere is diagnosable.

## Reproduce

Every number in this file comes from the commands below, in this order, on the machine described in
the Environment table. Nothing here runs in CI (D-21): the Decoder quick suite is the CI gate, and it
never trains and never downloads the dataset.

```sh
# 1. Materialize the pinned venv (CPython 3.12 + torch 2.12.1 + coremltools 9.0).
uv sync --project Decoder --extra dev

# 2. Materialize and verify the 1.77 GB dataset (gitignored; see 09-ingest-evidence.md).
uv run --project Decoder python Decoder/scripts/download_indy.py

# 3. The per-session ingest report (the Data tables above).
uv run --project Decoder python Decoder/scripts/report_sessions.py

# 4. Wiring check, about one minute, on the two smallest sessions. Never a committed number.
uv run --project Decoder python Decoder/scripts/train_real.py --smoke

# 5. The real run: pooled training under the pre-registered convergence rule, per-session held-out
#    co-bps, and the four-fold LOSO rotation. 2.72 h of CPU on this machine, of which about an hour
#    is the diverged fold running out its 60-epoch cap. Writes co_bps.margin as null by design.
uv run --project Decoder python Decoder/scripts/train_real.py

# 6. Record the stopping decision: the rule, every per-epoch relative change, the three the rule
#    inspected, and convergence.fired_at_floor. Step 5 already writes this; the flag re-derives it
#    from the committed curves for a JSON produced before the record existed.
uv run --project Decoder python Decoder/scripts/train_real.py --annotate-convergence

# 7. Measure the input-visibility probe on the committed checkpoint (about 30 s).
#    Its hidden_* columns must reproduce step 5's numbers exactly; that is the eval-path check.
uv run --project Decoder python Decoder/scripts/train_real.py --diagnostic

# 8. Derive the D-22 assertion margin FROM the observed value and write it back with its rationale.
#    This runs only after the number exists; the margin never precedes the measurement.
uv run --project Decoder python Decoder/scripts/train_real.py --derive-margin

# 9. The supplementary budget probe: the same pooled config with the convergence rule DISABLED,
#    run to the full 60-epoch cap, into a scratch directory so it cannot touch the published
#    artifact. Pre-registered above. About 70 minutes.
uv run --project Decoder python Decoder/scripts/train_real.py --no-plateau-stop --skip-loso \
  --checkpoint-dir Decoder/checkpoints/budget_probe \
  --out-json Decoder/checkpoints/budget_probe/09-budget-probe.json

# 10. The divergence diagnosis: replays the slow gate's training path one step at a time and prints
#     the pre-clip gradient norm and max |log-rate| per step. Pass --clip 0 for the unclipped run.
uv run --project Decoder python Decoder/scripts/diagnose_divergence.py --clip 1.0 --epochs 4

# 11. The quick gate (no dataset needed) and the slow real-data gate (about 15 minutes, RED).
uv run --project Decoder pytest Decoder/tests -m "not slow" -q
uv run --project Decoder pytest Decoder/tests -m slow -k test_heldout_cobps -q
uv run --project Decoder ruff check Decoder
```

Model weights are gitignored by the Plan 04-01 artifact policy. The committed evidence is this file
plus `09-decoder-metrics.json`; the weights are reproduced from `seed = 0` by step 5.
