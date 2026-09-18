# Phase 11 evidence: decomposing the 0 of 1,025 into a geometry term and a decode term

**Date:** 2026-09-17 (Plan 11-01). Governed by `10-PREREGISTRATION.md`, committed in `a72344b`
before any of the numbers this file reads existed.

**Result.** The published zero is **not** a near miss that a corrected acceptance rule would
recover. At its closest 1 percent of samples, the target-blind decoded cursor sits **16.58 mm** from
the target: **5.80x** the canonical 2.8614 mm acceptance radius, **2.21x** the task's own 7.50 mm
half-pitch, and **1.11x** even the 15.00 mm radius at which the animal's recorded hand scores
1,023 of 1,025. The geometry critique is correct and is not load-bearing. Fixing the geometry does
not produce a decoded hit.

## What this is and is not

This is a **re-reading of committed Phase 10 artifacts**, not a new measurement. It reads
`10-refit-real.json` (Plan 10-07) and `10-ceiling.json` (Plan 10-01) and does arithmetic on numbers
already published. No model was trained, re-fit or re-run; no checkpoint was written; no radius,
dwell or timeout was changed. Pre-registration rule 1 forbids relaxing the acceptance rule to
manufacture a hit. This file does the opposite operation: it measures the tolerance the decoder
would require and reports that the required tolerance exceeds the point where the task geometry
still means anything.

It remains an **open-loop replay of a recorded session; the subject was not in the loop.** Recorded
spikes cannot react to a decoded cursor, so nothing here is closed-loop evidence at any radius, and
no number here bounds what a decoder could achieve.

## Sources

| Field | Value |
|---|---|
| Arms, hits, distance percentiles | `.planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real.json` |
| Recorded-hand reference, workspace box | `.planning/phases/10-v1-real-data-closed-loop-launch/10-ceiling.json` |
| Session | `indy_20160630_01` (the weakest of four by held-out velocity R2, 0.1446 vs 0.4238 pooled; locked deliberately per D-14) |
| Source sha256 | `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8` |
| Encoder checkpoint sha256 | `f95b257bf2479b49102a2d8afee3c46d9008c51ba754d42a60a26762b7d3af8e` |
| Cursor updates (ticks) | 73,129 |
| Trials | 1,025 |
| Behavior clock | 250 Hz (median `diff(t)` = 0.004 s) |
| Determinism | Arithmetic over committed JSON. No sampling, no RNG, no clock, no dataset read |

## The acceptance rule, restated

| Quantity | Value | Where it comes from |
|---|---|---|
| Workspace side | 171.682 mm | `cursor_bbox_square`, derived from the session's own recorded cursor excursion |
| 30x30 cell | 5.7227 mm | side / 30 |
| **Canonical acceptance radius** | **2.8614 mm** | half-cell |
| Task target pitch | 15.0 mm | the dataset's own 8x8 lattice of 64 targets |
| Task half-pitch | 7.50 mm | the disc inscribed in a real task cell |
| Dwell | 0.30 s | Both scorers use 0.30 s, on **different clocks**. See the note below. |
| Dwell, recorded-hand ceiling | **75 consecutive samples** | `webgrid_ceiling.py` scores the recorded cursor on the 250 Hz Indy behavior clock |
| Dwell, decoded arms | **15 consecutive ticks** | `CortexReplayBench` decodes once per 20 ms bin (`dt = 0.020`, about 50 Hz), so 0.30 s is 15 ticks |

The 2.8614 mm radius is derived from the cursor bounding box cut into a 30x30 Webgrid, not from the
task. It is about 2.6x tighter than the task's own geometry. That mismatch is real and is documented
in `10-radius-rule-figure-evidence.md`.

## Term 1: the geometry loss, 1,025 to 147

Replaying the animal's **own recorded hand** through the same acceptance rule:

| Acceptance radius | dwell 0.30 s | dwell 0.10 s |
|---|---|---|
| 2.8614 mm (canonical) | 147 / 1,025 (14.3%) | 334 / 1,025 (32.6%) |
| 7.50 mm (task half-pitch) | 951 / 1,025 (92.8%) | 1,007 / 1,025 (98.2%) |
| 15.00 mm | 1,023 / 1,025 (99.8%) | 1,025 / 1,025 (100%) |

A perfect decoder that exactly reproduced the hand would score 147, not 1,025. **878 of the 1,025
trials are lost to the acceptance rule before decoding is involved.**

## Term 2: the decode loss, 147 to 0

Cursor-to-target distance by arm, from `10-refit-real.json`:

| Arm | Target info used | Hits | p1 | p5 | p25 | p50 | p90 | p1 / 2.8614 mm |
|---|---|---|---|---|---|---|---|---|
| `raw` | none | **0** | 16.58 | 35.98 | 69.66 | 97.98 | 144.38 | **5.80x** |
| `kalman_only` | none | **0** | 16.62 | 35.72 | 69.38 | 97.79 | 144.21 | **5.81x** |
| `refit` | `true_track` | 70 | 0.83 | 1.78 | 3.47 | 24.11 | 72.74 | 0.29x |
| `refit_reversed_target` | `reversed_track` | 2 | 3.91 | 14.48 | 35.16 | 53.58 | 90.15 | 1.37x |

Distances in mm. Only the two arms using no target information are decode-attributable.

**The `refit` arm's 70 hits are target-determined by construction and are not a decode result.**
`IntentRotation` rotates the decoded velocity toward the known target direction, so that arm is
told where to go. The `refit_reversed_target` control, identical but rotated toward a reversed
target, collapses to 2 hits. The 70-versus-2 spread measures the target information injected by the
rotation, not decoding. This is already the published framing (PROJECT.md, D-14).

## The effective acceptance radius

For the target-blind arms, the smallest radius at which even **1 percent** of samples fall inside is
**16.58 mm**. Against the three reference radii:

| Reference radius | Recorded hand scores | Decoded p1 distance vs that radius |
|---|---|---|
| 2.8614 mm (canonical) | 147 / 1,025 | 5.80x outside |
| 7.50 mm (task half-pitch) | 951 / 1,025 | 2.21x outside |
| 15.00 mm | 1,023 / 1,025 | 1.11x outside |

At 15.00 mm the recorded hand has essentially solved the task and the decoded cursor's closest
percentile is still outside the disc. **There is no radius at which the decoder scores and the task
geometry still means anything**, because the radius the decoder would need is larger than the radius
at which the task stops discriminating.

The dwell requirement makes this starker. At 16.58 mm at most 1 percent of 73,129 samples are
inside, at most 731 in total, a mean of 0.71 ticks per trial against the **15 consecutive** the
0.30 s dwell demands of the decoded arms. (A trial averages 71 ticks, so 15 consecutive is a real
requirement, not a formality.)

**Correction, 2026-09-18.** An earlier revision of this file gave the decoded arms' dwell as 75
consecutive samples. That is the recorded-hand figure. `webgrid_ceiling.py` scores the recorded
cursor on the 250 Hz behavior clock, where 0.30 s is 75 samples; `CortexReplayBench` decodes once per
20 ms bin (`dt = 0.020`, measured 50.77 Hz over 73,129 ticks in 1,440.26 s), where 0.30 s is 15
ticks. The two rules are equivalent in time and differ only in sample count. The conclusion is
unchanged and the corrected bar is lower, so it is stated here rather than quietly amended: at
0.71 inside-ticks per trial against 15 consecutive required, the margin is still roughly twenty-fold.

**Stated precisely, with its limit.** Percentiles bound the sweep, they do not replace it. From p1
alone it follows that under 1 percent of samples lie inside 15.00 mm; it does not follow deductively
that the hit count at 15.00 mm is exactly zero, because percentiles carry no information about
whether the inside-samples cluster into runs. The measured zero at 2.8614 mm is an observation; the
claim at 7.50 mm and 15.00 mm is a strong bound, not a proof. Settling it exactly requires the full
per-sample distance array and a re-run of `ceiling()` across the radius grid, which is the natural
first task of any continuation of this phase.

## What the decoded cursor is actually doing

Median distance to target is **97.98 mm** in a workspace **171.682 mm** on a side: **57.1 percent of
the workspace width**. The decoded cursor is not approaching the target and missing narrowly. It is
substantially uncorrelated with target position over most of the session. This is consistent with a
held-out velocity R2 of **0.1446** on this session, integrated open-loop, with no feedback path by
which error can be corrected, because the subject is a recording.

## Why this is the honest reading

A reviewer's natural objection to the published zero is "your evaluator is mis-specified, so fix the
geometry and re-score." The arithmetic above answers it: the evaluator **is** mis-specified, by a
factor of about 2.6 in radius, and correcting it fully would still not yield a decoded hit. The
decode gap is roughly an order of magnitude in the quantity that matters, not a boundary case.

The claim that survives is narrower and more defensible than "the decoder is weak": **the decoder
does not put the cursor near the target, and the acceptance rule's tightness, while real, is not the
reason the count is zero.**

## Runbook

```bash
python3 - <<'PY'
import json
d = json.load(open('.planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real.json'))
c = json.load(open('.planning/phases/10-v1-real-data-closed-loop-launch/10-ceiling.json'))
R = c['canonical_radius_mm']
for a in d['arms']:
    q = a['distance_to_target_mm']
    print(f"{a['name']:24s} hits={a['correct']:4d} p1={q['p1']:7.2f} p50={q['p50']:7.2f} "
          f"p1/R={q['p1']/R:5.2f}x target={a['rotation_target_source']}")
PY
```

Reads only committed artifacts. Needs no dataset, no model and no GPU.
