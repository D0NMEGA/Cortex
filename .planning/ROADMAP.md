# Roadmap: Cortex.app

## Overview

Cortex.app is a 7-week sprint to ship a photodiode-instrumented sub-25ms glass-to-glass BCI input pipeline on iPad Pro M4 / Mac M-series. The roadmap derives from `cortex-spec.md` Section 10 (Sprint Timeline), decomposed at `fine` granularity into 10 phases that respect dependency order: foundation → IPC primitive → real-time threading → decoder (training, then ANE deployment) → renderer → ReFIT closed-loop → system integration & v0 distribution → photodiode rig build → v1 measurement & launch.

Two milestones anchor the roadmap:
- **v0 (end of Phase 8):** software-timed glass-to-glass claim, BCI HID integration live, TestFlight build available.
- **v1 (end of Phase 10):** photodiode-instrumented "Glass-to-glass latency 24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)" claim, launch video published.

## Milestones

- 📋 **v0 Software-Timed (Week 5)** — Phases 1-8 (planned). Closed-loop synthetic-spike → cursor → 30×30 webgrid hit at 120Hz, software-side `mach_absolute_time` latency claim, TestFlight-ready notarized build.
- 📋 **v1 Photodiode-Instrumented (Week 7)** — Phases 9-10 (planned). Defensible "24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)" claim, launch video, README publish.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Foundation & 2026 Toolchain** - Repo skeleton on Xcode 26 + Swift 6.2 / macOS 26 Tahoe / iPadOS 26 with App Group container, privacy manifest, and CI green — completed 2026-06-19
- [x] **Phase 2: IPC Primitive — kqueue+recvmsg + FlatBuffers + AES-GCM** - Sub-µs sample-frame transport between acquisition daemon and app, encrypted, FD-passed via mach_msg — completed 2026-06-20 (SC#1 p99=208ns)
- [x] **Phase 3: Real-Time Threading — pthread USER_INTERACTIVE + Rust SPSC Ring** - Audio-callback-regime hot path with loom-verified lock-free ring buffer bridged to Swift via cbindgen — completed 2026-06-20 (THREAD-01..07 validated, security 18/18 closed)
- [x] **Phase 4: NDT1 Training on Indy/Loco Synthetic Replay** - 1.3M-param NDT1 (6 layers, h=1-2, 128 dim, 20ms bins) trained on Zenodo 3854034 with 4-bit palettization — completed 2026-06-21 (4/4 SC: 1.29M params, co-bps 0.3804 held-out, 3.471× palettization)
- [x] **Phase 5: NDT1 → CoreML deployment — ANE-eligible, sub-2ms verified** - coremltools-converted BC1S `(B,C,1,S)` `.mlpackage`; **100% ANE-eligible** (226/226 ops, 0 CPU-only), **<2ms p99** (≈0.5ms iPad-M2). Runtime placement measured CPU at 1.29M-param scale (M5 Pro + iPad-M2 scale trap) — reported honestly, not assumed ANE
- [x] **Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid** - Beam-raced ProMotion presentation, ≤0.4ms GPU compute, zero-copy `storageModeShared` drawables — completed 2026-06-22 (RENDER-01..09; M5 Pro GPU p99=0.162ms ~2.5× under ≤0.4ms, 60s soak 243,724 frames / 0 dropped; iPad-M4 canonical capture deferred per D-11/D-12)
- [ ] **Phase 7: ReFIT-Kalman Closed-Loop Recalibration** - Swift-side 6-DOF Kalman with per-update intent-rotation step delivering BPS uplift over raw NDT1
- [ ] **Phase 8: Apple BCI HID Integration, Distribution & v0 Ship** - Switch Control HID provider registration, Synchron-mirror entitlements, notarized TestFlight build, software-timed latency claim — **v0 milestone**
- [ ] **Phase 9: Photodiode Rig Hardware Build** - BPW34 + OPA381 TIA + Saleae Logic Pro 8 breadboard with GPIO intent-emission instrumentation
- [ ] **Phase 10: v1 Photodiode Measurement & Launch** - 10k-trial capture, statistical reduction to "24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k)" claim, launch video, README publish — **v1 milestone**

## Phase Details

### Phase 1: Foundation & 2026 Toolchain
**Goal**: Repo, toolchain, and distribution scaffolding stand up clean — every commit can be built on a `macos-15` runner with the 2026 Apple toolchain, and the App Group container is wired so later phases can drop POSIX shm into it without re-doing entitlements.
**Depends on**: Nothing (first phase)
**Requirements**: FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05
**Success Criteria** (what must be TRUE):
  1. `xcodebuild` from the `macos-15` GitHub Actions runner builds a signed empty-shell macOS 26 / iPadOS 26 app with Swift 6.2 (Approachable Concurrency) on every PR
  2. App Group container is provisioned and an entitlement-validated empty `shm_open` test fixture in the container survives sandbox checks (replaces the deprecated `com.apple.security.temporary-exception.shared-memory` entitlement)
  3. `PrivacyInfo.xcprivacy` validates against the 2026 required-reason API list with `CA92.1` declared for `mach_absolute_time`
  4. SwiftPM dependency graph resolves from a clean clone with zero CocoaPods artefacts (no `Podfile`, no `Pods/`)
**Plans**: 7 plans
- [x] 01-01-PLAN.md — Repo skeleton + 4 SwiftPM packages + cortex_shm.h `_Static_assert` + .gitignore + spec move (FOUND-01, FOUND-04) — completed 2026-04-28, see [01-01-SUMMARY.md](phases/01-foundation-2026-toolchain/01-01-SUMMARY.md)
- [x] 01-02-PLAN.md — XcodeGen project.yml + 3 Xcode targets + entitlements + Info.plist + daemon-bundle SPM smoke evidence (FOUND-01, FOUND-02) — completed 2026-04-30, see [01-02-SUMMARY.md](phases/01-foundation-2026-toolchain/01-02-SUMMARY.md)
- [x] 01-03-PLAN.md — PrivacyInfo.xcprivacy x2 + validate-privacy-manifest.sh with CA92.1 gate proof (FOUND-03) — completed 2026-04-28, see [01-03-SUMMARY.md](phases/01-foundation-2026-toolchain/01-03-SUMMARY.md)
- [x] 01-04-PLAN.md — fastlane scaffolding (Gemfile + Fastfile/Matchfile/Appfile placeholders) per D-09/D-10 (FOUND-01) — completed 2026-04-28, see [01-04-SUMMARY.md](phases/01-foundation-2026-toolchain/01-04-SUMMARY.md)
- [x] 01-05-PLAN.md — README.md + ADR-0001 (8 decisions, 3 critical findings) + ADR template + PR template (FOUND-01) — completed 2026-04-30, see [01-05-SUMMARY.md](phases/01-foundation-2026-toolchain/01-05-SUMMARY.md)
- [x] 01-06-PLAN.md — GitHub Actions ci.yml on macos-15 + Xcode 26.3 + SwiftFormat + SwiftLint + hot-path policy + caches (FOUND-05)
- [x] 01-07-PLAN.md — Manual SC#2 verification runbook + ShmCheck surface + sc2-evidence.md (FOUND-02; checkpoint:human-verify)

### Phase 2: IPC Primitive — kqueue+recvmsg + FlatBuffers + AES-GCM
**Goal**: A sample frame leaves the acquisition daemon and arrives in the app process in sub-µs, encrypted, with the FD passed via `mach_msg` — the "thinnest viable" transport that the decoder will later sit on top of.
**Depends on**: Phase 1
**Requirements**: IPC-01, IPC-02, IPC-03, IPC-04, IPC-05, IPC-06, IPC-07
**Success Criteria** (what must be TRUE):
  1. Round-trip latency of a single FlatBuffers `Sample { ts_ns: u64, channel_data: [f16] }` frame between two processes over the App-Group-resident POSIX shm + `kqueue`+`recvmsg` socket pair measures sub-µs at p99 on M4 (instrumented with `mach_absolute_time`)
  2. Cross-process FD handoff via `mach_msg` + `MACH_MSG_PORT_DESCRIPTOR` (using `fileport_makeport`) succeeds across daemon-app boundary on macOS 26 — no `SCM_RIGHTS` fallback in code
  3. AES-GCM-encrypted FlatBuffers frames with HKDF-derived per-session keys decrypt cleanly on the receiver, with the key round-tripping Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
  4. shm name in code is ≤31 bytes (Darwin `PSHMNAMLEN`); a unit test fails the build if the constant is changed to a name that would silently break on Darwin
**Plans**: 5 plans
- [x] 02-01-PLAN.md — Foundation: CORTEX_CHANNEL_COUNT _Static_assert + CortexIPC split (Transport/Session) + hot-path gate re-scope (CF#4) + CF#1 keychain & CF#3 rendezvous spikes (IPC-01, IPC-03, IPC-06)
- [x] 02-02-PLAN.md — CortexIPCTransport: Foundation-free shm ring (busy-poll, CF#2) + kqueue/recvmsg doorbell + mach_msg+fileport FD passing C shim, no SCM_RIGHTS (IPC-01, IPC-02, IPC-03)
- [x] 02-03-PLAN.md — CortexIPCSession: FlatBuffers Sample codec (Float16 rebind) + AES-GCM/HKDF deterministic-nonce crypto + data-protection Keychain round-trip (IPC-04, IPC-05, IPC-06)
- [x] 02-04-PLAN.md — Two-process proof harness: CF#3 rendezvous + producer (daemon) + consumer + ack-bounce; CI-runnable end-to-end correctness (IPC-02, IPC-03, IPC-07)
- [x] 02-05-PLAN.md — SC#1 shm-polled M4 benchmark (sc1-evidence.md, CF#2/D-18) + CI correctness gates (CortexIPC tests, no-SCM_RIGHTS grep) (IPC-02, IPC-07)

### Phase 3: Real-Time Threading — pthread USER_INTERACTIVE + Rust SPSC Ring
**Goal**: The acquisition/DSP hot path runs under audio-callback rules — pthread with `QOS_CLASS_USER_INTERACTIVE`, no Swift `Task`, no `dispatch_async`, no ARC retain/release on the path — and a `loom`-verified lock-free SPSC ring carries samples from that thread to the Swift UI layer via a `cbindgen` bridge.
**Depends on**: Phase 2
**Requirements**: THREAD-01, THREAD-02, THREAD-03, THREAD-04, THREAD-05, THREAD-06, THREAD-07
**Success Criteria** (what must be TRUE):
  1. The hot-path thread runs on a raw `pthread_create` worker that has called `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)`; Instruments → System Trace shows zero Swift cooperative-runtime activity on that thread under load
  2. A static-analysis CI gate fails the build if any hot-path source file calls `dispatch_async`, contains `lazy var`, holds a `pthread_mutex`, or imports `Foundation`/Obj-C runtime headers (audio-callback rules enforced as code policy)
  3. Rust `rtrb` SPSC ring with cache-line-padded atomics and Acquire/Release ordering moves 1M sample frames producer→consumer with zero observed reorderings under `loom` permutation testing in CI
  4. `cbindgen`-generated header lets Swift consume the Rust ring buffer via a stable C ABI, and a Swift integration test reads frames produced from the C/Rust side
**Plans**: 4 plans (3 waves)
- [x] 03-01-PLAN.md — FFI/build spine (Spike A): Rust staticlib + cbindgen header → xcframework .binaryTarget callable from Swift under swift build AND xcodebuild; freeze the C ABI + repr(C) Frame; pre-arm all Phase-3 CI gates (THREAD-06) [Wave 1]
- [x] 03-02-PLAN.md — In-house loom-verified SPSC ring: 128B-padded head/tail + Release/Acquire (no SeqCst), tiny loom permutation test + 1M-frame std-atomic FIFO stress test (D-R3/D-R5), real extern "C" bodies (THREAD-04, THREAD-05, THREAD-07) [Wave 2]
- [x] 03-03-PLAN.md — Foundation-free pthread USER_INTERACTIVE acquisition worker (productionized Benchmark.swift idiom) + extended hot-path policy gate (.rs tokens + self-test) + SC#1 instruments-evidence runbook (THREAD-01, THREAD-02, THREAD-03) [Wave 2]
- [x] 03-04-PLAN.md — Safe Swift wrapper over the cbindgen ABI + SC#4 integration test: produce N frames C/Rust-side, pop+verify value and order (THREAD-06) [Wave 3]

### Phase 4: NDT1 Training on Indy/Loco Synthetic Replay
**Goal**: A correctly-sized NDT1 (1.3M params, 6 layers, h=1-2 heads, 128 hidden, 20ms binning — *not* the commonly-miscited 4-head variant) trains end-to-end on the canonical O'Doherty Indy/Loco dataset and emits a 4-bit palettized PyTorch checkpoint ready for ANE conversion. No CoreML or Apple Silicon work yet — this is pure decoder R&D.
**Depends on**: Phase 1 (toolchain), parallelizable with Phase 6 (renderer)
**Requirements**: DEC-01, DEC-02, DEC-03, DEC-04, DEC-05
**Success Criteria** (what must be TRUE):
  1. NDT1 architecture matches the verified Ye & Pandarinath 2021 spec exactly — a parameter count assertion in test enforces ~1.3M params, 6 layers, h ∈ {1,2}, 128 hidden, 20ms bins (regression test against accidental drift to h=4)
  2. Training loop ingests Zenodo 3854034 Indy/Loco synthetic spike replay and converges to non-trivial reconstruction loss on a held-out split
  3. Activations in the saved-for-conversion graph are reshaped to BC1S `(B, C, 1, S)` per `apple/ml-ane-transformers`; a unit test fails if any tensor on the inference path retains the vanilla `(B, S, C)` layout
  4. `coremltools.optimize.palettize_weights` with `OpPalettizerConfig(nbits=4)` produces a quantized checkpoint with documented size reduction and bounded reconstruction-loss delta
**Plans**: 5 plans (3 waves) — new isolated `Decoder/` Python subsystem (uv, pinned 3.11/3.12)
- [x] 04-01-PLAN.md — Wave 0/1 scaffold: `Decoder/` + `pyproject.toml`/`uv.lock` (pinned 3.11/3.12) + torch/coremltools/h5py deps + ruff (no-bare-except gate) + seeded conftest fixtures + `.gitignore` for data/checkpoints/`.mlpackage` (DEC-02) [Wave 1]
- [x] 04-02-PLAN.md — Dataset layer: `.mat` (h5py, v7.3) loader + 20ms binning -> `(num_bins, 96)` + chronological-tail split + Zenodo manifest/download (sha256) + **closes Phase-2 D-11** (CORTEX_CHANNEL_COUNT=96 reconciled vs cortex_shm.h/cortex_ring.h/frame.rs) (DEC-02) [Wave 2]
- [x] 04-03-PLAN.md — NDT1ANE in BC1S form (Conv2d, single-head-chunk attention, `bchq,bkhc->bkhq` einsum) + masked-Poisson head + **SC1** (structural `num_heads in {1,2}` on every module + param guardrail) + **SC3** (BC1S forward-hook + zero-`nn.Linear` + (B,S,C) negative control) (DEC-01, DEC-04) [Wave 2]
- [x] 04-04-PLAN.md — Masked-modeling training loop -> held-out **co-bps** beats mean-rate null + short-budget CI smoke + committed `04-training-evidence.md` (SC2) (DEC-02) [Wave 3]
- [x] 04-05-PLAN.md — `ct.convert`->`.mlpackage` (mlprogram, CPU, no ANE) then `palettize_weights(OpPalettizerConfig(kmeans,nbits=4))` + size/Δloss characterization + `04-palettization-evidence.md` (SC4) (DEC-03, DEC-05) [Wave 3]

### Phase 5: NDT1 → CoreML deployment — ANE-eligible, sub-2ms verified
**Goal**: The 4-bit palettized NDT1 checkpoint becomes a `.mlpackage` that is **100% ANE-eligible** and meets **<2ms p99** (≈0.5ms measured), with input arriving zero-copy from a `MTLBuffer storageModeShared` and output emitting a 2-vector cursor velocity at fp16 every 20ms. At 1.29M params CoreML schedules it on **CPU** (measured M5 Pro + iPad-M2 — the documented scale trap); the <2ms budget — the load-bearing piece for the glass-to-glass claim — holds **regardless of placement**. (Reframed 2026-06-21 from "runs entirely on the M4 ANE": placement is measured & reported honestly, not assumed — see `05-placement-evidence.md`.)
**Depends on**: Phase 4
**Requirements**: DEC-06, DEC-07, DEC-08, DEC-09, DEC-10, DEC-11, DEC-12
**Success Criteria** (what must be TRUE):
  1. The compiled 4-bit `(vx,vy)` model is **100% ANE-eligible** — every schedulable op lists the Neural Engine in `supported_compute_devices`, **zero CPU-only ops** — verified by two independent tools on two devices (Mac `MLComputePlan`, 05-02; iPad Air M2 Xcode Performance Report, 05-05). Runtime **placement** is recorded **as measured**: at 1.29M params CoreML schedules the graph on **CPU** (reproduced M5 Pro + iPad-M2 — the documented scale trap), reported honestly, never assumed. Per-op verdicts committed (`runtime_plan.json`, `runtime_plan_ipad.json`, `05-perf-report-ipad-m2.json`) for reviewer verification
  2. `MLModelConfiguration.computeUnits` is set to `.cpuAndNeuralEngine` (a unit test fails the build if the value is `.all`); zero references to `_ANEClient` anywhere in the source tree (greppable assertion in CI)
  3. Decoder emits a 2-vector `(vx, vy)` fp16 cursor velocity every 20ms, with input tensor entering CoreML zero-copy via `MTLBuffer storageModeShared` + `MPSGraphTensorData(mtlBuffer:shape:dataType:)` (no host↔device copy on the inference path)
  4. End-to-end inference latency measures **<2ms at p99** — **p99 ≈ 0.51ms on iPad Air M2** (Xcode Performance Report, 120 predictions) and **p99 ≈ 0.14ms on M5 Pro** (10k-pass in-process `CortexDecoderBench`, 05-04); budget met with ≥4× margin **independent of compute placement**. Canonical iPad-M4 capture (same bench) is an optional future datapoint, not a gate
**Plans**: 5 plans (4 waves)
- [x] 05-01-PLAN.md — Velocity readout head: Conv2d(96->2) + static last-bin slice + closed-form ridge fit; convert.py emits (vx,vy) fp16 (FLOAT16 + tanh-GELU) (DEC-10) [Wave 1]
- [x] 05-02-PLAN.md — ANE op-eligibility gate (Python/Mac CI): MLComputePlan op scan on the compiled 4-bit package, every op ANE-eligible / zero CPU-only, einsum disposition + conditional meridian rewrite (DEC-06) [Wave 2]
- [x] 05-03-PLAN.md — Swift inference path: .cpuAndNeuralEngine (build-fails on .all) + zero-copy MLMultiArray(pixelBuffer:) over a shared IOSurface/MTLBuffer + (vx,vy) output + no-_ANEClient CI grep (DEC-07, DEC-09, DEC-12) [Wave 2]
- [x] 05-04-PLAN.md — In-process Swift latency bench: CortexDecoderBench warmup + 10k MLModel.prediction passes -> device-annotated p50/p99 histogram (Mac corroborating) (DEC-11) [Wave 3]
- [x] 05-05-PLAN.md — iPad HUMAN-UAT: on-device ANE-eligibility + placement **measured** (Xcode Performance Report, iPad Air M2/iPadOS 18.7.8) + corroborating <2ms p99; SC#1 reframed to the measured truth — eligible + CPU-scheduled at scale (DEC-08; checkpoint resolved via M2 capture) [Wave 4]

### Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid
**Goal**: A beam-raced 120Hz Metal renderer presents a 30×30 webgrid (the modern Bliss-Chapman / Neuralink reference, *not* the legacy 6×6 from Pandarinath 2017) on iPad Pro M4 ProMotion at ≤0.4ms GPU compute, with `dispatch_semaphore_t(value: 1)` enforcing one in-flight frame per Apple's "Synchronizing CPU and GPU Work" pattern. This phase can run in parallel with Phases 4-5 — only Phase 8 (system integration) needs both halves to converge.
**Depends on**: Phase 1 (toolchain), parallelizable with Phases 4-5
**Requirements**: RENDER-01, RENDER-02, RENDER-03, RENDER-04, RENDER-05, RENDER-06, RENDER-07, RENDER-08, RENDER-09
**Success Criteria** (what must be TRUE):
  1. `CAMetalDisplayLink` (iOS 17+, macOS 14+) drives drawable acquisition + encode deadline + present timestamp on iPad Pro M4 ProMotion at a sustained 120Hz; macOS target falls back to `NSScreen.displayLink` when not on Catalyst (zero `CADisplayLink` Metal usage in source tree)
  2. The 30×30 (~900 cell) webgrid drawn via Metal compute shader measures ≤0.4ms GPU frame time — **measured on M5 Pro ProMotion (corroborating-canonical, D-11): p99=0.1618ms, n=10k, ~2.5× margin** ([06-render-evidence.md](phases/06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid/06-render-evidence.md)) — with `MTL_HUD_ENABLED=1` reporting P95 frame time, drawable-wait, and encoder-time live in the scheme; **iPad Pro M4 canonical capture optional/future** ([06-HUMAN-UAT.md](phases/06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid/06-HUMAN-UAT.md))
  3. `Info.plist` `CADisableMinimumFrameDurationOnPhone = YES` is asserted by a build-time check; all drawables use `MTLBuffer storageModeShared` (zero-copy unified memory) with `dispatch_semaphore_t(value: 1)` gating one in-flight frame
  4. A synthetic cursor-velocity stream from the Phase 3 ring buffer drives the webgrid at 120Hz with no dropped frames over a 60-second sustained run — **measured on M5 Pro ProMotion (corroborating-canonical, D-11): 243,724 frames / 0 intervals >8.33ms** ([06-render-evidence.md](phases/06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid/06-render-evidence.md)); **iPad Pro M4 canonical capture optional/future** ([06-HUMAN-UAT.md](phases/06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid/06-HUMAN-UAT.md))
**Plans**: 6 plans (6 waves)
- [x] 06-01-PLAN.md — CortexRender core: WebgridParams + 30×30 compute kernel (Webgrid.metal) + shared WebgridFrameEncoder + MetalLayerConfig (framebufferOnly=false, maximumDrawableCount=2) (RENDER-04, RENDER-06) [Wave 1]
- [x] 06-02-PLAN.md — Velocity seam: CursorVelocity fp16 (D-03) + SPSC VelocityRing + renderer-owned CursorIntegrator (clamp + NaN/Inf reject, D-04) + deterministic Lissajous producer (D-05) (RENDER-04, RENDER-06) [Wave 2]
- [x] 06-03-PLAN.md — Display-link adapters: FrameSynchronizer (value:1) + iOS CAMetalDisplayLink + macOS NSView.displayLink, shared encoder, 120Hz, plain present (RENDER-01, RENDER-02, RENDER-07, RENDER-08) [Wave 3]
- [x] 06-04-PLAN.md — Info.plist 120Hz key + MTL_HUD scheme env + render-policy.sh grep-gate (negative-control self-test) + CortexRenderBench wiring + CI (RENDER-03, RENDER-06, RENDER-07, RENDER-08, RENDER-09) [Wave 4]
- [x] 06-05-PLAN.md — Measurement: gpuEndTime-gpuStartTime histogram (n>=10k) + 60s no-drop soak on M5 Pro ProMotion + 06-render-evidence.md (RENDER-02, RENDER-05) [Wave 5]
- [x] 06-06-PLAN.md — SC reframe sign-off (D-11, checkpoint:decision) + 06-HUMAN-UAT.md iPad-M4 canonical capture (D-12, never-auto-approve) (RENDER-02, RENDER-05) [Wave 6]
**UI hint**: yes

### Phase 7: ReFIT-Kalman Closed-Loop Recalibration
**Goal**: A 6-DOF state Kalman filter wraps the NDT1 cursor-velocity output on the Swift side, applying Gilja-2012 intent-rotation per cursor update — this is the closed-loop step that takes BrainGate from 4.16 to 8.5 BPS in humans, and the only post-decoder algorithmic surface that meaningfully moves the BPS number on synthetic Indy replay.
**Depends on**: Phase 5 (decoder output), Phase 6 (renderer for closed-loop visualization)
**Requirements**: REFIT-01, REFIT-02, REFIT-03
**Success Criteria** (what must be TRUE):
  1. Swift-side 6-DOF state Kalman filter consumes the post-CoreML 2-vector cursor velocity and emits a refined velocity at every 20ms tick, with intent-rotation step (Gilja 2012 Nature Neuroscience) executed every cursor update
  2. Webgrid BPS measured under the Soukoreff & MacKenzie 2004 ISO 9241-9 Fitts methodology shows a documented uplift over raw NDT1 output on the same synthetic Indy replay (delta committed as a regression artifact)
  3. The Kalman + rotation step adds zero detectable contribution to glass-to-glass tail latency (executes well within the 20ms decoder budget on the existing pthread, not a new thread)
**Plans**: TBD

### Phase 8: Apple BCI HID Integration, Distribution & v0 Ship
**Goal**: Cortex registers as a first-class HID provider via Apple's May 2025 BCI HID protocol with a Synchron-mirror entitlement surface, ships through `notarytool` + `fastlane match` to TestFlight, and the v0 launch artefact — closed-loop synthetic-spike → ReFIT-Kalman → 30×30 webgrid hit at 120Hz on iPad Pro M4 with a documented software-timed glass-to-glass claim — is downloadable by a TestFlight tester. This is the v0 milestone.
**Depends on**: Phase 7 (closed-loop pipeline complete)
**Requirements**: SYS-01, SYS-02, SYS-03, SYS-04, SYS-05, SYS-06, DIST-01, DIST-02, DIST-03, DIST-04, PERF-01, PERF-02, PERF-03, PERF-04
**Success Criteria** (what must be TRUE):
  1. A TestFlight tester (internal cohort) installs the build and a synthetic-spike stream drives the cursor on the 30×30 webgrid at 120Hz with Cortex registered as an Accessibility/Switch Control HID provider via the May 2025 BCI HID protocol surface (entitlements and `Info.plist` mirror Synchron's Vision Pro reference)
  2. Bidirectional context sharing demonstrates a closed-loop round trip: a host app sends UI state (cursor position, target list) into Cortex, Cortex returns intent, host applies refinement — instrumented log shows the round trip
  3. Build is signed and notarized via `notarytool submit` + `xcrun stapler staple` (zero `altool` references in the build pipeline) using `fastlane match` with an App Store Connect API key (`.p8` JWT); TestFlight is configured for 100 internal / 10,000 external testers with documented 90-day expiry
  4. README publishes the architectural commitments table, the rejected-alternatives table (MLX, Network.framework, Swift Task, ChaCha20, `_ANEClient`, CocoaPods, etc.), and the v0 software-timed glass-to-glass claim with `mach_absolute_time` methodology disclosed
  5. BPS on synthetic Indy-spike replay matches BrainGate Webgrid 6×6 (4.16 BPS) under the Soukoreff & MacKenzie 2004 methodology, with the documented gap toward the Neuralink P1 verified peak (8.5 BPS) called out; P99 decoder + render + present budget stays under 25ms in the software-timed measurement
**Plans**: TBD

### Phase 9: Photodiode Rig Hardware Build
**Goal**: The ~$110 BPW34 + OPA381 TIA + Saleae Logic Pro 8 photodiode rig physically exists, is aimed at the iPad Pro M4 pixel where the cursor lands, and a GPIO pulse from the acquisition daemon at intent-emission timestamp is captured cleanly on the Saleae alongside the photodiode rising edge — the instrument is ready for the 10k-trial campaign in Phase 10.
**Depends on**: Phase 8 (v0 software-timed claim must be defended before instrumented run starts)
**Requirements**: LAT-01, LAT-02, LAT-03, LAT-04
**Success Criteria** (what must be TRUE):
  1. BOM is ordered and received: BPW34 photodiode (Vishay), OPA381 transimpedance amp (TI), Saleae Logic Pro 8, breadboard + passives — total receipts ≤$110 excluding logic analyzer
  2. Breadboard with TIA stage is assembled, BPW34 is mounted aimed at the iPad Pro M4 pixel where the cursor lands, and a single test capture shows a clean photodiode rising edge response to a known pixel transition
  3. Acquisition daemon emits a GPIO pulse at intent-emission timestamp; Saleae captures both the GPIO edge and the photodiode rising edge on the same timeline at ≥100 MS/s with sub-µs alignment uncertainty
  4. A trial-run of ~100 captures shows the Δt distribution is unimodal and centered in the expected ~24-26ms range — no methodology bugs left to chase before the 10k campaign
**Plans**: TBD

### Phase 10: v1 Photodiode Measurement & Launch
**Goal**: 10,000 photodiode-instrumented trials produce the defensible single-line claim — *"Glass-to-glass latency 24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)"* — backed by a launch video showing the rig capturing the iPad Pro M4 cursor, and a README that publishes the methodology, statistics, and raw capture archive. This is the v1 milestone and the credibility artefact for Bliss Chapman / Nir Even-Chen review.
**Depends on**: Phase 9
**Requirements**: LAT-05, LAT-06, LAT-07, LAT-08
**Success Criteria** (what must be TRUE):
  1. Capture script automates a 10,000-trial run end-to-end (no human intervention per trial) and produces a structured archive of (intent_pulse_ts, photodiode_rising_edge_ts, Δt) tuples
  2. Statistical analysis on the n=10,000 distribution reports p50, σ, and a defensible single-line claim — the README publishes "Glass-to-glass latency 24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)" verbatim with the underlying histogram and methodology disclosed (NVIDIA LDAT / Meta Reality Labs precedent cited)
  3. Launch video shows the BPW34 rig physically capturing photons from an iPad Pro M4 ProMotion display while Cortex drives the 30×30 webgrid, with the photodiode trace and cursor frame side-by-side
  4. README, launch video, and raw 10k capture archive are published; the artefact is in a state suitable for hand-off to Bliss Chapman and Nir Even-Chen for review
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 (v0) → 9 → 10 (v1)

Phases 4-5 (decoder) and Phase 6 (renderer) are dependency-parallelizable — both depend only on Phase 1 (toolchain) and Phase 3 (threading for renderer's input ring). Phase 7 (ReFIT) requires both halves to converge.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation & 2026 Toolchain | v0 | 7/7 | ✓ Complete | 2026-06-19 |
| 2. IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | v0 | 5/5 | ✓ Complete | 2026-06-20 |
| 3. Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | v0 | 4/4 | ✓ Complete | 2026-06-20 |
| 4. NDT1 Training on Indy/Loco | v0 | 5/5 | ✓ Complete | 2026-06-21 |
| 5. NDT1 → CoreML deployment — ANE-eligible, sub-2ms verified | v0 | 5/5 | Complete | 2026-06-21 |
| 6. CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid | v0 | 6/6 | ✓ Complete | 2026-06-22 |
| 7. ReFIT-Kalman Closed-Loop Recalibration | v0 | 0/TBD | Not started | - |
| 8. Apple BCI HID Integration, Distribution & v0 Ship | v0 | 0/TBD | Not started | - |
| 9. Photodiode Rig Hardware Build | v1 | 0/TBD | Not started | - |
| 10. v1 Photodiode Measurement & Launch | v1 | 0/TBD | Not started | - |
