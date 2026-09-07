# Cortex.app

## What This Is

Cortex.app is a Neuralink-quality iPad/Mac BCI input pipeline clone — a credibility-grade demonstration that a single engineer can build a sub-25ms glass-to-glass neural cursor decoder on Apple Silicon. The decoder (NDT1, ~1.3M params) runs in <2ms via CoreML on Apple Silicon (100% ANE-eligible; CPU-scheduled at this ~1.3M-param scale, measured), drives a 120Hz beam-raced Metal renderer, and integrates with Apple's May 2025 BCI HID protocol so the same artifact works as both a tech demo and a deployable assistive input device.

## Core Value

**A real-neural-data decoder running end-to-end under 25ms, reproducibly.** Every architectural choice serves a claim that survives review: NDT1 decoding **real primate M1 spikes** (O'Doherty/Makin Indy, Zenodo 3854034) through a sub-25ms software-timed pipeline on Apple Silicon, with every number labeled by the device and method that produced it.

*Re-pointed 2026-08-28.* The original core value was the photodiode-instrumented "Glass-to-glass latency 24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k)" claim. That claim is **retired to Future work** — it needs a BOM and a provisioned iPad Pro M4 the project does not have, and it was never the largest credibility hole. The larger hole was that Phases 1-8 shipped a decoder that had only ever seen a **synthetic Poisson fallback**. v1 closes that instead. 24.7 ms remains a spec target, never a measurement, and may not be cited as achieved.

## Requirements

### Validated

#### Foundation (Phase 1 — completed 2026-06-19)
- [x] Repo skeleton on Xcode 26 + Swift 6.2 with macOS 26 Tahoe / iPadOS 26 targets — **FOUND-01** (4 SwiftPM packages + 3 XcodeGen targets build under Xcode 26.3 / Swift 6.2)
- [x] App Group container scaffolding for shared-memory IPC (sidesteps deprecated entitlement) — **FOUND-02**: cross-process `shm_open` between CortexMac.app + CortexDaemon proven on Apple Silicon, entitlement-validated (`sc2-evidence.md`); replaces `com.apple.security.temporary-exception.shared-memory`
- [x] `PrivacyInfo.xcprivacy` with required-reason API list (`CA92.1` for `mach_absolute_time`) — **FOUND-03** (validate-privacy-manifest.sh passes; CI-gated)
- [x] Swift Package Manager only (no CocoaPods) — **FOUND-04** (zero Podfile/Pods; clean-clone resolve, 3/3 tests pass)
- [x] CI on `macos-15` GitHub Actions runner — **FOUND-05** (ci.yml with Xcode 26.3 pin + 16 gates; gate armed — first PR exercises it)

#### IPC Primitive (Phase 2 — completed 2026-06-20)
- [x] POSIX shm ring + `kqueue`+`recvmsg` doorbell sample transport — **IPC-01 / IPC-02** (fixed-stride `ShmRing` acquire/release busy-poll + `socketpair`/`kqueue` `EVFILT_READ` doorbell; RingTests/DoorbellTests pass; Transport is Foundation-free, hot-path-gated)
- [x] Cross-process FD passing via `mach_msg` + `MACH_MSG_PORT_DESCRIPTOR` (`fileport_makeport`/`makefd`), zero `SCM_RIGHTS` — **IPC-03 / SC#2** (CI grep-gated over both source trees; CF#3 rendezvous via `posix_spawnattr_setspecialport_np`, proven 3/3)
- [x] FlatBuffers `Sample { ts_ns, channel_data:[ubyte] f16, seq }` codec with zero-copy Float16 rebind + half-pair length invariant — **IPC-04** (flatc 25.12.19 vendored == runtime; SampleCodecTests pass)
- [x] AES-GCM via CryptoKit, HKDF per-direction subkeys, 96-bit deterministic seq-nonce — **IPC-05** (CryptoTests: fail-closed tamper, nonce-uniqueness, cross-direction isolation)
- [x] Session secret in data-protection Keychain (`kCFBooleanTrue` + `AfterFirstUnlockThisDeviceOnly`) — **IPC-06 / SC#3** (CF#1 fallback: single-process round-trip + key delivered over `mach_msg`; cross-process access-group sharing deferred to Phase 8 — free-team signing cannot back the `keychain-access-groups` entitlement)
- [x] Sub-µs encrypted round-trip on the shm-polled path — **IPC-07 / SC#1**: p50=167ns, **p99=208ns**, σ=89.7ns, n=199k on M5 Pro (≥ M4), hardware-gated evidence (`sc1-evidence.md`), ~4.8× margin under 1µs

#### Real-Time Threading (Phase 3 — completed 2026-06-21)
- [x] Acquisition/DSP hot path on a raw `pthread` (never Swift `Task`), `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)` as its first action, Foundation-free (`import Darwin`) — **THREAD-01/02/03** (`CortexRingHotPath/Acquisition.swift`; SC#1 code-side verified, runtime `.trace` M4-gated per D-18 → `03-HUMAN-UAT.md`)
- [x] Hot-path discipline enforced by `hotpath-policy.sh` static-analysis CI gate over Swift/C/Rust sources with a negative-control self-test — **SC#2** (bites on `dispatch_async`/`lazy var`/`pthread_mutex`/`Foundation` + Rust `Mutex`/`.lock(`/`println!(`/`panic!(`)
- [x] In-house loom-verified lock-free SPSC ring — 128B cache-line-padded atomics (Apple Silicon), Release-publish/Acquire-observe, **no SeqCst** — **THREAD-04/05/07** (`cortex_ring` crate; SC#3a loom exhaustive proof + SC#3b 1M-frame strict-FIFO zero-loss, both green on main; D-R3 chose in-house over `rtrb` precisely for `loom` model-checking, rtrb-quality cross-checked ~4%)
- [x] Rust SPSC bridged to Swift via `cbindgen` header + `.xcframework`/`.binaryTarget`, `#[repr(C)] CortexFrame` consumed with no drift-prone Swift mirror, cbindgen-drift CI gate — **THREAD-06 / SC#4** (`CortexRing.Ring` safe RAII wrapper; 1000-frame round-trip verifies value + FIFO order, 7/7 swift tests green)
- D-R8 / Phase-2 D-06 closed: AES-GCM stays off this hot path — the SPSC ring is the decoupling boundary.

#### Decoder Training (Phase 4 — completed 2026-06-21)
- [x] NDT1 (Ye & Pandarinath 2021) in ANE-conducive BC1S form — 6 layers, h=2 (∈{1,2}, NOT the miscited h=4), 128 `d_model`, 20ms bins, **1,292,544 params** (~1.3M); `nn.Conv2d` 1×1 everywhere, zero `nn.Linear` on the inference path — **DEC-01** (param guardrail + structural head-count tests)
- [x] Masked-modeling training loop on O'Doherty Indy/Loco (Zenodo 3854034) — h5py v7.3 loader + 20ms binning → `(num_bins, 96)`, leakage-free chronological-tail split; held-out **co-bps = 0.3804** bits/spike **on a synthetic Poisson fallback** (`04-training-evidence.md`; no real `.mat` was present under `Decoder/data/`, and the objective let the encoder read the positions it was scored on) beats the mean-rate null by ~7.6× the 0.05 margin. **Invalid on both counts and superseded for the real-data claim by co-bps = 0.4096 bits/spike on four real Indy M1 sessions** against the train-split per-channel mean-rate null, margin 0.054 (`09-training-evidence.md`, Phase 9); also closed Phase-2 **D-11** (`CORTEX_CHANNEL_COUNT == 96` reconciled vs `cortex_shm.h`/`cortex_ring.h`/`frame.rs`) — **DEC-02**
- [x] CoreML conversion — traced encoder→rates → `ct.convert(convert_to="mlprogram")` → `.mlpackage` (coremltools 9.0, torch 2.12.1) — **DEC-03**
- [x] BC1S `(B, C, 1, S)` activations on the inference path — 93 rank-4 activations verified by forward-hook; `(B, S, C)` negative-control test raises — **DEC-04**
- [x] 4-bit k-means palettization via `OpPalettizerConfig(mode="kmeans", nbits=4)` — **3.471×** size reduction (2,678,038 → 771,534 B), Poisson-NLL Δ = 0.009114 ≤ 0.5 (`04-palettization-evidence.md`) — **DEC-05**. Both measured on a **randomly-initialized** NDT1. Re-measured on the real checkpoint in Phase 9 (`09-coreml-evidence.md`): the size ratio reproduces (**3.4134x**), the NLL delta does not (**0.020352**), and 4-bit destroys the real velocity decode (held-out R2 +0.423870 fp16 to -1.786971 at 4-bit), so the recommendation on record is **ship fp16**
- Pure decoder R&D in an isolated `Decoder/` uv subsystem (CPython 3.12); NO ANE residency / `computeUnits` / `<2ms` work — that is Phase 5.

### Active

> Foundation IPC items (`kqueue`+`recvmsg` primitive, FlatBuffers `Sample` schema) → **moved to Validated (Phase 2)**.

> Repo skeleton + App Group container scaffolding → **moved to Validated (Phase 1)**. `CortexDaemon` remains a standalone `type: tool` Phase-2 producer; the App-Store-distributable form (XPC service / launchd helper) is deferred to Phase 7/8 (system integration / distribution).

#### Decoder Pipeline
- [x] NDT1 implementation (6 layers, h=1-2 heads, 128 hidden dim, 20ms binning, ~1.3M params) — **validated Phase 4 (DEC-01; 1,292,544 params)**
- [x] Training loop on O'Doherty Indy/Loco synthetic spike replay (Zenodo 3854034) — **validated Phase 4 (DEC-02; held-out co-bps 0.3804, synthetic AND produced by a defective objective; real-data co-bps 0.4096, Phase 9)**
- [x] PyTorch → coremltools → `.mlpackage` pipeline with BC1S `(B, C, 1, S)` tensor layout — **validated Phase 4 (DEC-03/DEC-04)**
- [x] 4-bit palettization via `OpPalettizerConfig(nbits=4)` — **validated Phase 4 (DEC-05; 3.471× size, Δloss 0.009, both on random init; real-data 3.4134x, NLL delta 0.020352, Phase 9)**
- [x] CoreML deployment with `MLModelConfiguration.computeUnits = .cpuAndNeuralEngine` — **validated Phase 5 (DEC-07, build-failing gate)**
- [x] ANE-**eligibility** verified on-device (MLComputePlan + Xcode Performance Report); runtime placement **measured** (CPU at ~1.3M-param scale) — **Phase 5 (DEC-06/08)**; op tally corrected in Phase 9 to **239/239 eligible, 0 CPU-only** on the trained graph (Phase 5's 226 was read off a stale compiled artifact and was never the shipped graph's op count)
- [x] Decoder inference <2ms p99 — **≈0.5ms (iPad-M2) / 0.14ms (M5 Pro), Phase 5 (DEC-11)**; re-measured on the real weights, **p99 0.141083ms on Apple M5 Pro, ops measured CPU-placed, corroborating not canonical** (Phase 9)
- [x] ReFIT-Kalman closed-loop recalibration filter (6-DOF state, intent-rotation per cursor update) — **validated Phase 7 (REFIT-01/02/03)**: steady-state constant-gain 6-DOF Kalman (observable-block DARE, zero position rows, Schur-stable) + gated Gilja-2012 intent-rotation in `Packages/CortexReFIT`, Foundation-free simd on the policed hot path; 3-way ablation on synthetic data refit_bps 0.374 ≥ raw 0.161 (+133% S&M-2004 Fitts-TP, deterministic CI guard). NOT compared to 4.16/8.5 Webgrid bitrate (Phase 8, D-13)

#### Renderer
- [x] `CAMetalDisplayLink` (iOS) + `NSScreen.displayLink` (macOS) integration for beam-raced presentation — **validated Phase 6 (RENDER-01/08)**
- [x] 30×30 webgrid compute shader (~900 cells) at 120Hz — **validated Phase 6 (RENDER-04; 120Hz RENDER-02, M5 Pro ProMotion corroborating)**
- [x] `MTLBuffer storageModeShared` zero-copy unified-memory drawables — **validated Phase 6 (RENDER-06)**
- [x] Frame pacing with `dispatch_semaphore_t(value: 1)` per Apple's "Synchronizing CPU and GPU Work" pattern — **validated Phase 6 (RENDER-07)**
- [x] `Info.plist` `CADisableMinimumFrameDurationOnPhone = YES` for ProMotion 120Hz — **validated Phase 6 (RENDER-03)**
- [x] GPU frame time ≤0.4ms — **validated Phase 6 (RENDER-05; M5 Pro p99=0.162ms ~2.5× margin corroborating, iPad-M4 canonical deferred D-11/D-12)**

#### Threading & IPC
- [x] Acquisition/DSP hot path on pthread with `QOS_CLASS_USER_INTERACTIVE` (no Swift Task) — **validated Phase 3 (THREAD-01/02/03)**
- [x] Lock-free SPSC ring buffer (in-house loom-verified Rust SPSC — D-R3) with 128B cache-line padding and Release/Acquire ordering — **validated Phase 3 (THREAD-04/05/07)**
- [x] `cbindgen` Swift bridge for the Rust SPSC queue — **validated Phase 3 (THREAD-06)**
- [x] POSIX `shm_open` shared memory inside App Group container (≤31-byte names per Darwin `PSHMNAMLEN`) — **validated Phase 2 (IPC-01)**
- [x] `mach_msg` + `MACH_MSG_PORT_DESCRIPTOR` (via `fileport_makeport`) for cross-process FD passing — **validated Phase 2 (IPC-03, no SCM_RIGHTS)**
- [x] AES-GCM session encryption via CryptoKit `AES.GCM` (HKDF-derived key, Keychain-stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) — **validated Phase 2 (IPC-05/06)**

#### System Integration
- [ ] Apple BCI HID protocol integration as first-class input modality
- [ ] Switch Control + Accessibility framework HID provider registration
- [ ] Bidirectional context-sharing: app sends UI state, Cortex returns intent, app applies refinement
- [ ] Mirror Synchron's Vision Pro entitlement and `Info.plist` surface

#### Distribution
- [ ] `notarytool submit` + `xcrun stapler staple` workflow
- [ ] TestFlight distribution (100 internal / 10,000 external testers)
- [ ] `fastlane match` + App Store Connect API key (`.p8` JWT) for signing

> `PrivacyInfo.xcprivacy` (CA92.1) + SwiftPM-only + CI on macos-15 → **moved to Validated (Phase 1)**.

#### Latency Measurement (v1, weeks 6-7)
- [ ] Photodiode rig BOM ordered (BPW34 + OPA381 TIA + Saleae Logic Pro 8)
- [ ] Breadboard assembly with transimpedance amp
- [ ] GPIO pulse from acquisition daemon at intent-emission timestamp
- [ ] ~~10,000-trial photodiode capture script (Saleae at 100+ MS/s)~~ RETIRED to Future work 2026-08-28
- [ ] ~~Statistical analysis producing the defensible "24.7 ± 1.3ms (p50, σ=0.8ms, n=10k)" claim~~ RETIRED to Future work 2026-08-28
- [x] Four Indy M1 sessions materialized + SHA-256-pinned; NDT1 retrained on real spikes (RD-01..RD-06) -- **validated Phase 9**, 285,359 bins of real O'Doherty/Makin Indy M1 spikes (Zenodo 3854034), all numbers CPU-only on the dev Mac except where labeled:
  - Pooled held-out **co-bps 0.4096** vs the train-split per-channel mean-rate null (0.3814 vs the pooled test-mean null), `CO_BPS_MARGIN` 0.054 (`09-training-evidence.md`)
  - **Within session it decodes, across sessions it does not.** All four sessions positive against their own held-out mean (+0.2127, +0.1661, +0.2062, +0.2455); all four leave-one-session-out folds **negative** (-0.1238, -0.3060, -0.7805, -0.1890, mean -0.3498). The encoder does not transfer to an unseen session
  - Pooled held-out **velocity R2 0.4238** (vx 0.3430, vy 0.5338) over 56,943 bins of real `finger_pos` kinematics; the readout rotation leaves only 2 of 4 folds positive (median -0.4270) and bounds transfer from **above**, since the encoder saw all four sessions in every fold (`09-velocity-evidence.md`)
  - CoreML on the real checkpoints: **239/239 ANE-eligible, 0 CPU-only**; 4-bit destroys the decode (R2 -1.786971 per-tensor, best 4-bit +0.191784 at 2.6262x), so **ship fp16**; decoder **p99 0.141083ms on Apple M5 Pro**, ops measured CPU-placed, corroborating (`09-coreml-evidence.md`). The canonical iPad-Pro-M4 capture is deferred, never auto-approved (`09-HUMAN-UAT.md`)
- [ ] ReFIT re-fit + closed loop replayed on a real session; synthetic-number sweep + gate rewrite (RD-07..RD-10)
- [ ] Launch video and README documenting methodology

#### Performance Targets
- [ ] Match BrainGate Webgrid 6×6 BPS (4.16 BPS) on synthetic Indy-spike replay
- [ ] Document path toward Neuralink P1 cited reference (8.5 BPS, as cited since Phase 7; not independently sourceable)
- [ ] Frame-pacing diagnostics via `MTL_HUD_ENABLED=1` showing P95 frame time, drawable-wait, encoder-time

### Out of Scope

- **Real BCI hardware integration** — v0 uses synthetic Indy/Loco spike replay; real electrodes are out of scope for this sprint
- **MLX runtime** — unbounded P99 latency and no ANE support; use CoreML only
- **Network.framework / NWConnection** — 50-200µs overhead disqualifying for 1ms deadline; use raw `kqueue`+`recvmsg`
- **Swift `Task` on hot path** — unbounded scheduling latency; use pthread + USER_INTERACTIVE QoS
- **ChaCha20-Poly1305** — slower than AES-GCM on Apple Silicon (FEAT_AES); use CryptoKit AES.GCM
- **`_ANEClient` private API** — guaranteed App Store rejection; rely solely on `MLModelConfiguration.computeUnits`
- **CocoaPods** — deprecated/maintenance mode; SwiftPM only
- **Hardware PTP / IEEE-1588** — no macOS NIC supports it; document the software-PTP ~10µs floor instead
- **NDT2** — multi-context pretraining adds session-conditioning latency unnecessary for single-user v0
- **Vanilla `(B, S, C)` transformer tensor layout** — gets evicted off ANE; reshape to `(B, C, 1, S)` per `ml-ane-transformers`
- **4-head attention (commonly miscited NDT1)** — actual NDT1 uses h=1-2; do not over-parameterize
- **`CADisplayLink` for Metal** — superseded by `CAMetalDisplayLink`; do not regress
- **Multi-user / cloud sync** — single-user, on-device only for v0
- **6×6 webgrid (Pandarinath 2017)** — Neuralink/Bliss Chapman moved to 30×30; match modern standard

## Context

- **Solo sprint.** v0 (software-only timing) shipped 2026-06-23. v1 re-pointed 2026-08-28 to real-neural-data decoding (Phases 9-10); the photodiode path is Future work, not scheduled.
- **Audience:** Bliss Chapman (ex-Neuralink, currently recruitable per his "last day" tweet) and Nir Even-Chen (Neuralink, Stanford NPTL alum). Cortex.app is the artifact you hand them.
- **Apple May 2025 BCI HID is the integration moat.** It makes BCI a first-class input modality across iOS/iPadOS/visionOS. Synchron is the public reference integration with Vision Pro.
- **Research provenance:** 935-source web research run synthesized into 8 evidence clusters. Per-finding source counts: 119/120/91/139/103/94/154/115. All eight findings independently support each other; no contradictions.
- **OS versioning is current as of 2026.** macOS 26 Tahoe, Xcode 26, Swift 6.2 ("Approachable Concurrency"). Do not regress to "Xcode 17" / "macOS 16" — both wrong.
- **Bliss Chapman's instrumentation philosophy:** "Anyone can write fast-looking code; only people who have actually instrumented glass-to-glass have shipped fast code." The photodiode rig was the intended answer; without the hardware, the honest answer is to keep the software-timed number **labeled as software-timed** (it excludes compositor scanout) and to spend the credibility budget where it can actually be earned — on real neural data.

## Constraints

- **Tech stack**: Apple Silicon (M4) only — `FEAT_AES`, ANE, `CAMetalDisplayLink`, ProMotion all required. No x86 fallback.
- **Tech stack**: Xcode 26 + Swift 6.2 + macOS 26 Tahoe / iPadOS 26 — all 2026 baseline; older toolchains lack required APIs.
- **Performance**: Decoder inference <2ms p99 — non-negotiable for sub-25ms glass-to-glass.
- **Performance**: Renderer GPU time ≤0.4ms on M4 — leaves headroom for compositor.
- **Performance**: IPC round-trip sub-µs — disqualifies Network.framework (50-200µs).
- **Threading**: Hot path is audio-callback regime — no `dispatch_async`, no Obj-C runtime, no locks, no ARC retain/release. Pthread + USER_INTERACTIVE only.
- **Distribution**: Must ship through App Store path (no `_ANEClient`, no deprecated entitlements). Privacy manifest required. Notarized.
- **Timeline**: 6-7 week sprint; v0 by week 5, v1 by week 7.
- **Compatibility**: Single-user, on-device. No cloud, no multi-user, no real BCI hardware.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| CoreML on ANE (not MLX) | MLX has unbounded P99 + no ANE; CoreML is the only path meeting <2ms p99 budget | ✓ Validated Phase 5 — 226/226 ANE-**eligible** (MLComputePlan + iPad Perf Report); **<2ms p99 met** (≈0.5ms iPad-M2 / 0.14ms M5 Pro). Runtime placement measured **CPU** at 1.29M-param scale (the CoreML scale trap, reported honestly — DEC-06/08/11); M4-ANE placement an optional future datapoint. **Op tally superseded in Phase 9 by 239/239 eligible, 0 CPU-only.** Phase 5's 226 was read through a `compile_model` defect: `shutil.move` nested each fresh `.mlmodelc` inside the existing destination and returned the unchanged path, so every scan since 2026-06-21 read a stale compiled artifact. Isolating each compile under `tmp_path` fixed it; the trained graph carries 12 `batch_norm` ops and one extra `add` that a zero-initialized `pos_encoding` folds away when untrained. The eligibility verdict survives the correction (`09-coreml-evidence.md`) |
| pthread + `QOS_CLASS_USER_INTERACTIVE` (not Swift Task) | Swift cooperative scheduling cannot meet 1ms deadlines; 154 sources across Massicotte/Adamson/Napier confirm | ✓ Validated Phase 3 — `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE,0)` is the worker's first action, `import Darwin` only; SC#2 `hotpath-policy.sh` gate enforces it in CI (SC#1 `.trace` M4-gated, `03-HUMAN-UAT.md`) |
| `kqueue`+`recvmsg` over POSIX shm (not Network.framework) | Sub-µs vs 50-200µs overhead; disqualifying difference for 1ms deadline | ✓ Validated Phase 2 — shm busy-poll round-trip p99=208ns (CF#2: doorbell is the idle wake, the ring is the measured path) |
| `CAMetalDisplayLink` (not `CADisplayLink`) | Bundles drawable acquisition, encode deadline, on-glass timestamp into one callback for beam-raced 120Hz | — Pending |
| AES-GCM via CryptoKit (not ChaCha20-Poly1305) | Apple Silicon FEAT_AES makes AES-GCM faster; ChaCha is faster only on x86-without-AES-NI | ✓ Validated Phase 2 — HKDF per-direction subkeys + deterministic seq-nonce; fail-closed, nonce-uniqueness tested (off the measured path per D-01) |
| NDT1 not NDT2 | Multi-context pretraining adds session-conditioning latency unnecessary for single-user v0 | ✓ Validated Phase 4 — NDT1 (Ye & Pandarinath 2021) implemented & trained, 1,292,544 params |
| BC1S `(B, C, 1, S)` tensor layout | Only layout the ANE pins; standard `(B, S, C)` evicts to GPU/CPU | ✓ Validated Phase 4 (DEC-04) — `nn.Conv2d` 1×1 everywhere, 93 rank-4 activations forward-hook-verified, `(B,S,C)` negative control raises |
| h=1-2 attention heads | Actual NDT1 design; commonly miscited as 4 heads — do not over-parameterize | ✓ Validated Phase 4 (DEC-01) — all attention modules h=2 (∈{1,2}); structural head-count test + [1.0M,1.6M] param guardrail block any h=4 drift |
| 30×30 webgrid (not 6×6) | Lex Fridman / Bliss Chapman reference; Neuralink moved past 6×6 | — Pending |
| In-house loom-verified Rust SPSC (not `rtrb` directly) for ring buffer | Rust preferred — `loom` lets you model-check memory ordering, Swift cannot; D-R3 chose in-house so the exact production atomics route through a `loom` cfg-shim | ✓ Validated Phase 3 — 128B-padded, Release/Acquire (no SeqCst); SC#3a loom exhaustive proof + SC#3b 1M strict-FIFO zero-loss green; rtrb-quality cross-checked (~4%) |
| App Group container for shared memory | `com.apple.security.temporary-exception.shared-memory` deprecated for App Store | ✓ Validated Phase 1 — cross-process `shm_open` proven, entitlement-honored (sc2-evidence.md) |
| CortexDaemon as standalone `type: tool` (mh_execute) | A loadable `mh_bundle` can't run standalone or carry entitlements; D-03 packaging disposition resolved on Xcode 26 | ✓ Phase 2 — kept as `type: tool`, now the Phase-2 producer (generates key, encrypts, writes ring, passes fd, rings doorbell); App-Store form (XPC/launchd) deferred to Phase 7/8 |
| `mach_msg` + `MACH_MSG_PORT_DESCRIPTOR` for FD passing | Apple-recommended path over Unix-domain `SCM_RIGHTS` | ✓ Validated Phase 2 — `fileport_makeport`/`makefd`, zero SCM_RIGHTS (CI grep-gated); cross-process fd pass proven end-to-end |
| CF#1 → single-process Keychain + key-over-`mach_msg` (Phase 2 spike) | Free/personal team (Y4A54395NZ) cannot back a team-prefixed `keychain-access-groups` entitlement on a bare tool — entitled binary AMFI-SIGKILLed; unentitled → `errSecMissingEntitlement (-34018)` | ✓ Phase 2 spike — fallback wired; cross-process access-group sharing deferred to Phase 8 (paid enrollment) |
| CF#3 → `posix_spawnattr_setspecialport_np` rendezvous (not `bootstrap_register`) | `bootstrap_register` returns `BOOTSTRAP_NOT_PRIVILEGED` for ad-hoc names on modern macOS; special-port injection needs no launchd plist | ✓ Phase 2 spike (3/3) — ADOPT-WITH-RATIONALE vs locked D-08; `TASK_BOOTSTRAP_PORT` + reply-port handshake for fd directionality |
| Defer photodiode rig to weeks 6-7 | v0 with software timing ships first; v1 with photonic ground truth follows | — Superseded 2026-08-28 |
| Retire the photodiode rig; re-point v1 at real-data decoding | Hardware-gated (BOM + provisioned iPad Pro M4, the same gap behind 3 deferred Phase-8 gates). The decoder had only ever seen synthetic Poisson data, so real data is the higher-value claim per unit of risk. LAT-01..08 preserved in ROADMAP "Future work"; 24.7 ms stays a target, never a result | — Accepted (user, 2026-08-28) |
| Indy/Loco (Zenodo 3854034) as training data | Canonical BCI pretraining dataset; only viable synthetic source absent real electrodes | ✓ Validated Phase 4 (DEC-02) — h5py v7.3 loader + 20ms binning → (num_bins,96), chronological split, reproducible session manifest + checksummed downloader |
| ReFIT-Kalman recalibration on top of NDT1 | Gilja 2012 (Nature Neuroscience) — online intent re-estimation within the same BrainGate system. The 4.16 and 8.5 figures come from different systems; the gap between them is not attributable to ReFIT | ✓ Validated Phase 7 (REFIT-01/02/03; +133% S&M Fitts-TP ablation uplift, ReFIT-inspired online assist on synthetic replay) |
| Retrain NDT1 on four real Indy M1 sessions (the Option B set) | Two of the four originally-manifested sessions were 192-channel M1+S1 and were correctly rejected by the loader's 96-channel gate; slicing an M1 subset out of them would have mixed array configurations into a pool whose premise is stable channel-to-neuron identity. The chosen set spans 2016-06-24 to 2016-09-15 and exercises both `finger_pos` row layouts, `(6, k)` on three sessions and `(3, k)` on `indy_20160915_01` | ✓ Validated Phase 9 (RD-01..RD-06): 1.77 GB, four SHA-256-pinned sessions, 285,359 bins (`09-ingest-evidence.md`) |
| D-14: lock session `indy_20160630_01` as the closed-loop v1 session; pin velocity checkpoint sha256 `9d542cb51d4a...`; label all numbers "open-loop replay of a recorded session; the subject was not in the loop" | The weakest of the four sessions by held-out velocity R2 (0.1446 vs 0.4238 pooled); using the worst case is the honest choice | ✓ Phase 10 -- real-data closed loop ran end to end; `raw`/`kalman_only` arms: **0 hits of 1,025, 0.000000 BPS** (decode-attributable); `refit` arm: 70 hits / 0.487984 BPS (target-determined by construction -- `IntentRotation` uses the known target direction, not the decoded direction); `refit_reversed_target`: 2 hits / 0.013635 BPS. Seam A p99 8831017 ns (debug, M5 Pro, median of 5 runs). Seam B p50 136167 ns (in_process only -- MACH_SEND_INVALID_DEST). Reference: [10-refit-real-evidence.md](phases/10-v1-real-data-closed-loop-launch/10-refit-real-evidence.md), [10-replay-evidence.md](phases/10-v1-real-data-closed-loop-launch/10-replay-evidence.md) |
| D-17: keep the 8.5 BPS Neuralink figure dated 2026-09-07 | Neuralink.com/webgrid stated "over 10 BPS" as of 2026-09-07 retrieval; 8.5 is not independently sourceable to a primary Neuralink publication but was the user-accepted reference; an access date does not authenticate a number | ✓ Phase 10 -- 8.5 retained with date label; "over 10 BPS" noted as the current public statement |
| SC#2 not_met (D-18): real-data decode does not meet the BPS success criterion on attributable arms | `raw` and `kalman_only` score 0 of 1,025 trials; `sc2_disposition: "not_met"`, `sc2_rule: "B"` in `10-replay.json` (user decision, Plan 10-10 Task 3b) | ✓ Disposition committed; the project is honest about the gap |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-23 — Phase 8 (Apple BCI HID Integration, Distribution & v0 Ship) COMPLETE — the v0 milestone. New `Packages/CortexBCIHID` (5 Apple BCI HID report structs + verbatim report descriptor + 22 button actions + `#if CORTEX_HID_LIVE`-gated `VirtualDeviceGate` + declared-but-inert `virtual.device` entitlement ×3 targets) + the SYS-03/04 Scan-Info closed-loop round trip; new `Packages/CortexDemo` (synthetic-spike → NDT1(CoreML) → ReFIT-Kalman → 30×30 webgrid closed loop, decoder genuinely in loop) + software-timed glass-to-glass bench (`targetPresentationTimestamp`; p99 ≈ 8.32ms M5-corroborating — NOT the canonical iPad-M4 photodiode claim); real `notarytool`+`match(appstore)`+TestFlight distribution lanes (live submit gated); Webgrid BPS metric (ReFIT 1.953 BPS, honest 6.55 gap-to-8.5, as cited since Phase 7; not independently sourceable); credibility README + ADR-0002. 5 structural `*-policy.sh` CI gates + 59 Swift tests green (08-VERIFICATION 5/5 automated must-haves; all 14 req IDs traced). The 3 never-auto-approve HUMAN-UAT gates — live TestFlight (DIST-01/02/03), iPad-M4 canonical latency (PERF-04), on-device HID registration (SYS-01/02) — DEFERRED 2026-06-23 (prerequisites unavailable: paid enrollment / provisioned iPad Pro M4 / managed entitlement); none fabricated; tracked in `08-HUMAN-UAT.md`. v0 runnable today on the free Personal team. Deferred follow-ons: `project.yml` SYS-05 Info.plist hoist, repo-wide SwiftLint/SwiftFormat version pin (CI lint gate never triggered — all work direct-to-`main`), `/gsd-secure-phase 08`. Prior: Phase 7 (ReFIT-Kalman Closed-Loop Recalibration) complete, all gates green (REFIT-01/02/03, 6/6 must-haves on `main`). New `Packages/CortexReFIT`: observable-block steady-state Kalman gain fit offline in `Decoder/` (scipy DARE on the 4-DOF [v,a] block — the full 6×6 is unobservable from a velocity-only measurement — zero position rows, Schur-stable max|λ|≈0.93) → committed Foundation-free `KalmanConstants.swift` (D-15 code-gen); 6-DOF steady-state constant-gain `KalmanFilter` step (predict→external-position-sync→rotate-measurement→update→emit, constants-only, no runtime Riccati) + gated speed-preserving Gilja-2012 `IntentRotation`, both pure simd under `hotpath-policy.sh` (SC#3). Headless deterministic 3-way ablation (`CortexReFITBench`): raw 0.161 / Kalman-only 0.155 / ReFIT 0.374 S&M-2004 effective-width Fitts throughput (+133%, acq 61→100/120), byte-identical across runs, deterministic CI uplift guard (`refit_bps ≥ raw_bps`). Credibility framing locked: S&M-2004 Fitts-TP is NOT the Webgrid bitrate — explicitly NOT compared to 4.16/8.5 (Phase 8 SC#5, D-13); ReFIT-inspired online assist on synthetic replay, not a live-human two-stage retrain; real-Indy `.mat` replay loader a documented follow-on (synthetic-replay evidence, mirrors Phase-4). SC#3 filter step ~292ns p99 over 10k inline ticks (Mac M5-Pro corroborating; iPad-M4 canonical Manual-Only/deferred). Prior: Phase 6 (CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid) complete, all gates green (9/9 RENDER reqs on `main`). Beam-raced renderer in `Packages/CortexRender`: `WebgridFrameEncoder` compute shader (30×30 filled rounded cells, dark Neuralink theme, bright disc cursor, proximity-brighten, pixel-bounds guard), iOS `CAMetalDisplayLink` + macOS `NSScreen.displayLink` adapters over a `value:1` semaphore, fp16 `(vx,vy)` velocity seam + renderer-owned integrator + deterministic Lissajous drive, `render-policy.sh` CI gate (9 required + 3 forbidden tokens, negative-control self-test). Measured on M5 Pro ProMotion (corroborating-canonical, D-11): GPU p99=0.162ms (~2.5× under ≤0.4ms, n=10k) + 60s soak 243,724 frames / 0 intervals >8.33ms; SC#2/SC#4 + RENDER-02/05 reframed M5-Pro-measured (user-approved) with iPad-Pro-M4 canonical capture deferred (`06-HUMAN-UAT.md`, never-auto-approve, D-12). Prior: Phase 5 (NDT1→CoreML, 100% ANE-eligible 226/226 ops, <2ms p99 ≈0.5ms iPad-M2 / 0.14ms M5 Pro, runtime placement measured-CPU honest reframe — DEC-06..12). Next: Phase 9 — photodiode-rig-hardware-build (the v1 canonical-claim path). Note: PROJECT.md ### Validated still lacks per-phase subsections for Phases 5-8 (their Active items are checked in place) — a follow-up doc cleanup.*
