# Cortex.app

Neuralink-quality iPad / Mac BCI input pipeline clone. A sub-25ms glass-to-glass neural
cursor decoder on Apple Silicon: an NDT1 ~1.3M-param decoder runs in under 2ms via CoreML
(100% ANE-eligible), drives a 120Hz beam-raced Metal renderer, and registers against
Apple's May 2025 BCI HID protocol so the same artifact is both a tech demo and a
deployable assistive input device.

> **Status:** v0 milestone (Phase 8 / 10). The full closed loop runs today; the live
> distribution submission, the iPad-Pro-M4 canonical latency capture, and the v1
> photodiode-instrumented claim are honestly gated (see [Honest gates](#honest-gates)).
> Current position: `.planning/STATE.md`. Roadmap: `.planning/ROADMAP.md`.

## Core value

**Glass-to-glass latency under 25ms, photodiode-instrumented and reproducible.** Every
architectural choice serves that single number. The defining v1 claim is "Glass-to-glass
latency 24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)". Without a defensible
number this is a tech demo; with one it is a credibility artifact suitable for review by
Bliss Chapman / Nir Even-Chen.

The project's thesis is **instrumentation honesty** — Bliss Chapman's "anyone can write
fast-looking code; only people who have actually instrumented glass-to-glass have shipped
fast code". Over-claiming would undermine the whole thesis, so **every number on this page
is stated with its device and its gate**: software-timed (not photodiode), synthetic-replay
(not live-human), ANE-eligible (CPU-scheduled at this scale), free-team-signed (not
notarized-live), HID-surface-registered (the BCI-HID entitlement is request-gated).

## Architectural commitments

The five load-bearing commitments, each with its rationale and its **validated** outcome
(the measured number, the phase, and the evidence artifact). These are enforced as CI
structural gates so a future commit cannot silently regress them.

| # | Commitment | Why (rejected alternative) | Validated outcome |
|---|------------|----------------------------|-------------------|
| 1 | **CoreML on the ANE** | `MLX` has unbounded P99 and no ANE residency — disqualifying for a <2ms p99 budget | ✓ Phase 5 — **226/226 ops ANE-eligible** (MLComputePlan + Xcode Performance Report); **<2ms p99 met** (≈0.5ms iPad-M2 / 0.14ms M5 Pro). Runtime placement **measured CPU** at the 1.29M-param scale — the CoreML scale trap, reported honestly (DEC-06/08/11). |
| 2 | **pthread + `QOS_CLASS_USER_INTERACTIVE`** on the hot path | Swift `Task` cooperative scheduling cannot meet 1ms deadlines | ✓ Phase 3 — `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)` is the worker's first action, `import Darwin` only; the `hotpath-policy.sh` CI gate enforces it (THREAD-01/02/03). |
| 3 | **`kqueue`+`recvmsg` over POSIX shm** | `Network.framework` adds 50-200µs — disqualifying for a sub-µs round trip | ✓ Phase 2 — shm busy-poll round trip **p99 = 208ns**, σ=89.7ns, n=199k on M5 Pro (≥ M4); ~4.8× margin under 1µs (IPC-07, `sc1-evidence.md`). |
| 4 | **`CAMetalDisplayLink` 120Hz zero-copy** | `CADisplayLink` for Metal is superseded; it cannot bundle drawable/encode/present for beam racing | ✓ Phase 6 — **GPU p99 = 0.162ms** (~2.5× under the ≤0.4ms budget), 60s soak / 243,724 frames / 0 dropped on M5 Pro ProMotion; `storageModeShared` unified-memory drawables (RENDER-01/05/06). iPad-M4 canonical capture deferred (HUMAN-UAT). |
| 5 | **AES-GCM via CryptoKit** | `ChaCha20-Poly1305` is slower than AES-GCM on Apple Silicon `FEAT_AES` | ✓ Phase 2 — HKDF per-direction subkeys, deterministic 96-bit seq-nonce, fail-closed tamper + nonce-uniqueness tested, kept off the measured hot path (IPC-05). |

## Rejected alternatives

Decisions that reject an obvious-seeming option for a non-obvious reason. Each is enforced
somewhere in CI (a grep gate, a structural test, or a param guardrail) so the project cannot
regress into it.

| Rejected | Why | Chosen instead |
|----------|-----|----------------|
| **MLX** | unbounded P99 latency, no ANE residency | CoreML (`MLModelConfiguration.computeUnits`) |
| **Network.framework / NWConnection** | 50-200µs overhead | raw `kqueue`+`recvmsg` over POSIX shm |
| **Swift `Task` on the hot path** | unbounded scheduling latency | pthread + `QOS_CLASS_USER_INTERACTIVE` |
| **ChaCha20-Poly1305** | slower than AES-GCM on `FEAT_AES` | CryptoKit `AES.GCM` |
| **`_ANEClient` private API** | guaranteed App Store rejection | public `MLModelConfiguration` + `MLComputePlan` |
| **CocoaPods** | deprecated / maintenance mode | SwiftPM only |
| **hardware PTP / IEEE-1588** | no macOS NIC supports it | document the software-PTP ~10µs floor |
| **NDT2** | session-conditioning latency for a single-user v0 | NDT1 (Ye & Pandarinath 2021) |
| **`(B, S, C)` transformer layout** | gets evicted off the ANE | `(B, C, 1, S)` BC1S, `nn.Conv2d` 1×1 |
| **h=4 attention (the common NDT1 miscitation)** | over-parameterizes; actual NDT1 is h=1-2 | h=2 (∈{1,2}), param guardrail [1.0M, 1.6M] |
| **`CADisplayLink` for Metal** | superseded; no beam-raced present callback | `CAMetalDisplayLink` |
| **6×6 webgrid (Pandarinath 2017)** | Neuralink / Bliss Chapman moved past it | 30×30 webgrid (N=900) |
| **`altool`** | retired by Apple for notarization | `notarytool submit` + `stapler staple` |

## Latency claim — software-timed v0, photodiode v1

Cortex states **two** glass-to-glass numbers, kept side by side so the boundary between them
is explicit. This is the load-bearing honesty distinction.

**v0 — software-timed, measured now (M5 Pro corroborating).** The Plan 08-03 `CortexDemoBench`
drives the real closed loop for 10k ticks and measures
`targetPresentationTimestamp − intentEmission(mach_absolute_time)` — ending the measurement at
the `CAMetalDisplayLink` on-glass present timestamp (**`targetPresentationTimestamp`**, the
present time — NOT `targetTimestamp`, the render deadline):

| Software-timed glass-to-glass (M5-Pro-software-timed-corroborating) | Value |
|---------------------------------------------------------------------|-------|
| p50 | **≈ 4.2 ms** |
| p99 | **≈ 8.3 ms** (`8318256 ns`) — well under the 25ms budget |
| n | 10,000 ticks (smoke run: 2,000) |
| methodology | **software-timed pipeline latency - excludes the compositor's 1-3 frames of scanout; measuring that delta needs a photodiode rig, which is retired to Future work (LAT-01..LAT-08) and was never built** |

The verbatim methodology label is embedded in `GlassToGlassTimer.methodologyLabel` so it
travels with every reported number (bench stdout, `glass_to_glass.json`, the GUI overlay) and
cannot be dropped. The p99 is dominated by the 8.333ms 120Hz present-boundary snap, as
expected. The canonical device is M5 Pro ProMotion (corroborating); the iPad-Pro-M4 capture is
a never-auto-approved HUMAN-UAT gate (D-08).

**v1 — photodiode-instrumented, the SPEC TARGET (pending, NOT yet measured).**

> **Glass-to-glass latency 24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)**

This canonical number is the **v1 target**, captured by the BPW34 + TIA + Saleae photodiode
rig in Phases 9-10. It is **not** claimed as measured today — it quantifies precisely the
compositor scanout delta that the software-timed number above explicitly excludes. Presenting
the software-timed number as if it were this photodiode number would be the exact over-claim
the project's thesis forbids.

## Webgrid information-rate BPS

The leaderboard-comparable metric (PERF-01/02/03), measured in the deterministic headless
`CortexReFITBench` 3-way ablation (byte-identical across runs, CI-guarded), using the standard
Neuralink / Bliss-Chapman information-rate formula:

```
B = max(0, log2(N) * (Sc - Si) / t)     bits/second
```

with **N = 900** (the 30×30 grid's selectable targets including the delete/cancel key;
`log2(900) ≈ 9.81` bits/correct-selection — this `log2(N)` normalization is what makes a 30×30
result comparable to BrainGate's 6×6). The mandatory `max(0, ...)` clamp prevents a net-negative
selection count ever reading as a negative bitrate.

| Arm | Webgrid BPS (leaderboard metric) | S&M-2004 Fitts-TP (cross-check, PERF-03) |
|-----|---------------------------------:|-----------------------------------------:|
| raw (no filter) | 1.292 | 0.161 |
| Kalman-only | 1.183 | 0.155 |
| **ReFIT (Kalman + intent-rotation)** | **1.953** | 0.374 |

| Leaderboard reference (reported honestly — NOT a pass bar, D-12) | Webgrid BPS |
|------------------------------------------------------------------|------------:|
| **Cortex ReFIT (synthetic Indy replay, this evidence)** | **1.953** |
| BrainGate 6×6 (Pandarinath 2017) | 4.16 |
| **Neuralink P1 (Noland Arbaugh) verified peak** | **8.5** |

**The honest gap (PERF-02):** ReFIT's 1.953 BPS is 2.21 below the BrainGate 4.16 reference and
**6.55 BPS short of the 8.5 peak**. This is a **synthetic Indy replay** number (a seed-locked
deterministic stand-in through a noisy synthetic decoder), **NOT a live-human two-stage ReFIT
retrain**, and it was **NOT tuned toward 4.16** as a pass bar. The path to 8.5 is the live-human
retrain on real electrode data (v1). `Si` is **structurally 0** (the single-target dwell-to-select
harness has no mis-selection outcome), disclosed as `incorrect_model` so the BPS reads as an
honest upper-bound, never a silent "measured zero errors". Evidence:
[`08-bps-evidence.md`](.planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/08-bps-evidence.md)
+ `webgrid_bps.json` (regenerate-from-code).

## Honest gates

The wire-and-gate doctrine: every account-, entitlement-, or hardware-gated step ships as
**complete, structurally-verified code** plus a **never-auto-approved HUMAN-UAT checkpoint**
for the live/paid step. v0 is fully runnable and credible today; enrollment only flips a gate
from "ready" to "done". Each gate below names what is **done now** versus **what is gated** —
disclosing the gate is the point.

| Gate | Done now | Gated (and why) |
|------|----------|-----------------|
| **Free-team signing** | The developer's free Personal team (placeholder ID `57YW6M29S7`, already in `project.yml`) signs the **Mac GUI** demo; the full `notarytool` + `fastlane match (appstore)` + TestFlight lanes are written and structurally gated in CI | Notarized-live TestFlight submission — needs paid Apple Developer Program enrollment + an App Store Connect key (HUMAN-UAT) |
| **ANE-eligible vs placed** | 226/226 ops ANE-**eligible** (MLComputePlan), <2ms p99 met | Runtime placement is **measured CPU** at the 1.29M-param scale (the documented scale trap); an M4-ANE placement datapoint is an optional future capture |
| **iPad-M4 canonical latency** | M5 Pro ProMotion software-timed number (corroborating) | The canonical iPad-Pro-M4 capture is HUMAN-UAT — a free team cannot provision an iPad headless (D-08) |
| **BCI-HID entitlement** | The 5 Apple BCI HID report structs + the descriptor are ported into Swift; `com.apple.developer.hid.virtual.device` is **declared but inert** under free signing; the round trip is exercised in-app | Live `IOHIDUserDevice`/`HIDVirtualDevice` registration as a Switch Control provider — the entitlement is Apple-managed / partner-gated and request-gated for a solo dev (D-04) |
| **Software vs photodiode** | v0 software-timed p99 ≈ 8.3 ms (M5), methodology-labeled | The canonical photodiode-instrumented 24.7ms number is the v1 milestone (Phases 9-10) — it quantifies the compositor scanout the software timer excludes (D-07) |
| **Synthetic vs live-human BPS** | 1.953 Webgrid BPS on synthetic Indy replay, the 6.55 gap to 8.5 disclosed | A live-human two-stage ReFIT retrain on real electrode data is out of scope for v0 (D-12) |

## Run the demo

The runnable v0 artifact is the **CortexMac** closed-loop GUI app (Plan 08-03, D-09). It runs
the real synthetic-spike → IPC → NDT1 (CoreML) → ReFIT-Kalman → 120Hz 30×30 webgrid loop — the
decoder is genuinely in the loop (D-10), not an oscillator shortcut — and surfaces the
instrumented round-trip log line and the live software-timed glass-to-glass sample with its
methodology label.

```bash
xcodegen                          # regenerate Cortex.xcodeproj from project.yml
open Cortex.xcworkspace            # then run the CortexMac scheme in Xcode (free Personal team signs the Mac GUI)
```

`MTL_HUD_ENABLED=1` is set on the scheme, so the Metal HUD shows live frame pacing. The iPad
build is the **same code**, gated on provisioning. Headless reproductions (no GUI, no signing):

```bash
# Software-timed glass-to-glass bench (PERF-04; p99 < 25ms, M5 corroborating):
swift run --package-path Packages/CortexDemo CortexDemoBench --full

# Webgrid information-rate BPS + Fitts-TP cross-check (deterministic; needs no dataset):
swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke
```

Export `CORTEX_MODEL_URL` (a built `.mlpackage`) to exercise the model-backed NDT1 path; the
demo runs the deterministic synthetic decode fallback on a clean clone.

## What's here

- `Apps/CortexiOS/` — iPadOS 26 app target (Swift 6.2)
- `Apps/CortexMac/` — native AppKit macOS 26 Tahoe app (no Mac Catalyst); the v0 closed-loop demo
- `Apps/CortexDaemon/` — standalone `type: tool` producer (synthetic-spike → encrypt → ring → doorbell)
- `Packages/CortexCore/` — shared Swift+C library (App Group helpers, time utilities, the `cortex_shm.h` compile-time invariant)
- `Packages/CortexIPC/` — `kqueue`+`recvmsg` + POSIX shm + AES-GCM transport (Phase 2)
- `Packages/CortexRing/` — in-house loom-verified Rust SPSC ring, cbindgen-bridged to Swift (Phase 3)
- `Packages/CortexDecoder/` — NDT1 CoreML deployment, `.cpuAndNeuralEngine` inference path (Phase 5)
- `Packages/CortexReFIT/` — ReFIT-Kalman filter + intent-rotation + the Webgrid BPS / Fitts-TP harness (Phases 7-8)
- `Packages/CortexRender/` — `CAMetalDisplayLink` 120Hz renderer with the 30×30 webgrid compute shader (Phase 6)
- `Packages/CortexBCIHID/` — the ported Apple BCI HID report structs + descriptor + Scan-Info round trip (Phase 8)
- `Packages/CortexDemo/` — the v0 closed-loop assembly + software-timed glass-to-glass bench (Phase 8)
- `Decoder/` — the isolated `uv` Python subsystem for NDT1 R&D / training / CoreML conversion (Phase 4)
- `Tools/scripts/` — CI structural gates (`hotpath-policy.sh`, `render-policy.sh`, `hid-surface-policy.sh`, `notarize-policy.sh`, `match-policy.sh`, `bps-policy.sh`, `readme-policy.sh`, …)
- `docs/cortex-spec.md` — full technical specification (935-source research synthesis)
- `docs/adr/` — architecture decision records

## Prerequisites

- macOS 26 Tahoe + Xcode 26.x (26.3 is the CI pin per ADR-0001)
- Swift 6.2 toolchain (bundled with Xcode 26)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) + [SwiftLint](https://github.com/realm/SwiftLint): `brew install swiftformat swiftlint`
- Rust toolchain + `cbindgen` (for `CortexRing`): `brew install rustup-init && rustup-init -y && cargo install cbindgen`
- (Optional) [xcbeautify](https://github.com/cpisciotta/xcbeautify) for prettier build output

## Build

```bash
xcodegen                                          # regenerate Cortex.xcodeproj from project.yml
open Cortex.xcworkspace                           # open in Xcode
# OR build the unsigned smoke from the CLI (the CI path):
./Tools/scripts/build-rust.sh                     # build the CortexRingFFI xcframework first (gitignored)
xcodebuild build \
  -workspace Cortex.xcworkspace \
  -scheme CortexMac \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  -skipPackagePluginValidation \
  -skipMacroValidation
```

## Spec & decisions

- Full technical specification: [`docs/cortex-spec.md`](docs/cortex-spec.md)
- Architecture decisions: [`docs/adr/`](docs/adr/) — ADR-0001 (foundation/toolchain), ADR-0002 (v0 ship + BCI HID integration)

## License

Not yet specified. Will be added at the v0 / v1 milestone.
