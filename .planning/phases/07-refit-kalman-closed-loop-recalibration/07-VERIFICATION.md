---
phase: 07-refit-kalman-closed-loop-recalibration
verified: 2026-06-22T21:35:00Z
status: passed
score: 6/6 must-haves verified
human_verification:
  - test: "Filter-step tail latency on iPad-Pro-M4 (canonical device)"
    expected: "p99 < 2ms on the M4 Neural Engine / CPU-only path at 50 Hz decode cadence"
    why_human: "Hardware device checkpoint — CI runner cannot provision an iPad-Pro-M4. Documented Manual-Only deferral per 07-VALIDATION.md; not an automated-coverage gap."
---

# Phase 7: ReFIT-Kalman Closed-Loop Recalibration — Verification Report

**Phase Goal:** Swift-side 6-DOF Kalman with per-update intent-rotation step delivering BPS uplift over raw NDT1.
**Verified:** 2026-06-22T21:35:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `KalmanFilter.swift` implements predict → external position-sync (BEFORE rotation) → rotate measurement → constant-gain update → emit; constants-only (no runtime Riccati) | VERIFIED | Source confirmed: `setCursorPosition` syncs before `rotation.rotate`, then constant-gain update via six `simd_dot` rows. No Riccati at runtime — A/H/K captured from `KalmanConstants` at `init`. `@inline(__always)` step. |
| 2 | `KalmanConstants.swift` K has zero position rows (rows 0,1); gain solved on observable [vx,vy,ax,ay] block; Schur-stable closed loop | VERIFIED | Source confirmed: `K[0] = SIMD2(0,0)`, `K[1] = SIMD2(0,0)`, rows 2–5 non-zero. `kalman_gain.py` calls `steady_state_gain` → `observable_gain` → `solve_discrete_are(a_obs.T, h_obs.T, ...)` dual substitution; asserts `max|λ| < 1.0` before returning. Python tests: 9/9 passed. |
| 3 | `IntentRotation.swift` aligns direction fully onto cursor→target, preserves magnitude, gated off inside r_acq / no-target / zero-velocity | VERIFIED | Source confirmed: 4 guard branches — (1) `guard let target` passthrough, (2) `guard dist > r_acq, speed > Self.epsilon` passthrough, (3) speed-preserving align `(speed / dist) * d`. All 4 branches (no-target, inside-r_acq, zero-vel, outside-r_acq) covered by `IntentRotationTests`. Swift test suite: 21/21 passed. |
| 4 | Headless deterministic 3-way ablation (`CortexReFITBench --smoke`) yields `refit_bps >= raw_bps` on fixed seed; `refit_bps.json` byte-identical across runs; S&M-2004 We=4.133·SDx mean-of-means | VERIFIED | Gate run: refit_bps=0.374 >= raw_bps=0.161 (delta=+0.213, +133%). Bench output byte-identical to committed JSON. S&M-2004 formula confirmed in `FittsThroughput.swift`: `effectiveWidthConstant = 4.133`, `conditionThroughput` + `meanOfMeans`. |
| 5 | `IntentRotation`/`KalmanFilter` Foundation-free `import simd` (policed by `hotpath-policy.sh`); filter-step latency bench n≥10,000 ticks inline (no new thread), device-annotated | VERIFIED | `hotpath-policy.sh` exit 0 (scanned `Packages/CortexReFIT/Sources/CortexReFIT`; no forbidden tokens). `--self-test` exit 0 (all 12 negative controls bite). `main.swift` latency bench: 10,000 ticks inline on calling thread, `LatencyHistogram(deviceAnnotation: "M5-Pro-CPU-corroborating")`. |
| 6 | `07-bps-evidence.md` names S&M-2004 Fitts throughput, states MUST NOT compare to 4.16/8.5 (Phase-8/D-13 deferral), carries ReFIT-inspired honesty framing | VERIFIED | File confirmed: metric disclaimer present ("Soukoreff & MacKenzie 2004 ISO 9241-9 Fitts throughput"), explicit "MUST NOT be compared to 4.16 / 8.5", ReFIT-inspired framing ("NOT a live-human two-stage ReFIT retrain"), 3-way ablation table with all three arms. |

**Score:** 6/6 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Decoder/src/ndt1/kalman_gain.py` | Observable-block DARE: `solve_discrete_are(a_obs.T, h_obs.T, ...)`, zero position rows, Schur-stability assertion | VERIFIED | `steady_state_gain` → `observable_gain` → dual-substitution DARE → spectral radius check → `gain[2:6,:]=k_obs`, rows 0,1 exactly zero. |
| `Decoder/scripts/fit_kalman_gain.py` | Emit `KalmanConstants.swift`; default Q/R when data absent; seeded deterministic | VERIFIED | `render_swift` writes Foundation-free SIMD8 layout to the CortexReFIT package path. Default Q/R path documented; `np.random.seed(args.seed)`. |
| `Decoder/tests/test_kalman_gain.py` | 9 tests incl. full-6×6-raises negative control, position-rows-zero, Schur-stable, ≥50-tick trajectory | VERIFIED | 9/9 passed. Tests: `test_full_6x6_dare_raises_negative_control`, `test_position_rows_are_zero`, `test_closed_loop_is_schur_stable`, `test_multistep_trajectory_propagates_without_divergence`, plus 5 structural/shape tests. |
| `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift` | `import simd` only, `nonisolated enum`, zero position rows in K | VERIFIED | `import simd` (no Foundation). `public nonisolated enum KalmanConstants`. `K[0]=SIMD2(0,0)`, `K[1]=SIMD2(0,0)`. |
| `Packages/CortexReFIT/Sources/CortexReFIT/KalmanFilter.swift` | predict → sync → rotate → update → emit ordering; `nonisolated final class`; Foundation-free; zero-allocation | VERIFIED | `nonisolated final class KalmanFilter`. `import simd` only. Step ordering confirmed in source. SIMD8 state, K rows as SIMD2. `@inline(__always)`. |
| `Packages/CortexReFIT/Sources/CortexReFIT/IntentRotation.swift` | 4 gating branches; magnitude preserved; `import simd` only; `nonisolated struct` | VERIFIED | `public nonisolated struct IntentRotation: Sendable`. `import simd`. All 4 branches present: no-target guard, r_acq guard, speed guard, rotating branch. `(speed / dist) * d` preserves magnitude. |
| `Packages/CortexReFIT/Sources/CortexReFIT/FittsThroughput.swift` | S&M-2004 We=4.133·SDx, IDe=log2(De/We+1), TP=IDe/MT, mean-of-means; `import simd`; Foundation-free | VERIFIED | `effectiveWidthConstant = 4.133`. `indexOfDifficulty`, `throughput`, `meanOfMeans`, `conditionThroughput` all present. `import simd` only. |
| `Packages/CortexReFIT/Sources/CortexReFIT/WebgridAcquisition.swift` | Dwell-to-select, per-trial timeout, deterministic (no clock/RNG) | VERIFIED | `runTrial(positions:target:)` is a pure function of inputs. Continuous dwell counter. Timeout via `timeoutTicks`. `import simd` only. |
| `Packages/CortexReFIT/Sources/CortexReFITBench/main.swift` | 3-way ablation; seed-locked (SplitMix64, no clock/RNG in simulation path); all trials retained (no survivorship bias); warm filter across reaches; S&M mean-of-means | VERIFIED | `unitHash` SplitMix64 finalizer. All three arms use identical `reaches`. Filter warm-carried in `runArm`. `simulateReach` returns all trials (acquired and timeout). `FittsThroughput.meanOfMeans`. ContinuousClock used only in `--latency` mode (not BPS simulation). |
| `.planning/phases/07-refit-kalman-closed-loop-recalibration/refit_bps.json` | refit_bps >= raw_bps; correct keys; S&M-2004 metric label | VERIFIED | `refit_bps=0.374 >= raw_bps=0.161`. All 7 required keys present. `metric` field explicitly names S&M-2004 and "NOT the Webgrid bitrate". Byte-identical to bench output on re-run. |
| `.planning/phases/07-refit-kalman-closed-loop-recalibration/07-bps-evidence.md` | S&M-2004 metric naming; no-compare-to-4.16/8.5 disclaimer; ReFIT-inspired honesty framing | VERIFIED | All three elements present. |
| `Tools/scripts/check_refit_uplift.py` | Exit 0 when refit_bps >= raw_bps; exit 1 on regression; no bare except | VERIFIED | Specific exception types caught (`json.JSONDecodeError`, `OSError`, `TypeError`, `ValueError`). Exit 0 on committed JSON. |
| `Tools/scripts/hotpath-policy.sh` | `DIRS_ARRAY` includes `Packages/CortexReFIT/Sources/CortexReFIT` | VERIFIED | Line 79: `"Packages/CortexReFIT/Sources/CortexReFIT"` present in default `DIRS_ARRAY`. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `fit_kalman_gain.py` | `KalmanConstants.swift` | `render_swift` → `args.out.write_text` | VERIFIED | Target path hardcoded to `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift`. |
| `KalmanFilter.step` | `IntentRotation.rotate` | `private let rotation = IntentRotation()` stored in `KalmanFilter`; called inside `step` | VERIFIED | `rotation.rotate(measurement:cursor:target:acquisitionRadius:)` called after position sync, before update. |
| `kalman_gain.py` observable-block DARE | `KalmanConstants.K` zero position rows | `steady_state_gain`: `gain[2:6,:]=k_obs`, rows 0,1 zero | VERIFIED | Code path confirmed; Python tests assert `np.allclose(gain[0:2,:], 0.0)` — 9 passed. |
| `CortexReFITBench` | `refit_bps.json` (committed) | `writeJSON` to `.bench/refit_bps.json`; CI `diff -q` against committed | VERIFIED | Byte-identity confirmed by local `diff` run. CI step reproduces and diffs. |
| `check_refit_uplift.py` | `refit_bps.json` | reads and asserts `refit_bps >= raw_bps` | VERIFIED | Exit 0 on current committed file. CI step calls it as layer (2) of the uplift guard. |
| `hotpath-policy.sh` | `Packages/CortexReFIT/Sources/CortexReFIT` | `DIRS_ARRAY` default includes the path; scanned every CI run | VERIFIED | `hotpath-policy.sh` scan confirmed clean. Self-test confirms gate bites on all 5 Swift/C + 5 Rust tokens. |
| `ci.yml` | `CortexReFIT` | `swift test --package-path Packages/CortexReFIT` step; `ReFIT BPS uplift + determinism guard` step | VERIFIED | Both steps present in `ci.yml` lines 291–318. CortexReFIT included in per-package build loop (line 136). |

---

### Data-Flow Trace (Level 4)

Not applicable — this phase produces no data-rendering React/Vue/Svelte/UI components. The CortexReFITBench is a headless CLI harness; data-flow is verified by gate runs (bench output byte-identical to committed JSON) and the `check_refit_uplift.py` guard.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 21 Swift tests across 4 suites (REFIT-01/02/03) all pass | `swift test --package-path Packages/CortexReFIT` | 21/21 passed in 4 suites | PASS |
| 9 Python Kalman gain tests pass (incl. full-6×6 negative control) | `uv run --project Decoder --extra dev pytest Decoder/tests/test_kalman_gain.py -q` | 9 passed | PASS |
| hotpath-policy.sh exits 0 (CortexReFIT dir clean) | `./Tools/scripts/hotpath-policy.sh` | OK: 3 dirs + 2 Rust files clean | PASS |
| hotpath-policy.sh --self-test exits 0 (all negative controls bite) | `./Tools/scripts/hotpath-policy.sh --self-test` | SELF-TEST OK: 12/12 assertions pass | PASS |
| CortexReFITBench --smoke exits 0; refit_bps >= raw_bps on fixed seed | `swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke` | refit=0.374 >= raw=0.161; delta=+0.213 | PASS |
| check_refit_uplift.py exits 0 on committed JSON | `python3 Tools/scripts/check_refit_uplift.py .planning/phases/.../refit_bps.json` | OK: uplift holds (seed=0xC0FFEE, n=120) | PASS |
| Bench output byte-identical to committed refit_bps.json | `diff Packages/CortexReFIT/.bench/refit_bps.json .planning/.../refit_bps.json` | BYTE-IDENTICAL | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| REFIT-01 | 07-01-PLAN, 07-02-PLAN | Steady-state constant-gain Kalman on observable [vx,vy,ax,ay] block; zero position rows in K; Schur-stable closed loop; Swift `import simd` hot-path step | SATISFIED | `kalman_gain.py` observable-block DARE (dual substitution confirmed); `KalmanConstants.swift` K rows 0,1=zero; `KalmanFilter.swift` nonisolated + Foundation-free. Python tests 9/9. Swift constants tests 6/6. Swift filter tests 5/5. |
| REFIT-02 | 07-02-PLAN | Intent-rotation: direction-align with magnitude preserved; 4 gating branches; rotation acts on measurement BEFORE Kalman update | SATISFIED | `IntentRotation.swift` all 4 branches confirmed in source. `KalmanFilter.step` ordering: sync → rotate → update (confirmed). Swift intent-rotation tests 5/5. |
| REFIT-03 | 07-03-PLAN | Headless deterministic 3-way ablation; S&M-2004 We=4.133·SDx mean-of-means; refit_bps >= raw_bps committed; CI guard; filter-step latency bench n≥10,000 inline | SATISFIED | Bench gate exit 0, refit=0.374 >= raw=0.161. Byte-identical determinism confirmed. `FittsThroughput.swift` S&M-2004 formula confirmed. Latency bench 10,000 ticks inline (no new thread). `07-bps-evidence.md` metric framing confirmed. |

Note: REQUIREMENTS.md shows REFIT-01/02/03 as `[ ]` (unchecked). This is a known GSD behavior — `gsd state phase-complete` skips REQUIREMENTS traceability post-execution. The requirements are covered by the three plans' `requirements-completed` fields and verified against the actual codebase above.

---

### Anti-Patterns Found

| File | Pattern | Severity | Assessment |
|------|---------|----------|------------|
| `Packages/CortexReFITBench/main.swift` line 37 | `import Foundation` | Info | Intentional and correct — bench is explicitly off the hot path; `Foundation` is needed for `JSONEncoder/.sortedKeys`, `FileManager`, `URL`. Comment in source documents this: "bench is OFF the hot path (allowed here)". Not policed by `hotpath-policy.sh` (which only scans `Sources/CortexReFIT`, not `Sources/CortexReFITBench`). |
| `fit_kalman_gain.py` line 182 | Indy data dir exists but residual extraction falls back to default Q/R | Info | Documented Known Stub — intentional follow-on per 07-03-SUMMARY.md and `deferred-items.md`. `fit_noise` prints an honest message and falls back rather than fabricating residuals. Not a REFIT-03 failure. |

No blockers or warnings found.

---

### Human Verification Required

#### 1. Filter-step tail latency on iPad-Pro-M4 (canonical device)

**Test:** Run `swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke --latency` on a physical iPad-Pro-M4 (or M4 Mac as close proxy). Record p50/p99/max from the printed `LatencyHistogram`.

**Expected:** p99 comfortably below the 2 ms decoder budget at 50 Hz cadence. The constant-gain step is approximately 12 `simd_dot` ops on SIMD8; expected p99 in the tens-of-nanoseconds range on M-series silicon.

**Why human:** Hardware device checkpoint — the CI runner is not an iPad-Pro-M4. The Mac/M5-Pro corroborating number (p50=250 ns, p99=292 ns per `07-bps-evidence.md`) is automated, but the canonical iPad-M4 tail number is a Manual-Only deferral documented in `07-VALIDATION.md`. This is a documented deferral, not a gap.

---

### Gaps Summary

No gaps. All automated coverage is green:
- 21/21 Swift tests across 4 suites
- 9/9 Python Kalman gain tests
- `hotpath-policy.sh` and `--self-test` both exit 0
- `CortexReFITBench --smoke` exit 0; refit_bps >= raw_bps; byte-identical to committed JSON
- `check_refit_uplift.py` exit 0

The one outstanding item (iPad-M4 tail latency) is a documented Manual-Only deferral in `07-VALIDATION.md`, not a gap.

---

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | Real Indy `.mat` replay loader (residual extraction for data-grounded Q/R fit) | Phase 8 / follow-on R&D | Documented in `07-03-SUMMARY.md` as "intentional follow-on (documented)". `fit_kalman_gain.py` falls back to seeded default and says so plainly. |

---

_Verified: 2026-06-22T21:35:00Z_
_Verifier: gsd-verifier_
