# Phase 10 RD-07 evidence: the four-arm ReFIT ablation on real spikes

**Date:** 2026-09-05 (Plan 10-07). Every number below is transcribed from the committed
`10-refit-real.json`. None is recomputed in prose, and nothing here is rounded in a direction.

**The result, stated first.** On one open-loop replay of `indy_20160630_01` through the shipped fp16
NDT1 model, the two arms whose rate is attributable to the decode, `raw` and `kalman_only`, scored
**0 of 1,025 trials**. Their Webgrid BPS is **0.000000 at N=900 and 0.000000 at N=64**. The `refit`
arm scored 70 and the `refit_reversed_target` control scored 2, and neither of those is a decoding
result: `IntentRotation` replaces the decoded direction with the direction to the known target and
keeps only the decoded speed, so both target-seeing arms are target-determined by construction.

The ROADMAP set this standard for this phase in writing before the run: "If ReFIT's uplift does not
survive contact with real spikes, that is the finding and it gets published as such." This is that
publication. 10-PREREGISTRATION section 15 named a floored hit count as the expected outcome, on
measured evidence, before the number existed.

## 1. What was measured

Four arms over ONE decoded velocity sequence. The decode ran once, before the arm loop, into a
shared array, so the arms differ only in the filter stage. Decoding per arm would have injected a
difference the ablation would then have attributed to the filter.

| Arm | Filter stage | `rotation_target_source` |
|---|---|---|
| `raw` | the decoded velocity straight to the integrator, no filter | `none` |
| `kalman_only` | `KalmanFilter.step` with the rotation disabled | `none` |
| `refit` | `KalmanFilter.step` rotating toward the session's TRUE target | `true_track` |
| `refit_reversed_target` | identical to `refit` except the rotation's target track is time-reversed | `reversed_track` |

The reversed-target arm reverses only the ROTATION's target. Every arm, including this one, is
SCORED against the TRUE target. Reversing both would have made the control vacuous, because the
cursor would then be rotated toward the same target it is scored against
(10-PREREGISTRATION section 7).

What ran: the D-06 export of `indy_20160630_01` (73,160 bins at 20 ms, 96 channels, 1,025 trials),
decoded one tick per bin on the trailing 32-bin window ending at that bin, through
`Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage`, into the Phase-10 re-fit Kalman gain and
the Phase-7 `IntentRotation`. 73,129 decoded ticks. **0 decode fallbacks.** The bench aborts on a
`precondition` before computing any statistic if a single window falls back to the synthetic decode,
so no number here can be a synthetic number under a real-data label (10-PREREGISTRATION section 10).

The Kalman gain is the real-data re-fit from Plan 10-03, corrected onto the section-3a box by Plan
10-03a. Its provenance header reads `noise source = indy-heldout`, never `default`.

## 2. Provenance

| Field | Value |
|---|---|
| Machine | `Apple M5 Pro`, `arm64` |
| Device status | `corroborating` (this is not the project's canonical iPad Pro M4 capture device) |
| OS | macOS 26.5, build 25F71 |
| Toolchain | Xcode 26.3 (17C529), Apple Swift 6.2.4 (swiftlang-6.2.4.1.4, clang-1700.6.4.2) |
| Build configuration | `-c release` |
| Wall clock | 10.39 s (`/usr/bin/time -p`, second run) |
| Session | `indy_20160630_01` |
| Session sha256 | `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8` |
| Manifest | `Decoder/manifests/indy_sessions.json`, checked byte-equal to the entry above |
| Export sidecar sha256 | `a452ed69ef82d9c6f86d312e12defdadca843513a05092b0c1db1b9eb6dec4e3` |
| Encoder checkpoint sha256 | `f95b257bf2479b49102a2d8afee3c46d9008c51ba754d42a60a26762b7d3af8e` |
| Velocity checkpoint sha256 | `9d542cb51d4af4811f324fbc6bda0b503da7b15aafc98b5e1340e1a7f49cce65` |
| Ticks | `ticks_model_backed` 73129 of `ticks_total` 73129 |
| Determinism | No RNG in the ablation. Two independent runs produced byte-identical JSON (`diff` empty) |
| Seed | Seed 0 appears upstream, in the Kalman gain fit's provenance header. The replay itself has no seed |

Pinned wheel versions for the two Python stages this run consumed the output of, read from the
artifacts those stages emitted rather than from this worktree:

| Stage | Artifact recording it | Versions |
|---|---|---|
| The replay export (Plan 10-02) | `indy_20160630_01.replay.json` `env` | python 3.12.13, numpy 2.4.6, h5py 3.16.0 |
| The shipped model and readout (Phase 9) | `09-decoder-metrics.json` `velocity.env` | python 3.12.13, numpy 2.4.6, h5py 3.16.0, torch 2.12.1, coremltools 9.0 |

The ablation itself is Swift-only. No Python ran in this measurement's loop.

The `KalmanConstants.swift` provenance header, quoted from the generated file:

```
noise source = indy-heldout   seed = 0
session=indy_20160630_01 sha256=2ca8f6b7fcfc n_heldout=14600 lag_bins=1 lambda=0.1 side_mm=171.6820
grid_units_per_cm=0.05824724 sigma_jerk_sq=6048.884948 R=diag(0.15044900,0.08920892) R_offdiag=-0.03146268
rho_closed_loop=0.818794 encoder_sha=f95b257bf247 velocity_sha=9d542cb51d4a heldout_r2_pooled=+0.144602
```

## 3. The numbers

Transcribed from `10-refit-real.json`. The `N=900` column is a **counterfactual 30x30 grid score**
throughout; see section 6. Distance percentiles are the cursor-to-target distance in millimetres and
sit beside the hit count because 10-PREREGISTRATION section 14 makes the proxy RD-08's primary
observable, not a fallback.

| Arm | rotation target | hits | Webgrid BPS (N=900) | Webgrid BPS (N=64) | Fitts TP | realized gain | realized smoothing | dist mm p1 / p5 / p25 / p50 / p90 |
|---|---|---|---|---|---|---|---|---|
| `raw` | none | 0 | 0.000000000 (N=900) | 0.000000000 (N=64) | 0.356339853 | 1.000000000 | 0.599022778 | 16.58 / 35.98 / 69.66 / 97.98 / 144.38 |
| `kalman_only` | none | 0 | 0.000000000 (N=900) | 0.000000000 (N=64) | 0.355568936 | 0.923581354 | 0.942937180 | 16.62 / 35.72 / 69.38 / 97.79 / 144.21 |
| `refit` | true_track | 70 | 0.487984233 (N=900) | 0.298346309 (N=64) | 0.672882476 | 0.909801160 | 0.923848328 | 0.83 / 1.78 / 3.47 / 24.11 / 72.74 |
| `refit_reversed_target` | reversed_track | 2 | 0.013635365 (N=900) | 0.008336460 (N=64) | 0.347854906 | 0.884193582 | 0.900133940 | 3.91 / 14.48 / 35.16 / 53.58 / 90.15 |

Elapsed time per arm: `raw` and `kalman_only` 1440.26 s, `refit` 1407.76 s,
`refit_reversed_target` 1439.46 s. Si is 0 in every arm and that is structural, not measured; see
section 5.

The deltas:

| Delta | Webgrid BPS (N=900) | Webgrid BPS (N=64) | Fitts TP | Reading |
|---|---|---|---|---|
| `refit - kalman_only` | 0.487984233 (N=900) | 0.298346309 (N=64) | 0.317313540 | **the attributable delta**: gain and smoothing held fixed, and `IntentRotation` preserves speed exactly |
| `refit - raw` | 0.487984233 (N=900) | 0.298346309 (N=64) | 0.316542623 | **the confounded one**: conflates the rotation with the Kalman's gain and smoothing |
| `refit - reversed` | 0.474348868 (N=900) | 0.290009850 (N=64) | 0.325027570 | the attribution control |

`refit - raw` equals `refit - kalman_only` on both BPS normalisations for a specific and
uninteresting reason: `raw` and `kalman_only` are both exactly 0. The usual worry, that the headline
delta is inflated by the Kalman's gain and smoothing, cannot arise on this run. That is a property
of a floored comparison, not a finding about the filter, and it should not be quoted as one.

`raw`'s realized gain is exactly 1.000000 **by construction**, since the raw arm's output is its
input. It is not a measurement. The informative comparison is across the three filtered arms:
0.923581, 0.909801, 0.884194, a spread of 0.039388, which is 4.26 percent of the largest. Gain is
therefore not what separates these arms, so the Willett confound of section 8 is measured and ruled
out here rather than assumed away. The smoothing figures do separate: `raw` 0.599023 against
`kalman_only` 0.942937, a factor of 1.574. The Kalman is what smooths; the rotation is not.

## 4. The synthetic before-and-after (D-12)

The Phase-8 triple is preserved beside the real one so the before-and-after stays legible.

| Arm | Webgrid BPS, Phase 8, **synthetic seed-locked replay** | Webgrid BPS (N=900), this run, real spikes | Fitts TP, Phase 8, synthetic | Fitts TP, this run, real spikes |
|---|---|---|---|---|
| `raw` | 1.292123144 (N=900, synthetic) | 0.000000000 (N=900) / 0.000000000 (N=64) | 0.160898602 | 0.356339853 |
| `kalman_only` | 1.183000907 (N=900, synthetic) | 0.000000000 (N=900) / 0.000000000 (N=64) | 0.155455864 | 0.355568936 |
| `refit` | 1.953047884 (N=900, synthetic) | 0.487984233 (N=900) / 0.298346309 (N=64) | 0.374395063 | 0.672882476 |

The Phase-8 column is the seed-locked SYNTHETIC replay it always was; `1.953` is a synthetic number
and is labeled as one everywhere it appears. Its arms are seeded reaches, not recorded spikes.

On synthetic data `kalman_only` was BELOW `raw` on both metrics (1.183001 against 1.292123, and
0.155456 against 0.160899), so none of the synthetic uplift was attributable to the Kalman's gain
and smoothing; all of it was the rotation.

Does the same hold on real data? **On Fitts TP, yes, and by a much smaller margin**: `kalman_only`
0.355569 is below `raw` 0.356340. **On Webgrid BPS the question is undefined on this run**, because
both arms are exactly 0 and a comparison between two floored values carries no information. Saying
"the same holds" on BPS would be reading a result out of a tie.

## 5. The honest gap

The headline that is attributable to the decode is **0.000000 BPS (N=900, counterfactual 30x30 grid
score) and 0.000000 BPS (N=64)**, on both target-blind arms. Its distance from 4.16 is 4.16 and from
8.5 is 8.5. The `refit` arm's 0.487984 (N=900, counterfactual 30x30 grid score) / 0.298346 (N=64) is
3.672016 and 3.861654 below 4.16 respectively, and 8.012016 and 8.201654 below 8.5, but that arm's
heading is target-determined, so quoting its gap as a decoding gap would misstate what produced it.

The two reference figures, each with the condition it was measured under:

- **4.16 +/- 0.39 bps** is Pandarinath et al. 2017, eLife 18554, participant **T5 on a dense 9x9
  grid**, 8 evaluation blocks. It is not a 6x6 number. The 6x6 figures in the same paper are T6
  2.2 +/- 0.4, T5 3.7 +/- 0.4, T7 1.4 +/- 0.1. This repo previously labeled 4.16 as a 6x6 figure;
  RD-09 corrects that label.
- The Neuralink P1 (Noland Arbaugh) reference this repo has cited since Phase 7 is **8.5 BPS**. It
  is kept per D-17 and dated: as of 2026-09-05, neuralink.com/webgrid reads "Our clinical trial
  participants have achieved over 10 BPS controlling a computer with their brain" (retrieved
  2026-09-05). The 8.5 figure is not independently sourceable to a Neuralink primary, and an access
  date does not authenticate a number. The cross-AI review's dissent on keeping it is recorded
  rather than adopted; D-17 is the decision that governs. The canonical wording for this figure is
  defined once in Plan 10-11 task 3a and reused verbatim from there.

**The non-comparability disclosure.** The canonical short form, verbatim from 10-PREREGISTRATION
section 12, on one unwrapped line so byte identity is checkable:

```
this repo's Webgrid BPS is not like-for-like with either reference: the formula differs (log2(N) here versus log2(N-1) in eLife 18554), the grid differs (T5 dense 9x9, not 6x6), the harness makes incorrect selections structurally zero so Si is always 0, and Neuralink's current published score adds a click-types term this single-click-type harness omits
```

Each ground, expanded, with its citation:

1. **Formula.** eLife 18554 computes achieved bitrate with `log2(N - 1)`. `WebgridBPS.swift:55`
   returns `log2(Double(n))`, and `:70` documents the metric as
   `B = max(0, log2(N) x (Sc - Si) / t)`. Matching the `(correct - incorrect)` numerator does not
   make the two the same metric.
2. **Grid.** 4.16 is the dense 9x9 figure, not the 6x6 one.
3. **Task.** The harness makes incorrect selections **structurally zero**. The comment carrying this
   is `CortexReFITBench/main.swift:283-285` as cited in the pre-registration at commit `864259b`,
   which is `:286-288` at this commit after Plan 10-05 removed a three-line block earlier in the
   same file: "There is NO wrong-cell outcome to count as Si (structurally 0)". `Si` is therefore
   always 0 and the metric cannot express the speed-accuracy tradeoff that a human point-and-click
   bitrate measures. The same is true of `CortexReplayBench`, by construction: its
   `incorrect_model` field reads "none - single-target dwell-to-select; Si structurally 0; BPS is
   upper-bound".
4. **Click types.** Neuralink's published score is defined over net correct targets per minute, grid
   size, and the number of **click-type**s. This harness is single-click-type and its disclosed
   formula omits that term, so it is not full formula parity.

One sentence, to be clear about what all four grounds add up to: this repo's Webgrid BPS is **not
like-for-like** with EITHER reference, independent of which reference figure is chosen.

This is a **disclosure, not a formula change**. Editing `bps-policy.sh`'s pinned formula would break
the Phase-7 byte-identity fixture that D-09 exists to protect, so the formula stays and the
disclosure travels with the number.

**One claim this artifact does not make.** It does not say that ReFIT is what carries BrainGate from
the first of those two reference figures up to the second. 10-RESEARCH-INPUTS Finding 3 shows that
framing joins two independently sourced numbers from different systems, participants, arrays and
decoder generations into a causal claim the cited sources do not support. The framing exists in
`docs/cortex-spec.md:46`, `.planning/PROJECT.md:171` and `ROADMAP.md:139` and is RD-09's to sweep.

## 6. Both normalisations, and why

The recorded task presented **64 distinct targets**, which is 6.0 bits per selection
(`target_grid.distinct_targets` = 64, `log2_n_task` = 6.0 in the export sidecar). `WebgridBPS`
normalises by `log2(900) = 9.813781`. Crediting 9.81 bits per hit on a 64-target task awards
**1.635630 times** more information per selection than the task contained.

Both numbers are published, in the same row, everywhere. The N=900 figure is the headline **only for
continuity with the Phase-8 1.953 synthetic figure**, and it carries this label from
10-PREREGISTRATION section 6, in its exact words:

```
counterfactual 30x30 grid score; the recorded task presented 64 targets (6.0 bits), whose rate is N=64
```

It is what the recorded selections would be worth on a 900-cell grid. It is **not** the information
rate of the recorded task. The N=64 figure is the one labeled `the recorded task's information
rate`. Both JSON keys carry a sibling `*_label` string holding exactly these words, so the label
cannot be dropped by a prose edit downstream.

## 7. Hits against the recorded-cursor replay reference

The pre-registered reference from `10-ceiling.json`, at the same radius and the same dwell as this
run: **147 of 1,025 trials (14.34 percent)** at acquisition radius 2.8613660406415042 mm and dwell
0.30 s.

**What that reference is.** It is the hit rate obtained by replaying the animal's OWN recorded
cursor track through this repo's dwell-to-select rule at that radius and that dwell. It is a
property of one recorded trajectory under one acceptance rule. It is not a bound on what a decoder
can achieve: a decoder producing different trajectories, with straighter approaches or longer holds
inside the radius, can exceed it. Its value is that it makes a decoded count interpretable, because
without it a decoded zero says nothing about the decoder when the geometry alone already misses most
trials. The word "ceiling" survives in this artifact only inside the file name `10-ceiling.json` and
the JSON key `ceiling_ref`, both of which predate that framing decision
(10-PREREGISTRATION section 16).

| Arm | hits | of 1,025 trials | of the 147-hit reference | dist mm p1 / p5 / p25 / p50 / p90 |
|---|---|---|---|---|
| `raw` | 0 | 0.00 percent | 0.0000 | 16.58 / 35.98 / 69.66 / 97.98 / 144.38 |
| `kalman_only` | 0 | 0.00 percent | 0.0000 | 16.62 / 35.72 / 69.38 / 97.79 / 144.21 |
| `refit` | 70 | 6.83 percent | 0.4762 | 0.83 / 1.78 / 3.47 / 24.11 / 72.74 |
| `refit_reversed_target` | 2 | 0.20 percent | 0.0136 | 3.91 / 14.48 / 35.16 / 53.58 / 90.15 |
| recorded-cursor replay reference | 147 | 14.34 percent | 1.0000 | not applicable (the reference is the recorded track itself) |

**The zero is not a near miss, and the proxy is what shows that.** Over 73,129 ticks and 1,440
seconds, the closest the target-blind cursor ever came to the target, at the 1st percentile of the
whole distribution, was 16.58 mm on `raw` and 16.62 mm on `kalman_only`. The acquisition radius is
2.8614 mm. The best percentile of the target-blind arms is therefore **5.8 acquisition radii away**.
A hit count that floors at zero cannot distinguish a decoder that drove the cursor most of the way
from one that did nothing; the distance distribution can, and here it says the decoded velocity did
not drive the cursor near the target at all. For contrast, the `refit` arm's p1 is 0.83 mm, inside
the radius at 0.29 of it, which is what a target-determined heading buys.

### The five-factor decomposition of the zero (D-11)

Published in the pre-registered order, with the factor that most directly produces a zero first.
**Acquisition parameters were NOT relaxed**: radius 2.8613660406415042 mm, dwell 0.30 s, timeout
5.0 s, `r_acq` 0.5/30 grid units, exactly as pre-registered, in every arm.

1. **Velocity amplitude shrinkage.** The decoder tracks reach timing well, with decoded peaks
   aligned to true peaks, but systematically under-scales amplitude: true velocity peaks reach
   plus or minus 20 to 30 cm/s while the decoded output rarely leaves plus or minus 10. That is
   ordinary ridge and MSE shrinkage toward the mean, not a defect, and it is decisive for a hit
   count, because a systematically under-scaled velocity travels too short a distance to enter the
   acceptance radius within the dwell window. This mechanism was measured in the pre-execution pass
   recorded in 10-PREREGISTRATION section 14, before this run existed, and this run's own p1
   distances above are its consequence. The quantitative decoded-to-true magnitude ratio, mean and
   p95, is `10-replay.json`'s `decomposition.velocity_amplitude_shrinkage` in a later plan; it is
   not a number this artifact measured and it is not asserted here.
2. **Decode R2.** Two figures, each labeled with the method that produced it, and neither adjusted
   toward the other. **+0.1446** is the Phase-9 per-session held-out velocity R2 from
   `09-decoder-metrics.json` `velocity.per_session`, produced by the pooled Phase-9 split, n = 14,600,
   null = this session's own train-split mean velocity per axis. **0.1523** is an independent
   pre-execution re-measurement on 2026-09-05 on a chronological tail split of this one session,
   73,161 bins by 96 channels, split at bin 58,529, 14,601 held-out rows, scored with this repo's
   own `fit_velocity_real._build_design` and `kinematics.heldout_r2` against the train-split mean
   null, giving vx 0.0671, vy 0.2653, pooled 0.1523. The session was **deliberately not switched**:
   `indy_20160630_01` is locked by D-08, it is the weakest of the four (the range was +0.1446 to
   +0.5069, pooled +0.4238), and choosing a stronger session after seeing that would be selection on
   the outcome. The weakness is disclosed, not corrected.
3. **No closed-loop error correction.** A recorded session's spikes cannot respond to a cursor we
   drive. In a real closed loop the subject sees the cursor drift and corrects it; an open-loop
   replay has no such channel, so every decode error accumulates in the integrator instead of being
   pushed back. Offline decode accuracy is a poor predictor of closed-loop control quality for
   exactly this reason.
4. **Workspace-to-grid scale.** The `cursor_bbox_square` normalisation, `side_mm`
   171.68196243849025, `cell_mm` 5.7227320812830085, `acq_radius_mm` 2.8613660406415042. The
   acceptance zone is a half-cell of a 30x30 grid laid over the session's own cursor bounding box.
5. **Dwell and timeout.** Dwell 0.30 s with continuous-dwell semantics, timeout 5.0 s. At the 20 ms
   tick these are 15 consecutive in-radius samples. Not relaxed.

### The section 15 row, named and not adjudicated

10-PREREGISTRATION section 15's first column reads on the `refit` arm's hit count at the
pre-registered radius and dwell. On that literal text this run falls in **row A** (`hits >= 1`; the
measured count is 70). The row is named here because the plan requires the row to be named, and
nothing is concluded from it.

Two facts sit beside that row and are for the later plans to weigh, not for this artifact:

- the `refit` arm's heading is target-determined by construction (section 8b), so its 70 hits are
  not an independent decoding result;
- the two target-blind arms are 0 of 1,025, which is the shape row B describes.

The disposition was fixed in writing before the measurement, the table is committed at `864259b`,
and it is not reopened here. `sc2_disposition` and `sc2_rule` are keys of `10-replay.json`, not of
this file (section 15 rule 3), so **this artifact draws no conclusion about SC#2**. Per section 15
rule 2 no agent amends a success criterion; the amend-or-defer choice is confirmed by the user at
**Plan 10-10 Task 3**, which is a blocking checkpoint.

## 8. The Willett framing, scoped

Willett et al. 2017, "A Comparison of Intention Estimation Methods for Decoder Calibration in
Intracortical Brain-Computer Interfaces", IEEE Trans Biomed Eng 65(9):2066-2078, DOI
`10.1109/TBME.2017.2783358`, compared intention-estimation methods for decoder **CALIBRATION** on
BrainGate2 pilot clinical trial data, including ReFIT, an optimal feedback control model, a
piecewise-linear feedback control model and simpler heuristics, against a steady-state velocity
Kalman filter; it found that decoded velocity vectors differed by under 5 percent in angular error
while smoothing and output gain differed by over 50 percent, and concluded that simple differences
in gain and smoothing properties "can confound decoder comparisons". That warning is the entire
reason this artifact reports `realized_gain` and `realized_smoothing` per arm: gain and smoothing
are reported per arm so that any uplift is attributable rather than assumed, and on this run they
are measured to be within 4.26 percent across the three filtered arms. The limit of the citation, in
the same breath: the paper is about how the intention used to FIT a decoder is estimated, while this
repo's `IntentRotation` is a RUNTIME transform on an already-fit decoder's output, so the paper is
**not** a prediction about what this rotation should achieve, and no sentence in this artifact uses
it as one. An earlier research pass drew that inference; the cross-AI review of 2026-09-05 corrected
it and this is the corrected form. This is the only source cited for the confound; the four
offline-versus-closed-loop candidates in 10-RESEARCH-INPUTS Finding 4 remain unverified against
their primary text and are not cited.

## 8b. What the reversed-target arm establishes, and what it does not

Reproduced verbatim from 10-PREREGISTRATION section 7, which was committed before this number
existed:

> **What this control can and cannot establish.** Pre-registered before the number exists. Read both
> directions and do not later state only the flattering one.
>
> - If uplift **survives** the reversed target, the uplift is the rotation exploiting target
>   knowledge rather than the decode, and that is the finding (CONTEXT D-04).
> - If uplift **disappears** under the reversed target, that does **not** convert the `refit` arm
>   into an independent neural-decoding result. `IntentRotation.rotate`
>   (`IntentRotation.swift:75-85`) returns `(speed / dist) * d`: it replaces the decoded direction
>   with the direction to the known target and keeps only the decoded speed. The `refit` arm's
>   cursor heading is target-determined by construction in both arms; only the target differs. So
>   the correct reading of a failing reversed arm is narrow: the rotation needs the correct target
>   to help. It says nothing about how much intent the decode itself carried. The `raw` and
>   `kalman_only` arms, which never see a target, are the only arms whose rate is attributable to
>   the decode.

What happened: the uplift **disappeared** under the reversed target, 70 hits against 2, and
0.487984 against 0.013635 at N=900 (counterfactual 30x30 grid score; 0.298346 against 0.008336 at
N=64). By the paragraph above, the correct and narrow reading is that the rotation needs the correct
target to help. It is not evidence that the decode carried intent.

## 9. What this does not establish

**The open-loop disclosure (D-03), in full.** The byte-identical string this repo uses everywhere is
`open-loop replay of a recorded session; the subject was not in the loop`. "Closed loop" in this
project refers to the SOFTWARE path being closed end to end. It never refers to the subject being in
the loop, because a recorded session's spikes cannot respond to a cursor we drive.

Also not established here:

- **Generality.** One session, `indy_20160630_01`, chosen in advance by D-08 and the weakest of the
  four by held-out velocity R2.
- **Live-human calibration.** No live-human two-stage ReFIT retrain happened. This is a runtime
  rotation on an already-fit decoder, not a recalibration study.
- **Transfer.** No cross-session claim is made or supported. Phase 9's four leave-one-session-out
  co-bps folds were all negative against the test-mean null, mean **-0.3498**, range -0.7805 to
  -0.1238. The encoder does not transfer to an unseen session.
- **Device.** Every number here is an Apple M5 Pro number, labeled `corroborating`. None is an
  iPad Pro M4 number and none is a hardware-gated performance claim.
- **SC#2.** See section 7.

## 10. Runbook

Copy-pasteable from a clean checkout, with the dataset and the export materialized. The stale
`.bench` deletion is first and is not optional: a stale `.bench/glass_to_glass.json` from an earlier
phase carries an old methodology label that could be transcribed into evidence by mistake.

```bash
rm -rf Packages/CortexReFIT/.bench Packages/CortexDemo/.bench Packages/CortexDecoder/.bench

swift build -c release --package-path Packages/CortexDemo --product CortexReplayBench

CORTEX_REPLAY_EXPORT=Decoder/exports/indy_20160630_01.replay.json \
CORTEX_MODEL_URL=Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage \
swift run -c release --package-path Packages/CortexDemo CortexReplayBench \
  --out .planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real.json
```

Use a release build. Debug is roughly two orders of magnitude slower over the 224 million
`SpikeInputBuffer.write` calls this makes.

This run was executed in a git worktree, where the gitignored `Decoder/exports/`,
`Decoder/data/` and `Decoder/checkpoints/` do not exist. They were made available by creating those
three as real directories and symlinking the already-materialized, checksum-pinned files into them.
`git status` stays clean, and nothing from any of the three is committed.

Prerequisites, if starting from nothing:

```bash
uv sync --project Decoder --extra dev
uv run --project Decoder python Decoder/scripts/download_indy.py
uv run --project Decoder python Decoder/scripts/export_replay.py --session indy_20160630_01
```

Three of the emitted values that the bench cannot know were hand-added to
`10-refit-real.json` after the run, and this is recorded rather than left implicit:
`ceiling_ref` (copied field by field from the committed `10-ceiling.json`), `phase9_bounds` (copied
from `09-decoder-metrics.json`), and `env.ticks_model_backed` / `env.ticks_total` (the section-10
counts, both equal to the already-emitted `env.ticks`). The `references.note` the plan also names
was already emitted correctly by the bench and was not touched. The hand-edit was performed with a
Python round-trip that was first proven byte-identical to the Swift `JSONEncoder` output on the
unmodified file, so the only difference between the generated and the committed artifact is those
keys, and `diff` was used to confirm it.

## 11. D-09: no gate asserts the sign or magnitude of any number here

No gate, test or CI step asserts the sign or magnitude of any number in this artifact. Plan 10-09's
gate asserts provenance, schema and structure only. `10-refit-real.json` carries no `passed` key, no
`verdict` key and no `budget_ns` comparison (`grep -c '"passed"'` returns 0), and `CortexReplayBench`
compares nothing against any bar and exits 0 whatever the numbers are.

The Phase-7 `refit_bps.json` byte-identity invariant and `check_refit_uplift.py`'s
`refit_bps >= raw_bps` check remain untouched and synthetic-scoped. They run on the FROZEN Phase-7
gain, `KalmanConstants.phase7BaselineK`, precisely so that a real-data re-fit or a real-data result
cannot turn the build red. A negative or zero finding has to be publishable without reddening
anything, because a red build is pressure to tune, and this phase exists to remove that pressure
rather than to add it.

---

*Artifact: `.planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real.json`*
*Phase: 10-v1-real-data-closed-loop-launch, Plan 10-07, requirement RD-07*
*Measured 2026-09-05 on Apple M5 Pro, status corroborating*
