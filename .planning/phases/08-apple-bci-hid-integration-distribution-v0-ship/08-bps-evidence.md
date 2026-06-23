# Phase 8 PERF-01/02/03 Evidence — Webgrid information-rate BPS on synthetic Indy replay

**Date:** 2026-06-23
**Result:** ✅ **MEASURED & REPORTED HONESTLY** — on the fixed seed-locked synthetic replay the
**ReFIT (Kalman + intent-rotation)** Webgrid information-rate bitrate is
**`refit_webgrid_bps = 1.953 BPS`** (raw `1.292`, Kalman-only `1.183`), measured with the standard
Neuralink/Bliss-Chapman formula **`B = max(0, log2(N) × (Sc − Si) / t)`** over the 30×30 grid
(**N = 900** incl. the delete/cancel key). This number is reported **on synthetic replay** with the
explicit gap toward the Neuralink P1 verified peak (8.5 BPS) — **it was NOT engineered toward the
BrainGate 4.16 reference** (D-12). The Phase-7 **S&M-2004 Fitts-TP cross-check is retained** alongside
it (PERF-03).

> **PERF-01/02/03 / SC#5 (closes P7 D-13):** P7 deferred the 4.16/8.5 comparison precisely because the
> S&M-2004 Fitts throughput (0.374) is **not** the Webgrid bitrate. This phase adds the
> **leaderboard-comparable** Webgrid information-rate BPS — `log2(N)`-normalized so a 30×30 result is
> commensurate with BrainGate's 6×6 — measured in the **same deterministic headless harness**, and
> reports the **honest** synthetic-replay number with the gap to 8.5 documented (PERF-02). The metric
> is **device-independent / algorithmic** (no hardware gate — D-13, mirrors REFIT-03).

---

## ⚠ Which metric this is — and the honesty disclosures (load-bearing for the Chapman / Even-Chen audience)

This evidence carries **two distinct metrics** on the identical seed-locked replay:

1. **The Webgrid information-rate bitrate** — the **leaderboard-comparable** metric:

   ```
   B = max(0, log2(N) × (Sc − Si) / t)     bits/second
   ```
   - **N = 900** — the selectable-target count of the 30×30 webgrid **including the delete/cancel
     key** (08-RESEARCH §6). `log2(900) ≈ 9.81` bits/correct-selection; this `log2(N)` normalization
     is exactly what makes a 30×30 result comparable to BrainGate's 6×6 (the 4.16 reference number).
   - **Sc** = correct selections (Webgrid HITs), **Si** = incorrect selections, **t** = elapsed seconds.
   - **The `max(0, …)` clamp is MANDATORY** (08-RESEARCH §0.4 — CONTEXT D-11 omitted it): a
     net-negative selection count must read as 0 bits/s, never a negative bitrate.

   > **Disclosure — the `formula` string is a pin, not the source of truth.** The literal
   > `B = max(0, log2(N)*(Sc-Si)/t)` written into `webgrid_bps.json` (and asserted by `bps-policy.sh`)
   > is a **human-readable DISCLOSURE pinned against the JSON** — it is **not** the executed code path.
   > The executed math is `Swift.max(0, WebgridBPS.targetBits(n:) · net / seconds)` in `WebgridBPS.swift`,
   > and the **`WebgridBPSTests` unit tests** (Test 1 = clean-run value, Test 2 = the clamp bites) are
   > the **real correctness guard**. The string pin only catches a stale/hand-edited JSON drifting from
   > the documented formula.

2. **The S&M-2004 ISO 9241-9 Fitts throughput** (`TP = IDe/MT`, effective-width) — the **secondary
   cross-check** carried forward unchanged from Phase 7 (PERF-03). This is a **different metric** from
   the Webgrid bitrate; the two are emitted side-by-side and named distinctly (`WebgridBPS` vs
   `FittsThroughput`).

### MANDATORY Si (incorrect) disclosure — Si is STRUCTURALLY 0, so the BPS is an UPPER-BOUND (D-12 / T-08-05-07)

The acquisition harness this metric is built on — `WebgridAcquisition.runTrial(positions:target:)` — is a
**single-target dwell-to-select** model: it returns `TrialResult(acquired: Bool, …)` where
`acquired = true` is a **HIT** (a correct selection, Sc) and `acquired = false` is a **TIMEOUT**. There
is **no "dwell completed on a WRONG cell" outcome** — the harness **cannot drive Si > 0**. Therefore
**Si is structurally 0**, and `webgrid_bps.json` records this verbatim:

```
incorrect_model = "none — single-target dwell-to-select; Si structurally 0; BPS is upper-bound"
```

A silent bare `incorrect: 0` would read to a reviewer as "**measured** zero errors" when it actually
means "the harness **structurally cannot** produce an error." That over-claim is **forbidden** (D-12).
The reported BPS is consequently the **optimistic UPPER-BOUND** reading (`B = log2(N)·Sc/t`). No RNG /
non-deterministic miss model was introduced (that would break the D-13 byte-identical guarantee); the
honest disclosure is the chosen path (option (a) of the plan). The `max(0, …)` clamp + `WebgridBPSTests`
Test 2 remain the formula's correctness guard regardless of Si.

### Honest framing — synthetic replay, NOT a live-human retrain; NOT tuned toward 4.16

- This is a **synthetic Indy replay** number (a seed-locked deterministic stand-in for the gitignored
  held-out Indy data) — **NOT a live-human two-stage ReFIT retrain**. It is the honest software number
  that *sets up* the live claim, not the live claim itself (the same instrumentation-honesty framing as
  ANE-eligible-vs-placement and software-timed-vs-photodiode elsewhere in the project).
- The harness was **NOT engineered/tuned toward ≥ 4.16** as a pass bar. Doing so would game the metric
  and violate the project's instrumentation-honesty ethos (the whole thesis for the Bliss Chapman / Nir
  Even-Chen audience). **The number is recorded as whatever it honestly is** — here **1.953 BPS on the
  ReFIT arm**, which is **below** the 4.16 BrainGate reference and **6.55 BPS short** of the 8.5 peak.
  That honest gap is the point (PERF-02), not a failure to hide.

---

## Environment

| Field | Value |
|-------|-------|
| **Machine** | Apple Silicon (`arm64`), macOS 26 / Xcode 26.3, Swift 6.2.4 |
| **Compute** | **CPU only** — the harness is headless, deterministic, pure-`simd` math; no Metal, no display link, no ANE. **Device-independent** (D-13) — the number reproduces on any Apple-Silicon Mac, so no hardware gate is needed (unlike the latency claims). |
| **Data source** | **Deterministic synthetic seed-locked replay** (the gitignored held-out Indy R&D data is absent here — see "Data" below). Seed = `0xC0FFEE`. |
| **Determinism** | The harness is **seed/index-driven** with **no wall-clock, no RNG** in the simulation path (08-RESEARCH §6; modeled on `LissajousProducer`). `webgrid_bps.json` is encoded with `.sortedKeys`; **two same-seed runs produce byte-identical JSON** (verified, and re-asserted by `bps-policy.sh` run-twice + every CI build). |
| **Tick** | `dt = 0.020 s` (20 ms — `KalmanConstants.dt`). |

---

## Result — Webgrid BPS + Fitts-TP per arm (the 3-way ablation, identical seed-locked replay)

All three arms run the **identical** seed-locked replay and target sequence; they differ **only** in
the filter stage, so the delta is the filter's pure contribution. Both metrics are computed from the
**same** per-trial acquisition outcomes.

| Arm | Filter stage | **Webgrid BPS** (leaderboard metric) | S&M-2004 Fitts-TP (cross-check) |
|-----|--------------|-------------------------------------:|--------------------------------:|
| **raw** | decoded `(vx,vy)` straight to the integrator (no filter) | **1.292** | 0.161 |
| **Kalman-only** | `KalmanFilter.step`, rotation **disabled** (`target: nil`) | **1.183** | 0.155 |
| **Kalman + rotation (ReFIT)** | `KalmanFilter.step` with the active target + acquisition radius (rotation **on**) | **1.953** | 0.374 |

| Quantity (Webgrid, ReFIT arm) | Value |
|-------------------------------|-------|
| **refit_webgrid_bps** | **1.953047883714651** |
| **raw_webgrid_bps** | **1.292123144105848** |
| **kalman_only_webgrid_bps** | **1.183000907045892** |
| **N (selectable targets)** | **900** (30×30 incl. the delete/cancel key) |
| **Sc (correct = HITs)** | **103** |
| **Si (incorrect)** | **0** — structurally (see the disclosure above; BPS is an upper-bound) |
| **t (elapsed seconds)** | **517.56** (sum of per-trial movement times across the arm's reaches) |
| **seed** | `0xC0FFEE` |

| Leaderboard reference (report honestly, NOT a pass bar — D-12) | Webgrid BPS |
|----------------------------------------------------------------|------------:|
| **Cortex ReFIT (synthetic Indy replay, THIS evidence)** | **1.953** |
| BrainGate 6×6 (Pandarinath 2017) | 4.16 |
| **Neuralink P1 (Noland Arbaugh) verified peak** | **8.5** |

**The honest gap (PERF-02):** the ReFIT Webgrid BPS of **1.953** is **2.21 BPS below** the BrainGate
6×6 4.16 reference and **6.55 BPS short** of the Neuralink P1 8.5 verified peak. This gap is expected
and stated plainly: Cortex's number is on a **synthetic** seed-locked replay through a **noisy
synthetic decoder** (not a live human practicing on the task with a two-stage ReFIT retrain), and the
Sc/t accounting reflects the harness's dwell-to-select acquisition over 120 reaches/arm — not a human
free-typing on Webgrid for minutes. The path toward 8.5 is the **live-human two-stage ReFIT retrain on
real electrode data** (out of scope for v0; the synthetic-replay number is the honest v0 software
artifact that the v1 work builds on).

### Note on the two acquisition counts (transparency)

The Webgrid `Sc = 103` uses the authoritative `TrialResult.acquired` HIT flag. The Phase-7 Fitts-TP
debug line reports `acq = 100/120` for the ReFIT arm because it counts HITs whose movement time is
**strictly before** the timeout (`movementTime < timeout − 1e-9`); **3** reaches satisfy the dwell
**exactly at the final allowed tick** (`movementTime == 5.0 s`, the timeout budget) and so are counted
as HITs by the `acquired` flag (Webgrid Sc) but fall outside the strict-before-timeout Fitts predicate.
Both counts are honest; they use different predicates over the same trials. The Webgrid Sc correctly
uses the dwell-satisfied flag.

---

## Methodology

The pipeline per arm (08-RESEARCH §6), headless and deterministic (D-13):

```
seed-locked replay → decoded (vx,vy) → [ raw | Kalman-only | Kalman+rotation ]
   → CursorIntegrator → 30×30 WebgridAcquisition dwell-to-select → { Webgrid BPS, S&M-2004 Fitts-TP }
```

- **Sc / Si / t accounting (08-RESEARCH §6):** a "selection" = a cursor **dwell** satisfied in a cell.
  **Sc** = HITs (the dwell completed on the target cell), **t** = total elapsed across the arm's
  reaches (the sum of per-trial movement times — a HIT contributes its movement time, a TIMEOUT
  contributes the full timeout). **Si = 0 structurally** (the single-target harness has no wrong-cell
  outcome — disclosed above, the BPS is an upper-bound).
- **N = 900 (08-RESEARCH §6):** the 30×30 webgrid's selectable-target count **including** the
  delete/cancel cell. `WebgridBPS.gridTargetCount(rows: 30, cols: 30) = 900`.
- **Reused, unchanged seam:** `CursorIntegrator` (the single `[0,1]` clamp + non-finite reject) and the
  30×30 `WebgridAcquisition` geometry — the **same artifacts** the Phase-7 ablation and the live
  renderer use. No Metal, no display link. The Webgrid BPS is computed from the **same** per-trial
  acquisition outcomes that produce the Fitts-TP — so both metrics describe the identical replay.
- **Additive change (T-08-05-05):** the existing `refit_bps.json` write is **byte-for-byte unchanged**
  (verified — see "Artifacts") so the Phase-7 CI byte-identical + uplift guard still passes. The
  Webgrid BPS goes into a **separate** `webgrid_bps.json`.
- **Acquisition model — dwell-to-select + per-trial timeout, documented defaults (07-RESEARCH §4.4):**

  | Parameter | Default | Rationale |
  |-----------|---------|-----------|
  | dwell | **0.30 s** (continuous in-radius hold) | the continuous hold that commits a selection |
  | acquisition radius | **0.5 / 30** in `[0,1]` (½ cell of the 30×30 grid) | 07-RESEARCH §4.4 |
  | per-trial timeout | **5.0 s** | caps unreachable targets |

---

## Data

- **This run:** a **deterministic synthetic seed-locked replay** (seed `0xC0FFEE`) — Indy-style
  center-out reaches on the 30×30 grid, with a closed-form `SplitMix64(seed, tick-index)` directional
  perturbation modeling a noisy decoder. The gitignored held-out Indy R&D data is **not present** in
  this environment; the bench follows the `CortexDecoderBench` clean-clone-safe idiom.
- **On a real Indy session:** point `CORTEX_REFIT_REPLAY_URL` at a held-out replay; the bench then
  measures BPS on the real reach task the data came from. The synthetic path is what produced **this
  committed evidence** (mirroring Phase-4's synthetic-Poisson-fallback co-bps evidence and the Phase-7
  Fitts-TP evidence).

---

## Artifacts (committed / reproducible — not "trust me")

| File | Contents |
|------|----------|
| `.planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/webgrid_bps.json` | The committed Webgrid-BPS evidence: `raw/kalman_only/refit_webgrid_bps`, the `raw/refit_fitts_tp` cross-check, `n_targets` (900), the `formula` disclosure string, the `incorrect_model` Si disclosure, `correct`/`incorrect`/`seconds`, `seed`, the `reference_peak_bps`/`brain_gate_6x6_bps` anchors, and the synthetic-vs-live `caveat`. **Byte-identical** to the bench output (regenerate-from-code provenance). |
| `Packages/CortexReFIT/Sources/CortexReFIT/WebgridBPS.swift` | The pure `B = max(0, log2(N)·(Sc−Si)/t)` math (the **executed** source of truth; unit-tested in `WebgridBPSTests.swift`). |
| `Packages/CortexReFIT/Sources/CortexReFITBench/main.swift` | The extended 3-way ablation emitting **both** the Webgrid BPS and the S&M-2004 Fitts-TP per arm; the `refit_bps.json` write is unchanged. |
| `Tools/scripts/bps-policy.sh` | The structural + determinism gate: asserts the `Swift.max(0,` clamp + `log2` in `WebgridBPS.swift`, the `formula` + `n_targets` 900 in the JSON, and **run-twice byte-identical** `webgrid_bps.json` (D-06/D-13); ships a `--self-test` proving the clamp-strip + formula-strip negative controls bite. |
| `.planning/phases/07-refit-kalman-closed-loop-recalibration/refit_bps.json` | The Phase-7 Fitts-TP artifact — **LEFT INTACT** (the Webgrid BPS is additive; `diff` against the regenerated bench output exits 0). |

The CI gate (`.github/workflows/ci.yml`, step "Webgrid BPS structural + determinism gate") runs
`./Tools/scripts/bps-policy.sh` then `--self-test`, placed **after** the intact Phase-7 ReFIT guard.

---

## Re-run runbook (verbatim, reproducible)

On any Apple-Silicon Mac (CPU is fine — no hardware-gated step), from the repo root:

```sh
# Reproduce the committed Webgrid BPS + Fitts-TP (deterministic synthetic replay; needs no dataset):
swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke
#   -> writes Packages/CortexReFIT/.bench/{refit_bps.json, webgrid_bps.json} (byte-identical to committed)

# Run the unit tests (the REAL formula correctness guard + the clamp):
swift test --package-path Packages/CortexReFIT --filter WebgridBPSTests

# Assert the structural + determinism gate (what CI runs) + its negative-control self-test:
bash Tools/scripts/bps-policy.sh
bash Tools/scripts/bps-policy.sh --self-test

# Confirm the Phase-7 guard is intact (refit_bps.json unchanged):
diff Packages/CortexReFIT/.bench/refit_bps.json \
     .planning/phases/07-refit-kalman-closed-loop-recalibration/refit_bps.json   # exits 0
```

---

## Conclusion

**Phase 8 PERF-01/02/03 satisfied — honestly.** The deterministic headless harness now emits the
standard Neuralink/Bliss-Chapman **Webgrid information-rate BPS** (`B = max(0, log2(N)·(Sc−Si)/t)`,
N = 900) alongside the retained **S&M-2004 Fitts-TP cross-check** (PERF-03), measured on the identical
seed-locked synthetic replay, byte-identical across runs (D-13). The ReFIT arm achieves
**1.953 Webgrid BPS** — reported **honestly** with the explicit gap (2.21 BPS below the BrainGate 6×6
4.16 reference, 6.55 BPS short of the Neuralink P1 8.5 peak, PERF-02), on **synthetic** Indy replay
(NOT a live-human two-stage ReFIT retrain), and **NOT tuned toward 4.16** as a pass bar (D-12). **Si is
structurally 0** (the single-target dwell-to-select harness has no mis-selection path), **disclosed**
as `incorrect_model` in both the JSON and this doc — so the reported BPS is an honest **upper-bound**,
not a silent "measured zero errors." The `max(0, …)` clamp is mandatory and unit-tested
(`WebgridBPSTests` Test 2), the Phase-7 `refit_bps.json` + its CI guard are **left intact** (additive),
and the structural + run-twice-determinism `bps-policy.sh` gate (with a biting self-test) guards it all
in CI. The leaderboard-comparable Webgrid bitrate is the metric; the Fitts-TP is the cross-check — the
P7 D-13 deferral is closed correctly.
