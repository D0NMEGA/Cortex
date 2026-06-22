---
phase: 6
slug: cametaldisplaylink-120hz-renderer-with-30-30-webgrid
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-21
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from `06-RESEARCH.md` § "Validation Architecture (Nyquist)". The
> Per-Task map is keyed by **requirement** here; the planner maps tasks→requirements
> at plan time and the executor fills task IDs/status.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing / XCTest (`swift test`) + CI grep-gates (`Tools/scripts/*.sh`, shell) + a GPU-time measurement bench (dedicated executable, mirrors Phase-5 `CortexDecoderBench`) |
| **Config file** | `project.yml` (XcodeGen — single source of truth for targets/scheme env); CI workflow on `macos-15` + Xcode 26.3 |
| **Quick run command** | `swift test --package-path Packages/CortexRender` + the structural grep-gates (`Tools/scripts/render-policy.sh` or equivalent) |
| **Full suite command** | grep-gates + `swift test` + `xcodebuild` (CortexiOS/CortexMac schemes, `CODE_SIGNING_ALLOWED=NO`) + the GPU-time bench + the 60s soak (Mac ProMotion) |
| **Estimated runtime** | structural gates < 10s; `swift test` < 30s; the 60s sustained-120Hz soak is 60s by definition |

---

## Sampling Rate

- **After every task commit:** Run the quick command (grep-gates + `swift test` for the package touched)
- **After every plan wave:** Run the full suite (gates + `swift test` + `xcodebuild` build)
- **Before `/gsd-verify-work`:** Full suite green; GPU-time bench + 60s soak captured on M5 Pro ProMotion (corroborating-canonical, D-11)
- **Max feedback latency:** < 30s for structural/unit; the soak (60s) and on-device capture are end-of-wave/manual

---

## Per-Task Verification Map

> Task IDs are assigned by the planner. Rows below are the **requirement-level**
> validation contract (from RESEARCH.md); the planner attaches each to the task(s)
> that satisfy it and sets Wave/Status.

| Requirement | Validation method | Sampling / N | Pass condition | Test Type | Artifact | Status |
|-------------|-------------------|--------------|----------------|-----------|----------|--------|
| RENDER-01 | grep + build; iOS delegate fires | callback present | `CAMetalDisplayLink` used; iOS Metal path has no `CADisplayLink` | structural + unit | CI log | ⬜ pending |
| RENDER-02 | callback-rate count (Mac ProMotion) | 60s | sustained ≈120Hz | manual/bench | `frame_pacing.json` | ⬜ pending |
| RENDER-03 | plist build-time check | 1 (gate) | `CADisableMinimumFrameDurationOnPhone == true` | structural | CI log | ⬜ pending |
| RENDER-04 | grep + frame-capture | compute pass | compute kernel writes ~900-cell grid | structural + manual | capture note | ⬜ pending |
| RENDER-05 | `gpuStartTime/EndTime` or counter buffer | n ≥ 10k frames | p99 ≤ 0.4ms (M4 canonical; M5 Pro annotated) | bench | `gpu_time_hist.{json,png}` | ⬜ pending |
| RENDER-06 | grep + buffer audit | all CPU buffers | `storageModeShared`; no staging blit | structural | CI log | ⬜ pending |
| RENDER-07 | grep + code review | render path | `dispatch_semaphore(value:1)`; `maximumDrawableCount=2` | structural | CI log | ⬜ pending |
| RENDER-08 | grep + macOS run | callback | `NSView/NSScreen.displayLink`; no Catalyst | structural + manual | CI log + run | ⬜ pending |
| RENDER-09 | scheme env check + screenshot | 1 | `MTL_HUD_ENABLED=1` in scheme; HUD visible | structural + manual | scheme + screenshot | ⬜ pending |
| SC#4 (soak) | 60s soak (Mac ProMotion) | 120·60 frames | zero intervals > 8.33ms (ε bound) | manual/bench | soak log | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] GPU-time measurement bench target (dedicated executable; `gpuStartTime/EndTime` histogram) — no off-the-shelf framework; built in-phase
- [ ] Structural grep-gate script (`Tools/scripts/render-policy.sh`) with a negative-control self-test (mirrors Phase-3 `hotpath-policy.sh`)
- [ ] `swift test` target in `Packages/CortexRender` (integrator/seam unit tests)

*Swift Testing/XCTest + the CI grep-gate harness already exist project-wide; this phase adds the render-specific gate + GPU bench.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Sustained 120Hz, no dropped frames over 60s | RENDER-02 / SC#4 | Refresh rate can't be proven in headless CI; needs a real 120Hz ProMotion panel | Run the soak on M5 Pro MacBook Pro ProMotion (corroborating-canonical, D-11); log every interval > 8.33ms |
| GPU compute time ≤ 0.4ms | RENDER-05 / SC#2 | Needs live GPU timestamps on Apple Silicon | M5 Pro ProMotion now (annotated); iPad Pro M4 canonical capture deferred per `06-HUMAN-UAT.md` (D-12) |
| `MTL_HUD_ENABLED=1` HUD visible (P95 frame time, drawable-wait, encoder-time) | RENDER-09 | HUD is an on-screen overlay | Launch the scheme; screenshot the HUD |
| iPad Pro M4 canonical ≤0.4ms + 60s 120Hz capture | RENDER-05 / SC#2 / SC#4 | Rare hardware; load-bearing credibility number | `06-HUMAN-UAT.md` runbook — **presented as a checkpoint, never auto-approved** (D-12); deferred optional/future |

*The phase completes on the Mac-corroborating tier; the iPad-Pro-M4 capture is deferred (D-11/D-12).*

---

## Validation Sign-Off

- [ ] All tasks have an `<automated>` verify or a Wave 0 dependency
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers the render-gate + GPU bench
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s (structural/unit)
- [ ] `nyquist_compliant: true` set in frontmatter (by planner after task→requirement mapping)

**Approval:** pending
