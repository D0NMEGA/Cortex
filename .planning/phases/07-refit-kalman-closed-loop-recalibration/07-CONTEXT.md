# Phase 7: ReFIT-Kalman Closed-Loop Recalibration - Context

**Gathered:** 2026-06-22
**Status:** Ready for planning

<domain>
## Phase Boundary

A **6-DOF Kalman filter on the Swift side, post-CoreML** wraps the NDT1 decoder's 2-vector
`(vx, vy)` cursor-velocity output and emits a *refined* velocity every 20 ms tick, applying a
**Gilja-2012 intent-rotation step every cursor update** (REFIT-01, REFIT-02). A **headless,
deterministic closed-loop Webgrid BPS harness** then measures cursor-control throughput under the
**Soukoreff & MacKenzie 2004 ISO 9241-9 Fitts** methodology and commits the **documented uplift over
raw NDT1** on synthetic Indy replay as a regression artifact (REFIT-03, PERF-03). The filter + rotation
must add **zero detectable contribution to glass-to-glass tail latency** — it runs on the *existing*
decoder pthread, inside the 20 ms budget, never a new thread (SC#3).

**In scope:** the Kalman filter stage, the intent-rotation step, the headless BPS measurement harness,
the committed uplift artifact + CI guard.

**Out of scope (Phase 8, v0 ship):** the live on-device 120 Hz closed-loop demo
(synthetic-spike → decoder → ReFIT → 30×30 webgrid hit — SYS-06); the *formal* "match BrainGate 4.16 BPS
/ document gap to Neuralink 8.5" leaderboard claim (PERF-01/02 — ROADMAP Phase 8 SC#5); Apple BCI HID
integration; distribution.

</domain>

<decisions>
## Implementation Decisions

### Kalman core & substrate (REFIT-01)
- **D-01:** State vector is **6-DOF constant-acceleration kinematic `[px, py, vx, vy, ax, ay]`**.
  Position is in the state because the intent-rotation step (D-04..D-06) needs the cursor's position
  relative to the target. The **output to the seam stays a 2-vector velocity** (`CursorVelocity`) — the
  position state is internal to the filter's dynamics, not double-integrated (the renderer's
  `CursorIntegrator` still owns velocity→screen-position). Measurement = the decoded `(vx, vy)`.
- **D-02:** **Steady-state constant-gain Kalman.** The converged gain `K` is precomputed offline (the
  time-invariant linear-Gaussian model reaches a steady-state covariance), so the per-tick hot-path op is
  just a few fixed `simd` mat-vec products: `x = A·x + K·(z − H·A·x)`. Zero allocation, fully
  deterministic, trivially within the 20 ms budget. No per-tick covariance propagation.
- **D-03:** **Swift + `simd`** — fixed-size `simd` matrices/vectors (hand-assembled 6×6 / 2×6),
  Foundation-free, no heap. Honors REFIT-01 "Swift side" + spec §2.4 "pure linear algebra," and passes
  `Tools/scripts/hotpath-policy.sh`. (Not Accelerate — BLAS setup outweighs inlined `simd` at this tiny
  fixed dim. Not Rust — the seam *could* host a `cbindgen` producer, but spec/REFIT-01 say Swift; recorded
  as a deferred option.)

### Intent-rotation semantics (REFIT-02)
- **D-04:** **Online per-tick rotation** — the rotation is applied at inference, every 20 ms update, with
  **no offline retrain**. This is the literal SC#1 reading ("intent-rotation step executed every cursor
  update"). Recorded honestly as a **ReFIT-*inspired* online assist**, not Gilja's full two-stage
  retraining procedure (which is explicitly NOT what this phase implements — see Deferred).
- **D-05:** The rotation acts on the **measurement** — the decoded velocity `z` is rotated toward the
  active target *before* the Kalman measurement update, so the filter fuses a target-consistent
  observation. This is the actual ReFIT assumption ("the user intends the target"), not a cosmetic
  post-hoc nudge of the output.
- **D-06:** **Full direction-align, speed preserved, gated.** The rotation aligns the velocity direction
  fully onto the cursor→target vector while preserving the decoded *speed* (magnitude). It applies **only
  when a target is active AND the cursor is outside the acquisition radius** — so it does not "snap" once
  on-target. Canonical Gilja behavior with sane gating.

### BPS measurement harness (REFIT-03 / SC#2 / PERF-03)
- **D-07:** **Headless deterministic closed-loop simulation** — a pure-Swift bench/test executable
  (mirroring `CortexDecoderBench`): replay → `[raw | Kalman-only | Kalman+rotation]` → `CursorIntegrator`
  → 30×30 webgrid acquisition → Fitts throughput. **No Metal, no display link.** Reuses the existing
  `CursorIntegrator` + `WebgridParams` geometry. CI-stable, fast, reproducible. (The live 120 Hz
  renderer-in-the-loop demo is Phase 8 SYS-06.)
- **D-08:** **Dwell-to-select + per-trial timeout** — a target is acquired when the cursor stays within
  the target cell for a fixed dwell window; a per-trial timeout caps unreachable targets. Classic
  BrainGate/Webgrid convention, deterministic. (Exact dwell ms, acquisition radius, and timeout are
  implementer's discretion — sensible defaults, documented in the artifact.)
- **D-09:** **Full Soukoreff & MacKenzie 2004 throughput with effective-width correction** —
  `TP = IDe / MT`, `IDe = log2(De/We + 1)`, `We = 4.133 · SD` of the endpoint scatter, mean-of-means
  aggregation across conditions. The effective-width adjustment (not nominal width) is what makes the
  number defensible to a Neuralink-grade reviewer.
- **D-10:** **Committed artifact + deterministic CI guard.** Commit `07-bps-evidence.md` + a
  machine-readable JSON (raw vs ReFIT BPS, delta, n trials, seed, methodology notes). Add a short-budget
  CI smoke asserting **`ReFIT_BPS ≥ raw_BPS` on the fixed seed** — mirrors the Phase-4 co-bps>null gate;
  deterministic so non-flaky, traps filter regressions structurally.

### Synthetic intent source (REFIT-03 / PERF-01) — the credibility crux
- **D-11:** **Use the Indy dataset's own reach targets** as the acquisition targets; replay the held-out
  neural data through the decoder. The 30×30 webgrid is the *display* geometry; BPS is measured on the
  real reach task the data came from. **No fabricated neural signal** — the most honest reading of
  REFIT-03 ("improves BPS over raw NDT1 output on synthetic Indy replay") and aligned with the project's
  instrument-it-honestly ethos. (A synthetic intent→spikes forward model was rejected: it would make the
  BPS partly a measurement of the forward model, not the decoder — see Deferred.)
- **D-12:** **3-way ablation** — the artifact reports **raw NDT1 / Kalman-only / Kalman+rotation** on the
  *identical* seed-locked replay and target sequence (the three paths differ only in the filter stage).
  Isolates how much uplift is the rotation vs the Kalman smoothing. Cheap given determinism;
  reviewer-grade transparency.
- **D-13:** **Absolute BPS + relative uplift now; defer the formal leaderboard claim.** The Phase-7
  artifact lists raw/ReFIT *absolute* BPS and the delta, with a one-line note that the formal "match
  BrainGate 4.16 BPS / document gap to Neuralink 8.5 BPS" claim (PERF-01/02) is **Phase 8 SC#5**. Captures
  the numbers without overclaiming on synthetic replay.

### Structure & provenance
- **D-14:** The filter lives in a **new `CortexReFIT` Swift package** — consistent with the project's
  per-subsystem split (CortexCore / CortexIPC / CortexRender / CortexDecoder). High cohesion; owns its own
  `hotpath-policy.sh` gate coverage. It bridges the decoder's `SIMD2<Float>` to the renderer's
  `CursorVelocity` seam. **Planner note:** the shared seam types (`CursorVelocity`, possibly `VelocityRing`)
  currently live in `CortexRender`; the planner decides whether to keep a `CortexRender` dependency or
  hoist those types to `CortexCore` so neither Decoder nor ReFIT depends on the renderer.
- **D-15:** **Steady-state gain + process/measurement noise (Q, R) are fit offline in the `Decoder/` uv
  subsystem and emitted as committed Swift constants.** Fit Q/R from held-out Indy residual statistics,
  solve the discrete-algebraic-Riccati equation for the steady-state gain, emit the 6×6 / 2×6 matrices as
  committed Swift constants. Data-grounded, reproducible, and the Swift hot path loads constants only.
  Couples to the `Decoder/` uv subsystem (`uv sync --project Decoder --extra dev` required for its tooling).

### Implementer's Discretion
- Exact dwell-time, acquisition-radius, and per-trial-timeout values for the webgrid task (sensible
  defaults, recorded in the artifact).
- The precise `simd` matrix/vector layout and inlining of the predict+update step.
- Trial count `n` for the BPS run, plus a short-budget CI-smoke variant of the same harness.
- Where the steady-state-gain Riccati solve runs in `Decoder/` (script vs test) and the emitted-constants
  file format.
- How the filter's internal position state is synchronized to the actual (clamped) cursor position each
  tick for the rotation's cursor→target vector (fed back from the integrator / known in the headless sim).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Spec & requirements (authoritative for this phase)
- `docs/cortex-spec.md` §2.4 — ReFIT-Kalman: 6-DOF state, intent-rotation per update, "pure linear
  algebra, runs on the Swift side post-CoreML," Gilja 2012 provenance (4.16 → 8.5 BPS in humans).
- `docs/cortex-spec.md` §2.3 — decoder I/O: output is a **2-vector `(vx, vy)`, fp16, predicted every 20 ms**
  (the Kalman's input contract).
- `docs/cortex-spec.md` §2.5 + §8 — reference targets / BPS leaderboard (BrainGate 4.16, Neuralink P1 8.5,
  30×30 webgrid) and the Soukoreff & MacKenzie 2004 ISO 9241-9 Fitts citation.
- `.planning/REQUIREMENTS.md` — **REFIT-01/02/03** (the phase requirements); **PERF-01/02/03** and
  **SYS-06** establish the Phase-8 boundary (formal leaderboard + live demo).
- `.planning/ROADMAP.md` §"Phase 7" — Goal + Success Criteria SC#1 (filter+rotation every 20 ms),
  SC#2 (S&M 2004 BPS uplift artifact), SC#3 (zero tail-latency contribution, existing pthread).
  §"Phase 8" — confirms SYS-06 live demo + PERF leaderboard claim are NOT this phase.

### Existing integration seam (the Kalman is a drop-in producer — do not re-architect)
- `Packages/CortexRender/Sources/CortexRender/CursorVelocity.swift` — the velocity-typed seam
  (`ts_ns, seq, fp16 vx, fp16 vy`); FFI-mirrored `#[repr(C)]` discipline; comments explicitly anticipate
  "Phase 7 ReFIT-Kalman becomes the producer."
- `Packages/CortexRender/Sources/CortexRender/CursorIntegrator.swift` — the **single** non-finite-reject +
  `[0,1]` clamp validation point (Phase 6 D-04). The Kalman output flows through here unchanged.
- `Packages/CortexRender/Sources/CortexRender/VelocityRing.swift` — the SPSC velocity ring
  (`push`/`pop` of `CursorVelocity`) the filter writes into.
- `Packages/CortexRender/Sources/CortexRender/LissajousProducer.swift` — the current deterministic
  synthetic drive (Phase 6 D-05). The Phase-7 real path (decoder→Kalman) replaces it as the producer; its
  determinism contract is the model for the BPS harness.
- `Packages/CortexRender/Sources/CortexRender/WebgridParams.swift` — 30×30 grid geometry (cell size,
  cursor coords) the headless BPS harness reuses for target/cell mapping.
- `Packages/CortexDecoder/Sources/CortexDecoder/NeuralDecoder.swift` — `decode(_:) -> SIMD2<Float>`
  (the Kalman's input); `CortexDecoder.velocityDimension == 2`
  (`Packages/CortexDecoder/Sources/CortexDecoder/CortexDecoder.swift`).
- `Packages/CortexDecoder/Sources/CortexDecoderBench/main.swift` — the in-process bench-executable pattern
  the headless BPS harness mirrors.
- `Packages/CortexDecoder/Sources/CortexDecoder/LatencyHistogram.swift` — histogram pattern for the SC#3
  tail-latency measurement of the filter step.

### Hot-path & CI discipline (locked from prior phases)
- `Tools/scripts/hotpath-policy.sh` — the static-analysis gate (no `dispatch_async`/`lazy var`/locks/
  `Foundation` on the hot path). The `CortexReFIT` package MUST be covered by it (SC#3 runs on the
  existing pthread).
- `Tools/scripts/render-policy.sh` — the renderer-side gate (for any harness touching render code).
- `Decoder/src/ndt1/velocity_head.py` — the linear ridge readout; comments note "ReFIT-Kalman is
  REFIT-01 / Phase 7 (Swift, post-CoreML)." This subsystem is where Q/R fitting + the Riccati solve land
  (D-15).

### Evidence-artifact precedent (format to mirror for `07-bps-evidence.md`)
- `.planning/phases/04-ndt1-training-on-indy-loco-synthetic-replay/04-training-evidence.md` — held-out
  co-bps evidence + the "beats null by margin" CI-gate pattern (D-10 mirrors it).
- `.planning/phases/02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm/sc1-evidence.md` — device-annotated
  latency-evidence format.

### External references (no local file — cite in artifact)
- **Gilja et al. 2012**, "A high-performance neural prosthesis enabled by control algorithm design,"
  *Nature Neuroscience* — the ReFIT-KF + intent-rotation source.
- **Soukoreff & MacKenzie 2004**, "Towards a standard for pointing device evaluation," ISO 9241-9 Fitts
  throughput (effective-width method) — the BPS methodology source.
- **Ye & Pandarinath 2021** — NDT1 architecture (the decoder this filter wraps).
- **Pandarinath 2017** (BrainGate Webgrid 6×6, 4.16 BPS) and **Neuralink PRIME** (Noland Arbaugh, 8.5 BPS
  verified) — the leaderboard references (formal comparison deferred to Phase 8).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`CursorVelocity` + `VelocityRing` + `CursorIntegrator` (CortexRender)** — the entire velocity seam is
  already built and was explicitly designed to accept the Phase-7 Kalman as its producer. The integrator
  already rejects non-finite velocity and clamps to `[0,1]`, so the Kalman does not need its own output
  safety net (but should still emit finite values).
- **`WebgridParams` (CortexRender)** — 30×30 grid geometry reused by the headless BPS harness for
  target/cell coordinates and the acquisition test.
- **`NeuralDecoder.decode(_:) -> SIMD2<Float>` (CortexDecoder)** — the filter's upstream input; fp16
  widened to `Float`. `velocityDimension == 2` is the frozen output contract.
- **`CortexDecoderBench/main.swift` + `LatencyHistogram` (CortexDecoder)** — the bench-executable +
  histogram patterns for the BPS harness and the SC#3 tail-latency proof.
- **`LissajousProducer` (CortexRender)** — the determinism contract (closed-form, seed/`t`-only, no clock/
  RNG) is the template for the reproducible BPS replay.
- **`Decoder/` uv subsystem** — owns Indy data loading (`scripts/download_indy.py`, `tests/test_data.py`),
  the NDT1 model, and the `velocity_head`. Q/R fitting + Riccati solve land here (D-15).
  Run `uv sync --project Decoder --extra dev` before its tooling (pytest/ruff live in an `--extra dev`).

### Established Patterns
- **Velocity-typed seam (Phase 6 D-03/D-04)** — producers emit `CursorVelocity`; the integrator is the
  single validation point. The Kalman conforms; no seam change.
- **Hot-path discipline (Phase 3 THREAD-01/02 + `hotpath-policy.sh`)** — Foundation-free `import Darwin`/
  `simd`, `QOS_CLASS_USER_INTERACTIVE`, no `dispatch_async`/locks/heap on the path. SC#3 binds the filter
  to the existing decoder pthread.
- **Device-gated, committed-evidence, CI-guard culture** — measured-not-asserted claims, seed-locked
  deterministic artifacts, build-failing regression gates (DEC param guardrail, co-bps>null, render-policy).
- **Per-subsystem Swift packages + `#[repr(C)]`/cbindgen FFI discipline** — the new `CortexReFIT` package
  follows the established split.

### Integration Points
- **Upstream:** `NeuralDecoder.decode() -> SIMD2<Float>` (on the decoder pthread, post-CoreML).
- **Filter:** `CortexReFIT` Kalman (predict → rotate measurement → update → emit refined velocity).
- **Downstream:** write `CursorVelocity` into `VelocityRing`; renderer pops + `CursorIntegrator.integrate`.
- **Measurement:** headless harness replays Indy → decoder → `[raw|Kalman-only|Kalman+rot]` → integrator →
  webgrid acquisition → S&M 2004 throughput → `07-bps-evidence.md` + JSON + CI guard.
- **Offline:** `Decoder/` fits Q/R + solves the steady-state gain → committed Swift constants.

</code_context>

<specifics>
## Specific Ideas

- The seam comments in `CursorVelocity.swift` / `CursorIntegrator.swift` were written in Phase 6
  specifically for this phase ("Phase 7's Kalman feeds unchanged — it also emits a velocity"). Treat them
  as a contract: **do not re-architect the seam.**
- The honesty framing matters to the audience (Bliss Chapman / Nir Even-Chen): this is a **ReFIT-inspired
  online intent-rotation assist on synthetic replay**, not a live-human two-stage ReFIT retrain — the
  artifact must say so plainly, and the 3-way ablation (D-12) is the transparency mechanism.
- BPS uplift is measured raw-vs-ReFIT on the **identical seed-locked replay**; the delta is the filter's
  pure contribution.

</specifics>

<deferred>
## Deferred Ideas

- **Classic two-stage ReFIT retraining** (rotate intended kinematics over a calibration block → re-fit KF
  params / decoder readout offline → run recalibrated filter) — more faithful to Gilja 2012, but heavier
  and couples back into the decoder training loop. Rejected in favor of the online per-tick assist (D-04).
  Candidate future enhancement if a stronger BPS claim is wanted.
- **Synthetic intent→spikes forward model** (drive the decoder to arbitrary 30×30 webgrid targets) —
  rejected (D-11) because the BPS would partly measure the forward model, not the decoder. Could enable a
  true free-form webgrid task later if a generative spike model is built.
- **Rust + `cbindgen` `#[repr(C)] CursorVelocity` producer** — the seam anticipates it and the project's
  loom culture favors it, but spec/REFIT-01 say Swift side (D-03). Possible future port for
  loom-checkable correctness.
- **Live on-device 120 Hz closed-loop demo (SYS-06)** and the **formal BrainGate-4.16/Neuralink-8.5
  leaderboard claim (PERF-01/02)** — explicitly **Phase 8** (v0 ship), not this phase.
- **Angle-limited / partial-blend rotation** — a more conservative rotation knob; not used now (D-06 uses
  full align), but available if the uplift looks overstated.

</deferred>

---

*Phase: 07-refit-kalman-closed-loop-recalibration*
*Context gathered: 2026-06-22*
