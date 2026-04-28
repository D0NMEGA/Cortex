# Cortex.app — v1 Requirements

Source: `cortex-spec.md` (935-source research synthesis, 8 evidence clusters).
All requirements are hypotheses until shipped and validated against the v1 release criteria (defensible photodiode-instrumented latency claim).

---

## v1 Requirements

### Foundation (FOUND)

- [x] **FOUND-01**: Repository scaffolded with Xcode 26 + Swift 6.2, targeting macOS 26 Tahoe and iPadOS 26 — Plan 01-01 (CortexCore mixed Swift+C package + 3 stubs); see [01-01-SUMMARY.md](phases/01-foundation-2026-toolchain/01-01-SUMMARY.md)
- [ ] **FOUND-02**: App Group container configured for shared-memory IPC (replaces deprecated `com.apple.security.temporary-exception.shared-memory` entitlement)
- [ ] **FOUND-03**: Privacy manifest `PrivacyInfo.xcprivacy` includes `CA92.1` reason code for `mach_absolute_time`
- [x] **FOUND-04**: SwiftPM-only dependency graph (no CocoaPods anywhere in the build) — Plan 01-01 (zero Podfile/Pods/ artifacts, four SwiftPM packages well-formed); see [01-01-SUMMARY.md](phases/01-foundation-2026-toolchain/01-01-SUMMARY.md)
- [ ] **FOUND-05**: GitHub Actions CI runs on `macos-15` runner with Xcode 26 toolchain

### IPC Transport (IPC)

- [ ] **IPC-01**: POSIX `shm_open` shared memory inside App Group container with names ≤31 bytes (Darwin `PSHMNAMLEN` limit)
- [ ] **IPC-02**: Raw `kqueue` + `recvmsg` socket pair primitive moves a sample frame between acquisition daemon and app process
- [ ] **IPC-03**: Cross-process file descriptor passing via `mach_msg` with `MACH_MSG_PORT_DESCRIPTOR` (using `fileport_makeport`)
- [ ] **IPC-04**: FlatBuffers `Sample { ts_ns: u64, channel_data: [f16] }` schema serializes/deserializes uniform 0.5ms blocks
- [ ] **IPC-05**: AES-GCM session encryption via CryptoKit `AES.GCM` with HKDF-derived per-session keys
- [ ] **IPC-06**: Session keys stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- [ ] **IPC-07**: Measured round-trip latency sub-µs over local socket pair

### Threading (THREAD)

- [ ] **THREAD-01**: Acquisition/DSP hot path runs on a pthread, never on Swift `Task`
- [ ] **THREAD-02**: Hot-path thread uses `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)`
- [ ] **THREAD-03**: Hot path obeys audio-callback rules — no `dispatch_async`, no Obj-C runtime, no locks, no ARC retain/release
- [ ] **THREAD-04**: Lock-free SPSC ring buffer (Rust `rtrb` or C++ `rigtorp/SPSCQueue`) bridges decoder thread to UI
- [ ] **THREAD-05**: Ring buffer uses cache-line-padded atomics with Acquire/Release memory ordering
- [ ] **THREAD-06**: Rust SPSC bridged to Swift via `cbindgen`-generated header (preferred over C++ for `loom` model-checking)
- [ ] **THREAD-07**: Memory ordering verified with `loom` permutation testing (or equivalent for C++ choice)

### Decoder Pipeline (DEC)

- [ ] **DEC-01**: NDT1 architecture implemented — 6 transformer layers, h=1-2 attention heads, 128 hidden dim, 20ms spike binning, ~1.3M params
- [ ] **DEC-02**: Training pipeline ingests O'Doherty Indy/Loco synthetic spike replay (Zenodo 3854034)
- [ ] **DEC-03**: Trained PyTorch checkpoint converts to `.mlpackage` via coremltools
- [ ] **DEC-04**: Tensor activations reshape to BC1S `(B, C, 1, S)` layout per `apple/ml-ane-transformers`
- [ ] **DEC-05**: 4-bit palettization applied via `coremltools.optimize.palettize_weights` with `OpPalettizerConfig(nbits=4)`
- [ ] **DEC-06**: Every model op validated against ANE op-support matrix (no CPU/GPU fallbacks on inference path)
- [ ] **DEC-07**: `MLModelConfiguration.computeUnits = .cpuAndNeuralEngine` (NOT `.all`)
- [ ] **DEC-08**: ANE residency verified at runtime via Instruments → CoreML template
- [ ] **DEC-09**: Input tensor enters CoreML zero-copy via `MTLBuffer storageModeShared` + `MPSGraphTensorData(mtlBuffer:shape:dataType:)`
- [ ] **DEC-10**: Output is 2-vector cursor velocity (vx, vy) at fp16, emitted every 20ms
- [ ] **DEC-11**: Decoder inference latency <2ms p99 on M4 Neural Engine
- [ ] **DEC-12**: Zero use of `_ANEClient` private API (App Store rejection risk)

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
| FOUND-01 | Phase 1: Foundation & 2026 Toolchain | 01-01 (complete) |
| FOUND-02 | Phase 1: Foundation & 2026 Toolchain | TBD |
| FOUND-03 | Phase 1: Foundation & 2026 Toolchain | TBD |
| FOUND-04 | Phase 1: Foundation & 2026 Toolchain | 01-01 (complete) |
| FOUND-05 | Phase 1: Foundation & 2026 Toolchain | TBD |
| IPC-01 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | TBD |
| IPC-02 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | TBD |
| IPC-03 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | TBD |
| IPC-04 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | TBD |
| IPC-05 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | TBD |
| IPC-06 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | TBD |
| IPC-07 | Phase 2: IPC Primitive (kqueue+recvmsg + FlatBuffers + AES-GCM) | TBD |
| THREAD-01 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | TBD |
| THREAD-02 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | TBD |
| THREAD-03 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | TBD |
| THREAD-04 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | TBD |
| THREAD-05 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | TBD |
| THREAD-06 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | TBD |
| THREAD-07 | Phase 3: Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC) | TBD |
| DEC-01 | Phase 4: NDT1 Training on Indy/Loco | TBD |
| DEC-02 | Phase 4: NDT1 Training on Indy/Loco | TBD |
| DEC-03 | Phase 4: NDT1 Training on Indy/Loco | TBD |
| DEC-04 | Phase 4: NDT1 Training on Indy/Loco | TBD |
| DEC-05 | Phase 4: NDT1 Training on Indy/Loco | TBD |
| DEC-06 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | TBD |
| DEC-07 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | TBD |
| DEC-08 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | TBD |
| DEC-09 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | TBD |
| DEC-10 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | TBD |
| DEC-11 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | TBD |
| DEC-12 | Phase 5: NDT1 → CoreML deployment with ANE residency verified | TBD |
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
