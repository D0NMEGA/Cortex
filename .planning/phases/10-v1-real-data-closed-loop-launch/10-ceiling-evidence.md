# Phase 10 RD-08 evidence: the recorded-cursor webgrid replay reference

**Date:** 2026-09-05 (Plan 10-01, Task 3). Read the pre-registration in
`10-PREREGISTRATION.md`, committed in `864259b` before this run, before this number, and before any
decoded number exists in this phase.

**Result:** replaying the animal's own recorded cursor through this repo's dwell-to-select rule at
an acquisition radius of **2.8614 mm** and a dwell of **0.30 s** hits **147 of 1,025 trials
(14.3 percent)** on `indy_20160630_01`.

## What this is not

This is a property of **one recorded trajectory under one acceptance rule at one radius and one
dwell**. It is not a bound on what a decoder can score. A decoder that produces different
trajectories, with straighter approaches or longer holds inside the radius, can exceed it. Its
value is as a pre-registered reference point that makes a decoded count interpretable: without it,
a decoded zero says nothing about the decoder, because the geometry alone already misses most
trials.

The reviewer who independently reproduced this arithmetic on 2026-09-05 reproduced the numbers and
rejected the framing that this is what any decoder could at best achieve. That framing does not
appear in this artifact and must not appear in any Phase 10 artifact. The word "ceiling" survives
only in the file and identifier names that already carried it (`webgrid_ceiling.py`,
`10-ceiling.json`, this file); every published sentence uses the recorded-cursor replay wording.

## Environment

| Field | Value |
|---|---|
| Machine | `Apple M5 Pro`, `arm64` |
| OS | macOS 26.5 (`sw_vers -productVersion` -> `26.5`) |
| Platform string | `macOS-26.5-arm64-arm-64bit` |
| Interpreter | CPython 3.12.13 (uv-managed) |
| numpy | 2.4.6 |
| h5py | 3.16.0 |
| Determinism | No seed. The computation is a deterministic pass over the recorded arrays: no sampling, no RNG, no clock |
| Session | `indy_20160630_01` |
| Source sha256 | `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8` |
| Manifest | `Decoder/manifests/indy_sessions.json` (the emitted JSON binds to this digest; the script refuses a `PENDING` or non-64-hex entry) |
| Wall clock | 0.18 s total |

The versions above were read from the environment that produced the number, with
`uv run --project Decoder python -c "import numpy,h5py,sys,platform;print(...)"`, not transcribed
from another document.

The M5 Pro is a corroborating development machine, not the project's canonical iPad Pro M4 capture
device. That distinction does not bear on this file: nothing here is a hardware-gated performance
claim. A hit count is a property of a recorded trajectory and an acceptance rule, not of the
silicon that counted it.

## Runbook

Copy-pasteable from a clean checkout with the dataset materialized:

```bash
uv sync --project Decoder --extra dev
uv run --project Decoder python Decoder/scripts/download_indy.py   # only if Decoder/data/ is empty
uv run --project Decoder python Decoder/scripts/webgrid_ceiling.py \
  --session indy_20160630_01 \
  --out .planning/phases/10-v1-real-data-closed-loop-launch/10-ceiling.json
```

This run was executed in a git worktree, where the gitignored `Decoder/data/` does not exist. The
session was made available by creating `Decoder/data/` and symlinking the already-materialized,
checksum-pinned `indy_20160630_01.mat` into it, so the command above ran verbatim with its default
`--data-dir`. Neither the directory nor the symlink is committed: `.gitignore:90` covers
`Decoder/data/`, verified with `git check-ignore -v`.

## The computed box

The workspace normalisation is `cursor_bbox_square`, pre-registered in `10-PREREGISTRATION`
section 3. The box is a square, axis-aligned, derived from the session's own cursor track.

| Quantity | Value |
|---|---|
| `side_mm` | 171.68196243849025 |
| `cell_mm` | 5.7227320812830085 (`side_mm / 30`) |
| `acq_radius_mm` | 2.8613660406415042 (`cell_mm / 2`) |
| `x_min_mm` | -74.0309318477683 |
| `x_max_mm` | 97.65103059072196 |
| `y_min_mm` | -30.400955608084388 |
| `y_max_mm` | 141.28100683040586 |
| `centre_x_mm` | 11.810049371476829 |
| `centre_y_mm` | 55.440025611160735 |
| Containment | Passed. All 365,809 cursor samples fall inside the box; the script raises `ValueError` naming the offending count if any does not |

The reason the box comes from the cursor and not from the 105.0 mm target field, in one line:
`CursorIntegrator` clamps to `[0, 1]`, so normalising on the target field would clip real cursor
excursions (the cursor spans 171.7 mm by 139.1 mm and leaves the target field on both axes), and a
clipped trajectory is fabricated cursor behavior.

The pre-registration recorded `side_mm` about 171.7, `cell_mm` about 5.72 and `acq_radius_mm` about
2.86 as **expected** values, not asserted ones. The measured values above are what the script
computed, and they land where the pre-registration expected.

## The table

Every radius by dwell cell from `10-ceiling.json`, hit count out of 1,025 trials. The **canonical**
cell is the pre-registered one: the box's own `acq_radius_mm` at dwell 0.30 s.

| Acquisition radius | Dwell 0.30 s | Dwell 0.10 s |
|---|---|---|
| 1.75 mm | 43 / 1025 (4.2%) | 153 / 1025 (14.9%) |
| 2.32 mm | 83 / 1025 (8.1%) | 242 / 1025 (23.6%) |
| 2.86 mm | 147 / 1025 (14.3%) | 334 / 1025 (32.6%) |
| **2.861366 mm (canonical)** | **147 / 1025 (14.3%)** | 334 / 1025 (32.6%) |
| 3.50 mm | 249 / 1025 (24.3%) | 449 / 1025 (43.8%) |
| 7.50 mm | 951 / 1025 (92.8%) | 1007 / 1025 (98.2%) |
| 15.00 mm | 1023 / 1025 (99.8%) | 1025 / 1025 (100%) |

## Reproduction check

`10-RESEARCH.md` Correction 4 independently measured the six reference radii on 2026-09-05, before
`webgrid_ceiling.py` existed. Every row reproduces exactly.

| Radius (mm) | Dwell 0.30 s, RESEARCH | Dwell 0.30 s, this run | Dwell 0.10 s, RESEARCH | Dwell 0.10 s, this run |
|---|---|---|---|---|
| 1.75 | 43 | 43 | 153 | 153 |
| 2.32 | 83 | 83 | 242 | 242 |
| 2.86 | 147 | 147 | 334 | 334 |
| 3.50 | 249 | 249 | 449 | 449 |
| 7.50 | 951 | 951 | 1007 | 1007 |
| 15.00 | 1023 | 1023 | 1025 | 1025 |

Twelve of twelve cells agree, and the trial count agrees at 1,025. No row differed, so nothing had
to be recorded as a discrepancy. Had a row differed, the rule set in the plan was to record the
difference and its likely cause rather than to adjust the script: a control that was tuned until it
reproduced an expected number is not a control.

Two things make that claim worth something rather than circular. The dwell and segmentation
semantics are pinned independently in `Decoder/tests/test_webgrid_ceiling.py` on synthetic arrays
whose answers are known by hand, so the script's rule is checked against arithmetic rather than
against the number it is supposed to reproduce. And the strict-versus-inclusive boundary is
documented rather than tuned: `WebgridAcquisition.runTrial` accepts a sample exactly on the radius
(`<=`) while this script is strictly inside (`<`), matching the reference implementation the table
was measured with. On continuous-valued millimetre distances the boundary is measure-zero, so the
two agree on this data.

One defect was found and fixed during this run, and it is recorded here because it changed code
rather than a number. Computing the box edge on the span-defining axis as `centre +/- side/2` does
not round-trip to the observed extreme: the `x_max` sample fell 1.4e-14 mm outside the box and the
strict containment check refused the entire session. The fix gives that axis the observed extremes
verbatim, which is the same square in exact arithmetic. The check was not loosened, and
`test_square_box_containment_is_exact_on_the_governing_axis` pins the exactness with `==` rather
than `approx`, because `approx` would pass under the very defect it guards. All 365,809 samples are
finite; there was never a data problem.

## Interpretation

The 7.50 mm row is the task's own implied acceptance zone. The animal held a 300 ms dwell inside
7.5 mm of the target on 92.8 percent of trials, and 7.5 mm is half the real 15 mm target pitch. On
that reading the recorded task is effectively a 14x14 grid over the field, not a 30x30 one.

D-02 locks the 30x30 re-grid. This artifact reports that consequence rather than changing the
decision: the canonical 2.8614 mm radius is roughly a third of the task's own implied zone, and the
recorded trajectory itself clears it on 14.3 percent of trials. A decoded cursor is being asked to
do something the recorded cursor does about one time in seven.

Two further facts belong beside the number, because they are what make a decoded zero the expected
outcome rather than a surprise:

- `indy_20160630_01` is the **weakest** of the four sessions by held-out velocity R2 (+0.1446
  against a per-session range of +0.1446 to +0.5069). D-08 locked it in advance, before any outcome
  was known, and `10-PREREGISTRATION` section 15 rule 0 keeps it locked. The weakness is disclosed,
  not corrected.
- The pre-execution measurement recorded in `10-PREREGISTRATION` section 1 found pooled held-out
  R2 about 0.15 on a chronological tail split of this session, with the decoder tracking reach
  timing well but systematically under-scaling velocity amplitude. A cursor driven by
  systematically under-scaled velocity travels too short a distance to enter a 2.86 mm acceptance
  radius within a 300 ms continuous dwell.

## The RD-08 hit contract

Reproduced verbatim from `10-PREREGISTRATION` section 15, so a reader meets it **before** the
decoded measurement rather than after. The disposition is chosen from this table whatever the
outcome.

| Outcome on the `refit` arm at the pre-registered radius and dwell | SC#2 disposition (`sc2_disposition`) | What the phase does |
|---|---|---|
| **A.** `hits >= 1` | `met` | Publish the count against the replay reference. Plan 10-10 Task 2 captures the demonstration on the M5 Pro |
| **B.** `hits == 0` on all four arms and the recorded-cursor replay reference is `>= 1` (**the expected row**) | `not_met` | Publish the zero, with the distance proxy as the primary observable and the five-factor D-11 decomposition beside it. Do not relax radius, dwell or timeout. Record SC#2 as NOT MET and route the amend-or-defer choice to the user at Plan 10-10 Task 3, which is a blocking checkpoint |
| **C.** `hits == 0` and the recorded-cursor replay reference is also `0` | `unachievable_at_this_geometry` | The geometry admits no hit for the recorded trajectory either, so the criterion cannot discriminate. That is itself the finding. Publish it and route the same user choice |

**Which row is still open.** All three. No decoded number exists yet, so no row has been selected.
What this artifact fixes is the **denominator side** of the contract: the recorded-cursor replay
reference at the canonical radius and dwell is **147, which is `>= 1`**. Row C is therefore ruled
out at this geometry: if the decoded count comes back zero, it lands in row B, `not_met`, and not
in the "the criterion cannot discriminate" escape. That is the harder of the two zero outcomes, and
it is fixed here, before the measurement, rather than after.

The four binding rules carry unchanged: the session is not switched, no acquisition parameter is
relaxed in any row, no agent amends a success criterion, and the disposition is written into
`10-replay.json` as `sc2_disposition` with `sc2_rule` naming the row.

## Pre-registration statement

**This number was committed before any decoded hit count existed.** The pre-registration that
governs it is commit `864259b` (`docs(10-01): pre-register every Phase 10 measurement convention`),
which fixes the workspace box, the canonical radius and dwell, the artifact schema and the RD-08
hit contract. This artifact and `10-ceiling.json` land in the commit that carries this file, and
that commit precedes every commit in this phase that touches `10-replay.json` or any decoded
number. The git order is the audit trail (threat T-10-01-02).

Nothing in `10-PREREGISTRATION.md` was edited after this measurement was taken.

## Disclosure

`open-loop replay of a recorded session; the subject was not in the loop`

The recorded cursor replayed here is the animal's own movement from 2016. Nothing in this
measurement responds to anything this project does, and no claim about closed-loop control follows
from it.

## Artifact

`10-ceiling.json`, thirteen top-level keys exactly as `10-PREREGISTRATION` section 11 fixes them:
`schema_version`, `data_source`, `session_id`, `source_sha256`, `manifest_path`, `workspace`,
`canonical_radius_mm`, `canonical_dwell_s`, `canonical_hits`, `trials`, `table`, `env`,
`disclosure`. `data_source` is `real`.
