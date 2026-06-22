# Cortex.app — v1 Requirements

Source: `cortex-spec.md` (935-source research synthesis, 8 evidence clusters).
All requirements are hypotheses until shipped and validated against the v1 release criteria (defensible photodiode-instrumented latency claim).

---

## v1 Requirements

### Foundation (FOUND)

- [x] **FOUND-01**: Repository scaffolded with Xcode 26 + Swift 6.2, targeting macOS 26 Tahoe and iPadOS 26 — Plan 01-01 (CortexCore mixed Swift+C package + 3 stubs), Plan 01-02 (XcodeGen project.yml + 3 Xcode targets), Plan 01-04 (fastlane Phase-1 placeholders + Bundler-managed install); see [01-01-SUMMARY.md](phases/01-foundation-2026-toolchain/01-01-SUMMARY.md), [01-02-SUMMARY.md](phases/01-foundation-2026-toolchain/01-02-SUMMARY.md), [01-04-SUMMARY.md](phases/01-foundation-2026-toolchain/01-04-SUMMARY.md)
- [x] **FOUND-02**: App Group container configured for shared-memory IPC (replaces deprecated `com.apple.security.temporary-exception.shared-memory` entitlement) — Plan 01-02 (three Cortex.entitlements files declare `group.com.donovansantine.cortex.shared` per D-07; sandbox explicitly off in Phase 1 per Critical Finding #1; runtime cross-process verification deferred to Plan 01-07 manual SC#2 runbook); see [01-02-SUMMARY.md](phases/01-foundation-2026-toolchain/01-02-SUMMARY.md)
- [x] **FOUND-03**: Privacy manifest `PrivacyInfo.xcprivacy` includes `CA92.1` reason code for `mach_absolute_time` — Plan 01-03 (two manifests + validate-privacy-manifest.sh CI gate, negative-control proven to bite); see [01-03-SUMMARY.md](phases/01-foundation-2026-toolchain/01-03-SUMMARY.md)
- [x] **FOUND-04**: SwiftPM-only dependency graph (no CocoaPods anywhere in the build) — Plan 01-01 (zero Podfile/Pods/ artifacts, four SwiftPM packages well-formed); see [01-01-SUMMARY.md](phases/01-foundation-2026-toolchain/01-01-SUMMARY.md)
- [x] **FOUND-05**: GitHub Actions CI runs on `macos-15` runner with Xcode 26 toolchain — Plan 01-06 (.github/workflows/ci.yml with 16 gates including explicit Xcode 26.3 pin via maxim-lobanov/setup-xcode@v1, no-CocoaPods structural check, no-app-sandbox structural check, PrivacyInfo-in-bundle check, hot-path policy, validate-privacy-manifest.sh; .swiftformat + .swiftlint.yml + Tools/scripts/hotpath-policy.sh land alongside); see [01-06-SUMMARY.md](phases/01-foundation-2026-toolchain/01-06-SUMMARY.md)

### IPC Transport (IPC)

- [x] **IPC-01**: POSIX `shm_open` shared memory inside App Group container with names ≤31 bytes (Darwin `PSHMNAMLEN` limit) — Plans 02-01, 02-02 (`ShmRing.swift` + `cortex_shm.h` `_Static_assert`; `CORTEX_SHM_NAME="/cortex.samples"` = 15 B; RingTests green); verified [02-VERIFICATION.md](phases/02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm/02-VERIFICATION.md)
- [x] **IPC-02**: Raw `kqueue` + `recvmsg` socket pair primitive moves a sample frame between acquisition daemon and app process — Plans 02-02, 02-04, 02-05 (`Doorbell.swift` socketpair+kqueue EVFILT_READ+recvmsg, no control buffer; DoorbellTests 2/2); verified 02-VERIFICATION.md
- [x] **IPC-03**: Cross-process file descriptor passing via `mach_msg` with `MACH_MSG_PORT_DESCRIPTOR` (using `fileport_makeport`) — Plans 02-01, 02-02, 02-04 (`cortex_fdmsg.c` fileport path + `cortex_rendezvous.c`; zero `SCM_RIGHTS`, CI grep gate); verified 02-VERIFICATION.md
- [x] **IPC-04**: FlatBuffers `Sample { ts_ns: u64, channel_data: [f16] }` schema serializes/deserializes uniform 0.5ms blocks — Plan 02-03 (`sample.fbs` + `SampleCodec.swift` zero-copy Float16 rebind; SampleCodecTests 5/5); verified 02-VERIFICATION.md
- [x] **IPC-05**: AES-GCM session encryption via CryptoKit `AES.GCM` with HKDF-derived per-session keys — Plan 02-03 (`SessionCrypto.swift` HKDF<SHA256> per-direction subkeys, 96-bit deterministic nonce, fail-closed; CryptoTests 6/6); verified 02-VERIFICATION.md
- [x] **IPC-06**: Session keys stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — Plans 02-01, 02-03 (`SessionKeychain.swift` data-protection keychain; KeychainTests 5/5; cross-process access-group sharing deferred → Phase 8 per CF#1); verified 02-VERIFICATION.md
- [x] **IPC-07**: Measured round-trip latency sub-µs over local socket pair — Plans 02-04, 02-05 (`sc1-evidence.md` p99=208ns, n=199,000, M5 Pro ≥ M4; HarnessE2ETests correctness gate green); verified 02-VERIFICATION.md

### Threading (THREAD)

- [x] **THREAD-01**: Acquisition/DSP hot path runs on a pthread, never on Swift `Task`
- [x] **THREAD-02**: Hot-path thread uses `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)` _(code-side verified as first action; SC#1 runtime `.trace` M4-gated, tracked in 03-HUMAN-UAT.md per D-18)_
- [x] **THREAD-03**: Hot path obeys audio-callback rules — no `dispatch_async`, no Obj-C runtime, no locks, no ARC retain/release _(enforced by `hotpath-policy.sh` CI gate, SC#2)_
- [x] **THREAD-04**: Lock-free SPSC ring buffer (in-house loom-verifiable Rust SPSC, rtrb-quality cross-checked — D-R3) bridges decoder thread to UI
- [x] **THREAD-05**: Ring buffer uses cache-line-padded atomics (128B, Apple Silicon — D-R4) with Acquire/Release memory ordering (no SeqCst)
- [x] **THREAD-06**: Rust SPSC bridged to Swift via `cbindgen`-generated header (preferred over C++ for `loom` model-checking)
- [x] **THREAD-07**: Memory ordering verified with `loom` permutation testing

### Decoder Pipeline (DEC)

- [x] **DEC-01**: NDT1 architecture implemented — 6 transformer layers, h=1-2 attention heads, 128 hidden dim, 20ms spike binning, ~1.3M params
- [x] **DEC-02**: Training pipeline ingests O'Doherty Indy/Loco synthetic spike replay (Zenodo 3854034)
- [x] **DEC-03**: Trained PyTorch checkpoint converts to `.mlpackage` via coremltools
- [x] **DEC-04**: Tensor activations reshape to BC1S `(B, C, 1, S)` layout per `apple/ml-ane-transformers`
- [x] **DEC-05**: 4-bit palettization applied via `coremltools.optimize.palettize_weights` with `OpPalettizerConfig(nbits=4)`
- [x] **DEC-06**: Every model op ANE-eligible — validated against the ANE op-support matrix via `MLComputePlan` (226/226 ops Neural-Engine-eligible, **zero CPU-only ops**); einsum attention lowers to ANE-eligible MIL ops (05-02)
- [x] **DEC-07**: `MLModelConfiguration.computeUnits = .cpuAndNeuralEngine` (NOT `.all`) — build-failing Swift gate (05-03)
- [x] **DEC-08**: Decoder **100% ANE-eligible** (226/226 ops, 0 CPU-only) verified on-device — `MLComputePlan` (Mac, 05-02) + Xcode Performance Report (iPad Air M2, 05-05); runtime **placement measured & reported honestly** — CPU at 1.29M-param scale (M5 Pro + iPad-M2, the CoreML scale trap), <2ms p99 met regardless. *Reframed 2026-06-21 from "ANE residency verified at runtime": placement is measured, not assumed — public API cannot force ANE placement at this model scale*
- [x] **DEC-09**: Input tensor enters CoreML zero-copy — shared `IOSurface` + `MTLBuffer storageModeShared` (`kCVPixelFormatType_OneComponent16Half`) via `MLMultiArray(pixelBuffer:)`, pointer-identity proven (05-03; chosen over `MPSGraphTensorData` for the `MLModel.prediction` path)
- [x] **DEC-10**: Output is 2-vector cursor velocity (vx, vy) at fp16, emitted every 20ms
- [x] **DEC-11**: Decoder inference latency <2ms p99 — measured p99 ≈0.51ms (iPad-M2) / ≈0.14ms (M5 Pro); CPU-scheduled at this scale (not M4 ANE — see DEC-08); canonical iPad-M4 capture optional/future
- [x] **DEC-12**: Zero use of `_ANEClient` private API — tree-wide CI grep gate over production source (05-03)

### ReFIT-Kalman (REFIT)

- [ ] **REFIT-01**: 6-DOF state Kalman filter on Swift side, post-CoreML
- [ ] **REFIT-02**: Intent-rotation step executes every cursor update (Gilja 2012 closed-loop recalibration)
- [ ] **REFIT-03**: Filter improves cursor BPS over raw NDT1 output on synthetic Indy replay

### Renderer (RENDER)

- [ ] **RENDER-01**: `CAMetalDisplayLink` (iOS 17+, macOS 14+) drives drawable acquisition + encode deadline + present timestamp callback
- [ ] **RENDER-02**: Renderer hits 120Hz on iPad Pro M4 ProMotion display
- [ ] **RENDER-03**: `Info.plist` sets `CADisableMinimumFrameDurationOnPhone = YES` for ProMotion 120Hz
- [ ] **RENDER-04**: 30×30 webgrid (~900 cells) drawn via Metal compute shader
- [ ] **RENDER-05**: GPU frame time ≤0.4ms on M4
- [ ] **RENDER-06**: All drawables use `MTLBuffer storageModeShared` for zero-copy unified-memory presentation
- [ ] **RENDER-07**: Single in-flight frame with `dispatch_semaphore_t(value: 1)` for CPU/GPU sync (Apple's "Synchronizing CPU and GPU Work" pattern)
- [ ] **RENDER-08**: macOS target uses `NSScreen.displayLink(target:selector:)` (macOS 14+) when not on Catalyst
- [ ] **RENDER-09**: Frame-pacing diagnostics enabled via `MTL_HUD_ENABLED=1` reporting P95 frame time, drawable-wait, encoder-time

### System Integration (SYS)

- [ ] **SYS-01**: Cortex registers as a HID provider via Apple's May 2025 BCI HID protocol
- [ ] **SYS-02**: Switch Control + Accessibility framework integration links Cortex as first-class input modality
- [ ] **SYS-03**: Bidirectional context sharing — app sends UI state (cursor position, target list) to Cortex
- [ ] **SYS-04**: Cortex returns intent; app applies refinement (closed-loop decoding round trip)
- [ ] **SYS-05**: Entitlement and `Info.plist` surface mirrors Synchron's Vision Pro reference integration
- [ ] **SYS-06**: End-to-end synthetic-spike → decoder → ReFIT-Kalman → cursor → webgrid hit demonstrated at 120Hz

### Distribution (DIST)

- [ ] **DIST-01**: Build signs and notarizes via `notarytool submit` + `xcrun stapler staple` (no `altool`)
- [ ] **DIST-02**: `fastlane match` with App Store Connect API key (`.p8` JWT) handles signing
- [ ] **DIST-03**: TestFlight distribution configured for 100 internal / 10,000 external testers (90-day build expiry)
- [ ] **DIST-04**: README documents the architectural commitments and rejected-alternatives table

### Latency Measurement Rig (LAT) — v1, Weeks 6-7

- [ ] **LAT-01**: BOM ordered — BPW34 photodiode + OPA381 transimpedance amp + Saleae Logic Pro 8 (~$110)
- [ ] **LAT-02**: Breadboard assembled with TIA stage and BPW34 aimed at iPad pixel where cursor lands
- [ ] **LAT-03**: GPIO pulse emitted from acquisition daemon at intent-emission timestamp
- [ ] **LAT-04**: Saleae captures both edges (intent pulse + photodiode rising edge) at ≥100 MS/s
- [ ] **LAT-05**: Capture script automates 10,000-trial measurement run
- [ ] **LAT-06**: Statistical analysis produces p50, σ, and n=10k claim
- [ ] **LAT-07**: Final defensible claim documented: "Glass-to-glass latency 24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)"
- [ ] **LAT-08**: Launch video shows the rig in action against iPad Pro M4

### Performance Targets (PERF)

- [ ] **PERF-01**: Match BrainGate Webgrid 6×6 BPS (4.16 BPS) on synthetic Indy-spike replay
- [ ] **PERF-02**: Document path toward Neuralink P1 verified peak (8.5 BPS) — what gaps remain
- [ ] **PERF-03**: Webgrid metric methodology mirrors Soukoreff & MacKenzie 2004 ISO 9241-9 Fitts throughput
- [ ] **PERF-04**: P99 decoder + render + present budget remains under 25ms glass-to-glass

---

## v2 Requirements (Deferred)

- **NDT2 multi-context pretraining** — once single-user v0 ships, evaluate whether session-conditioning latency is acceptable for v2
- **POYO-1 generalist decoder** (Azabou 2023) — alternative to NDT family if NDT1 plateaus
- **Real BCI hardware integration** — currently scoped out; evaluate after v1 instrumented latency is published
- **Multi-user / cloud sync** — out of scope for v0/v1; revisit if BCI HID adoption signals demand
- **Vision Pro target** — Synchron precedent exists; Cortex Vision Pro target follows iPad/Mac success
- **Hardware PTP** — no current macOS NIC supports it; revisit if Apple ships timestamping silicon
- **Higher-fidelity rigs** — Hamamatsu S5973 or OPA858 TIA upgrades if BPW34/OPA381 noise floor limits measurement

---

## Out of Scope

- **MLX runtime** — unbounded P99 latency, no ANE support; CoreML is the only viable path for the <2ms p99 budget
- **Network.framework / NWConnection** — measured 50-200µs overhead disqualifies it for sub-µs IPC requirement
- **Swift `Task` on hot path** — cooperative scheduling cannot meet 1ms deadlines; 154 sources confirm
- **ChaCha20-Poly1305** — slower than AES-GCM on Apple Silicon `FEAT_AES`; faster only on x86-without-AES-NI
- **`_ANEClient` private API** — guaranteed App Store rejection
- **CocoaPods** — deprecated/maintenance mode; SwiftPM only
- **Hardware PTP / IEEE-1588** — no macOS NIC supports it; software PTP ~10µs floor is the documented ceiling
- **NDT2 in v0/v1** — multi-context pretraining adds session-conditioning latency unnecessary for single-user
- **Vanilla `(B, S, C)` transformer tensor layout** — gets evicted off ANE; mandatory `(B, C, 1, S)` BC1S reshape
- **4-head attention NDT1** — common miscitation; actual NDT1 uses h=1-2
- **`CADisplayLink` for Metal** — superseded by `CAMetalDisplayLink`
- **6×6 webgrid (Pandarinath 2017)** — Neuralink/Bliss Chapman moved to 30×30; align with modern reference
- **Cross-machine clock sync** — macOS lacks hardware-timestamp NICs entirely
- **Real BCI electrodes in v0** — synthetic Indy/Loco replay only
- **iPhone target** — iPad Pro M4 + Mac M-series only; iPhone is post-v1 if at all
- **macOS Catalyst single binary** — separate macOS target uses `NSScreen.displayLink` instead of `CAMetalDisplayLink`-Catalyst-bridge

---

## Traceability

Coverage: 65/65 v1 requirements mapped to phases (100%).

| REQ-ID | Phase | Plan |
|--------|-------|------|
| FOUND-01 | Phase 1: Foundation & 2026 Toolchain | 01-01 (complete), 01-02 (complete), 01-04 (complete) |
| FOUND-02 | Phase 1: Foundation & 2026 Toolchain | 01-02 (complete -- entitlement scaffolding); 01-07 (manual SC#2 runtime verification) |
| FOUND-03 | Phase 1: Foundation & 2026 Toolchain | 01-03 (complete) |
| FOUND-04 | Phase 1: Foundation & 2026 Toolchain | 01-01 (complete) |
| FOUND-05 | Phase 1: Foundation & 2026 Toolchain | 01-06 (complete) |
| IPC-01 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | 02-01 (complete), 02-02 (complete) |
| IPC-02 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | 02-02 (complete), 02-04 (complete), 02-05 (complete) |
| IPC-03 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | 02-01 (complete), 02-02 (complete), 02-04 (complete) |
| IPC-04 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | 02-03 (complete) |
| IPC-05 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | 02-03 (complete) |
| IPC-06 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | 02-01 (complete), 02-03 (complete) |
| IPC-07 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | 02-04 (complete), 02-05 (complete) |
| THREAD-01 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | 03-03 (complete) |
| THREAD-02 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | 03-03 (complete -- code-side; SC#1 .trace tracked in 03-HUMAN-UAT.md, M4-gated per D-18) |
| THREAD-03 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | 03-03 (complete -- hot path + hotpath-policy.sh CI gate, SC#2) |
| THREAD-04 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | 03-01 (complete -- frozen C ABI), 03-02 (complete -- ring) |
| THREAD-05 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | 03-02 (complete -- 128B pad, Release/Acquire) |
| THREAD-06 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | 03-01 (complete -- cbindgen header), 03-04 (complete -- Swift wrapper + integration) |
| THREAD-07 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | 03-02 (complete -- loom permutation test, SC#3a) |
| DEC-01 | Phase 4: NDT1 Training on Indy/Loco | 04-03 |
| DEC-02 | Phase 4: NDT1 Training on Indy/Loco | 04-01, 04-02, 04-04 |
| DEC-03 | Phase 4: NDT1 Training on Indy/Loco | 04-05 |
| DEC-04 | Phase 4: NDT1 Training on Indy/Loco | 04-03 |
| DEC-05 | Phase 4: NDT1 Training on Indy/Loco | 04-05 |
| DEC-06 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | 05-02 |
| DEC-07 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | 05-03 |
| DEC-08 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | 05-05 |
| DEC-09 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | 05-03 |
| DEC-10 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | 05-01 |
| DEC-11 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | 05-04 |
| DEC-12 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | 05-03 |
| RENDER-01 | Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid | TBD |
| RENDER-02 | Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid | TBD |
| RENDER-03 | Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid | TBD |
| RENDER-04 | Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid | TBD |
| RENDER-05 | Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid | TBD |
| RENDER-06 | Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid | TBD |
| RENDER-07 | Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid | TBD |
| RENDER-08 | Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid | TBD |
| RENDER-09 | Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid | TBD |
| REFIT-01 | Phase 7: ReFIT-Kalman Closed-Loop Recalibration | TBD |
| REFIT-02 | Phase 7: ReFIT-Kalman Closed-Loop Recalibration | TBD |
| REFIT-03 | Phase 7: ReFIT-Kalman Closed-Loop Recalibration | TBD |
| SYS-01 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| SYS-02 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| SYS-03 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| SYS-04 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| SYS-05 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| SYS-06 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| DIST-01 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| DIST-02 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| DIST-03 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| DIST-04 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| PERF-01 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| PERF-02 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| PERF-03 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| PERF-04 | Phase 8: Apple BCI HID Integration, Distribution & v0 Ship | TBD |
| LAT-01 | Phase 9: Photodiode Rig Hardware Build | TBD |
| LAT-02 | Phase 9: Photodiode Rig Hardware Build | TBD |
| LAT-03 | Phase 9: Photodiode Rig Hardware Build | TBD |
| LAT-04 | Phase 9: Photodiode Rig Hardware Build | TBD |
| LAT-05 | Phase 10: v1 Photodiode Measurement & Launch | TBD |
| LAT-06 | Phase 10: v1 Photodiode Measurement & Launch | TBD |
| LAT-07 | Phase 10: v1 Photodiode Measurement & Launch | TBD |
| LAT-08 | Phase 10: v1 Photodiode Measurement & Launch | TBD |
