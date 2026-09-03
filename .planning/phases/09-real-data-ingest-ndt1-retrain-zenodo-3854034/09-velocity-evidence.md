# Phase 9 RD-02 evidence: the velocity readout, fit and scored on real finger_pos kinematics

**Date:** 2026-09-02 (Plan 09-07). Read the pre-registration in
`Decoder/scripts/fit_velocity_real.py`, committed in `ba47798` before the run, before the numbers.
**Result:** pooled held-out **R2 = 0.4238** on real `finger_pos` cursor velocity against a constant
**TRAIN-split** mean-velocity null, over 56,943 held-out 20 ms bins from four O'Doherty/Makin Indy
M1 sessions (Zenodo record 3854034). All four sessions are positive against their own train means:
**+0.5046, +0.5069, +0.1446, +0.4797**. Measured on the development Mac, **CPU only, no
hardware-gated claim**.

**Transfer is a different story, and it is neither of the two clean answers.** A leave-one-session-out
rotation of the readout, added after the numbers above and reported below, degrades **every** fold,
leaves **two of four** above a constant-velocity null (+0.2363 and +0.0718), and collapses on one
(-6.9907). The readout partially transfers.

This replaces `velocity_r2.json`'s **0.99985**, which was never a decode result.

## At a glance

| Quantity | Value | Null |
|---|---|---|
| Pooled held-out R2 | **0.4238** | pooled TRAIN-split mean velocity per axis |
| Pooled held-out R2, `vx` | **0.3430** | pooled TRAIN-split mean `vx` |
| Pooled held-out R2, `vy` | **0.5338** | pooled TRAIN-split mean `vy` |
| Per-session held-out R2 | **+0.1446 to +0.5069, 4 of 4 positive** | that session's own TRAIN-split mean |
| Held-out bins scored | 56,943 (20 ms each, 1,138.9 s of recording) | not applicable |
| Rows the readout was fit on | 228,160 | not applicable |
| Locked lag | **1 bin, 20 ms**, the argmax of the TRAIN-only sweep | not applicable |
| Two-sided alignment check | maximum still at +20 ms over -160 to +160 ms, **interior** | not applicable |
| Locked ridge lambda | **0.1**, by the pre-registered cross-validation tie-breaker | not applicable |
| Graph-versus-arithmetic parity | 4.8e-05 cm/s max abs | not applicable |
| In-sample train R2 at the locked settings | 0.4646 | the fit rows' own mean |
| Readout rotation, per fold | **+0.2363, +0.0718, -0.9257, -6.9907**, 2 of 4 positive | the held-out session's own TRAIN-split mean |
| Readout rotation, mean and spread | mean -1.9021, std 3.4311, median -0.4270, 0 folds failed | the held-out session's own TRAIN-split mean |
| Readout rotation, cost of holding a session out | mean -2.3110, range -0.2706 to -7.4953, **4 of 4 negative** | the same session with itself in the pool |
| Superseded, synthetic self-consistency check | **0.99985** | `05-velocity-head-evidence.md` |

Every value in that table was produced on this machine's CPU from the four manifest-pinned real
sessions. None is estimated, extrapolated, or carried over from another document. There is no error
bar anywhere in this file; see the honesty section for why the bin count overstates the sample size.

## Environment

| Field | Value |
|-------|-------|
| Machine | Apple M5 Pro, 18 cores, 24 GB, `arm64` |
| OS | macOS 26.5 |
| Compute | CPU only, 6 torch threads. No Neural Engine, no GPU, no compute-unit targeting |
| Interpreter | CPython 3.12.13 (uv-managed) |
| torch | 2.12.1 (CPU) |
| numpy | 2.4.6 |
| h5py | 3.16.0 |
| coremltools | 9.0 (installed, unused in this plan) |
| Determinism | `seed = 0`. The fit is a closed-form `np.linalg.solve`, so it carries no sampling |
| Encoder | `Decoder/checkpoints/ndt1_real_pooled.pt`, sha256 `f95b257bf2479b49102a2d8afee3c46d9008c51ba754d42a60a26762b7d3af8e`, loaded frozen and unchanged |
| Output | `Decoder/checkpoints/ndt1_real_with_velocity.pt`, sha256 `9d542cb51d4af4811f324fbc6bda0b503da7b15aafc98b5e1340e1a7f49cce65` (gitignored) |
| Compute time | 1,255.9 s total. Measured parts: 1,252.0 s of encoder forward passes (110.4 + 733.1 + 324.5 + 84.0 s, one per session), 1.9 s loading the four `.mat` files, 0.7 s hashing their 1.77 GB. The 17 ridge solves, the parity check and the checkpoint write account for the remaining 1.3 s |

The M5 Pro is a corroborating development machine, not the project's canonical iPad Pro M4 capture
device. That distinction does not matter here because nothing in this file is a hardware-gated
performance claim: R2 is a property of the weights and the data, not of the silicon.

## What this replaces

`05-velocity-head-evidence.md` publishes a velocity R2 of **0.99985**, sourced from
`Decoder/checkpoints/velocity_r2.json`. That number is a self-consistency check, and it is worth
being precise about what it checked, because the shape of it is the reason this plan exists.

`Decoder/tests/test_convert_velocity_output.py:55` builds its labels like this:

```python
w_true = rng.standard_normal((CHANNELS, VELOCITY_DIM)) * 0.05
vel = last_bin @ w_true + 0.01 * rng.standard_normal((n_windows, VELOCITY_DIM))
```

The labels are a seeded linear function of `last_bin` plus one percent noise, and the ridge is then
asked to regress `last_bin` onto them. Of course it recovers them. The test is a correct and useful
test: it confirms `load_ridge` reproduces `X @ W.T + b` and that the readout is not degenerate. It
is not a measurement of how well anything decodes movement, and it never claimed to be inside its
own file. What went wrong is that the number escaped into an evidence artifact where a reader would
read it as a decode result.

Nothing in `05-velocity-head-evidence.md` is retracted or edited: it measured what it measured. The
number is superseded, and `velocity.supersedes` in `09-decoder-metrics.json` says so by name so the
replacement is auditable rather than silent.

## Labels (D-06, D-07, C-02)

**Source.** `finger_pos`, and the planar pair is **rows 1 and 2** as h5py sees them, not rows 0 and
1. D-06's original wording, "first two axes (x, y)", would have selected the depth axis and negated
x. Correction C-02 fixed the spec; the extraction lives once, in `ndt1.data.load_session`, and is
pinned by Plan 09-02's fixture test. This plan re-states the convention in
`velocity.label_source` so a regression would be visible in the committed JSON.

The evidence for the correction is measured, not argued. On `indy_20160630_01`:

| Quantity | Value |
|---|---|
| `corr(cursor_pos[0], finger_pos[0])` | +0.2852 |
| `corr(cursor_pos[0], finger_pos[1])` | **-1.0000** |
| `corr(cursor_pos[1], finger_pos[2])` | **-1.0000** |
| `max abs(cursor_pos[0] - (-10 * finger_pos[1]))` | 2.09 mm |
| `std(finger_pos[0])`, the depth axis | 0.242 cm |
| `std(finger_pos[1])`, `std(finger_pos[2])` | 3.257 cm, 3.279 cm |

Rows are ordered `(z, -x, -y[, azimuth, elevation, roll])` in cm. Taking rows 0 and 1 raises no
exception, produces a well-formed design matrix, and would have mixed a near-static 0.24 cm depth
channel into the label, roughly halving R2 with one axis effectively unlearnable. It is a
silent-failure path with no error, which is why it is pinned by a test rather than by a comment.

The negation is undone once, at the loader, so downstream code and Phase 10's `R` fit from
`z_decoded` versus `v_true` residuals see true `(x, y)` in cm rather than inheriting a sign
implicitly. The sign is cosmetic for the ridge, which absorbs it into `W`, and is not cosmetic for
the direction the shipped cursor moves.

**Derivation (D-07).** A plain backward finite difference at the native 250 Hz behavior rate, then a
mean aggregate of the samples falling in each 20 ms bin. There is **no smoothing filter**. A
Savitzky-Golay derivative would introduce a window length and a polynomial order that would each
need justifying, and it can smooth away genuine fast dynamics; the 250 Hz clock is already five
times finer than the 20 ms bin, so the aggregation is the only averaging the labels need and it is
the one they need. `ndt1.kinematics.bin_velocity` recomputes `num_bins` with the identical
`floor((t_end - t_start) / bin_s)` arithmetic `bin_spikes` uses and reuses its high-edge clip, so
the labels and the spike matrix are row-aligned by construction; the runner asserts the two row
counts match and aborts otherwise. An empty 20 ms bin raises rather than emitting a `NaN`.

## The design matrix, and the three things it is not

One design row is one 32-bin window, indexed by that window's **last** bin, because
`VelocityHead.forward` reads the static slice `rates[..., -1:]`.

**It is built at stride 1, not one window per 32 bins.** The deployed model is called once per
20 ms bin with the trailing 32-bin window, so stride 1 is the serving geometry. It is also the
`(n_bins, num_channels)` layout `ndt1.kinematics.apply_lag` documents, which is what makes "lag k"
mean "the window ending at bin `i` paired with the velocity at bin `i + k`" rather than
"paired with the velocity 32k bins later". The cost is 285,235 encoder forward passes instead of
8,914, which is 21 minutes of CPU rather than 40 seconds. That is the whole reason this run needed
to be detached.

**Its columns are the encoder's raw output, not exponentiated rates.** The shipped module composes
`velocity_head(encoder(x))`: the 1x1 conv consumes the encoder output unchanged, and with
`log_input=True` that output is log-rates. Fitting `W` on `exp(log_rates)` would produce weights the
shipped graph never applies, and inserting an `exp` to match would add an op type D-09 forbids.
This is asserted, not asserted-about: the run computes the full forward pass of the assembled
model on real held-out windows and compares it against the `X @ W.T + b` arithmetic the reported R2
comes from. **Max abs disagreement 4.8e-05 cm/s**, which is float32 rounding in the conv weights
against a float64 solve. Had the design matrix been exponentiated, that gap would be enormous
rather than at the rounding floor.

**Its encoder input is unmasked.** Training hides the scored positions and co-bps is scored the same
way, but the deployed model is fed a real, complete 32-bin window. The readout is therefore fit and
scored under the **serving** condition, which is the 05-RESEARCH Decision-1 no-train/serve-skew
rule. One consequence must be stated plainly: **these R2 values are not comparable to the co-bps
values in the same JSON**, which are measured under the masked objective with a quarter of the
input hidden.

**Split discipline.** Per session, the chronological tail split point comes from
`ndt1.data.chronological_split` itself rather than from a restatement of its arithmetic, so the
readout is fit and scored on exactly the blocks the encoder was trained and evaluated on. Held-out
design rows begin a full window **after** the split point, so no held-out prediction reads a single
bin the encoder trained on. The lag is applied per session and only then concatenated: lagging a
concatenation would pair the last rows of one recording with the first rows of another recorded
weeks later.

The run also refuses to start unless the four session ids, all four session sha256 values, and the
encoder checkpoint's sha256 match what `09-decoder-metrics.json` records. The readout must be fit
on exactly the data the encoder was trained on, and that is checked rather than assumed.

## Lag sweep (D-08)

Fit and scored on the **TRAIN** rows only, at lambda 1.0, over the pre-registered `lag_bins` 0 to 8.
Selection never touched the held-out tail, so there is no leak, and the whole curve is published so
a reader can see how sensitive the result is to the choice instead of taking the argmax on trust.

| `lag_bins` | `lag_ms` | Train R2 | Rows |
|---|---|---|---|
| 0 | 0 | 0.462034 | 228,164 |
| 1 | 20 | **0.464637 (locked)** | 228,160 |
| 2 | 40 | 0.463099 | 228,156 |
| 3 | 60 | 0.457890 | 228,152 |
| 4 | 80 | 0.449539 | 228,148 |
| 5 | 100 | 0.438521 | 228,144 |
| 6 | 120 | 0.425335 | 228,140 |
| 7 | 140 | 0.410436 | 228,136 |
| 8 | 160 | 0.394190 | 228,132 |

Row counts differ by 32 out of 228,164 across the sweep, because a longer lag drops more unpaired
tail rows. The in-sample score is a selection criterion, never a result: it is computed on the same
rows the fit used, against those rows' own mean.

**The argmax is 20 ms, and it tripped this plan's own warning.** `nlb_tools/make_tensors.py` sets
`'lag': 140` ms for `mc_rtt`, with `mc_maze` at 100 ms and the somatosensory `area2_bump` at
-20 ms; M1 activity leads hand velocity by 120 to 180 ms in two macaques by cross-correlation
(PNAS 10.1073/pnas.2212227120). The pre-registration says an argmax outside 5 to 8 bins is a signal
that the alignment or the sign is wrong, not a discovery. **The observed argmax does not agree with
that range.** The run printed the warning, and the answer is below rather than a shrug.

### Alignment diagnostic: the other side of zero

A one-sided sweep cannot distinguish "zero really is the optimum" from "the labels are shifted late
and the argmax is pinned at the boundary", because both look identical. So the same TRAIN-only
curve was computed at the eight negative offsets, after the pre-registered sweep and **never as
part of the selection**. The locked lag is the argmax of the 0 to 8 sweep whatever this shows.

| Offset (bins) | Offset (ms) | Train R2 | Rows |
|---|---|---|---|
| -8 | -160 | 0.357104 | 228,132 |
| -7 | -140 | 0.370212 | 228,136 |
| -6 | -120 | 0.384513 | 228,140 |
| -5 | -100 | 0.399826 | 228,144 |
| -4 | -80 | 0.415601 | 228,148 |
| -3 | -60 | 0.430899 | 228,152 |
| -2 | -40 | 0.444508 | 228,156 |
| -1 | -20 | 0.455191 | 228,160 |

Over the full two-sided curve from -160 ms to +160 ms the maximum is still +20 ms, and the curve
falls away monotonically on both sides, by 0.070 over the +160 ms arm and by 0.108 over the
-160 ms arm. **The optimum is interior. The labels are not shifted**, which is exactly the failure
the D-08 warning exists to catch, and it is not present.

**Why 20 ms and not 140 ms, offered as an interpretation rather than a measurement.** The 140 ms
figure is applied to per-bin rates that a non-causal model produced with the whole trial in view, so
the rate at bin `i` there already carries information from bins after `i`, and pairing it with
behavior at `i + 7` is well posed. Here the encoder sees a trailing 32-bin window that ends at bin
`i` and nothing after it, and the readout reads that window's final position. Under that geometry
the best-predicted velocity is the one nearest the end of the available evidence, and a 140 ms lag
would be asking a 640 ms causal window to extrapolate seven bins past its own last observation.
This reading is consistent with the measured curve, and it has not been tested; the measured claim
is only that the two-sided maximum is interior at +20 ms.

It is worth noting separately that a 20 ms lag is the operationally correct answer for this
artifact. The shipped model exists to move a cursor to where the hand is now, at a 50 Hz decode
cadence. A readout locked at 140 ms would have been predicting where the hand is about to be, which
is a different product.

## Ridge lambda

Also TRAIN-only, at the locked lag. The rule was fixed before the run for a specific reason: an
in-sample train R2 is monotone non-increasing in lambda by construction, so it cannot select a
lambda, it can only document sensitivity. Taking its argmax would mechanically return the smallest
value on the grid every time.

| lambda | Train R2 | GCV | Rows |
|---|---|---|---|
| 0.01 | 0.464643 | 6.413748e+01 | 228,160 |
| 0.1 | **0.464643 (locked)** | **6.413747e+01** | 228,160 |
| 1 | 0.464637 | 6.413799e+01 | 228,160 |
| 10 | 0.464269 | 6.418050e+01 | 228,160 |
| 100 | 0.458770 | 6.483309e+01 | 228,160 |
| 1000 | 0.438253 | 6.727819e+01 | 228,160 |

The pre-registered rule was: lock `ridge_fit`'s existing default of 1.0, fixed in Phase 5 before any
real measurement existed, unless the train-R2 spread across the whole grid exceeds 1e-3, in which
case break the tie with generalized cross-validation on the train split alone (closed-form, no
extra split, no leak; 09-RESEARCH section 7, option 1).

**The tie-breaker fired, and its result is immaterial.** The whole-grid spread is 2.64e-2, above the
1e-3 tolerance, so the rule routed to cross-validation, which is minimized at 0.1. But that spread
is produced almost entirely by lambda 100 and 1000: across 0.01 to 10 the train R2 moves 3.7e-4 and
cross-validation moves in its sixth significant figure. The curve documents the insensitivity the
research predicted for a 96-column design matrix against 228,160 rows. Locking 1.0 instead of 0.1
would move the fourth decimal place of the train R2 by six units in the last digit. The value is
reported as locked because the rule says so, and the curve is published so that a reader can see the
choice did not matter.

## Held-out R2 (D-10)

Computed **once**, at the locked lag of 1 bin and the locked lambda of 0.1. Per axis:

```
R2_axis = 1 - SS_res / SS_tot
SS_res  = sum_t (v_true[t, axis] - v_pred[t, axis])^2      over the TEST bins
SS_tot  = sum_t (v_true[t, axis] - mean_TRAIN(v_true[:, axis]))^2
pooled  = 1 - (sum_axes SS_res) / (sum_axes SS_tot)
```

**The null mean comes from the TRAIN split.** `ndt1.kinematics.heldout_r2` takes it as a required
positional argument precisely so it cannot quietly default to the test set's own mean, and a
mutation test proves that substitution is caught. Scoring against the test set's own mean would
make `SS_tot` the test variance and silently convert this into the easier textbook R2, which is a
different claim; the two are not interchangeable on a dataset with measured within-session drift.

**Pooled is not the mean of the two axes.** It is `1 - sum SS_res / sum SS_tot`, which weights the
axes by their variance. Here the two differ visibly: the mean of +0.3430 and +0.5338 is 0.4384,
while the pooled figure is 0.4238. Averaging would have over-weighted the quieter axis.

| Session | `vx` | `vy` | pooled | Held-out bins | Null |
|---|---|---|---|---|---|
| `indy_20160624_03` | +0.4585 | +0.5684 | **+0.5046** | 4,968 | its own TRAIN-split mean |
| `indy_20160627_01` | +0.4246 | +0.6252 | **+0.5069** | 33,597 | its own TRAIN-split mean |
| `indy_20160630_01` | +0.0586 | +0.2589 | **+0.1446** | 14,600 | its own TRAIN-split mean |
| `indy_20160915_01` | +0.3813 | +0.5764 | **+0.4797** | 3,778 | its own TRAIN-split mean |
| **Pooled** | **+0.3430** | **+0.5338** | **+0.4238** | 56,943 | the pooled TRAIN-split mean |

Per session the null is that session's own train mean, which is the harder of the two available
nulls: the pooled train mean is an average over four recordings and sits further from any single
session's tail, which inflates R2. The pooled row uses the pooled train mean because that is the
mean of the rows the readout was actually fit on.

**Two things this table shows that a pooled number alone would hide.** First, `vy` beats `vx` on
every one of the four sessions, by between 0.11 and 0.20. Second, the spread across sessions is
3.5x: `indy_20160630_01` returns +0.1446 while `indy_20160627_01` returns +0.5069 from the same
weights. `indy_20160630_01` is also the session on which 09-RESEARCH measured a -8.1% within-session
drift in mean firing rate from the train head to the test tail. That is a suggestive coincidence and
nothing more: one drift measurement on one session does not establish a cause, and no per-session
drift figure was measured for the other three under this plan.

**All four sessions are positive.** This is the same direction as Plan 09-06d's within-session
co-bps result, and like it, every row of that table is a chronological tail of a session the readout
was fit on and the encoder was pretrained on. What happens on a session the readout has never seen
is the next section.

## Cross-session transfer: the readout rotation (R5)

Four folds. For each session: fit the ridge on the other three sessions' TRAIN rows, with the lag
and the lambda **re-selected on those three alone**, then score held-out R2 on the excluded
session's own TEST tail against **its own TRAIN-split mean**. Selecting either knob once globally
would have chosen it on data that includes the held-out session. All four folds fitted; none failed.

**Read the scope of this experiment before the numbers.** The encoder is the same pooled checkpoint
in every fold, and it was pretrained on all four sessions, including the held-out one. This rotation
therefore isolates whether the linear **readout** transfers, holding the representation fixed. It is
**not** Plan 09-06d's leave-one-session-out co-bps, where the encoder itself was retrained from
scratch without the held-out session, and it is a **strictly weaker** transfer claim. A genuinely
new session in deployment would face both problems at once: a readout that has not seen it and an
encoder that has not either. **These numbers therefore bound true cross-session performance from
above.**

| Held-out session | Locked lag | Fit rows | `vx` | `vy` | pooled | Held-out bins | With this session in the pool | Cost of holding it out |
|---|---|---|---|---|---|---|---|---|
| `indy_20160627_01` | 0 bins | 93,677 | +0.1676 | +0.3349 | **+0.2363** | 33,598 | +0.5069 | -0.2706 |
| `indy_20160915_01` | 1 bin | 212,950 | -0.1949 | +0.3343 | **+0.0718** | 3,778 | +0.4797 | -0.4078 |
| `indy_20160630_01` | 2 bins | 169,660 | -1.2237 | -0.5301 | **-0.9257** | 14,599 | +0.1446 | -1.0703 |
| `indy_20160624_03` | 1 bin | 208,193 | -10.0102 | -2.8157 | **-6.9907** | 4,968 | +0.5046 | -7.4953 |

Rotation over the four folds: **mean -1.9021, sample std 3.4311, min -6.9907, max +0.2363, median
-0.4270, 2 of 4 positive, 0 failed**. Lambda locked at 0.1 in all four folds.

**The mean is not the result here.** One fold is 7.6x further from zero than the next worst, so the
mean of -1.9021 is a statement about that fold and little else. The median of -0.4270 and the fold
list are the honest summary, and the reason both are printed is that a rotation reported as a mean
alone would hide exactly the structure that makes this interesting.

### What the rotation says, stated precisely

**1. Transfer partially holds. It neither survives nor fails cleanly.** Two of four held-out sessions
are decoded better than a constant-velocity null by a readout that never saw them (+0.2363 and
+0.0718). Two are not (-0.9257 and -6.9907). Any single-sentence verdict in either direction would
be false to the data.

**2. Holding a session out always costs, and the cost is never small.** All four deltas are negative,
from -0.2706 to -7.4953. Even the best-transferring fold loses more than half its in-pool R2
(+0.5069 down to +0.2363). Whatever the readout learns is at least partly session-specific.

**3. The null choice, which was decisive for co-bps, is immaterial here.** Scored against the fold's
three TRAINING sessions' mean velocity instead of the held-out session's own, the four numbers are
+0.2363, +0.0718, -0.9258, -6.9907: identical to four decimal places. Mean velocity in a self-paced
reach is near zero on both axes, so every constant-velocity null is nearly the same constant. Plan
09-06d's 0.59 bits/spike gap between its two co-bps nulls has no counterpart here, and this result
does not turn on that subtlety at all.

**4. Per-fold re-selection did not move the lag toward the published anchor.** The four folds locked
1, 0, 2 and 1 bins, every one of them tripping the 5-8 bin warning. Four independent selections on
four different training pools agreeing on 0 to 2 bins is further evidence that the 20 ms optimum is a
property of the trailing-causal-window geometry rather than of one particular pooling.

### Does this corroborate the co-bps rotation? Partly, and the disagreement matters

Plan 09-06d's leave-one-session-out co-bps, against the held-out session's own mean, ranked the
sessions from easiest to hardest as `indy_20160624_03` (-0.1238), `indy_20160915_01` (-0.1890),
`indy_20160627_01` (-0.3060), `indy_20160630_01` (-0.7805). The velocity readout rotation ranks them
`indy_20160627_01` (+0.2363), `indy_20160915_01` (+0.0718), `indy_20160630_01` (-0.9257),
`indy_20160624_03` (-6.9907).

**Where they agree:** `indy_20160630_01` is the hardest session for the encoder rotation and the
second hardest here, and it is also the weakest within-session velocity result of the four
(+0.1446). Three views of that session point the same way.

**Where they disagree, which is the more informative half:** `indy_20160624_03` is the **easiest**
fold for the co-bps rotation and the **worst by a wide margin** here. The two metrics do not rank
these sessions the same way, so "this session is the outlier" is not a property of the session that
transfers between them. No magnitude should be compared across the two rotations in any case: co-bps
is in bits per spike and R2 is dimensionless, and any numerical similarity between them is a
coincidence of scale.

### The collapsed fold, and what is not claimed about it

`indy_20160624_03` at -6.9907 means the residual sum of squares is about eight times the null's, and
`vx` alone is at -10.0102. That is a **scale and offset** failure, not a sign failure: the readout is
not predicting the wrong direction so much as the wrong magnitude, by a lot. There is a mechanism
available in the arithmetic, which is that a rank-2 linear map with a single fitted intercept has no
way to adapt to a session-level shift in the distribution of the encoder outputs it consumes, so an
unseen session whose feature distribution sits outside the training pool's is extrapolated rather
than interpolated.

**That mechanism is not established here.** It was not tested, and the obvious test, re-centering the
held-out session's features or its predictions, is deliberately not run: it would be tuning to
rescue a number after seeing that it is bad, which is the one thing this phase's whole
pre-registration chain exists to prevent. It is written down as an open question instead.

## Reading the number honestly (D-25)

**What the readout is.** A rank-2 linear map from 96 encoder outputs at a **single** 20 ms bin. No
recurrence, no nonlinearity, no multi-lag design matrix.

**What comparable published numbers are.** On 30 Indy sessions at 10 ms bins with 96-channel
unsorted multiunit activity, single-session finger-velocity R2 runs 0.633 to 0.717 across GRU,
Transformer, RWKV and Mamba, rising to 0.720 to 0.838 with multi-session training
(arXiv 2406.06626). Those are sequence models with far more capacity, nonlinear readouts, and bins
half the width. Classic Wiener-filter decoders reach their numbers using many lagged bins at once.
**Cite these as context, never as a head-to-head comparison**: the bin width, the readout class and
the evaluation protocol all differ, and this repository's discipline is that a number measured under
one protocol is not set against a number measured under another.

Against that context, 0.4238 from a single-bin rank-2 linear map is unremarkable rather than
impressive, and it lands slightly above the 0.1 to 0.4 band 09-RESEARCH predicted for this exact
configuration. It is reported as measured. Nothing was clamped, no setting was re-rolled to improve
it, and the pre-registration committed to publishing a negative value as the finding had one
appeared.

**The pooled 0.4238 is a within-pool number, and the rotation is what bounds it.** Every row of the
per-session table is a session the readout was fit on. On a session it has not seen, the same
readout returns +0.2363, +0.0718, -0.9257 and -6.9907, and even that understates the deployment
problem, because in deployment the encoder would not have seen the session either. **0.4238 is what
this decoder does on sessions it has been fit for; it is not what it would do on a new recording
day.**

**What is missing, and it matters more than the value.** There is **no error bar anywhere in this
file**. The 56,943 held-out bins are not 56,943 independent samples: cursor velocity is
autocorrelated over hundreds of milliseconds, so the effective sample size is smaller than the bin
count by an unmeasured factor, and the held-out block is one contiguous stretch per session rather
than a resample. Quoting the fourth decimal place of 0.4238 is quoting more precision than this
protocol establishes. The per-session spread of 0.1446 to 0.5069 is the honest indication of how
much this number moves with the data it is scored on.

**What would close the gap to the published range**, all of it backlog rather than scheduled scope:
joint fine-tuning of the encoder and the head against the kinematic objective instead of freezing an
encoder trained only for masked reconstruction; a multi-lag design matrix so the readout sees a
window of rates rather than one bin; 10 ms bins; session conditioning; and a nonlinear readout,
which would have to be re-checked against the deployment constraints this plan deliberately did not
touch. D-25 is explicit that a low honest number completes the phase, and the deliverable here is
that the shipped weights were fit on real primate kinematics with the selection published, not that
the value is good.

## Reproduce

```bash
uv sync --project Decoder --extra dev
uv run --project Decoder python Decoder/scripts/download_indy.py     # materializes Decoder/data/
uv run --project Decoder python Decoder/scripts/fit_velocity_real.py --smoke

# The published run. About 21 minutes of CPU; detach it.
nohup uv run --project Decoder python Decoder/scripts/fit_velocity_real.py \
  > Decoder/checkpoints/09-07-logs/velocity.log 2>&1 &

# The readout rotation. Seconds, off the cached design matrices.
uv run --project Decoder python Decoder/scripts/fit_velocity_real.py --reuse-rates --loso

uv run --project Decoder pytest Decoder/tests -m "not slow" -q       # 189 passed, 9 deselected
uv run --project Decoder ruff check Decoder                          # All checks passed
```

The run reads `09-decoder-metrics.json`, verifies the four session hashes and the encoder hash
against it, and merges a `velocity` section back into it without touching any other key. Re-running
is idempotent: the fit is closed-form and carries no sampling. `--reuse-rates` skips the 21-minute
forward pass when the cached design matrices still match the encoder and session hashes, and
recomputes rather than failing when they do not.

CI never runs this script (D-21). The metrics-JSON schema assertions covering the `velocity` section
land in Plan 09-09.
