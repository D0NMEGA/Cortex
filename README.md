# Cortex.app

A credibility-grade BCI input pipeline on Apple Silicon: NDT1 (~1.3M params) decodes real primate
M1 spikes, drives a 120 Hz beam-raced Metal renderer, and integrates with Apple's May 2025 BCI HID
protocol. The same artifact functions as a tech demo and as a deployable assistive input device.

> **Status:** v1 milestone (Phase 10 / 10). The real-data closed loop runs on
> `indy_20160630_01` (O'Doherty/Makin Indy M1, Zenodo 3854034). Six human UAT gates remain
> deferred (see [Honest gates](#honest-gates)). Roadmap: `.planning/ROADMAP.md`.

## Core value

**Real primate M1 spikes decoded end to end, reproducibly, under a software-timed sub-25 ms
budget.** NDT1 decodes the O'Doherty/Makin Indy M1 dataset (Zenodo 3854034, four checksum-pinned
sessions) through the CoreML -> ReFIT-Kalman -> 120 Hz renderer -> BCI HID path. Session
`indy_20160630_01` (the project's locked session, the weakest of the four by held-out velocity R2
at 0.1446) ran open-loop end to end with the shipped fp16 model. Results are in the
[Webgrid BPS](#webgrid-information-rate-bps) section.

The project's thesis is **instrumentation honesty** -- Bliss Chapman's "anyone can write fast-looking
code; only people who have actually instrumented glass-to-glass have shipped fast code". Over-claiming
would undermine the whole thesis, so **every number on this page is stated with its device and its
method label**: software-timed (not photodiode), real-data open-loop replay (not live-human),
ANE-eligible (CPU-scheduled at this scale), free-team-signed (not notarized-live), HID-surface-registered
(the BCI-HID entitlement is request-gated).

## Architectural commitments

The five load-bearing commitments, each with its rationale and its validated outcome (the measured
number, the phase, and the evidence artifact).

<!-- CI-STATUS-CLAIM: Plan 10-17 updates this sentence after the first push and the first runner execution. -->
Each commitment is wired into `.github/workflows/ci.yml` as a build-failing gate, and each gate ships a
`--self-test` proving every check bites, run locally and transcribed in the phase evidence. As of
2026-09-07 the workflow has not yet executed on a hosted runner. That is verified against GitHub, not
inferred: `gh api repos/D0NMEGA/Cortex/actions/runs` returns `total_count: 0` and `gh repo view`
returns an empty `defaultBranchRef`, so the remote exists and holds no commits.

| # | Commitment | Why (rejected alternative) | Validated outcome |
|---|------------|----------------------------|-------------------|
| 1 | **CoreML on the ANE** | `MLX` has unbounded P99 and no ANE residency -- disqualifying for a <2ms p99 budget | Phase 5 -- **239/239 ops ANE-eligible** (MLComputePlan + Xcode Performance Report, re-measured on the trained real-data graph in Phase 9, independently reproduced on iPad Air M2); **<2ms p99 met** (approx 0.5 ms iPad-M2 / 0.14 ms M5 Pro). Runtime placement **measured CPU** at the 1.29M-param scale -- the CoreML scale trap, reported honestly (DEC-06/08/11). |
| 2 | **pthread + `QOS_CLASS_USER_INTERACTIVE`** on the hot path | Swift `Task` cooperative scheduling cannot meet 1 ms deadlines | Phase 3 -- `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)` is the worker's first action, `import Darwin` only; the `hotpath-policy.sh` CI gate enforces it (THREAD-01/02/03). |
| 3 | **`kqueue`+`recvmsg` over POSIX shm** | `Network.framework` adds 50-200 us -- disqualifying for a sub-us round trip | Phase 2 -- shm busy-poll round trip **p99 = 208 ns**, sigma=89.7 ns, n=199k on M5 Pro (>= M4); approx 4.8x margin under 1 us (IPC-07, `sc1-evidence.md`). |
| 4 | **`CAMetalDisplayLink` 120 Hz zero-copy** | `CADisplayLink` for Metal is superseded; it cannot bundle drawable/encode/present for beam racing | Phase 6 -- **GPU p99 = 0.162 ms** (approx 2.5x under the <=0.4 ms budget), 60 s soak / 243,724 frames / 0 dropped on M5 Pro ProMotion; `storageModeShared` unified-memory drawables (RENDER-01/05/06). iPad-M4 canonical capture deferred (HUMAN-UAT). |
| 5 | **AES-GCM via CryptoKit** | `ChaCha20-Poly1305` is slower than AES-GCM on Apple Silicon `FEAT_AES` | Phase 2 -- HKDF per-direction subkeys, deterministic 96-bit seq-nonce, fail-closed tamper + nonce-uniqueness tested, kept off the measured hot path (IPC-05). |

## Rejected alternatives

Decisions that reject an obvious-seeming option for a non-obvious reason. Each is wired into CI
(a grep gate, a structural test, or a param guardrail) so the project cannot regress into it.

| Rejected | Why | Chosen instead |
|----------|-----|----------------|
| **MLX** | unbounded P99 latency, no ANE residency | CoreML (`MLModelConfiguration.computeUnits`) |
| **Network.framework / NWConnection** | 50-200 us overhead | raw `kqueue`+`recvmsg` over POSIX shm |
| **Swift `Task` on the hot path** | unbounded scheduling latency | pthread + `QOS_CLASS_USER_INTERACTIVE` |
| **ChaCha20-Poly1305** | slower than AES-GCM on `FEAT_AES` | CryptoKit `AES.GCM` |
| **`_ANEClient` private API** | guaranteed App Store rejection | public `MLModelConfiguration` + `MLComputePlan` |
| **CocoaPods** | deprecated / maintenance mode | SwiftPM only |
| **hardware PTP / IEEE-1588** | no macOS NIC supports it | document the software-PTP approx 10 us floor |
| **NDT2** | session-conditioning latency for a single-user v0 | NDT1 (Ye & Pandarinath 2021) |
| **`(B, S, C)` transformer layout** | gets evicted off the ANE | `(B, C, 1, S)` BC1S, `nn.Conv2d` 1x1 |
| **h=4 attention (the common NDT1 miscitation)** | over-parameterizes; actual NDT1 is h=1-2 | h=2 (in {1,2}), param guardrail [1.0M, 1.6M] |
| **`CADisplayLink` for Metal** | superseded; no beam-raced present callback | `CAMetalDisplayLink` |
| **6x6 webgrid (Pandarinath 2017)** | Neuralink / Bliss Chapman moved past it | 30x30 webgrid (N=900) |
| **`altool`** | retired by Apple for notarization | `notarytool submit` + `stapler staple` |

## Latency claim -- software-timed pipeline

Cortex states a software-timed number on two paths, kept side by side so the boundary between them
is explicit.

### Software-timed, synthetic path (Phase 8 / v0, M5 Pro corroborating)

The Plan 08-03 `CortexDemoBench` drives the real closed loop for 10k ticks and measures
`targetPresentationTimestamp - intentEmission(mach_absolute_time)` -- ending at the
`CAMetalDisplayLink` on-glass present timestamp (NOT `targetTimestamp`). No model was in the loop on
this run (`isModelBacked` false; synthetic fallback on every tick).

| Software-timed glass-to-glass, Phase 8 (synthetic path, M5-Pro-software-timed-corroborating) | Value |
|-----------------------------------------------------------------------------------------------|-------|
| p50 | approx 4.2 ms |
| p99 | approx 8.3 ms (8318256 ns) -- well under the 25 ms budget |
| n | 10,000 ticks |
| methodology | **software-timed pipeline latency - excludes the compositor's 1-3 frames of scanout; measuring that delta needs a photodiode rig, which is retired to Future work (LAT-01..LAT-08) and was never built** |

### Software-timed, real-data path (Phase 10 / v1, Seam A, M5 Pro corroborating)

`CortexDemoBench --real`, same boundary as Phase 8. The changed variable is the spike source and the
decode: `RecordedSpikeSource` over the D-06 export of `indy_20160630_01`, decoded by the shipped
NDT1 fp16 model (velocity checkpoint `9d542cb51d4a`, 2294 of 2294 ticks model-backed). Warmup,
clock, present arithmetic, sampling function and percentile math are the same code. Debug build is
the headline because Phase 8 was also a debug build.

| Seam A (real-data path, M5-Pro-software-timed-corroborating) | debug | release |
|--------------------------------------------------------------|-------|---------|
| p50 | 4753046 ns (4.753 ms) | 4302424 ns (4.302 ms) |
| p99 | **8831017 ns (8.831 ms)** | 8386219 ns (8.386 ms) |
| n | 2,286 ticks | 2,286 ticks |
| runs | 5 (p50/p99 are medians) | 5 |
| ticks model-backed | 2294 / 2294 | 2294 / 2294 |
| methodology | **software-timed pipeline latency - excludes the compositor's 1-3 frames of scanout; measuring that delta needs a photodiode rig, which is retired to Future work (LAT-01..LAT-08) and was never built** |

The verbatim methodology label is embedded in `GlassToGlassTimer.methodologyLabel` so it travels with
every reported number (bench stdout, `glass_to_glass.json`, the GUI overlay) and cannot be dropped.

The n is 2,286 (not 10,000) because the export holds 73,160 bins; the model's 32-bin window yields
2,286 whole windows. Replaying windows to hit a round number would pad the distribution. The present
time is modelled arithmetic (`cadence_provenance: "modelled 120 Hz"`), not a `CAMetalDisplayLink`
reading; the iPad-M4 gate (Gate 5) would supply the measured cadence.

### Seam B: the daemon-to-decode chain (wider boundary, not comparable to Seam A)

Seam B measures the full chain: daemon reads the export bin, `SampleCodec` encodes as FlatBuffers
`Sample`, `SessionCrypto` AES-GCM seals it, writes to the `shm_open`ed `ShmRing`, rings the
`Doorbell` socketpair, consumer polls, decrypts, decodes, fills the 32-bin accumulator, calls NDT1,
integrates the cursor, encodes a BCI HID report.

| Seam B (daemon-to-decode chain, M5 Pro corroborating) | Value |
|-------------------------------------------------------|-------|
| p50 | **136167 ns (0.136 ms)**, stable to 0.55 percent across 5 runs |
| p99 | 160958 ns (0.161 ms), **unstable: 58 percent run-to-run swing** |
| n | 73,128 windows |
| process boundary | **`in_process`** -- the two-process daemon rendezvous fails with `MACH_SEND_INVALID_DEST`, confirmed to have failed that way before any Phase-10 change (Plan 10-06). Producer and consumer ran lock-step in one process over the real `shm_open`ed ShmRing, Doorbell socketpair, AES-GCM and FlatBuffers codec, with no cross-process wakeup or context switch included. This is a floor, not a cross-process estimate. |

**Seam B is not comparable to Seam A or to the Phase-8 glass-to-glass number.** Seam A measures
intent-to-present; Seam B measures a strictly wider chain. Seam B's floor status and its
process-boundary qualification are stated in those words in `10-replay.json` (`boundary`,
`process_boundary`, `process_status`).

### Future work (retired from v1): photodiode-instrumented latency

<!-- readme-policy.sh rule A is a SAME-LINE check: the figure below and its retirement marker must stay on one physical line. Re-wrapping this paragraph fails the gate. -->
Glass-to-glass latency 24.7 +/- 1.3 ms (p50, sigma=0.8 ms, n=10k, photodiode-instrumented) is a retired spec target, never measured.
The photodiode rig (LAT-01..LAT-08) is hardware-gated and was never built; ADR-0003 records why it
was retired.

## Webgrid information-rate BPS

The leaderboard-comparable metric (PERF-01/02/03), measured in the deterministic headless
`CortexReplayBench` four-arm ablation (byte-identical across runs, CI-guarded).

**D-14 provenance triple:** session `indy_20160630_01`, velocity checkpoint `9d542cb51d4a`
(full sha256 `9d542cb51d4af4811f324fbc6bda0b503da7b15aafc98b5e1340e1a7f49cce65`), open-loop replay.

**Open-loop replay disclosure.** The byte-identical string used throughout this repo is:
`open-loop replay of a recorded session; the subject was not in the loop`. Closed loop refers to the
SOFTWARE path being closed end to end, never to the subject being in the loop, because a recorded
session's spikes cannot respond to a cursor we drive.

Formula, unchanged from Phase 8:

```
B = max(0, log2(N) * (Sc - Si) / t)     bits/second
```

with **N = 900** (the 30x30 grid's selectable targets including the delete/cancel key).

### Real-data ablation (Phase 10, v1, M5 Pro corroborating, `indy_20160630_01`)

These numbers are transcribed from `10-refit-real.json`. The N=900 column is a **counterfactual
30x30 grid score** throughout (see the normalization note below).

| Arm | rotation target | hits of 1,025 | Webgrid BPS (N=900, counterfactual) | Webgrid BPS (N=64, recorded task) | Fitts TP |
|-----|----------------|--------------|-------------------------------------|------------------------------------|----------|
| `raw` | none | **0** | **0.000000** | **0.000000** | 0.356340 |
| `kalman_only` | none | **0** | **0.000000** | **0.000000** | 0.355569 |
| `refit` | `true_track` | 70 (target-determined by construction) | 0.487984 | 0.298346 | 0.672882 |
| `refit_reversed_target` | `reversed_track` | 2 (target-determined) | 0.013635 | 0.008336 | 0.347855 |

Evidence: [10-refit-real-evidence.md](.planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real-evidence.md).

**The headline attributable to the decode is 0.000000 BPS on both normalizations.** `raw` and
`kalman_only` are the only arms whose rate is attributable to the decode; both score 0 of 1,025. The
`refit` arm's `IntentRotation` replaces the decoded direction with the direction to the KNOWN target
and keeps only the decoded speed (pre-registered in `10-PREREGISTRATION.md` section 7 before any
number existed), so its 70 hits and 0.487984 BPS are target-determined by construction. Neither
0.487984 nor 70 represents a decoding result and must never appear as one.

**SC#2 disposition.** `10-replay.json` carries `sc2_disposition: "not_met"` and `sc2_rule: "B"`,
written from the user's decision ("Not met, on attributable arms") recorded in Plan 10-10 Task 3b.

**Normalization.** The recorded task presented 64 distinct targets (6.0 bits per selection). N=900
awards log2(900)/log2(64) = 1.64x more information per hit than the task contained; it is
published for continuity with the Phase-8 synthetic figure. N=64 is the recorded task's information
rate. Both are in the same row.

**Hits against the recorded-cursor replay reference.** The pre-registered reference from
`10-ceiling.json`: **147 of 1,025 trials (14.34 percent)** at acquisition radius 2.8614 mm and dwell
0.30 s. This reference is the hit rate of the animal's OWN recorded cursor through this repo's
dwell-to-select rule at that radius and dwell. It is a property of one recorded trajectory under one
acceptance rule, not a bound on what a decoder can achieve. The distance distribution is the primary
observable (RD-08): at the 1st percentile of the target-blind distribution, the decoded cursor was
16.58 mm from the target against an acquisition radius of 2.8614 mm -- 5.8 radii away.

### Phase 8 synthetic triple (retained per D-12 as the before-and-after)

| Arm | Webgrid BPS (N=900, counterfactual) | Fitts TP | Notes |
|-----|-------------------------------------|----------|-------|
| raw | 1.292 | 0.161 | **synthetic seed-locked replay**, no model in the loop |
| Kalman-only | 1.183 | 0.155 | **synthetic seed-locked replay** |
| **ReFIT** | **1.953** | 0.374 | **synthetic seed-locked replay** |

1.953 is a synthetic number, produced on a seed-locked Poisson replay with no model in the loop. It
appears here because D-12 requires the before-and-after to be one glance apart. It was NOT tuned
toward 4.16 as a pass bar. Evidence:
[08-bps-evidence.md](.planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/08-bps-evidence.md).

### Reference numbers

| Reference | BPS | Condition |
|-----------|-----|-----------|
| BrainGate T5 (dense 9x9) | 4.16 +/- 0.39 | Pandarinath et al. 2017, eLife 18554, participant T5 on a **dense 9x9 grid** (not 6x6) |
| BrainGate T5 (6x6) | 3.7 +/- 0.4 | same paper, same participant, 6x6 grid |
| Neuralink P1 (Noland Arbaugh) | 8.5 | kept per D-17, dated 2026-09-07; current public statement at neuralink.com/webgrid: "over 10 BPS" (retrieved 2026-09-07). The 8.5 figure is not independently sourceable to a Neuralink primary; an access date does not authenticate a number. |

**Non-comparability disclosure (verbatim from `WebgridBPS.nonComparabilityDisclosure` in
`Packages/CortexReFIT/Sources/CortexReFIT/WebgridBPS.swift`):**

> this repo's Webgrid BPS is not like-for-like with either reference: the formula differs (log2(N)
> here versus log2(N-1) in eLife 18554), the grid differs (T5 dense 9x9, not 6x6), the harness makes
> incorrect selections structurally zero so Si is always 0, and Neuralink's current published score
> adds a click-types term this single-click-type harness omits

This is a disclosure, not a formula change. Editing the pinned formula in `bps-policy.sh` would
break the Phase-7 byte-identity fixture (D-09).

## Honest gates

The wire-and-gate doctrine: every account-, entitlement-, or hardware-gated step ships as
**complete, structurally-verified code** plus a **never-auto-approved HUMAN-UAT checkpoint** for the
live/paid step. Each gate below names what is **done now** versus **what is gated**.

| Gate | Done now | Gated (and why) |
|------|----------|-----------------|
| **Free-team signing** | The developer's free Personal team (placeholder ID `57YW6M29S7`, already in `project.yml`) signs the **Mac GUI** demo | Notarized-live TestFlight submission -- needs paid Apple Developer Program enrollment + an App Store Connect key (HUMAN-UAT gate 2) |
| **ANE-eligible vs placed** | 239/239 ops ANE-**eligible** (MLComputePlan), re-measured on the trained real-data graph (Phase 9), independently reproduced on iPad Air M2; <2ms p99 met | Runtime placement is **measured CPU** at the 1.29M-param scale (the documented scale trap); an M4-ANE placement datapoint is an HUMAN-UAT gate (gate 4) |
| **iPad-M4 canonical latency** | M5 Pro ProMotion software-timed number (corroborating) | The canonical iPad-Pro-M4 software-timed glass-to-glass capture is HUMAN-UAT gate 1 -- a free team cannot provision an iPad headless (D-08) |
| **BCI-HID entitlement** | The 5 Apple BCI HID report structs + the descriptor are ported into Swift; `com.apple.developer.hid.virtual.device` is **declared but inert** under free signing; the round trip is exercised in-app | Live `IOHIDUserDevice`/`HIDVirtualDevice` registration as a Switch Control provider -- the entitlement is Apple-managed / partner-gated and request-gated for a solo dev (D-04, HUMAN-UAT gate 3) |
| **Software vs photodiode** | v0 (Phase 8) software-timed p99 approx 8.3 ms (M5 Pro); v1 (Phase 10) Seam A debug p99 8.831 ms (M5 Pro), both methodology-labeled | Photodiode-instrumented glass-to-glass is retired to Future work (LAT-01..LAT-08) -- hardware-gated and never built; see ADR-0003 |
| **Synthetic vs real-data BPS** | Real-data open-loop replay on `indy_20160630_01`: 0.000000 BPS on attributable arms; 1.953 synthetic triple retained beside it per D-12 | A live-human two-stage ReFIT retrain on real electrode data is out of scope for v1 |
| **Cross-session transfer** | Phase 9's four leave-one-session-out co-bps folds were all negative against the held-out session's own mean, mean -0.3498, range -0.7805 to -0.1238 | No cross-session claim is made or supported |
| **CI has not yet executed on a runner** | Gates are wired into `ci.yml` and each is proven to bite by a locally-run `--self-test` | As of 2026-09-07 the workflow has not yet executed on a hosted runner (total_count: 0); Plan 10-17 performs the first push |
| **iPad-M4 real-data latency** | M5 Pro Seam A debug p99 median 8831017 ns (corroborating) | Canonical iPad-Pro-M4 Seam A p99 on the real-data path is HUMAN-UAT gate 5 |
| **iPad-M4 120 Hz webgrid demo** | M5 Pro demo capture: 61.38 s, sustained 120.00 FPS / 8.33 ms, real spikes, no GUI capture committed (48.6 MB .mov pinned by sha256) | Canonical iPad-Pro-M4 120 Hz webgrid demonstration is HUMAN-UAT gate 6 |

## Run the demo

The CortexMac closed-loop GUI app (Plan 08-03, Plan 10-09) runs the real closed loop. The synthetic
path (no export, no model) and the real-data path (with export and model) both work.

```bash
xcodegen                          # regenerate Cortex.xcodeproj from project.yml
open Cortex.xcworkspace           # run the CortexMac scheme in Xcode (free Personal team signs the Mac GUI)
```

`MTL_HUD_ENABLED=1` is set on the scheme, so the Metal HUD shows live frame pacing.

**Real-data path.** Export is gitignored and materialized from the SHA-256-pinned `.mat`:

```bash
uv sync --project Decoder --extra dev
uv run --project Decoder python Decoder/scripts/download_indy.py
uv run --project Decoder python Decoder/scripts/export_replay.py --session indy_20160630_01
```

Then set two environment variables before building in Xcode:

```
CORTEX_REPLAY_EXPORT=Decoder/exports/indy_20160630_01.replay.json
CORTEX_MODEL_URL=Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage
MTL_HUD_ENABLED=1
```

Headless reproductions (no GUI, no signing):

```bash
# Software-timed glass-to-glass bench (PERF-04; p99 < 25 ms, M5 corroborating):
swift run --package-path Packages/CortexDemo CortexDemoBench --full

# Real-data replay bench (p99 Seam A, webgrid ablation):
CORTEX_REPLAY_EXPORT=Decoder/exports/indy_20160630_01.replay.json \
CORTEX_MODEL_URL=Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage \
swift run -c release --package-path Packages/CortexDemo CortexReplayBench \
  --out /tmp/refit-real.json

# Webgrid information-rate BPS + Fitts-TP cross-check (deterministic; needs no dataset):
swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke
```

## What's here

- `Apps/CortexiOS/` -- iPadOS 26 app target (Swift 6.2)
- `Apps/CortexMac/` -- native AppKit macOS 26 Tahoe app (no Mac Catalyst); the v0/v1 closed-loop demo
- `Apps/CortexDaemon/` -- standalone `type: tool` producer (spike source -> encrypt -> ring -> doorbell)
- `Packages/CortexCore/` -- shared Swift+C library (App Group helpers, time utilities, the `cortex_shm.h` compile-time invariant)
- `Packages/CortexIPC/` -- `kqueue`+`recvmsg` + POSIX shm + AES-GCM transport (Phase 2)
- `Packages/CortexRing/` -- in-house loom-verified Rust SPSC ring, cbindgen-bridged to Swift (Phase 3)
- `Packages/CortexDecoder/` -- NDT1 CoreML deployment, `.cpuAndNeuralEngine` inference path (Phase 5)
- `Packages/CortexReFIT/` -- ReFIT-Kalman filter + intent-rotation + the Webgrid BPS / Fitts-TP harness (Phases 7-8)
- `Packages/CortexRender/` -- `CAMetalDisplayLink` 120 Hz renderer with the 30x30 webgrid compute shader (Phase 6)
- `Packages/CortexBCIHID/` -- the ported Apple BCI HID report structs + descriptor + Scan-Info round trip (Phase 8)
- `Packages/CortexDemo/` -- the closed-loop assembly + software-timed glass-to-glass bench + real-data replay bench (Phases 8/10)
- `Decoder/` -- the isolated `uv` Python subsystem for NDT1 R&D / training / CoreML conversion (Phases 4/9)
- `Tools/scripts/` -- CI structural gates (`hotpath-policy.sh`, `render-policy.sh`, `hid-surface-policy.sh`, `notarize-policy.sh`, `match-policy.sh`, `bps-policy.sh`, `readme-policy.sh`, ...)
- `docs/cortex-spec.md` -- full technical specification (935-source research synthesis)
- `docs/adr/` -- architecture decision records

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
- Architecture decisions: [`docs/adr/`](docs/adr/) -- ADR-0001 (foundation/toolchain), ADR-0002 (v0 ship + BCI HID integration), ADR-0003 (photodiode retirement)

## License

Not yet specified. Will be added at the v0 / v1 milestone.
