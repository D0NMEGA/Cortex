---
phase: 6
slug: cametaldisplaylink-120hz-renderer-with-30-30-webgrid
status: validated
nyquist_compliant: true
wave_0_complete: true
created: 2026-06-21
validated: 2026-06-22
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
| RENDER-01 | grep + build; iOS delegate fires | callback present | `CAMetalDisplayLink` used; iOS Metal path has no `CADisplayLink` | structural + unit | CI log | ✅ green |
| RENDER-02 | callback-rate count (Mac ProMotion) | 60s | sustained ≈120Hz | manual/bench | `soak_log.json` | ✅ green¹ |
| RENDER-03 | plist build-time check | 1 (gate) | `CADisableMinimumFrameDurationOnPhone == true` | structural | CI log | ✅ green |
| RENDER-04 | grep + frame-capture | compute pass | compute kernel writes ~900-cell grid | structural + manual | capture note | ✅ green |
| RENDER-05 | `gpuStartTime/EndTime` or counter buffer | n ≥ 10k frames | p99 ≤ 0.4ms (M4 canonical; M5 Pro annotated) | bench | `gpu_time_hist.json` | ✅ green¹ |
| RENDER-06 | grep + buffer audit | all CPU buffers | `storageModeShared`; no staging blit | structural | CI log | ✅ green |
| RENDER-07 | grep + code review | render path | `dispatch_semaphore(value:1)`; `maximumDrawableCount=2` | structural | CI log | ✅ green |
| RENDER-08 | grep + macOS run | callback | `NSView/NSScreen.displayLink`; no Catalyst | structural + manual | CI log + run | ✅ green |
| RENDER-09 | scheme env check + screenshot | 1 | `MTL_HUD_ENABLED=1` in scheme; HUD visible | structural + manual | scheme + screenshot | ✅ green² |
| SC#4 (soak) | 60s soak (Mac ProMotion) | 120·60 frames | zero intervals > 8.33ms (ε bound) | manual/bench | soak log | ✅ green¹ |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

¹ Green at the **M5 Pro corroborating-canonical tier** (D-11): RENDER-05 p99=0.1618 ms (n=10,000); SC#4/RENDER-02 soak 243,724 frames / 0 over-budget (offscreen-throughput). The iPad Pro M4 **canonical** capture (on-panel 120 Hz refresh + on-device p99) is deferred to `06-HUMAN-UAT.md` (D-12, never-auto-approve) — recorded under Manual-Only, **not** a Nyquist gap.
² Structural env-gate green (`MTL_HUD_ENABLED=1`; render-policy.sh); the on-screen HUD **visual** is Manual-Only (an overlay can't be asserted headlessly).

---

## Wave 0 Requirements

- [x] GPU-time measurement bench target (dedicated executable; `gpuStartTime/EndTime` histogram) — no off-the-shelf framework; built in-phase → `Apps/CortexRenderBench/GPUTimeHistogram.swift` (+ `FrameSoak.swift`)
- [x] Structural grep-gate script (`Tools/scripts/render-policy.sh`) with a negative-control self-test (mirrors Phase-3 `hotpath-policy.sh`) → present + executable; clean run EXIT 0, `--self-test` EXIT 0
- [x] `swift test` target in `Packages/CortexRender` (integrator/seam unit tests) → 19/19 pass (WebgridParams, CursorIntegrator, VelocityRing, LissajousProducer)

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

- [x] All tasks have an `<automated>` verify or a Wave 0 dependency
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers the render-gate + GPU bench
- [x] No watch-mode flags
- [x] Feedback latency < 30s (structural/unit)
- [x] `nyquist_compliant: true` set in frontmatter (by planner after task→requirement mapping)

**Approval:** ✅ validated 2026-06-22 — audit re-ran the full automated suite green; see Validation Audit below.


---

## Plan -> Requirement Mapping (set by planner 2026-06-21)

The phase was decomposed into 6 plans across 6 waves. Each RENDER requirement is satisfied by the
plan(s) below; every requirement's validation row above is covered by an automated `<verify>` in the
mapped plan, with the live-hardware rows handled by the Mac-corroborating bench (Plan 05) and the
deferred iPad-M4 capture (Plan 06, never-auto-approve checkpoint).

| Requirement | Plan(s) | Task verify (automated) | Tier |
|-------------|---------|-------------------------|------|
| RENDER-01 (CAMetalDisplayLink iOS, no CADisplayLink on iOS Metal path) | 06-03 (impl), 06-04 (grep-gate) | swift build CortexRender; render-policy.sh asserts CAMetalDisplayLink present + forbids CADisplayLink in iOS adapter | CI-structural |
| RENDER-02 (120Hz) | 06-03 (CAFrameRateRange 120), 06-05 (Mac soak), 06-06 (iPad canonical, deferred) | swift build; FrameSoak 60s; UAT (deferred) | structural + Mac-corroborating + iPad-deferred |
| RENDER-03 (CADisableMinimumFrameDurationOnPhone=YES) | 06-04 | xcodegen + grep project.yml key==true; CI plist gate | CI-structural |
| RENDER-04 (compute-shader 30x30 grid) | 06-01 (kernel), 06-04 (grep-gate), 06-05 (measures real kernel) | swift test/build; render-policy.sh `kernel void webgrid` | CI-structural |
| RENDER-05 (GPU <=0.4ms) | 06-05 (gpuStartTime/EndTime histogram), 06-06 (iPad canonical, deferred) | xcodebuild CortexRenderBench; p99 vs 0.4ms in 06-render-evidence.md | Mac-corroborating + iPad-deferred |
| RENDER-06 (storageModeShared zero-copy) | 06-01 (encoder), 06-04 (grep-gate) | swift build; render-policy.sh storageModeShared present + storageModeManaged forbidden | CI-structural |
| RENDER-07 (dispatch_semaphore value:1, maximumDrawableCount=2) | 06-03 (FrameSynchronizer), 06-04 (grep-gate) | swift build; render-policy.sh asserts value:1 + maximumDrawableCount=2 | CI-structural |
| RENDER-08 (NSView/NSScreen.displayLink macOS, no Catalyst) | 06-03 (Mac adapter), 06-04 (grep-gate) | swift build; render-policy.sh `displayLink(target:` present | CI-structural |
| RENDER-09 (MTL_HUD_ENABLED=1 scheme env) | 06-04 (scheme env), 06-05 (HUD note) | grep project.yml MTL_HUD_ENABLED (>=2); HUD screenshot on live run | CI-structural + manual |

Supporting decisions (no RENDER id; validated by their plans' tests): D-03 velocity seam + D-04
integrator clamp/NaN-reject + D-05 Lissajous determinism -> 06-02 (`swift test` integrator + ring +
determinism cases); D-06..D-09 visuals -> 06-01 kernel; D-10 three tiers -> 06-04 (tier 1) + 06-05
(tier 2 Mac) + 06-06 (tier 3 iPad, deferred); D-11 SC reframe -> 06-06 (sign-off-gated);
D-12 never-auto-approve UAT -> 06-06 (autonomous:false checkpoint).

**Wave 0 coverage:** the render-policy.sh structural gate + negative-control self-test (06-04) and the
GPU-time bench (06-05) are the in-phase-built validation infrastructure; `swift test` in
Packages/CortexRender (06-01/06-02) is the unit surface. nyquist_compliant set true: every task has an
automated `<verify>` (or, for the 06-06 Task-1 checkpoint:decision, a human-gate by design), and no 3
consecutive tasks lack an automated verify.

---

## Validation Audit 2026-06-22

This audit re-ran the full automated validation surface against the live tree (not a paper review):

| Check | Command | Result |
|-------|---------|--------|
| Render package unit tests | `swift test --package-path Packages/CortexRender` | **19/19 pass** (4 suites) |
| Structural render gate | `bash Tools/scripts/render-policy.sh` | **EXIT 0** (9 required-present + 3 forbidden-absent) |
| Gate negative-control | `bash Tools/scripts/render-policy.sh --self-test` | **EXIT 0** (every strip/inject bites; macOS scoping control passes) |
| CI wiring | `.github/workflows/ci.yml` | render-policy gate + `--self-test` + `project.yml`/`Info.plist` plist gate all wired (lines 213–237) |
| GPU-time bench artifact | `gpu_time_hist.json` | p99=0.1618 ms, n=10,000 (M5 Pro corroborating) |
| Soak artifact | `soak_log.json` | 243,724 frames / 0 over-budget (M5 Pro corroborating) |

| Metric | Count |
|--------|-------|
| Requirements audited | 9 RENDER + SC#4 (10) |
| COVERED (automated, green) | 10 |
| PARTIAL | 0 |
| MISSING (gaps) | 0 |
| Gaps filled this audit | 0 (none to fill) |
| Manual-only (un-automatable, already recorded) | iPad-M4 canonical GPU (RENDER-05/SC#2) · iPad-M4 on-panel 120 Hz (RENDER-02/SC#4) · MTL_HUD visual (RENDER-09) |

**Verdict: Nyquist-compliant.** Every requirement has an automated verification that exists and runs
green at its achievable tier (CI-structural / unit / M5-Pro-corroborating bench). The three Manual-Only
items are legitimately un-automatable on a headless runner (physical iPad Pro M4 ProMotion panel; an
on-screen HUD overlay) and are tracked in `06-HUMAN-UAT.md` under the never-auto-approve D-12 gate —
deferred canonical captures, **not** coverage gaps. Per-Task statuses were reconciled from the
plan-time `⬜ pending` seed to verified-green: this VALIDATION.md was authored as a contract on
2026-06-21 and not updated post-execution; `06-VERIFICATION.md` (2026-06-22) independently corroborates
the same green state. No new tests were generated (nothing to fill); no implementation files touched.
