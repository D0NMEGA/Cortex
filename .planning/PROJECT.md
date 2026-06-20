# Cortex.app

## What This Is

Cortex.app is a Neuralink-quality iPad/Mac BCI input pipeline clone — a credibility-grade demonstration that a single engineer can build a sub-25ms glass-to-glass neural cursor decoder on Apple Silicon. The decoder (NDT1, ~1.3M params) runs in <2ms on the M4 Neural Engine via CoreML, drives a 120Hz beam-raced Metal renderer, and integrates with Apple's May 2025 BCI HID protocol so the same artifact works as both a tech demo and a deployable assistive input device.

## Core Value

**Glass-to-glass latency under 25ms, photodiode-instrumented and reproducible.** Every architectural choice serves this — the spec's defining claim is "Glass-to-glass latency 24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)." Without that defensible number, this is a tech demo. With it, it's a credibility artifact suitable for review by Bliss Chapman / Nir Even-Chen.

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

### Active

> Foundation IPC items (`kqueue`+`recvmsg` primitive, FlatBuffers `Sample` schema) → **moved to Validated (Phase 2)**.

> Repo skeleton + App Group container scaffolding → **moved to Validated (Phase 1)**. `CortexDaemon` remains a standalone `type: tool` Phase-2 producer; the App-Store-distributable form (XPC service / launchd helper) is deferred to Phase 7/8 (system integration / distribution).

#### Decoder Pipeline
- [ ] NDT1 implementation (6 layers, h=1-2 heads, 128 hidden dim, 20ms binning, ~1.3M params)
- [ ] Training loop on O'Doherty Indy/Loco synthetic spike replay (Zenodo 3854034)
- [ ] PyTorch → coremltools → `.mlpackage` pipeline with BC1S `(B, C, 1, S)` tensor layout
- [ ] 4-bit palettization via `OpPalettizerConfig(nbits=4)`
- [ ] CoreML deployment with `MLModelConfiguration.computeUnits = .cpuAndNeuralEngine`
- [ ] ANE residency verification via Instruments → CoreML template
- [ ] Decoder inference at <2ms p99 on M4 ANE
- [ ] ReFIT-Kalman closed-loop recalibration filter (6-DOF state, intent-rotation per cursor update)

#### Renderer
- [ ] `CAMetalDisplayLink` integration (iOS 17+, macOS 14+) for beam-raced presentation
- [ ] 30×30 webgrid compute shader (~900 cells) at 120Hz
- [ ] `MTLBuffer storageModeShared` zero-copy unified-memory drawables
- [ ] Frame pacing with `dispatch_semaphore_t(value: 1)` per Apple's "Synchronizing CPU and GPU Work" pattern
- [ ] `Info.plist` `CADisableMinimumFrameDurationOnPhone = YES` for ProMotion 120Hz
- [ ] GPU frame time ≤0.4ms on M4

#### Threading & IPC
- [ ] Acquisition/DSP hot path on pthread with `QOS_CLASS_USER_INTERACTIVE` (no Swift Task)
- [ ] Lock-free SPSC ring buffer (Rust `rtrb` or C++ `rigtorp/SPSCQueue`) with cache-line padding and Acquire/Release ordering
- [ ] `cbindgen` Swift bridge for the Rust SPSC queue
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
- [ ] 10,000-trial photodiode capture script (Saleae at 100+ MS/s)
- [ ] Statistical analysis producing the defensible "24.7 ± 1.3ms (p50, σ=0.8ms, n=10k)" claim
- [ ] Launch video and README documenting methodology

#### Performance Targets
- [ ] Match BrainGate Webgrid 6×6 BPS (4.16 BPS) on synthetic Indy-spike replay
- [ ] Document path toward Neuralink P1 verified peak (8.5 BPS)
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

- **Solo sprint, 6-7 weeks.** v0 (software-only timing) ships end of week 5; v1 (photodiode-instrumented) ships end of week 7.
- **Audience:** Bliss Chapman (ex-Neuralink, currently recruitable per his "last day" tweet) and Nir Even-Chen (Neuralink, Stanford NPTL alum). Cortex.app is the artifact you hand them.
- **Apple May 2025 BCI HID is the integration moat.** It makes BCI a first-class input modality across iOS/iPadOS/visionOS. Synchron is the public reference integration with Vision Pro.
- **Research provenance:** 935-source web research run synthesized into 8 evidence clusters. Per-finding source counts: 119/120/91/139/103/94/154/115. All eight findings independently support each other; no contradictions.
- **OS versioning is current as of 2026.** macOS 26 Tahoe, Xcode 26, Swift 6.2 ("Approachable Concurrency"). Do not regress to "Xcode 17" / "macOS 16" — both wrong.
- **Bliss Chapman's instrumentation philosophy:** "Anyone can write fast-looking code; only people who have actually instrumented glass-to-glass have shipped fast code." This is why the photodiode rig is the highest-leverage credibility artifact in the project.

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
| CoreML on ANE (not MLX) | MLX has unbounded P99 + no ANE; CoreML is the only path meeting <2ms p99 budget | — Pending |
| pthread + `QOS_CLASS_USER_INTERACTIVE` (not Swift Task) | Swift cooperative scheduling cannot meet 1ms deadlines; 154 sources across Massicotte/Adamson/Napier confirm | — Pending |
| `kqueue`+`recvmsg` over POSIX shm (not Network.framework) | Sub-µs vs 50-200µs overhead; disqualifying difference for 1ms deadline | ✓ Validated Phase 2 — shm busy-poll round-trip p99=208ns (CF#2: doorbell is the idle wake, the ring is the measured path) |
| `CAMetalDisplayLink` (not `CADisplayLink`) | Bundles drawable acquisition, encode deadline, on-glass timestamp into one callback for beam-raced 120Hz | — Pending |
| AES-GCM via CryptoKit (not ChaCha20-Poly1305) | Apple Silicon FEAT_AES makes AES-GCM faster; ChaCha is faster only on x86-without-AES-NI | ✓ Validated Phase 2 — HKDF per-direction subkeys + deterministic seq-nonce; fail-closed, nonce-uniqueness tested (off the measured path per D-01) |
| NDT1 not NDT2 | Multi-context pretraining adds session-conditioning latency unnecessary for single-user v0 | — Pending |
| BC1S `(B, C, 1, S)` tensor layout | Only layout the ANE pins; standard `(B, S, C)` evicts to GPU/CPU | — Pending |
| h=1-2 attention heads | Actual NDT1 design; commonly miscited as 4 heads — do not over-parameterize | — Pending |
| 30×30 webgrid (not 6×6) | Lex Fridman / Bliss Chapman reference; Neuralink moved past 6×6 | — Pending |
| Rust `rtrb` or C++ `rigtorp/SPSCQueue` for ring buffer | Rust preferred — `loom` lets you model-check memory ordering, Swift cannot | — Pending |
| App Group container for shared memory | `com.apple.security.temporary-exception.shared-memory` deprecated for App Store | ✓ Validated Phase 1 — cross-process `shm_open` proven, entitlement-honored (sc2-evidence.md) |
| CortexDaemon as standalone `type: tool` (mh_execute) | A loadable `mh_bundle` can't run standalone or carry entitlements; D-03 packaging disposition resolved on Xcode 26 | ✓ Phase 2 — kept as `type: tool`, now the Phase-2 producer (generates key, encrypts, writes ring, passes fd, rings doorbell); App-Store form (XPC/launchd) deferred to Phase 7/8 |
| `mach_msg` + `MACH_MSG_PORT_DESCRIPTOR` for FD passing | Apple-recommended path over Unix-domain `SCM_RIGHTS` | ✓ Validated Phase 2 — `fileport_makeport`/`makefd`, zero SCM_RIGHTS (CI grep-gated); cross-process fd pass proven end-to-end |
| CF#1 → single-process Keychain + key-over-`mach_msg` (Phase 2 spike) | Free/personal team (Y4A54395NZ) cannot back a team-prefixed `keychain-access-groups` entitlement on a bare tool — entitled binary AMFI-SIGKILLed; unentitled → `errSecMissingEntitlement (-34018)` | ✓ Phase 2 spike — fallback wired; cross-process access-group sharing deferred to Phase 8 (paid enrollment) |
| CF#3 → `posix_spawnattr_setspecialport_np` rendezvous (not `bootstrap_register`) | `bootstrap_register` returns `BOOTSTRAP_NOT_PRIVILEGED` for ad-hoc names on modern macOS; special-port injection needs no launchd plist | ✓ Phase 2 spike (3/3) — ADOPT-WITH-RATIONALE vs locked D-08; `TASK_BOOTSTRAP_PORT` + reply-port handshake for fd directionality |
| Defer photodiode rig to weeks 6-7 | v0 with software timing ships first; v1 with photonic ground truth follows | — Pending |
| Indy/Loco (Zenodo 3854034) as training data | Canonical BCI pretraining dataset; only viable synthetic source absent real electrodes | — Pending |
| ReFIT-Kalman recalibration on top of NDT1 | Gilja 2012 — what gets BrainGate from 4.16 → 8.5 BPS in humans | — Pending |

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
*Last updated: 2026-06-20 — Phase 2 (IPC Primitive) complete & verified (7/7 must-haves). IPC-01..07 validated; SC#1 sub-µs round-trip measured (p50=167ns / **p99=208ns** / σ=89.7ns, n=199k on M-series ≥ M4, `sc1-evidence.md`), SC#2 no-SCM_RIGHTS (mach_msg+fileport, CI-gated), SC#3 AES-GCM+Keychain, SC#4 compile-time asserts. Spikes: CF#1 keychain → single-process + key-over-mach_msg (access-group sharing deferred to Phase 8); CF#3 rendezvous → posix_spawnattr_setspecialport_np. Follow-ups: xcodebuild Float16 daemon-target config; `/gsd-secure-phase 02`.*
