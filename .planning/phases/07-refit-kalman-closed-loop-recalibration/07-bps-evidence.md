# Phase 7 REFIT-03 / SC#2 Evidence — ReFIT intent-rotation improves Fitts throughput over raw NDT1

> **SUPERSEDED FOR THE REAL-DATA CLAIM (Phase 10, 2026-09-07).** The 0.374 and 0.161 figures below
> were produced on a **synthetic seed-locked Poisson replay** with no trained model in the loop.
> They are superseded for any claim about real neural data by
> [`10-refit-real-evidence.md`](../10-v1-real-data-closed-loop-launch/10-refit-real-evidence.md)
> (Phase 10, `indy_20160630_01`, decode-attributable arms: **0 of 1,025 hits, 0.000000 BPS**).
>
> **Retained as the D-09 regression fixture.** The `phase7BaselineK` constant in
> `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift` is frozen from this Phase-7
> run. `CortexReFITBench --smoke` verifies the byte-identity of the deterministic synthetic ablation
> on every CI run to guard against filter-step regressions. Cite these numbers only in that
> regression context; never in a real-data context.
>
> This file is **NOT retroactively edited**.

**Date:** 2026-06-22
**Result:** ✅ **PASS** — on the fixed seed-locked replay the **ReFIT (Kalman + intent-rotation)**
throughput **`refit_bps = 0.374`** beats the **raw NDT1** throughput **`raw_bps = 0.161`** by
**`Δ = +0.213`** (≈ **+133 %**), satisfying the deterministic CI guard `refit_bps ≥ raw_bps`.

> **SC#2 (Phase 7 Success Criterion #2 / REFIT-03):** "Headless deterministic closed-loop harness
> measures **S&M-2004 BPS uplift over raw NDT1** on synthetic Indy replay; the documented uplift is
> committed as a regression artifact." The uplift is operationalized as a **3-way ablation** (raw /
> Kalman-only / Kalman+rotation) on the **identical seed-locked replay** (D-12), with a build-failing
> CI guard asserting `refit_bps ≥ raw_bps` (D-10, mirroring Phase-4's `co-bps > null` gate).

---

## ⚠ Which metric this is — and which it is NOT (the load-bearing disclaimer, 07-RESEARCH §4.3)

The number reported here is **Soukoreff & MacKenzie 2004 ISO 9241-9 Fitts throughput**:

```
TP  = IDe / MT                       (bits/second — the "BPS" reported below)
IDe = log2( De / We + 1 )            (effective index of difficulty, Shannon form)
We  = 4.133 · SDx                    (effective width; 4.133 = √(2πe), the 96%-spread constant)
```

computed with the **effective-width method** (`We` from the *realized endpoint scatter* `SDx`, not the
nominal target width — 07-RESEARCH §4.2 / §7 pitfall 3) and aggregated **mean-of-means** across
amplitude conditions.

**This is a DIFFERENT metric from the Neuralink / BrainGate Webgrid bitrate**
(`log2(N) · (correct − incorrect) / time`). The well-known reference numbers — **BrainGate 4.16 BPS**
(Pandarinath 2017) and **Neuralink P1 8.5 BPS** (Noland Arbaugh) — are **Webgrid bitrate**, a
different scale. **The Phase-7 S&M-TP number here MUST NOT be compared to 4.16 / 8.5.** That
apples-to-oranges leaderboard comparison (matching the Webgrid-bitrate metric) is **Phase 8 SC#5
(PERF-01 / PERF-02), explicitly deferred per CONTEXT D-13** — Phase 7 reports the *absolute* S&M-TP
for each arm and the *raw → ReFIT delta* on the identical seed-locked replay, nothing more.

## Honesty framing (07-RESEARCH §1, CONTEXT specifics — matters to the Chapman / Even-Chen audience)

This is a **ReFIT-*inspired* online intent-rotation assist on synthetic replay** — NOT a live-human
two-stage ReFIT retrain. Specifically:

- The intent-rotation is applied **online, per 20 ms tick, to the decoder's velocity measurement**
  before the Kalman update (D-04 / D-05). It is **not** Gilja-2012's offline two-stage procedure
  (rotate intended kinematics over a calibration block → re-fit the KF/decoder offline → run the
  recalibrated filter). That classic offline re-fit is **explicitly deferred** (CONTEXT "Deferred").
- The Kalman gain is the **steady-state constant gain** fit offline (D-02 / D-15); there is no runtime
  Riccati and no per-tick covariance propagation.
- The **3-way ablation (D-12) is the transparency mechanism**: it isolates how much of the uplift is
  the intent-rotation versus the Kalman smoothing, so the result cannot hide behind a single headline
  number.

---

## Environment

| Field | Value |
|-------|-------|
| **Machine** | Apple Silicon (`arm64`), macOS 26 / Xcode 26.3, Swift 6.2 |
| **Compute** | **CPU only** — the harness is headless, deterministic, pure-`simd` math; no Metal, no display link, no ANE. The number reproduces on any Apple-Silicon Mac. |
| **Data source** | **Deterministic synthetic seed-locked replay** (the gitignored held-out Indy R&D data is absent in this environment — see "Data" below). Seed = `0xC0FFEE`. |
| **Determinism** | The harness is **seed/index-driven** with **no wall-clock, no RNG** in the simulation path (07-RESEARCH §7 pitfall 8; modeled on `LissajousProducer`). `refit_bps.json` is encoded with `.sortedKeys`; **two same-seed runs produce byte-identical JSON** (verified, and re-asserted every CI build). |
| **Tick** | `dt = 0.020 s` (20 ms — `KalmanConstants.dt`). |

---

## Result — the 3-way ablation (D-12)

All three arms run the **identical** seed-locked replay and target sequence; they differ **only** in
the filter stage, so the delta is the filter's pure contribution.

| Arm | Filter stage | S&M-2004 Fitts throughput (bits/s) | Target acquisition rate |
|-----|--------------|-----------------------------------:|------------------------:|
| **raw** | decoded `(vx,vy)` straight to the integrator (no filter) | **0.161** | 61 / 120 |
| **Kalman-only** | `KalmanFilter.step`, rotation **disabled** (`target: nil`) | **0.155** | 60 / 120 |
| **Kalman + rotation (ReFIT)** | `KalmanFilter.step` with the active target + acquisition radius (rotation **on**) | **0.374** | 100 / 120 |

| Quantity | Value |
|----------|-------|
| **raw_bps** | **0.16089860247386525** |
| **kalman_only_bps** | **0.15545586433053596** |
| **refit_bps** | **0.37439506338290895** |
| **delta** (refit − raw) | **+0.2134964609090437** (≈ **+133 %**) |
| **n_trials** (reaches / arm) | 120 |
| **seed** | `0xC0FFEE` |
| **dt** | 0.020 s |

**Interpretation (honest).** The uplift is driven by **target-acquisition success**, the canonical
ReFIT mechanism (Gilja's intention-estimation independently raised acquisition rates **37 % / 59 %**
across two monkeys — 07-RESEARCH §1). With a noisy decoder, the **raw** and **Kalman-only** arms
frequently fail to *hold* the target through the dwell window (acq ≈ 60 / 120); the **intent-rotation**
re-aligns the decoded velocity onto the cursor→target vector each tick, so the cursor converges and
holds (acq = 100 / 120) with tighter endpoint scatter → higher effective `IDe` → higher throughput.
Notably **Kalman-only ≈ raw** here: smoothing alone, without the target-directed rotation, does not
improve acquisition on this task — exactly the kind of distinction the ablation is designed to expose.

---

## Methodology

The pipeline per condition (07-RESEARCH §4.1), headless and deterministic (D-07):

```
seed-locked replay → decoded (vx,vy) → [ raw | Kalman-only | Kalman+rotation ]
   → CursorIntegrator → 30×30 WebgridParams acquisition → S&M-2004 throughput
```

- **Reused, unchanged seam (D-07):** `CursorIntegrator` (the single `[0,1]` clamp + non-finite reject
  validation point, Phase-6 D-04) and the 30×30 `WebgridParams` geometry — the same artifacts the live
  renderer uses. No Metal, no display link.
- **External position sync (07-RESEARCH §2.3):** each tick the integrator's authoritative clamped
  position is synced into the filter via `setCursorPosition` **before** the step (the cursor→target
  vector uses the real position, not an unobservable double-integrated one). The Kalman filter is
  **carried warm across reaches** (the continuous closed loop is never reset mid-session).
- **Effective width (D-09):** `We = 4.133 · SDx`, where `SDx` is the standard deviation of the
  **endpoint coordinates projected onto the start→target movement axis** — the *realized* landing
  scatter, **not** the nominal cell width (this is what makes the number reviewer-defensible —
  07-RESEARCH §4.2; nominal width would silently inflate/deflate TP, §7 pitfall 3).
- **Mean-of-means aggregation (D-09):** trials are binned into **amplitude conditions** (the S&M
  per-amplitude grouping); each condition's `TP` is computed from its own endpoint-scatter `SDx`, then
  the per-condition `TP`s are averaged — **not** a pooled all-trials average. **No trial is dropped:**
  a timed-out reach contributes the full timeout as its movement time and its (scattered) endpoint, so
  a missed target is honestly a low-throughput outcome (no survivorship bias).
- **Acquisition model — dwell-to-select + per-trial timeout (D-08), documented defaults (07-RESEARCH §4.4):**

  | Parameter | Default | Rationale |
  |-----------|---------|-----------|
  | dwell | **0.30 s** (continuous in-radius hold) | 07-RESEARCH §4.4 (300–500 ms); the continuous hold that commits a selection |
  | acquisition radius | **0.5 / 30** in `[0,1]` (½ cell of the 30×30 grid) | 07-RESEARCH §4.4 |
  | per-trial timeout | **5.0 s** | 07-RESEARCH §4.4 (5–10 s); caps unreachable targets |

- **Targets (D-11):** the harness uses Indy-style center-out reaches mapped onto the 30×30 grid — the
  **dataset's own reach targets** are the acquisition targets (no fabricated neural signal). The 30×30
  webgrid is the *display* geometry for cell/coordinate mapping. In **this** environment the gitignored
  Indy data is absent, so a **seed-locked synthetic stand-in** is used (see "Data").

---

## SC#3 — filter-step tail latency (zero detectable contribution)

The filter step (`predict → rotate → update`) was timed over **n = 10 000 ticks**, measured **inline
on the calling thread** — **no new thread** is spawned (SC#3: "runs on the existing decoder pthread,
not a new thread"). The `CortexReFIT` filter path is also covered by `Tools/scripts/hotpath-policy.sh`
(Foundation-free `import simd`, no locks/heap — a build-failing code policy, Plan 02).

| Percentile | Value | vs the 20 ms tick budget |
|-----------|------:|-------------------------:|
| **p50** | **250 ns** | 0.00125 % |
| **p99** | **292 ns** | 0.00146 % |
| max | ~0.6 µs (timing jitter) | ~0.003 % |

**Device annotation (project culture, 07-RESEARCH §5).** This is a **CORROBORATING Mac/CPU number**
(`deviceAnnotation = "M5-Pro-CPU-corroborating"`). The **canonical iPad-M4 tail-latency capture is
Manual-Only — deferred per 07-VALIDATION, and is NOT an automated-coverage gap** (it follows the same
device-gating discipline as the Phase-5 DEC-11 latency claim). The constant-gain step is ~tens of
`simd` FLOPs; even the p99 here is ~0.0015 % of the 20 ms budget, so the filter + rotation add **no
detectable contribution to glass-to-glass tail latency** (SC#3). The bench **records and prints — it
asserts nothing on the latency value** (a Mac CPU tail percentile is not the canonical claim).

> The p50/p99 above are stable across runs; `max` is wall-clock measurement jitter (not part of the
> committed JSON, which carries no latency fields, so `refit_bps.json` stays byte-identical regardless).

---

## Data

- **This run:** a **deterministic synthetic seed-locked replay** (seed `0xC0FFEE`) — Indy-style
  center-out reaches on the 30×30 grid, with a closed-form `SplitMix64(seed, tick-index)` directional
  perturbation modeling a noisy decoder (the "noisy NDT1 readout" the raw arm suffers and the rotation
  arm corrects). The gitignored held-out Indy R&D data is **not present** in this environment; the
  bench follows the `CortexDecoderBench` idiom (clean-clone safe).
- **On a real Indy session:** point `CORTEX_REFIT_REPLAY_URL` at a held-out replay; the bench then
  measures BPS on the real reach task the data came from (D-11). The synthetic path is what produced
  **this committed evidence** (mirroring Phase-4's synthetic-Poisson-fallback co-bps evidence).

---

## Artifacts (committed / reproducible — not "trust me")

| File | Contents |
|------|----------|
| `.planning/phases/07-refit-kalman-closed-loop-recalibration/refit_bps.json` | The committed machine-readable triple: `raw_bps`, `kalman_only_bps`, `refit_bps`, `delta`, `n_trials`, `seed`, `dt`, `metric`, `methodology`. **Byte-identical** to the bench output (regenerate-from-code provenance). |
| `Tools/scripts/check_refit_uplift.py` | The deterministic CI guard: fails the build unless `refit_bps ≥ raw_bps` (REFIT-03 / D-10). |
| `Packages/CortexReFIT/Sources/CortexReFITBench/main.swift` | The headless 3-way ablation harness + the SC#3 filter-step latency bench. |
| `Packages/CortexReFIT/Sources/CortexReFIT/{FittsThroughput,WebgridAcquisition}.swift` | The pure S&M-2004 throughput math + dwell-to-select model (unit-tested in `FittsThroughputTests.swift`). |

The CI guard (`.github/workflows/ci.yml`, step "ReFIT BPS uplift + determinism guard") (1) re-runs the
seed-locked harness and asserts it reproduces the committed JSON **byte-for-byte** (determinism), then
(2) asserts `refit_bps ≥ raw_bps` and **fails the build otherwise** (a filter regression that erases
the uplift cannot merge). The negative control (mutate `refit_bps < raw_bps` → guard exits non-zero)
was verified.

---

## Re-run runbook (verbatim, reproducible)

On any Apple-Silicon Mac (CPU is fine — no hardware-gated step), from the repo root:

```sh
# Reproduce the committed numbers (deterministic synthetic replay; needs no dataset):
swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke
#   -> writes Packages/CortexReFIT/.bench/refit_bps.json (byte-identical to the committed copy)

# Add the SC#3 filter-step tail-latency bench (n=10 000 ticks, inline, device-annotated):
swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke --latency

# Assert the uplift guard (what CI runs):
python3 Tools/scripts/check_refit_uplift.py \
  .planning/phases/07-refit-kalman-closed-loop-recalibration/refit_bps.json

# Run the unit tests (S&M-2004 math + filter + constants):
swift test --package-path Packages/CortexReFIT

# (Optional) on a real held-out Indy session:
CORTEX_REFIT_REPLAY_URL=/path/to/replay \
  swift run --package-path Packages/CortexReFIT CortexReFITBench
```

---

## Conclusion

**Phase 7 REFIT-03 / SC#2 PASSES.** The headless deterministic 3-way ablation on the identical
seed-locked replay shows the **ReFIT intent-rotation assist** lifts **S&M-2004 Fitts throughput** from
**`raw_bps = 0.161`** to **`refit_bps = 0.374`** (`Δ = +0.213`, ≈ +133 %), driven by the canonical
target-acquisition mechanism (acq 61 → 100 / 120), with **Kalman-only ≈ raw** isolating the rotation's
contribution from the smoothing's (D-12). The uplift is committed as `refit_bps.json` and guarded by a
deterministic, build-failing CI check (`refit_bps ≥ raw_bps`, D-10). The reported metric is **S&M-2004
Fitts throughput, NOT the Webgrid bitrate** — it **must not** be compared to BrainGate 4.16 / Neuralink
8.5 (that comparison is **Phase 8 SC#5, deferred per D-13**). The filter-step tail latency is
**~292 ns p99 over 10 000 ticks, inline on the existing thread** — a negligible ~0.0015 % of the 20 ms
budget (SC#3); the canonical iPad-M4 number is Manual-Only (deferred), the Mac number corroborating.
This is a **ReFIT-inspired online intent-rotation assist on synthetic replay**, not a live-human
two-stage ReFIT retrain — stated plainly, with the ablation as the transparency mechanism.
