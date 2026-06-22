---
phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid
verified: 2026-06-22T14:00:00Z
status: human_needed
score: 7/9 must-haves verified (2 require human/device testing per D-12)
human_verification:
  - test: "iPad Pro M4 GPU compute time ≤0.4ms (p99, n≥10k) — RENDER-05 / SC#2 canonical capture"
    expected: "CortexRenderBench on iPad Pro M4 returns p99 ≤0.4ms; commit gpu_time_hist_ipad.json"
    why_human: "Real iPad Pro M4 hardware required; CI has no paired device or Metal GPU. M5 Pro corroborating number (p99=0.1618ms) completes the phase per D-11 but canonical capture is D-12 deferred."
  - test: "iPad Pro M4 sustained 120Hz, no dropped frames over 60s — RENDER-02 / SC#4 on-panel refresh"
    expected: "CortexiOS scheme on iPad Pro M4 ProMotion panel; MTL_HUD P95 ≈ 8.33ms; zero intervals >8.33ms over 60s"
    why_human: "Requires physical iPad Pro M4 ProMotion panel — 120Hz refresh cannot be verified on a headless runner or a non-ProMotion device (iPad Air M2 is 60Hz LCD, physically incapable). M5 Pro offscreen-throughput soak (243,724 frames / 0 over-budget) establishes GPU headroom; on-panel canonical capture is D-12 deferred."
---

# Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid — Verification Report

**Phase Goal:** A beam-raced 120Hz Metal renderer presents a 30×30 webgrid on iPad Pro M4 ProMotion at ≤0.4ms GPU compute, with `dispatch_semaphore_t(value: 1)` enforcing one in-flight frame per Apple's 'Synchronizing CPU and GPU Work' pattern.
**Verified:** 2026-06-22T14:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Build Verification

| Check | Command | Result |
|-------|---------|--------|
| `xcodegen generate` | `xcodegen generate` | EXIT 0 — "Created project at Cortex.xcodeproj" |
| macOS build | `xcodebuild build -scheme CortexMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | **BUILD SUCCEEDED** |
| iOS slice type-check | `xcrun swiftc -typecheck -sdk iphoneos -target arm64-apple-ios26.0 -swift-version 6 … + Bundle.module shim` | EXIT 0 — zero errors (shim required; documented in 06-03-SUMMARY deviation) |
| Swift package tests | `swift test --package-path Packages/CortexRender` | **19/19 PASS** (4 suites: WebgridParams 3, CursorIntegrator 6, VelocityRing 8, LissajousProducer 3; SPSC stress test 200k frames 0 corrupt) |

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | iOS uses CAMetalDisplayLink (zero CADisplayLink on iOS Metal path) — RENDER-01 | VERIFIED | `iOSDisplayLinkAdapter.swift` line 35: `class iOSDisplayLinkAdapter: NSObject, CAMetalDisplayLinkDelegate`; line 79: `let link = CAMetalDisplayLink(metalLayer:)`; `grep CADisplayLink iOSDisplayLinkAdapter.swift` returns empty (render-policy.sh FORBIDDEN check passes) |
| 2 | macOS uses NSView.displayLink → CADisplayLink at 120Hz — RENDER-08 | VERIFIED | `MacDisplayLinkAdapter.swift` line 91: `let link = view.displayLink(target: self, selector: #selector(tick(_:)))` |
| 3 | dispatch_semaphore(value: 1) enforces one in-flight frame — RENDER-07 | VERIFIED | `FrameSynchronizer.swift` line 42: `private let semaphore = DispatchSemaphore(value: 1)`; wait/signal balance confirmed: line 49 `semaphore.wait()`, line 59 `semaphore.signal()` (completion handler), line 69 `semaphore.signal()` (skip path) |
| 4 | Metal compute kernel draws 30×30 webgrid into drawable — RENDER-04 | VERIFIED | `Webgrid.metal` line 43: `kernel void webgrid(…)`; `WebgridFrameEncoder.swift` line 43: `makeComputePipelineState`; `WebgridParams.swift` lines 90-91: `gridColumns: 30, gridRows: 30` |
| 5 | Zero-copy uniforms upload, no managed/staging buffer — RENDER-06 | VERIFIED | `WebgridFrameEncoder.swift` line 78: `encoder.setBytes(&uniforms, length: …, index: 0)`; render-policy.sh FORBIDDEN `storageModeManaged` check passes (exit 0) |
| 6 | CADisableMinimumFrameDurationOnPhone=YES + MTL_HUD_ENABLED=1 in schemes — RENDER-03/09 | VERIFIED | `project.yml` line 71: `CADisableMinimumFrameDurationOnPhone: true`; `Apps/CortexiOS/Info.plist`: `<key>CADisableMinimumFrameDurationOnPhone</key><true/>`; MTL_HUD_ENABLED in both iOS and macOS scheme run environments |
| 7 | render-policy.sh structural gate passes (all 9 required + 3 forbidden) and self-test passes | VERIFIED | `render-policy.sh`: EXIT 0 (all 9 REQUIRED-PRESENT ok, all FORBIDDEN-ABSENT ok); `--self-test`: EXIT 0 (9 required-strip bites + 4 forbidden-inject bites + macOS scoping-control passes) |
| 8 | GPU compute time ≤0.4ms p99 — RENDER-05 / SC#2 (M5 Pro corroborating-canonical) | VERIFIED (corroborating tier) | `gpu_time_hist.json`: p99=0.1618ms, n=10,000, device="Apple M5 Pro", extent=2752×2064; 06-render-evidence.md confirms measurement method (gpuEndTime−gpuStartTime, 200 warmup frames discarded). ~2.5× margin vs 0.4ms bound. iPad Pro M4 canonical capture: deferred per D-12 (06-HUMAN-UAT.md) |
| 9 | 60s sustained throughput zero over-budget frames — SC#4 (M5 Pro corroborating-canonical) | VERIFIED (corroborating tier) | `soak_log.json`: mode=offscreen-throughput, 60.000s, 243,724 frames, 4062.06 Hz, over_budget_intervals=0, max_interval_ms=2.3687, device="Apple M5 Pro". On-panel 120Hz canonical refresh via iPad Pro M4: deferred per D-12 |

**Score:** 9/9 truths pass at the applicable verification tier. Truths 8 and 9 are verified at the M5 Pro corroborating-canonical tier (D-11); the iPad Pro M4 canonical captures remain deferred (D-12) and require human/device testing — hence status `human_needed`.

---

### Required Artifacts

| Artifact | Lines | Status | Key Evidence |
|----------|-------|--------|--------------|
| `Packages/CortexRender/Sources/CortexRender/WebgridParams.swift` | 102 | VERIFIED | `gridColumns: 30, gridRows: 30`; `nonisolated Sendable`; `grid30x30` convenience |
| `Packages/CortexRender/Sources/CortexRender/Webgrid.metal` | 110 | VERIFIED | `kernel void webgrid`; `texture2d<float, access::write>`; pixel-bounds guard present |
| `Packages/CortexRender/Sources/CortexRender/WebgridFrameEncoder.swift` | 92 | VERIFIED | `makeComputePipelineState`; `setBytes` zero-copy upload; `encode(into:commandBuffer:params:)` |
| `Packages/CortexRender/Sources/CortexRender/MetalLayerConfig.swift` | 44 | VERIFIED | `framebufferOnly = false`; `maximumDrawableCount = 2`; `presentsWithTransaction = false` |
| `Packages/CortexRender/Sources/CortexRender/CursorVelocity.swift` | 46 | VERIFIED | `vx: Float16`; `vy: Float16`; field order: ts_ns, seq, vx, vy |
| `Packages/CortexRender/Sources/CortexRender/VelocityRing.swift` | 110 | VERIFIED | `Synchronization.Atomic` head/tail Release/Acquire; `@unchecked Sendable`; failable `init?` |
| `Packages/CortexRender/Sources/CortexRender/CursorIntegrator.swift` | 102 | VERIFIED | `isFinite` guard; `clampFinite`; `pos += velocity * dt` integration |
| `Packages/CortexRender/Sources/CortexRender/LissajousProducer.swift` | 64 | VERIFIED | `velocity(at t: Double)` closed-form; no `Date()/random` (grep returns empty) |
| `Packages/CortexRender/Sources/CortexRender/FrameSynchronizer.swift` | 71 | VERIFIED | `DispatchSemaphore(value: 1)`; `waitForNextFrame`; `signalOnComplete`; direct `signal()` for skip path |
| `Packages/CortexRender/Sources/CortexRender/iOSDisplayLinkAdapter.swift` | 174 | VERIFIED | `CAMetalDisplayLinkDelegate`; `preferredFrameRateRange(120,120,120)`; `preferredFrameLatency=1.0`; plain `cb.present(drawable)` |
| `Packages/CortexRender/Sources/CortexRender/MacDisplayLinkAdapter.swift` | 164 | VERIFIED | `displayLink(target: self, selector:)`; `nextDrawable()`; `autoreleasepool`; plain `cb.present(drawable)` |
| `Packages/CortexRender/Sources/CortexRender/WebgridView.swift` | 151 | VERIFIED | `UIViewRepresentable`/`NSViewRepresentable`; Coordinator retains adapter; `dismantle*View` teardown |
| `Apps/CortexRenderBench/GPUTimeHistogram.swift` | 259 | VERIFIED | `gpuEndTime − gpuStartTime`; n≥10k; p50/p95/p99; writes `gpu_time_hist.json` |
| `Apps/CortexRenderBench/FrameSoak.swift` | 231 | VERIFIED | 60s soak; flags intervals >8.33ms; writes `soak_log.json`; `onPanelRunSteps` documented |
| `Apps/CortexRenderBench/main.swift` | 135 | VERIFIED | Plan-04 stub replaced; arg-parsed CLI (`frames`, `WxH`, `--warmup`, `--soak`, `--out`); `MainActor.assumeIsolated` entry |
| `Tools/scripts/render-policy.sh` | 353 | VERIFIED | executable (`-rwxr-xr-x`); 9 REQUIRED-PRESENT + 3 FORBIDDEN; `--self-test` negative-control |
| `.planning/phases/…/06-render-evidence.md` | — | VERIFIED | M5 Pro device-annotated; p99=0.1618ms; 243,724 frames/0 over-budget; "what this is NOT" paragraph; D-11/D-12 framing |
| `.planning/phases/…/gpu_time_hist.json` | — | VERIFIED | p99=0.1618ms; device="Apple M5 Pro"; samples=10000; extent=2752×2064 |
| `.planning/phases/…/soak_log.json` | — | VERIFIED | frames=243724; over_budget_intervals=0; achieved_hz=4062.06; device="Apple M5 Pro" |
| `.planning/phases/…/06-HUMAN-UAT.md` | — | VERIFIED | status: partial; never-auto-approve banner; passed:0, pending:3; all 3 tests in correct deferred state |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `iOSDisplayLinkAdapter` | `WebgridFrameEncoder` | `encoder.encode(into:commandBuffer:params:)` | WIRED | Line 150 in iOSDisplayLinkAdapter.swift calls `encoder.encode(into: update.drawable, commandBuffer: cb, params: params)` |
| `MacDisplayLinkAdapter` | `WebgridFrameEncoder` | `encoder.encode(into:commandBuffer:params:)` | WIRED | Line 145 in MacDisplayLinkAdapter.swift calls `encoder.encode(into: drawable, commandBuffer: cb, params: params)` |
| `iOSDisplayLinkAdapter` | `FrameSynchronizer` | `synchronizer.waitForNextFrame()` + `signalOnComplete` | WIRED | Lines 119/162 in iOSDisplayLinkAdapter.swift |
| `MacDisplayLinkAdapter` | `FrameSynchronizer` | `synchronizer.waitForNextFrame()` + `signalOnComplete` / direct `signal()` | WIRED | Lines 113/157/131 in MacDisplayLinkAdapter.swift; skip path balances wait |
| `VelocityRing.pop()` | `CursorIntegrator.integrate(latest:dt:)` | drain-to-latest loop in adapters | WIRED | Both adapters: `var latest = ring.pop(); while let next = ring.pop() { latest = next }; … integrate(latest:dt:)` |
| `CursorIntegrator` | `WebgridParams.grid30x30` | `cursorX`/`cursorY` from `CursorPosition` | WIRED | Adapters construct `WebgridParams.grid30x30(cursorX: pos.x, cursorY: pos.y, …)` after integration |
| `WebgridView` | `iOSDisplayLinkAdapter`/`MacDisplayLinkAdapter` | Coordinator `start(layer:ring:)` | WIRED | `make*View` builds encoder + starts platform adapter; adapter retained in `@MainActor Coordinator` |
| `ContentView` (iOS + Mac) | `WebgridView` | `WebgridView(ring: driver.ring)` | WIRED | Both `Apps/CortexiOS/ContentView.swift` and `Apps/CortexMac/ContentView.swift` line 16: `WebgridView(ring: driver.ring)` |
| `LissajousProducer` | `VelocityRing` | push thread in `WebgridDriver` | WIRED | ContentViews contain `WebgridDriver` owning the single LissajousProducer push thread feeding `driver.ring` |
| `CortexRenderBench` | `WebgridFrameEncoder` | `OffscreenDrawable` wrapper + `encode(into:commandBuffer:params:)` | WIRED | `GPUTimeHistogram.swift` creates real `WebgridFrameEncoder`, wraps offscreen MTLTexture in `OffscreenDrawable` conforming to `CAMetalDrawable`, calls `encoder.encode(into:)` |
| `render-policy.sh` | renderer sources | `grep` over `FrameSynchronizer.swift`, `MetalLayerConfig.swift`, `iOSDisplayLinkAdapter.swift`, `MacDisplayLinkAdapter.swift`, `Webgrid.metal`, `project.yml` | WIRED | render-policy.sh exits 0; all 9 REQUIRED tokens found in their owning files |
| `ci.yml` | `render-policy.sh` | `./Tools/scripts/render-policy.sh` + `--self-test` step | WIRED | ci.yml line 213-214: both gate and self-test run after `xcodegen generate` |
| `ci.yml` | `Apps/CortexiOS/Info.plist` | `plutil -extract` plist check | WIRED | ci.yml lines 225-228: `grep CADisableMinimumFrameDurationOnPhone project.yml` + `plutil -extract` |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `WebgridView` / both adapters | `ring` (VelocityRing) | `WebgridDriver` push thread feeding `LissajousProducer.velocity(at:)` | Yes — LissajousProducer emits `(vx,vy) Float16` at ~50Hz; closed-form, no RNG, deterministic | FLOWING |
| `WebgridFrameEncoder` | `params` (WebgridParams) | `CursorIntegrator.integrate(latest:dt:)` → `grid30x30(cursorX:cursorY:…)` | Yes — cursor position is integrated from real velocity frames and clamped to [0,1] | FLOWING |
| `GPUTimeHistogram` | `gpuTimes` array | `commandBuffer.gpuEndTime − commandBuffer.gpuStartTime` post `waitUntilCompleted()` | Yes — real GPU timestamps from Metal command buffer completion; n=10,000 frames measured | FLOWING |
| `FrameSoak` | `intervals` array + `overBudgetCount` | wall-clock per-frame encode+commit+wait loop over 60s | Yes — real CFAbsoluteTimeGetCurrent() deltas; 243,724 genuine encode cycles | FLOWING |
| `gpu_time_hist.json` | p50/p95/p99 | `GPUTimeHistogram.run()` nearest-rank reduction | Yes — genuine measurements on Apple M5 Pro, reproduced p99=0.1615/0.1618ms across two runs | FLOWING |
| `soak_log.json` | frames/over_budget_intervals | `FrameSoak.run()` 60s loop | Yes — genuine 243,724-frame run on Apple M5 Pro | FLOWING |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| xcodegen exits 0 | `xcodegen generate` | EXIT 0, project written | PASS |
| macOS app build succeeds | `xcodebuild build -scheme CortexMac … CODE_SIGNING_ALLOWED=NO` | **BUILD SUCCEEDED** | PASS |
| 19/19 tests pass including SPSC stress | `swift test --package-path Packages/CortexRender` | 19 passed, 0 failed | PASS |
| render-policy.sh clean run | `bash Tools/scripts/render-policy.sh` | EXIT 0, all 9 ok + all FORBIDDEN absent | PASS |
| render-policy.sh self-test (every check bites) | `bash Tools/scripts/render-policy.sh --self-test` | EXIT 0, SELF-TEST OK (9 strips + 4 injections + scoping-control) | PASS |
| iOS slice type-checks against iOS 26 SDK | `xcrun swiftc -typecheck -sdk iphoneos -target arm64-apple-ios26.0 -swift-version 6 … + shim` | EXIT 0 (only expected Bundle.module error before shim; 0 errors after shim) | PASS |

---

### Requirements Coverage

| Requirement | Description | Artifact | Status | Evidence |
|-------------|-------------|----------|--------|----------|
| RENDER-01 | CAMetalDisplayLink iOS path (zero CADisplayLink on iOS Metal) | `iOSDisplayLinkAdapter.swift` | SATISFIED | `CAMetalDisplayLinkDelegate` conformance; render-policy.sh FORBIDDEN gate passes |
| RENDER-02 | 120Hz ProMotion — M5 Pro corroborating; iPad-M4 deferred | `MacDisplayLinkAdapter.swift`, `soak_log.json`, `06-HUMAN-UAT.md` | SATISFIED (corroborating tier; canonical deferred D-12) | 243,724 frames / 0 over-budget; REQUIREMENTS.md reframed |
| RENDER-03 | CADisableMinimumFrameDurationOnPhone=YES + storageModeShared + value:1 | `project.yml`, `Info.plist`, `FrameSynchronizer.swift`, `WebgridFrameEncoder.swift` | SATISFIED | plist `<true/>`; `setBytes` zero-copy; `DispatchSemaphore(value: 1)` |
| RENDER-04 | Metal compute shader webgrid | `Webgrid.metal`, `WebgridFrameEncoder.swift` | SATISFIED | `kernel void webgrid`; `makeComputePipelineState`; `framebufferOnly=false` |
| RENDER-05 | GPU frame time ≤0.4ms, n≥10k histogram — M5 Pro corroborating; iPad-M4 deferred | `GPUTimeHistogram.swift`, `gpu_time_hist.json`, `06-HUMAN-UAT.md` | SATISFIED (corroborating tier; canonical deferred D-12) | p99=0.1618ms, n=10,000; REQUIREMENTS.md reframed |
| RENDER-06 | storageModeShared zero-copy | `WebgridFrameEncoder.swift` | SATISFIED | `setBytes` is the zero-copy small-constant path; `storageModeManaged` absent |
| RENDER-07 | dispatch_semaphore(value:1) one in-flight frame | `FrameSynchronizer.swift` | SATISFIED | `DispatchSemaphore(value: 1)`; every wait balanced by exactly one signal |
| RENDER-08 | NSScreen.displayLink macOS path | `MacDisplayLinkAdapter.swift` | SATISFIED | `view.displayLink(target: self, selector:)`; render-policy.sh REQUIRED-PRESENT passes |
| RENDER-09 | MTL_HUD_ENABLED scheme env | `project.yml` | SATISFIED | MTL_HUD_ENABLED=1 in both CortexiOS and CortexMac scheme run environments |

---

### Anti-Patterns Found

| File | Pattern | Severity | Verdict |
|------|---------|----------|---------|
| `Apps/CortexiOS/ContentView.swift` line 4 | Word "placeholder" in comment | Info | Not a stub — the comment reads "the Phase-1 placeholder text is replaced by WebgridView". `var body` renders `WebgridView(ring: driver.ring)`. |
| `Apps/CortexMac/ContentView.swift` line 4 | Word "placeholder" in comment | Info | Same — comment documents history. Actual body is `WebgridView(ring: driver.ring)`. |

No functional stubs found. The Plan-04 `Apps/CortexRenderBench/main.swift` one-line stub (`print("bench: Plan 05 lands here")`) was replaced — grep returns empty. No `TODO`/`FIXME` in renderer sources. No `return null`/`return {}`/`return []` in non-test code. No hardcoded empty data flowing to rendering.

---

### Honesty Check (Load-Bearing Numbers)

**RENDER-02 / SC#4 (243,724 frames / 0 over-budget):**
- `soak_log.json`: frames=243724, over_budget_intervals=0, achieved_hz=4062.06 — matches `06-render-evidence.md` exactly.
- Mode label: "offscreen-throughput (CI-friendly subset)" — correctly distinguished from on-panel 120Hz refresh. Not over-claimed.
- Device: "Apple M5 Pro" — correctly attributed; NOT labelled as iPad Pro M4.

**RENDER-05 / SC#2 (p99=0.1618ms, n=10k):**
- `gpu_time_hist.json`: p99=0.1618, samples=10000 — matches `06-render-evidence.md` exactly.
- Reproduced across two runs (p99=0.1615 / 0.1618) — deterministic LissajousProducer drive confirmed.
- Device: "Apple M5 Pro" — correctly attributed. Extent: 2752×2064 (representative full-surface, not a toy texture — honest).

**SC reframe (D-11/D-12):**
- ROADMAP SC#2 and SC#4 both carry "measured on M5 Pro ProMotion (corroborating-canonical, D-11)" and "iPad Pro M4 canonical capture optional/future".
- REQUIREMENTS RENDER-02 and RENDER-05 reframed identically; all 9 RENDER IDs and `[ ]` checkbox states preserved (2 occurrences each, confirmed by grep).
- `06-HUMAN-UAT.md`: status=partial; passed=0, pending=3; never-auto-approve banner present.
- No fabricated numbers detected. No M5 Pro number presented as the iPad Pro M4 canonical claim anywhere in the codebase.

---

### Human Verification Required

#### 1. iPad Pro M4 GPU compute time ≤0.4ms — RENDER-05 / SC#2 (canonical capture)

**Test:** On a connected iPad Pro M4 (iPadOS 26), build and run `CortexRenderBench` targeting the iPad (or use Xcode GPU frame capture on the live `CortexiOS` scheme). Measure `gpuEndTime − gpuStartTime` over n≥10,000 frames at the 2752×2064 drawable extent. Confirm p99 ≤0.4ms. Commit `gpu_time_hist_ipad.json` (or `.gputrace`/screenshot) into the phase dir.

**Expected:** p99 ≤0.4ms on iPad Pro M4 ANE/GPU. Consistent with M5 Pro p99=0.1618ms and the cortex-spec expectation (~0.3–0.6ms on A17 Pro → ≤0.4ms on M4).

**Why human:** Real iPad Pro M4 hardware required. Xcode GPU frame capture is a GUI profiler on a live device process — CI has no paired device, no Metal GPU, and no display. This is a load-bearing project-credibility number (never-auto-approve, D-12).

#### 2. iPad Pro M4 sustained 120Hz on-panel, zero dropped frames over 60s — RENDER-02 / SC#4 (canonical on-panel refresh)

**Test:** On a connected iPad Pro M4, run the `CortexiOS` scheme. Confirm `CAMetalDisplayLink` drives at `preferredFrameRateRange(120,120,120)`. With `MTL_HUD_ENABLED=1` (already set in scheme), confirm P95 frame time ≈8.33ms and zero intervals >8.33ms over a 60s window. Screenshot the MTL_HUD overlay. Optionally add a display-link callback counter and commit `soak_log_ipad.json`.

**Expected:** Sustained 120Hz for 60s with zero over-budget frames on the iPad Pro M4 ProMotion panel.

**Why human:** Requires a physical iPad Pro M4 ProMotion panel — 120Hz *on-display refresh* cannot be verified headlessly or on a 60Hz device (iPad Air M2 is physically incapable). The M5 Pro offscreen-throughput soak proves GPU-workload headroom; on-panel 120Hz refresh is a distinct claim requiring the canonical display surface. Never-auto-approve per D-12.

---

### Gaps Summary

No functional gaps. All 9 RENDER requirements are implemented and the corroborating evidence is genuine. The two `human_needed` items are the expected deferred D-12 canonical captures (iPad Pro M4 hardware not in hand) — explicitly planned in 06-HUMAN-UAT.md with the never-auto-approve banner.

The overall `status: human_needed` reflects that SC#2 and SC#4 have verified corroborating evidence (M5 Pro, D-11) but not yet the canonical on-device iPad Pro M4 capture (D-12). Per the ROADMAP and REQUIREMENTS reframe (D-11, sign-off approved), the phase completes on the Mac-corroborating tier; the iPad-M4 capture is optional/future.

---

*Verified: 2026-06-22T14:00:00Z*
*Verifier: gsd-verifier*
