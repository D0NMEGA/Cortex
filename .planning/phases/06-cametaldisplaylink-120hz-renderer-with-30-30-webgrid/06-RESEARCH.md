# Phase 6 Research: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid

**Researched:** 2026-06-21 (main-thread browser-harness Apple-DocC pass + multi-source scraper digest — NOT the HTTP-only subagent)
**Phase goal:** A beam-raced 120Hz Metal renderer presents a 30×30 (~900-cell) compute-shader webgrid driven by a cursor-velocity stream, on iPad Pro M4 ProMotion at ≤0.4ms GPU compute, with `dispatch_semaphore(value:1)` enforcing one in-flight frame; macOS is a full visual peer via `NSScreen.displayLink`.
**Requirements:** RENDER-01 … RENDER-09 (+ PERF-04 budget contribution)
**Phase-6 handoff (verified in code):** `Packages/CortexRender/` is an 8-line stub (`CortexRender.swift` marker enum + README); already wired in `project.yml` as a dependency of both `CortexiOS` and `CortexMac`. `SUPPORTS_MACCATALYST: NO` + `NSApplicationDelegateAdaptor` already set (Phase 1) → the RENDER-08 `NSScreen.displayLink` path is unobstructed. Phase 3 SPSC ring (`Packages/CortexRing/`, `#[repr(C)] CortexFrame` + `cortex_spsc_push/pop`, Swift `CortexRing.push/pop`) is the design template for the velocity seam. `Apps/CortexiOS/Info.plist` has a `project.yml` placeholder comment: *"CADisableMinimumFrameDurationOnPhone arrives in Phase 6."* Decisions are locked in `06-CONTEXT.md` (D-01…D-12).

---

## TL;DR — the load-bearing findings

1. **iOS and macOS use *different* display-link plumbing — this is the single biggest architectural fact.** iOS/iPadOS uses `CAMetalDisplayLink` (iOS 17+), whose delegate `metalDisplayLink(_:needsUpdate:)` is **handed a ready drawable** via `update.drawable` — no manual `nextDrawable()`. macOS-native (non-Catalyst, per RENDER-08 + spec) uses `NSView/NSScreen.displayLink(target:selector:)` (macOS 14+) which returns a plain **`CADisplayLink`**; in its selector you **manually** call `metalLayer.nextDrawable()`, encode, present. Both are real 120Hz paths, but the renderer needs **two thin display-link adapters over one shared encode core**. (`CAMetalDisplayLink` *is* available macOS 14+, but the spec deliberately avoids it on native AppKit because it needs an AppKit-thread tick — RENDER-08 stands.)

2. **`preferredFrameLatency` accepts ONLY `1.0` or `2.0`.** `1.0` = lowest latency (≈ single frame in flight); `2.0` = default (double-buffer, more GPU slack). The beam-raced glass-to-glass goal wants **`1.0`** — and that is *exactly consistent* with the locked `dispatch_semaphore(value:1)` (RENDER-07) and `maximumDrawableCount = 2`.

3. **Cortex's `dispatch_semaphore(value:1)` is a deliberate latency-over-throughput divergence from Apple's canonical sample.** Apple's "Synchronizing CPU and GPU Work" sample uses `value = 3` (triple-buffered, maximizes CPU/GPU *overlap*/throughput). Cortex wants **minimum latency**, so `value:1` (one frame in flight, no overlap) is correct and intentional — same wait/signal mechanism (`wait` at top of callback, `signal` in `commandBuffer.addCompletedHandler`), just count = 1. The planner must NOT "fix" it back to 3.

4. **Writing the 30×30 grid from a *compute* shader straight into the drawable requires `CAMetalLayer.framebufferOnly = false`.** By default (`true`) the drawable texture has only `.renderTarget` usage — you "may not sample, read from, or write to" it. RENDER-04 mandates a compute shader, so either (a) set `framebufferOnly = false` and `compute → drawable.texture` directly (simplest, one pass, slight CA optimization cost), or (b) keep `framebufferOnly = true`, compute into an offscreen `storageModeShared`/`.shaderWrite` texture, then blit/draw into the drawable. **Decide this explicitly** (CONTEXT D-09 had it as discretion — this is the research-backed framing).

5. **`present(at:)` / timed-present variants ASSERT under `CAMetalDisplayLink`.** Apple docs: "Using alternative methods to [present] that target the presentation for a specific time cause an assert when used with a `CAMetalDisplayLink`." Use plain `update.drawable.present()` / `commandBuffer.present(update.drawable)`. (Only exception: `presentsWithTransaction = true` requires the `waitUntilScheduled()` + `drawable.present()` form — not needed here; keep `presentsWithTransaction = false` for the async, lowest-latency present.)

6. **120Hz on ProMotion is opt-in two ways:** `Info.plist` **`CADisableMinimumFrameDurationOnPhone = YES`** (iOS 15+; unlocks above-default rates on ProMotion) AND a **`preferredFrameRateRange = CAFrameRateRange(minimum:120, maximum:120, preferred:120)`** on the (CAMetal)DisplayLink. Without the Info.plist key, the system caps you at the default. The macOS `CADisplayLink` also honors `preferredFrameRateRange` (macOS 14+).

7. **GPU compute time (SC#2 ≤0.4ms) is measurable two ways, no device-exclusive API:** live via `MTL_HUD_ENABLED=1` scheme env (RENDER-09: P95 frame time, drawable-wait, encoder-time on-screen), and programmatically via `commandBuffer.gpuStartTime`/`gpuEndTime` (CFTimeInterval, public) or an `MTLCounterSampleBuffer` with `.timestamp` at the compute encoder boundaries. Both run on the M5 Pro Mac now (CONTEXT D-11 corroborating-canonical) and on the iPad later.

8. **The sample to mirror is WWDC23 session 10123 / "Achieving smooth frame rates with a Metal display link"** — doc page is current to **Xcode 26.3** (confirms 2026 currency). It is the canonical setup/teardown + delegate pattern; the planner should treat it as the reference implementation.

---

## Decision 1 — iOS display-link path: `CAMetalDisplayLink` (RENDER-01/02)

**API surface (confirmed, iOS 17.0+ / iPadOS 17.0+):**
- `class CAMetalDisplayLink` — `init(metalLayer: CAMetalLayer)`; set `.delegate`; `.add(to: runloop, forMode:)` to start; `.isPaused = true` to stop; `.invalidate()` to tear down.
- `var preferredFrameRateRange: CAFrameRateRange` — best-effort within range; default = display max. Set `CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)` for locked 120Hz (system may still drop under thermal/Low-Power/accessibility — handle gracefully).
- `var preferredFrameLatency: Float` — **only `1.0` or `2.0`**. Use `1.0` for the beam-raced budget.
- `protocol CAMetalDisplayLinkDelegate { func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) }`
- `CAMetalDisplayLink.Update`: `var drawable: any CAMetalDrawable { get }` (ready-to-render, no `nextDrawable()`), `var targetTimestamp: CFTimeInterval` (deadline to call `present`), `var targetPresentationTimestamp: CFTimeInterval` (estimated on-glass time — use Δ vs previous for animation/integration dt).

**Callback contract (from the delegate doc):** render into `update.drawable.texture`; encode all Metal commands; call `present` **before** `update.targetTimestamp`; the GPU may finish after that deadline within the `preferredFrameLatency` budget. Do **not** use timed-present variants (assert — finding #5).

**Run loop:** add to `.main`/`.current` run loop in `.common` mode (sample convention). The callback fires on that run loop's thread. The lock-free `CortexRing.pop()` is callback-safe (no locks/allocation) — consistent with Phase 3 audio-callback discipline; the renderer callback is a *display* regime (Metal encode is allowed here, unlike the acquisition hot path).

---

## Decision 2 — macOS display-link path: `NSScreen/NSView.displayLink` → `CADisplayLink` (RENDER-08)

**Why different (spec + docs):** `CADisplayLink` "A timer object that allows your app to synchronize its drawing to the refresh rate" — macOS 14.0+. `func NSScreen.displayLink(target:selector:) -> CADisplayLink` returns a CADisplayLink synced to that screen. The CADisplayLink doc itself says: *"If your app needs more control over refresh rate … use `CAMetalDisplayLink` and the information from `CAMetalDisplayLink.Update` instances"* — i.e. CAMetalDisplayLink is the richer Metal path, but the cortex-spec deliberately uses the CADisplayLink path on native AppKit (CAMetalDisplayLink wants an AppKit-thread tick; CVDisplayLink is rejected as legacy).

**Recommendation — prefer `NSView.displayLink(target:selector:)` over `NSScreen.displayLink`:** the AppKit docs note views/windows move between screens and `NSView`/`NSWindow.displayLink` "track those changes automatically." For a single-window demo either works; `NSView.displayLink` is more robust to screen moves at zero extra cost.

**Plumbing differences vs iOS (the adapter must handle):**
- **No vended drawable** — in the selector you call `metalLayer.nextDrawable()` yourself (may return nil under contention → skip the frame).
- `selector` receives the `CADisplayLink`; read `.timestamp` / `.targetTimestamp` / `.duration` for pacing and the integrator dt (`1 / (targetTimestamp - timestamp)` = actual fps).
- 120Hz: set the returned link's `.preferredFrameRateRange = CAFrameRateRange(120,120,120)` (CADisplayLink supports it, macOS 14+). The M5 Pro MacBook Pro built-in panel is ProMotion 120Hz → this is the CONTEXT D-11 corroborating-canonical surface.

**Shared core:** factor a `WebgridFrameEncoder` (takes a `CAMetalDrawable` + the current cursor position) used by *both* adapters; only drawable-acquisition + pacing differ between the `CAMetalDisplayLinkDelegate` (iOS) and the `@objc` selector (macOS).

---

## Decision 3 — Frame pacing: `dispatch_semaphore(value:1)` + drawable pool (RENDER-07)

**The canonical pattern (Apple "Synchronizing CPU and GPU Work"):**
```
sem = dispatch_semaphore_create(MaxFramesInFlight)   // sample uses 3
// per frame:
dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER)
// … encode using the in-flight resource instance …
commandBuffer.addCompletedHandler { _ in dispatch_semaphore_signal(sem) }
commandBuffer.present(drawable); commandBuffer.commit()
```
**Cortex divergence (locked, intentional):** `value: 1` (RENDER-07) = strictly one frame in flight = **lowest latency**, trading away the CPU(n+1)/GPU(n) overlap the sample's `value:3` buys. Pair with `CAMetalLayer.maximumDrawableCount = 2` (only `2` or `3` allowed; `2` is the low-latency choice) and `preferredFrameLatency = 1.0`. The wait/signal mechanism is identical; only the count differs. **Annotate this in code** so a future reader (or the planner) doesn't "optimize" it back to triple-buffering and silently add a frame of latency to the glass-to-glass budget (PERF-04).

**Gotcha:** with `value:1` the CPU blocks on the previous frame's GPU completion before encoding the next — if the compute pass ever exceeds the frame interval (8.33ms @120Hz), you drop to 60Hz. At ≤0.4ms GPU target there is enormous headroom, so this is safe; SC#4 (60s no-drop soak) validates it.

---

## Decision 4 — 30×30 webgrid compute shader → drawable (RENDER-04/06)

**Constraint (confirmed):** `CAMetalLayer.framebufferOnly` defaults `true` → drawable textures are `.renderTarget`-only ("may not sample, read from, or write to those textures"). A compute kernel writing the grid into the drawable needs **`framebufferOnly = false`**.

**Two viable paths (planner picks; (a) recommended for simplicity at this cell count):**
- **(a) Compute-direct-to-drawable:** `framebufferOnly = false`; one compute encoder writes all ~900 cells + cursor + proximity-highlight into `update.drawable.texture` (`access::write` texture). Simplest; one pass; the CA-optimization cost is negligible for a full-screen compute write at 120Hz on M-series.
- **(b) Compute-offscreen + present:** keep `framebufferOnly = true`; compute into an offscreen `MTLTexture` (`.shaderWrite | .shaderRead`, `storageModeShared`/`.private`), then a tiny render/blit pass into the drawable. More encoders, but lets CA keep the drawable optimized and isolates the compute target.

**Webgrid kernel shape:** dispatch one threadgroup-grid over the 30×30 lattice (or over output pixels, mapping pixel→cell). Cell geometry (filled rounded cells, D-06), dark palette (D-07), bright-disc cursor (D-08), and cursor-proximity brightening (D-09) are all cheap per-pixel math — well within ≤0.4ms for ~900 cells on M4. Pass cursor position + grid params via `setBytes` (small constant) or a `storageModeShared` uniforms buffer (RENDER-06). Drawable pixel format `.bgra8Unorm` (or `.rgba16Float` if HDR wanted — not needed).

**RENDER-06 zero-copy:** all CPU-written buffers (uniforms, cursor pos) use `MTLResourceStorageModeShared` (unified memory; the sample uses exactly this for its vertex buffers). No blit from a `.managed`/staging buffer.

---

## Decision 5 — Cursor-velocity input seam (CONTEXT D-03/D-04/D-05) — project-internal

Little external research needed; this reuses Phase 3 assets. **Plan:**
- **Seam:** a small `CursorVelocity { ts_ns: u64, seq: u64, vx: f16, vy: f16 }` (matches DEC-10's 2-vector fp16 @20ms). The producer→renderer hop is **in-process** in Phase 6 (no daemon), so the ring can be either a second `#[repr(C)]` Rust SPSC instantiation + cbindgen (mirrors `cortex_ring.h`) **or** a small Swift-side SPSC. Recommend the **Swift-side ring for Phase 6** (in-process, no cross-FFI need yet) with the *struct layout* chosen to match a future `#[repr(C)]` so Phase 7's decoder/Kalman producer can swap to the Rust ring without changing the renderer. (Flagged as discretion in CONTEXT — lean Swift-side now.)
- **Integrator (renderer-owned, D-04):** `pos += velocity * dt`, `dt` from `update.targetPresentationTimestamp - prev` (iOS) or `targetTimestamp - timestamp` (macOS); clamp `pos` to grid bounds. Empty ring → `velocity = 0` (cursor holds). Decouple the 20ms (50Hz) velocity cadence from the 120Hz render: the renderer integrates with the latest available velocity each frame (zero-order hold), so 120Hz visual smoothness is independent of the 50Hz input.
- **Synthetic drive (D-05):** deterministic Lissajous `v(t) = (A·ω·cos(ω₁t), B·ω·sin(ω₂t))` (or position-parametric, differentiated) — reproducible for the 60s soak.

---

## Decision 6 — GPU-time + frame-pacing measurement (RENDER-05/09, SC#2/SC#4)

- **Live (RENDER-09):** `MTL_HUD_ENABLED=1` in the scheme env (set in `project.yml` schemes) → on-screen P95 frame time, drawable-wait, encoder-time. Zero code.
- **Programmatic GPU compute time (SC#2 ≤0.4ms):** `commandBuffer.gpuEndTime - commandBuffer.gpuStartTime` (CFTimeInterval, public, set after completion) per frame → histogram; or an `MTLCounterSampleBuffer` (`MTLCounterSet` `.timestamp`) sampling at compute-encoder start/end for the *compute-pass-only* time (tighter than whole-frame). Record p50/p95/p99 over the soak.
- **Sustained 120Hz, no drops (SC#4):** count callbacks over 60s; assert ≥ (120·60·(1−ε)); log any interval > 8.33ms. Drive with the deterministic Lissajous so the run is reproducible.
- **Where (CONTEXT D-10/D-11):** all of the above run on the **M5 Pro MacBook Pro ProMotion** now (corroborating-canonical); the iPad-M4 capture is the canonical/optional-future datapoint via `06-HUMAN-UAT.md`. **iPad Air M2 cannot serve SC#4** (60Hz panel) — GPU-compute-time corroboration only.

---

## Decision 7 — Info.plist + 120Hz unlock (RENDER-03)

- `Info.plist` **`CADisableMinimumFrameDurationOnPhone = <true/>`** (iOS 15+) — without it the system caps above-default frame rates on ProMotion. Goes in `Apps/CortexiOS/Info.plist` (the `project.yml` placeholder comment already marks the spot). **Build-time assertion (SC#3):** a CI/plist check that the key is present and `true` (mirrors the Phase 1 `validate-privacy-manifest.sh` / no-sandbox grep-gate discipline).
- macOS needs no equivalent key (ProMotion governed by the display + `preferredFrameRateRange`).

---

## Hardware strategy — what's gated on what (mirrors THREAD-02 / SC#1 / Phase-5 precedent; CONTEXT D-10/D-11)

| Requirement | CI-structural (macos-15, build-failing) | Mac M5 Pro ProMotion — corroborating-canonical NOW | iPad Pro M4 — canonical artifact (HUMAN-UAT, optional/future) |
|---|---|---|---|
| RENDER-01 CAMetalDisplayLink (iOS) / no CADisplayLink-for-Metal | ✅ grep: `CAMetalDisplayLink` present, no `CADisplayLink` on the **iOS** Metal path | (runs) | (runs) |
| RENDER-08 macOS `NSScreen/NSView.displayLink`, no Catalyst | ✅ grep: `displayLink(target:` present; `SUPPORTS_MACCATALYST: NO` | ✅ **primary** (runs live) | — |
| RENDER-02 sustained 120Hz | ⚠ can't prove rate in CI | ✅ **canonical** (built-in ProMotion) | ✅ canonical (spec target) |
| RENDER-03 `CADisableMinimumFrameDurationOnPhone=YES` | ✅ **primary** (plist build check) | — | (enables 120Hz) |
| RENDER-04 compute-shader grid | ✅ grep: compute kernel + dispatch present | ✅ runs | ✅ runs |
| RENDER-05 GPU ≤0.4ms | ⚠ — | ✅ **corroborating-canonical** (gpuStartTime/EndTime + HUD) | ✅ canonical (M4) |
| RENDER-06 `storageModeShared` drawables/buffers | ✅ **primary** grep | ✅ runs | ✅ runs |
| RENDER-07 `dispatch_semaphore(value:1)` 1-in-flight | ✅ **primary** grep (`value:1`, `maximumDrawableCount=2`) | ✅ runs | ✅ runs |
| RENDER-09 `MTL_HUD_ENABLED=1` in scheme | ✅ **primary** (scheme env check) | ✅ visible | ✅ visible |
| SC#4 60s no-drop soak | ⚠ — | ✅ **canonical** (120Hz panel) | ✅ canonical |

**SC reframe (D-11, apply at plan/execute with sign-off, Phase-5 style):** ROADMAP SC#2/SC#4 + REQUIREMENTS RENDER-02/05 wording → "measured on M5 Pro ProMotion; iPad Pro M4 capture optional/future." iPad Air M2 (60Hz) is explicitly insufficient for the 120Hz claims.

---

## Recommended build order (for the planner — not prescriptive on plan count)

1. **CortexRender core + shared encoder (`Packages/CortexRender`):** `CAMetalLayer` config (`framebufferOnly` per D4, `maximumDrawableCount=2`, `presentsWithTransaction=false`, `storageModeShared` uniforms), the 30×30 webgrid compute kernel (`.metal`), and a platform-agnostic `WebgridFrameEncoder(drawable:, cursorPos:)`. → RENDER-04, RENDER-06.
2. **Velocity seam + integrator:** `CursorVelocity` struct + in-process SPSC (Swift-side, `#[repr(C)]`-compatible layout) + renderer-owned integrator (clamp to grid) + deterministic Lissajous synthetic producer. → CONTEXT D-03/D-04/D-05 (feeds the cursor).
3. **iOS adapter:** `CAMetalDisplayLinkDelegate` over a `CAMetalLayer`; `preferredFrameRateRange=120`, `preferredFrameLatency=1.0`; `value:1` semaphore wait/signal; render `update.drawable`; plain `present`. → RENDER-01, RENDER-02, RENDER-07.
4. **macOS adapter:** `NSView.displayLink(target:selector:)` → CADisplayLink; `preferredFrameRateRange=120`; manual `nextDrawable()`; same semaphore + shared encoder. → RENDER-08.
5. **Info.plist + scheme + CI gates:** `CADisableMinimumFrameDurationOnPhone=YES` (iOS plist) + build-time check; `MTL_HUD_ENABLED=1` in both schemes; grep gates (no `CADisplayLink` on iOS Metal path, `storageModeShared`, `value:1`/`maximumDrawableCount=2`, `displayLink(target:`). → RENDER-03, RENDER-09, SC#1 structural.
6. **Measurement + soak (Mac now):** `gpuStartTime/EndTime` (or counter buffer) histogram + 60s no-drop soak on M5 Pro ProMotion; commit `frame_pacing_{json,png}` + HUD screenshot. → RENDER-05, SC#2/SC#4 corroborating.
7. **`06-HUMAN-UAT.md` runbook (iPad-M4, present-not-auto-approve, D-12):** verbatim steps for on-device ≤0.4ms GPU + 60s 120Hz capture + HUD/Instruments artifacts a reviewer checks. → SC#2/SC#4 canonical (deferred).

**Swift 6.2 note:** `CAMetalDisplayLinkDelegate` callbacks + the `@objc` macOS selector run on the run-loop thread; mind `MainActor`/`Sendable` isolation (project uses `.defaultIsolation(MainActor.self)`). The encoder + ring should be `Sendable`-clean; avoid actor hops in the callback (latency). No `print()` on the path (os.Logger).

---

## Validation Architecture (Nyquist)

Each requirement gets a *characterization* (measured value + bound with margin), not just a boolean — mirrors Phase-4/5 evidence-doc discipline.

| Req | Validation method | Sampling / N | Pass condition | Artifact |
|---|---|---|---|---|
| RENDER-01 | grep + build; iOS delegate fires | callback present | `CAMetalDisplayLink` used; iOS Metal path has no `CADisplayLink` | CI log |
| RENDER-02 | callback-rate count (Mac ProMotion) | 60s | sustained ≈120Hz | `frame_pacing.json` |
| RENDER-03 | plist build-time check | 1 (gate) | key present == `true` | CI log |
| RENDER-04 | grep + frame-capture | compute pass | compute kernel writes grid; ~900 cells | capture note |
| RENDER-05 | `gpuStartTime/EndTime` or counter buffer | n≥10k frames | p99 ≤0.4ms (M4 canonical; M5 annotated) | `gpu_time_hist.{json,png}` |
| RENDER-06 | grep + buffer audit | all CPU buffers | `storageModeShared`; no staging blit | CI log |
| RENDER-07 | grep + code review | inference path | `dispatch_semaphore(value:1)`; `maximumDrawableCount=2` | CI log |
| RENDER-08 | grep + macOS run | callback | `NSView/NSScreen.displayLink`; no Catalyst | CI log + run |
| RENDER-09 | scheme env check + screenshot | 1 | `MTL_HUD_ENABLED=1` present; HUD visible | scheme + screenshot |
| SC#4 | 60s soak (Mac ProMotion) | 120·60 frames | zero intervals >8.33ms (ε bound) | soak log |

---

## Risks & open questions

1. **(MED) Two display-link code paths** — iOS `CAMetalDisplayLink.Update` (vended drawable) vs macOS `CADisplayLink` (manual `nextDrawable()`). Mitigation: a shared `WebgridFrameEncoder`; only acquisition+pacing differ. Don't try to unify with CAMetalDisplayLink-on-macOS (AppKit-thread-tick caveat, spec-rejected).
2. **(MED) `framebufferOnly=false` vs offscreen+blit** (Decision 4) — direct-to-drawable is simplest but disables a CA optimization; offscreen+blit is more code. Cheap at 900 cells either way; pick (a) unless GPU time exceeds budget, then try (b). Surface as an explicit plan decision.
3. **(MED) `value:1` latency choice misread as a bug** — annotate heavily (Decision 3) so it isn't "optimized" back to triple-buffering, which would add a frame (~8.3ms) to PERF-04's glass-to-glass budget.
4. **(LOW) iPad Air M2 is 60Hz** — cannot demonstrate SC#4 120Hz at all; Mac ProMotion is the live canonical surface; iPad-M4 deferred (CONTEXT D-11). Honest reframe required at plan/execute (Phase-5 precedent).
5. **(LOW) Drawable starvation under `value:1` + `maximumDrawableCount=2`** — `nextDrawable()` (macOS) can return nil under contention; handle by skipping the frame, not blocking. With ≤0.4ms GPU there's ample headroom.
6. **(LOW) macOS `nextDrawable()` autorelease** — wrap the macOS callback body in an explicit autorelease scope to avoid drawable retention across frames (classic CAMetalLayer stutter cause seen in the SO/forum threads).

## Main-thread-gated research
None outstanding — this pass ran on the main thread (browser-harness Apple-DocC JSON + scraper digest). No items deferred to a browser-only follow-up. (Optional enrichment, not blocking: WWDC23 session 10123 video transcript and Apple Dev Forums thread/763426 "Running 120Hz with low latency" for additional pacing gotchas.)

## Citations
- Apple — `CAMetalDisplayLink` (iOS 17+/macOS 14+): https://developer.apple.com/documentation/quartzcore/cametaldisplaylink ; delegate `metalDisplayLink(_:needsUpdate:)`: https://developer.apple.com/documentation/quartzcore/cametaldisplaylinkdelegate/metaldisplaylink(_:needsupdate:) ; `Update` (`drawable`/`targetTimestamp`/`targetPresentationTimestamp`): https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/update
- Apple — `preferredFrameRateRange`: https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/preferredframeraterange ; `preferredFrameLatency` (only 1.0/2.0): https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/preferredframelatency
- Apple — `NSScreen.displayLink(target:selector:)` (macOS 14+, returns CADisplayLink): https://developer.apple.com/documentation/appkit/nsscreen/displaylink(target:selector:) ; `CADisplayLink`: https://developer.apple.com/documentation/quartzcore/cadisplaylink ; `CADisplayLink.preferredFrameRateRange`: https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange
- Apple — Sample "Achieving smooth frame rates with a Metal display link" (WWDC23 s10123, doc current to Xcode 26.3): https://developer.apple.com/documentation/metal/metal_sample_code_library/achieving_smooth_frame_rates_with_metal_s_display_link
- Apple — Sample "Synchronizing CPU and GPU Work" (semaphore + MaxFramesInFlight + storageModeShared): https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work
- Apple — `CAMetalLayer.framebufferOnly`: https://developer.apple.com/documentation/quartzcore/cametallayer/framebufferonly ; `maximumDrawableCount` (2 or 3): https://developer.apple.com/documentation/quartzcore/cametallayer/maximumdrawablecount ; `presentsWithTransaction`: https://developer.apple.com/documentation/quartzcore/cametallayer/presentswithtransaction
- Apple — `CADisableMinimumFrameDurationOnPhone` (Info.plist, iOS 15+): https://developer.apple.com/documentation/bundleresources/information-property-list/cadisableminimumframedurationonphone
- WWDC21 "Optimize for variable refresh rate displays": https://developer.apple.com/videos/play/wwdc2021/10147/
- Frame-pacing concepts — Raph Levien, "Swapchains and frame pacing": https://raphlinus.github.io/ui/graphics/gpu/2021/10/22/swapchain-frame-pacing.html
- Field gotchas — Apple Dev Forums: "Running 120Hz with low latency" https://developer.apple.com/forums/thread/763426 ; "Is CAMetalDisplayLink expected to…" https://developer.apple.com/forums/thread/743684 ; CAMetalLayer/CVDisplayLink fullscreen stutter (autorelease/nextDrawable): https://stackoverflow.com/questions/76598416/
- Local canonical spec: `docs/cortex-spec.md` §3 "Renderer (Finding 3, 91 sources)" (lines ~60-67, 271-282)

---

*Phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid*
*Research method: main-thread browser-harness (Apple DocC JSON via http_get) + ~/Developer/scrapers digest. Run 2026-06-21.*
