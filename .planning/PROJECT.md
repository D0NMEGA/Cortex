# Cortex.app

## What This Is

Cortex.app is a Neuralink-quality iPad/Mac BCI input pipeline clone — a credibility-grade demonstration that a single engineer can build a sub-25ms glass-to-glass neural cursor decoder on Apple Silicon. The decoder (NDT1, ~1.3M params) runs in <2ms on the M4 Neural Engine via CoreML, drives a 120Hz beam-raced Metal renderer, and integrates with Apple's May 2025 BCI HID protocol so the same artifact works as both a tech demo and a deployable assistive input device.

## Core Value

**Glass-to-glass latency under 25ms, photodiode-instrumented and reproducible.** Every architectural choice serves this — the spec's defining claim is "Glass-to-glass latency 24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)." Without that defensible number, this is a tech demo. With it, it's a credibility artifact suitable for review by Bliss Chapman / Nir Even-Chen.

## Requirements

### Validated

(None yet — ship to validate)

### Active

#### Foundation
- [ ] Repo skeleton on Xcode 26 + Swift 6.2 with macOS 26 Tahoe / iPadOS 26 targets
- [ ] App Group container scaffolding for shared memory IPC (sidesteps deprecated entitlement)
- [ ] `kqueue`+`recvmsg` IPC primitive demonstrating sample-to-app transport
- [ ] FlatBuffers wire format with `Sample { ts_ns: u64, channel_data: [f16] }` schema

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
- [ ] POSIX `shm_open` shared memory inside App Group container (≤31-byte names per Darwin `PSHMNAMLEN`)
- [ ] `mach_msg` + `MACH_MSG_PORT_DESCRIPTOR` (via `fileport_makeport`) for cross-process FD passing
- [ ] AES-GCM session encryption via CryptoKit `AES.GCM` (HKDF-derived key, Keychain-stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)

#### System Integration
- [ ] Apple BCI HID protocol integration as first-class input modality
- [ ] Switch Control + Accessibility framework HID provider registration
- [ ] Bidirectional context-sharing: app sends UI state, Cortex returns intent, app applies refinement
- [ ] Mirror Synchron's Vision Pro entitlement and `Info.plist` surface

#### Distribution
- [ ] `notarytool submit` + `xcrun stapler staple` workflow
- [ ] `PrivacyInfo.xcprivacy` with required-reason API list (`CA92.1` for `mach_absolute_time`)
- [ ] TestFlight distribution (100 internal / 10,000 external testers)
- [ ] `fastlane match` + App Store Connect API key (`.p8` JWT) for signing
- [ ] Swift Package Manager only (no CocoaPods)
- [ ] CI on `macos-15` GitHub Actions runner

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
| `kqueue`+`recvmsg` over POSIX shm (not Network.framework) | Sub-µs vs 50-200µs overhead; disqualifying difference for 1ms deadline | — Pending |
| `CAMetalDisplayLink` (not `CADisplayLink`) | Bundles drawable acquisition, encode deadline, on-glass timestamp into one callback for beam-raced 120Hz | — Pending |
| AES-GCM via CryptoKit (not ChaCha20-Poly1305) | Apple Silicon FEAT_AES makes AES-GCM faster; ChaCha is faster only on x86-without-AES-NI | — Pending |
| NDT1 not NDT2 | Multi-context pretraining adds session-conditioning latency unnecessary for single-user v0 | — Pending |
| BC1S `(B, C, 1, S)` tensor layout | Only layout the ANE pins; standard `(B, S, C)` evicts to GPU/CPU | — Pending |
| h=1-2 attention heads | Actual NDT1 design; commonly miscited as 4 heads — do not over-parameterize | — Pending |
| 30×30 webgrid (not 6×6) | Lex Fridman / Bliss Chapman reference; Neuralink moved past 6×6 | — Pending |
| Rust `rtrb` or C++ `rigtorp/SPSCQueue` for ring buffer | Rust preferred — `loom` lets you model-check memory ordering, Swift cannot | — Pending |
| App Group container for shared memory | `com.apple.security.temporary-exception.shared-memory` deprecated for App Store | — Pending |
| `mach_msg` + `MACH_MSG_PORT_DESCRIPTOR` for FD passing | Apple-recommended path over Unix-domain `SCM_RIGHTS` | — Pending |
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
*Last updated: 2026-04-28 after initialization*
