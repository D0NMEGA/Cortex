# Phase 9 RD-03 / RD-04 evidence: NDT1 trained on real primate M1 spikes

**Date:** 2026-08-31. Corrected the same day; read "The correction" first.
**Result:** pooled held-out **co-bps = 0.0062 bits/spike** against the train-split per-channel
mean-firing-rate null, and **-0.0219** against the drift-robust test-mean null, measured on **real
O'Doherty/Makin Indy M1 spikes (Zenodo record 3854034)**, four sessions, CPU only.

**Stated plainly: with the positions it is scored on hidden from the encoder, this NDT1 does not
beat a constant per-channel mean firing rate.** Under the gate null it is 0.006 bits/spike above it;
under the drift-robust null it is 0.022 below. That is the finding. It is not a failed run, nothing
was tuned toward or away from it, and the sections below say exactly what it does and does not mean.

The first version of this artifact, published earlier the same day, reported **1.9116**. That number
came out of a training objective that let the encoder read the values it was scored on, so it
measured self-reconstruction rather than prediction. It is superseded by this one. It is preserved,
labeled, in `09-decoder-metrics.json` under `superseded_visible_input_objective` and quoted
throughout this file, because correcting a published number means labeling the old one, not
deleting it.

This artifact still supersedes the co-bps of **0.3804** in `04-training-evidence.md`, which was
measured on a **synthetic Poisson fallback** because no real `.mat` was present under
`Decoder/data/` when Phase 4 ran. That number is now doubly superseded: synthetic data AND the same
defective objective.

**This is not a hardware-gated claim.** It is CPU-only decoder R&D that reproduces on any Mac CPU
with the pinned wheels. There is no Neural Engine, Core ML, palettization or latency number in this
file; those are Plans 09-07 and 09-08.

## The correction (Plan 09-06b)

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

| Quantity | Superseded (visible input) | Corrected (hidden input) |
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
| Pooled held-out co-bps | **0.0062** bits/spike | pooled train-split mean rate (the D-22 gate) |
| Pooled held-out co-bps | **-0.0219** bits/spike | test mean (NLB convention, drift-robust) |
| Per-session held-out range | -0.3820 to 0.2084 bits/spike | test mean |
| Leave-one-session-out, 3 of 4 folds | -0.4852 mean, -0.7289 to -0.2381 | test mean |
| Leave-one-session-out, 4th fold | diverged; loss 268623.80 at epoch 7, non-finite by epoch 12 | not applicable |
| Re-derived assertion margin | 0.00082 bits/spike | 13.1% of the observation (D-22) |
| Committed slow gate | **RED**: its training run diverges (4.68e22 by epoch 12) | not applicable |
| Superseded value, visible input | 1.9116 bits/spike | this file, earlier the same day |
| Superseded value, synthetic data | 0.3804 bits/spike | `04-training-evidence.md` |

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

There is no velocity or kinematics head in this artifact; the readout is Plan 09-07.

### Config, Phase-4 verbatim (D-14)

| Parameter | Value |
|---|---|
| epochs | 12 |
| lr | 2e-3 |
| optimizer | AdamW, weight_decay 0.01 |
| batch_size | 16 |
| seq_len | 32 bins (640 ms) |
| mask_ratio | 0.25 |
| test_frac | 0.2 |
| bin_ms | 20.0 |
| seed | 0 |
| device | cpu |
| log_input | true |
| params | 1,292,544 |

These are byte-for-byte the constants Phase 4 used to produce the synthetic 0.3804, and byte-for-byte
the constants the superseded 1.9116 was produced with. They are unchanged here NOT for comparability
with 0.3804, which is gone for the reasons given above, but so that **the objective is the only
variable** between the superseded numbers and these. Nothing was tuned.

**The budget is the one open question about this number, and it is not resolved here.** D-14 permits
RAISING the epoch budget when the curve has clearly not converged, and forbids lowering it. By the
criterion the superseded run used (epochs 10 to 12 oscillating inside 0.0018), the curve below has
**not** converged: it descends monotonically to the last epoch at about 0.0007 per epoch with no
oscillation. So D-14's raise-the-budget branch would fire.

It was deliberately not taken. A longer budget is a second variable, and this task exists to change
exactly one; it would also move the number upward, which is the direction that makes the result look
better. Reporting 0.0062 at the same 12 epochs the superseded 1.9116 used is the comparison that
isolates the objective. What a longer budget would give was not measured and is recorded as the
first gap below.

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

| Null | Pooled held-out co-bps (bits/spike) | Superseded, visible input |
|---|---|---|
| `train_null`, the pooled train-split per-channel mean (the D-22 gate) | **0.0062** | 1.9116 |
| `test_mean_null`, the test-set per-channel mean (NLB convention) | **-0.0219** | 1.8834 |

Scored on 1,782 held-out windows (57,071 bins, 19.0 minutes of recording) drawn from the four
sessions' chronological tails, on one seeded mask at `mask_ratio = 0.25`. Apple M5 Pro, CPU only,
`seed = 0`. Full precision: 0.006214627530704778 and -0.021921097548397350.

**How to read it.** co-bps is the improvement over a constant per-channel rate predictor, in bits
per spike, so 0 means "exactly as good as predicting each channel's mean rate everywhere". 0.0062
is 0.6% of one hundredth of a bit above that; -0.0219 is slightly below it. In practical terms this
model, trained for 12 epochs on 7,132 windows under the corrected objective, extracts essentially
nothing from the surrounding context that the per-channel mean rate does not already give you.

The honest framing of the whole exercise: the reason to run it was that the repository was
publishing a number that did not mean what it claimed. It now publishes one that does. A near-zero
context-only co-bps at this budget is a true statement about this model on this data, and it is
worth more to the project than a flattering invalid one.

### Per-session held-out co-bps (RD-04a)

| session_id | test windows | `train_null` | `session_train_null` | `test_mean_null` | superseded `test_mean_null` |
|---|---|---|---|---|---|
| indy_20160624_03 | 156 | -0.0173 | -0.2184 | -0.2338 | 1.8129 |
| indy_20160627_01 | 1050 | -0.1094 | -0.1431 | -0.1946 | 1.6725 |
| indy_20160630_01 | 457 | 0.1922 | -0.3710 | -0.3820 | 1.6500 |
| indy_20160915_01 | 119 | 0.6471 | 0.2161 | 0.2084 | 1.9540 |
| **pooled** | **1782** | **0.0062** | not applicable | **-0.0219** | 1.8834 |

Five things this table says, none of which is visible from the pooled number alone:

1. **Three of the four sessions are negative under the drift-robust null**, and two are negative
   under the gate null as well. Only `indy_20160915_01` is positive under all three, at 0.2084 to
   0.6471. Under the superseded objective every cell of this table was above 1.6.
2. **The one positive session is the smallest.** `indy_20160915_01` is 19,052 bins, 6.7% of the
   corpus, and 119 of 1,782 held-out windows. It is also the session with the width-3 `finger_pos`
   outlier. A per-session number resting on 119 windows carries much more sampling noise than
   `indy_20160627_01`'s 1,050, so this is not evidence that the model works on that session and not
   the others; it is one number with a wide error bar that was not quantified.
3. **The pooled value is not the mean of the per-session values.** The per-session mean under
   `test_mean_null` is -0.1505; the pooled figure is -0.0219. co-bps is a ratio of summed
   quantities, so pooling weights by held-out spike count rather than by session, and the pooled
   figure is not a per-session average.
4. **The null-to-null gaps are unchanged from the superseded run, to four decimal places.** The
   `train_null` to `session_train_null` gap is 0.2010, 0.0336, 0.5632, 0.4310 here and was 0.2011,
   0.0336, 0.5632, 0.4309 before; the `session_train_null` to `test_mean_null` gap never exceeds
   0.0516 in either. That is a property of the data, not of the model: the difference between two
   co-bps values scored against different nulls on the same mask cancels the model term exactly.
   It is a free internal check that the re-measurement changed the model and nothing else, and it
   preserves the superseded run's conclusion that the gap between the gate null and the drift-robust
   null is cross-session heterogeneity rather than the measured 8.1% within-session rate drift.
   `indy_20160627_01` still has the smallest gap (0.0336) because the pooled mean is essentially its
   own mean.
5. **The drift-robust floor is -0.0219 pooled, and it is negative.** Quoting only the gate value
   would be quoting the more flattering of two numbers that were both measured, and in this case it
   would also be quoting the only one of the two that is above zero.

### Training loss curve (masked-position Poisson NLL, mean per epoch)

```
epoch  loss     |bar (scaled 0.550-0.600)
  1    0.5939   |#######################################     (start)
  2    0.5708   |#####################
  3    0.5673   |##################
  4    0.5657   |#################
  5    0.5644   |################
  6    0.5637   |###############
  7    0.5632   |###############
  8    0.5615   |#############
  9    0.5603   |############
 10    0.5599   |############
 11    0.5592   |###########
 12    0.5584   |###########                                 (end)
```

0.5939 to 0.5584: a **6% reduction** over 12 epochs and 5,352 optimizer steps, in 844 s of CPU. The
superseded run, same data and same config with the answers visible, fell 0.4309 to 0.2439, a 43%
reduction. The corrected objective is a far harder problem, which is the expected consequence of
removing the value being predicted from the input, and the loss is roughly twice as high throughout.

**This curve has not converged.** It descends monotonically to the last epoch, with no oscillation:
the last five per-epoch deltas are -0.0012, -0.0004, -0.0007, -0.0008, and the model is still
improving when the budget runs out. The superseded run's convergence signal was epochs 10 to 12
oscillating inside 0.0018; nothing like that happens here. By that criterion D-14's raise-the-budget
branch fires and the budget should be raised.

It was not raised, for the reason given under the config table: a longer budget is a second variable
in a task whose entire purpose is to change exactly one, and it moves the number in the flattering
direction. **The honest statement is that 0.0062 is a 12-epoch number under an objective that had
not finished fitting, not an asymptote.** How much a longer budget would recover is the single
largest open question about this result and is the first entry under "Gaps" below.

### Re-derived assertion margin (D-22)

`CO_BPS_MARGIN` is now **0.00082**, replacing the superseded **0.25** and, before that, the Phase-4
**0.05**.

The value was derived by code from the measurement, not typed by a human who had seen the number:
`train_real.py --derive-margin` reads the observed pooled `train_null` out of the committed metrics
JSON and multiplies it by the fraction Phase 4 used (`0.05 / 0.3804 = 13.1441%`), then rounds to two
significant figures. `0.0062146275 * 0.131441 = 0.000817`, so 0.00082. The rationale string it
generates is committed at `co_bps.margin_rationale` in `09-decoder-metrics.json` and mirrored into
the constant's comment in `Decoder/tests/test_heldout_cobps.py`.

**The derivation rule was not changed, only the observation it reads.** That matters: re-deriving
under a rule chosen after seeing the corrected number is exactly the tuning D-22 exists to prevent.
The same multiplication that produced 0.25 from 1.9116 produced 0.00082 from 0.0062.

**What a 0.00082 gate is worth, said plainly.** It asserts that the model beats the constant
per-channel mean-rate null by more than 0.00082 bits/spike, and nothing more. That is far too small
to demonstrate "non-trivial reconstruction" in any meaningful sense, and far too small to be robust
to run-to-run variation on a different machine or a different torch build. It is not inflated to
look like a pass, and the artifact does not claim it is a meaningful bar. The rationale generator
was corrected as part of this work for the same reason: it previously asserted unconditionally that
the margin was "high enough above the 0.0 null to mean something, low enough below the observation
that run-to-run variation cannot flake the gate", which was true of 0.25 against 1.9116 and is not
true here. It now states what the derivation did and what the gate therefore asserts, and leaves the
judgment to the reader with the observation printed beside it.

Whether a threshold gate on co-bps is the right shape of assertion at all, once the honest value is
near zero, is a question for `decoder-policy.sh` in Plan 09-09. It is logged in
`deferred-items-09-06b.md`.

Both predecessors are superseded for different reasons and both are named in the tests so a
regression says why: Phase 4's 0.05 was calibrated against a purpose-built learnable synthetic
sinusoid, and 0.25 was derived from a self-reconstruction score.

Five quick tests (`Decoder/tests/test_cobps_margin.py`) hold this in place: the constant is neither
the Phase-4 value nor the superseded 0.25, the JSON carries both the margin and its rationale, the
two agree, and the superseded numbers are still present and labeled. The training pass deliberately
writes `co_bps.margin = null` on every run, so a re-run without a re-derivation fails those tests
loudly rather than leaving a stale assertion guarding a number that no longer exists.

### The committed slow gate is RED under the corrected objective

`Decoder/tests/test_heldout_cobps.py` was executed against the re-derived margin on real data, and
**it fails**. Not because the model narrowly misses a threshold, but because its training run
diverges:

```
uv run --project Decoder pytest Decoder/tests -m slow -k test_heldout_cobps -q
1 failed, 160 deselected in 970.77s (0:16:10)

AssertionError: the loop did not train: final loss 4.67701e+22 is not below the first epoch's
0.603385. Per-epoch loss [0.6033846852891648, 0.5941419602776856, 0.5848473572410275,
0.5849856212401069, 0.5824850972056923, 0.5800964635851137, 0.5782270424168207, 21301.737633484227,
26.62697594475853, 22.9264001268977, 1.4864985342398979e+22, 4.677011763621308e+22]. A co-bps
computed from these weights (observed: -1576.77256) describes the divergence, not the model.
```

Seven clean descending epochs, a blow-up at epoch 8, a partial recovery over epochs 9 and 10 that
never returns near 0.58, then 1.49e22 and 4.68e22. **The -1576.77 is a divergence artifact and is
not a co-bps this artifact claims, in either direction.**

It reproduced identically on a second execution: the same twelve losses to full precision and the
same -1576.77256. The divergence is deterministic, not a flake.

Two changes were made to the test and neither of them is the margin or the assertion. It now scores
through `masked_forward`, so the gate and the trainer share one objective; and the two "did it
train" checks, one of which was already in the test, were moved AHEAD of the co-bps assertion. Before
that move the failure read "held-out co_bps -1576.77256 did not beat the mean-rate null by the
documented margin 0.00082", which invites the reading that the model is catastrophically bad when the
truth is that the optimizer blew up. **The test still fails; only the reported first cause changed.**

This is the third instance of one instability. The `log_input=True` Poisson NLL has model term
`exp(rate) - target * rate`, so a predicted log-rate excursion overflows and AdamW at `lr = 2e-3`
with no gradient clipping has nothing to arrest it. It fired once under the superseded objective
(one LOSO fold, a silent NaN at epoch 12) and twice under the corrected one (a different LOSO fold at
epoch 7, and this gate at epoch 8). **The corrected objective is measurably less stable at this
learning rate**, which is the expected consequence of a harder prediction problem and is itself a
finding rather than a nuisance.

It is reported and not repaired. Gradient-norm clipping or a lower learning rate would very likely
fix all three, and both would move every other number in this file, so applying one inside the task
that corrects the objective would confound two changes and leave no way to attribute a difference to
either. See `deferred-items-09-06b.md` item 1.

Note that this test trains on a **naive concatenation** of the four sessions with a single
chronological split, not the D-12 per-session split the headline numbers use, so it is a gate and
never the headline. What it establishes here is negative: the committed assertion does not pass on
real spikes under the corrected objective, and the reason is numerical, not a near miss.

### Input-visibility diagnostic

`train_real.py --diagnostic` loads the committed checkpoint from disk and re-scores it twice on the
same seeded mask: once with the scored positions hidden, as training and scoring both now do, and
once with them visible, as the superseded objective did on every forward pass. The two labels have
swapped roles since the first version of this artifact: **`hidden` is now the published path** and
`visible` is the probe.

| Eval set | hidden, `train_null` | visible, `train_null` | hidden, `test_mean_null` | visible, `test_mean_null` |
|---|---|---|---|---|
| indy_20160624_03 | -0.0173 | 0.0079 | -0.2338 | -0.2086 |
| indy_20160627_01 | -0.1094 | -0.0648 | -0.1946 | -0.1500 |
| indy_20160630_01 | 0.1922 | 0.3481 | -0.3820 | -0.2261 |
| indy_20160915_01 | 0.6471 | 0.6089 | 0.2084 | 0.1702 |
| pooled | **0.0062** | 0.0701 | **-0.0219** | 0.0420 |

Three things.

- **The `hidden` columns reproduce the committed values to full double precision**, on an
  independently constructed mask and a checkpoint reloaded from disk through
  `torch.load(weights_only=True)`. That is the evaluation-path determinism check (T-09-06-01).
- **Leaking the scored counts back in buys 0.064 bits/spike pooled** (0.0062 to 0.0701). Run the
  same probe against the superseded checkpoint and the same leak was worth about **7.4** bits/spike
  (-5.5266 to 1.9116). That contrast is the clearest single measurement of what the defect was
  doing: a model trained with the answers visible learns to copy them and collapses when they are
  removed; a model trained without them gains almost nothing when they are handed back, because it
  never learned to use them. **The superseded 1.9116 was almost entirely self-reconstruction.**
- **The `visible` column here is not a better number.** This checkpoint never saw uncorrupted inputs
  at scored positions during training, so feeding them is out of distribution. It is a probe, not a
  corrected, alternative or improved result, and it must not be quoted as one. Note that it is not
  uniformly higher either: `indy_20160915_01` scores lower with the input visible, which is what an
  out-of-distribution input looks like rather than a leak the model can exploit.

### Reproducibility (T-09-06-01)

The pooled training run was executed **twice**, an hour apart, from the same seed, the second time
into a scratch checkpoint directory so it could not touch the published artifact. Compared
programmatically rather than by eye:

| Quantity | Run 1 versus run 2 |
|---|---|
| pooled checkpoint SHA-256 | **identical**: `0496a72cc0878bc01e77968b28a9dfeee68f0ac4fd09c8d0537a95b801b4b209` |
| all 12 per-epoch losses | identical (0.5939 ... 0.5584) |
| pooled `train_null` and `test_mean_null` | identical (0.0062, -0.0219) |
| all per-session co-bps under all three nulls | identical |

An identical checkpoint hash is the strongest form of this claim available: it means the optimizer
visited the same states in the same order, not merely that two summary statistics agreed.

The second run used `--skip-loso`, so the **rotation was executed once**, not twice. Its four folds
have no independent replication in this artifact and are stated on that basis. The rotation of the
superseded run did reproduce bit for bit across two executions of the same code path, which is
evidence that the LOSO machinery is deterministic but not evidence about these particular fold
values.

The evaluation path has its own independent check: `--diagnostic` reloads the committed checkpoint
from disk through `torch.load(weights_only=True)`, builds a fresh mask from `seed = 0`, and
reproduces every per-session and pooled figure to full double precision (see the diagnostic table
above).

Scope of the claim: this machine, these pinned wheel versions, CPU, this thread count. Cross-platform
determinism was not tested.

The second run also surfaced and closed a bug in the runbook: a relative `--checkpoint-dir` made
`Path.relative_to` raise at the JSON write, after the training had finished, so the run's only record
was its log. `_repo_relative` now resolves the path first. The numbers above were recovered from that
log and from the checkpoint on disk, both of which survived; nothing was re-run to produce them. Cross-platform determinism was not tested.

## Multi-session generalization (RD-04)

### The four-fold rotation (D-13)

Each fold retrains from scratch on three sessions' train halves with the identical config, then
evaluates on the held-out session's FULL binned matrix. The full matrix, not just its test tail,
because a held-out session had zero exposure, so every one of its bins is legitimately held out.
Each session is held out exactly once.

| Fold (held out) | trained on | train windows | eval windows | `train_null` | `test_mean_null` | final loss |
|---|---|---|---|---|---|---|
| indy_20160624_03 | 0627, 0630, 0915 | 6508 | 781 | -0.0089 | -0.2381 | 0.5577 |
| indy_20160627_01 | 0624, 0630, 0915 | 2929 | 5254 | diverged | diverged | non-finite (epoch 12) |
| indy_20160630_01 | 0624, 0627, 0915 | 5303 | 2286 | 0.4473 | -0.7289 | 0.5875 |
| indy_20160915_01 | 0624, 0627, 0630 | 6656 | 595 | 0.0139 | -0.4886 | 0.5654 |

Summary over the three folds that produced a value:

| Null | mean | std | min | max | folds | finite | diverged |
|---|---|---|---|---|---|---|---|
| `train_null` | 0.1508 | 0.2571 | -0.0089 | 0.4473 | 4 | 3 | 1 |
| `test_mean_null` | **-0.4852** | 0.2454 | -0.7289 | -0.2381 | 4 | 3 | 1 |

**The meaningful cross-comparison is under `test_mean_null`, not `train_null`.** A LOSO fold's
`train_null` is the mean of three sessions the evaluated session is not among, so it is an even worse
constant predictor than the pooled null is, and it inflates the fold's co-bps for a reason that has
nothing to do with generalization. That reasoning is unchanged from the superseded run and it still
bites: comparing 0.1508 (LOSO) with 0.1781 (the in-pool per-session mean) under that null would make
the drop look like 0.03, when under the honest null it is 0.33.

Under the drift-robust null the comparison is honest:

| Evaluation | mean `test_mean_null` co-bps |
|---|---|
| in-pool, per-session held-out tails | -0.1505 |
| leave-one-session-out, three finite folds | **-0.4852** |

**Every finite fold is negative under the drift-robust null.** On a session it has never seen, this
model is worse than that session's own constant per-channel mean rate, by 0.24 to 0.73 bits/spike.
The superseded run reported +1.5110 here and read it as "the model transfers at a cost of about
15%"; that reading does not survive the correction and is withdrawn.

D-15 named this outcome in advance as a legitimate result: a LOSO number near zero or negative means
channel identity did not transfer across sessions. It is what the rotation produced. Nothing was
reshaped, re-seeded or re-run to reach it, and the caveat that qualifies it is the same one that
qualifies the pooled number: the folds trained for 12 epochs under a curve that had not converged
(final losses 0.5577, 0.5875, 0.5654, all still descending).

### The fold that diverged

**A fold still diverges, but a different one, with a different signature.** Under the superseded
objective the fold holding out `indy_20160624_03` trained cleanly for eleven epochs and then lost the
twelfth to a NaN. Under the corrected objective that fold completes:

```
indy_20160624_03 held out: 0.5947 0.5701 0.5673 0.5660 0.5642 0.5652 0.5626 0.5623 0.5611 0.5596 0.5590 0.5577
```

and the fold holding out `indy_20160627_01` blows up instead, mid-training rather than at the end:

```
indy_20160627_01 held out: 0.5305 0.5100 0.5016 0.4989 0.4970 0.4953 268623.8026 99.9337 24.3704 26.3921 30.6708 nan
```

Six clean descending epochs, then epoch 7 at 268,623.80, a partial recovery over epochs 8 to 11
(99.93, 24.37, 26.39, 30.67) that never gets back near 0.5, and a non-finite epoch 12. This is a
different failure from the superseded run's silent final-epoch NaN: the blow-up is visible for five
epochs before it becomes non-finite, and the optimizer visibly tries and fails to recover.

The mechanism is the same and is unchanged by this correction: the `log_input=True` Poisson NLL has
model term `exp(rate) - target * rate`, so once a predicted log-rate spikes, `exp` overflows and the
gradients go non-finite. AdamW at `lr = 2e-3` with no gradient clipping has nothing to arrest it.

Two honest observations about which fold diverges. The divergence is **not** the same event as
before, so it is not a property of one session's data: it moved when the objective changed, which
points at the optimization rather than at `indy_20160624_03` or `indy_20160627_01` specifically.
And the fold that now diverges is the one trained on the fewest windows (2,929) and evaluated on the
most (5,254), because it holds out the session that is 59% of the corpus.

It is reported rather than repaired, for the same reasons as before plus one more. Gradient-norm
clipping and a lower learning rate are both changes that would move every number in this file, so
applying one inside the task that corrects the objective would confound the two changes and leave no
way to attribute a difference to either. And an 11-epoch budget would have produced a finite number
for the superseded run's diverged fold, but choosing a budget BECAUSE it avoids a NaN is tuning
toward a result, which D-22 and D-25 forbid. The fold contributes nothing to the summary and its full
loss curve is committed in `09-decoder-metrics.json` so the epoch is auditable. See
`deferred-items-09-06b.md` item 1.

The honest reading is that this config sits close to the numerical stability edge on real spikes
under both objectives, that one quarter of the rotation was lost to it again, and that a rotation
summary resting on three of four folds is weaker evidence than one resting on four.

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

### It is not an asymptote, and it is not a statement about NDT1

Two things this near-zero number does NOT establish.

**It does not establish that NDT1 cannot do better on this data.** The loss curve had not converged
at 12 epochs (see the Result section), the budget was deliberately not raised, and the zero-masking
choice biases predictions at scored positions downward by an unmeasured amount. A longer budget, a
learned mask token, a larger or smaller mask ratio, session conditioning, or more data could all move
it. None of those was tried, on purpose: this task changed one variable.

**It does not establish that the masked-modeling objective is the wrong pretraining task.** co-bps
here is a reconstruction score, and a model can be a poor bin-level reconstructor and still learn
representations that decode velocity well. The kinematic decode is Plan 09-07 and is the number that
speaks to the project's actual goal. Nothing in this file should be read as predicting it.

What the number does establish is narrow and worth having: **under a correct masked objective, at
this budget and this configuration, this model extracts essentially nothing about a hidden 20 ms bin
from its surrounding context that the per-channel mean rate does not already provide.**

### The superseded number, and how it may be used

The 1.9116 this artifact previously published is retained in `09-decoder-metrics.json` under
`superseded_visible_input_objective`, with the defect that produced it, a warning, and a pointer to
what replaced it. `Decoder/tests/test_cobps_margin.py` fails if that record is removed.

It may be cited as a historical record of what this repository measured and when. It **must not** be
cited as a decoder result, a co-bps, or a comparison against any benchmark. The measured reason is
in the diagnostic above: about 7.4 of its 1.9116-to--5.5266 span came from the model reading the
values it was scored on.

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

The direction of the comparison has reversed with the correction, and the table above is why neither
direction was ever a like-for-like comparison. The superseded 1.9116 sat an order of magnitude ABOVE
those baselines, which should have been read as a warning rather than as a result, and was: it is
what motivated the audit that found the defect. The corrected 0.0062 sits well BELOW them. Neither
fact says this decoder is better or worse than AutoLFADS, because the protocols differ on session,
units, bin width, segmentation, and what is held out. The baselines are here to answer "what
magnitude of co-bps do people report on primate M1 reach data", and the answer, roughly 0.15 to 0.2,
is the context in which 0.0062 should be read.

**Correction, stated plainly (C-03).** NLB'21's `mc_rtt` task uses `indy_20170202_02`, recorded
2017-02-02, per DANDI dandiset 000129 asset metadata. That session is not in Zenodo record 3854034
at all. This repository previously asserted that `indy_20160630_01` was the session behind that
benchmark; that claim was false and is retracted here. None of the four sessions used in this
artifact appears in NLB'21.

## Supersedes

Two numbers, for two different reasons.

**1.9116, published in the first version of this file earlier the same day.** Measured on real
spikes, but under an objective in which the encoder received the true count at every position it was
scored on. Superseded by the numbers above. Retained, labeled, in `09-decoder-metrics.json` under
`superseded_visible_input_objective`, and preserved in this file's tables so a reader who encounters
it elsewhere can find out what it was. Everything derived from it is superseded with it: the
per-session range 1.6500 to 1.9540, the LOSO mean 1.5110, the "generalization costs about 15%"
reading, and the assertion margin 0.25.

**0.3804, from `04-training-evidence.md`.** Measured on a synthetic Poisson fallback because no real
`.mat` was present under `Decoder/data/` when Phase 4 ran. It is now superseded twice over: synthetic
data AND the same defective objective, since Phase 4's training loop is the one this correction
fixed.

Per D-24 neither artifact is retroactively rewritten: a historical evidence artifact records what
that phase actually measured, and rewriting it would destroy the record rather than correct it.
`04-training-evidence.md` gains a superseded banner pointing here in Plan 09-10. **Note for 09-10:**
its citation sweep was scoped to labeling 0.3804 as synthetic. It now also needs to label 0.3804 as
having been produced under the defective objective, and to ensure no document quotes 1.9116 without
pointing here. `.planning/PROJECT.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md` and the
Phase 4 and Phase 5 artifacts were deliberately not touched by this correction; they are 09-10's
scope.

`Decoder/tests/test_heldout_cobps.py` also changes meaning: with `Decoder/data/` materialized, its
`_load_binned()` takes the real-session branch instead of the synthetic Poisson fallback, so the slow
gate it enforces is a real-data gate; and it now scores through `masked_forward`, so the gate and the
trainer share one objective. Its `CO_BPS_MARGIN` was re-derived from the corrected observation (see
the Result section).

## Gaps and what would close them (D-25)

A low honest number completes this phase; so does a high one that is honestly qualified. D-25 was
written for exactly the outcome above, and it applies: **the deliverable is that the decoder has
seen real primate M1 spikes and that every number is measured under an objective that means what it
says.** These are the gaps in what was measured, recorded as backlog and not as scheduled scope.

0. **CLOSED: the objective does not hide what it scores.** This was gap 1 in the first version of
   this file and it is the reason for the correction above. `ndt1.train.masked_forward` now hides
   the scored positions in training and in every scoring path, and
   `Decoder/tests/test_masked_input_isolation.py` fails if that is reversed.

1. **The budget: 12 epochs on a curve that had not converged.** The largest open question about
   0.0062. The loss was still descending monotonically at about 0.0007 per epoch when the budget ran
   out, and D-14's raise-the-budget branch would fire. It was not raised because a longer budget is
   a second variable in a task designed to change one, and because it moves the number in the
   flattering direction. **Closing it:** re-run at a longer budget with everything else fixed, and
   publish the 12-epoch and the longer-budget numbers side by side so the effect of the budget is
   visible rather than substituted. That is a decision, not a fix, because it changes the D-14
   config.

2. **The zero-masking ambiguity is unquantified.** Zeroing a masked bin is indistinguishable from a
   genuinely silent bin, which biases predictions at scored positions downward by an amount this
   work did not measure. 0.0062 is therefore a lower bound. **Closing it:** train a variant with a
   learned mask embedding and compare. That needs either a 97th input channel or a new
   `nn.Parameter`, both of which touch the Core ML conversion path or the guarded parameter count,
   so it is its own plan.

3. **Numerical instability, now firing in two places.** A LOSO fold diverges (a different one than
   before, with a visible five-epoch blow-up rather than a silent NaN) and **the committed slow gate
   diverges outright and is RED**. Gradient-norm clipping or a lower learning rate would very likely
   fix both; both change every number in this file, so applying one inside this correction would
   have confounded two changes. This is the most actionable item on the list and the one most likely
   to also move gap 1, since a run that cannot be trained past 12 epochs without blowing up cannot
   answer the budget question either. See `deferred-items-09-06b.md` item 1.

4. **Four sessions, one dominant.** 59% of the corpus is one recording, and the one session with a
   positive co-bps is the smallest (119 held-out windows). More sessions of comparable length would
   make both the pooled number and the rotation more even, and would let the per-session values
   carry error bars.

5. **No error bars anywhere.** Every number here is a single seeded run. The per-session values
   especially, resting on 119 to 1,050 windows, have sampling variability that was not quantified.
   **Closing it:** multiple seeds, or a bootstrap over held-out windows.

6. **No session conditioning.** See the D-15 statement in the generalization section. It is the
   modeling change most directly aimed at the negative LOSO result.

7. **No velocity readout in this artifact.** The kinematic decode number is Plan 09-07; this file is
   reconstruction only, and a poor reconstruction co-bps does not by itself predict a poor velocity
   decode.

8. **Determinism is verified for this machine and these wheel versions**, not across platforms. The
   config and the pinned versions are committed so a divergence elsewhere is diagnosable.

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

# 5. The real run: pooled training, per-session held-out co-bps, the four-fold LOSO rotation.
#    Roughly 60 minutes of CPU. Writes 09-decoder-metrics.json with co_bps.margin left null.
uv run --project Decoder python Decoder/scripts/train_real.py

# 6. Measure the input-visibility probe on the committed checkpoint (about one minute).
#    Its hidden_* columns must reproduce step 5's numbers exactly; that is the eval-path check.
uv run --project Decoder python Decoder/scripts/train_real.py --diagnostic

# 7. Derive the D-22 assertion margin FROM the observed value and write it back with its rationale.
#    This runs only after the number exists; the margin never precedes the measurement.
uv run --project Decoder python Decoder/scripts/train_real.py --derive-margin

# 8. The training-path determinism check: the same pooled run into a scratch checkpoint dir, whose
#    checkpoint SHA-256 must equal step 5's. --skip-loso keeps it to about 15 minutes.
uv run --project Decoder python Decoder/scripts/train_real.py --skip-loso \
  --checkpoint-dir Decoder/checkpoints/repro \
  --out-json Decoder/checkpoints/repro/09-decoder-metrics-repro.json

# 9. The quick gate (no dataset needed) and the slow real-data gate (about 20 minutes).
uv run --project Decoder pytest Decoder/tests -m "not slow" -q
uv run --project Decoder pytest Decoder/tests -m slow -k test_heldout_cobps -q
uv run --project Decoder ruff check Decoder
```

Model weights are gitignored by the Plan 04-01 artifact policy. The committed evidence is this file
plus `09-decoder-metrics.json`; the weights are reproduced from `seed = 0` by step 5.
