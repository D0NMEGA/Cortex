---
phase: 5
slug: ndt1-coreml-deployment-with-ane-residency-verified
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-21
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Phase 5 spans **two** test surfaces: the Python `Decoder/` subsystem (conversion, velocity head, ANE op-eligibility via coremltools `MLComputePlan`) and the Swift `CortexDecoder` package (compute-units config, zero-copy input, `(vx,vy)` output, in-process latency). Runtime ANE *placement* (DEC-08) and on-device p99 (DEC-11) are **iPad-M4 manual-only** per the project's THREAD-02/SC#1 precedent.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (Python)** | pytest 8.x + pytest markers (`slow`) — `Decoder/` |
| **Framework (Swift)** | Swift Testing / XCTest — `Packages/CortexDecoder` |
| **Config file** | `Decoder/pyproject.toml` (+ `ruff.toml`); `Packages/CortexDecoder/Package.swift` |
| **Quick run command** | `uv sync --project Decoder --extra dev && uv run --project Decoder pytest -q -m "not slow"` |
| **Full suite command (Python)** | `uv run --project Decoder pytest -q` (includes slow convert/palettize/compute-plan tests) |
| **Full suite command (Swift)** | `swift test --package-path Packages/CortexDecoder` |
| **Estimated runtime** | Python quick ~10s; Python full ~60s (builds real `.mlpackage` + compiles `.mlmodelc`); Swift ~15s |

> **Env reminder (project memory):** always `uv sync --project Decoder --extra dev` first — pytest/ruff are an optional-dependencies extra; bare `uv run pytest` fails with a misleading `No module named numpy`. coremltools is locked at **9.0**. ruff `BLE` gate forbids bare/blind `except`.

---

## Sampling Rate

- **After every task commit:** Run the quick command (Python `-m "not slow"`, or `swift test` for Swift-only tasks).
- **After every plan wave:** Run the full Python suite **and** the Swift suite.
- **Before `/gsd-verify-work`:** Both suites green; the `MLComputePlan` op-eligibility artifact (`runtime_plan.json`) regenerated.
- **Max feedback latency:** ~60 seconds (full Python suite, dominated by the real convert→compile→compute-plan path).

---

## Per-Task Verification Map

> Concrete task IDs are assigned by the plans (`05-NN-PLAN.md`). Each task must carry an `<automated>` verify command mapping to the requirement below, OR be listed under Manual-Only with a HUMAN-UAT runbook reference. Representative mapping:

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-NN-XX | NN | — | DEC-10 | T-05-* / — | only self-produced `.mlpackage` loaded | unit (py) | `uv run --project Decoder pytest -q -k velocity_head` | ❌ W0 | ⬜ pending |
| 05-NN-XX | NN | — | DEC-06 | — | op-eligibility scan, no untrusted model | unit (py) | `uv run --project Decoder pytest -q -k compute_plan` | ❌ W0 | ⬜ pending |
| 05-NN-XX | NN | — | DEC-07 | — | `.cpuAndNeuralEngine` (not `.all`) | unit (swift) | `swift test --package-path Packages/CortexDecoder` | ❌ W0 | ⬜ pending |
| 05-NN-XX | NN | — | DEC-09 | — | zero-copy, pointer identity | unit (swift) | `swift test --package-path Packages/CortexDecoder` | ❌ W0 | ⬜ pending |
| 05-NN-XX | NN | — | DEC-12 | — | no `_ANEClient` private API | grep (CI) | `! grep -rn "_ANEClient" Packages Apps Decoder` | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Decoder/tests/test_velocity_head.py` — stubs for DEC-10 (output shape `(…,2)` fp16, ridge fit, parity)
- [ ] `Decoder/tests/test_ane_compute_plan.py` — stubs for DEC-06 (`MLComputePlan` op-eligibility scan + einsum op disposition)
- [ ] `Packages/CortexDecoder/Tests/CortexDecoderTests/` — XCTest target (does not yet exist; the package is an 8-line stub) for DEC-07/DEC-09/DEC-10 Swift-side
- [ ] coremltools 9.0 + torch 2.12.1 already locked (Phase 4) — no new install

*Existing Decoder pytest infrastructure covers the Python surface; the Swift test target is net-new Wave-0 scaffolding.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 100% ANE runtime **placement** (`.preferred == neuralEngine`, zero CPU/GPU) | DEC-08 / SC#1 | The ~1.29M-param model is below the ANE runtime-placement scale threshold on Mac (research Decision 2 — the meridian scale trap); canonical placement requires the iPad-M4 mobile scheduler. Instruments/Performance Report are GUI tools. | `05-HUMAN-UAT.md` runbook: connect iPad Pro M4 → Instruments → Core ML template (or Xcode `.mlpackage` Performance Report, or on-device `MLComputePlan`) → confirm 100% `preferred == neuralEngine` → commit trace/screenshot + `runtime_plan_ipad.json` |
| Inference latency <2ms p99 over 10k passes | DEC-11 / SC#4 | Canonical claim is on iPad-M4 hardware; Python `predict()` timing is IPC-dominated (research Decision 5). | `05-HUMAN-UAT.md`: run the in-process Swift bench on the connected iPad M4 → commit `latency_histogram.{json,png}` with device + per-op placement annotation |

> Mac-side corroborating measurements (eligibility scan, M5 latency) **are** automated and run in CI; only the iPad-M4 canonical artifacts are manual.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies (or a Manual-Only entry above)
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (Swift test target scaffolding)
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter (after planner maps every task)

**Approval:** pending
