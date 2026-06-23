---
phase: 08-apple-bci-hid-integration-distribution-v0-ship
plan: 05
subsystem: testing
tags: [webgrid-bps, fitts-throughput, information-rate, swift-testing, ci-gate, determinism, neuralink, braingate, refit, instrumentation-honesty]

# Dependency graph
requires:
  - phase: 07-refit-kalman-closed-loop-recalibration
    provides: CortexReFITBench deterministic 3-way ablation harness, WebgridAcquisition dwell-to-select model, FittsThroughput S&M-2004 math, refit_bps.json + its CI byte-identical guard
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship (08-01)
    provides: Phase-8 CI structural-gate idiom (hid-surface-policy.sh) the bps-policy.sh gate is placed after
provides:
  - WebgridBPS.swift — pure B=max(0,log2(N)*(Sc-Si)/t) information-rate bitrate math with the mandatory clamp (N=900 for 30x30 incl. delete key)
  - Extended CortexReFITBench emitting BOTH the Webgrid BPS (leaderboard metric) AND the S&M-2004 Fitts-TP cross-check per arm
  - webgrid_bps.json — committed machine-readable Webgrid BPS + Fitts-TP + the Si=0 incorrect_model disclosure + the honest synthetic-vs-live caveat
  - 08-bps-evidence.md — honest synthetic-replay BPS (refit 1.953), the 6.55-BPS gap to 8.5, NOT tuned toward 4.16
  - bps-policy.sh — structural (clamp+log2+formula+N) + run-twice-determinism CI gate with a biting self-test
affects: [distribution-readme-DIST-04, phase-08-verification, phase-08-validation, milestone-v0-ship]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Webgrid information-rate BPS (log2(N)-normalized) as the leaderboard-comparable metric, distinct from the S&M-2004 Fitts-TP cross-check (PERF-03)"
    - "Mandatory max(0,...) clamp on a rate metric, unit-tested to BITE on net-negative input + gate-asserted present"
    - "Structural Si=0 honesty disclosure (incorrect_model) — a single-target dwell-to-select harness's upper-bound reading is disclosed, never silently emitted (D-12)"
    - "Additive evidence artifact: a new metric in a separate JSON keeps the prior phase's committed artifact + its CI guard byte-identical"
    - "JSONEncoder .withoutEscapingSlashes so a documented formula literal reads verbatim (matches the plan/evidence/gate)"

key-files:
  created:
    - Packages/CortexReFIT/Sources/CortexReFIT/WebgridBPS.swift
    - Packages/CortexReFIT/Tests/CortexReFITTests/WebgridBPSTests.swift
    - Tools/scripts/bps-policy.sh
    - .planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/webgrid_bps.json
    - .planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/08-bps-evidence.md
  modified:
    - Packages/CortexReFIT/Sources/CortexReFITBench/main.swift
    - .github/workflows/ci.yml

key-decisions:
  - "Chose plan option (a) DISCLOSE for Si: pass incorrect:0 and write the incorrect_model upper-bound disclosure into both the JSON and evidence (no RNG miss model — preserves D-13 determinism)"
  - "Webgrid seconds t = sum of per-trial movement times (HIT MT or full timeout) across the arm's reaches; Sc = the authoritative TrialResult.acquired HIT count"
  - "Added .withoutEscapingSlashes to the NEW webgrid_bps.json writer only (refit_bps.json writer untouched) so the formula field reads as the documented literal B = max(0, log2(N)*(Sc-Si)/t)"
  - "Reported the honest synthetic-replay number (refit 1.953 BPS, below 4.16) with the explicit 6.55-BPS gap to 8.5 — NOT tuned toward any pass bar (D-12)"

patterns-established:
  - "Pattern 1: leaderboard-comparable Webgrid bitrate alongside the Fitts-TP cross-check, both from the same per-trial outcomes on the identical seed-locked replay"
  - "Pattern 2: a mandatory rate-metric clamp guarded three ways — unit test bites (Test 2), source token present (gate), formula disclosure pinned (gate)"
  - "Pattern 3: additive-artifact discipline — new metric in a separate JSON, prior-phase artifact + guard left byte-identical (diff exits 0)"

requirements-completed: [PERF-01, PERF-02, PERF-03]

# Metrics
duration: 11min
completed: 2026-06-23
---

# Phase 8 Plan 05: Webgrid Information-Rate BPS Metric Summary

**Webgrid information-rate BPS (B = max(0, log2(900)·(Sc−Si)/t)) added to the deterministic CortexReFITBench alongside the retained S&M-2004 Fitts-TP cross-check — ReFIT scores an honest 1.953 BPS on synthetic Indy replay (6.55 short of 8.5, NOT tuned toward 4.16), with the mandatory clamp, the structural Si=0 disclosure, and a run-twice-determinism CI gate; the Phase-7 refit_bps.json + its guard left byte-identical.**

## Performance

- **Duration:** ~11 min
- **Started:** 2026-06-23T06:25:52Z
- **Completed:** 2026-06-23T06:36:54Z
- **Tasks:** 3
- **Files modified:** 7 (5 created, 2 modified)

## Accomplishments
- **`WebgridBPS.swift`** — pure, Foundation-free `enum WebgridBPS` mirroring `FittsThroughput`'s value-namespace style: `targetBits(n)=log2(N)` (guarded `n≥2`), `bitsPerSecond(...)` with the **MANDATORY `Swift.max(0, …)` clamp** (08-RESEARCH §0.4 — CONTEXT D-11 omitted it), `gridTargetCount(30,30)=900` (incl. the delete key), and the `referencePeakBPS=8.5` / `brainGate6x6BPS=4.16` leaderboard anchors. 5 Swift-Testing behaviors (clean-run value, the clamp BITES on net-negative, log2(N) + n<2 guard, seconds≤0 guard, 30×30=900).
- **Extended `CortexReFITBench`** to accumulate the Webgrid `Sc`/`t` per arm over the **identical seed-locked reaches** and emit **both** the Webgrid BPS (the leaderboard metric) and the **retained** S&M-2004 Fitts-TP (PERF-03 cross-check) for raw/kalman_only/refit. The existing `refit_bps.json` write is **byte-for-byte unchanged** (Phase-7 CI guard intact); the Webgrid BPS goes into a separate `webgrid_bps.json`.
- **Honest, disclosed result:** ReFIT **1.953 Webgrid BPS** (raw 1.292, Kalman-only 1.183), Sc=103, Si=0, t=517.56s — reported with the explicit **6.55-BPS gap to the 8.5 peak** (PERF-02) and an explicit statement it was **NOT tuned toward 4.16** (D-12). **Si is structurally 0** (the single-target dwell-to-select harness has no mis-selection path), **disclosed** as `incorrect_model` in both the JSON and `08-bps-evidence.md` → the BPS is an honest **upper-bound**, not a silent "measured zero errors."
- **`bps-policy.sh`** — structural (clamp + log2 + formula pin + N=900) **and** run-twice-byte-identical determinism gate, with a `--self-test` whose clamp-strip and formula-strip negative controls bite; wired into CI **after** the intact Phase-7 ReFIT guard.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement WebgridBPS.swift (clamp + tests, TDD)** — `73b7cc0` (feat)
2. **Task 2: Extend bench to emit Webgrid BPS + Fitts-TP, write evidence + JSON** — `52d4296` (feat)
3. **Task 3: bps-policy.sh (formula + determinism) + self-test + CI wiring** — `1148d4b` (chore)

_Task 1 was TDD: the failing `WebgridBPSTests` (RED) and the `WebgridBPS.swift` implementation (GREEN) were authored together and committed as one `feat` once green._

## Files Created/Modified
- `Packages/CortexReFIT/Sources/CortexReFIT/WebgridBPS.swift` — the pure Webgrid information-rate bitrate math (executed source of truth) with the mandatory clamp + log2(N) normalization + leaderboard anchors.
- `Packages/CortexReFIT/Tests/CortexReFITTests/WebgridBPSTests.swift` — 5 Swift-Testing behaviors; the REAL correctness guard (Test 2 asserts the clamp bites).
- `Packages/CortexReFIT/Sources/CortexReFITBench/main.swift` — extended ablation: `ReachOutcome`/`ArmResult` carry both metrics; emits the Webgrid BPS + Fitts-TP per arm; writes `webgrid_bps.json` (`.sortedKeys` + `.withoutEscapingSlashes`); `refit_bps.json` write unchanged.
- `.planning/phases/08-.../webgrid_bps.json` — committed machine-readable evidence (refit 1.953, raw/kalman BPS, Fitts-TP cross-check, formula pin, `incorrect_model`, caveat, 8.5/4.16 anchors).
- `.planning/phases/08-.../08-bps-evidence.md` — honest synthetic-replay framing, the gap to 8.5, the Si=0 upper-bound disclosure, the Fitts-TP cross-check, the re-run runbook.
- `Tools/scripts/bps-policy.sh` — structural + run-twice-determinism gate with a biting self-test (mirrors render-policy.sh; chmod +x, mode 100755).
- `.github/workflows/ci.yml` — new "Webgrid BPS structural + determinism gate (PERF-01, D-06/D-13)" step after the unmodified Phase-7 ReFIT guard.

## Decisions Made
- **Si honesty = option (a) DISCLOSE** (plan-preferred): the single-target dwell-to-select harness cannot drive Si>0, so `incorrect:0` is passed and the `incorrect_model: none — single-target dwell-to-select; Si structurally 0; BPS is upper-bound` disclosure is written into **both** artifacts. No RNG/clock miss model (would break D-13 determinism).
- **Webgrid `t`** = sum of per-trial movement times (HIT MT or full timeout) across the arm; **`Sc`** = the authoritative `TrialResult.acquired` HIT count. The evidence transparently documents that this Sc (103) differs from the Phase-7 Fitts debug `acq` (100) because the Fitts predicate is strictly-before-timeout while the Webgrid Sc uses the dwell-satisfied flag (3 final-tick HITs).
- **`.withoutEscapingSlashes`** added to the NEW Webgrid JSON writer only — so the `formula` field reads as the documented literal `B = max(0, log2(N)*(Sc-Si)/t)` (the JSON default would escape `/`→`\/`, breaking the plan/evidence/gate literal). The Phase-7 `writeJSON` was left untouched.
- **Honest number, not a pass bar:** ReFIT's 1.953 BPS is reported as-is (below the 4.16 reference), with the gap to 8.5 documented — the instrumentation-honesty ethos for the Chapman/Even-Chen audience (D-12).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected an inexact hardcoded sanity-anchor literal in WebgridBPSTests Test 1**
- **Found during:** Task 1 (TDD GREEN phase)
- **Issue:** The hand-written sanity-anchor literal `16.356_336_488_372_9` was a transcription error (off by 3.45e-05 from the true `log2(900)·100/60`). The primary `#expect` against the recomputed `log2(900.0)*100.0/60.0` passed — proving the implementation was correct; only the duplicated literal was wrong.
- **Fix:** Replaced with the exact value `16.356_301_985_361_73` (verified via `python3`), tolerance tightened to `1e-9`.
- **Files modified:** Packages/CortexReFIT/Tests/CortexReFITTests/WebgridBPSTests.swift
- **Verification:** All 5 WebgridBPSTests green.
- **Committed in:** `73b7cc0` (Task 1 commit)

**2. [Rule 1 - Bug] Untyped the leaderboard-anchor constants so the plan's acceptance grep matches**
- **Found during:** Task 1 (acceptance-criteria verification)
- **Issue:** I initially declared `public static let referencePeakBPS: Double = 8.5`; the plan's acceptance grep `referencePeakBPS = 8.5` (and the `<action>` text `public static let referencePeakBPS = 8.5`) expects the untyped form — the `: Double ` between the name and `=` broke the literal grep.
- **Fix:** Dropped the explicit `: Double` annotation on both anchors (the literal `8.5`/`4.16` infer to `Double`; Test 5's `== 8.5`/`== 4.16` still hold).
- **Files modified:** Packages/CortexReFIT/Sources/CortexReFIT/WebgridBPS.swift
- **Verification:** The plan's exact grep now matches; all 5 tests still green.
- **Committed in:** `73b7cc0` (Task 1 commit)

**3. [Rule 1 - Bug] JSON forward-slash escaping broke the documented formula literal**
- **Found during:** Task 2 (acceptance-criteria verification)
- **Issue:** `JSONEncoder` escapes `/` as `\/` by default, so the written `formula` field read `B = max(0, log2(N)*(Sc-Si)\/t)` — which does NOT match the plan/evidence/gate literal `...(Sc-Si)/t` (the plan's acceptance grep would miss it).
- **Fix:** Added `.withoutEscapingSlashes` to the NEW `writeWebgridJSON` encoder ONLY (the Phase-7 `writeJSON` is untouched, so `refit_bps.json` stays byte-identical). Re-verified determinism + the Phase-7 byte-identical guard after the change.
- **Files modified:** Packages/CortexReFIT/Sources/CortexReFITBench/main.swift
- **Verification:** The plan's literal grep now matches; `webgrid_bps.json` byte-identical across two runs; `refit_bps.json` still byte-identical to the Phase-7 committed copy.
- **Committed in:** `52d4296` (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (3 Rule-1 bugs — all literal/encoding corrections, the documented Cortex literal-grep-discipline pattern).
**Impact on plan:** All three were small correctness fixes to make the artifacts match the plan's documented literals exactly; the executed math and the additive-change guarantees were correct from the first run. No scope creep, no new dependencies, no architectural changes.

## Issues Encountered
- The Webgrid `Sc` (103) vs the Phase-7 Fitts `acq` debug (100) discrepancy was investigated and found to be a genuine, explainable predicate difference (dwell-satisfied flag vs strictly-before-timeout MT — 3 final-tick HITs). Documented transparently in `08-bps-evidence.md` rather than papered over.

## Known Stubs
None. The Webgrid BPS is a fully computed metric over the real deterministic harness. `Si=0` is **not** a stub — it is the structurally-correct value for a single-target dwell-to-select harness, explicitly disclosed (`incorrect_model`) as an upper-bound in both the JSON and the evidence (D-12). The synthetic-replay data path is the documented, intentional v0 evidence basis (a real-Indy `.mat` loader remains a documented follow-on, consistent with Phases 4/7).

## User Setup Required
None — no external service configuration required. The metric is device-independent / algorithmic and runs headless on any Apple-Silicon Mac (CPU).

## Next Phase Readiness
- **PERF-01/02/03 satisfied.** The Webgrid BPS (1.953, honest) + the Fitts-TP cross-check are committed evidence; the DIST-04 README (Plan 06) can now cite the leaderboard-comparable Webgrid bitrate with its honest gap to 8.5 + the synthetic-vs-live caveat.
- **P7 D-13 closed correctly** — the 4.16/8.5 comparison now uses the Webgrid bitrate (not the Fitts-TP), reported honestly.
- **No blockers.** The Phase-7 `refit_bps.json` + its CI guard remain intact (additive change verified byte-identical); the new `bps-policy.sh` gate + self-test are wired into CI after it.

## Self-Check: PASSED

All 6 created files verified present on disk; all 3 task commit hashes (`73b7cc0`, `52d4296`, `1148d4b`) verified in git history. The Phase-7 `refit_bps.json` byte-identical diff guard exits 0; `bps-policy.sh` + `--self-test` exit 0; `WebgridBPSTests` 5/5 green; `CortexReFITBench --smoke` exits 0.

---
*Phase: 08-apple-bci-hid-integration-distribution-v0-ship*
*Completed: 2026-06-23*
