# Deferred items, Plan 09-07 (velocity readout on real kinematics)

Four items. None blocks Plan 09-08's conversion: the checkpoint it converts exists, carries the
Plan 09-06 encoder bit-identically, and its readout is fit on real `finger_pos` velocity.

## 1. No cross-session velocity readout, and it is now cheap to run

**What is missing.** Plan 09-06d's headline is a split: the encoder beats a mean-rate null on
held-out data from sessions it trained on (4 of 4 positive) and loses to it on sessions it has
never seen (4 of 4 LOSO folds negative). This plan measured only the within-pool half of the same
question for velocity. Every number in `09-velocity-evidence.md` is a chronological tail of a
session the encoder trained on. Whether the READOUT transfers to an unseen session is unmeasured,
and the evidence says so rather than implying otherwise.

**Why it was not done here.** It is not in Plan 09-07's success criteria, and adding an unplanned
measurement after seeing a favourable pooled number is the shape of the thing this phase's
pre-registration chain exists to prevent.

**What it would cost now: seconds, not hours.** `fit_velocity_real.py --reuse-rates` reads the
cached per-session design matrices from `Decoder/checkpoints/09-07-rates/`, so a four-fold rotation
is four ridge solves plus four scorings on matrices that already exist. The 21-minute forward pass
does not have to run again. The one design question the follow-up must answer first is which null
to score against, and Plan 09-06d already settled the analogous one: the held-out session's OWN
mean, never the training pool's, because the pooled mean is the weakest constant predictor applied
to the hardest task and the gap between the two nulls IS the cross-session heterogeneity.

**Recommendation.** Fold it into Plan 09-11 or into Phase 10's RD-07 work, where a cross-session
`R` fit would want the same numbers.

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
