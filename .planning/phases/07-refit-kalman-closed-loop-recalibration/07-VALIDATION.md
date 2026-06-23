---
phase: 7
slug: refit-kalman-closed-loop-recalibration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-22
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from `07-RESEARCH.md` § Validation Architecture. Task IDs are assigned at plan time;
> `/gsd-validate-phase 7` reconciles status post-execution (this is a plan-time seed — GSD does not flip ⬜→✅ automatically).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (Swift)** | `swift test` (SwiftPM) — `CortexReFIT` package unit tests + headless BPS bench executable (mirrors `CortexDecoderBench`) |
| **Framework (Python)** | `pytest` under `Decoder/` for the offline Q/R fit + DARE steady-state-gain solve (`uv sync --project Decoder --extra dev` first; `coremltools` pinned 9.0) |
| **Static gates** | `Tools/scripts/hotpath-policy.sh` (covers new `CortexReFIT`), `Tools/scripts/render-policy.sh` (if harness touches render code) |
| **Quick run command** | `swift test --filter CortexReFIT` |
| **Full suite command** | `swift test && uv run --project Decoder --extra dev pytest && Tools/scripts/hotpath-policy.sh` |
| **Estimated runtime** | ~30–90 s (Swift unit + Python gain-fit); BPS bench is a separate short-budget CI smoke |

---

## Sampling Rate

- **After every task commit:** Run `swift test --filter CortexReFIT` (or the touched package's filter / `pytest` for Decoder/ tasks)
- **After every plan wave:** Run the full suite command above
- **Before `/gsd-verify-work`:** Full suite green + `hotpath-policy.sh` green + BPS smoke (`refit_bps ≥ raw_bps` on fixed seed) green
- **Max feedback latency:** ~90 s

---

## Per-Task Verification Map

> Task IDs (`07-PP-TT`) are assigned when plans are written; rows below are keyed by requirement/SC so coverage is provable now. (Threat refs filled by the planner's `<threat_model>`.)

| Requirement / SC | Validated behavior | Test Type | Automated Command | Status |
|---|---|---|---|---|
| REFIT-01 | Kalman step matches reference `numpy` constant-gain impl on fixed inputs (single step + ≥50-tick trajectory) | unit | `swift test --filter CortexReFIT` | ⬜ pending |
| REFIT-01 | Steady-state gain valid: closed-loop `A_obs(I−K_obs·H_obs)` Schur-stable (`max|λ|<1`); DARE solved on **observable [v,a] block** (full 6×6 would raise) | unit | `uv run --project Decoder --extra dev pytest -k gain` | ⬜ pending |
| REFIT-02 | Intent-rotation: outside r_acq → dir==cursor→target, mag==‖z‖; inside r_acq → z unchanged; no target → z unchanged; zero-velocity guard | unit | `swift test --filter CortexReFIT` | ⬜ pending |
| REFIT-03 / SC#2 | 3-way ablation on identical seed-locked Indy replay; `refit_bps ≥ raw_bps`; S&M-2004 effective-width TP | integration | BPS bench (fixed seed) + CI smoke | ⬜ pending |
| REFIT-03 | Determinism: two harness runs on same seed → bit-identical JSON | integration | BPS bench ×2, diff JSON | ⬜ pending |
| SC#3 | Filter-step tail latency negligible vs 20 ms budget; on existing decoder pthread (no new thread) | bench | `LatencyHistogram` over filter step, n≥10 000 | ⬜ pending (M5-Pro corroborating) |
| SC#3 | Hot-path discipline: no `dispatch_async`/`lazy var`/locks/`Foundation` in `CortexReFIT` | static | `Tools/scripts/hotpath-policy.sh` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Packages/CortexReFIT/Tests/CortexReFITTests/` — unit-test target for the Kalman step + intent-rotation (REFIT-01/02)
- [ ] `Decoder/tests/test_kalman_gain.py` — DARE solve + Schur-stability + gain-shape assertions (REFIT-01, D-15)
- [ ] BPS bench executable target (mirrors `CortexDecoderBench`) — 3-way ablation harness (REFIT-03)
- [ ] `hotpath-policy.sh` coverage extended to `CortexReFIT` (SC#3)

*Existing SwiftPM + pytest infrastructure covers the frameworks; the above are the new test surfaces this phase adds.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Canonical filter tail-latency on iPad-Pro-M4 | SC#3 | Hardware-measurement device checkpoint — Mac/M5-Pro number is corroborating only (project device-gating culture) | Run the filter-step `LatencyHistogram` bench on iPad-M4; record p50/p99/max; annotate device. Deferred (not an automated-coverage gap). |

*All other phase behaviors have automated, deterministic verification.*

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter (set by `/gsd-validate-phase 7` post-execution)

**Approval:** pending
