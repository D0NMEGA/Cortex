# Roadmap: Cortex.app

## Overview

Cortex.app is a sprint to ship a sub-25ms glass-to-glass BCI input pipeline on iPad Pro M4 / Mac M-series, decoding real primate M1 spikes. The roadmap derives from `cortex-spec.md` Section 10 (Sprint Timeline), decomposed at `fine` granularity into 10 phases that respect dependency order: foundation → IPC primitive → real-time threading → decoder (training, then ANE deployment) → renderer → ReFIT closed-loop → system integration & v0 distribution → real-data ingest & retrain → v1 real-data closed loop & launch.

**Re-planned 2026-08-28.** Phases 9-10 originally built a BPW34 + OPA381 TIA + Saleae photodiode rig and ran a 10k-trial glass-to-glass campaign. That path is **retired to [Future work](#future-work-retired-from-v1)** — it is gated on hardware the project does not have (the BOM, plus the provisioned iPad Pro M4 that already forced three Phase-8 HUMAN-UAT deferrals), and it was never the project's largest credibility hole. The larger hole is that **every decoder number in the repo was produced on a synthetic Poisson fallback, not real neural data** (`04-training-evidence.md`: "No real `.mat` was present under `Decoder/data/`"). Phases 9-10 now close that hole instead.

Two milestones anchor the roadmap:
- **v0 (end of Phase 8):** software-timed glass-to-glass claim, BCI HID integration live, TestFlight build available.
- **v1 (end of Phase 10):** real-neural-data decoding claim — NDT1 trained and evaluated on the four curated O'Doherty/Makin Indy M1 sessions (Zenodo 3854034) rather than synthetic Poisson replay — driving the closed loop end to end, with every synthetic-derived number re-derived or explicitly labeled, and the photodiode latency claim retired to Future work.

## Milestones

- ✅ **v0 Software-Timed** — Phases 1-8, shipped 2026-06-23 (internal checkpoint; never archived separately, its phases are inside the v1.0 archive). Closed-loop synthetic-spike → cursor → 30×30 webgrid hit at 120Hz, software-side `mach_absolute_time` latency claim, TestFlight-ready notarized build.
- ✅ **v1.0 Real-Data Decoding** — Phases 1-10, shipped 2026-09-16. Four real Indy M1 sessions checksum-pinned and ingested, NDT1 retrained and re-converted on real spikes, ReFIT ablation and closed loop re-run on a real session, README republished with the photodiode claim retired. Headline result is negative and published as such: 0/1025 target acquisition. Full detail: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md) · [MILESTONES.md](MILESTONES.md)
- 🚧 **v1.1 Technical Narrative and Decode-Gap Analysis** — Phases 11-12, started 2026-09-17, hard deadline 2026-09-18 (Neuralink onsite). A compilation milestone plus one bounded measurement: decompose the published 0 of 1,025 into a geometry term and a decode term, and produce a sequential decision-by-decision walkthrough of the pipeline. Adds no product capability and touches no shipped v1.0 code path.

## Phases

<details>
<summary>✅ v1.0 Real-Data Decoding (Phases 1-10) - SHIPPED 2026-09-16</summary>

- [x] **Phase 1: Foundation & 2026 Toolchain** - Repo skeleton on Xcode 26 + Swift 6.2 / macOS 26 Tahoe / iPadOS 26 with App Group container, privacy manifest, and CI green — completed 2026-06-19
- [x] **Phase 2: IPC Primitive — kqueue+recvmsg + FlatBuffers + AES-GCM** - Sub-µs sample-frame transport between acquisition daemon and app, encrypted, FD-passed via mach_msg — completed 2026-06-20 (SC#1 p99=208ns)
- [x] **Phase 3: Real-Time Threading — pthread USER_INTERACTIVE + Rust SPSC Ring** - Audio-callback-regime hot path with loom-verified lock-free ring buffer bridged to Swift via cbindgen — completed 2026-06-20 (THREAD-01..07 validated, security 18/18 closed)
- [x] **Phase 4: NDT1 Training on Indy/Loco Synthetic Replay** - 1.3M-param NDT1 (6 layers, h=1-2, 128 dim, 20ms bins) trained on Zenodo 3854034 with 4-bit palettization — completed 2026-06-21 (4/4 SC: 1.29M params, co-bps 0.3804 held-out **on synthetic Poisson replay and under a defective objective**, 3.471× palettization **on a randomly-initialized graph**; both re-derived on real data in Phase 9: co-bps 0.4096, size ratio 3.4134x)
- [x] **Phase 5: NDT1 → CoreML deployment — ANE-eligible, sub-2ms verified** - coremltools-converted BC1S `(B,C,1,S)` `.mlpackage`; **100% ANE-eligible** (226/226 ops, 0 CPU-only), **<2ms p99** (≈0.5ms iPad-M2). Runtime placement measured CPU at 1.29M-param scale (M5 Pro + iPad-M2 scale trap) — reported honestly, not assumed ANE. **Op tally superseded in Phase 9 by 239/239 eligible, 0 CPU-only**: the 226 was read off a stale compiled artifact (a `compile_model` `shutil.move` nested each fresh `.mlmodelc` inside the existing destination) and was measured on an untrained graph; eligibility survives the correction
- [x] **Phase 6: CAMetalDisplayLink 120Hz Renderer with 30×30 Webgrid** - Beam-raced ProMotion presentation, ≤0.4ms GPU compute, zero-copy `storageModeShared` drawables — completed 2026-06-22 (RENDER-01..09; M5 Pro GPU p99=0.162ms ~2.5× under ≤0.4ms, 60s soak 243,724 frames / 0 dropped; iPad-M4 canonical capture deferred per D-11/D-12)
- [x] **Phase 7: ReFIT-Kalman Closed-Loop Recalibration** - Swift-side 6-DOF Kalman with per-update intent-rotation step delivering BPS uplift over raw NDT1 — completed 2026-06-23 (REFIT-01/02/03 verified 6/6; 3-way ablation on synthetic data refit_bps 0.374 ≥ raw 0.161, +133% S&M-2004 Fitts-TP uplift; SC#3 filter step ~292ns p99 over 10k inline ticks, Mac-corroborating; iPad-M4 canonical latency Manual-Only/deferred)
- [x] **Phase 8: Apple BCI HID Integration, Distribution & v0 Ship** - Switch Control HID provider registration, Synchron-mirror entitlements, notarized TestFlight build, software-timed latency claim — **v0 milestone** — completed 2026-06-23 (automated half green 5/5: 59 Swift tests + 5 `*-policy.sh` gates + benches; software-timed glass-to-glass p99 ≈ 8.32ms M5-corroborating; ReFIT 1.953 BPS synthetic, honest gap-to-8.5 (as cited since Phase 7; not independently sourceable); 3 never-auto-approve HUMAN-UAT gates — live TestFlight / iPad-M4 canonical latency / on-device HID registration — DEFERRED, tracked in 08-HUMAN-UAT.md)
- [x] **Phase 9: Real-Data Ingest & NDT1 Retrain (Zenodo 3854034)** - Materialize and checksum-pin the four Indy M1 sessions, retrain NDT1 on real spikes, re-derive co-bps / palettization / ANE eligibility on the real-data checkpoint — completed 2026-09-03 (RD-01..RD-06; 5/5 SC verified in 09-VERIFICATION.md, verdict human_needed; real-data co-bps 0.4096, palettization 3.4134x, 239/239 ANE-eligible; RD-06b canonical iPad-M4 p99 deferred, iPad Air M2 corroborating capture p99 0.5790 ms)
- [x] **Phase 10: v1 Real-Data Closed Loop & Launch** - ReFIT re-fit and ablation on real data, end-to-end real-session replay, synthetic-number sweep with a CI gate, README republish retiring the photodiode claim — **v1 milestone** (completed 2026-09-08)

Per-phase goals, plan lists, success criteria and dependency notes: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md).

</details>

### Milestone v1.1: Technical Narrative and Decode-Gap Analysis (in progress)

Scoped 2026-09-17 against a one-working-day deadline. Phase 12 is the must-ship deliverable;
Phase 11 is time-boxed so it cannot consume the day. Requirements: `.planning/REQUIREMENTS.md`.
Audience research: `.planning/research/NEURALINK-JD.md`.

- [ ] **Phase 11: Decode-attributable gap analysis** - Score the decoded trajectory through the same
  acceptance machinery `webgrid_ceiling.py` already applies to the recorded hand, sweep the
  acceptance radius, and report the decoder's effective acceptance radius in mm. Decompose the
  published zero into the geometry loss (1,025 to 147, already established for the recorded hand)
  and the decode loss (147 to 0, never measured). Quantify velocity variance shrinkage against the
  shrinkage a held-out R2 of 0.4238 predicts, and the angular error distribution. Requirements:
  GAP-01..GAP-08

  **Success criteria**
  1. A decoded counterpart to `10-ceiling.json` exists, covering the same radius and dwell grid, and
     reproduces 0 of 1,025 at the canonical 2.8614 mm / 0.30 s cell from committed artifacts
  2. The decoder's effective acceptance radius is stated in mm, as a multiple of the 2.8614 mm
     canonical radius, and as a multiple of the task's own 7.50 mm half-pitch
  3. The zero is decomposed into a geometry term and a decode term, each stated separately with its
     own trial count
  4. Velocity shrinkage and angular error are reported as distributions with the method that
     produced them, not as point assertions
  5. `11-decode-gap-evidence.md` carries machine, OS, pinned wheel versions, determinism statement,
     session id, source sha256 and a copy-pasteable runbook, and every artifact repeats the
     open-loop disclosure verbatim

  **Dependency note.** Reads only committed artifacts and the already-materialized, checksum-pinned
  `indy_20160630_01.mat`. Trains nothing, re-fits nothing, and writes no checkpoint.

- [ ] **Phase 12: Sequential technical walkthrough** - One document walking the pipeline in
  data-flow order, each stage carrying the decision, the rejected alternative and its quantitative
  reason, the measured number with its device and method, and the weakness named before a reviewer
  names it. Closes on the Phase 11 result. Requirements: NAR-01..NAR-07

  **Success criteria**
  1. Eight stage sections exist in data-flow order: acquisition hot path, IPC transport, SPSC ring,
     decoder, ReFIT-Kalman, renderer, BCI HID surface, evidence and gate layer
  2. Each section names a specific rejected alternative and the quantitative reason it was rejected
  3. Every number traces to a committed `*-evidence.md` and carries its device and method; no
     Mac-measured number is presented as an iPad-M4 number
  4. The weak results are stated plainly and not softened: 0 of 1,025, leave-one-session-out
     negative on all four folds, ReFIT uplift not surviving real spikes, NDT1 losing to a linear
     ridge baseline, INT-01/02/03, and the six device- and account-gated deferrals
  5. The document passes `readme-policy.sh` and `honesty-sweep.sh` context rules, and the 24.7 ms
     figure appears only as a retired spec target

  **Dependency note.** Depends on Phase 11 for its closing section only. The other seven sections
  are independent and can be drafted while Phase 11 runs.

Open work not addressed in v1.1 stays recorded as Known Gaps in [MILESTONES.md](MILESTONES.md): six
device- and account-gated requirements, INT-02 and INT-03, and the `summary-extract` parser defect.
The cheapest remaining credibility item is Phase 3's SC#1 Instruments System Trace, which needs no
new hardware and is the first candidate for v1.2, alongside the manifold / population-dynamics
analysis that `research/NEURALINK-JD.md` records as a real gap.

## Progress

| Milestone | Phases | Plans | Status | Shipped |
| --------- | ------ | ----- | ------ | ------- |
| v1.0 Real-Data Decoding | 1-10 | 70/70 | Complete (11 partials deferred, none auto-approved) | 2026-09-16 |
| v1.1 Technical Narrative and Decode-Gap Analysis | 11-12 | 0/0 | In progress (started 2026-09-17) | - |

Per-phase progress rows are preserved in [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md).

## Future work (retired from v1)

Retired 2026-08-28 when the v1 milestone was re-pointed from photodiode-instrumented latency to
real-neural-data decoding. These requirements are **preserved, not deleted** — the work is still the
right way to earn a true glass-to-glass number, it is simply gated on hardware this project does not
have, and on the provisioned iPad Pro M4 that already forced three Phase-8 HUMAN-UAT deferrals.

### Photodiode Rig Hardware Build (was Phase 9)
BPW34 (Vishay) + OPA381 TIA (TI) + Saleae Logic Pro 8 breadboard, ~$110 BOM excluding the logic
analyzer, aimed at the iPad Pro M4 pixel where the cursor lands, with the acquisition daemon emitting
a GPIO pulse at intent-emission timestamp captured on the same timeline at >=100 MS/s.
**Requirements**: LAT-01, LAT-02, LAT-03, LAT-04

### v1 Photodiode Measurement & Launch (was Phase 10)
10,000-trial automated capture producing `(intent_pulse_ts, photodiode_rising_edge_ts, dt)` tuples,
statistical reduction to a p50/sigma claim, and a launch video showing the rig capturing photons off a
ProMotion display. The spec's canonical target line was *"Glass-to-glass latency 24.7 +/- 1.3 ms
(p50, sigma=0.8 ms, n=10k, photodiode-instrumented)"*.
**Requirements**: LAT-05, LAT-06, LAT-07, LAT-08

**Standing honesty constraint:** 24.7 ms was always a **spec target, never a measurement**. Nothing in
v1 may present it as achieved. Phase 10's rewritten `readme-policy.sh` enforces this structurally
(SC#4) — the number is only ever citable as a retired target.
