---
phase: 07-refit-kalman-closed-loop-recalibration
plan: 02
subsystem: api
tags: [kalman, refit, intent-rotation, simd, swift, hotpath, gilja-2012, steady-state-gain, nonisolated]

# Dependency graph
requires:
  - phase: 07-refit-kalman-closed-loop-recalibration (Plan 01)
    provides: "KalmanConstants.swift (A 6×6 / H 2×6 as SIMD8 zero-pad rows, K 6×2 zero-position-rows, Qobs/R) + CortexReFIT package scaffold depending on the CortexRender velocity seam"
  - phase: 05-coreml-ane-deployment
    provides: "CortexDecoder.decode(_:) -> SIMD2<Float> — the (vx,vy) measurement the filter wraps; velocityDimension == 2"
  - phase: 06-cametaldisplaylink-120hz-renderer
    provides: "CursorVelocity / VelocityRing / CursorIntegrator velocity seam (the integrator owns the [0,1] clamp + non-finite reject; the filter only emits finite values)"
provides:
  - "IntentRotation.swift — Gilja-2012 gated full-direction-align, speed-preserving intent-rotation on the MEASUREMENT (REFIT-02); four gating branches + magnitude-preservation tested"
  - "KalmanFilter.swift — 6-DOF steady-state constant-gain step in RESEARCH §2.2 order (predict → external position sync → rotate measurement → constant-gain update → emit (vx,vy)); inlined SIMD8/SIMD2 dot products, zero allocation, no runtime Riccati (REFIT-01)"
  - "KalmanFilterTests.swift — single-step hand-computed match + 64-tick trajectory vs an independent nested-loop reference (‖x_swift−x_ref‖<tol) + external-position-sync + finiteness + rotation-wired"
  - "hotpath-policy.sh covers Packages/CortexReFIT/Sources/CortexReFIT (SC#3); gate + --self-test green — hot-path discipline on the filter path is now a build-failing CODE policy"
  - "KalmanConstants enum marked nonisolated (+ its fit_kalman_gain.py emitter) so the nonisolated hot-path filter loads A/H/K with no MainActor isolation hop"
affects: [07-03-bps-harness, wave-3-headless-bps-replay, phase-8-live-closed-loop-demo]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Inlined fixed-dim simd mat-vec: x⁻=A·x and innovation/update as a handful of simd_dot over the committed SIMD8/SIMD2 constant rows (pad lanes 6,7 zero → contribute nothing); zero heap, hot-path-safe"
    - "External position sync into the predicted-position block BEFORE the rotation (RESEARCH §2.3 / §7 pitfall 5): position is unobservable from a velocity measurement, so K's position rows are zero and only setCursorPosition moves px,py — no double-integration"
    - "Independent in-test reference (plain nested-loop [Float] matrices over the SAME committed constants) is the trajectory-match oracle for the inlined-simd hot path — a wrong dot-product drifts and fails over ≥50 ticks"
    - "nonisolated immutable Sendable constants for the hot path: an enum of compile-time simd let-arrays is marked nonisolated so a nonisolated (decoder-pthread) consumer reads it with no isolation hop — mirrors IntentRotation / CursorVelocity opting out of .defaultIsolation(MainActor.self)"

key-files:
  created:
    - "Packages/CortexReFIT/Sources/CortexReFIT/IntentRotation.swift"
    - "Packages/CortexReFIT/Sources/CortexReFIT/KalmanFilter.swift"
    - "Packages/CortexReFIT/Tests/CortexReFITTests/IntentRotationTests.swift"
    - "Packages/CortexReFIT/Tests/CortexReFITTests/KalmanFilterTests.swift"
  modified:
    - "Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift"
    - "Decoder/scripts/fit_kalman_gain.py"
    - "Tools/scripts/hotpath-policy.sh"
    - ".github/workflows/ci.yml"

key-decisions:
  - "Intent-rotation acts on the MEASUREMENT before the Kalman update (D-05): full direction-align onto cursor→target, decoded speed preserved, gated to target-active AND dist>r_acq AND speed>eps (D-06) — never a post-hoc output nudge"
  - "Step ordering is load-bearing (RESEARCH §2.2): predict → overwrite predicted position with the synced cursor → rotate measurement toward (target−syncedPos) → constant-gain update → emit; the position sync precedes the rotation so the cursor→target vector uses the authoritative clamped position"
  - "KalmanConstants made nonisolated (generator + generated file kept consistent) — the immutable Sendable simd constants must be readable from the nonisolated hot-path filter on the decoder pthread (SC#3); the original MainActor isolation blocked the build"
  - "6-DOF state packed in a SIMD8<Float> (lanes 6,7 unused) and constants captured into stored let rows at init — step touches only instance storage, zero per-tick allocation, no static-property access on the hot path"

patterns-established:
  - "Pattern: inlined-simd hot-path math validated against an independent nested-loop in-test reference over a multi-tick trajectory (propagation, not one step)"
  - "Pattern: nonisolated immutable-constant enum as the hot-path data source for a nonisolated pthread consumer (no MainActor hop), keeping the offline code-gen emitter and the committed file byte-consistent"

requirements-completed: [REFIT-01, REFIT-02]

# Metrics
duration: 28min
completed: 2026-06-23
---

# Phase 7 Plan 02: ReFIT-Kalman Step + Intent-Rotation Summary

**The 6-DOF steady-state constant-gain ReFIT-Kalman step (predict → external position sync → rotate measurement → constant-gain update → emit (vx,vy)) and the Gilja-2012 gated speed-preserving intent-rotation, implemented in pure Foundation-free `import simd`, matched to an independent reference over a 64-tick trajectory, with CortexReFIT now policed by `hotpath-policy.sh` (SC#3).**

## Performance

- **Duration:** ~28 min (plan span across both tasks; Task 1 by a prior executor, Task 2 this session)
- **Started:** 2026-06-23T00:58:33Z (Task 1 commit time, prior executor)
- **Completed:** 2026-06-23T01:53:00Z
- **Tasks:** 2
- **Files modified:** 8 (4 created, 4 modified)

## Accomplishments

- **Gilja-2012 intent-rotation on the measurement (REFIT-02, Task 1 — `e40a400`).** `IntentRotation.rotate(measurement:cursor:target:acquisitionRadius:)` aligns the decoded velocity's DIRECTION fully onto cursor→target while PRESERVING its decoded speed, gated to target-active AND `dist > r_acq` AND `speed > eps`. All four gating branches (outside r_acq rotates, inside r_acq passthrough, no target passthrough, zero-velocity guard) plus magnitude-preservation and finiteness are unit-tested (5 tests).
- **6-DOF steady-state constant-gain Kalman step (REFIT-01, Task 2 — `5202a96`).** `KalmanFilter.step(measurement:target:acquisitionRadius:)` runs the exact RESEARCH §2.2 ordering — `x⁻ = A·x` (six inlined `simd_dot` over the SIMD8 constant rows) → sync the synced cursor into `x⁻[px,py]` BEFORE the rotation → `rotate` the measurement → `x = x⁻ + K·(z_rot − H·x⁻)` → emit `(vx,vy)`. Constants-only (no runtime Riccati, no covariance propagation, D-02); zero per-tick allocation.
- **Numerical correctness proven over propagation, not one step.** `KalmanFilterTests` checks one step against a hand-computed update AND a 64-tick trajectory against an INDEPENDENT plain nested-loop `[Float]` reference reading the same committed constants (`‖x_swift − x_ref‖ < 2e-3` at every tick, full 6-state) — a wrong inlined dot-product would drift and fail (threat T-07-02-04). Also asserts external position-sync (two synced positions ⇒ two rotated measurements; the synced p — not a double-integrated one — feeds the rotation) and rotation-wiring (active-target output differs from the no-rotation path, and projects further along cursor→target).
- **Hot-path discipline established for CortexReFIT (SC#3).** `Packages/CortexReFIT/Sources/CortexReFIT` added to `hotpath-policy.sh` `DIRS_ARRAY`; the gate scans it clean and the negative-control `--self-test` still bites on every forbidden token — so a future `import Foundation`/lock/heap on the filter path is a build-failing code policy (threat T-07-02-01). Both source files are `import simd`-only.
- **16/16 CortexReFIT tests green** (KalmanConstants 6 + IntentRotation 5 + KalmanFilter 5) under Swift 6.2.4 / Xcode 26.3.

## Task Commits

Each task was committed atomically (with `--no-verify` per the isolated-worktree parallel-execution protocol):

1. **Task 1: IntentRotation — gated full-direction-align, speed-preserving (REFIT-02)** — `e40a400` (feat) _[prior executor; the executor died on an API-stream timeout after this commit, before Task 2]_
2. **Task 2: KalmanFilter step + hotpath-policy coverage (REFIT-01, SC#3)** — `5202a96` (feat)

_Task 2 is a single atomic TDD commit (test + impl + policy + CI + the nonisolated blocking-fix) per the continuation orchestrator's "commit Task 2 atomically" instruction — RED→GREEN was run in-session before staging (tests confirmed failing for "cannot find 'KalmanFilter' in scope", then passing)._

## Files Created/Modified

- `Packages/CortexReFIT/Sources/CortexReFIT/IntentRotation.swift` _(Task 1)_ — `nonisolated struct IntentRotation` with the gated `rotate(...)`; `import simd`, Foundation-free; `epsilon = 1e-6` zero-velocity guard.
- `Packages/CortexReFIT/Sources/CortexReFIT/KalmanFilter.swift` _(Task 2)_ — `nonisolated final class KalmanFilter`; 6-DOF state in a `SIMD8<Float>`; A/H/K snapshotted into stored `let` rows at init; `setCursorPosition` / `setState` / `stateVector` seams; `step(...)` the per-tick predict→sync→rotate→update→emit op.
- `Packages/CortexReFIT/Tests/CortexReFITTests/IntentRotationTests.swift` _(Task 1)_ — 5 Swift Testing cases (4 gating branches + magnitude + finiteness).
- `Packages/CortexReFIT/Tests/CortexReFITTests/KalmanFilterTests.swift` _(Task 2)_ — 5 Swift Testing cases incl. the 64-tick reference-match trajectory; carries an independent nested-loop `referenceStep` oracle.
- `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift` _(Task 2, modified)_ — `public enum` → `public nonisolated enum` (+ doc note) so the hot-path filter reads A/H/K with no isolation hop.
- `Decoder/scripts/fit_kalman_gain.py` _(Task 2, modified)_ — the Swift emitter now produces `public nonisolated enum KalmanConstants` (+ matching doc note) so regeneration stays consistent with the committed file.
- `Tools/scripts/hotpath-policy.sh` _(Task 2, modified)_ — added `Packages/CortexReFIT/Sources/CortexReFIT` to the `DIRS_ARRAY` default (+ Phase-7 rationale comment).
- `.github/workflows/ci.yml` _(Task 2, modified)_ — one-line comment on the Hot-path policy step noting CortexReFIT joined the scope in Phase 7 (the default-scope run polices it; no separate step).

## Decisions Made

- **Single atomic Task-2 commit rather than the TDD test→feat split.** The continuation orchestrator explicitly scoped this run to "execute ONLY Task 2, commit it atomically." RED (tests fail: no `KalmanFilter` symbol) and GREEN (16/16 pass) were both exercised in-session; the commit bundles test + implementation + policy + CI + the nonisolated fix.
- **The 6-DOF state lives in a `SIMD8<Float>` (lanes 6,7 unused), matching the committed A/H SIMD8 row layout** so the predict is six `simd_dot(A_row, state)` with the pad lanes contributing zero — the layout Plan 01 emitted dictated this (implementer's-discretion inlining per CONTEXT).
- **`stateVector` / `setState` test seams kept minimal and off the hot path** — the hot path (`step`) touches only the `SIMD8` state and the stored constant rows; the `[Float]` array seams exist purely for the reference-match and sync tests.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `KalmanConstants` was MainActor-isolated and unreadable from the nonisolated hot-path filter**
- **Found during:** Task 2 (KalmanFilter build)
- **Issue:** Under the package's `.defaultIsolation(MainActor.self)`, the generated `KalmanConstants` enum's `static let A/H/K` are MainActor-isolated. `KalmanFilter` MUST be `nonisolated` (it runs on the decoder pthread — SC#3), so loading the constants raised `error: main actor-isolated static property 'H'/'K' can not be referenced from a nonisolated context`. The RESEARCH/CONTEXT design explicitly requires the hot-path filter to load these constants, so they must be `nonisolated`. Left unfixed, `swift build` fails.
- **Fix:** Marked the enum `public nonisolated enum KalmanConstants` (the values are immutable `Sendable` compile-time simd `let`-arrays, so `nonisolated` is sound — no data race). Applied the identical one-token change to BOTH the generated `KalmanConstants.swift` AND its emitter `Decoder/scripts/fit_kalman_gain.py` (line 277 template) so regeneration produces byte-consistent output — no code-gen drift (the generator and its output agree). Mirrors how `IntentRotation` / `CursorVelocity` opt out of the package-default MainActor.
- **Files modified:** `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift`, `Decoder/scripts/fit_kalman_gain.py`
- **Verification:** `swift build` + `swift test --package-path Packages/CortexReFIT` green (16/16); `KalmanConstantsTests` (still `@MainActor`) still compiles — a MainActor context reads a nonisolated value fine. The emitter change is a Swift-string-literal edit only (no Python logic/import/type touched).
- **Committed in:** `5202a96` (Task 2 commit)

**2. [Rule 3 - Blocking] `SIMD8<Float>` has no `.x`/`.y` member accessors**
- **Found during:** Task 2 (KalmanFilter first build)
- **Issue:** Initial draft used `state.x`/`state.y` to read/write the position lanes; only `SIMD2/3/4` expose `.x/.y/.z/.w` — `SIMD8` does not (`error: value of type 'SIMD8<Float>' has no member 'x'`).
- **Fix:** Used subscript indexing `state[0]` / `state[1]` for the position lanes (consistent with the rest of the lane access in `step`).
- **Files modified:** `Packages/CortexReFIT/Sources/CortexReFIT/KalmanFilter.swift`
- **Verification:** `swift build` proceeds past these lines; full suite green.
- **Committed in:** `5202a96` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 3 - blocking). Both confined to Task 2's own changes; no scope creep, no new requirements, no architectural change. The `nonisolated` fix touched the Plan-01 generated file + its generator, but only to make the hot-path consumer the plan mandates actually compile — and kept generator/output consistent.

## Issues Encountered

- **PostToolUse hook flagged `numpy`/`ndt1` import errors on the `fit_kalman_gain.py` edit.** These are the documented environment quirks (the `ty` type-checker hook + bare `pytest` run outside the synced `uv` env — `uv sync --project Decoder --extra dev` is required, per the Plan-01 SUMMARY and project memory). My edit to that file is a Swift-string-literal change inside a triple-quoted template — no Python logic, import, or type touched — so the flags are pre-existing and out of scope (executor SCOPE BOUNDARY). The canonical gate for this change is the Swift build, which is green.
- **Local `swiftlint`/`swiftformat` version skew (noted in Plan 01).** Not chased — the canonical, version-stable gates `swift build` + `swift test` + `hotpath-policy.sh` (+ `--self-test`) are all green, exactly as the plan's `<verify>` specifies.

## User Setup Required

None — no external service configuration required. (The data-grounded Q/R fit for any future regeneration uses `Decoder/data/` Indy `.mat` artifacts; absent here, Plan 01's deterministic seeded default is used. Regeneration would additionally need `uv sync --project Decoder --extra dev`.)

## Next Phase Readiness

- **Wave 3 (Plan 07-03, the headless S&M-2004 BPS harness) is unblocked.** `KalmanFilter` + `IntentRotation` are the closed-loop algorithmic surface the harness drives in its `Kalman-only` / `Kalman+rotation` ablation arms (D-12): `replay → decode → [raw | Kalman-only | Kalman+rotation] → CursorIntegrator → webgrid acquisition → throughput`. The filter emits a plain `SIMD2<Float>`; the harness narrows to the `CursorVelocity` seam (the convenience `stepEmitting(...)` wrapper was left for Plan 03 to define alongside its `ts_ns`/`seq` source, as it was optional in the plan).
- **SC#3 tail-latency bench (Plan 03) substrate ready.** The `step` is allocation-free inlined simd on the existing pthread; the `LatencyHistogram`-over-filter-step measurement (n ≥ 10k) plugs onto it directly.
- **No blockers.**

## Self-Check: PASSED

- Created files verified present: `IntentRotation.swift`, `KalmanFilter.swift`, `IntentRotationTests.swift`, `KalmanFilterTests.swift` — all FOUND on disk.
- Commits verified in `git log`: `e40a400` (Task 1) FOUND, `5202a96` (Task 2) FOUND.
- `swift test --package-path Packages/CortexReFIT` → 16/16 PASS; `./Tools/scripts/hotpath-policy.sh` exit 0; `--self-test` exit 0.

---
*Phase: 07-refit-kalman-closed-loop-recalibration*
*Completed: 2026-06-23*
