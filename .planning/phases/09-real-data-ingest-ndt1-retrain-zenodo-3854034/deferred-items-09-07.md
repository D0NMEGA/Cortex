# Deferred items, Plan 09-07 (velocity readout on real kinematics)

Four items, of which item 1 is CLOSED inside this plan. None blocks Plan 09-08's conversion: the
checkpoint it converts exists, carries the Plan 09-06 encoder bit-identically, and its readout is
fit on real `finger_pos` velocity.

## 1. CLOSED. The cross-session velocity readout was measured

**Closed 2026-09-02**, in the same plan, by `fit_velocity_real.py --loso`. Four folds, four fitted,
no failures, two seconds off the cached design matrices. Results, scored on each held-out session's
own TEST tail against its own TRAIN-split mean: **+0.2363, +0.0718, -0.9257, -6.9907**, mean
-1.9021, median -0.4270, 2 of 4 positive, and all four deltas against the same session's in-pool
number negative (-0.2706 to -7.4953). Full reporting in `09-velocity-evidence.md`, section
"Cross-session transfer: the readout rotation (R5)"; raw values in `velocity.loso` and
`velocity.loso_summary`.

**What remains open from it, folded in here rather than opened as a fifth item.**

*The collapsed fold has no established cause.* `indy_20160624_03` at -6.9907 is a scale and offset
failure: the residual sum of squares is about eight times the null's and `vx` alone is -10.0102. The
mechanism available in the arithmetic is that a rank-2 linear map with one fitted intercept cannot
adapt to a session-level shift in the encoder-output distribution it consumes. That was not tested,
and the obvious test (re-centering the held-out session's features or predictions) was deliberately
not run, because it would be tuning to rescue a number after seeing it is bad. If a future plan wants
it, the honest form is to pre-register the re-centering as a stated method change with its own
held-out evaluation, not as a repair.

*The rotation is readout-only, so the real cross-session number is worse.* The encoder is the same
pooled checkpoint in every fold and was pretrained on all four sessions. A true cross-session test
would retrain the encoder without the held-out session, as Plan 09-06d's co-bps rotation does, and
then fit the readout on the remaining three. That is a multi-hour run, not a two-second one, and it
is the experiment that would say what this decoder does on a genuinely new recording day. The
numbers already published bound it from above.

## 2. No error bar anywhere in this artifact

**What is missing.** The pooled held-out R2 is reported as 0.4238 with no interval. The 56,943
held-out bins are not 56,943 independent samples: cursor velocity is autocorrelated over hundreds
of milliseconds and each session contributes one contiguous block, so the effective sample size is
smaller than the bin count by a factor nobody has measured. This is the same gap
`deferred-items-09-06d.md` item 4 records for co-bps, and it is now the second artifact in this
phase to carry it.

**What would close it.** A moving-block bootstrap over the held-out tail with a block length set
from the measured velocity autocorrelation time, resampled to give a percentile interval on the
pooled and per-session values. Closed-form ridge makes each resample cheap, and the design matrices
are cached, so the cost is dominated by the number of resamples rather than by any model work.

**Why it matters for what ships.** The evidence currently says "the fourth decimal place is not
established" in prose. An interval would let it say so with a number, and would tell a reader
whether the 3.5x per-session spread (0.1446 to 0.5069) is heterogeneity or sampling noise.

## 3. Only one session has a measured within-session drift figure

**What is missing.** `indy_20160630_01` returns the weakest held-out R2 of the four (+0.1446 against
+0.4797 to +0.5069) and is also the one session for which 09-RESEARCH measured a within-session
firing-rate drift, -8.1% from the train head to the test tail. That is one point, and the evidence
labels it a coincidence rather than an explanation. No drift figure was measured for
`indy_20160624_03`, `indy_20160627_01` or `indy_20160915_01` under any plan in this phase.

**What would close it.** Compute the per-channel mean-rate ratio between each session's train head
and test tail for all four sessions and set it against the per-session R2. Four numbers, no model
work, minutes. If the ordering holds it becomes an explanation worth stating; if it does not, the
coincidence should be dropped from the evidence rather than left implying a cause.

## 4. The lag interpretation is consistent with the curve and is not tested

**What is missing.** The locked lag is 1 bin (20 ms), well outside the 5-8 bin range anchored by
`nlb_tools`' 140 ms setting for `mc_rtt`. The alignment question that raises IS answered by
measurement: the two-sided curve from -160 ms to +160 ms has a single interior maximum at +20 ms, so
the labels are not shifted. What is NOT tested is the offered explanation, that the 140 ms figure
belongs to per-bin rates produced non-causally with a whole trial in view, whereas here the encoder
sees a trailing causal window and the readout reads its final position.

**What would close it.** Re-derive the design matrix from windows CENTERED on the target bin rather
than ending at it, and re-run the same sweep. If the argmax moves toward 140 ms, the explanation is
supported; if it stays at 20 ms, it is not. This is a diagnostic only and must not touch the shipped
path: a centered window is not causal and cannot be served, so the shipped readout would still be
fit on trailing windows whatever the diagnostic shows.

**Priority: low.** The locked lag is the operationally correct one for this artifact either way. A
cursor decoder is asked where the hand is now, not where it will be in seven bins.
