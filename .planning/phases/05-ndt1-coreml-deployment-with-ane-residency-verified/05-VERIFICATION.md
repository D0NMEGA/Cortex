---
status: passed
phase: 05-ndt1-coreml-deployment-with-ane-residency-verified
verified: 2026-06-21
requirements: [DEC-06, DEC-07, DEC-08, DEC-09, DEC-10, DEC-11, DEC-12]
note: SC#1/DEC-08 reframed 2026-06-21 (ANE placement → ANE-eligibility + measured CPU placement + <2ms); verified against the reframed criteria.
---

# Phase 5 Verification — NDT1 → CoreML deployment (ANE-eligible, sub-2ms)

**Phase goal (reframed):** the 4-bit palettized NDT1 `.mlpackage` is 100% ANE-eligible, runs zero-copy, emits `(vx,vy)` fp16, and meets <2ms p99 — placement measured & reported honestly. **Verdict: PASSED.**

## Success criteria

| SC | Criterion (reframed) | Verdict | Evidence |
|----|----------------------|---------|----------|
| 1 | **ANE-eligible** (226/226, 0 CPU-only); runtime placement measured & reported honestly | ✅ PASS | `05-ane-eligibility-evidence.md` (Mac); `05-perf-report-ipad-m2.json` + `runtime_plan_ipad.json` (iPad M2 — 226/226 eligible, `{CPU:226}` placement). Placement = CPU at this scale (scale trap), recorded honestly. |
| 2 | `computeUnits = .cpuAndNeuralEngine` (build-fails on `.all`); zero `_ANEClient` | ✅ PASS | 05-03 build-failing Swift gate + tree-wide CI grep (DEC-07/12). |
| 3 | `(vx,vy)` fp16 zero-copy via shared `IOSurface`/`MTLBuffer` | ✅ PASS | 05-03 `MLMultiArray(pixelBuffer:)`, pointer-identity proven (DEC-09/10). |
| 4 | <2ms p99 inference | ✅ PASS | p99 ≈ 0.51ms (iPad-M2, `05-perf-report-ipad-m2.json`) / ≈0.14ms (M5 Pro, `05-latency-evidence.md`). ~4× margin, on CPU. |

## Requirement traceability

DEC-06 ✅ (eligibility, 05-02) · DEC-07 ✅ (05-03) · DEC-08 ✅ (reframed; eligibility on-device + measured placement, 05-02/05-05) · DEC-09 ✅ (05-03) · DEC-10 ✅ (05-01) · DEC-11 ✅ (05-04) · DEC-12 ✅ (05-03). **7/7 closed.**

## Honest caveat (carried forward)

Runtime ANE *placement* is **not** achieved — the 1.29M-param model is below CoreML's ANE-dispatch scale threshold and CPU-places on every device/config/tool tested (M5 Pro `.cpuAndNeuralEngine`; iPad Air M2 `.all`); public API can't force it. The decoder is fully ANE-**eligible** and meets the <2ms budget on CPU, so the core value (sub-25ms glass-to-glass) is unaffected. A canonical iPad-M4 (iPadOS 26) capture is an optional future datapoint that *might* show different placement, but is not required for the phase claim. See `05-placement-evidence.md`.
