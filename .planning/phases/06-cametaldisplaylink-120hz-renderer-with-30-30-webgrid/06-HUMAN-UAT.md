---
status: partial
phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid
source: [06-VALIDATION.md, 06-render-evidence.md]
started: 2026-06-22T18:34:26Z
updated: 2026-06-22T18:34:26Z
---

> ## ⚠️ CRITICAL — NEVER AUTO-APPROVE (D-12)
>
> **These measured numbers are load-bearing project credibility. PRESENT this checkpoint to the
> user; do NOT auto-approve it** — even when `auto_advance=true`. Auto-approving fabricates the
> project's defining ≤0.4ms-GPU / 120Hz-on-panel numbers (the MEMORY rule "Device checkpoints:
> never auto-approve / auto-approving fabricates load-bearing numbers").
>
> **The phase is COMPLETE on the Mac-corroborating tier (Plan 05, `06-render-evidence.md`):** the
> M5 Pro ProMotion is a genuine 120Hz Apple Silicon panel and honestly shows both ≤0.4ms GPU
> (p99=0.1618ms, n=10k, ~2.5× margin) and a 60s sustained-throughput soak (243,724 frames, 0
> intervals >8.33ms). **This runbook is the DEFERRED optional/future iPad-Pro-M4 *canonical*
> capture** (rare hardware) — recorded so it can be run when an iPad Pro M4 is in hand. None of the
> tests below are captured yet; none may be marked passed without a real iPad-Pro-M4 capture. Do
> NOT fabricate any iPad-M4 number. (This is the exact D-11/D-12 disposition mirroring the Phase-5
> SC#1/DEC-08 iPad-M4 capture, which remains optional/future.)

## Current Test

[awaiting iPad Pro M4 hardware]

The Mac-corroborating tier (M5 Pro ProMotion, `06-render-evidence.md`) completes the phase; the
three tests below are the iPad-Pro-M4 *canonical* capture, deferred optional/future. Each is the
on-device complement of an already-committed M5-Pro-corroborating number — captured the same way
(the unchanged `CortexRenderBench` GPU-time method + the on-panel `CortexiOS` scheme HUD), tied to
the same code so the runbook cannot drift.

## Tests

### 1. iPad Pro M4 canonical GPU compute time ≤0.4ms — RENDER-05 / SC#2 (p99 over n≥10k)
expected: On a **connected iPad Pro M4** (iPadOS 26), build + run the **`CortexiOS`** scheme driving
the **real 30×30 / 900-cell `webgrid` compute pass** (the unchanged `WebgridFrameEncoder`), then
capture the **GPU compute-time histogram** — `commandBuffer.gpuEndTime − gpuStartTime` over
**n ≥ 10,000** frames (the **same** `CortexRenderBench` method run on-device), **OR** an **Xcode GPU
frame capture** of the live `CortexiOS` render loop. Reviewer needs only **ONE** of the two.

  **Build + deploy the artifact (prerequisite for both options):**
  1. In **Xcode 26.3**, select the **connected iPad Pro M4** as the run destination (Window →
     Devices and Simulators → confirm paired + trusted). `MTL_HUD_ENABLED=1` is already set in the
     `CortexiOS` scheme (Plan 04, RENDER-09).
  2. The webgrid is driven by the deterministic, closed-form `LissajousProducer.velocity(at:t)`
     (D-05) — no RNG, no clock-derived workload — so the on-device GPU-time histogram is stable
     run-to-run (the same property that made the M5 Pro runs bit-identical: p99 = 0.1615ms then
     0.1618ms).

  **(a) On-device `CortexRenderBench` GPU-time histogram** (canonical artifact — mirrors `06-render-evidence.md`):
  1. Build the **`CortexRenderBench`** target for the iPad Pro M4 (embed in a thin host if the run
     destination requires it). It encodes the real `webgrid` pass into an offscreen
     `.bgra8Unorm`/`.shaderWrite` `MTLTexture` (the identical write scope the live drawable gets
     under `MetalLayerConfig.framebufferOnly = false`), `commit()` + `waitUntilCompleted()`, reads
     `gpuEndTime − gpuStartTime` per frame, discards **200 warmup** frames, reduces to nearest-rank
     percentiles over **10,000** samples at a representative full-surface drawable extent
     (≈2752×2064, the iPad-Pro-M4-13″-class extent already used on the M5 Pro).
  2. Read the printed **p50 / p95 / p99** line. Confirm **p99 ≤ 0.4 ms** (the SC#2 bound).
  3. Commit the on-device **`gpu_time_hist_ipad.json`** (the iPad complement of the Mac
     `gpu_time_hist.json`), annotated **on-device / iPad Pro M4 / iPadOS 26**, into this phase dir.

  **(b) Xcode GPU frame capture** of the live `CortexiOS` render loop:
  1. Run the **`CortexiOS`** scheme on the iPad Pro M4; once the webgrid is animating, trigger a
     **GPU frame capture** (Debug → Capture GPU Frame).
  2. Open the compute pass for the `webgrid` kernel and read its **GPU duration**; confirm it is
     **≤ 0.4 ms**.
  3. **Save the `.gputrace`** (or screenshot the timeline) and commit it into this phase dir
     (e.g. `webgrid-ipad-m4.gputrace` / `gpu-capture-ipad.png`).

  **Pass condition:** p99 (or the captured per-frame compute) **≤ 0.4 ms** on iPad Pro M4, over the
  real 900-cell `webgrid` pass.
  **Artifacts to commit:** `gpu_time_hist_ipad.json` (option a) **OR** the `.gputrace`/screenshot
  (option b) into this phase dir.

  **Honest framing (D-11/D-12):** the **M5-Pro-corroborating** number is the always-available proxy
  that **COMPLETES the phase** — `06-render-evidence.md` (p99 = 0.1618ms, n=10k, ~2.5× margin) is a
  genuine measurement on a real 120Hz ProMotion Apple-Silicon device, attributed to the M5 Pro and
  **never** substituted for the M4 number. The cortex-spec "~0.3–0.6ms GPU on A17 Pro → M4 ≤0.4ms"
  expectation is consistent with 0.16ms on the faster M5 Pro, but the M4 number stays the deferred
  datapoint to be captured here. **If the iPad-M4 capture is ever taken, record it as observed — do
  not assume it from the M5 Pro run.**
result: [pending — optional/future, iPad Pro M4 not in hand]
why_human: The on-device `CortexRenderBench` run and the Xcode **GPU frame capture** are GUI
profilers on a live process and require **real iPad Pro M4 hardware** — they cannot run in CI (no
GUI, no Metal GPU, no paired device on the `macos` runner). This is a **load-bearing canonical
credibility number**, so it is a `checkpoint:human-verify` and **never auto-approved** (D-12). The
always-on CI proxy is the Plan-04 structural tier (`render-policy.sh` + the 120Hz-plist build-time
gate — the invariants a headless runner CAN assert); the M5-Pro-corroborating live number
(`06-render-evidence.md`) is the always-available measurement that completes the phase. This follows
the same **D-18** "measure on the available device, gate the canonical claim on the target device"
precedent as Phase-2 SC#1, Phase-3 SC#1 (`03-HUMAN-UAT.md`), and Phase-5 SC#1/SC#4 (`05-HUMAN-UAT.md`).

### 2. iPad Pro M4 sustained 120Hz, no dropped frames over 60s — RENDER-02 / SC#4 (on-panel refresh)
expected: On the **same connected iPad Pro M4 ProMotion panel**, run the **`CortexiOS`** scheme so
the `CAMetalDisplayLink` adapter (Plan 03) drives the webgrid at `preferredFrameRateRange(120,120,120)`
with the `value:1` `FrameSynchronizer` holding one frame in flight. Over a **60-second** sustained
run, **count display-link callbacks** and confirm **zero intervals > 8.33 ms** (the 120Hz budget =
1000/120).

  1. Launch the `CortexiOS` scheme on the iPad Pro M4 built-in ProMotion display; the deterministic
     `LissajousProducer` (D-05) drives the cursor.
  2. With **`MTL_HUD_ENABLED=1`** (set in the `CortexiOS` scheme, RENDER-09) confirm the HUD's
     **P95 frame time ≈ 8.33 ms** and **zero long frames** over the 60s window.
  3. (optional, stronger artifact) enable a display-link callback counter in the iOS adapter to
     count ticks over 60s and log any interval > 8.33 ms; commit the on-device
     **`soak_log_ipad.json`** (the iPad complement of the Mac `soak_log.json`).

  **Pass condition:** sustained 120Hz for 60s on the iPad Pro M4 panel — **zero intervals > 8.33 ms**.
  **Artifact to commit:** the HUD screenshot (Test 3) and/or `soak_log_ipad.json` into this phase dir.
result: [pending — optional/future, iPad Pro M4 not in hand]
why_human: This needs a **real iPad-Pro-M4 120Hz ProMotion panel** — it is the on-display *refresh*
proof, which a headless CI runner cannot produce. **iPad Air M2 is physically incapable** of this
claim (60Hz LCD panel — it can corroborate GPU-compute time but **cannot** show 120Hz refresh), so
unlike the Phase-5 capture this SC#4 test has **no M2 fallback** — the Mac ProMotion panel
(`06-render-evidence.md`, mode b) is the corroborating refresh surface and the iPad-Pro-M4 panel is
the canonical one. Never auto-approve (D-12). The offscreen-throughput soak (mode a) on the M5 Pro —
243,724 frames, 0 intervals > 8.33 ms — proves GPU-workload headroom and completes the phase; this
test is the deferred on-panel canonical refresh capture.

### 3. MTL_HUD_ENABLED=1 HUD visible on-device — RENDER-09 (P95 frame time, drawable-wait, encoder-time)
expected: Launch the **`CortexiOS`** scheme on the iPad Pro M4 and confirm Apple's **Metal
Performance HUD** overlay is visible, reporting per frame: **P95 frame time** (≈ 8.33 ms at locked
120Hz), **drawable-wait** (near-zero confirms the `value:1` + `maximumDrawableCount = 2` low-latency
config is not starving), and **encoder-time** (corroborates the ≤0.4ms compute number from Test 1).

  1. With `MTL_HUD_ENABLED=1` already set in the `CortexiOS` scheme (Plan 04), run on the iPad Pro M4.
  2. Confirm the HUD overlay renders on-screen with the three metrics above live.
  3. **Screenshot the HUD overlay** and commit it into this phase dir (e.g.
     `mtl-hud-ipad-m4.png`) — the on-panel artifact for SC#4 (Test 2) + RENDER-09.

  **Pass condition:** HUD overlay visible on-device with P95 frame time / drawable-wait /
  encoder-time legible; P95 ≈ 8.33 ms at locked 120Hz.
  **Artifact to commit:** `mtl-hud-ipad-m4.png` into this phase dir.
result: [pending — optional/future, iPad Pro M4 not in hand]
why_human: An on-screen overlay on the live device — there is nothing for CI to capture (no display,
no GPU, no on-device launch on a headless runner). The HUD env (`MTL_HUD_ENABLED=1`) is already
asserted present in both app schemes by the Plan-04 structural gate; this test is the human
*visual* confirmation that it renders on the iPad-Pro-M4 panel. Never auto-approve (D-12).

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

**Status (2026-06-22):** All three iPad-Pro-M4 canonical-capture tests are **pending — optional/future**
(rare hardware, iPad Pro M4 not in hand). The phase **COMPLETES on the Mac-corroborating tier**
(Plan 05, `06-render-evidence.md`): M5 Pro ProMotion, GPU compute p99 = 0.1618ms (n=10k, ≤0.4ms SC#2
PASS, ~2.5× margin) + 60s offscreen-throughput soak 243,724 frames / 0 intervals > 8.33ms. RENDER-02/
RENDER-05 are reframed to "measured on M5 Pro ProMotion (corroborating-canonical, D-11); iPad Pro M4
canonical capture optional/future" (the sign-off-gated D-11 reframe, mirroring the Phase-5 SC#1/DEC-08
disposition). This runbook records the exact iPad-Pro-M4 steps for when the device is in hand; the
capture is **presented as a checkpoint and never auto-approved** (D-12).

## Gaps

- The iPad-Pro-M4 *canonical* ≤0.4ms-GPU + 60s-on-panel-120Hz + on-device-HUD captures are deferred
  optional/future (rare hardware). The phase does **not** block on them — it completes on the
  Mac-corroborating tier (`06-render-evidence.md`).
- SC#4's on-panel 120Hz *refresh* proof has **no iPad Air M2 fallback** (60Hz LCD is physically
  incapable); the only corroborating refresh surface is the M5 Pro built-in ProMotion panel
  (`06-render-evidence.md`, mode b), and the iPad-Pro-M4 panel is the deferred canonical surface.
- When an iPad Pro M4 is obtained, run all three tests via the steps above, commit the artifacts
  (`gpu_time_hist_ipad.json` / `.gputrace`, `soak_log_ipad.json`, `mtl-hud-ipad-m4.png`) into this
  phase dir, and present the checkpoint to the user for sign-off — **never auto-approve.**
