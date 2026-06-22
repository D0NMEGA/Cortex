---
phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid
plan: 03
subsystem: ui
tags: [cametaldisplaylink, cadisplaylink, nsview-displaylink, metal, 120hz, promotion, dispatch-semaphore, swift6, renderer, uiviewrepresentable, nsviewrepresentable]

# Dependency graph
requires:
  - phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid (Plan 01)
    provides: WebgridFrameEncoder.encode(into:commandBuffer:params:) + MetalLayerConfig.configure (framebufferOnly=false / maximumDrawableCount=2 / presentsWithTransaction=false) + WebgridParams.grid30x30 — the shared compute core both adapters drive
  - phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid (Plan 02)
    provides: VelocityRing (lock-free SPSC pop), CursorIntegrator.integrate(latest:dt:) (clamped, always-finite), CursorVelocity (fp16 seam), LissajousProducer.velocity(at:) (deterministic drive)
  - phase: 01-foundation
    provides: CortexRender SwiftPM package (.defaultIsolation(MainActor.self), macOS 26 / iOS 26 targets); SUPPORTS_MACCATALYST=NO + NSApplicationDelegateAdaptor (unobstructs the RENDER-08 NSView.displayLink path)
provides:
  - FrameSynchronizer — dispatch_semaphore(value:1) ONE-in-flight gate shared by both adapters; waitForNextFrame() + signalOnComplete(cb) (addCompletedHandler) + a direct signal() for the macOS nil-drawable skip path (wait/signal balance, T-06-03-01)
  - iOSDisplayLinkAdapter — CAMetalDisplayLinkDelegate driving the shared encoder at locked 120Hz, preferredFrameLatency=1.0, the vended update.drawable (no nextDrawable), plain present; ZERO legacy display-link references on the iOS Metal path (RENDER-01/02/07)
  - MacDisplayLinkAdapter — NSView.displayLink(target:selector:) -> CADisplayLink at locked 120Hz, manual layer.nextDrawable() in an autoreleasepool, reusing the SAME value:1 synchronizer (RENDER-08/02/07)
  - WebgridView — SwiftUI-embeddable Metal surface (UIViewRepresentable iOS / NSViewRepresentable macOS) hosting the CAMetalLayer + platform adapter, consumer-only over a caller-supplied VelocityRing
  - Live 30×30 webgrid on both app targets (CortexiOS full-bleed, CortexMac windowed), animated at launch by a deterministic in-process LissajousProducer push thread
affects: [Plan 06-04 (structural grep-gates: value:1 / maximumDrawableCount=2 / no-legacy-displaylink-on-iOS / displayLink(target:) / CADisableMinimumFrameDurationOnPhone / MTL_HUD), Plan 06-05/06 (M5 Pro ProMotion gpuStartTime/EndTime histogram + 60s 120Hz soak drive over these adapters), Phase 7 (ReFIT-Kalman replaces LissajousProducer behind the unchanged D-03 ring → adapter seam)]

# Tech tracking
tech-stack:
  added: [CAMetalDisplayLink/CAMetalDisplayLinkDelegate/CAMetalDisplayLink.Update (iOS), CADisplayLink via NSView.displayLink(target:selector:) (macOS 14+), CAFrameRateRange, DispatchSemaphore(value:1), UIViewRepresentable/NSViewRepresentable Metal host]
  patterns:
    - "Two thin display-link adapters over ONE shared WebgridFrameEncoder — only drawable acquisition (iOS vended update.drawable vs macOS manual nextDrawable) + pacing differ (RESEARCH TL;DR #1)"
    - "value:1 one-in-flight gate: wait at callback top, signal in addCompletedHandler; a single FrameSynchronizer type owns the wait/signal balance for both platforms (RENDER-07)"
    - "Every waitForNextFrame() balanced by exactly one signal — the macOS nil-drawable skip path calls synchronizer.signal() directly so value:1 cannot deadlock (T-06-03-01)"
    - "macOS callback body wrapped in autoreleasepool to release each nextDrawable()-vended drawable promptly (drawable-retention stutter mitigation, T-06-03-02)"
    - "Swift 6.2 .defaultIsolation(MainActor.self): @MainActor adapters; the nonisolated CAMetalDisplayLinkDelegate requirement re-enters via MainActor.assumeIsolated (no actor hop / no await on the latency path)"
    - "SwiftUI Metal host: layerClass-backed UIView (iOS) / makeBackingLayer CAMetalLayer NSView (macOS); adapter retained in the representable's Coordinator, torn down in dismantle*View"
    - "Host owns the SINGLE producer thread (SPSC discipline): WebgridView is consumer-only over a caller-supplied VelocityRing; ContentView's WebgridDriver is the one producer"

key-files:
  created:
    - Packages/CortexRender/Sources/CortexRender/FrameSynchronizer.swift
    - Packages/CortexRender/Sources/CortexRender/iOSDisplayLinkAdapter.swift
    - Packages/CortexRender/Sources/CortexRender/MacDisplayLinkAdapter.swift
    - Packages/CortexRender/Sources/CortexRender/WebgridView.swift
  modified:
    - Apps/CortexiOS/ContentView.swift
    - Apps/CortexMac/ContentView.swift
    - project.yml

key-decisions:
  - "Both adapters @MainActor; the nonisolated CAMetalDisplayLinkDelegate callback re-enters via MainActor.assumeIsolated rather than awaiting — keeps the latency-critical encode path hop-free under .defaultIsolation(MainActor.self) + complete strict concurrency"
  - "FrameSynchronizer exposes a direct signal() (not only signalOnComplete) so the macOS nextDrawable()==nil skip path balances the value:1 wait it already took — every wait gets exactly one signal, structurally deadlock-safe (T-06-03-01)"
  - "WebgridView is consumer-only over a caller-supplied VelocityRing; the host (ContentView's WebgridDriver) owns the SINGLE LissajousProducer push thread — keeps the SPSC one-producer/one-consumer invariant crisp"
  - "Both callbacks drain the ring to the most recent frame (while-let pop) before integrating — a 120Hz consumer never lags the ~50Hz producer (zero-order hold; D-04/RESEARCH Decision 5)"
  - "Synthetic producer is a plain Foundation Thread + Thread.sleep (NOT a pthread/QoS hot path): it is the synthetic DRIVE, distinct from the Phase-3 acquisition regime; a deterministic fixed-step simTime (not a wall clock) keeps the path bit-reproducible for the SC#4 soak (D-05)"
  - "iOS host is a layerClass-backed UIView, macOS host an makeBackingLayer CAMetalLayer NSView — full-size auto-resizing Metal layer with no manual frame syncing"

patterns-established:
  - "Pattern: one shared frame encoder, two platform display-link adapters; the value:1 synchronizer is the single shared pacing primitive"
  - "Pattern: literal-grep-safe comments — forbidden tokens (legacy display-link class, timed-present, stdout console call) are described by intent, never written as the bare literal, so a structural grep-gate over the iOS path stays accurate (continues the Phase 1-5 reword precedent)"

requirements-completed: [RENDER-01, RENDER-02, RENDER-07, RENDER-08]

# Metrics
duration: 8min
completed: 2026-06-22
---

# Phase 6 Plan 03: Display-Link Adapters + WebgridView Integration Summary

**Two thin display-link adapters over the one shared `WebgridFrameEncoder` — iOS `CAMetalDisplayLink` (vended `update.drawable`, `preferredFrameLatency=1.0`, plain present, zero legacy display-link) and macOS `NSView.displayLink → CADisplayLink` (manual `nextDrawable()` in an `autoreleasepool`) — both locked to 120Hz and gated to ONE in-flight frame by a shared `dispatch_semaphore(value:1)` `FrameSynchronizer`, embedded via a `UIViewRepresentable`/`NSViewRepresentable` `WebgridView` so both app targets render the live 30×30 webgrid driven at launch by a deterministic in-process Lissajous producer.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-06-22T02:42:18Z
- **Completed:** 2026-06-22T02:50:31Z
- **Tasks:** 2
- **Files modified:** 7 (4 created, 3 modified)

## Accomplishments

- **`FrameSynchronizer` — the value:1 one-in-flight gate (RENDER-07).** `dispatch_semaphore(value:1)` with `waitForNextFrame()` (wait at callback top), `signalOnComplete(cb)` (signal in `addCompletedHandler` on GPU completion), and a direct `signal()` for the macOS nil-drawable skip path. Heavy anti-optimization annotation ("do NOT raise to 3 — adds ~8.3ms to the glass-to-glass budget") so a future maintainer (and the Plan-04 grep-gate) can't silently triple-buffer it back. `@unchecked Sendable` (shared between the callback thread and the completion-handler thread by design; `DispatchSemaphore` is itself thread-safe).
- **`iOSDisplayLinkAdapter` — the iOS path (RENDER-01/02/07).** `CAMetalDisplayLinkDelegate` over a `MetalLayerConfig`-configured `CAMetalLayer`; `start()` sets `preferredFrameRateRange = CAFrameRateRange(minimum:120, maximum:120, preferred:120)` + `preferredFrameLatency = 1.0`, adds to the main run loop in `.common`. The `metalDisplayLink(_:needsUpdate:)` callback: value:1 wait → dt from `update.targetPresentationTimestamp` delta → drain `VelocityRing.pop()` to latest → `CursorIntegrator.integrate` → `WebgridParams.grid30x30` from the vended `update.drawable` extent → `encode` → `signalOnComplete` → plain `present` → `commit`. Uses the vended drawable (no `nextDrawable()`); ZERO legacy display-link references on this path.
- **`MacDisplayLinkAdapter` — the macOS path (RENDER-08/02/07).** `NSView.displayLink(target:self, selector:#selector(tick))` → `CADisplayLink` at locked 120Hz — the sanctioned macOS Metal path. The `@objc tick(_:)` body is wrapped in `autoreleasepool` (T-06-03-02 stutter mitigation): value:1 wait → dt from `link.timestamp` delta → `guard let drawable = layer.nextDrawable() else { synchronizer.signal(); return }` (balances the wait, T-06-03-01) → drain ring → integrate → grid30x30 → encode → `signalOnComplete` → plain `present` → `commit`. Mirrors the iOS callback exactly; reuses the SAME shared encoder + value:1 synchronizer.
- **`WebgridView` — the SwiftUI host.** `UIViewRepresentable` (iOS, `layerClass`-backed `CAMetalLayer` `UIView`) / `NSViewRepresentable` (macOS, `makeBackingLayer` `CAMetalLayer` `NSView`). `make*View` configures the layer via `MetalLayerConfig`, builds the `WebgridFrameEncoder`, starts the platform adapter, and retains it in a `@MainActor Coordinator` (torn down in `dismantle*View`). Consumer-only over a caller-supplied `VelocityRing`.
- **Both app `ContentView`s now render the live grid.** The Phase-1 placeholder `VStack` text is replaced by the embedded `WebgridView` (`.ignoresSafeArea()` full-bleed on iOS; `.frame(minWidth:560,minHeight:480)` on macOS), plus a `WebgridDriver` owning the SINGLE deterministic `LissajousProducer` push thread (~50Hz / 20ms, DEC-10 cadence; fixed-step `simTime` for bit-reproducibility) feeding the ring — so the cursor moves at launch with no real decoder yet.

## Task Commits

Each task was committed atomically:

1. **Task 1: FrameSynchronizer (value:1) + iOS CAMetalDisplayLink adapter** — `d10892b` (feat)
2. **Task 2: macOS NSView.displayLink adapter + WebgridView + app ContentViews** — `9848e8d` (feat)

_Plan metadata commit + STATE/ROADMAP/REQUIREMENTS owned by the orchestrator (this sequential executor does not write them)._

## Files Created/Modified

- `Packages/CortexRender/Sources/CortexRender/FrameSynchronizer.swift` — value:1 one-in-flight gate, wait/signal balance, anti-optimization annotation (created, 71 lines)
- `Packages/CortexRender/Sources/CortexRender/iOSDisplayLinkAdapter.swift` — CAMetalDisplayLinkDelegate, 120Hz, preferredFrameLatency=1.0, vended drawable, plain present (created, 174 lines)
- `Packages/CortexRender/Sources/CortexRender/MacDisplayLinkAdapter.swift` — NSView.displayLink → CADisplayLink, 120Hz, manual nextDrawable in autoreleasepool, shared value:1 gate (created, 164 lines)
- `Packages/CortexRender/Sources/CortexRender/WebgridView.swift` — UIViewRepresentable/NSViewRepresentable Metal host + adapter Coordinator (created, 151 lines)
- `Apps/CortexiOS/ContentView.swift` — full-bleed WebgridView + WebgridDriver (LissajousProducer push thread) (modified)
- `Apps/CortexMac/ContentView.swift` — windowed WebgridView + WebgridDriver (modified)
- `project.yml` — added `package: CortexRender` to both app targets (Rule 3 — see Deviations) (modified)

## Decisions Made

- **`@MainActor` adapters + `MainActor.assumeIsolated` in the callback** — the package's `.defaultIsolation(MainActor.self)` makes the adapters main-actor-isolated, while `CAMetalDisplayLinkDelegate.metalDisplayLink(_:needsUpdate:)` is a nonisolated framework requirement. Re-entering via `MainActor.assumeIsolated` (the link is added to the main run loop, so the callback genuinely runs there) satisfies strict concurrency WITHOUT an `await` on the latency-critical encode path. RESEARCH's Swift 6.2 note ("mind MainActor/Sendable; avoid actor hops in the callback") drove this.
- **Direct `FrameSynchronizer.signal()` for the macOS skip path** — with value:1 an unbalanced wait deadlocks forever. The macOS `nextDrawable()==nil` and `makeCommandBuffer()==nil` branches `signal()` directly to balance the wait they already took; the normal path balances via `signalOnComplete`. Every wait → exactly one signal, structurally (T-06-03-01), not by luck.
- **Drain-to-latest in both callbacks** — `var latest = ring.pop(); while let next = ring.pop() { latest = next }` so the 120Hz consumer always integrates the most recent of the ~50Hz producer's frames (zero-order hold; D-04). Empty ring → nil → integrator holds.
- **Synthetic producer is a plain `Thread` + `Thread.sleep`, deterministic fixed-step time** — it is the synthetic DRIVE, not the Phase-3 acquisition hot path, so no pthread/QoS ceremony is warranted; `simTime` advances by a fixed 20ms step (not a wall-clock read) so the integrated path is bit-reproducible for the SC#4 soak (D-05). One producer thread keeps the SPSC invariant crisp.
- **`layerClass` (iOS) / `makeBackingLayer` (macOS) Metal hosts** — the cleanest full-size auto-resizing `CAMetalLayer` host on each platform, no manual frame-sync glue.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `CortexRender` was not a dependency of either app target — added it to `project.yml`**
- **Found during:** Task 2 (wiring the app ContentViews to `import CortexRender`)
- **Issue:** The plan's Task 2 action states "project.yml already lists CortexRender as a dependency of both apps — no project.yml change needed." It does NOT: `CortexRender` was registered under `packages:` but the `CortexiOS` target depended only on `CortexCore`, and `CortexMac` on `CortexCore` + the `CortexDaemon` target. `import CortexRender` in the new ContentViews would therefore fail to resolve, blocking the app builds.
- **Fix:** Added `- package: CortexRender` to the `dependencies:` of both `CortexiOS` and `CortexMac` in `project.yml`, then re-ran `xcodegen generate`. (The renderer was already registered as a package, so no `packages:` change was needed.)
- **Files modified:** `project.yml`
- **Verification:** `xcodegen generate` clean; `xcodebuild` package graph now resolves `CortexRender` for BOTH app targets (visible in the "Resolved source packages" list for the iOS scheme); `CortexMac` app build SUCCEEDED.
- **Committed in:** `9848e8d` (Task 2 commit)

**2. [Rule 3 - Blocking] Literal-grep false-positives in the iOS adapter's explanatory comments — reworded**
- **Found during:** Task 1 (acceptance-criteria check)
- **Issue:** The negative acceptance criteria `! grep -q 'CADisplayLink'`, `! grep ... 'present\(at:'`, and `! grep -q 'print('` over `iOSDisplayLinkAdapter.swift` tripped on heavy explanatory comments that mentioned each forbidden token while *documenting its avoidance* (e.g. "regressing to `CADisplayLink` here is the Out-of-Scope rejection", "NOT a timed present(at:) variant", "No `print()` — os.Logger only"). No forbidden API is actually used; the grep cannot distinguish code from a comment. This is the exact recurring literal-grep pattern documented in Phases 1-5, and the Plan-04 CI grep-gate would fail identically.
- **Fix:** Reworded the comments to describe the prohibited APIs by intent ("the legacy per-screen display-link timer class", "the timed/timestamp-targeting present variants", "the stdout console call") without the standalone literal tokens. Meaning fully preserved; the actual code is unchanged (vended `update.drawable`, plain `cb.present(drawable)`, `os.Logger`).
- **Files modified:** `Packages/CortexRender/Sources/CortexRender/iOSDisplayLinkAdapter.swift`
- **Verification:** All three negative greps now return empty over the iOS adapter; `swift build` + the iOS-SDK type-check both stayed green after the edit.
- **Committed in:** `d10892b` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 3 - Blocking: a missing build-graph dependency the plan mis-assumed was present, and the recurring literal-grep comment reword).
**Impact on plan:** Both were necessary for buildability/gate-correctness and stayed within scope — the four artifacts, the contract (`FrameSynchronizer`/`WebgridView`), the RENDER-01/02/07/08 truths, and the threat mitigations are exactly as specified. No new runtime dependency (CortexRender was already a registered package; only the per-target edge was missing). No scope creep.

## Issues Encountered

- **iOS app-target `xcodebuild` is environment-gated, not blocked by a code defect.** This Xcode 26.3 install has no iOS 26.2 platform runtime (and no iOS Simulator runtime), so `xcodebuild -scheme CortexiOS` cannot find ANY eligible iOS destination (device or simulator). Structural verification was taken to the maximum extent locally instead: (1) `swift build --package-path Packages/CortexRender` (macOS slice) is green; (2) the ENTIRE iOS `#if os(iOS)` slice — `iOSDisplayLinkAdapter` + the iOS `WebgridView` + all collaborators — type-checks against the real iOS 26 SDK via `xcrun swiftc -typecheck -sdk iphoneos -target arm64-apple-ios26.0 -swift-version 6` (EXIT 0, with only the SwiftPM-synthesized `Bundle.module` accessor shimmed); (3) the `CortexiOS` package graph resolves `CortexRender`; (4) the `CortexMac` app build SUCCEEDED end-to-end (the Metal Toolchain compiled `Webgrid.metal` into the app bundle's `default.metallib`). The dynamic iOS-device build is deferred to the canonical environment / CI on `macos-15` with the iOS platform installed — exactly the Phase-1 toolchain-deferral precedent (and consistent with D-11: the iPad-M4 capture is itself deferred/optional). No verification-gate escalations; no architectural (Rule 4) decisions.

## Known Stubs

None. The renderer is fully wired on both platforms: real `CAMetalDisplayLink` (iOS) / `NSView.displayLink` (macOS) drive, the real shared `WebgridFrameEncoder` compute pass, the real `CursorIntegrator` over the real lock-free `VelocityRing`, and a real `LissajousProducer` push thread emitting real velocity at launch. The synthetic producer is intentional by design (D-05) — the Phase-5 decoder / Phase-7 ReFIT-Kalman become the producer behind the unchanged D-03 ring→adapter seam; that is the planned evolution, not a stub.

## Threat Flags

None beyond the plan's `<threat_model>`. The introduced surface is exactly the wait/signal balance + the drawable lifecycle the register anticipated: T-06-03-01 (value:1 deadlock on a nil-drawable skip) is mitigated by the macOS skip path's direct `synchronizer.signal()` (every wait balanced by exactly one signal); T-06-03-02 (drawable-retention stutter) is mitigated by the macOS `autoreleasepool` wrap (grep-asserted); T-06-03-03 (value:1 → value:3 tamper) is mitigated by the heavy `FrameSynchronizer`/`MetalLayerConfig` annotations + the Plan-04 grep-gate; T-06-03-04 (torn read at the consumer) is inherited from Plan 02's Acquire/Release SPSC (the callback only `pop()`s). In-process only — no network/auth/persistence/external input.

## User Setup Required

None - no external service configuration required. (Local note: a dynamic iOS-device/simulator run requires the iOS 26.2 platform component installed in Xcode 26.3 — Xcode > Settings > Components; the macOS app runs as-is.)

## Next Phase Readiness

- **Ready for Plan 06-04 (structural gates + Info.plist + scheme):** the grep targets are all present and literal-grep-safe — `value: 1` + `maximumDrawableCount = 2` (FrameSynchronizer / MetalLayerConfig), `CAMetalDisplayLink` + zero legacy-display-link on the iOS path (iOSDisplayLinkAdapter), `displayLink(target:` (MacDisplayLinkAdapter). Plan 04 still adds `CADisableMinimumFrameDurationOnPhone = YES` to `Apps/CortexiOS/Info.plist`, `MTL_HUD_ENABLED=1` to both schemes, and the build-failing CI gates over these tokens.
- **Ready for Plan 06-05/06 (Mac measurement + soak):** the macOS adapter runs live on the M5 Pro ProMotion panel (D-11 corroborating-canonical); `commandBuffer.gpuStartTime/gpuEndTime` instrumentation + the 60s 120Hz soak hang off `tick(_:)`, driven by the now-deterministic LissajousProducer.
- **Phase 7 readiness:** because the seam is velocity-typed and the integrator is renderer-owned, the ReFIT-Kalman becomes the `VelocityRing` producer with no consumer/adapter change — the `WebgridDriver` push thread is the only swap point.
- **Blocker (carried, environment):** the iOS-device/simulator dynamic build needs the iOS 26.2 platform component in this Xcode (deferred to CI on `macos-15` / a fully-provisioned Xcode, per the Phase-1 precedent). The iOS slice is otherwise fully type-checked against the iOS 26 SDK.

## Self-Check: PASSED

- All 4 created source files verified on disk (FrameSynchronizer 71L, iOSDisplayLinkAdapter 174L, MacDisplayLinkAdapter 164L, WebgridView 151L); WebgridView exceeds the frontmatter `min_lines: 40`.
- Both task commits verified in `git log` (`d10892b`, `9848e8d`).
- `swift build --package-path Packages/CortexRender` green; `swift test` 19/19 green (no regression); `CortexMac` app `xcodebuild` BUILD SUCCEEDED; iOS slice `swiftc -typecheck` against the iOS 26 SDK EXIT 0; all 5 plan `<verification>` checks + all task `<acceptance_criteria>` pass.
- STATE.md / ROADMAP.md / REQUIREMENTS.md NOT modified by this executor (orchestrator-owned).

---
*Phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid*
*Completed: 2026-06-22*
