---
plan: 05-05
phase: 05-ndt1-coreml-deployment-with-ane-residency-verified
status: complete
requirements: [DEC-08]
checkpoint: human-verify (resolved via M2-corroborating capture, 2026-06-21)
---

# Plan 05-05 Summary — iPad HUMAN-UAT runbook + on-device capture (DEC-08)

## What shipped

The iPad HUMAN-UAT runbook (`05-HUMAN-UAT.md`) and DEC-08 disposition (`05-placement-evidence.md`) were authored (Tasks 1–2, commits `f139e57`, `6b10b14`), then the blocking `checkpoint:human-verify` (Task 3) was **resolved by an on-device capture** — on an **iPad Air 11-inch (M2), iPadOS 18.7.8** (the user's always-available hardware; an iPad Pro **M4** was not available — M4 access is rare/borrowed). Captured via the Xcode Core ML Performance Report (runbook option b). The M2 is a valid **corroborating tier** (same M2-class Neural Engine as the iPad Pro M2; iPadOS 18 runs Core ML profiling fine).

## Measured verdict (iPad Air M2, `computeUnits=.all`, n=120 predictions)

| Claim | Result |
|-------|--------|
| ANE **eligibility** (SC#1 precondition) | **226/226 ops `neuralEngine ∈ supported`, 0 CPU-only** — confirmed on real iPad silicon (independently reproduces the Plan-02 Mac `MLComputePlan` verdict) |
| Runtime **placement** (SC#1) | **226/226 `preferred == cpu` (0 ANE, 0 GPU)** — the 1.29M-param model CPU-placed: the Risk-#1 scale trap, now reproduced on a real iPad (not just the M5 Pro Mac) |
| **Latency** (SC#4) | **p50 ≈ 0.20 ms, p99 ≈ 0.51 ms** (max 8.94 ms cold) — **<2 ms budget met ~4×, on CPU** |

## The reframe (the load-bearing decision)

The honest-fallback scenario that `05-placement-evidence.md` explicitly anticipated **materialized**: the model is fully ANE-eligible but the CoreML scheduler keeps it on CPU at this scale, on **every** device/config/tool tested (M5 Pro under `.cpuAndNeuralEngine` per 05-02 + in-proc bench 05-04; iPad Air M2 under `.all` now). Public API cannot force ANE placement (`_ANEClient` is forbidden — App Store rejection), so "100% ANE runtime placement" is not achievable at 1.29M params within constraints.

Per the user's decision (2026-06-21), **SC#1 / DEC-08 was reframed** from "100% ANE runtime placement" to the measured, defensible truth:

> **100% ANE-eligible (226/226, 0 CPU-only) + CPU-scheduled at this model scale (measured, reported honestly) + <2 ms p99 regardless of placement.**

The core value — sub-25 ms glass-to-glass, <2 ms decoder — is **unaffected**: the budget is met with ~4× margin even on CPU. Reframed across ROADMAP (goal, SC#1, SC#4, title), REQUIREMENTS (DEC-06/08/11), and PROJECT.md (headline, decisions). Canonical iPad-M4 capture remains an optional future datapoint (M4 + iPadOS 26 *might* schedule differently, but the scale trap is consistent across M5 Pro + M2).

## Key files

- `05-HUMAN-UAT.md` — both tests recorded (eligibility PASS, placement MEASURED-CPU, latency PASS-corroborating); status `resolved`.
- `05-placement-evidence.md` — Result flipped PENDING → CAPTURED; eligibility/placement split + scale-trap narrative retained; reframe recorded.
- `05-perf-report-ipad-m2.json` (980 KB) — raw Xcode Performance Report (the reviewer artifact).
- `runtime_plan_ipad.json` — distilled per-op `preferred`/`supported` verdict (iPad complement of the Mac `runtime_plan.json`).

## Deviations

1. **Device: iPad Air M2, not iPad Pro M4** — user's available hardware; recorded as M2-corroborating, canonical M4 left optional. No fabrication.
2. **SC#1/DEC-08 reframed** (the big one) — placement is CPU, not ANE, at this scale; claim changed to measured truth (eligible + CPU-at-scale + <2 ms). User-approved.

## Self-check: PASSED

- Both staged docs authored + committed; checkpoint resolved by real on-device measurement (no fabricated placement).
- Measured numbers transcribed from `05-perf-report-ipad-m2.json` / `runtime_plan_ipad.json` (226 CPU-preferred, 226 ANE-eligible, p99 0.51 ms).
- Reframe applied consistently across ROADMAP / REQUIREMENTS / PROJECT / evidence / UAT.
- `milestone: v1.0` preserved.
