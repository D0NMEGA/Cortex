---
phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid
plan: 05
subsystem: testing
tags: [metal, gpu-timing, gpuStartTime, gpuEndTime, cfTimeInterval, render-bench, percentile-histogram, frame-soak, promotion-120hz, offscreen-drawable, lissajous, device-annotation, honest-reframe, mainactor-isolation]

# Dependency graph
requires:
  - phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid (Plan 01)
    provides: WebgridFrameEncoder (the real 30x30 / 900-cell webgrid compute pass the bench measures), WebgridParams.grid30x30, MetalLayerConfig (the bgra8Unorm + framebufferOnly=false drawable write scope the offscreen texture mirrors), Webgrid.metal (the bounds-guarded kernel)
  - phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid (Plan 02)
    provides: LissajousProducer.velocity(at:) (deterministic reproducible drive, D-05), CursorIntegrator.integrate(latest:dt:) (clamp/NaN-reject), CursorVelocity seam type
  - phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid (Plan 03)
    provides: MacDisplayLinkAdapter (the encode pattern the bench mirrors; the on-panel mode-b soak surface), FrameSynchronizer value:1 (the one-frame-in-flight gate documented in the on-panel run steps)
  - phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid (Plan 04)
    provides: CortexRenderBench type:tool XcodeGen target + scheme (CortexRender + CortexCore deps) and the main.swift stub this plan replaces; MTL_HUD_ENABLED=1 in the CortexMac scheme (the on-panel HUD read)
  - phase: 05-ndt1-coreml-deployment-with-ane-residency-verified
    provides: the CortexDecoderBench + 05-placement-evidence.md honest-reframe precedent (warmup + N passes + device-annotated percentile histogram + committed evidence; corroborating-vs-canonical framing)
provides:
  - "CortexRenderBench/GPUTimeHistogram.swift — measures the REAL webgrid compute pass over n>=10k offscreen frames via commandBuffer.gpuEndTime-gpuStartTime, reducing to a device-annotated p50/p95/p99 histogram + gpu_time_hist.json (RENDER-05)"
  - "CortexRenderBench/FrameSoak.swift — a 60s sustained-throughput soak (offscreen mode a) driven by the deterministic LissajousProducer (D-05), counting any interval > 8.33ms (SC#4), + documented on-panel mode-b run steps + soak_log.json"
  - "OffscreenDrawable — a CAMetalDrawable-conforming wrapper over an offscreen MTLTexture so the headless bench drives the UNCHANGED WebgridFrameEncoder (measures the identical compute workload, no window)"
  - "06-render-evidence.md — device-annotated GPU p50/p95/p99 vs <=0.4ms SC#2 (PASS, ~2.5x margin) + SC#4 60s soak verdict (243724 frames, 0 over-budget), M5 Pro corroborating-canonical (D-11), iPad-M4 deferred (D-12), with the honest what-this-is-NOT framing"
  - "Measured M5 Pro numbers: GPU p99=0.1618ms (n=10k); 60s soak 4062Hz / 0 intervals > 8.33ms"
affects: [Plan 06-06 (the iPad-M4 canonical capture this Mac-corroborating tier stands in for; the SC reframe sign-off; 06-HUMAN-UAT.md never-auto-approve checkpoint), 06-VERIFICATION (SC#2/SC#4 evidence rows), Phase 7 (the ReFIT-Kalman producer replaces LissajousProducer behind the unchanged seam; the bench can re-measure the same kernel)]

# Tech tracking
tech-stack:
  added: [CortexRenderBench executable (the GPU-time + soak bench), commandBuffer.gpuStartTime/gpuEndTime CFTimeInterval GPU-time measurement, OffscreenDrawable CAMetalDrawable wrapper over an offscreen MTLTexture, nearest-rank percentile reduction, MainActor.assumeIsolated tool entry-point]
  patterns:
    - "Dedicated measurement bench executable (warmup + N passes + device-annotated percentile histogram + committed evidence .md) — the Phase-5 CortexDecoderBench discipline, now for the renderer; a bench NOT a swift-test timing gate (D-18, keeps a flaky latency assertion out of CI)"
    - "Headless GPU-kernel measurement via a CAMetalDrawable-conforming offscreen-texture wrapper: drives the UNCHANGED production encoder (so the grep-asserted real kernel IS measured) with no window; present* are no-ops, commit + waitUntilCompleted reads gpuEndTime-gpuStartTime"
    - "Honest device-annotation / corroborating-vs-canonical reframe (Phase-5 05-placement-evidence.md): every number carries device.name (in JSON + doc), labels M5 Pro corroborating-canonical (D-11), labels the canonical iPad-M4 capture deferred optional/future (D-12), and carries a what-this-is-NOT paragraph — never substitutes the available-device number for the spec's canonical-device claim (threat T-06-05-01)"
    - "Deterministic reproducible measurement workload (D-05): the per-frame cursor is closed-form LissajousProducer.velocity(at: t) with no RNG / no clock-derived workload, so the histogram is bit-stable run-to-run (the only time input is the 60s wall-clock bound + the measured intervals) — confirmed by two 10k runs giving p99=0.1615/0.1618ms"
    - "MainActor-isolated tool entry-point: a type:tool executable whose top-level code enters the MainActor-isolated bench (driving CortexRender's .defaultIsolation(MainActor.self) encoder) via MainActor.assumeIsolated — sound because the bench is single-threaded with no other actors"

key-files:
  created:
    - Apps/CortexRenderBench/GPUTimeHistogram.swift
    - Apps/CortexRenderBench/FrameSoak.swift
    - .planning/phases/06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid/06-render-evidence.md
    - .planning/phases/06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid/gpu_time_hist.json
    - .planning/phases/06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid/soak_log.json
  modified:
    - Apps/CortexRenderBench/main.swift

key-decisions:
  - "Measured at a representative 2752x2064 (~5.68M-px, iPad-Pro-M4-13-class) drawable extent, NOT a toy texture — the SC#2 <=0.4ms bound is a full-surface claim, so the bench writes a full-surface-class offscreen target; p99=0.1618ms there is an honest full-frame number with 2.5x margin (a 512x512 toy gave p99=0.03ms, which would have overstated the headroom)"
  - "Reused the UNCHANGED WebgridFrameEncoder via an OffscreenDrawable CAMetalDrawable wrapper rather than re-implementing the encode against an MTLTexture — this is what makes the grep-asserted 'WebgridFrameEncoder' check honest (the bench measures the IDENTICAL kernel + setBytes upload + dispatchThreads-to-extent the live adapters run), and the only divergence (present -> no-op, commit+waitUntilCompleted) is the documented headless substitution"
  - "SC#4 split into mode (a) offscreen-throughput (measured headless: 60s, 243724 frames, 4062Hz, 0 over-budget) + mode (b) on-panel 120Hz refresh (documented exact CortexMac-scheme run steps + the MTL_HUD P95-frame-time read) — honest that throughput-headroom and display-refresh are distinct, and the canonical refresh proof is the live/iPad run, not the headless number"
  - "Honest device-annotation per the Phase-5 reframe (T-06-05-01): the evidence doc + both JSON artifacts carry device.name, label M5 Pro corroborating-canonical (D-11) and the iPad-M4 capture deferred optional/future (06-HUMAN-UAT.md, D-12), and carry the what-this-is-NOT paragraph — the M5 Pro number is NEVER presented as the spec's canonical iPad-M4 number (the MEMORY rule: device checkpoints never auto-approve / auto-approving fabricates load-bearing numbers)"
  - "Made the bench MainActor-isolated (GPUTimeHistogram.run / FrameSoak.run / runFrameSoak @MainActor; main.swift enters via MainActor.assumeIsolated) to satisfy CortexRender's .defaultIsolation(MainActor.self) on WebgridFrameEncoder under SWIFT_STRICT_CONCURRENCY: complete — a blocking compile fix (Rule 3), not an architectural change; the single-threaded bench has no other actor so assumeIsolated is sound"

patterns-established:
  - "Pattern: the renderer's GPU-time/soak bench is the Mac-corroborating tier (D-10 tier 2) complement to Plan 04's CI-structural gate (tier 1) — the gate proves the invariants statically every CI run, the bench measures the live numbers a headless runner cannot, exactly as Phase-5 split eligibility (Mac CI) from placement (device capture)"
  - "Pattern: a CAMetalDrawable-conforming offscreen wrapper is the headless harness for ANY drawable-taking encoder — drives production code unchanged, measures the real kernel, no window/display-link required (reusable for Phase 7 when the Kalman producer replaces Lissajous behind the same seam)"

requirements-completed: [RENDER-02, RENDER-05]

# Metrics
duration: 10min
completed: 2026-06-22
---

# Phase 6 Plan 05: Mac GPU-Time Measurement + 60s Sustained-Throughput Soak Summary

**A `CortexRenderBench` executable that measures the REAL 30×30 / 900-cell `webgrid` compute pass (the unchanged `WebgridFrameEncoder`, driven headless via a `CAMetalDrawable`-conforming offscreen-texture wrapper) over n=10 000 frames via `commandBuffer.gpuEndTime − gpuStartTime` → a device-annotated p50/p95/p99 histogram, plus a 60 s deterministic-Lissajous sustained-throughput soak flagging any interval > 8.33 ms — RUN ON THIS M5 Pro ProMotion to capture genuine numbers (GPU p99 = 0.1618 ms, SC#2 ≤0.4 ms PASS with ~2.5× margin; 60 s soak = 243 724 frames / 4062 Hz / 0 over-budget, SC#4 throughput PASS) — committed as `06-render-evidence.md` + `gpu_time_hist.json` + `soak_log.json`, honestly device-annotated M5 Pro corroborating-canonical (D-11) with the iPad-Pro-M4 canonical capture deferred optional/future (D-12).**

## Performance

- **Duration:** 10 min
- **Started:** 2026-06-22T03:06:57Z
- **Completed:** 2026-06-22T03:16:27Z
- **Tasks:** 2
- **Files modified:** 6 (5 created, 1 modified)

## Measured Numbers (genuine, on Apple M5 Pro / macOS 26.5 / Xcode 26.3 / Swift 6.2.4)

**RENDER-05 / SC#2 — GPU compute time (n = 10 000 frames @ 2752×2064 real webgrid pass):**

| Metric | ms |
|--------|---:|
| p50 | 0.0798 |
| p95 | 0.0801 |
| **p99** | **0.1618** |
| min / max / mean | 0.0795 / 0.1629 / 0.0822 |

→ **SC#2 ≤ 0.4 ms (p99): PASS**, margin **0.2382 ms (~2.5×)**. Reproducibility: two 10k runs gave p99 = 0.1615 / 0.1618 ms (time-noise on a bit-identical deterministic workload, D-05).

**SC#4 — 60 s sustained-throughput soak (offscreen mode a, deterministic Lissajous):**

- 60.000 s, **243 724 frames**, **4062.1 Hz achieved** (≈ 34× the 120 Hz target)
- **0 intervals > 8.33 ms** (max 2.369 ms, mean 0.246 ms) → **SC#4 (throughput) PASS — zero over-budget frames**

## Accomplishments

- **`GPUTimeHistogram.swift` (Task 1) — the RENDER-05 GPU-compute-time core.** Creates a system `MTLDevice` + queue + the real `WebgridFrameEncoder`, encodes the `webgrid` kernel into an offscreen `.bgra8Unorm`/`.shaderWrite` `MTLTexture` (the identical write scope `MetalLayerConfig.framebufferOnly = false` opens on the live drawable), and over n ≥ 10k frames reads `commandBuffer.gpuEndTime − gpuStartTime` (CFTimeInterval seconds → ms, valid post-`waitUntilCompleted`, 06-RESEARCH Decision 6), reducing to nearest-rank p50/p95/p99 + min/max/mean and writing `gpu_time_hist.json` (raw percentiles + `device.name` + texture extent). 200 warmup frames discarded; allocation-light loop, no per-frame `print()`.
- **`OffscreenDrawable` — the headless harness.** A `CAMetalDrawable`-conforming wrapper over the offscreen texture so the bench drives the **UNCHANGED** production encoder (this is what makes the grep-asserted `WebgridFrameEncoder` honest — the identical kernel + `setBytes` upload + `dispatchThreads`-to-extent is measured); `present*` are no-ops, the bench `commit()`s + `waitUntilCompleted`s to read the timestamps.
- **`FrameSoak.swift` (Task 2) — the SC#4 soak.** A 60 s wall-clock encode+commit+wait loop over the same offscreen path, driven by the deterministic `LissajousProducer` (D-05), recording every per-frame interval and counting any > 8.33 ms (the 120 Hz budget). Reports frames / achieved Hz / over-budget count / max+mean interval and writes `soak_log.json`. Documents **mode (b)** — the canonical on-panel 120 Hz refresh proof via the `CortexMac` scheme + `MacDisplayLinkAdapter` + the `MTL_HUD` P95 read — with exact run steps (also embedded in `FrameSoak.onPanelRunSteps`).
- **`main.swift` (modified) — the CLI.** Replaced the Plan-04 stub with an arg-parsed entry point (`frames` clamped ≥10 000 per RENDER-05, `WxH` extent default 2752×2064, `--warmup`, `--soak [sec]`, `--out`); MainActor-isolated run (`MainActor.assumeIsolated`) to drive the MainActor-isolated encoder under strict concurrency.
- **`06-render-evidence.md` — the device-annotated evidence.** GPU p50/p95/p99 table vs the ≤0.4 ms SC#2 bound with margin; the SC#4 60 s soak verdict (mode a measured + mode b on-panel run steps); the `MTL_HUD` read note (RENDER-09); a reproducibility + bounds-safety section; and the honest **"what this is / what this is NOT"** paragraph — **M5 Pro ProMotion corroborating-canonical (D-11)**, **iPad-Pro-M4 canonical capture deferred optional/future (`06-HUMAN-UAT.md`, D-12)**, the number **never** substituted for the spec's canonical M4 claim. Mirrors the Phase-5 `05-placement-evidence.md` discipline exactly.

## Task Commits

Each task was committed atomically:

1. **Task 1: GPU-time histogram bench (gpuEndTime − gpuStartTime over n≥10k frames)** — `b6eed6d` (feat) — `GPUTimeHistogram.swift` + `main.swift`
2. **Task 2: 60s sustained-throughput soak + device-annotated evidence** — `5d1e119` (feat) — `FrameSoak.swift` + `06-render-evidence.md` + `gpu_time_hist.json` + `soak_log.json`

_Plan metadata commit + STATE/ROADMAP/REQUIREMENTS owned by the orchestrator (this sequential executor does not write them)._

## Files Created/Modified

- `Apps/CortexRenderBench/GPUTimeHistogram.swift` — GPU-compute-time histogram core + `OffscreenDrawable` wrapper (created)
- `Apps/CortexRenderBench/FrameSoak.swift` — 60s sustained-throughput soak + on-panel mode-b run steps + `runFrameSoak` CLI bridge (created)
- `Apps/CortexRenderBench/main.swift` — arg-parsed, MainActor-isolated CLI replacing the Plan-04 stub (modified)
- `.planning/.../06-render-evidence.md` — device-annotated GPU + soak evidence, honest M5-Pro-corroborating / iPad-M4-deferred framing (created)
- `.planning/.../gpu_time_hist.json` — measured p50/p95/p99 + device + extent (created)
- `.planning/.../soak_log.json` — measured 60s soak: mode, frames, achieved Hz, over-budget count, device (created)

## Decisions Made

- **Representative 2752×2064 extent, not a toy.** The SC#2 ≤0.4 ms bound is a full-surface claim, so the bench writes a full-surface-class (~5.68 M px) offscreen target; p99 = 0.1618 ms there is an honest full-frame number (a 512×512 toy gave 0.03 ms and would have overstated the headroom).
- **Reused the unchanged `WebgridFrameEncoder` via `OffscreenDrawable`.** Makes the grep-asserted `WebgridFrameEncoder` check honest — the identical kernel/upload/dispatch is measured; the only divergence is the documented headless substitution (`present` → no-op, `commit` + `waitUntilCompleted`).
- **SC#4 split into measured-throughput (mode a) + documented on-panel-refresh (mode b).** Honest that GPU-workload headroom (measured: 4062 Hz, 0 over-budget) and on-display 120 Hz refresh (the live `CortexMac` HUD run / iPad-M4 capture) are distinct claims.
- **Honest device-annotation (T-06-05-01).** Every number carries `device.name`; M5 Pro labelled corroborating-canonical (D-11); the iPad-M4 capture labelled deferred optional/future (D-12); the what-this-is-NOT paragraph present. The M5 Pro number is never the spec's canonical M4 number.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] MainActor-isolated the bench to satisfy `CortexRender`'s default MainActor isolation**
- **Found during:** Task 1 (first `xcodebuild build`)
- **Issue:** `WebgridFrameEncoder.init` + `.encode(into:commandBuffer:params:)` are `@MainActor`-isolated because `CortexRender` declares `swiftSettings: [.defaultIsolation(MainActor.self)]` (Package.swift). The bench's nonisolated `run` methods + nonisolated `main.swift` top-level code calling them failed to compile under the target's `SWIFT_STRICT_CONCURRENCY: complete` ("call to main actor-isolated instance method … in a synchronous nonisolated context").
- **Fix:** Annotated `GPUTimeHistogram.run`, `FrameSoak.run`, and `runFrameSoak` `@MainActor`, and wrapped `main.swift`'s execution in `MainActor.assumeIsolated { … }`. Sound: the bench is single-threaded with no other actors, and a `type: tool` executable's top-level code runs on the main thread. Not an architectural change — the encoder's isolation is pre-existing; this conforms the bench to it.
- **Files modified:** `Apps/CortexRenderBench/{GPUTimeHistogram,FrameSoak,main}.swift`
- **Verification:** `xcodebuild build -scheme CortexRenderBench … CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED**; the bench then ran and produced genuine numbers.
- **Committed in:** `b6eed6d` (Task 1) for GPUTimeHistogram/main; `5d1e119` (Task 2) for FrameSoak.

**2. [Rule 3 - Blocking] Promoted `OffscreenDrawable` from `private` to module-internal**
- **Found during:** Task 2 (`xcodebuild build` after adding FrameSoak.swift)
- **Issue:** `OffscreenDrawable` was `private` to `GPUTimeHistogram.swift`; `FrameSoak.swift` (same module) could not see it ("cannot find 'OffscreenDrawable' in scope") — it reuses the identical offscreen-drawable path.
- **Fix:** Changed `private final class` → `final class` (module-internal) so both `GPUTimeHistogram` and `FrameSoak` share the one wrapper (they measure the same encode path, just frame-count vs duration).
- **Files modified:** `Apps/CortexRenderBench/GPUTimeHistogram.swift`
- **Verification:** `xcodebuild build` → **BUILD SUCCEEDED**; both bench files compiled.
- **Committed in:** `5d1e119` (Task 2 — the visibility change is in GPUTimeHistogram.swift, but it was already committed in Task 1 with the `final class` form, so Task 2 only added FrameSoak.swift; see note below).

> Note on commit boundary: `OffscreenDrawable` was authored module-internal before the Task-1 commit (the visibility fix was applied while iterating on the build, prior to staging), so it is in `b6eed6d`. FrameSoak.swift (which consumes it) is in `5d1e119`. Both per-task verifications were run against the working tree (which always had both source files present, as `xcodebuild` compiles the whole target) — the standard sequential-executor verify-against-working-tree pattern.

---

**Total deviations:** 2 auto-fixed (2 Rule 3 - Blocking: Swift 6.2 strict-concurrency MainActor isolation + a module-visibility fix).
**Impact on plan:** Both were mechanical compile-blockers from the pre-existing `CortexRender` MainActor isolation + Swift module visibility — no behavior change, no architectural change, no scope creep. The two source files, the evidence doc, both JSON artifacts, all three `<threat_model>` mitigations (T-06-05-01 honest device-annotation, T-06-05-02 inherited bounds-safety, T-06-05-03 deterministic reproducible soak), and the RENDER-02/05 + SC#2/SC#4 truths are exactly as specified. The render-policy.sh CI gate stays green (exit 0). Context7 + the 06-RESEARCH main-thread Apple-DocC pass confirmed the `gpuStartTime`/`gpuEndTime` CFTimeInterval / `dispatchThreads` signatures before writing.

## Issues Encountered

- **Strict-concurrency MainActor isolation (resolved, Rule 3 #1).** The first build surfaced `CortexRender`'s `.defaultIsolation(MainActor.self)` requiring the bench's encode calls on the MainActor — resolved by `@MainActor` on the bench entry points + `MainActor.assumeIsolated` at the `type: tool` top level. No other issues; the bench built and ran on the second/third build, producing stable, reproducible numbers (p99 = 0.1615/0.1618 ms across two runs).
- **No fabrication risk materialized.** Every committed number was measured live on this M5 Pro and is reproducible from the committed bench; the honest corroborating-vs-canonical framing (D-11/D-12) is applied so the iPad-M4 canonical capture stays the deferred, never-auto-approved datapoint (the load-bearing credibility rule).

## Known Stubs

None. The Plan-04 `main.swift` stub (`print("bench: Plan 05 lands here")`) was fully replaced with the real measurement CLI. The `gpu_time_hist.json` + `soak_log.json` contain genuine measured values (not placeholders). The only deferred items are the on-panel `MTL_HUD` screenshot (mode b, run live on the ProMotion panel) and the iPad-Pro-M4 canonical capture (Plan 06 / `06-HUMAN-UAT.md`, D-12) — these are explicitly-labelled deferred optional/future datapoints, NOT stubs that prevent this plan's goal (which was the Mac-corroborating measurement, completed and committed).

## Threat Flags

None beyond the plan's `<threat_model>`. This plan adds a measurement bench + an evidence doc — no runtime, network, auth, or persistence surface, no new endpoints/schema/file-access at a trust boundary. The three registered threats are all mitigated as specified: **T-06-05-01** (misattributing the M5 Pro number as the canonical M4 number) by the device-annotation in the JSON + the evidence-doc header/labels + the what-this-is-NOT paragraph + deferring the canonical capture to Plan 06's never-auto-approve checkpoint; **T-06-05-02** (bench kernel out-of-bounds write) by reusing Plan 01's bounds-guarded kernel with `dispatchThreads` sized exactly to the offscreen extent (no new write scope); **T-06-05-03** (non-deterministic unreproducible soak) by the closed-form `LissajousProducer` drive (no RNG, only the 60s wall-clock duration is time-based) — confirmed reproducible by two bit-stable histogram runs.

## User Setup Required

None - no external service configuration required. The bench runs locally via `xcodebuild`/the `CortexRenderBench` scheme on the existing M5 Pro + Xcode 26.3 toolchain; the on-panel mode-b HUD run and the iPad-M4 capture are the documented (deferred) live runs, not setup.

## Next Phase Readiness

- **Ready for Plan 06-06 (iPad-M4 canonical capture + SC reframe sign-off):** the Mac-corroborating tier is complete — `06-render-evidence.md` + `gpu_time_hist.json` + `soak_log.json` are committed with genuine M5 Pro numbers and the honest corroborating-vs-canonical framing. Plan 06 carries the iPad-Pro-M4 ≤0.4 ms + 60 s 120 Hz canonical capture as a **never-auto-approved checkpoint** (`06-HUMAN-UAT.md`, D-12) and the ROADMAP SC#2/SC#4 + REQUIREMENTS RENDER-02/05 wording reframe ("measured on M5 Pro ProMotion; iPad-M4 capture optional/future") with user sign-off (D-11) — exactly the Phase-5 SC#1 disposition.
- **On-panel mode-b run available:** the `CortexMac` scheme runs live on the M5 Pro ProMotion panel with `MTL_HUD_ENABLED=1` (Plan 04) for the on-screen P95-frame-time / drawable-wait / encoder-time corroboration + HUD screenshot (the exact steps are in the evidence doc + `FrameSoak.onPanelRunSteps`).
- **Reusable for Phase 7:** the bench measures the kernel through the unchanged `WebgridFrameEncoder` + the deterministic-drive seam, so when the ReFIT-Kalman producer replaces `LissajousProducer` behind the fixed velocity seam, the same `CortexRenderBench` re-measures the identical compute pass with no harness change.

## Self-Check: PASSED

- All created files verified on disk: `Apps/CortexRenderBench/GPUTimeHistogram.swift`, `Apps/CortexRenderBench/FrameSoak.swift`, `.planning/.../06-render-evidence.md`, `.planning/.../gpu_time_hist.json`, `.planning/.../soak_log.json`; `main.swift` modified.
- Both task commits verified in `git log`: `b6eed6d` (Task 1), `5d1e119` (Task 2).
- Full plan `<verification>` re-run green: `xcodebuild build -scheme CortexRenderBench … CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED** (both bench files compiled); `gpuStartTime`/`gpuEndTime` over n=10 000 → p50/p95/p99 (RENDER-05); `FrameSoak` flags > 8.33 ms over 60 s driven by deterministic Lissajous (SC#4, D-05); `06-render-evidence.md` exists, device-annotated `M5 Pro` (D-11), iPad-M4 deferred (`06-HUMAN-UAT`/optional/future, D-12). **`render-policy.sh` exits 0** (the CI structural gate stays green).
- The committed numbers are genuinely measured on this M5 Pro (not fabricated/estimated): GPU p99 = 0.1618 ms (SC#2 PASS, 2.5× margin); 60 s soak 243 724 frames / 4062 Hz / 0 over-budget (SC#4 throughput PASS).
- STATE.md / ROADMAP.md / REQUIREMENTS.md NOT modified by this executor (orchestrator-owned).

---
*Phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid*
*Completed: 2026-06-22*
