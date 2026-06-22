# Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 06-CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-21
**Phase:** 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid
**Areas discussed:** Webgrid task scope, Cursor-velocity input contract, Webgrid + cursor visuals, On-device verification tiering

---

## Webgrid Task Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Visual substrate only | 30×30 grid + velocity-driven cursor; no targets/selection/scoring | ✓ |
| Substrate + visual target | Adds one highlighted target cell that advances on dwell (visual only) | |
| Full Webgrid task | Targets + dwell-selection + BPS scoring (Phase 8 scope) | |

| Option | Description | Selected |
|--------|-------------|----------|
| Full visual peer | macOS renders same webgrid via NSScreen.displayLink; daily interactive + HUD surface | ✓ |
| Minimal dev harness | macOS NSScreen.displayLink path for corroboration only | |
| iPad/iOS only | Defer macOS renderer (risks leaving RENDER-08 unverified) | |

**User's choice:** Visual substrate only; macOS full visual peer.
**Notes:** iPad Pro M4 ProMotion stays the canonical perf target. Target/dwell → Phase 7, BPS → Phase 8.

---

## Cursor-Velocity Input Contract

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated velocity seam | (vx,vy) fp16 frame in own SPSC ring (Phase 3 design); synthetic now, decoder+Kalman later; matches DEC-10 | ✓ |
| Reuse CortexFrame ring | Renderer reads raw 96-ch neural ring directly (wrong layer) | |
| In-process synthetic, no ring | Generate velocity in render layer; ring introduced Phase 7 | |

| Option | Description | Selected |
|--------|-------------|----------|
| Renderer owns integrator | velocity→position per tick, bounds-clamped; seam stays velocity-typed | ✓ |
| Upstream emits position | Producer emits absolute position; pushes integration into Phase 7 layer | |
| Seam carries both | Frame carries velocity AND position (heavier contract) | |

| Option | Description | Selected |
|--------|-------------|----------|
| Smooth parametric path | Deterministic Lissajous/sinusoid; reproducible 60s soak | ✓ |
| Bounded random walk | Velocity noise; organic but non-deterministic | |
| Center-out sweeps | Classic BCI center-out motion toward synthetic points | |

**User's choice:** Dedicated velocity seam; renderer owns integrator; smooth parametric drive.
**Notes:** Seam contract fixed at `{ts_ns, seq, vx, vy}` fp16; exact ring instantiation mechanism left to planning.

---

## Webgrid + Cursor Visuals

| Option | Description | Selected |
|--------|-------------|----------|
| Filled rounded cells | Classic Neuralink/BrainGate Webgrid look; cheap in compute shader | ✓ |
| Grid lines only | Thin lattice, empty cells; minimal | |
| Dot matrix | Dot at each cell center | |

| Option | Description | Selected |
|--------|-------------|----------|
| Dark (Neuralink-style) | Near-black bg, cool cells, bright cursor; maximizes photodiode contrast | ✓ |
| Light | White/light grid | |
| High-contrast mono | Pure black/white | |

| Option | Description | Selected |
|--------|-------------|----------|
| Bright filled disc, no trail | Clean luminance step for Phase 9 photodiode; cheap; GPU ≤0.4ms | ✓ |
| Ring / hollow circle | Outline only; less emitted luminance | |
| Disc + motion trail | Dynamic look; adds compute + smears photodiode edge | |

| Option | Description | Selected |
|--------|-------------|----------|
| Subtle proximity highlight | Cells brighten near cursor; pure visual, no logic | ✓ |
| No reaction | Cells stay uniform | |

**User's choice:** Filled rounded cells; dark Neuralink theme; bright filled-disc cursor (no trail); subtle proximity highlight.
**Notes:** Visual choices deliberately serve the Phase 9 photodiode SNR (high-luminance cursor pixel on dark bg).

---

## On-Device Verification Tiering

| Option | Description | Selected |
|--------|-------------|----------|
| Three tiers as described | CI-structural gates / Mac-corroborating / iPad-M4 canonical | ✓ |
| CI-structural + Mac only | Drop iPad-M4 tier | |
| Let me adjust the gate list | Change which checks are build-failing | |

| Option | Description | Selected |
|--------|-------------|----------|
| M5 Pro Mac ProMotion, reframe honestly | Measure ≤0.4ms GPU + 60s 120Hz on M5 Pro ProMotion; reframe SC#2/SC#4; iPad-M4 optional/future | ✓ |
| Block until iPad Pro M4 obtained | Stalls phase on rare hardware | |
| My Mac isn't 120Hz | (Would gate SC#4 entirely to a future ProMotion capture) | |

| Option | Description | Selected |
|--------|-------------|----------|
| HUMAN-UAT runbook, present not auto-approve | 06-HUMAN-UAT.md; phase completes on Mac-corroborating tier; iPad-M4 deferred | ✓ |
| Inline capture, no separate runbook | Fold capture into plan/verification docs | |

**User's choice:** Three tiers; M5 Pro Mac ProMotion corroborating-canonical + honest reframe; 06-HUMAN-UAT.md checkpoint, present-not-auto-approve.
**Notes:** iPad Air M2 is a 60Hz LCD — physically cannot show 120Hz; only useful for GPU-compute-time corroboration. Mirrors Phase 5 SC#1 disposition and the "device checkpoints never auto-approve" discipline.

## Implementer's Discretion

- Renderer threading layout of the display-link callback
- Square-grid → viewport aspect mapping (centered, letterboxed, square cells)
- Empty-ring behavior (cursor holds last position)
- CAMetalDisplayLink preferredFrameRateRange / preferredFrameLatency tuning
- Compute-shader → drawable path (write-to-drawable vs offscreen + blit)
- Velocity-ring depth + exact ring instantiation mechanism (Rust SPSC re-instantiation vs Swift-side ring)

## Deferred Ideas

- Webgrid target + dwell-selection mechanics → Phase 7 / Phase 8 (BPS)
- Real decoder / ReFIT-Kalman producer for the velocity seam → Phase 7
- iPad Pro M4 canonical on-device capture → optional/future (06-HUMAN-UAT.md records steps)
