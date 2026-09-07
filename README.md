# Cortex.app

An Apple Silicon neural-decoding prototype. It replays recorded primate M1 spikes through a CoreML
NDT1 decoder, a ReFIT-Kalman filter, a 120 Hz Metal cursor renderer and an Apple BCI HID report
encoder, and measures each stage with pinned, reproducible artifacts.

It demonstrates within-session velocity decoding from real neural data. It does **not** demonstrate
useful closed-loop cursor control, and it does not measure physical end-to-end latency. Both are
stated with numbers below rather than deferred to a footnote.

## What works, and what does not

| | state |
|---|---|
| Offline velocity decoding from real M1 spikes | Works. Pooled held-out R2 **0.4238**, beaten by a linear baseline at **0.4616**. |
| Within-session generalization | Weak. Held-out R2 **0.1446** on the locked session. |
| Across-session transfer | Fails. Leave-one-session-out co-bps **-0.3498**, below a mean-rate null. |
| Replay target acquisition, decode-only | **0 of 1,025** acquisitions. |
| Replay with the target supplied each tick | 70 of 1,025, which is not a decoding result (see below). |
| Software-timed pipeline latency | Measured, p99 **8.831 ms** on an M5 Pro. |
| Physical glass-to-glass latency | Not measured. No photodiode rig was built. |
| ANE execution | Graph is **239/239 ANE-eligible**; runtime placement measures **CPU** at this model scale. |
| BCI HID device registration | Surface implemented; the entitlement is request-gated and inert under free-team signing. |

## Decoding results

Source: `indy_20160630_01` from the O'Doherty / Cardoso / Makin / Sabes primate M1 dataset
(Zenodo 3854034), 96 channels, 20 ms bins, 73,160 bins. The session is checksum-pinned; the shipped
fp16 velocity checkpoint is `9d542cb51d4a`.

**Offline velocity prediction.** The decoder predicts cursor velocity from spike counts.

| metric | value |
|---|---|
| pooled held-out velocity R2 | 0.4238 |
| single-session held-out velocity R2 | 0.1446 |
| leave-one-session-out co-bps vs the unseen session's test mean | -0.3498 |

The co-bps figure masks random bin/channel entries. The Neural Latents Benchmark withholds whole
neurons at evaluation, so this number is **not** NLB-comparable and is not offered as one.

**Against a matched linear baseline, the encoder does not win.** A causal ridge decoder on raw binned
spike counts, fit and scored through the same split, the same 20 ms lag, the same rows and the same
train-mean null, reaches a higher held-out R2 than the 1.3M-parameter NDT1 encoder:

| decoder | history | pooled held-out R2 |
|---|---|---|
| ridge on raw spikes | 20 ms | 0.1280 |
| ridge on raw spikes | 80 ms | 0.2795 |
| ridge on raw spikes | 320 ms | 0.4428 |
| **ridge on raw spikes** | **640 ms (the encoder's own window)** | **0.4616** |
| **NDT1 encoder + ridge readout** | 640 ms | **0.4238** |

Both are scored on the identical 56,943 held-out rows. The baseline also leads on every session
individually, including the locked one (0.1832 against 0.1446). The baseline's ridge penalty is
chosen by a weaker rule than the encoder's, so the baseline is untuned rather than flattered.

So on this dataset, under this protocol, the transformer is not earning its parameters. That is a
finding about this setup, not a general claim about NDT1: a stronger result would need better
generalization across sessions, which is exactly where this decoder currently fails.

**The demo runs the decoder that wins.** `CortexMac` drives the replay from that same ridge filter by
default, loaded from the weights the comparison was measured with rather than a reimplementation of
them: `export_ridge_decoder.py` refuses to write the file unless the exported weights reproduce the
published 0.4616 on the same 56,943 rows, and a Swift test asserts the on-device decode matches the
Python fit on a fixed probe window. It is 3,072 multiply-adds per axis and ships in the app bundle,
so the demo needs no checkpoint file at all.

`CORTEX_DECODER=ndt1` runs the transformer instead, with everything downstream identical: the same
window, lag, cm/s units, filter, integrator and scoring. The on-screen instrumentation names which
decoder produced the motion and on how many ticks, because a decoded cursor and a synthetic one look
the same on screen.

A caution on reading the demo as a decoder comparison: it is not one. Two 45-second captures cover
different stretches of the session with roughly 26 trials each, and over that window the two
decoders look comparable, with NDT1 slightly ahead on per-trial progress. The matched claim is the
R2 table above, scored on identical rows.
Reproduce with `uv run --project Decoder python Decoder/scripts/fit_baseline_decoders.py`.

**Replay, not closed loop.** This is an open-loop replay of a recorded session: the animal was not
in the loop, and recorded spikes cannot respond to the decoded cursor. Nothing here is closed-loop
BCI, and the code no longer says otherwise. Four arms over 1,025 trials:

| arm | acquisitions | Webgrid BPS | target information |
|---|---|---|---|
| `raw` (decode only) | **0 / 1,025** | 0 | none |
| `kalman_only` (decode + filter) | **0 / 1,025** | 0 | none |
| target-assisted | 70 / 1,025 | 0.487984 | true target supplied every tick |
| target-assisted, reversed | 2 / 1,025 | 0.013635 | reversed target supplied every tick |

**The decode-attributable result is 0 of 1,025.** The arm that scores is handed the true target
direction on every tick; reversing that target collapses it from 70 to 2, which shows the 70 is
explained by the supplied target rather than by decoded intent. It is labelled target-assisted rather
than ReFIT on purpose: ReFIT uses target-informed intention to retrain decoder parameters, and does
not supply target knowledge during online control.

BPS uses `max(0, (log2(N) * (correct - incorrect)) / minutes)` with N = 900 for a 30x30 grid. These
values are **not** comparable to published BrainGate or Neuralink scores, for four separate reasons:
the bit convention differs (log2(N) here versus log2(N-1) in eLife 18554), the grid differs, this
harness makes incorrect selections **structurally zero** so the error term is always 0 and every BPS
here is an upper bound, and Neuralink's published score adds a click-type term that this
single-click-type harness omits.

## Why the acquisition count is zero

The acquisition rule does not match the task the data came from, and the repository measures this
directly. Replaying the animal's **own recorded cursor track** through the same rule gives:

| acquisition radius | dwell 0.30 s | dwell 0.10 s |
|---|---|---|
| 2.861 mm (the rule used above) | 147 / 1,025 (14.3%) | 334 / 1,025 (32.6%) |
| 7.50 mm | **951 / 1,025 (92.8%)** | 1,007 / 1,025 (98.2%) |
| 15.00 mm | 1,023 / 1,025 (99.8%) | 1,025 / 1,025 (100%) |

The dataset's task was self-paced reaches to a grid of 64 targets at 15 mm pitch, without gaps. The
30x30 Webgrid is a different geometry imposed on top of it, and its 2.861 mm radius is derived from
the grid cell, not from the task. At that radius the recorded hand itself succeeds on 14.3% of
trials; at half the real target pitch it succeeds on 92.8%.

Two things follow, and only the first is a defect in the decoder:

1. The decoder is weak. Held-out R2 of 0.14 within session is not enough for reliable acquisition.
2. The evaluator is mis-specified relative to the source task, which depresses every arm.

Fixing the geometry would not turn this into closed-loop evidence. Recorded spikes cannot react to a
decoded cursor, so no replay of this dataset can establish online control at any radius.

## Latency

All figures are **software-timed pipeline latency**, measured with `mach_absolute_time` from intent
emission to the present timestamp. This excludes the compositor's 1 to 3 frames of scanout.

**Intent to present**, `CortexDemoBench --real`, real spike source, shipped fp16 model, 2,294 of
2,294 ticks model-backed, M5 Pro corroborating:

| | debug | release |
|---|---|---|
| p50 | 4.753 ms | 4.302 ms |
| p99 | **8.831 ms** | 8.386 ms |
| n | 2,286 windows | 2,286 windows |

n is 2,286 because the export holds 73,160 bins and the model's 32-bin window yields that many whole
windows. The present time is modelled 120 Hz arithmetic, not a `CAMetalDisplayLink` reading.

**Daemon to decode**, a strictly wider chain (FlatBuffers encode, AES-GCM seal, `shm_open` ring,
doorbell, decrypt, 32-bin accumulate, NDT1, cursor integrate, HID report):

| | value |
|---|---|
| p50 | 0.136 ms, stable to 0.55% across 5 runs |
| p99 | 0.161 ms, unstable: 58% run-to-run swing |
| process boundary | `in_process`. The two-process rendezvous fails with `MACH_SEND_INVALID_DEST`. Producer and consumer ran lock-step in one process over the real ring, doorbell, crypto and codec, with no cross-process wakeup included. **This is a floor, not a cross-process estimate.** |

These two are not comparable to each other: the first measures intent to present, the second a wider
chain.

## Architecture

| decision | why the obvious alternative was rejected | measured outcome |
|---|---|---|
| CoreML for inference | `MLX` has unbounded p99 and no ANE residency | 239/239 ops **ANE-eligible** (MLComputePlan, reproduced on iPad Air M2); p99 under 2 ms (approx 0.5 ms iPad-M2, 0.14 ms M5 Pro). Runtime placement measures **CPU** at the 1.29M-param scale. |
| pthread + `QOS_CLASS_USER_INTERACTIVE` | Swift `Task` cooperative scheduling cannot meet 1 ms deadlines | QoS is the worker's first action, `import Darwin` only, enforced by a CI gate. |
| `shm_open` + `kqueue`/`recvmsg` | `Network.framework` adds 50 to 200 us | shm round trip p99 **208 ns**, sigma 89.7 ns, n = 199k on M5 Pro. |
| `CAMetalDisplayLink` | `CADisplayLink` cannot bundle drawable, encode and present for beam racing | GPU p99 **0.162 ms** against a 0.4 ms budget; 60 s soak, 243,724 frames, 0 dropped. |
| AES-GCM via CryptoKit | `ChaCha20-Poly1305` is slower on Apple Silicon `FEAT_AES` | HKDF per-direction subkeys, deterministic 96-bit nonce, fail-closed tamper tests, kept off the measured hot path. |

Other rejected options, each with a CI gate preventing regression: the Apple-private `_ANEClient` API
(App Store rejection), `CocoaPods` (SwiftPM only), and `altool` (superseded by notarytool).

## Run it

Requires Apple Silicon, macOS 26, Xcode 26.3. Signing is a free **Personal team**, so the BCI HID
`entitlement` is declared but inert, and GUI launch is the supported path.

The GUI decodes with the ridge filter by default and needs only `CORTEX_REPLAY_EXPORT`, since the
weights are in the bundle. `CORTEX_DECODER=ndt1` selects the transformer and additionally needs
`CORTEX_MODEL_URL`. `Tools/capture/record-demo.sh` builds, launches, frames and records the window.

```bash
# Rust SPSC ring, consumed by SwiftPM as a binary target
./Tools/scripts/build-rust.sh
xcodegen generate

# Python decoder environment (the dev extra is required)
uv sync --project Decoder --extra dev
uv run --project Decoder pytest Decoder/tests -m "not slow" -q

# Materialize the dataset from the committed checksum manifest (not committed)
uv run --project Decoder python Decoder/scripts/download_indy.py

# Refit the linear baselines and re-export the decoder the demo runs. The export refuses to write
# unless its weights reproduce the published held-out R2, so a drifted fit fails loudly here.
uv run --project Decoder python Decoder/scripts/fit_baseline_decoders.py
uv run --project Decoder python Decoder/scripts/export_ridge_decoder.py

# Real-data replay: Seam A latency and the four-arm ablation
swift run --package-path Packages/CortexDemo CortexDemoBench --real

# Information-rate and Fitts throughput cross-check (deterministic, needs no dataset)
swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke
```

## Verification

Twelve policy gates run in CI, and each ships a `--self-test` that proves every check still bites by
mutating the artifact and requiring failure. A gate whose required set changes without its self-test
changing in the same commit is treated as silently disarmed.

The gates cover: README disclosure and secret leakage, information-rate determinism, renderer budget,
HID surface structure, decoder provenance, real-data provenance, repo-wide labelling of superseded
figures, hot-path threading, notarization config, signing config, lint toolchain pinning, and
`Info.plist` keys that the project generator would otherwise strip.

Every published number is committed as an evidence artifact carrying the machine, pinned tool
versions, seed and a reproduction command. A number measured on `synthetic` data is labelled
synthetic; a number measured on a Mac is never presented as an iPad number.

## Known limitations

- No live human or animal is in the loop. Every result is replay of a recorded session.
- Physical end-to-end latency is unmeasured. Present timing is modelled, not read from the display link.
- The decoder does not transfer across sessions (negative leave-one-session-out co-bps).
- A matched linear baseline now exists and **beats** the encoder (see above). A fitted Kalman decoder
  on the same splits has not been run yet.
- The baseline's ridge penalty is selected by in-sample train R2, which always picks the smallest
  value in the grid, so its score is untuned rather than optimised. Proper validation would very
  likely raise it, but not certainly: a validated penalty could land lower on this particular test
  split. The win over the encoder does not depend on that either way.
- On-device iPad and iPhone measurements are not yet collected.
- The training readout pairs a spike window with the velocity one 20 ms bin later; the replay path
  associates the decode with the window's own last bin. That inconsistency is not yet resolved.

## Future work

Not built, and not claimed as measured.

Glass-to-glass latency 24.7 +/- 1.3 ms (p50, sigma=0.8 ms, n=10k, photodiode-instrumented) is a retired spec target, never measured.
The photodiode rig is hardware-gated and was never built. ADR-0003 in `docs/adr/` records why it
was retired.

## Reference points

Published cursor information rates, for scale. None of these is a claim about this project.

| system | rate |
|---|---|
| BrainGate, dense 9x9 grid | 4.16 BPS |
| BrainGate T5, 6x6 grid | 3.7 BPS |
| Neuralink P1, cited peak | 8.5 BPS, as cited by this repo since its earliest Webgrid work; not independently sourceable to a Neuralink primary |

## Spec and decisions

Architecture decision records are in `docs/adr/`. The full specification is `docs/cortex-spec.md`.

## License

MIT.
