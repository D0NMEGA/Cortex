---
status: PASS
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 05
subsystem: swift
tags: [swift, refit, kalman, ablation, rd-07, d-09, byte-identity, willett-confound, coreml, ndt1]

# Dependency graph
requires:
  - phase: 10-v1-real-data-closed-loop-launch
    provides: Plan 10-03's real-data Kalman re-fit and 10-03a's corrected workspace box; Plan 10-02's D-06 export; Plan 10-04's CortexCore.ReplayExport, RecordedSpikeSource and the spike-source seam; 10-PREREGISTRATION sections 3a, 6, 7, 8, 10, 11, 12, 13 and 15
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    provides: the shipped ndt1_real_vel_sweep_fp16.mlpackage with its (1, 96, 1, 32) spikes input
  - phase: 07-refit-kalman-closed-loop-recalibration
    provides: KalmanFilter, IntentRotation, WebgridAcquisition, FittsThroughput and the committed refit_bps.json fixture
provides:
  - KalmanConstants.phase7BaselineK - the frozen Phase-7 gain, emitted by the same generator that emits the shipped K
  - KalmanFilter.init(gain:) - the ONE gain-unpacking implementation, with init() forwarding to it
  - CortexReFITBench --smoke running on the frozen gain, so the synthetic fixture is immune to a real-data re-fit
  - ArmStatistics.realizedGain / realizedSmoothing - the always-finite Willett-confound statistics
  - CortexReplayBench - the RD-07 four-arm ablation over the D-06 export, writing refit_real.json
affects: [10-06, 10-07, 10-09, 10-10, 10-11, 10-12, rd-07-ablation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A build gate that guards CODE is pinned to a frozen constant, so a data re-fit can never redden it"
    - "The frozen constant is emitted by the same generator through the same solver as the shipped one, never transcribed"
    - "A decoy env hook with no implementation behind it is made to refuse loudly and name the real entry point, rather than half-honoured"
    - "A real-data measurement executable is separate from the synthetic fixture whose bytes are a gate"
    - "A confound is turned into two reported per-arm numbers instead of an assumption in prose"

key-files:
  created:
    - Packages/CortexDemo/Sources/CortexDemo/ArmStatistics.swift
    - Packages/CortexDemo/Tests/CortexDemoTests/ArmStatisticsTests.swift
    - Packages/CortexDemo/Sources/CortexReplayBench/main.swift
  modified:
    - Decoder/scripts/fit_kalman_gain.py
    - Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift
    - Packages/CortexReFIT/Sources/CortexReFIT/KalmanFilter.swift
    - Packages/CortexReFIT/Sources/CortexReFITBench/main.swift
    - Packages/CortexReFIT/Tests/CortexReFITTests/KalmanConstantsTests.swift
    - Packages/CortexReFIT/Tests/CortexReFITTests/KalmanFilterTests.swift
    - Packages/CortexDemo/Package.swift
    - Packages/CortexDemo/Tests/CortexDemoTests/ClosedLoopPipelineTests.swift

key-decisions:
  - "phase7BaselineK is COMPUTED in every generator run from default_noise(seed) through the same steady_state_gain call, not transcribed; it came out bit-identical to the Phase-7 gain committed at 5202a96, which is the proof that the freeze is the real Phase-7 gain"
  - "KalmanFilter.init() became a convenience forwarding to init(gain:), so there is exactly ONE unpacking implementation and a second gain source cannot drift from the first"
  - "CORTEX_REFIT_REPLAY_URL disposition: option (ii), the hook is KEPT and a present path exits 1 naming CortexReplayBench. Deleting it would have removed the discoverability; half-honouring it was the defect"
  - "CortexReplayBench decodes ONE tick per 20 ms bin on a trailing 32-bin window, not one per non-overlapping window. Non-overlapping windows advance the session clock 640 ms per tick, which collapses the pre-registered 0.30 s dwell to a single sample"
  - "One CursorIntegrator is carried across the whole replay per arm rather than reset per trial: the D-06 export has NO recorded cursor track, so the plan's per-trial 'first true cursor position' does not exist, and a continuous cursor is also what the recorded task had"
  - "The emitted arm entries carry four fields beyond section 11's list (bps_n900_label, bps_n64_label, distance_to_target_mm, incorrect_model); the first two are required by section 6, the third by this plan, the fourth is the structural-Si disclosure. The TOP-LEVEL key set matches section 11 exactly"

patterns-established:
  - "A carried-in pre-existing defect is repaired only after reproducing BOTH directions in this worktree, not on the finding plan's word"
  - "A regenerated generated file is proven correct by diffing its new constant against the historical commit it claims to restore"

requirements-completed: [RD-07]

# Metrics
duration: 95min
completed: 2026-09-05
---

# Phase 10 Plan 05: The frozen fixture gain and the four-arm real-data ablation Summary

**The two byte-identity gates 10-03's re-fit turned red are green again with neither committed fixture re-issued, and `CortexReplayBench` now runs four arms over 73,129 real decoded ticks of `indy_20160630_01` with zero decode fallbacks, reporting realized gain and smoothing per arm and both BPS normalisations.**

## Performance

- **Duration:** 95 min
- **Tasks:** 3, plus one authorized carried-in repair
- **Files:** 11 (3 created, 8 modified)
- **Commits:** 6 (2 TDD RED, 3 GREEN, 1 carried-in repair)

## Task commits

| # | Task | Commit | Type |
|---|---|---|---|
| 1 | Frozen-gain tests (RED) | `2589a12` | test |
| 1 | Freeze the Phase-7 gain for the synthetic fixture (GREEN) | `577f8e4` | fix |
| 2 | ArmStatistics tests (RED) | `5ca22c1` | test |
| 2 | Realized gain and smoothing (GREEN) | `ec64639` | feat |
| 3 | CortexReplayBench, the four-arm real-data ablation | `855aac1` | feat |
| - | The carried-in `ClosedLoopPipelineTests` repair | `95c73c7` | test |

## Task 1: the freeze, and the proof it is the real Phase-7 gain

Both red gates are green. Neither committed fixture was touched:
`git diff bab1a4e..HEAD --stat` over `refit_bps.json` and `webgrid_bps.json` is empty.

`Decoder/scripts/fit_kalman_gain.py`'s `render_swift` now calls `default_noise(fit.seed)`
unconditionally and runs the same `steady_state_gain` on it, so `phase7BaselineK` is GENERATED in
every run rather than transcribed. The provenance header gains one line naming which of the two
gains ships.

**The load-bearing check, executed rather than argued.** The emitted `phase7BaselineK` is
byte-identical to the `K` committed at `5202a96`, the original Phase-7 constants commit:

```
SIMD2<Float>(0.0392099203499935, 0.0)
SIMD2<Float>(0.0, 0.03920992034999153)
SIMD2<Float>(0.039207960001001047, 0.0)
SIMD2<Float>(0.0, 0.03920796000099885)
```

So the frozen constant is the Phase-7 gain, not a plausible-looking substitute.

`KalmanFilter.init()` became a `convenience init` forwarding to a new `public init(gain:)`. There is
now exactly one unpacking implementation, which `KalmanFilterTests` Test 6 pins by driving both
inits over an identical 64-tick sequence and requiring bit-equal output and bit-equal state at every
tick. Test 7 requires the frozen gain to drive the filter DIFFERENTLY from the shipped one, so the
freeze cannot become load-free by coincidence. Neither test asserts a direction or a magnitude.

Both `KalmanFilter()` sites in `CortexReFITBench` now take `KalmanConstants.phase7BaselineK`
(`grep -cF 'KalmanFilter()'` returns 0). The `Arm` enum, `RefitBPS`, `WebgridBPSReport`, the reach
sequence and both JSON writers are untouched.

### The `CORTEX_REFIT_REPLAY_URL` decoy: option (ii), fail loudly

The hook is KEPT and a present path now `exit(1)`s, naming `CortexReplayBench` as the real-data
entry point. Measured: `CORTEX_REFIT_REPLAY_URL=<a real export> CortexReFITBench` exits **1**.

Option (ii) over option (i) because deleting the hook would remove the discoverability an operator
who sets it clearly wants, while the defect was never the hook itself: it was that a present path
set `source = "indy-replay (...) + seed-locked synthetic perturbation"` and then ran the synthetic
reaches anyway. There has never been a loader behind it. The string
`seed-locked synthetic perturbation` now survives only inside the comment that records what was
removed; no branch reachable with a real path produces it. The `--smoke` path is untouched, which is
why the bytes hold.

### The byte-identity proof, executed

| Command | Result |
|---|---|
| `rm -rf Packages/CortexReFIT/.bench && CortexReFITBench --smoke` | exit **0** |
| `diff .bench/refit_bps.json .planning/phases/07-*/refit_bps.json` | **empty**, exit 0 |
| `diff .bench/webgrid_bps.json .planning/phases/08-*/webgrid_bps.json` | **empty**, exit 0 |
| `python3 Tools/scripts/check_refit_uplift.py .planning/phases/07-*/refit_bps.json` | exit **0** |
| `./Tools/scripts/bps-policy.sh` | exit **0** |
| `./Tools/scripts/bps-policy.sh --self-test` | exit **0** |
| `git diff --stat` on both committed fixtures | **empty** (neither was re-issued) |

The regenerated `--smoke` output reproduces the Phase-7/8 numbers exactly: `refit_bps`
0.37439506338290895, `kalman_only_bps` 0.15545586433053596, `raw_bps` 0.16089860247386525,
`refit_webgrid_bps` 1.953047883714651, Sc 103, t 517.56 s.

**The synthetic 8.0047 guard rail holds: that number appears in no artifact this plan produced.** It
was what the re-fit gain produced on the SYNTHETIC seeded fixture, whose heading is target-determined
and whose incorrect selections are structurally zero, so its proximity to the 8.5 reference is
coincidence and it must never be quoted as progress. Freezing the fixture's gain removed it.

## Task 2: the Willett confound, measured

`ArmStatistics` is a stateless namespace beside `WebgridBPS`. `realizedGain` is the ratio of MEAN
SPEEDS, not the mean of per-tick ratios: the latter is undefined on every tick the decoder emitted a
tiny velocity, which on a shrinkage-heavy real decode is many of them, and averaging those would be
dominated by the ticks with the smallest denominator. `realizedSmoothing` is the lag-1
autocorrelation of the output speed series.

Every division is guarded and every return is `.isFinite`-checked. 12 tests cover the degenerate
shapes a floored real-data arm actually produces: empty input, an all-zero denominator, a constant
series with zero variance, a single sample, and a series containing the zero vector. The source
carries the review D-9 scope limit in writing (`CALIBRATION` appears; `near-zero` does not), and
none of the four unverified `10-RESEARCH-INPUTS` Finding-4 candidates is cited.

## Task 3: `CortexReplayBench`, and what it measured

A separate executable, per RESEARCH Pitfall 6 and D-09. `git diff --stat Packages/CortexReFIT/` for
this task is empty.

The decode runs ONCE into a shared array before the arm loop (T-10-05-04), one tick per 20 ms bin on
the trailing 32-bin window ending at that bin. The reversed-target site carries the vacuous-control
trap verbatim plus the review D-9 limit. `grep -nE '(passed|verdict|PASS|FAIL)\s*='` returns
nothing.

The emitted JSON's top-level key set matches 10-PREREGISTRATION section 11 **exactly** (checked
programmatically: 0 missing, 0 extra). Arm entries carry all 10 pre-registered fields plus
`bps_n900_label` and `bps_n64_label` (required by section 6), `distance_to_target_mm` (required by
this plan), and `incorrect_model` (the structural-Si disclosure). No float in the file is
non-finite.

### The run, recorded as an execution observation and NOT as published evidence

Plan 10-07's evidence artifact is where a number from this bench gets published with a runbook and a
reading. This is the first run of the code, reported here so the next plan knows what it produces.

Machine: **Apple M5 Pro**, macOS 26.5 (25F71) arm64, Swift 6.2.4. Release build, 11.8 s wall.

```
./Packages/CortexDemo/.build/release/CortexReplayBench \
  --export Decoder/exports/indy_20160630_01.replay.json \
  --model  Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage
```

Session `indy_20160630_01`, sidecar sha256 `a452ed69...6dec4e3` (matches 10-03a). 73,160 bins,
**73,129 decoded ticks, 0 decode fallbacks**, 1,025 trials segmented on target changes (the sidecar
records 1,025). Workspace `cursor_bbox_square`, `side_mm` 171.68196243849025, `acq_radius_mm`
2.8613660406415042. Dwell 0.30 s, timeout 5.0 s, r_acq 0.5/30, none relaxed.

| Arm | rotation target | hits | seconds | bps_n900 | bps_n64 | fitts_tp | realized_gain | realized_smoothing | dist_mm p1/p5/p25/p50/p90 |
|---|---|---|---|---|---|---|---|---|---|
| `raw` | none | 0 | 1440.26 | 0.000000 | 0.000000 | 0.356340 | 1.000000 | 0.599023 | 16.58 / 35.98 / 69.66 / 97.98 / 144.38 |
| `kalman_only` | none | 0 | 1440.26 | 0.000000 | 0.000000 | 0.355569 | 0.923581 | 0.942937 | 16.62 / 35.72 / 69.38 / 97.79 / 144.21 |
| `refit` | true_track | 70 | 1407.76 | 0.487984 | 0.298346 | 0.672882 | 0.909801 | 0.923848 | 0.83 / 1.78 / 3.47 / 24.11 / 72.74 |
| `refit_reversed_target` | reversed_track | 2 | 1439.46 | 0.013635 | 0.008336 | 0.347855 | 0.884194 | 0.900134 | 3.91 / 14.48 / 35.16 / 53.58 / 90.15 |

| Delta | bps_n900 | bps_n64 | fitts_tp |
|---|---|---|---|
| `refit_minus_kalman_only` (the attributable number) | 0.487984 | 0.298346 | 0.317314 |
| `refit_minus_raw` (conflates gain and smoothing) | 0.487984 | 0.298346 | 0.316543 |
| `refit_minus_reversed` (the attribution control) | 0.474349 | 0.290010 | 0.325028 |

**Five things the evidence artifact must carry, learned from running it.**

1. **The two arms attributable to the decode both scored ZERO hits.** `raw` and `kalman_only` never
   see a target, and 10-PREREGISTRATION section 7 states in advance that they "are the only arms
   whose rate is attributable to the decode". Both are 0 of 1,025 trials at the pre-registered
   geometry. That is the honest headline of this run, and section 15 named a floored count as the
   expected outcome before it existed.
2. **The 70 hits on `refit` are not a decoding result.** `IntentRotation.rotate` returns
   `(speed / dist) * d`: it replaces the decoded direction with the direction to the known target and
   keeps only the decoded speed. Both target-seeing arms are target-determined by construction; only
   the target differs. The reversed-target arm collapsing to 2 hits says the rotation needs the
   correct target to help. It says nothing about how much intent the decode carried.
3. **`refit_minus_raw` equals `refit_minus_kalman_only` on both BPS normalisations** because raw and
   kalman_only are both exactly 0. The usual concern (the headline delta being inflated by the
   Kalman's gain and smoothing) cannot arise on this run, and the reason should be stated rather
   than the coincidence quoted.
4. **`raw`'s `realized_gain` is exactly 1.0 by construction**, since the raw arm's output IS its
   input. It is not a measurement and must not be read as one. The informative comparison is
   `kalman_only` 0.9236 against `refit` 0.9098 against `reversed` 0.8842: the gain is within about 4
   percent across the three filtered arms, so the Willett confound is not what separates them here.
   The smoothing figures (0.5990, 0.9429, 0.9238, 0.9001) show the Kalman is what smooths, not the
   rotation.
5. **This plan does NOT adjudicate SC#2.** Section 15's disposition table is keyed to
   `10-replay.json` and RD-08, which is Plans 10-06 and 10-09. The `refit` arm's non-zero hit count
   is recorded here as an observation; whether it satisfies a criterion, given point 2, is a
   question for those plans and, per section 15 rule 2, not for an executor.

## The authorized carried-in repair

`ClosedLoopPipelineTests` Test 2 asserted that NDT1 genuinely ran in the loop while building the
pipeline with the default 8-bin `SyntheticSpikeSource` against a model whose `spikes` input is
`(1, 96, 1, 32)`. The buffer is rejected on every tick and the pipeline falls back, so the case
could never pass under the condition it was written for. It looked green only because it returns
early when `CORTEX_MODEL_URL` is unset.

The fix is the source's window length: the pipeline is built at `RecordedSpikeSource.modelSeqLen`.
The assertion is unchanged and not weakened, and the case is not deleted. One line of behavior
change, plus a comment recording why. **It is a test change, not an implementation change**, so it
stayed inside the authorized scope.

**Both directions were reproduced in this worktree rather than inherited from 10-04's note.** With
the shipped fp16 model wired, `git checkout`-ing the file back to its pre-repair state and running
`--filter modelBackedDecodePathPresent` fails at `ClosedLoopPipelineTests.swift:71` with
`Expectation failed: anyModelTick`; restoring the repair makes it pass. Committed separately as
`95c73c7`.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 3 - Blocking] The plan's per-trial cursor seed does not exist in the export**

- **Found during:** Task 3, writing the arm loop.
- **Issue:** the plan says each arm uses "a per-trial `CursorIntegrator` started at the trial's first
  true cursor position". The D-06 export's 424-byte record holds 96 spike counts, a 2-vector
  velocity, a 2-vector target and a bin start; the sidecar's `units` names `spikes`, `t_start`,
  `target` and `velocity`. There is **no recorded cursor track**. Reconstructing one by integrating
  the true velocity over 73,160 bins would accumulate drift and would not be the recorded cursor.
- **Fix:** ONE `CursorIntegrator` per arm, carried across the whole replay, started at the grid
  centre and never reset. A continuous cursor is also what the recorded task had: the targets
  change, the cursor does not teleport. Each trial's Fitts start is the integrator's position at
  that trial's first tick, so the movement axis is still per-trial.
- **Why not the alternative:** resetting per trial to a position we do not have would fabricate
  cursor behavior, which is the same defect class 10-03a's containment argument exists to prevent.
- **Files:** `Packages/CortexDemo/Sources/CortexReplayBench/main.swift`
- **Committed in:** `855aac1`

**2. [Rule 1 - Bug] Non-overlapping decode windows would have destroyed the dwell semantics**

- **Found during:** Task 3.
- **Issue:** `RecordedSpikeSource.window(i)` returns the export's bins `[i*32 ..< (i+1)*32]`, which
  is correct for Plan 10-04's latency bench (it needs distinct windows to time) but advances the
  session clock 640 ms per tick. At `dt = 0.64`, `WebgridAcquisition.dwellTicks` is
  `ceil(0.30/0.64) = 1`, so a single in-radius sample would commit a selection. The pre-registered
  0.30 s continuous dwell would have been silently gone, and the hit counts would have been
  meaningless.
- **Fix:** the bench decodes one tick per 20 ms bin on the trailing 32-bin window ending at that
  bin, via `ReplayExport.window(endingAt:length:)`. That is `RecordedSpikeSource`'s own documented
  alignment ("row i pairs the spike window ENDING at bin i") applied at every bin, and it is the
  cadence `KalmanConstants.dt`, `WebgridAcquisition(dt: 0.020)` and the Phase-7 harness all assume.
  `RecordedSpikeSource.modelSeqLen` is still the one home for the 32.
- **Cost:** 73,129 CoreML predictions instead of 2,286. Measured at 11.8 s wall in a release build.
- **Files:** `Packages/CortexDemo/Sources/CortexReplayBench/main.swift`
- **Committed in:** `855aac1`

**3. [Rule 3 - Blocking] Top-level `let`s in `main.swift` are MainActor-isolated**

- **Found during:** Task 3, first build.
- **Issue:** `CortexDemo` sets `.defaultIsolation(MainActor.self)` and top-level code in a
  `main.swift` runs on the MainActor, but a global `func` in the same file is nonisolated, so
  `runArm`, `report(for:)` and `armReport` could not read `decoded`, `trials`, `trueTargets`,
  `reversedTargets` or `runs`.
- **Fix:** those three functions are marked `@MainActor`. No data was moved and no isolation was
  relaxed.
- **Files:** `Packages/CortexDemo/Sources/CortexReplayBench/main.swift`
- **Committed in:** `855aac1`

**4. [Rule 2 - Missing critical] The `bps_*_label` siblings the plan did not list**

- **Found during:** Task 3, checking the emitted schema against the pre-registration.
- **Issue:** the plan's per-arm output list names `bps_n900` and `bps_n64` but not their labels.
  10-PREREGISTRATION section 6 requires in writing that "Both JSON keys carry a sibling `*_label`
  string holding the same text, so the label cannot be dropped by a prose edit."
- **Fix:** `bps_n900_label` and `bps_n64_label` carry the pre-registered strings verbatim, from two
  file-level `let`s so the two places they are emitted cannot diverge.
- **Files:** `Packages/CortexDemo/Sources/CortexReplayBench/main.swift`
- **Committed in:** `855aac1`

**Total: 4 auto-fixed (2 blocking, 1 bug, 1 missing-critical). No Rule 4 escalation.** Deviation 1
was the only one that came close, and it is a measurement-convention choice inside a pre-registered
frame rather than an architectural one: the pre-registration fixes the geometry, the dwell and the
scoring, and says nothing about where the cursor starts, because the box it registered has no cursor
track in it.

### Formatting note

`swiftformat` was run on every file this plan created. `ArmStatistics.swift`,
`ArmStatisticsTests.swift`, `CortexReplayBench/main.swift`, `KalmanConstants.swift`,
`KalmanFilter.swift` and `ClosedLoopPipelineTests.swift` are all `--lint` clean (the two test files
with `--disable swiftTestingTestCaseNames`, which fires identically on the pre-existing suite).

`CortexReFITBench/main.swift` is **not** `swiftformat --lint` clean and never has been. It carried
35 violations at `bab1a4e` and carries 32 after this plan, in exactly the same eight rule classes
(`wrap` 18, `docComments` 4, `conditionalAssignment` 7 to 4, `numberFormatting` 2, plus one each of
`preferKeyPath`, `preferCountWhere`, `unusedArguments`, `wrapSingleLineComments`). The count fell
because this plan removed the `let source: String` if/else. No new violation and no new rule class
was introduced. The repo-wide `--strict` sweep is D-18 work in a later plan; conforming this one
file now would be an out-of-scope reformat that buries the lines that matter.

### Deliberately not done

- **`10-refit-real.json` was not committed to the phase directory.** The bench writes to the
  gitignored `.bench/refit_real.json`. Plan 10-07 owns the committed artifact and its evidence file.
- **`10-ceiling.json`'s 147 of 1,025 is not restated in the bench source.** The bench prints a
  pointer to the file by name instead, so a published reference number has one home and cannot drift
  into a second copy.
- **`RecordedSpikeSource` was not changed.** Its non-overlapping windows are correct for Seam A; the
  ablation reaches the sliding window through `ReplayExport` directly rather than altering a type
  Plan 10-06 depends on.
- **STATE.md and ROADMAP.md were not updated**, per the task.

## Known Stubs

Two zero-valued fallbacks exist in `CortexReplayBench`. Neither is reachable, and each is unreachable
by construction rather than by convention.

| File | Fallback | Why it cannot fire |
|---|---|---|
| `CortexReplayBench/main.swift` | `(try? export.target(at: bin)) ?? SIMD2<Double>(0, 0)` | `bin` runs over `[31, binCount - 1]`, which `ReplayExport.checkBounds` accepts for any export that passed `init` (which refuses `n_bins <= 0`), and the loop is not entered at all unless `binCount > 31` |
| `CortexReplayBench/main.swift` | the same for the reversed index `binCount - 1 - bin` | that index runs over `[0, binCount - 32]`, a strict subset of the valid range |

The decode path has NO fallback on purpose: a failure increments `decodeFailures`, and the run
aborts on a `precondition` before any statistic is computed (10-PREREGISTRATION section 10). The
measured run had 0 of 73,129.

No placeholder text, no hardcoded empty collection and no unwired component was introduced.

## Verification

Every command run in this worktree on **Apple M5 Pro**, macOS 26.5 (25F71) arm64, Swift 6.2.4,
swiftformat 0.61.1, python 3.12 under `uv`.

| Command | Result |
|---|---|
| `swift test --package-path Packages/CortexReFIT` | **32 tests in 5 suites passed** (28 pre-existing + 4 new) |
| `swift test --package-path Packages/CortexDemo` | **33 tests in 4 suites passed** (21 pre-existing + 12 new) |
| `swift test --package-path Packages/CortexDemo` with `CORTEX_MODEL_URL` set | **33 tests in 4 suites passed** (was 1 failure before the carried-in repair) |
| `swift test --package-path Packages/CortexCore` | **15 tests in 1 suite passed** |
| `CortexReFITBench --smoke` then `diff` vs the committed `refit_bps.json` | **empty diff**, exit 0 |
| `diff .bench/webgrid_bps.json` vs the committed `webgrid_bps.json` | **empty diff**, exit 0 |
| `python3 Tools/scripts/check_refit_uplift.py <committed refit_bps.json>` | exit **0** |
| `./Tools/scripts/bps-policy.sh` | exit **0** |
| `./Tools/scripts/bps-policy.sh --self-test` | exit **0** |
| `./Tools/scripts/hotpath-policy.sh` | exit **0** |
| `./Tools/scripts/hotpath-policy.sh --self-test` | exit **0** |
| `./Tools/scripts/decoder-policy.sh` | exit **0** |
| `./Tools/scripts/render-policy.sh` | exit **0** |
| `uv run --project Decoder ruff check Decoder` | **exit 0**, all checks passed |
| `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` | **273 passed**, 10 deselected |
| `swift run ... CortexReplayBench` with no inputs | names both missing, **exit 0** |
| `CortexReplayBench --export ... --model ...` | 73,129 ticks, 0 fallbacks, **exit 0**, 11.8 s |
| `CortexReplayBench` run twice, `diff` of `refit_real.json` | **byte-identical** |
| `CORTEX_REFIT_REPLAY_URL=<real export> CortexReFITBench` | **exit 1**, names `CortexReplayBench` |
| `git diff bab1a4e..HEAD --stat` on both committed fixtures | **empty** |
| `git status --short` | clean; nothing from `Decoder/{data,exports,checkpoints}` or `.bench/` |

### Acceptance greps

| Check | Result |
|---|---|
| `grep -cF 'phase7BaselineK' KalmanConstants.swift` | 2 |
| `grep -cF 'phase7BaselineK' fit_kalman_gain.py` | 3 |
| `grep -cF 'KalmanFilter()' CortexReFITBench/main.swift` | **0** |
| `grep -cF 'KalmanFilter(gain: KalmanConstants.phase7BaselineK)'` | 2 |
| `grep -cF 'public init(gain' KalmanFilter.swift` | 1 |
| `grep -cF 'noise source = indy-heldout' KalmanConstants.swift` | 1 |
| `grep -cF 'struct RefitBPS' CortexReFITBench/main.swift` | 1, unchanged inside |
| `grep -c '@Test' ArmStatisticsTests.swift` | 12 (>= 8) |
| `grep -cF '10.1109/TBME.2017.2783358' ArmStatistics.swift` | 1 |
| `grep -cF 'isFinite' ArmStatistics.swift` | 4 |
| `grep -cE 'pmc\.ncbi\|s41598-019-44166-7\|pcbi\.1004948\|PMC3638090\|PMC4105020'` | **0** |
| `grep -cF 'CALIBRATION' ArmStatistics.swift` / `grep -icF 'near-zero'` | 1 / **0** |
| `grep -cF 'CortexReplayBench' Packages/CortexDemo/Package.swift` | 2 (products and targets) |
| `grep -cF 'refit_reversed_target'` / `'rotation_target_source'` in the bench | 4 / 3 |
| `grep -cF 'bitsPerSecond'` in the bench | 2 (dual-N) |
| `grep -cF 'realizedGain'` / `'realizedSmoothing'` / `'CursorIntegrator'` / `'runTrial'` | 1 / 1 / 2 / 3 |
| `grep -n '4.16'` in the bench | 2 lines, both carrying `DENSE` and `9x9` |
| `grep -nE '(passed\|verdict\|PASS\|FAIL)\s*='` in the bench | **nothing** (D-09) |
| `grep -cE 'precondition\('` in the bench | 1, naming the decode-fallback count |
| `git diff --stat Packages/CortexReFIT/` for Task 3 | **empty** |

### Artifact minimums

| Artifact | Lines | Required |
|---|---|---|
| `CortexReplayBench/main.swift` | 738 | >= 300 |
| `ArmStatistics.swift` | 104 | >= 60 |

### What was NOT run, and why

- **The 10 `slow` Decoder tests** (CoreML conversion, palettization, held-out co-bps, and the Kalman
  residual fit) were not run. This plan changed exactly one Python function, `render_swift`, which is
  string rendering downstream of the fit; the fit itself, `fit_noise`, `steady_state_gain` and every
  input to them are untouched. The generator WAS re-run end to end against the real data, which
  exercises the whole fit path once, and the shipped `K` in the regenerated file is unchanged from
  what 10-03a committed.
- **`readme-policy.sh` and `honesty-sweep.sh`** were not run. This plan publishes no prose artifact
  and touches neither the README nor `docs/cortex-spec.md`; those gates are Plans 10-12 and 10-14.
- **The repo-wide `swiftformat --strict` / SwiftLint sweep** was not run. It is D-18 work in a later
  plan and would be an out-of-scope reformat here. The per-file state is recorded above.
- **No iPad-M4 or device measurement** was taken. Every number in this summary is an M5 Pro number
  and is labeled `corroborating` in the emitted JSON.

## Notes for later plans

- **10-06 and 10-09:** the `CortexDemo` suite is green with `CORTEX_MODEL_URL` set. The
  `ClosedLoopPipelineTests` red they were warned about is repaired in `95c73c7`.
- **10-07:** the artifact to publish is `Packages/CortexDemo/.bench/refit_real.json`. The five
  points under "The run" all belong in the evidence artifact, particularly point 1 (both
  decode-attributable arms are zero) and point 2 (the 70 hits are target-determined). The
  pre-registration's section 7 paragraph on what the control cannot establish is already verbatim in
  the bench source and should be quoted, not paraphrased.
- **10-09:** the schema test can bind to the exact section-11 top-level key set; it matches with 0
  missing and 0 extra today. `export_sidecar_sha256` is computed from the bytes actually read.
- **10-11:** `WebgridBPS.swift`'s doc comment is untouched here, so the long-form non-comparability
  disclosure is still that plan's to add.
- **Anyone re-running the ablation:** use a release build. Debug is roughly two orders of magnitude
  slower on the 224 million `SpikeInputBuffer.write` calls. `Decoder/{data,exports,checkpoints}` must
  be real directories holding symlinks, never bare symlinks, or `git status` goes dirty.

## Self-Check: PASSED

Files claimed as created, all confirmed present on disk:
`Packages/CortexDemo/Sources/CortexDemo/ArmStatistics.swift`,
`Packages/CortexDemo/Tests/CortexDemoTests/ArmStatisticsTests.swift`,
`Packages/CortexDemo/Sources/CortexReplayBench/main.swift`.

Files claimed as modified, all confirmed changed in the commits below:
`Decoder/scripts/fit_kalman_gain.py`, `KalmanConstants.swift`, `KalmanFilter.swift`,
`CortexReFITBench/main.swift`, `KalmanConstantsTests.swift`, `KalmanFilterTests.swift`,
`Packages/CortexDemo/Package.swift`, `ClosedLoopPipelineTests.swift`.

Commits claimed, all resolving as commit objects on top of the expected base
`4f074449567b2e1aa4642bbc59106df059918228`: `2589a12`, `577f8e4`, `5ca22c1`, `ec64639`, `855aac1`,
`95c73c7`.

The three load-bearing claims were executed, not asserted: the regenerated `phase7BaselineK` was
byte-compared against the `K` committed at `5202a96` and matches; `CortexReFITBench --smoke` produces
a `refit_bps.json` and a `webgrid_bps.json` that both `diff` clean against the committed copies with
neither committed file modified; and the carried-in test repair was reproduced in BOTH directions in
this worktree with the shipped model wired.

*Phase: 10-v1-real-data-closed-loop-launch*
*Completed: 2026-09-05*
