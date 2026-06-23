# Phase 7: ReFIT-Kalman Closed-Loop Recalibration — Research

**Researched:** 2026-06-23
**Status:** Complete
**Method:** Main-thread browser-harness pass (PMC open-access full text) + Context7 (`scipy.linalg`) + multi-source digest (`research_topic.py`, academic tier) + control-theory derivation. Done on the main thread because the `gsd-phase-researcher` subagent is HTTP-only and cannot drive browser-harness.

> **Scope reminder.** Phase 7 covers **REFIT-01 / REFIT-02 / REFIT-03** only. PERF-01/02 (formal BrainGate-4.16 / Neuralink-8.5 leaderboard claim), PERF-03 (formal S&M-2004 methodology requirement), and SYS-06 (live 120 Hz closed-loop demo) are **Phase 8** in the traceability table — this phase *uses* the S&M-2004 method as a tool and reports absolute + relative BPS, but does not close the formal leaderboard requirement. CONTEXT.md D-13 already locks this boundary.

---

## TL;DR for the planner (read this first)

1. **The intent-rotation is dead simple math** — rotate the decoded velocity vector's *direction* fully onto the cursor→target vector while *preserving its magnitude*, gated to "target active AND cursor outside the acquisition radius." Literature-confirmed (§1). It acts on the **measurement** `z` before the Kalman update (D-05), not on the output.

2. **THE PITFALL THAT WILL BITE (§2.3):** the 6-DOF state `[px,py,vx,vy,ax,ay]` with a **velocity-only** measurement is **not observable** — position cannot be inferred from velocity measurements. A naive `scipy.linalg.solve_discrete_are` on the full 6×6 system **raises `LinAlgError` ("stable subspace could not be isolated")** or returns a non-convergent position covariance. **Resolution:** solve the steady-state gain on the observable **4-DOF `[vx,vy,ax,ay]` sub-block**, zero-pad the position rows of `K`, and **sync the position state externally** to the integrator's clamped cursor position each tick (this is exactly the last "Implementer's Discretion" bullet in CONTEXT.md). The 6-DOF *state* is retained (honors SC#1 "6-DOF state"); only the *gain* is computed on the observable block.

3. **scipy DARE uses the control form** — for the Kalman (estimation) steady-state covariance, pass the **duals**: `solve_discrete_are(a=Aᵀ, b=Hᵀ, q=Q, r=R)`. Concrete code in §3.

4. **Two different "BPS" definitions exist** (§4.3) — S&M-2004 Fitts **throughput** (`TP = IDe/MT`, bits/s) is *not* the same metric as the Neuralink/BrainGate **Webgrid bitrate** (`log2(N)·(correct−incorrect)/time`). The 4.16 / 8.5 reference numbers are Webgrid-bitrate. Phase 7 reports **S&M throughput** and the **raw→ReFIT delta on the identical seed-locked replay** — the artifact MUST name which metric it reports and MUST NOT compare its S&M-TP number directly to 4.16/8.5 (that apples-to-oranges comparison is the deferred Phase-8 claim). This is the single biggest credibility trap in the phase.

5. **The uplift is real and expected** — Gilja's intention-estimation independently raised target-acquisition rates **37% / 59%** across two monkeys (§1). A measurable `ReFIT_BPS > raw_BPS` on the fixed seed is the *expected* result; the CI guard (`ReFIT_BPS ≥ raw_BPS`) is the right shape.

---

## 1. The ReFIT intent-rotation: what it actually is (REFIT-02 / SC#1)

**Source — Gilja/Shenoy, "Intention Estimation in Brain Machine Interfaces," J Neural Eng (PMC4105020), the definitive methods dissection of ReFIT-KF:**

> *"'intention estimation' refers to training set modifications, in which the cursor velocities … are **rotated to point towards the direction of the target** and their **magnitudes are set to zero during the periods the cursor is successfully held at the target**. … These intention estimation modifications … are based on the assumption that **the [user] intends to move to the target at all times and intends to cease moving when holding on the target** to select it."*

**Quantified effect (same paper):** intention estimation *alone* (independent of the two-stage retrain) raised target-acquisition rates by **37% and 59%** in two monkeys, by improving the tuning/mutual-information of the kinematic↔neural mapping.

### What this confirms about the Phase-7 design
| CONTEXT decision | Literature backing | Verdict |
|---|---|---|
| D-05: rotation acts on the velocity, rotating it toward the target | "cursor velocities are rotated to point towards the direction of the target" | ✅ faithful |
| D-06: full direction-align, **magnitude preserved**, gated to outside acquisition radius | Gilja aligns direction; sets magnitude→0 *on hold*. Phase-7's "no rotation inside acq radius" is the online analogue of Gilja's "magnitude 0 on hold" | ✅ faithful, honest variant |
| D-04: this is an **online per-tick assist**, NOT Gilja's offline two-stage retrain | Gilja's is a **training-set** modification feeding an **offline KF re-fit**; Phase-7 applies the rotation **live** to the measurement | ✅ — and CONTEXT.md is explicit about the distinction |

**Honesty framing (matters to the Bliss Chapman / Nir Even-Chen audience):** the artifact must state plainly that this is a **ReFIT-*inspired* online intent-rotation assist on synthetic replay**, not a live-human two-stage ReFIT retrain. The 3-way ablation (D-12: raw / Kalman-only / Kalman+rotation) is the transparency mechanism that isolates the rotation's contribution from the Kalman smoothing's.

### Concrete rotation step (planner can hand this to the executor verbatim)
Given decoded velocity `z = (vx, vy)`, synced cursor position `p = (px, py)`, active target center `t`, acquisition radius `r_acq`:
```
d = t - p                       // cursor→target vector
if (target_active && |d| > r_acq && |z| > eps) {
    speed = |z|                 // preserve decoded speed (magnitude)
    z_rot = speed * (d / |d|)   // full direction-align onto cursor→target
} else {
    z_rot = z                   // no rotation: on-target hold or no target
}
```
`eps` guards a zero-velocity divide. All `simd` float ops, no allocation, no branchy hot-path surprises.

---

## 2. The 6-DOF steady-state Kalman filter (REFIT-01 / SC#1 / SC#3)

### 2.1 State, dynamics, measurement (concrete matrices)
State (CONTEXT D-01, grouped-by-derivative-order): `s = [px, py, vx, vy, ax, ay]ᵀ`. Tick `dt = 0.020 s` (20 ms).
With `I` = 2×2 identity, `0` = 2×2 zero, the **constant-acceleration** transition and **velocity-only** measurement are:

```
        ⎡ I   dt·I   ½dt²·I ⎤                       (px,py)
A (6×6)=⎢ 0   I      dt·I   ⎥        H (2×6) = [0  I  0]   ⇒  z = (vx, vy)
        ⎣ 0   0      I      ⎦                       (measures velocity only)
```

Measurement `z` = the decoded `(vx,vy)` from `NeuralDecoder.decode(_:) -> SIMD2<Float>` (fp16 widened to Float), **after** the intent-rotation of §1.

### 2.2 Steady-state constant-gain update (D-02 — the hot-path op)
The model is time-invariant linear-Gaussian, so the a-priori covariance converges and the gain `K` is **constant** — precompute it offline (§3), load it as a Swift constant. Per-tick hot path is allocation-free fixed-dim `simd`:
```
x⁻      = A · x                              // predict (kinematic propagation)
x⁻[p]   = clamped_cursor_position            // SYNC position externally (§2.3) — before rotation
z_rot   = rotate(z, toward = target − x⁻[p]) // §1 intent-rotation on the measurement
x       = x⁻ + K · (z_rot − H · x⁻)          // update (constant gain)
emit CursorVelocity(vx = x[vx], vy = x[vy])  // 2-vector output to VelocityRing
```
No per-tick covariance propagation, no Riccati at runtime, zero heap — trivially inside the 20 ms budget, satisfies `hotpath-policy.sh` (Foundation-free `import simd`).

### 2.3 ⚠ Observability pitfall (the load-bearing finding)
**Velocity-only measurement ⇒ position is unobservable.** The position block of the state is a pure integrator driven by the velocity estimate; no measurement ever corrects it, so its error covariance grows without bound and the **full 6×6 DARE has no stabilizing solution** (`scipy` will raise `LinAlgError`, or any iterative Riccati will not converge on the position block).

**Resolution (rigorous + honest + matches CONTEXT's discretion bullet):**
- Compute the steady-state gain on the **observable 4-DOF sub-block** `[vx,vy,ax,ay]` (velocity + acceleration), which *is* observable from a velocity measurement (observability matrix `[H_obs; H_obs·A_obs]` has full rank 4).
- Embed the resulting `K_obs` (4×2) into the full **6×2 `K` with zero rows for `px,py`** — position receives no measurement correction (correct: it isn't measured).
- **Externally sync** the position state each tick to the authoritative clamped cursor position: in the live path, fed back from `CursorIntegrator` (which owns velocity→screen-position and the `[0,1]` clamp, Phase-6 D-04); in the headless BPS harness, the integrator's position is known directly. This keeps `px,py` usable for the rotation geometry without divergence.
- The 6-DOF *state vector* is retained end-to-end (honors SC#1 "6-DOF state Kalman filter"); only the *gain derivation* uses the observable block.

Observable sub-block matrices (for the Decoder/ solve):
```
A_obs (4×4) = ⎡ I   dt·I ⎤      H_obs (2×4) = [ I   0 ]
              ⎣ 0   I    ⎦
```

---

## 3. Offline gain fitting in `Decoder/` (D-15 — the `uv` subsystem)

**Run `uv sync --project Decoder --extra dev` first** (pytest/ruff are an `--extra dev`; bare `uv run` dies with a misleading `No module named numpy`). `coremltools` is pinned at **9.0** — do not bump.

### 3.1 scipy DARE → steady-state Kalman gain (Context7-verified API)
`scipy.linalg.solve_discrete_are(a, b, q, r, e=None, s=None, balanced=True)` solves the **control-form** DARE
`AᴴXA − X − (AᴴXB)(R + BᴴXB)⁻¹(BᴴXA) + Q = 0`.
The Kalman steady-state **a-priori** covariance is the **dual** — substitute `a→Aᵀ`, `b→Hᵀ`:
```python
import numpy as np
from scipy import linalg as la

dt = 0.020
I2 = np.eye(2)
A_obs = np.block([[I2, dt*I2],
                  [np.zeros((2,2)), I2]])          # 4×4 on [vx,vy,ax,ay]
H_obs = np.block([[I2, np.zeros((2,2))]])          # 2×4  (measures velocity)

# Q_obs (4×4 process noise) and R (2×2 measurement noise) fit from Indy residuals (§3.2)
P_pred = la.solve_discrete_are(A_obs.T, H_obs.T, Q_obs, R)   # a-priori cov (4×4)
S      = H_obs @ P_pred @ H_obs.T + R
K_obs  = P_pred @ H_obs.T @ la.inv(S)              # steady-state gain (4×2)

K = np.zeros((6, 2)); K[2:6, :] = K_obs            # zero position rows -> 6×2
```
Sanity assertion (must hold): the closed-loop `A_obs (I − K_obs H_obs)` is Schur-stable (all eigenvalues `|λ|<1`). Emit `A` (6×6), `H` (2×6), `K` (6×2) — plus `Q`,`R` for provenance — as committed Swift constants (D-15). Float layout is implementer's discretion (§ CONTEXT.md).

### 3.2 Fitting Q and R from held-out Indy (data-grounded)
- **R** (2×2 measurement noise): covariance of the **decoder residual** `e_k = z_k(decoded) − v_k(true Indy velocity)` on held-out trials — i.e., how noisy the NDT1 velocity readout is. This is the honest measurement-noise model.
- **Q** (process noise): a discrete **white-noise-jerk** model on `[v,a]` is the standard defensible choice; scale `σ_jerk²` from the empirical distribution of true-acceleration increments on Indy. Alternatively tune `Q` so the **innovation sequence** `(z_rot − H·x⁻)` is approximately white on held-out replay. Either is reviewer-defensible; document which, and the seed/split, in the artifact.
- The fit + Riccati solve land as a script or test under `Decoder/` (implementer's discretion); emit a single generated Swift constants file consumed by `CortexReFIT`.

> Note: `solve_discrete_lyapunov(a, q)` (also Context7-verified, `AXAᴴ − X + Q = 0`) is the alternative if you ever need the *open-loop* steady-state covariance — not needed here, but it's the tool if a reviewer asks "what's the prior covariance without measurements."

---

## 4. The S&M-2004 BPS harness (REFIT-03 / SC#2)

### 4.1 Headless deterministic closed-loop (D-07)
Mirror `CortexDecoderBench/main.swift`: a pure-Swift executable, **no Metal / no display link**. Pipeline per condition:
`Indy held-out replay → NeuralDecoder.decode → [ raw | Kalman-only | Kalman+rotation ] → CursorIntegrator → 30×30 WebgridParams acquisition → S&M-2004 throughput`. Reuse `CursorIntegrator` + `WebgridParams` unchanged. Determinism contract = `LissajousProducer` (seed/`t`-only, no clock/RNG) so the same seed yields **bit-identical** BPS.

### 4.2 Soukoreff & MacKenzie 2004 throughput (effective-width method, D-09)
Per the ISO 9241-9 standard procedure:
```
TP  = IDe / MT                       (bits/second; the "BPS")
IDe = log2( De / We + 1 )            (effective index of difficulty, Shannon form)
We  = 4.133 · SDx                    (effective width; 4.133 = √(2πe), the 96%-spread constant)
```
- `De` = mean **effective** movement distance (actual start→endpoint), `MT` = mean movement time per trial.
- `SDx` = standard deviation of the **endpoint coordinates projected onto the task (movement) axis** — the scatter of where the cursor actually landed, NOT the nominal target width. Using effective width (adjusting for the speed-accuracy tradeoff the subject actually struck) is precisely what makes the number defensible.
- **Aggregate by mean-of-means** across conditions/target-amplitudes (compute per-condition `TP`, then average), not by pooling all trials — the standard's recommended aggregation.

### 4.3 ⚠ Two different "BPS" metrics — name the one you report
| Metric | Formula | Who uses it | Phase-7 role |
|---|---|---|---|
| **S&M-2004 Fitts throughput** | `TP = IDe/MT` (bits/s) | ISO 9241-9 pointing eval | **This is what Phase 7 reports** (SC#2, PERF-03 method) |
| **Webgrid bitrate** | `log2(N)·(correct − incorrect)/time` | Neuralink / BrainGate leaderboard | The 4.16 / 8.5 reference numbers — **Phase-8 comparison, deferred (D-13)** |

These are **numerically different scales**; do not compare a S&M-TP value to 4.16/8.5. The artifact's framing: report **absolute S&M-TP for raw/Kalman-only/Kalman+rot** + the **raw→ReFIT delta on the identical seed-locked replay** (the delta is the filter's pure contribution), with a one-line note that the formal leaderboard comparison (matching Webgrid-bitrate) is Phase-8 SC#5.

### 4.4 Acquisition model (D-08, implementer's discretion — sensible defaults to document)
Dwell-to-select (cursor held inside target cell for a fixed dwell window) + per-trial timeout (caps unreachable targets). Suggested defaults to record: dwell ≈ **300–500 ms**, acquisition radius = **½ cell** of the 30×30 grid, per-trial timeout ≈ **5–10 s**. Targets = the Indy dataset's own reach targets (D-11 — no fabricated neural signal); the 30×30 webgrid is the *display* geometry for cell/coordinate mapping.

### 4.5 Committed artifact + CI guard (D-10)
`07-bps-evidence.md` (prose, methodology, honesty framing, 3-way ablation table) + machine-readable JSON (`raw_bps`, `kalman_only_bps`, `refit_bps`, `delta`, `n_trials`, `seed`, `dt`, methodology notes). Short-budget CI smoke asserts **`refit_bps ≥ raw_bps` on the fixed seed** — deterministic (non-flaky), traps filter regressions structurally. Mirrors Phase-4's `co-bps > null` gate (`04-training-evidence.md`).

---

## 5. SC#3 — zero detectable tail-latency contribution

Reuse `LatencyHistogram` (CortexDecoder). Measure the **filter-step** wall time (`predict → rotate → update`) per tick over **n ≥ 10 000** ticks on the existing decoder pthread (`QOS_CLASS_USER_INTERACTIVE`, never a new thread — SC#3). Report p50/p99/max; assert the filter p99 is a negligible fraction of the 20 ms budget (the constant-gain op is ~tens of `simd` FLOPs → sub-microsecond; budget is 20 ms). The `CortexReFIT` package MUST be covered by `Tools/scripts/hotpath-policy.sh`. **Device note (per project culture):** the canonical tail number is an iPad-M4 / ANE-adjacent claim; a Mac/M5-Pro measurement is **corroborating** — annotate the device and do not present a Mac number as the canonical claim (mirrors the Phase-5 DEC-11 / device-gating pattern). Pure-CPU `simd` here is far less device-sensitive than ANE placement, but keep the annotation discipline.

---

## Validation Architecture
### (§6 — drives VALIDATION.md / Nyquist Dimension 8)

**Measurement-adequacy principle:** every load-bearing number must be sampled densely enough to be stable, and every requirement must map to a deterministic, re-runnable check.

| What is validated | REQ / SC | Method | Sampling adequacy (the "Nyquist" bar) | Gate type |
|---|---|---|---|---|
| Kalman step numerical correctness | REFIT-01 | Unit test vs a reference `numpy` constant-gain implementation on fixed inputs; assert `‖x_swift − x_ref‖ < tol` | A handful of hand-checked vectors + ≥ 1 multi-step trajectory (≥ 50 ticks) so propagation error is exercised, not just one step | Automated (CI) |
| Steady-state gain is valid | REFIT-01 | Offline: assert closed-loop `A_obs(I−K_obs H_obs)` is Schur-stable (`max|λ|<1`); assert `solve_discrete_are` ran on the **observable** block (full 6×6 would raise) | n/a (algebraic) | Automated (Decoder/ test) |
| Intent-rotation semantics | REFIT-02 | Unit tests: (a) outside r_acq → output direction == cursor→target dir, magnitude == ‖z‖; (b) inside r_acq → output == z (no rotation); (c) no active target → output == z; (d) zero-velocity guard | All 4 gating branches covered + magnitude-preservation asserted to float tol | Automated (CI) |
| BPS uplift over raw NDT1 | REFIT-03 / SC#2 | Headless harness, identical seed-locked Indy replay, 3-way ablation; assert `refit_bps ≥ raw_bps` | `n_trials` large enough that `We = 4.133·SDx` is stable — **≥ ~100 acquisition trials per condition** (SDx of endpoint scatter needs enough endpoints; document the n and the seed). Provide a short-budget CI variant (smaller n) that still preserves the `≥` ordering | Automated (CI smoke, fixed seed) |
| Determinism | REFIT-03 | Run harness twice on same seed → bit-identical JSON | 2 runs (reproducibility is binary) | Automated (CI) |
| Filter tail-latency negligible | SC#3 | `LatencyHistogram` over filter step | **n ≥ 10 000 ticks** (tail p99 needs ≥10k samples to be meaningful — same bar as the decoder bench) | Automated bench; device-annotated (M5-Pro corroborating, iPad-M4 canonical) |
| Hot-path discipline | SC#3 | `hotpath-policy.sh` over `CortexReFIT` | static (full-file scan) | Automated (CI, build-failing) |

**Coverage map:** REFIT-01 → rows 1–2; REFIT-02 → row 3; REFIT-03/SC#2 → rows 4–5; SC#3 → rows 6–7. No requirement is left without a deterministic, re-runnable check. iPad-M4 canonical latency capture is **Manual-Only** (deferred per project device-checkpoint culture), not an automated-coverage gap.

---

## 7. Pitfalls & gotchas (condensed)

1. **Full 6×6 DARE will fail** — solve on the observable `[v,a]` block; zero-pad K's position rows; sync position externally (§2.3). *This is the #1 thing that will waste an executor's time if missed.*
2. **Metric confusion** — S&M-TP ≠ Webgrid-bitrate; never compare the Phase-7 TP to 4.16/8.5 (§4.3).
3. **Effective width, not nominal** — `We = 4.133·SDx` from endpoint scatter; using nominal target width silently inflates/deflates TP and is not reviewer-defensible (§4.2).
4. **Rotation gating** — must be off inside the acquisition radius and when no target is active, or the cursor "snaps" and the BPS is meaningless/overstated (D-06).
5. **Position sync ordering** — sync position *before* computing the rotation's cursor→target vector, and use the integrator's **clamped** position (the `[0,1]` validation point is `CursorIntegrator`, Phase-6 D-04 — don't add a second clamp in `CortexReFIT`; just emit finite values).
6. **Seam types location (D-14)** — `CursorVelocity` / `VelocityRing` currently live in `CortexRender`. Planner decides: keep a `CortexRender` dependency from `CortexReFIT`, or hoist the seam types to `CortexCore`. Do **not** re-architect the seam — the Phase-6 comments declare it a contract.
7. **`uv` extra-dev** — `uv sync --project Decoder --extra dev` before any Decoder/ tooling; `coremltools` stays at 9.0.
8. **Determinism** — no clock/RNG in the harness; seed everything; the `LissajousProducer` closed-form pattern is the model.

---

## 8. Sources

- **Gilja/Shenoy et al., "Intention Estimation in Brain Machine Interfaces,"** *J Neural Eng* — PMC4105020. https://pmc.ncbi.nlm.nih.gov/articles/PMC4105020/ (intent-rotation definition + 37%/59% effect; pulled full text via browser-harness).
- **Gilja et al. 2012,** "A high-performance neural prosthesis enabled by control algorithm design," *Nat Neurosci* — PubMed 23160043. https://pubmed.ncbi.nlm.nih.gov/23160043/ (the ReFIT-KF source; 4.16→8.5 BPS provenance).
- **Pandarinath et al. 2017,** "High performance communication by people with paralysis using an intracortical BCI," *eLife* 18554. https://elifesciences.org/articles/18554 (BrainGate Webgrid bitrate context).
- **Even-Chen / comparison of intention-estimation methods for decoder calibration** — PMC6043406. https://pmc.ncbi.nlm.nih.gov/articles/PMC6043406/ (corroborates intention-estimation as the dominant ReFIT gain).
- **`scipy.linalg.solve_discrete_are` / `solve_discrete_lyapunov`** — Context7 `/websites/scipy_doc_scipy`. https://docs.scipy.org/doc/scipy/reference/generated/scipy.linalg.solve_discrete_are.html (DARE signature, control-form definition, verified example).
- **Soukoreff & MacKenzie 2004,** "Towards a standard for pointing device evaluation, perspectives on 27 years of Fitts' law research in HCI," *Int. J. Human-Computer Studies* — ISO 9241-9 effective-throughput method (`We = 4.133·SD`, mean-of-means). (Methodology already locked in CONTEXT.md D-09.)

---

*Phase: 07-refit-kalman-closed-loop-recalibration*
*Research method: main-thread browser-harness + Context7 + control-theory derivation (subagent researcher skipped — it is HTTP-only and cannot drive browser-harness)*
