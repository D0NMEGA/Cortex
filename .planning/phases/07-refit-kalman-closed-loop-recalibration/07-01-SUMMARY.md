---
phase: 07-refit-kalman-closed-loop-recalibration
plan: 01
subsystem: decoder
tags: [kalman, scipy, solve_discrete_are, dare, simd, refit, swift-package, codegen, observability]

# Dependency graph
requires:
  - phase: 04-ndt1-training-on-indy-loco-synthetic-replay
    provides: "Decoder/ uv subsystem (numpy/scipy env, velocity_head ridge-fit house style, conftest seeded fixtures, Indy data loader)"
  - phase: 05-coreml-ane-deployment
    provides: "CortexDecoder.decode(_:) -> SIMD2<Float> (the (vx,vy) measurement the filter wraps), velocityDimension == 2"
  - phase: 06-cametaldisplaylink-120hz-renderer
    provides: "CursorVelocity / VelocityRing / CursorIntegrator velocity seam in CortexRender (the producer→consumer contract CortexReFIT depends on)"
provides:
  - "Decoder/src/ndt1/kalman_gain.py — observable 4-DOF DARE solver (scipy dual substitution), 6×2 zero-position-row steady-state gain, Schur-stability check"
  - "Decoder/scripts/fit_kalman_gain.py — Q/R fit (white-noise-jerk + decoder-residual) with seeded default fallback; emits KalmanConstants.swift (D-15 code-gen)"
  - "Packages/CortexReFIT — new Swift package (Package.swift, namespace enum, generated KalmanConstants.swift, structural-invariant tests) depending on CortexRender (D-14 keep-decision)"
  - "Committed steady-state matrices A (6×6), H (2×6), K (6×2 zero-position-rows), Qobs (4×4), R (2×2) as Foundation-free simd constants for Wave-2 to consume"
affects: [07-02-kalman-filter-intent-rotation, 07-03-bps-harness, wave-2-predict-update-step, plan-02-hotpath-policy-scope]

# Tech tracking
tech-stack:
  added: ["scipy>=1.11 (Decoder/ uv subsystem; resolved scipy 1.18.0, coremltools held at 9.0)"]
  patterns:
    - "Offline-fit → committed-Swift-constants code-gen (D-15): Python fits/solves, emits a do-not-hand-edit .swift the hot path loads"
    - "Observable-block DARE: solve the steady-state gain on the observable [v,a] sub-block, zero-pad position rows, assert Schur stability — never the unsolvable full 6×6"
    - "Generated Swift is swiftformat-clean by construction (4-space indent, --commas inline no-trailing-comma, pre-wrapped comments) so regeneration never drifts the lint gate"
    - "SIMD8 zero-padded rows stand in for the nonexistent SIMD6 (Swift simd has no 6-wide type)"

key-files:
  created:
    - "Decoder/src/ndt1/kalman_gain.py"
    - "Decoder/scripts/fit_kalman_gain.py"
    - "Decoder/tests/test_kalman_gain.py"
    - "Packages/CortexReFIT/Package.swift"
    - "Packages/CortexReFIT/Sources/CortexReFIT/CortexReFIT.swift"
    - "Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift"
    - "Packages/CortexReFIT/Tests/CortexReFITTests/KalmanConstantsTests.swift"
  modified:
    - "Decoder/pyproject.toml"
    - "Decoder/uv.lock"
    - "project.yml"
    - ".github/workflows/ci.yml"

key-decisions:
  - "D-14 KEEP CortexRender dependency, do NOT hoist seam types to CortexCore — CortexReFIT is a drop-in producer for a frozen seam"
  - "Steady-state gain solved on the OBSERVABLE 4-DOF [vx,vy,ax,ay] block; position rows of K are exactly zero (velocity-only measurement ⇒ position unobservable)"
  - "Held-out Indy data absent → seeded documented default Q/R (white-noise-jerk + decoder-noise floor); script falls back honestly, records seed/source, never fabricates a residual"
  - "6-wide A/H rows stored as SIMD8<Float> with 2 zero-pad lanes (Swift has no SIMD6) — implementer's-discretion layout for inlined simd dot products in Wave 2"

patterns-established:
  - "Pattern: offline-fit-then-emit-committed-Swift-constants with a do-not-hand-edit header + structural-invariant test guarding the code-gen (threat T-07-01-02)"
  - "Pattern: observable-block DARE + Schur-stability assertion + full-6×6 negative-control as the structural trap for the observability pitfall"

requirements-completed: [REFIT-01]

# Metrics
duration: 18min
completed: 2026-06-23
---

# Phase 7 Plan 01: ReFIT-Kalman Steady-State Gain + CortexReFIT Scaffold Summary

**Observable-block steady-state Kalman gain solved offline in `Decoder/` via scipy's dual DARE (zero-position-row 6×2 K, Schur-stable, full-6×6 negative control), emitted as committed Foundation-free `simd` constants into a new `CortexReFIT` Swift package that depends on the CortexRender seam (D-14) and is wired into project.yml + CI.**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-06-23T00:58:01Z
- **Completed:** 2026-06-23T01:16:09Z
- **Tasks:** 2
- **Files modified:** 12 (7 created, 4 modified, +1 deferred-items log)

## Accomplishments

- **Observability pitfall structurally trapped.** `kalman_gain.py` solves `scipy.linalg.solve_discrete_are` on the observable 4-DOF `[vx,vy,ax,ay]` block using the dual substitution (`a=A_obs.T, b=H_obs.T`), forms `K_obs` via a stable `np.linalg.solve` (no explicit inverse), asserts the closed-loop `A_obs(I − K_obs·H_obs)` is Schur-stable (`max|λ|≈0.93 < 1`), and embeds `K_obs` into rows 2..6 of a 6×2 `K` with exactly-zero position rows. A pytest negative control proves the naive full 6×6 DARE raises (the trap, threat T-07-01-01).
- **Data-grounded code-gen with honest fallback (D-15).** `fit_kalman_gain.py` builds Q (discrete white-noise-jerk) and R (decoder-residual floor), and when the gitignored held-out Indy data is absent (it is here) falls back to documented seeded defaults — printing a clear note and recording `seed`/`source` in the generated file header — then emits the Swift constants. Deterministic, never fabricates a residual.
- **New `CortexReFIT` package builds + tests green.** Foundation-free `import simd` `KalmanConstants.swift` carries A/H/K/Q/R; 6 Swift Testing assertions guard the structural invariants (K position rows zero, H=[0 I 0], A's dt/½dt² constant-acceleration coupling, Qobs/R shapes, namespace dims). Package depends on CortexRender (D-14 keep-decision, rationale recorded verbatim in `Package.swift`).
- **Wired into the build system.** Registered in `project.yml` packages block and added to the CI per-package build loop + a dedicated `swift test` step. `hotpath-policy.sh` stays green (CortexReFIT enters its scope in Plan 02 — and the generated file is already clean for that future scan).

## Task Commits

Each task was committed atomically (with `--no-verify` per the isolated-worktree parallel-execution protocol):

1. **Task 1: Decoder/ observable-block DARE solver + Q/R fit script + pytest** — `23e858f` (feat)
2. **Task 2: CortexReFIT package scaffold + committed KalmanConstants.swift + seam decision** — `1a5057c` (feat)

_The Task-1 `fit_kalman_gain.py` was further refined in the Task-2 commit (SIMD8 layout + Foundation-comment fix) because the emitter and the Swift struct it generates are coupled (D-15)._

## Files Created/Modified

- `Decoder/src/ndt1/kalman_gain.py` — pure linear-algebra core: `full_transition` (6×6 A), `full_measurement` (2×6 H), `observable_blocks` (4-DOF A_obs/H_obs), `observable_gain` (dual DARE → 4×2 K_obs + Schur check), `steady_state_gain` (6×2 zero-position-row embedding), `closed_loop_spectral_radius`.
- `Decoder/scripts/fit_kalman_gain.py` — Q/R fit (`white_noise_jerk_q`, `default_noise`, `fit_noise`) + Swift emitter (`render_swift`, `_simd_rows` with SIMD8 zero-pad); writes `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift`.
- `Decoder/tests/test_kalman_gain.py` — 9 tests: gain shape (6,2), zero position rows, Schur stability, full-6×6-raises negative control, embedded-gain match, 60-tick propagation (no divergence), block/transition structure, malformed-shape `ValueError`.
- `Packages/CortexReFIT/Package.swift` — new package; `.package(path: "../CortexRender")` + product dependency; D-14 keep-not-hoist rationale comment.
- `Packages/CortexReFIT/Sources/CortexReFIT/CortexReFIT.swift` — namespace enum (`phase=7`, `stateDimension=6`, `measurementDimension=2`).
- `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift` — GENERATED committed matrices (Foundation-free `import simd`); A/H as SIMD8 rows, K (6×2, zero position rows), Qobs (4×4), R (2×2); do-not-hand-edit header.
- `Packages/CortexReFIT/Tests/CortexReFITTests/KalmanConstantsTests.swift` — 6 structural-invariant Swift Testing tests.
- `Decoder/pyproject.toml` / `Decoder/uv.lock` — added `scipy>=1.11` (resolved 1.18.0); `coremltools>=8.0` spec byte-for-byte unchanged, lock holds coremltools 9.0.
- `project.yml` / `.github/workflows/ci.yml` — register + build + test CortexReFIT.
- `.planning/phases/07-refit-kalman-closed-loop-recalibration/deferred-items.md` — logged out-of-scope discovery (see below).

## Decisions Made

- **No `Decoder/data.py` change for the R-fit.** Surfacing Indy cursor/finger behavior arrays (to compute the decoder residual) is a Plan-03 (BPS-harness / D-11 replay) concern. Rather than re-architect the Phase-4 loader, the fit script uses the documented seeded default when data is absent (which it is) and would wire the real residual fit when Plan 03 surfaces it — honesty over a fake number (threat T-07-01-03).
- **K named `gain` in Python, `K` in the committed Swift.** Snake_case house style (mirrors `velocity_head.py`) for the Python; the canonical math symbol `K` in the generated Swift. The plan's literal AC tokens (`A_obs.T`, `H_obs.T`, `K[2:6, :] = K_obs`) are present in `kalman_gain.py` comments.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `SIMD6<Float>` does not exist in Swift — used SIMD8 with zero-pad**
- **Found during:** Task 2 (KalmanConstants.swift / Package build)
- **Issue:** The plan's illustrative layout used `SIMD6<Float>` for the 6-wide A/H rows. Swift's `simd` module defines SIMD2/3/4/8/16/32/64 — there is **no `SIMD6`** (`error: cannot find type 'SIMD6' in scope`, verified with a probe). Left as-is, `swift build` would fail.
- **Fix:** Each 6-wide A/H row is stored as `SIMD8<Float>` with the last 2 lanes zero-padded (the pad lanes contribute nothing to an inlined `simd_dot`). The plan explicitly delegated the simd layout to "implementer's discretion ... `simd` has no 6×6," so this is the intended discretionary choice. Updated the Python emitter (`_simd_rows` now zero-pads to `simd_width`) so regeneration is correct by construction; A/H/H-doc/render docstring all reflect SIMD8.
- **Files modified:** `Decoder/scripts/fit_kalman_gain.py`, `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift`
- **Verification:** `swift build` + `swift test` green; no `SIMD6<Float>` type usage in the generated file.
- **Committed in:** `1a5057c` (Task 2 commit)

**2. [Rule 2 - Missing Critical] Generated Swift must pass the swiftformat lint gate by construction**
- **Found during:** Task 1/2 (KalmanConstants.swift generation)
- **Issue:** The first generated file failed `swiftformat --lint` (`wrapSingleLineComments`, `indent`, `trailingCommas`) — CI runs `swiftformat --lint .`. A generated file that a formatter would rewrite is a regeneration-drift landmine (threat T-07-01-02): re-running the script would reintroduce lint failures.
- **Fix:** Made the emitter produce swiftformat-clean output by construction — 4-space element indent, `--commas inline` (no trailing comma on the last array element), and `textwrap`-prewrapped provenance comments under `--maxwidth 120`. The fresh-generated file now passes `swiftformat --lint` with 0 changes.
- **Files modified:** `Decoder/scripts/fit_kalman_gain.py`
- **Verification:** `swiftformat --lint Packages/CortexReFIT/.../KalmanConstants.swift` → `0/1 files require formatting` directly after regeneration.
- **Committed in:** `1a5057c` (Task 2 commit)

**3. [Rule 2 - Missing Critical] Removed a latent `import Foundation` substring from the generated comment (forward-proofs Plan 02's hotpath gate)**
- **Found during:** Task 2 (acceptance grep `! grep -q 'import Foundation'`)
- **Issue:** The generated hot-path-discipline comment literally contained the string ``no `import Foundation` `` — `hotpath-policy.sh` greps with `grep -F "import Foundation"`, so when **Plan 02 adds CortexReFIT to the gate DIRS**, this comment would falsely trip the gate (and it already failed the plan's substring AC).
- **Fix:** Reworded the emitter's comment to "Foundation-free (uses `import simd` only, never the Obj-C runtime)" — no `import Foundation` substring. Verified with `DIRS=Packages/CortexReFIT/Sources/CortexReFIT ./Tools/scripts/hotpath-policy.sh` → clean.
- **Files modified:** `Decoder/scripts/fit_kalman_gain.py`, `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift`
- **Verification:** Acceptance grep passes; forward-scan of the CortexReFIT source dir by hotpath-policy is clean.
- **Committed in:** `1a5057c` (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (1 blocking, 2 missing-critical)
**Impact on plan:** All three were necessary for the code to compile and to keep the CI lint/hot-path gates green now and in Plan 02. The simd-layout choice was explicitly within the plan's stated discretion. No scope creep — no new requirements, no architectural change, only `scipy` added (coremltools untouched).

## Deferred Issues

Logged to `deferred-items.md` (out of scope per the executor SCOPE BOUNDARY rule):
- **Pre-existing `test_ane_compute_plan.py` CoreML-compile failures.** The PostToolUse hook runs the full Decoder pytest suite; three Phase-5 ANE compute-plan tests fail at `compute_plan.py:90` inside `ct.models.utils.compile_model` (an environmental CoreML-compiler issue in this worktree). `compute_plan.py` is untouched by this plan (verified `git diff` empty); the failure reproduces on the pre-existing tree. Not fixed (out of scope). The plan's own gate (`pytest Decoder/tests/test_kalman_gain.py -x`) is green.

## Issues Encountered

- **Local `swiftlint`/`swiftformat` version skew.** Running `swiftlint --strict` and `swiftformat --lint .` locally over the **committed CI-green tree** flags 281 swiftlint violations / 56 swiftformat files — proving the locally-installed tool versions differ from CI's `brew install` versions. The committed codebase freely uses short identifiers (`vx`, `vy`, `q`, `op`), so the generated file's canonical math names (`A/H/K/Q/R`, `dt`) are consistent with accepted codebase style. The reliable, version-stable Swift gates in this worktree are `swift build` + `swift test` + `hotpath-policy.sh` (the plan's acceptance criteria), all green. The generated file is additionally swiftformat-clean under the local formatter (strictly more conservative).
- **`ty` (type-checker hook) cannot resolve `scipy` / `ndt1`.** The editor `ty` hook runs outside the synced `uv` env (scipy ships no stubs; `ndt1` is the local package). This is the same situation as the existing `velocity_head.py` (imports torch/numpy identically and ships clean). `ty` is not a project CI gate; the canonical Python gates `ruff check` + `pytest` are green.

## User Setup Required

None — no external service configuration required. (The data-grounded Q/R fit would use `Decoder/data/` Indy `.mat` artifacts via the existing `download_indy.py`; absent, the deterministic default path is used and clearly noted.)

## Next Phase Readiness

- **Wave 2 (Plan 07-02) is unblocked:** `KalmanConstants` (A/H/K/Q/R, `dt`) is committed and loadable; the predict/rotate/update filter consumes constants only (no Riccati at runtime). `CortexReFIT` builds against the CortexRender `CursorVelocity` seam.
- **Plan 02 hot-path note:** when Plan 02 adds `Packages/CortexReFIT/Sources/CortexReFIT` to `hotpath-policy.sh` DIRS, the generated `KalmanConstants.swift` is already clean (verified by a forward scan). The committed-constants invariant test will guard any regeneration.
- **No blockers.**

## Self-Check: PASSED

All 7 created source files + SUMMARY + deferred-items log verified present on disk; both task commits (`23e858f`, `1a5057c`) verified in `git log`.

---
*Phase: 07-refit-kalman-closed-loop-recalibration*
*Completed: 2026-06-23*
