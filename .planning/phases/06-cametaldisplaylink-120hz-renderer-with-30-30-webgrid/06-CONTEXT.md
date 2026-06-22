# Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid - Context

**Gathered:** 2026-06-21
**Status:** Ready for planning

<domain>
## Phase Boundary

A beam-raced 120Hz Metal renderer presents a 30×30 webgrid (~900 cells) driven by a
cursor-velocity stream, on iPad Pro M4 ProMotion at ≤0.4ms GPU compute. `CAMetalDisplayLink`
on iOS, `NSScreen.displayLink` on macOS (not a Catalyst bridge); the grid is drawn via a
Metal **compute** shader; drawables use `MTLBuffer storageModeShared` (zero-copy unified
memory); one in-flight frame is gated by `dispatch_semaphore_t(value: 1)` per Apple's
"Synchronizing CPU and GPU Work" pattern.

**This phase is the visual substrate + frame pacing + synthetic drive.** It deliberately
precedes the closed loop: Phase 7 (ReFIT-Kalman) wires in the real decoder output and Phase 8
adds Webgrid BPS scoring + HID. Phase 6 ships the grid, the cursor, the 120Hz pacing, and a
synthetic velocity source — nothing that scores or selects.

Covers RENDER-01 … RENDER-09. Parallelizable with Phases 4-5; depends only on Phase 1
(toolchain) and the Phase 3 ring design (input seam).

</domain>

<decisions>
## Implementation Decisions

### Webgrid Task Scope
- **D-01:** **Visual substrate only.** Render the 30×30 grid + a velocity-driven cursor. No
  targets, no dwell/selection, no scoring in this phase. Target/dwell logic → Phase 7
  (decoder closed loop); BPS scoring (Soukoreff-MacKenzie ISO 9241-9) → Phase 8 (PERF-01/03).
- **D-02:** **macOS is a full visual peer**, rendering the same webgrid via
  `NSScreen.displayLink` (macOS 14+). It is the engineer's daily interactive + `MTL_HUD`
  surface and the only Apple Silicon GPU drivable live during dev. **iPad Pro M4 ProMotion
  remains the canonical performance target** for the spec's ≤0.4ms / 120Hz claims.

### Cursor-Velocity Input Contract
- **D-03:** **Dedicated `(vx, vy)` fp16 velocity seam** is the renderer's input — a small
  frame (`{ ts_ns, seq, vx, vy }`, fp16 velocity) carried over an SPSC ring reusing the
  Phase 3 loom-verified ring design. A **synthetic producer** fills it in Phase 6; the Phase 5
  decoder + Phase 7 Kalman become the producer later. Matches **DEC-10** (2-vector cursor
  velocity at fp16, emitted every 20ms). Do **not** reuse the raw 96-channel `CortexFrame`
  ring as the renderer input — that couples the renderer to neural data it cannot decode.
- **D-04:** **Renderer owns the velocity→position integrator.** The seam stays velocity-typed;
  the renderer integrates velocity→position each tick and clamps to grid bounds. Position is a
  presentation concern, and Phase 7's Kalman also emits velocity, so the seam is unchanged when
  the real decoder lands.
- **D-05:** **Smooth parametric synthetic drive** (Lissajous/sinusoid) powers the cursor for
  the 60s sustained soak (SC#4) and the demo — deterministic and reproducible, so frame-pacing
  measurements are stable and the no-dropped-frames soak is repeatable.

### Webgrid + Cursor Visuals
- **D-06:** **Filled rounded cells** with small gaps — the classic Neuralink/BrainGate Webgrid
  look; reads clearly at 900 cells and is cheap in a compute shader.
- **D-07:** **Dark (Neuralink-style) theme** — near-black background, cool-toned cells, bright
  cursor. Chosen partly to **serve the Phase 9 photodiode**: a high-luminance cursor on a dark
  background gives the cleanest rising edge when the BPW34 is aimed at the cursor pixel.
- **D-08:** **Bright filled-disc cursor, no motion trail** — biggest clean luminance step for
  the photodiode, cheapest to draw, keeps GPU ≤0.4ms. No trail (it would smear the photodiode
  edge and add compute).
- **D-09:** **Subtle cursor-proximity cell highlight** — cells brighten slightly near the
  cursor. Pure visual effect (no selection/scoring logic), keeps the 30×30 grid alive during
  the synthetic soak and previews Phase 7/8 target interaction.

### On-Device Verification Tiering
- **D-10:** **Three verification tiers** (mirrors Phase 3 `.trace` / Phase 5 ANE):
  1. **CI-structural, build-failing gates on `macos-15`:** no `CADisplayLink`-for-Metal in the
     source tree; `storageModeShared` present on drawable buffers; `dispatch_semaphore_t(value: 1)`
     present; `CADisableMinimumFrameDurationOnPhone = YES` in `Info.plist` (build-time check);
     compute-shader grid path present; `NSScreen.displayLink` on the macOS target;
     `MTL_HUD_ENABLED=1` in the scheme env. Follows the Phase 1 / Phase 3 grep-gate precedent.
  2. **Mac-corroborating live numbers** on the M5 Pro MacBook Pro ProMotion panel — `MTL_HUD`
     P95 frame time, drawable-wait, encoder-time + webgrid GPU compute time + a 60s sustained
     120Hz soak.
  3. **iPad-M4 canonical capture** — the spec's canonical ≤0.4ms GPU + 60s 120Hz numbers.
- **D-11:** **M5 Pro MacBook Pro ProMotion is the corroborating-canonical surface** for SC#2
  (≤0.4ms GPU) and SC#4 (60s sustained 120Hz) this phase — it is a genuine 120Hz Apple Silicon
  ProMotion device, so it can show both honestly. **Reframe SC#2/SC#4** to "measured on M5 Pro
  ProMotion; iPad Pro M4 capture optional/future" — exactly the Phase 5 SC#1 disposition.
  **iPad Air M2 cannot serve SC#4** (60Hz LCD panel — physically cannot show 120Hz); it is
  useful only for GPU-compute-time corroboration. Apply the reframe to ROADMAP SC#2/SC#4 +
  REQUIREMENTS RENDER-02/05 wording at plan/execute time (with user sign-off), as Phase 5 did.
- **D-12:** **`06-HUMAN-UAT.md` runbook** captures the exact on-device capture steps (like
  `03-HUMAN-UAT.md` / `05-HUMAN-UAT.md`). It is **presented as a checkpoint, never
  auto-approved** — these measured numbers are load-bearing project credibility. The phase
  **completes on the Mac-corroborating tier**, with the iPad-Pro-M4 capture deferred as
  optional/future.

### Implementer's Discretion
Sensible defaults; no user decision needed — planner/executor choose within the constraints above:
- Renderer threading layout of the display-link callback (per Apple "Synchronizing CPU and GPU
  Work" + Phase 3 audio-callback discipline — the lock-free ring `pop` is callback-safe).
- Square-grid → viewport aspect mapping (preserve square cells, centered, letterbox the
  non-square remainder).
- Empty-ring behavior (cursor holds last position; integrator sees zero/last velocity).
- `CAMetalDisplayLink` `preferredFrameRateRange` / `preferredFrameLatency` tuning.
- Compute-shader → drawable path (write directly to the drawable texture vs. offscreen + blit).
- Velocity-ring depth and the exact ring instantiation mechanism (a second Rust SPSC
  instantiation with a `#[repr(C)] CursorVelocity` + cbindgen, vs. a Swift-side SPSC for the
  in-process Phase 6 producer). The seam contract (D-03) is fixed; the mechanism is open.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Renderer spec (primary)
- `docs/cortex-spec.md` §3 "Renderer (Finding 3, 91 sources)" (lines ~60-67) and "Finding 3:
  CAMetalDisplayLink / 120 Hz renderer" (lines ~271-282) — the load-bearing source-of-truth:
  `CAMetalDisplayLink` API surface (`CAMetalDisplayLinkDelegate`, `init(metalLayer:)`,
  `preferredFrameRateRange`, `preferredFrameLatency`, `targetTimestamp`); 120Hz/ProMotion;
  30×30 compute-shader webgrid (~0.3-0.6ms GPU on A17 Pro → M4 ≤0.4ms expectation);
  `storageModeShared`; `dispatch_semaphore_t(value: 1)`; macOS `NSScreen.displayLink` (not
  `CVDisplayLink`, not Catalyst bridge); `MTL_HUD_ENABLED=1`; `CADisableMinimumFrameDurationOnPhone`.

### Requirements + roadmap
- `.planning/REQUIREMENTS.md` — RENDER-01 … RENDER-09 (the nine phase requirements), PERF-04
  (P99 decoder+render+present under 25ms), and the Out-of-Scope entries that pin the rejected
  alternatives (`CADisplayLink` for Metal, 6×6 webgrid, macOS Catalyst single binary).
- `.planning/ROADMAP.md` Phase 6 (lines ~118-128) — Goal + 4 Success Criteria + the
  parallelizable-with-Phases-4-5 note.
- `.planning/PROJECT.md` Key Decisions table — `CAMetalDisplayLink`-not-`CADisplayLink`,
  30×30-not-6×6, and the Phase 1 cross-phase note that `SUPPORTS_MACCATALYST: NO` +
  `NSApplicationDelegateAdaptor` already makes the RENDER-08 `NSScreen.displayLink` path defensible.

### Input-seam + device-gating precedents
- `Packages/CortexRing/rust/include/cortex_ring.h` — the `#[repr(C)] CortexFrame` ABI +
  `cortex_spsc_push`/`cortex_spsc_pop`; the design template to mirror for the `(vx,vy)`
  velocity seam (D-03).
- `Packages/CortexRing/Sources/CortexRing/Ring.swift` — the Swift `CortexRing` `push`/`pop`
  RAII wrapper pattern.
- `.planning/phases/05-ndt1-coreml-deployment/05-HUMAN-UAT.md` and `05-placement-evidence.md`
  — the honest-reframe precedent (measure on available hardware, reframe the claim, leave the
  canonical-device capture optional/future) for D-11.
- `.planning/phases/03-real-time-threading*/03-HUMAN-UAT.md` — the device-gated capture runbook
  precedent for D-12.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Packages/CortexRender/` — currently an empty stub (`CortexRender.swift` marker enum +
  `README.md`). The renderer lands here. Already wired in `project.yml` as a dependency of
  both `CortexiOS` and `CortexMac`.
- Phase 3 SPSC ring (`Packages/CortexRing/`) — the `(vx,vy)` velocity seam (D-03) reuses this
  loom-verified ring design; `CortexFrame {ts_ns, seq, channel_data[96]}` shows the
  `#[repr(C)]` + cbindgen pattern to mirror for a `CursorVelocity {ts_ns, seq, vx, vy}` payload.

### Established Patterns
- `project.yml` (XcodeGen) is the single source of truth for Xcode topology — the renderer
  target wiring, `Info.plist` key, and scheme env (`MTL_HUD_ENABLED=1`) all change in
  `project.yml`, never in a generated `.pbxproj`. There is already a placeholder comment in
  `project.yml`: *"CADisableMinimumFrameDurationOnPhone arrives in Phase 6 with the renderer."*
- `SUPPORTS_MACCATALYST: NO` + `NSApplicationDelegateAdaptor` are already set (Phase 1) — the
  RENDER-08 `NSScreen.displayLink` path is unobstructed.
- CI grep-gate precedent: Phase 1 (no-sandbox / no-CocoaPods / PrivacyInfo-in-bundle) and
  Phase 3 (`Tools/scripts/hotpath-policy.sh` with a negative-control self-test). The renderer's
  structural gates (D-10 tier 1) follow this exact shape.

### Integration Points
- `Apps/CortexiOS/{App.swift,ContentView.swift,Info.plist}` and
  `Apps/CortexMac/{App.swift,ContentView.swift,Info.plist}` host the render surface;
  `CADisableMinimumFrameDurationOnPhone = YES` goes in `Apps/CortexiOS/Info.plist`.
- The synthetic velocity producer is **in-process** in Phase 6 (no cross-process daemon hop,
  unlike the Phase 2 neural ring) — the producer and renderer both live in the app process.

</code_context>

<specifics>
## Specific Ideas

- Dev Mac is an **M5 Pro MacBook Pro** with a built-in 120Hz ProMotion display — the
  corroborating-canonical measurement surface for SC#2/SC#4 (D-11).
- The dark-bg + bright-disc cursor choice is intentionally photodiode-friendly (Phase 9): the
  cursor is the high-luminance pixel the BPW34 will be aimed at.
- Visual reference is the **modern Neuralink / Bliss Chapman Webgrid** (30×30 filled cells),
  explicitly *not* the legacy Pandarinath 2017 6×6.

</specifics>

<deferred>
## Deferred Ideas

- **Webgrid target + dwell-selection mechanics** → Phase 7 (decoder closed loop) for the
  interaction, Phase 8 (PERF-01/03) for BPS scoring under Soukoreff-MacKenzie ISO 9241-9.
- **Real decoder / ReFIT-Kalman producer** for the velocity seam → Phase 7 (the synthetic
  producer is swapped out behind the fixed D-03 seam).
- **iPad Pro M4 canonical on-device capture** (≤0.4ms GPU + 60s sustained 120Hz on M4
  ProMotion) → optional/future, rare hardware; the `06-HUMAN-UAT.md` runbook records the exact
  steps so it can be run when an iPad Pro M4 is in hand.

</deferred>

---

*Phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid*
*Context gathered: 2026-06-21*
