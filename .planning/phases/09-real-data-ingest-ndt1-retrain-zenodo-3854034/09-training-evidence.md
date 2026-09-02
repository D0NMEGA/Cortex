# Phase 9 RD-03 / RD-04 evidence: NDT1 trained on real primate M1 spikes

**Date:** 2026-08-31, revised 2026-09-02 (Plan 09-06d). Read the pre-registration below before the
numbers.
**Result:** pooled held-out **co-bps = 0.4096 bits/spike** against the train-split per-channel
mean-firing-rate null and **0.3814** against the pooled test-mean null, measured on **real
O'Doherty/Makin Indy M1 spikes (Zenodo record 3854034)**, four sessions, CPU only, at a
pre-registered 200-epoch cap with no stopping rule, with the scored positions hidden from the
encoder, gradients norm-clipped, and the Poisson NLL linearized against forward-pass overflow.

## The finding: it decodes within a session and does not transfer across sessions

This is the headline, and it is a split rather than a single number.

| | Against each held-out set's OWN mean firing rate | Verdict |
|---|---|---|
| **Within session** (pooled model, each session's chronological tail) | +0.2127, +0.1661, +0.2062, +0.2455 | **4 of 4 positive** |
| **Across sessions** (leave-one-session-out, unseen session) | -0.1238, -0.3060, -0.7805, -0.1890 | **4 of 4 negative**, mean -0.3498 |

**The model beats a per-channel mean firing rate on held-out data from sessions it trained on, and
loses to it on a session it has never seen.** Every session is positive within-session, by 0.17 to
0.25 bits/spike against the strongest constant per-channel predictor available. Every fold is
negative across sessions, by 0.12 to 0.78.

**Do not quote the rotation's `train_null` mean of +0.2446 as a cross-session result.** It is
positive, and it is the wrong null for that question: it is the mean of the three sessions the fold
trained on, so it cannot track the held-out session's own rate level. Scored against the held-out
session's own mean -- which is what "did this transfer" actually asks -- the same four folds give
-0.3498. The gap between those two numbers, 0.59 bits/spike, IS the cross-session heterogeneity.
That is the tell, and it is why both nulls are reported everywhere in this file.

## The earlier "it does not beat the null" was a budget artifact, not a property of the model

09-06b and 09-06c both reported three of four sessions losing to their own test mean. Both were
12-epoch runs. At 200 epochs all four are positive. **The negative per-session verdict this
artifact carried through two corrections was an artifact of the epoch budget.** The trajectory
below shows where it flipped: pooled co-bps crosses zero between epochs 10 and 20 and is still
climbing steeply at the budget both earlier runs stopped at.

| Arm | Budget | Pooled `train_null` | Pooled `test_mean_null` | Sessions below their own mean | LOSO folds finite |
|---|---|---|---|---|---|
| 09-06, defective objective | 12 | 1.9116 | 1.8834 | n/a, invalid | n/a |
| 09-06b, corrected, unclipped | 12 | 0.0062 | -0.0219 | 3 of 4 | 3 of 4 |
| 09-06c, clipped, rule fired at its floor | 12 | 0.0713 | 0.0432 | 3 of 4 | 3 of 4 |
| **09-06d, this run, no stopping rule** | **200** | **0.4096** | **0.3814** | **0 of 4** | **4 of 4** |

## The headline is one sample from an oscillating plateau, and that is a precision limit

**0.4096 / 0.3814 is the value at the cap, exactly as pre-registered, and it is not a converged
value to four figures.** The trajectory climbs monotonically to about epoch 70 and then plateaus
and oscillates for the remaining 130 epochs.

| Post-plateau statistics, epochs 70 to 200, 14 sampled points | `train_null` | `test_mean_null` |
|---|---|---|
| Mean of the samples | 0.3562 | 0.3281 |
| Standard deviation | 0.0524 | 0.0524 |
| Minimum, maximum | 0.2437 to 0.4209 | 0.2155 to 0.3928 |
| Full range (half-range) | 0.1773 (+/-0.0886) | 0.1773 (+/-0.0886) |
| The reported value at the cap | **0.4096** | **0.3814** |
| Where the cap value sits in that band | 12th of 14 samples | 12th of 14 samples |

**So a single-epoch sample of this metric carries roughly +/-0.09 of noise once the run has
plateaued, and the epoch-200 sample happens to land high in the band.** Quoting 0.4096 as a precise
converged value would overstate the precision by about an order of magnitude. The honest statement
is "about 0.33 to 0.36 with a single-sample spread of +/-0.09, and 0.4096 at the pre-registered
reporting epoch". The cap value is reported unchanged because the pre-registration said the
headline is the value at the cap and because averaging the plateau after seeing its shape would be
a post-hoc estimator this run has no pre-registration for.

**The pre-registered floor criterion fires, but not for the reason it was written for.** It asked
whether co-bps moved less than 1% of the headline over the last 50 epochs; it moved 24.1%
(`train_null`) and 25.9% (`test_mean_null`), so **the headline is labeled a floor**. Reading the
trajectory rather than the criterion, that 24% is oscillation and not a climb: the training loss
falls only 0.31% over those same 50 epochs and 0.62% from epoch 70 to 200. The run is plateaued in
loss and noisy in co-bps, which is a different situation from "still improving" and is reported as
such.

## The loss stabilizer was not inert, it fired twice, and both times the run survived

The pre-registration committed to reporting this either way, and it came out the informative way.
`ndt1.loss.stable_exp` linearizes `exp` above `C = 20`, and the run records the largest predicted
log-rate of every epoch of every model it trains:

| Where | Epoch | Max log-rate | Loss at that epoch | What the pre-09-06d objective does at that log-rate |
|---|---|---|---|---|
| Pooled run | 6 of 200 | **69.94** | 8,470.04 | finite but enormous; 09-06c recorded 460,088,591,144.74 at this same epoch |
| LOSO fold holding out `indy_20160915_01` | 7 of 60 | **149.32** | 26,374.18 | `exp(149.32)` is `inf` in float32, so `nan`, which is exactly what 09-06c got on this same fold |

**149.32 is 1.68x the float32 `exp` overflow bound of 88.7.** That is the case the linearization
exists for and the case a `torch.clamp` could not have rescued: clamping yields a gradient of
`-target` above the bound, which drives an escaped rate further up. Both excursions recovered on
the very next epoch (0.5623 and 0.5661) and both runs went on to finish their full budget.

**The consequence for attribution, stated rather than glossed.** The stabilizer is proven
bit-identical below `C` in value and gradient (`tests/test_loss_stability.py`, `torch.equal` over a
2,054-point grid), and epochs 1 through 5 of this pooled run reproduce 09-06c's per-epoch losses
exactly. But it activated at epoch 6, so from epoch 6 onward this is a different trajectory from
09-06c's, and **the movement from 0.0713 to 0.4096 is not attributable to the epoch budget alone.**
Two changes are in this run and both are named: the budget and the stabilizer.

### The four numbers this file supersedes

All four are preserved, labeled, in `09-decoder-metrics.json`, and quick tests fail if any is
deleted. Correcting a published number means labeling the old one.

| Value | Where | What was wrong with it |
|---|---|---|
| **0.3804** | `04-training-evidence.md` | Measured on a **synthetic Poisson fallback**: no real `.mat` was under `Decoder/data/` when Phase 4 ran. Doubly superseded, because it used the defective objective too. |
| **1.9116** | this file, first version | The encoder could read the value at every position it was scored on, so it measured self-reconstruction. `superseded_visible_input_objective`. |
| **0.0062** | this file, second version | Objective already correct; the run was 12 unclipped epochs on a curve that had not flattened, and one LOSO fold and the committed slow gate diverged. `superseded_truncated_budget`. |
| **0.0713** | this file, third version | Objective correct and gradients clipped; a pre-registered stopping rule fired at its own 12-epoch floor, leaving most of the available co-bps unmeasured, and a forward-pass overflow the clip could not reach cost one LOSO fold. `superseded_rule_stopped_at_floor`. |

**This is not a hardware-gated claim.** It is CPU-only decoder R&D that reproduces on any Mac CPU
with the pinned wheels. There is no Neural Engine, Core ML, palettization or latency number in this
file; those are Plans 09-07 and 09-08.

## Plan 09-06d: pre-registration, written before the run

**This section was written and committed BEFORE the run it describes was started.** Its commit
precedes the commit that carries the numbers, and `git log` is the check. That is the third time in
this chain, and the reason is unchanged: a budget or a rule chosen after seeing the curve is a
tuned result with extra steps.

### The problem this run exists to remove

09-06c's stopping rule was defined on the training loss, could not see a co-bps, was committed
before the run, and was applied without modification. It still produced a bad number, and the
subordinate probe measured exactly how bad: **the rule fired at its 12-epoch floor, and between
epoch 12 and epoch 60 the training loss falls 1.3% while pooled co-bps rises 4.2x.** A plateau
criterion on a masked Poisson NLL that is 71 to 80% empty bins goes quiet long before the model
stops improving on the normalized comparison co-bps measures.

The tempting move is a better stopping rule. That move is refused here. Any rule that stops
somewhere inside the curve is a selection, and a selection made after seeing that longer is better
is a tuned budget however it is dressed up. **This run removes the selection instead of replacing
it:** train to a large cap, record co-bps along the way, and publish the whole trajectory. The
headline is the value AT THE CAP. A reader sees where it plateaus and judges convergence without
taking anyone's word for it.

### What is being changed, and only this

Everything else is byte-for-byte identical to 09-06c: `lr = 2e-3`, `batch_size = 16`,
`seq_len = 32`, `mask_ratio = 0.25`, `seed = 0`, `test_frac = 0.2`, `weight_decay = 0.01`,
`log_input = true`, `grad_clip_norm = 1.0`, the architecture, and the corrected input-masking
objective.

**1. The forward-pass overflow is fixed, in the loss.** 09-06c diagnosed it and deliberately did
not fix it, because that task already had two variables. `ndt1.loss.masked_poisson_nll` now
computes `stable_exp(x) - target * x`, where `stable_exp` is `exp` below a threshold `C` and the
tangent line to `exp` at `C` above it.

| | |
|---|---|
| `C` | `LOG_RATE_LINEARIZE_ABOVE = 20.0` |
| Healthy regime | real 20 ms bins carry 0 to 5 spikes; the per-channel mean rate is about 0.3 spikes/bin, so a healthy log-rate sits near `log(0.3) = -1.2`. The largest `\|log-rate\|` ever observed over a clean epoch of this training path is **13.3** (09-06c's committed replay). |
| Why 20 is above it | `exp(20)` is 4.85e8 spikes per 20 ms bin: eight orders of magnitude beyond the largest count in the corpus, and 812x further out in rate space than that observed maximum. |
| Why 20 is below the ceiling | float32 `exp` overflows above about **88.7**. At `C = 20` the constant gradient `exp(C)` is 4.85e8, so the linear branch is still finite at a log-rate of 1e20 and the sum of squares inside `clip_grad_norm_` cannot itself overflow. A larger `C` buys nothing (the loss at the threshold is already astronomical) and costs both margins. |
| Not `torch.clamp` | above a clamp bound the derivative of the clamped `exp` is zero, so all that survives is the `- target * x` term and the total gradient is `-target`: NEGATIVE, so a descent step drives an already-escaped rate further up. That wrong sign is asserted in `tests/test_loss_stability.py`, not argued for. |

**Why this is not a third variable, and how that claim is checked rather than asserted.**
`tests/test_loss_stability.py` asserts with `torch.equal` that below `C` the stabilized loss is
bit-identical to the unmodified `nn.PoissonNLLLoss` formulation **in value and in gradient**, over
a 2,054-point grid from -40 up to one thousandth below the threshold. So the guard can only change
a run that would otherwise have produced `nan`. On top of that proof, the run itself records
`max_log_rate_per_epoch` for every epoch of every model it trains, and this evidence will publish
the maximum over the whole run: **if that maximum stays below 20, the stabilizer provably never
activated and the epoch budget is the only variable between this run and 09-06c's.** If it does
activate, that is reported, with the epoch it happened at.

**2. The stopping rule is removed and the cap is raised from 60 to 200.** `--plateau-stop` keeps
the 09-06c rule available for reproduction; it is off. The run goes to the cap, `stop_reason` is
`epoch_cap` by design, and the headline is the last row of the trajectory.

### The run plan

Registered before anything was launched. There is no stopping rule to register this time, so what
is registered is the cap, the sampling interval, and the rotation's budget.

| Parameter | Value | Why this value |
|---|---|---|
| `EPOCH_CAP` (pooled) | **200** | A compute bound, not a result-shaped choice. The 09-06c probe measured 4137.8 s for 60 pooled epochs, i.e. 69 s/epoch on 7,132 windows, so 200 epochs is about 3.8 h of CPU. It is 3.3x the largest budget this phase has run and 16.7x the budget of the number it supersedes. |
| `COBPS_SAMPLE_EVERY` | **10** | Held-out pooled co-bps against BOTH nulls at epoch 1, then every 10th epoch, then at the cap: 21 points. Dense enough to see a plateau, cheap enough not to distort the run (about 5 s per scoring pass against a 69 s epoch). |
| `LOSO_EPOCH_CAP` | **60** | A COST decision, declared as one. See below. |
| Stopping rule | **none** | The run ends at the cap and nowhere else. |
| Checkpoint | **the model at the cap** | Not the model at whichever epoch scored best. There is no epoch selection anywhere in this run, including in what gets saved. |

**The rotation's budget is a cost decision, and it is labeled as one rather than presented as a
result.** Ideally the four folds would run at the same 200-epoch cap as the pooled run. They will
not: the folds are 21,396 training windows against the pooled 7,132, so a full-cap rotation is
about 11.5 h of CPU ON TOP of the 3.8 h headline run. 60 epochs per fold is about 3.5 h and is
**not a new number** -- it is the epoch cap 09-06c had already committed, so the reduced budget is
an inherited constant rather than one chosen for this run. All four folds get the same budget, all
four run to it, each fold's budget is recorded beside its number, and the consequence is stated
wherever the rotation is quoted: **the folds are less trained than the headline model, so a
cross-session number from them is a floor for that budget and is not comparable to the pooled
figure as though both had been trained equally.** A full rotation is still run: four folds, each
session held out exactly once, and any divergence is recorded rather than dropped.

### What will be reported, whichever way it comes out

- **The full co-bps-versus-epoch trajectory**, in `09-decoder-metrics.json` as an explicit array
  and in this file as a table, against BOTH nulls. The headline is the row at the cap.
- **Whether the trajectory had flattened by the cap**, by a descriptive rule fixed here so the
  wording is not chosen after seeing the shape: the evidence will report the change over the last
  50 epochs (the value at 200 minus the value at 150, as a fraction of the value at 200) and will
  **label the headline a floor unless that change is under 1% of the headline.** This governs the
  CAVEAT only. The reported number is the value at the cap either way; nothing is selected.
- **The maximum predicted log-rate over the run**, so the loss stabilizer's inertness is a
  measurement on the published run and not only a property of a unit test.
- Per-session co-bps against both nulls, and the count of sessions that lose to their own test
  mean. **A pooled number that is positive while most sessions are individually negative is
  reported as exactly that**, because it is a materially weaker claim than "the model beats the
  null" and must not be rounded up to it.
- The four-fold rotation with mean and spread, each fold's budget beside its number, and any
  divergence recorded rather than dropped.
- `CO_BPS_MARGIN` re-derived by the unchanged `--derive-margin` rule from whatever the new headline
  is. Fourth re-derivation, same multiplication.
- The full supersession chain, four links, none deleted: 1.9116 defective, 0.0062
  corrected-truncated, 0.0713 clipped-truncated, and this run.

**A negative result is still a result.** A converged NDT1 at 1.29M parameters on about 95 minutes
of real primate M1 spikes may still fail to beat a constant per-channel mean firing rate, and the
drift-robust `test_mean_null` is reported beside the gate null every time -- the more flattering of
the two is never promoted to headline. Nothing about the learning rate, the mask ratio, the
architecture, the seed, the batch size or the choice of null will be moved to change the answer. If
the run diverges despite the stabilization, the failure and its diagnosis are published and no
estimated number is substituted for the missing one.

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
Every hyperparameter that describes the MODEL is still Phase-4-verbatim -- learning rate, batch
size, sequence length, mask ratio, weight decay, seed, architecture -- so that nothing about the
model's capacity or optimization is a free variable in this chain. What has changed across the four
arms is named each time and is confined to the objective (09-06b's input masking, 09-06d's
linearized `exp`), the numerics (09-06c's gradient clip), and the budget (09-06d's 200 epochs).

Plan 09-10's citation sweep now has more to say than it was planned for. It should record that
`04-training-evidence.md`'s 0.3804 is superseded twice over, on synthetic data AND under a defective
objective, that any document quoting 1.9116 must point here, and that any document asserting NDT1
does not beat a mean-rate null on real M1 spikes is now contradicted by this file. Nothing outside
this plan's files was edited: PROJECT.md, ROADMAP.md, REQUIREMENTS.md and the Phase 4 and Phase 5
artifacts are 09-10's scope and are untouched.

## At a glance

| Quantity | Value | Null |
|---|---|---|
| Pooled held-out co-bps | **0.4096** bits/spike | pooled train-split mean rate (the D-22 gate) |
| Pooled held-out co-bps | **0.3814** bits/spike | pooled test mean (NLB convention) |
| Per-session held-out range | +0.1661 to +0.2455 bits/spike, **4 of 4 positive** | that session's own test mean |
| Per-session, window-weighted mean | **+0.1858** bits/spike | that session's own test mean |
| Leave-one-session-out, all 4 folds | **-0.3498** mean, -0.7805 to -0.1238, std 0.2968 | held-out session's own mean |
| Leave-one-session-out, all 4 folds | +0.2446 mean, +0.1054 to +0.3958 | the fold's train-split mean (the weaker null) |
| LOSO divergences | **none: 4 of 4 folds finite**, all ran their full 60 epochs | not applicable |
| Pooled stopping epoch | **200 of a 200 cap**, `stop_reason=epoch_cap`, **no stopping rule applied** | not applicable |
| Post-plateau spread, epochs 70 to 200 | mean 0.3562, std 0.0524, range 0.2437 to 0.4209 | pooled train-split mean rate |
| Loss change over the last 50 epochs | 0.31% | not applicable |
| Max predicted log-rate, pooled run | 69.94 at epoch 6 (threshold 20, float32 `exp` overflow 88.7) | not applicable |
| Max predicted log-rate, any fold | 149.32 at epoch 7 of the `indy_20160915_01` fold | not applicable |
| Re-derived assertion margin | 0.054 bits/spike | 13.1% of the observation (D-22) |
| Committed slow gate | still RED, and NOT re-run under this plan; see below | not applicable |
| Superseded, rule stopped at its floor | 0.0713 bits/spike | this file, previous version |
| Superseded, 12 unclipped epochs | 0.0062 bits/spike | this file, second version |
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
| Compute time | 15,043 s pooled (200 epochs) + 14,836 s rotation (4 folds x 60 epochs) = 29,879 s, 8.3 h |

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
`ndt1.train.DEFAULT_GRAD_CLIP_NORM`). That is a change to the optimization, not to the objective.

The OBJECTIVE changed once, in Plan 09-06d, and only outside the data regime. The `log_input=True`
model term is now `stable_exp(x) - target * x` rather than `exp(x) - target * x`, where
`stable_exp` is `exp` below `C = 20` and the tangent line to `exp` at `C` above it. Below `C` the
value and the gradient are bit-identical to `nn.PoissonNLLLoss`, asserted with `torch.equal` over a
2,054-point grid running from -40 to one thousandth below the threshold, so the change can only
affect a step that would otherwise have produced `inf` or `nan`. It affected two: see "The loss
stabilizer was not inert" above.

There is no velocity or kinematics head in this artifact; the readout is Plan 09-07.

### Config: Phase-4 verbatim except for three named changes (D-14)

| Parameter | Value | Phase-4 verbatim? |
|---|---|---|
| epochs | **200 run, 200 cap, no stopping rule** | **no, deliberately** |
| grad_clip_norm | **1.0** | **no, deliberately (Plan 09-06c)** |
| log_rate_linearize_above | **20.0** | **no, deliberately (Plan 09-06d)** |
| loso epoch budget | **60 per fold**, a declared cost decision | **no, deliberately** |
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

Three changes from the run this supersedes and no others. All three were declared in the
pre-registration above before the run started, and none is presented as free. The loss stabilizer
is the one with a proof attached rather than only a rationale: it is bit-identical below its
threshold, so it is inert everywhere except on a step that would otherwise be non-finite.

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

### The co-bps trajectory (RD-03), which is the primary artifact of this run

Held-out pooled co-bps against both nulls, measured at epoch 1, every 10th epoch, and at the cap,
on the same seeded mask and the same 1,782 held-out windows as the headline. **The reported value
is the last row.** No epoch was selected from this curve and the committed checkpoint is the model
at epoch 200, not the model at whichever epoch scored best.

| Epoch | Training loss | co-bps vs `train_null` | co-bps vs `test_mean_null` | Elapsed s |
|---|---|---|---|---|
| 1 | 16.565122 | -0.1076 | -0.1357 | 68 |
| 10 | 0.558629 | +0.0163 | -0.0119 | 713 |
| 20 | 0.554323 | +0.1160 | +0.0879 | 1407 |
| 30 | 0.552680 | +0.1973 | +0.1692 | 2407 |
| 40 | 0.551576 | +0.2368 | +0.2086 | 3264 |
| 50 | 0.550894 | +0.2636 | +0.2355 | 4149 |
| 60 | 0.549939 | +0.3023 | +0.2742 | 4914 |
| 70 | 0.549568 | +0.3564 | +0.3283 | 5629 |
| 80 | 0.548904 | +0.3462 | +0.3181 | 6345 |
| 90 | 0.548709 | +0.2437 | +0.2155 | 7051 |
| 100 | 0.547575 | +0.3377 | +0.3095 | 7743 |
| 110 | 0.547268 | +0.4085 | +0.3804 | 8451 |
| 120 | 0.547805 | +0.3543 | +0.3262 | 9276 |
| 130 | 0.548618 | +0.3256 | +0.2975 | 10057 |
| 140 | 0.547331 | +0.4090 | +0.3808 | 10764 |
| 150 | 0.547811 | +0.3109 | +0.2828 | 11475 |
| 160 | 0.547155 | +0.4209 | +0.3928 | 12184 |
| 170 | 0.547011 | +0.2985 | +0.2703 | 12896 |
| 180 | 0.546466 | +0.4170 | +0.3888 | 13606 |
| 190 | 0.546787 | +0.3485 | +0.3204 | 14316 |
| 200 | 0.546140 | +0.4096 | +0.3814 | 15043 |

Committed as the `co_bps.trajectory` array in `09-decoder-metrics.json` and appended to a
gitignored JSONL sidecar as each row was measured, so an interrupted run would still have left its
points on disk.

**How to read the shape.** Three regimes, and the boundaries are visible without any rule:

1. **Epochs 1 to about 20: below the null.** co-bps starts at -0.1076 and crosses zero between
   epoch 10 and epoch 20. Every earlier arm of this work reported a number from inside this regime.
2. **Epochs 20 to about 70: a monotone climb.** +0.0879 to +0.3283 against the drift-robust null,
   with no reversal. This is where the entire result is earned.
3. **Epochs 70 to 200: a noisy plateau.** 14 samples spanning 0.2155 to 0.3928 with a standard
   deviation of 0.0524 and no visible trend, while the training loss falls a further 0.62%.

**What the earlier stopping rule would have done to this curve.** 09-06c's rule fired at epoch 12,
where co-bps is approximately +0.02 against the gate null. A rule that instead stopped on the
stability of the held-out metric would have fired somewhere in regime 3 and returned anything from
0.2437 to 0.4209 depending on which epoch it happened to land on. **That 0.18-wide spread is the
argument for publishing the curve rather than a stopping rule's output**, and it is why this run
has neither a rule nor a selected epoch.

### Pooled held-out co-bps (RD-03)

| Null | This run, 200 epochs | 09-06c, 12 epochs | 09-06b, 12 unclipped | Visible input |
|---|---|---|---|---|
| `train_null`, the pooled train-split per-channel mean (the D-22 gate) | **0.4096** | 0.0713 | 0.0062 | 1.9116 |
| `test_mean_null`, the pooled test-set per-channel mean (NLB convention) | **0.3814** | 0.0432 | -0.0219 | 1.8834 |

Scored on 1,782 held-out windows (57,071 bins, 19.0 minutes of recording) drawn from the four
sessions' chronological tails, on one seeded mask at `mask_ratio = 0.25`. Apple M5 Pro, CPU only,
`seed = 0`. Full precision: 0.40956884089908474 and 0.3814331158199826, with the precision caveat
above -- the fourth figure is noise, and so is the third.

**How to read it.** co-bps is the improvement over a constant per-channel rate predictor, in bits
per spike, so 0 means "exactly as good as predicting each channel's mean rate everywhere". The gap
between the two nulls, 0.0281, is smaller than it was in every previous arm, which is itself
informative: the pooled train mean and the pooled test mean have become nearly equally hard to beat
because the model is now well clear of both.

**The pooled null is still the weakest one measured here**, being a per-channel mean across four
recordings spanning 83 days. This time it does not change the verdict: the per-session table below
scores each session against its own test mean, which is the strongest constant per-channel
predictor available, and every session is still positive. That was not true of any earlier arm.

### Per-session held-out co-bps (RD-04a)

| session_id | test windows | `train_null` | `session_train_null` | `test_mean_null` | 09-06c `test_mean_null` |
|---|---|---|---|---|---|
| indy_20160624_03 | 156 | 0.4292 | 0.2282 | **+0.2127** | -0.2146 |
| indy_20160627_01 | 1050 | 0.2513 | 0.2177 | **+0.1661** | -0.1565 |
| indy_20160630_01 | 457 | 0.7805 | 0.2173 | **+0.2062** | -0.2076 |
| indy_20160915_01 | 119 | 0.6842 | 0.2532 | **+0.2455** | +0.2156 |
| unweighted mean | | 0.5363 | 0.2291 | **+0.2077** | -0.0908 |
| **window-weighted mean** | | 0.4315 | 0.2209 | **+0.1858** | -0.1499 |
| **pooled** | **1782** | **0.4096** | not applicable | **0.3814** | 0.0432 |

Five things this table says.

1. **Every session is positive under both session-specific nulls, and three of them changed sign.**
   The window-weighted mean against each session's own test mean moved from -0.1499 to +0.1858.
   This is the single largest change in this artifact's history and it came from epochs, not from
   any change to the model, the data, the null or the metric.
2. **The per-session values are tightly clustered and the `train_null` values are not.** Against
   each session's own mean the four sessions span 0.1661 to 0.2455, a range of 0.08; against the
   pooled train mean they span 0.2513 to 0.7805, a range of 0.53. The spread in the second column
   is a property of how far each session's rate level sits from the pooled average, not of how well
   the model did on it. This is why `session_train_null` and `test_mean_null` are the columns to
   read.
3. **The largest session is now the weakest, but it is still positive.** `indy_20160627_01` is 59%
   of the corpus and scores +0.1661, the lowest of the four. In 09-06c it was -0.1565.
4. **The null-to-null gaps are unchanged to four decimal places across every arm of this work.**
   `train_null` minus `session_train_null` is 0.2010, 0.0336, 0.5632, 0.4310 here and was 0.2010,
   0.0336, 0.5632, 0.4310 in 09-06c and 09-06b. A difference between two co-bps values scored
   against different nulls on the same mask cancels the model term exactly, so those gaps are a
   property of the DATA. Their invariance across three completely different checkpoints is a free
   internal check that each re-measurement changed the model and nothing else.
5. **The pooled value is larger than every per-session value against the session-specific nulls.**
   That is the pooled null being easier, as it has been throughout; the difference is that this
   time the qualifier does not reverse the sign of anything.

### Training loss curve (masked-position Poisson NLL, mean per epoch)

The full 200-epoch curve is committed as the `losses` array. The features worth naming:

```
epoch  loss           note
  1    16.5651        a large first-epoch transient, identical to 09-06c's
  2     0.5693        recovered
  3     0.5660
  4     0.5629
  5     0.5615        epochs 1-5 reproduce 09-06c's losses exactly
  6  8470.0421        a log-rate excursion to 69.94, LINEARIZED; 09-06c recorded 4.6e11 here
  7     0.5623        recovered on the next epoch
 ...
 70     0.5496        the monotone climb in co-bps ends around here
 ...
150     0.5478
200     0.5461        the minimum of the whole curve, and the last epoch
```

The loss minimum is at epoch 200, so the training loss was still (barely) descending at the cap:
0.31% over the last 50 epochs and 0.62% from epoch 70. That is the sense in which the run had not
converged. It is a much weaker statement than the 24% co-bps change over the same span, which is
oscillation rather than trend.

**The `stop_reason` is `epoch_cap` and `convergence.converged` is `false`, by design.** With no
stopping rule there is no plateau to detect and nothing to declare converged; those two fields
record that the run ended where the pre-registration said it would.

### Re-derived assertion margin (D-22)

`CO_BPS_MARGIN` is now **0.054**, replacing **0.0094**, and before that **0.00082**, and before that
**0.25**, and before that the Phase-4 **0.05**.

The value was derived by code from the measurement, not typed by a human who had seen the number:
`train_real.py --derive-margin` reads the observed pooled `train_null` out of the committed metrics
JSON and multiplies it by the fraction Phase 4 used (`0.05 / 0.3804 = 13.1441%`), then rounds to two
significant figures. `0.4095688409 * 0.131441 = 0.053834`, so 0.054. The generated rationale is
committed at `co_bps.margin_rationale` and mirrored into the constant's comment in
`Decoder/tests/test_heldout_cobps.py`.

**The derivation rule has now survived four re-derivations without being touched.** That is the
point of it. Re-deriving under a rule chosen after seeing a new number is exactly the tuning D-22
exists to prevent, so the same multiplication that produced 0.25 from 1.9116, 0.00082 from 0.0062
and 0.0094 from 0.0713 produced 0.054 from 0.4096. All four predecessors are named in the tests so
a regression says why each is superseded.

**What a 0.054 gate is worth, said plainly.** It asserts that the model beats the constant
per-channel mean-rate null by more than 0.054 bits/spike against the POOLED train-split null, and
nothing more. That is finally a threshold with some room under it: the observation is 7.6x the
margin, and the lowest sample anywhere on the post-plateau trajectory (0.2437) still clears it by
4.5x, so unlike its two immediate predecessors this gate would not flake on the metric's own
+/-0.09 sampling noise.

**What it still does not assert.** It says nothing about the per-session picture, and nothing at
all about cross-session transfer, where this same checkpoint's rotation is negative on every fold
against the held-out session's own mean. A green gate here means "the pooled model beats the
weakest of the three nulls reported", and a reader who stops at the gate has read the most
flattering line in this file. Whether a threshold gate on co-bps is the right shape of assertion is
a question for `decoder-policy.sh` in Plan 09-09; a concrete recommendation is in
`deferred-items-09-06c.md` item 2, updated in `deferred-items-09-06d.md` item 1.

Eleven quick tests (`Decoder/tests/test_cobps_margin.py`) hold this in place: the constant is none
of the four superseded values, the JSON carries both the margin and its rationale, the two agree,
all three superseded records are still present and labeled, every superseded record says what
replaced it, and the live pooled value is not equal to any superseded one. The training pass
deliberately writes `co_bps.margin = null` on every run, so a re-run without a re-derivation fails
those tests loudly rather than leaving a stale assertion guarding a number that no longer exists.

### The forward-pass stabilizer, verified against the failure it was written for

09-06c diagnosed the divergence to the step and deferred the fix. This plan implemented it and then
checked it against the real failure rather than declaring victory from a unit test.

**The committed replay.** `Decoder/scripts/diagnose_divergence.py` reproduces the slow gate's exact
training path one step at a time. Re-run under 09-06d with the same `--clip 1.0`:

```
clip=1.0  sessions=4  steps/epoch=446
epoch 1: mean loss 0.598218  max pre-clip grad norm 4.67403  max |lograte| 10.49
epoch 2: mean loss 0.587946  max pre-clip grad norm 7.99201  max |lograte| 13.32
epoch 3: mean loss 0.582616  max pre-clip grad norm 7.99201  max |lograte| 13.33
  !! step 1365 (epoch 4): loss=7.67831e+06 max|lograte|=97.43 pre_clip_grad_norm=1.49222e+09
     grad_nonfinite=False param_nonfinite=False
epoch 4: mean loss 18128.3   max pre-clip grad norm 1.49222e+09  max |lograte| 97.43
epoch 5: mean loss 0.580501
epoch 6: mean loss 0.578968
epoch 7: mean loss 0.576679
epoch 8: mean loss 0.575874
```

Read that against the two arms it supersedes, all three on the identical path:

| Run | Epochs 1-3 | Epoch 4 | Epochs 5-8 |
|---|---|---|---|
| 09-06b, no clipping | 0.6034 0.5941 0.5848 | 0.5850 | fine until epoch 8, then 21301.74 and 1.49e22, never recovers |
| 09-06c, clip 1.0 | 0.5982 0.5879 0.5826 | **nan** | nan, nan, nan, nan |
| **09-06d, clip 1.0 + linearized `exp`** | **0.5982 0.5879 0.5826** | **18128.3** | **0.5805 0.5790 0.5767 0.5759** |

Epochs 1 to 3 are identical between 09-06c and 09-06d to six decimal places, which is the no-op
claim measured on real data rather than argued from a test. At step 1365 the same excursion happens
(97.43 against 09-06c's 97.33), and where 09-06c produced `nan` and lost the run, 09-06d produces a
finite 7.68e6, keeps every gradient and parameter finite, and descends for four more epochs.

**And it mattered on the published run, twice.** The pooled run's epoch 6 hit a log-rate of 69.94
and the `indy_20160915_01` LOSO fold's epoch 7 hit **149.32**, which is 1.68x the float32 `exp`
overflow bound. `exp(149.32)` is `inf` in float32, so under the pre-09-06d objective that fold is
`nan` from epoch 7 -- and that is exactly what happened to the same fold in 09-06c, which went
non-finite at epoch 8 and burned an hour producing `nan` to its cap. This time it produced 26374.18,
recovered to 0.5661 the next epoch, and finished with a usable number. **This is the first complete
four-fold rotation in this phase.**

### The committed slow gate: still RED, and NOT re-run under this plan

`Decoder/tests/test_heldout_cobps.py::test_heldout_cabps_beats_mean_rate_null` is red on main and
this plan did not execute it. That is a deliberate limit on what is claimed here, so read the
following as two separate statements:

- **Measured.** The replay above runs that test's exact training path -- the same naive
  concatenation, the same single chronological split, `lr = 2e-3`, `seed = 0`, `batch_size = 16` --
  and it now survives to epoch 8 with a monotonically descending loss where 09-06c had `nan` from
  epoch 4. The failure mode "it cannot finish training" is therefore very likely gone.
- **Not measured.** Whether the gate now reaches its assertion and whether it then passes against
  the re-derived 0.054 margin. The test was not run under this plan, so this file makes no claim
  about its verdict.

**The second problem is untouched and is the one that matters.** `_load_binned()` still
concatenates the four sessions into one matrix and splits it once chronologically, which cuts
32-bin windows across session boundaries weeks apart -- the thing the committed headline path
explicitly forbids as a fabricated neural sequence (D-12, `ndt1.sessions.pooled_splits`) -- and
which makes the test half essentially one held-out session rather than four chronological tails. A
gate that passes on a fabricated split is not evidence of anything.

The margin was NOT lowered to whatever would pass; it was re-derived upward, from 0.0094 to 0.054,
by the unchanged rule. Plan 09-09 owns the gate's disposition; `deferred-items-09-06d.md` item 1
carries the recommendation forward with the one clause that no longer applies struck out.

### Input-visibility diagnostic

`train_real.py --diagnostic` loads the committed checkpoint from disk and re-scores it twice on the
same seeded mask: once with the scored positions hidden, as training and scoring both do, and once
with them visible, as the defective objective did on every forward pass. `hidden` is the published
path; `visible` is the probe.

| Eval set | hidden, `train_null` | visible, `train_null` | hidden, `test_mean_null` | visible, `test_mean_null` |
|---|---|---|---|---|
| indy_20160624_03 | 0.4292 | 0.4236 | 0.2127 | 0.2071 |
| indy_20160627_01 | 0.2513 | 0.2692 | 0.1661 | 0.1840 |
| indy_20160630_01 | 0.7805 | 0.7727 | 0.2062 | 0.1985 |
| indy_20160915_01 | 0.6842 | 0.6797 | 0.2455 | 0.2410 |
| pooled | **0.4096** | 0.4168 | **0.3814** | 0.3886 |

Three things.

- **The `hidden` columns reproduce the committed values to full double precision**
  (0.40956884089908474 and 0.3814331158199826), on an independently constructed mask and a
  checkpoint reloaded from disk through `torch.load(weights_only=True)`. That is the
  evaluation-path determinism check (T-09-06-01), and the diagnostic's own recorded
  `checkpoint_sha256` matches the published one.
- **Leaking the scored counts back in now buys 0.0072 bits/spike pooled** (0.4096 to 0.4168),
  against 0.062 for the 12-epoch checkpoint and about **7.4** for the checkpoint trained under the
  defective objective. The gain from being handed the answers has fallen by an order of magnitude
  as the model got better at predicting them from context, which is the direction that says the
  remaining number is context and not copying. Two of the four sessions score LOWER with the input
  visible.
- **The `visible` column is not a better number.** This checkpoint never saw uncorrupted inputs at
  scored positions during training, so feeding them is out of distribution. It is a probe, not an
  alternative result, and it must not be quoted as one.

### Reproducibility (T-09-06-01)

| Check | Result |
|---|---|
| Training path, epochs 1-5 | The pooled run's first five per-epoch losses reproduce 09-06c's to six decimal places (16.5651, 0.5693, 0.5660, 0.5629, 0.5615) from a separate process a day later, including the 16.56512170355149 first-epoch transient. From epoch 6 the runs diverge because the loss stabilizer fires, which is expected and is why the divergence point is named. |
| Divergence replay | `diagnose_divergence.py` reproduces 09-06c's epochs 1-3 to six decimals and its excursion step (1365) exactly, on a different day and a different process. |
| Evaluation path | `--diagnostic` reloads the committed checkpoint from disk, builds a fresh `seed = 0` mask, and reproduces every per-session and pooled figure to full double precision. |
| In-run probe vs final score | The trajectory's epoch-200 row equals the post-training pooled score to full double precision, so the in-training probe and the reported headline are the same computation. |
| Null-to-null gaps | 0.2010, 0.0336, 0.5632, 0.4310, identical to four decimal places across THREE checkpoints trained under different numerics and budgets. These cancel the model term algebraically, so their invariance is a property of the data and a check on the measurement code. |
| Checkpoint SHA-256 | `f95b257bf2479b49102a2d8afee3c46d9008c51ba754d42a60a26762b7d3af8e` |

**Weaker than 09-06b's claim, and stated as such.** That plan executed the full pooled run twice and
compared checkpoint SHA-256 byte for byte. A 200-epoch run costs 4.2 h, so this one was executed
once and no final hash was compared. What is established is that the first five epochs and the
divergence replay reproduce bit for bit from separate processes. The LOSO rotation was executed once
and has no replication at all.

Scope of the claim: this machine, these pinned wheel versions, CPU, this thread count.
Cross-platform determinism was not tested.

## Multi-session generalization (RD-04)

### The four-fold rotation (D-13)

Each fold retrains from scratch on three sessions' train halves with the identical config, then
evaluates on the held-out session's FULL binned matrix. The full matrix, not just its test tail,
because a held-out session had zero exposure, so every one of its bins is legitimately held out.
Each session is held out exactly once.

**The rotation ran at 60 epochs per fold against the pooled run's 200, and that is a COST decision
rather than a result decision.** It was pre-registered before the run. The four folds are 21,396
training windows against the pooled 7,132, so a full-cap rotation would have cost about 11.5 h of
CPU on top of the 4.2 h headline run. 60 is not a number chosen for this run: it is the epoch cap
Plan 09-06c had already committed. Every fold got the same budget and every fold ran to it. **The
consequence is that these four models are less trained than the pooled model, so every number below
is a floor for a 60-epoch budget and is not comparable to the pooled figure as though both had been
trained equally.**

| Fold (held out) | trained on | train windows | eval windows | budget | epochs | diverged | `train_null` | `test_mean_null` | final loss |
|---|---|---|---|---|---|---|---|---|---|
| indy_20160624_03 | 0627, 0630, 0915 | 6508 | 781 | 60 | 60 | no | 0.1054 | **-0.1238** | 0.5481 |
| indy_20160627_01 | 0624, 0630, 0915 | 2929 | 5254 | 60 | 60 | no | 0.1636 | **-0.3060** | 0.4807 |
| indy_20160630_01 | 0624, 0627, 0915 | 5303 | 2286 | 60 | 60 | no | 0.3958 | **-0.7805** | 0.5804 |
| indy_20160915_01 | 0624, 0627, 0630 | 6656 | 595 | 60 | 60 | no | 0.3135 | **-0.1890** | 0.5547 |

**All four folds produced a value. This is the first complete rotation in this phase**: 09-06b lost
one fold and 09-06c lost a different one, both to the forward-pass overflow the loss stabilizer now
bounds. Nothing was dropped and nothing had to be summarized over a subset.

| Null | mean | std | min | max | folds | finite | diverged |
|---|---|---|---|---|---|---|---|
| `train_null` | +0.2446 | 0.1336 | 0.1054 | 0.3958 | 4 | 4 | 0 |
| `test_mean_null` | **-0.3498** | 0.2968 | -0.7805 | -0.1238 | 4 | 4 | 0 |

**The two nulls disagree in SIGN here, and that disagreement is the finding.** A LOSO fold's
`train_null` is the mean of three sessions the evaluated session is not among, so it cannot track
the held-out session's own rate level; it is the weakest constant predictor anywhere in this
artifact, applied to the hardest task in it. **Quoting +0.2446 as "the model generalizes across
sessions" would be quoting the wrong null on purpose.** Scored against the held-out session's own
mean, which is what the question actually asks, all four folds are negative and the mean is -0.3498.
The 0.59 bits/spike gap between the two columns IS the cross-session heterogeneity.

Under the drift-robust null, the whole comparison in one table:

| Evaluation | mean `test_mean_null` co-bps | 09-06c | 09-06b |
|---|---|---|---|
| in-pool, per-session held-out tails, window-weighted | **+0.1858** | -0.1499 | -0.2192 |
| leave-one-session-out, all four folds | **-0.3498** | -0.4427 (3 folds) | -0.4852 (3 folds) |

**Within a session, positive on all four. Across sessions, negative on all four.** The within-session
column moved by +0.336 between 09-06c and this run and changed sign; the cross-session column moved
by +0.093 and did not. **Sixteen times the epoch budget did not buy cross-session transfer, and that
is a much more useful piece of information than either number alone.** D-15 named this outcome in
advance as a legitimate result: a LOSO number near zero or negative means channel identity did not
transfer across sessions. It is what the rotation produced, for the third consecutive time, and now
on a complete rotation with no fold missing.

**The caveat that keeps this honest.** The folds ran 60 epochs and the pooled model ran 200. The
pooled run's own trajectory shows co-bps still climbing steeply at epoch 60 (+0.3023 against
+0.4096 at the cap), so a full-budget rotation would very likely improve these four numbers. It
would have to improve them by more than 0.35 bits/spike to change the sign, which is roughly the
entire within-session result; that is a large gap, but it has not been measured and is not claimed.
`deferred-items-09-06d.md` item 2 records what closing it costs.

### The fold that used to diverge, and what stopped it

09-06b lost the fold holding out `indy_20160627_01`. 09-06c fixed that one with gradient clipping
and lost a different one, `indy_20160915_01`, non-finite at epoch 8, which then burned an hour
running out its cap producing `nan`. 09-06d loses neither.

The `indy_20160915_01` fold is the direct test, because it is the same fold on the same data with
the same seed:

```
epoch 6:      0.5682
epoch 7:  26374.1750     max predicted log-rate 149.32
epoch 8:      0.5661
...
epoch 60:     0.5547     train_null +0.3135, test_mean_null -0.1890
```

**149.32 is 1.68x the float32 `exp` overflow bound of 88.7**, so `exp` of it is `inf` and the
pre-09-06d objective returns `nan` at that step -- which is exactly what it did in 09-06c. The
linearization turns it into a finite 26,374.18, the gradient stays finite and correctly signed, and
the model is back to 0.5661 on the very next epoch. A `torch.clamp` could not have done this: above
its bound the clamped `exp` contributes nothing to the derivative, leaving the gradient at
`-target`, which drives an escaped rate further up.

The stability ledger, all four rotation cases plus the pooled run and the slow-gate replay:

| Case | 09-06b (no clip) | 09-06c (clip) | 09-06d (clip + linearized `exp`) |
|---|---|---|---|
| Fold holding out `indy_20160624_03` | clean | clean | clean |
| Fold holding out `indy_20160627_01` | **diverged, epoch 7** | clean | clean |
| Fold holding out `indy_20160630_01` | clean | clean | clean |
| Fold holding out `indy_20160915_01` | clean | **non-finite, epoch 8** | **clean, excursion bounded at epoch 7** |
| Pooled run | clean | clean (4.6e11 transient at epoch 6) | clean (8.5e3 transient at epoch 6) |
| Committed slow gate's path (replay) | blows up at epoch 8, never recovers | **nan from epoch 4** | **finite transient at epoch 4, descends through epoch 8** |

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
  (Observed at 200 epochs: the pooled value, +0.3814, is ABOVE the per-session window-weighted mean
  of +0.1858, because co-bps pools by held-out spike count and because the pooled null is weaker.)
- A LOSO number near zero or negative is a legitimate result meaning channel identity did not
  transfer. (Observed at 200 pooled epochs and 60 per fold: **all four folds are negative**, mean
  -0.3498 under the drift-robust null. This is the branch the prior named, and it is what happened,
  now for the third consecutive rotation and the first complete one.)

Neither outcome would have changed what was reported. **The 16x increase in epoch budget that
flipped every per-session number from negative to positive did not flip a single LOSO fold**, which
is the sharpest available evidence that the cross-session result is a property of the data and the
architecture rather than of undertraining. It is exactly the branch this prior named, written down
before any of these numbers existed.

## What this number is NOT (D-23)

### It is not a converged number, and it is not precise to four figures

`stop_reason` is `epoch_cap` and `convergence.converged` is `false`, by design: with no stopping
rule there is nothing to declare converged. The training loss reaches its minimum at the final
epoch, so it was still descending, if only by 0.31% over the last 50 epochs.

More importantly, **the metric itself oscillates by about +/-0.09 once the run has plateaued**, and
the reported value is one sample from that band, sitting 12th of 14. See the precision section at
the top of this file. Anyone quoting "0.4096" to four significant figures is quoting three figures
of noise.

### It is not a statement that NDT1 transfers across sessions

It is the opposite of that statement. Every leave-one-session-out fold is negative against the
held-out session's own mean firing rate. On a session this model has never seen, it is worse than
that session's constant per-channel rate. The positive `train_null` rotation mean of +0.2446 is
against a null that cannot see the held-out session at all and must not be quoted as transfer.

### It is not comparable to NLB'21, in either direction

See the protocol table below. Session, unit definition, bin width, segmentation, and what is held
out all differ. **0.3814 sits inside the 0.147 to 0.192 range those baselines report, and that
proximity is a coincidence of scale, not a result.** It is neither a claim of parity nor a claim of
superiority, and it must not be presented as either.

### It does not establish that NDT1 cannot do better

The architecture, learning rate, mask ratio, batch size and seed were all held at their Phase-4
values throughout this correction chain, and D-25 forbade moving them to improve the number.
Nothing here is a tuned configuration. The one variable that was explored, the epoch budget, turned
out to be worth the entire result: 12 epochs gave +0.0432 and 200 gave +0.3814 against the same
null on the same data. That is a warning about how much of this artifact's history was
budget-limited rather than a claim that 200 is the right number.

### It does not establish that masked modeling is the wrong pretraining task

Three of the four earlier arms of this work reported per-session numbers below zero, and this run
shows that verdict was a budget artifact. Any conclusion drawn from those arms about masked
modeling on this corpus should be re-examined against this trajectory rather than carried forward.

### The superseded numbers, and how they may be used

- **1.9116** is not a decoder result. It was produced by an objective in which the encoder received
  the true count at every position it was scored on. It may be quoted only as an example of what
  that defect produces.
- **0.0062** may be quoted only as what a 12-epoch unclipped run under the corrected objective gave,
  on a curve that had not flattened.
- **0.0713** may be quoted only as what a 12-epoch clipped run gave when a pre-registered stopping
  rule fired at its own floor. The trajectory in this file shows the curve at epoch 12; that is
  where 0.0713 sits.
- **0.3804** is a synthetic-data number from Phase 4 and is not a real-data result at all.
- **0.4096 and 0.3814** may be quoted as the pooled, 200-epoch, within-pool held-out values, with
  the +/-0.09 sampling caveat and with the cross-session result attached. Quoting the pooled figure
  without the LOSO result is quoting the most flattering line in this file.

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
rather than a result, and was: it is what motivated the audit that found the defect.

**The current 0.3814 lands inside that 0.147 to 0.192 range, and the resemblance is a trap.** It is
tempting to read "0.38 against AutoLFADS's 0.192" as a result. It is not one, in either direction.
The protocols differ on session (`indy_2016*` here against `indy_20170202_02` there), on unit
definition (96 channels of summed threshold crossings against 130 sorted single units), on bin
width (20 ms against 5 ms), on segmentation, and on what is held out (a random 25% of (bin,
channel) positions against entire neurons). Any one of those differences can move a co-bps by more
than the whole gap being compared. The baselines are here to answer "what magnitude of co-bps do
people report on primate M1 reach data", and the answer, roughly 0.15 to 0.2, is the ORDER OF
MAGNITUDE in which 0.3814 should be read -- not a leaderboard position. Note also that the LOSO
numbers in this file, which are the closest thing here to a generalization test, are negative.

**Correction, stated plainly (C-03).** NLB'21's `mc_rtt` task uses `indy_20170202_02`, recorded
2017-02-02, per DANDI dandiset 000129 asset metadata. That session is not in Zenodo record 3854034
at all. This repository previously asserted that `indy_20160630_01` was the session behind that
benchmark; that claim was false and is retracted here. None of the four sessions used in this
artifact appears in NLB'21.

## Supersedes

Four numbers, for four different reasons, none of them deleted.

**0.0713, published in the previous version of this file.** Real spikes, correct objective,
gradients clipped, but a run that a pre-registered loss-plateau stopping rule ended at that rule's
own 12-epoch floor. A probe registered before it ran then measured that epochs 12 to 60 move the
training loss 1.3% while pooled co-bps rises 4.2x; the trajectory in this file extends that finding
to 200 epochs. The same run also lost one LOSO fold to a forward-pass overflow the clip could not
reach. Retained as `superseded_rule_stopped_at_floor`. Everything derived from it is superseded with
it: the per-session values, the three-fold LOSO mean -0.4427, and the assertion margin 0.0094.

**0.0062, published in the second version of this file.** Real spikes, correct objective, but a
fixed 12-epoch budget inherited from Phase 4 (where it had been calibrated against the DEFECTIVE
objective) and no gradient clipping, on a curve still descending when the budget ran out and with
one LOSO fold and the committed slow gate diverging. Retained as `superseded_truncated_budget`.

**1.9116, published in the first version of this file.** Real spikes, but under an objective in
which the encoder received the true count at every position it was scored on. Retained as
`superseded_visible_input_objective`.

**0.3804, from `04-training-evidence.md`.** Measured on a synthetic Poisson fallback because no real
`.mat` was present under `Decoder/data/` when Phase 4 ran. Superseded twice over: synthetic data AND
the defective objective.

Per D-24 no historical artifact is retroactively rewritten: it records what that phase actually
measured, and rewriting it would destroy the record rather than correct it. **Note for Plan 09-10:**
its citation sweep now has a FOUR-link chain to label. `04-training-evidence.md` needs a superseded
banner; no document may quote 1.9116 as a decoder result; any document quoting 0.0062 or 0.0713
must point here; and any document that carried the claim "NDT1 does not beat a mean-rate null on
real M1 spikes" now carries a statement this run has falsified, which is the most important thing
09-10 has to find and fix. `.planning/PROJECT.md`, `.planning/ROADMAP.md`,
`.planning/REQUIREMENTS.md` and the Phase 4 and Phase 5 artifacts were deliberately not touched by
this correction; they are 09-10's scope.

`Decoder/tests/test_heldout_cobps.py` also changes meaning: with `Decoder/data/` materialized its
`_load_binned()` takes the real-session branch, so the slow gate it enforces is a real-data gate;
it scores through `masked_forward`; and its `CO_BPS_MARGIN` was re-derived from the 200-epoch
observation. It remains RED and was not executed under this plan; see above for what that does and
does not claim.

## Gaps and what would close them (D-25)

A low honest number completes this phase; so does a higher one that is honestly qualified. D-25 was
written for exactly this: **the deliverable is that the decoder has seen real primate M1 spikes and
that every number is measured under an objective and a numerical regime that mean what they say.**
These are the gaps, recorded as backlog and not as scheduled scope.

0. **CLOSED: the objective does not hide what it scores.** Plan 09-06b. `ndt1.train.masked_forward`
   hides the scored positions in training and in every scoring path, and
   `Decoder/tests/test_masked_input_isolation.py` fails if that is reversed.

1. **CLOSED: numerical instability.** Plan 09-06d. `ndt1.loss.stable_exp` linearizes `exp` above
   `C = 20`, so a log-rate excursion produces a finite loss with a finite correctly-signed gradient.
   Proven bit-identical below the threshold in value and gradient
   (`Decoder/tests/test_loss_stability.py`), and verified against the real failure: the committed
   replay of the slow gate's path went from `nan` at epoch 4 to a finite transient and four more
   descending epochs, and the published run's four-fold rotation completed with zero divergences
   for the first time in this phase, including a fold that reached a log-rate of 149.32.

2. **CLOSED: the budget.** 200 epochs against the 12 that every earlier arm reported from. It was
   worth the entire per-session result: the window-weighted per-session value against each session's
   own mean went from -0.1499 to +0.1858 and every session changed sign. The full trajectory is
   published so the reader can see where that happened.

3. **CLOSED BY REMOVAL: the stopping rule.** No rule was written to replace 09-06c's. Any rule that
   stops inside the curve is a selection, and one designed after seeing that longer is better is a
   tuned budget however it is worded. The run goes to a fixed cap and the whole trajectory is
   published instead. 09-06c's rule is kept behind `--plateau-stop` for reproduction.

4. **NEW: the reported value is one sample from a noisy plateau.** From epoch 70 the metric
   oscillates over a 0.18-wide band (std 0.0524) with no trend, while the loss is flat. The
   pre-registered headline is the value at the cap, which lands 12th of 14 samples in that band.
   **Closing it:** a pre-registered estimator over the plateau -- for example the mean of the last K
   sampled epochs -- committed BEFORE the run that reads it. Averaging this run's plateau now would
   be a post-hoc estimator chosen after seeing the shape, so it is reported as a spread rather than
   collapsed into a number.

5. **NEW: two changes are in this run, not one.** The pre-registration expected the loss stabilizer
   to be inert, in which case the epoch budget would have been the only variable. It was not inert:
   it fired at pooled epoch 6, so from that epoch the trajectory differs from 09-06c's and the
   movement from 0.0713 to 0.4096 is not attributable to the budget alone. **Closing it** would
   take a 200-epoch run with the stabilizer disabled, which by construction produces `nan`, so the
   attribution cannot be separated by experiment. What can be said is bounded and is said: the
   guard is bit-identical below its threshold, and epochs 1 to 5 reproduce exactly.

6. **NEW: the rotation ran at 30% of the headline's budget.** 60 epochs per fold against 200
   pooled, pre-registered as a cost decision. The pooled trajectory shows co-bps still climbing
   steeply at epoch 60, so the four cross-session numbers are floors. **Closing it:**
   `--only-loso --loso-epoch-cap 200`, about 11.5 h of CPU and no new code or decisions.
   `deferred-items-09-06d.md` item 2.

7. **The zero-masking ambiguity is unquantified.** Zeroing a masked bin is indistinguishable from a
   genuinely silent bin, which biases predictions at scored positions downward by an amount this
   work did not measure. The reported values are therefore a lower bound. **Closing it:** train a
   variant with a learned mask embedding and compare. That needs either a 97th input channel or a
   new `nn.Parameter`, both of which touch the Core ML conversion path or the guarded parameter
   count, so it is its own plan.

8. **Four sessions, one dominant.** 59% of the corpus is one recording. Now that every session is
   positive within-session, the binding constraint on the cross-session result is the number of
   sessions, not the budget: 16x the epochs moved every per-session number's sign and moved no
   LOSO fold's. More sessions is the change most likely to move the transfer result.
   `deferred-items-09-06d.md` item 3.

9. **No error bars anywhere.** Every number here is a single seeded run scored on one mask. The
   per-session values rest on 119 to 1,050 windows and their sampling variability was not
   quantified. The plateau spread in this file is a spread over EPOCHS, not over data or seeds, and
   the two are not interchangeable. `deferred-items-09-06d.md` item 4.

10. **Reproducibility is weaker than 09-06b's.** That run trained the pooled configuration twice and
    compared checkpoint SHA-256 byte for byte. A 200-epoch run costs 4.2 h, so this one was executed
    once; its corroboration is a five-epoch bit-identical match against 09-06c plus a full
    evaluation-path replay. The rotation was executed once.

11. **The committed slow gate is still RED and was not run under this plan.** Its training path very
    likely survives now, on the evidence of the replay, but whether it reaches and passes its
    assertion was not measured, and its D-12-violating split is untouched. Plan 09-09 owns it.

12. **No session conditioning.** See the D-15 statement in the generalization section. It is the
    modeling change most directly aimed at the negative LOSO result, and this run's evidence that
    the budget is not the cause makes it more clearly the right next lever.

13. **No velocity readout in this artifact.** The kinematic decode number is Plan 09-07; this file is
    reconstruction only. Plan 09-07 should note that the checkpoint it inherits is a very different
    model from the one 09-06c handed over: 200 epochs instead of 12, a pooled co-bps 5.7x higher,
    and a different SHA-256.

14. **Determinism is verified for this machine and these wheel versions**, not across platforms.
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

# 5. STAGE 1 of the published run: pooled training to the 200-epoch cap with NO stopping rule,
#    the 21-point co-bps trajectory, per-session held-out co-bps, and the checkpoint. 15,043 s of
#    CPU (4.2 h). Writes co_bps.margin as null by design. --skip-loso so the headline is on disk
#    before the rotation starts; a failure hours into stage 2 then costs stage 2 and nothing else.
uv run --project Decoder python Decoder/scripts/train_real.py --skip-loso

# 6. STAGE 2: the four-fold LOSO rotation at its own 60-epoch budget, merged into the JSON stage 1
#    wrote. 14,836 s of CPU (4.1 h). Fails loudly if stage 1 has not produced a pooled value.
uv run --project Decoder python Decoder/scripts/train_real.py --only-loso

# 7. Measure the input-visibility probe on the committed checkpoint (about 40 s).
#    Its hidden_* columns must reproduce step 5's numbers exactly; that is the eval-path check.
uv run --project Decoder python Decoder/scripts/train_real.py --diagnostic

# 8. Derive the D-22 assertion margin FROM the observed value and write it back with its rationale.
#    This runs only after the number exists; the margin never precedes the measurement.
uv run --project Decoder python Decoder/scripts/train_real.py --derive-margin

# 9. The divergence replay: reruns the committed slow gate's exact training path one step at a
#    time, printing the pre-clip gradient norm and max |log-rate| per step. This is what shows the
#    linearized loss surviving the excursion that produced nan in 09-06c. About 25 minutes.
uv run --project Decoder python Decoder/scripts/diagnose_divergence.py --clip 1.0 --epochs 8

# 10. The superseded 09-06c arm, for anyone reproducing the comparison rather than the result:
#     the loss-plateau stopping rule, off by default, into a scratch directory.
uv run --project Decoder python Decoder/scripts/train_real.py --plateau-stop --epoch-cap 60 \
  --skip-loso --checkpoint-dir Decoder/checkpoints/plateau_repro \
  --out-json Decoder/checkpoints/plateau_repro/metrics.json

# 11. The quick gate (no dataset needed) and the slow real-data gate (RED; NOT run under 09-06d).
uv run --project Decoder pytest Decoder/tests -m "not slow" -q
uv run --project Decoder pytest Decoder/tests -m slow -k test_heldout_cobps -q
uv run --project Decoder ruff check Decoder
```

Steps 5 and 6 total 29,879 s (8.3 h) of CPU. The top-level `wall_clock_s` of 22,385.3 s for stage 1
is LARGER than its 15,043 s of training because it is measured with `time.time()` and the machine
slept for about two hours mid-run; the per-epoch elapsed times in the trajectory come from
`time.monotonic()`, which excludes that, and are the honest compute figures. Run detached with
`nohup` and hold sleep off with `caffeinate -dimsu -w <pid>`.

Model weights are gitignored by the Plan 04-01 artifact policy. The committed evidence is this file
plus `09-decoder-metrics.json`; the weights are reproduced from `seed = 0` by steps 5 and 6, and the
published checkpoint's SHA-256 is `f95b257bf2479b49102a2d8afee3c46d9008c51ba754d42a60a26762b7d3af8e`.
