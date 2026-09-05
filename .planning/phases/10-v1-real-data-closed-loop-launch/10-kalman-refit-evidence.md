# Phase 10 RD-07 evidence: the ReFIT-Kalman gain, re-fit on the real held-out residual

**Date:** 2026-09-05 (Plan 10-03), **re-fit the same day** on the amended workspace box (see the
banner below). The measurement conventions were fixed in `10-PREREGISTRATION.md` sections 3, 4 and
5, committed before the first run and before any number in this file existed.
**Result:** `R = diag(0.15044900, 0.08920892)` and `sigma_jerk_sq = 6048.884948`, both in
grid-units per second, fit from 14,600 held-out 20 ms bins of `indy_20160630_01`. The generated
`KalmanConstants.swift` provenance header now reads `noise source = indy-heldout`; it read
`noise source = default` in every commit before this one. Measured on an Apple M5 Pro, CPU only.

## Re-fit 2026-09-05: the corrected workspace box

**Why it was re-fit.** `10-PREREGISTRATION` section 3 defined the workspace box by the line
`cursor_mm = 10.0 * planar_cm`, and this fit implemented that literally. Plan 10-01, which authored
section 3, had boxed the session's RECORDED `cursor_pos` track instead and published its reference
number on that box. The two are different boxes, and the user resolved the conflict on 2026-09-05 in
favour of the recorded track, which is the only one of the two that contains BOTH tracks: 13 of the
session's 365,809 recorded cursor samples fall outside the finger-derived box, and 0 fall outside the
recorded-cursor box. Section 3a records the amendment. This fit was re-run on the corrected box, so
that `k` here and `acquisition_radius_mm` in every other Phase-10 artifact describe the same square.

**What moved.** `side_mm` 171.0725351294064 to **171.68196243849025**, so
`k = 10 / side_mm` moved by 0.35 percent and every grid-unit quantity moved by `k^2`, which is
**-0.7087 percent** exactly.

| Quantity | First fit (superseded box) | Re-fit (recorded-cursor box) |
|---|---|---|
| `side_mm` | 171.0725351294064 | **171.68196243849025** |
| `grid_units_per_cm` (`k`) | 0.05845474 | **0.05824724** |
| `R[0,0]`, (grid-units/s)^2 | 0.15152282 | **0.15044900** |
| `R[1,1]`, (grid-units/s)^2 | 0.08984564 | **0.08920892** |
| `R` off-diagonal | -0.03168725 | **-0.03146268** |
| `sigma_jerk_sq` | 6092.058703 | **6048.884948** |
| Residual RMS, grid-units/s | 0.389284, 0.299734 | **0.387902, 0.298670** |
| Closed-loop spectral radius | 0.818794 | **0.818794** (unchanged) |
| `K`, as `Float` | see below | **bit-identical** |

**What did NOT move, and why that is not a coincidence.** `R` and `Q` both scale by exactly `k^2`,
and the steady-state Kalman gain is invariant under a common positive scaling of the pair: `P` scales
by `k^2` and it cancels in `K = P H'(H P H' + R)^-1`. So the re-fit changed `K` only in the last one
or two digits of its float64 decimal repr, and all four non-zero entries round to the SAME `Float`
(`0.32957715`, `0.36582625`, `3.2835786`, `4.147321`, verified bitwise). The shipped filter's runtime
behavior is therefore unchanged by the re-fit, `rho` is unchanged, and the two synthetic
byte-identity gates Plan 10-05 owns are exactly as red as Plan 10-03 left them, no more.

Every physical quantity is likewise unchanged, because a cm/s number does not depend on the box: the
residual RMS is 6.6596 and 5.1276 cm/s before and after, the residual correlation is -0.2716 before
and after, and the held-out R2 is +0.144602 before and after.

**Nothing was tuned.** The re-fit is the same code, the same seed, the same checkpoints and the same
14,600 rows, with one input constant corrected. The direction of the change was fixed by arithmetic
before the run: `k^2` had to be 0.99291311, and R had to fall by 0.7087 percent. It did.

**What this is not.** It is not a performance claim. A gain fit from real residuals is a gain fit
from real residuals; whether it decodes better is measured in Plans 10-05 and 10-07, and the
pre-registered rules there allow that answer to be negative.

## At a glance

| Quantity | Re-fit on real residuals | Phase-7 documented default |
|---|---|---|
| Provenance header line | `noise source = indy-heldout   seed = 0` | `noise source = default   seed = 0` |
| `R[0,0]` (vx), grid-units/s squared | **0.15044900** | 0.25 |
| `R[1,1]` (vy), grid-units/s squared | **0.08920892** | 0.25 |
| `R` off-diagonal, reported and NOT used | **-0.03146268** (correlation -0.2716) | 0 by construction |
| Residual RMS, grid-units/s | **0.387902** (vx), **0.298670** (vy) | not applicable |
| Residual RMS, cm/s | **6.6596** (vx), **5.1276** (vy) | not applicable |
| Residual mean, grid-units/s | -0.005409 (vx), +0.000946 (vy) | not applicable |
| `sigma_jerk_sq`, grid-units/s cubed, squared | **6048.884948** | 1.0 |
| Closed-loop spectral radius on the observable block | **0.818794** | 0.980199 |
| `K` velocity rows (vx, vy) | **0.32957716, 0.36582624** | 0.03920992, 0.03920992 |
| `K` acceleration rows (ax, ay) | **3.28357857, 4.14732106** | 0.03920796, 0.03920796 |
| `K` position rows | exactly zero | exactly zero |
| Held-out rows scored | 14,600 (20 ms each) | not applicable |
| Held-out R2 of the decoder whose residual this is | +0.144602 pooled | not applicable |

Every value in the left column was computed on this machine from the manifest-pinned session and the
Phase-9 checkpoints. None is estimated, extrapolated or carried over from another document.

## Environment

| Field | Value |
|-------|-------|
| Machine | Apple M5 Pro, `arm64` |
| OS | macOS 26.5 (build 25F71) |
| Compute | CPU only. No Neural Engine, no GPU, no compute-unit targeting |
| Interpreter | CPython 3.12.13 (uv-managed) |
| numpy | 2.4.6 |
| scipy | 1.18.0 (supplies `solve_discrete_are`) |
| torch | 2.12.1 (CPU) |
| h5py | 3.16.0 |
| scikit-learn | 1.9.0 |
| coremltools | 9.0 (installed, unused in this plan) |
| Seed | `seed = 0`, recorded in the generated header. The fit is closed-form; there is no sampling |
| Session | `indy_20160630_01`, sha256 `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8` |
| Encoder | `Decoder/checkpoints/ndt1_real_pooled.pt`, sha256 `f95b257bf2479b49102a2d8afee3c46d9008c51ba754d42a60a26762b7d3af8e` |
| Readout | `Decoder/checkpoints/ndt1_real_with_velocity.pt`, sha256 `9d542cb51d4af4811f324fbc6bda0b503da7b15aafc98b5e1340e1a7f49cce65` |
| Wall clock | about 6 minutes, dominated by 73,130 stride-1 encoder forward passes over the session |

The M5 Pro is a corroborating development machine, not the project's iPad Pro M4 capture device. That
distinction does not matter here, because nothing in this file is a hardware-gated claim: R and Q are
properties of the data and the decoder, not of the machine that divided the numbers.

## What changed, and why it was an implementation task

`10-CONTEXT.md`'s reusable-assets list said `fit_kalman_gain.py` "already implements the RD-07
re-fit" and that the re-fit was "a re-run plus a residual source, not new machinery". That was wrong,
and `10-RESEARCH.md` Correction 1 verified it at `Decoder/scripts/fit_kalman_gain.py:154-189`: BOTH
branches of `fit_noise` returned `default_noise`. There was no code path that computed
`cov(z_decoded - v_true)`. Running the script with `--data-dir` pointing at the real sessions
produced the default constants and a header that said so.

The two header states, side by side. Before this plan, at
`Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift:7-10`:

```
//   dt          = 0.02  (20 ms tick, CONTEXT D-01)
//   noise source = default   seed = 0
//   DEFAULT Q/R (held-out Indy data absent): white-noise-jerk sigma_jerk^2=1.0, R=diag(0.25) per axis. Re-run with
//   --data-dir pointing at downloaded Indy .mat to fit R from decoder residuals (07-RESEARCH 3.2).
```

After:

```
//   dt          = 0.02  (20 ms tick, CONTEXT D-01)
//   noise source = indy-heldout   seed = 0
//   session=indy_20160630_01 sha256=2ca8f6b7fcfc n_heldout=14600 lag_bins=1 lambda=0.1 side_mm=171.6820
//   grid_units_per_cm=0.05824724 sigma_jerk_sq=6048.884948 R=diag(0.15044900,0.08920892) R_offdiag=-0.03146268
//   rho_closed_loop=0.818794 resid_rms_grid_s=(0.387902,0.298670) encoder_sha=f95b257bf247
//   velocity_sha=9d542cb51d4a resid_mean_grid_s=(-0.005409,+0.000946) heldout_r2_pooled=+0.144602
//   readout=shipped_pooled_ridge side_mm_source=ndt1.replay_export.workspace_from_cursor+section-3a-cross-check
//   grid normalisation: R and Q are fit in GRID-UNITS/s using grid_units_per_cm = 10.0 / side_mm
//   (10-PREREGISTRATION section 4, pre-registered before the fit ran). A residual fit in cm/s and
//   normalised afterwards differs by grid_units_per_cm^2, which is large.
```

The header is the acceptance criterion, not the fact that the script ran (10-RESEARCH Pitfall 1).
`KalmanConstantsTests.noiseSourceIsRealData` reads it as a string and fails the build if it ever says
`default` again, and the control below shows that test failing on demand.

## Method

The procedure is 10-PREREGISTRATION section 4, restated with the numbers this run produced.

1. **The decoder.** The residual is the SHIPPED decoder's: the Phase-9 pooled encoder plus the pooled
   ridge readout in `ndt1_real_with_velocity.pt`, applied unchanged. No readout was re-fit here. The
   script verifies the checkpoint's sha256 against the one `09-decoder-metrics.json` published, and
   refuses to run on random weights.
2. **The rows.** The chronological tail split of `indy_20160630_01`: 73,161 bins, split at bin
   58,529, held-out design rows starting a full 32-bin window after the split, `lag_bins = 1` and
   `lambda = 0.1` (both locked in Phase 9 and re-read from `09-decoder-metrics.json` at fit time
   rather than restated). That leaves **14,600** scored rows. The readout never saw them.
3. **The wiring check.** Scored against this session's own train-split mean, those rows give held-out
   R2 pooled **+0.144602** (vx +0.058557, vy +0.258861). `09-decoder-metrics.json` publishes
   `0.14460174271291293` for the same session and the same null. The agreement to six decimals is
   what establishes that the residual comes from the same pipeline as the published R2 rather than
   from a re-implementation of it. It is recorded, not asserted: nothing in CI compares them.
4. **The units.** `side_mm = 171.68196243849025`, so `grid_units_per_cm = 10.0 / side_mm =
   0.05824724`. The residual is converted to grid-units/s BEFORE the covariance is taken. This is the
   whole of open question 3, and it matters: fitting in cm/s and normalising afterwards would be
   wrong by `grid_units_per_cm^2 = 0.00339274`, a factor of 295.
5. **R.** `R_full = cov(resid_grid)`, then `R = diag(R_full[0,0], R_full[1,1])`. The filter's
   measurement model is per-axis, so the diagonal is what it can use; the off-diagonal is recorded
   below and in the header, and is not used.
6. **Q.** `sigma_jerk_sq` is the variance of `diff2(v_true) / dt^2` on the same rows, in grid units,
   averaged over the two axes because `white_noise_jerk_q` takes one isotropic scalar. Q is then the
   standard discrete white-noise-jerk form on `[vx, vy, ax, ay]`.
7. **The gain.** `steady_state_gain(q_obs, r)` is called inside `fit_noise`, before anything is
   written, and its raise is not caught.

The `side_mm` note, as resolved. The first run of this fit computed 171.0725 mm, the bounding box of
`10 * planar_cm`, which is what section 3's literal text said. Section 3's own expected value ("about
171.7"), 10-RESEARCH, and Plan 10-01's published reference had all used the session's own recorded
`cursor_pos` array, which differs by the fitted slope 10.005 and a sub-0.03 mm offset. That is a real
conflict, not a rounding difference, and it was escalated rather than absorbed: the user resolved it
on 2026-09-05 in favour of the recorded cursor track, section 3a records the amendment and the
containment argument behind it, and this fit was re-run. The value the shipped fit used,
171.68196243849025, is in the header, and `side_mm_source=` names the one authoritative
implementation it came from.

## Results

| Quantity | Value | Phase-7 default | Ratio |
|---|---|---|---|
| `R[0,0]`, (grid-units/s) squared | 0.15044900 | 0.25 | 0.602 |
| `R[1,1]`, (grid-units/s) squared | 0.08920892 | 0.25 | 0.357 |
| `R` off-diagonal | -0.03146268 | 0 | reported, not used |
| Residual sd, vx | 0.387878 grid-units/s = 6.6592 cm/s | 0.5 grid-units/s = 8.5841 cm/s | 0.78 |
| Residual sd, vy | 0.298679 grid-units/s = 5.1278 cm/s | 0.5 grid-units/s = 8.5841 cm/s | 0.60 |
| `sigma_jerk_sq` | 6048.884948 | 1.0 | 6049 |
| `K` row 2 (vx) | 0.32957716 | 0.03920992 | 8.41 |
| `K` row 3 (vy) | 0.36582624 | 0.03920992 | 9.33 |
| `K` row 4 (ax) | 3.28357857 | 0.03920796 | 83.7 |
| `K` row 5 (ay) | 4.14732106 | 0.03920796 | 105.8 |
| `K` rows 0, 1 (px, py) | exactly zero | exactly zero | unchanged |
| Closed-loop spectral radius | 0.818794 | 0.980199 | more damped |

The `sd` rows convert `sqrt(R)` to cm/s; the at-a-glance table's RMS rows convert the header's
`resid_rms_grid_s`. The two differ in the fourth decimal because the residual mean is not zero, which
is the same reason both are reported.

Three observations, stated without inflating them.

**The real measurement noise is smaller than the documented floor, and it is anisotropic.** The
Phase-7 default assumed 0.25 on both axes; the measured values are 0.150 and 0.089. The vy residual
is the smaller one, consistent with the decoder's per-axis held-out R2 on this session (vx +0.0586,
vy +0.2589): the axis it decodes better is the axis whose residual is smaller. The default was a
documented stand-in, so its being off by 40 to 64 percent is expected rather than surprising.

**The fitted jerk is six thousand times the default.** `sigma_jerk_sq = 1.0` was a placeholder in
units nobody had measured. Real 20 ms binned finger velocity, expressed in grid-units/s, has second
differences whose implied jerk variance is 6049. Because the gain depends on the RATIO of process to
measurement noise, this is the dominant change: Q went up by 6049 and R came down, so the filter now
trusts the measurement far more and smooths far less. That is why `K`'s velocity rows are 8 to 9
times larger and its acceleration rows are 84 to 106 times larger.

**The re-fit gain is more damped, not less.** The closed-loop spectral radius fell from 0.9802 to
0.8188. A larger gain and a smaller spectral radius are the same statement: the estimator converges
faster because it weights each measurement more.

## The off-diagonal, published rather than discarded

`R_full[0,1] = -0.03146268`, which against diagonal entries of 0.1504 and 0.0892 is a residual
correlation of **-0.2716**. That is not negligible, and it is the one place where the measurement is
in tension with the model: a filter that used the full 2x2 R would treat the two axes' errors as
coupled, and this one does not.

The disposition was fixed in advance. 10-PREREGISTRATION section 4 step 3 says R is the diagonal,
because `KalmanConstants.R` feeds a per-axis measurement model and `KalmanConstantsTests`'s existing
`noiseProvenanceShapes` invariant requires `R[0].y == 0` and `R[1].x == 0`. Those assertions are
unchanged by this plan and still pass. The correct reading of -0.2716 is that it is a finding for a
future plan to act on if it chooses, published here and in the shipped header as `R_offdiag=`, not a
licence to change the invariant after seeing the number.

Two smaller disclosures, in the same spirit. R is a covariance about the mean, per the
pre-registration, so the decoder's small velocity bias does not enter it; the bias is
`(-0.005409, +0.000946)` grid-units/s, which is `(-0.0929, +0.0162)` cm/s, and folding it in would
change R by 0.02 percent and 0.001 percent respectively. And Q is isotropic by construction, so the
single `sigma_jerk_sq` is the mean of the two per-axis jerk variances rather than a claim that the
axes agree.

## Stability

`steady_state_gain` solved the observable-block DARE and did NOT raise, so the closed loop
`A_obs (I - K_obs H_obs)` is Schur-stable by its own internal assertion. The measured spectral radius
is **0.818794**, recorded in the shipped header as `rho_closed_loop=0.818794`. `K`'s position rows
are exactly zero, which the pre-existing `gainPositionRowsAreZero` test still checks.

Plan 10-03 added a second, independent check on the Swift side, because until now nothing verified
the numbers actually COMMITTED. `KalmanConstantsTests.shippedGainIsSchurStable` rebuilds
`M = (I - K_obs H_obs) A_obs` from `KalmanConstants` as shipped, squares it to `M^4096`, and asserts
that `norm(M^4096)^(1/4096) < 1`. By Gelfand's formula that root is an upper bound on the spectral
radius, so passing it certifies stability and an unstable gain cannot pass. The check is restricted
to state indices 2 through 5 on purpose: `K`'s position rows are zero, so the full 6x6 closed loop
keeps A's position integrators and has spectral radius exactly 1 by design.

## What this does NOT establish

Read this section before quoting any number above.

- **A re-fit gain is not a performance claim.** Nothing here shows the re-fit decodes better, moves a
  cursor better, or acquires more targets. R and Q describe the residual of a decoder that was
  already fixed; the ablation that tests whether the new gain changes any outcome is Plan 10-05 and
  Plan 10-07, and 10-PREREGISTRATION section 13 says a negative or zero result there is publishable
  without turning the build red. No gate added by this plan asserts the direction of any of these
  numbers.
- **The residual is open-loop.** It is the error of a decoder replaying a recorded session. The
  animal could not correct it, because the animal was not in the loop. A closed-loop residual would
  be a different distribution and R would be a different number.
- **It is one session, and a weak one.** `indy_20160630_01` was locked by CONTEXT D-08 before any
  Phase-10 outcome was known, and its held-out velocity R2 is the lowest of the four sessions
  (+0.1446 against a range of +0.1446 to +0.5069). R fit on a stronger session would be smaller. The
  weakness is disclosed, not corrected.
- **The 14,600 rows are not 14,600 independent samples.** They are consecutive 20 ms bins of a
  continuous reach, so the effective sample size is far smaller than the row count. There is no error
  bar on R in this file, and one computed as if the rows were independent would be wrong.
- **`sigma_jerk_sq` is a fitted intensity, not a measured physical jerk.** It is the variance of a
  second difference of a binned velocity estimate, which includes the binning and differencing noise,
  not only the animal's motion.

## Downstream effect on the two synthetic byte-identity fixtures

The gain changed relative to the Phase-7 DEFAULT, so `CortexReFITBench --smoke` produces different
numbers and both committed synthetic fixtures stop matching. This was anticipated: Plan 10-05 exists
to freeze a `phase7BaselineK` for the smoke path so the synthetic regression fixture keeps guarding
the FILTER CODE, which is what it was always for.

**The 2026-09-05 re-fit did not add to that, and this was measured rather than inferred.** `K` is
invariant under the common `k^2` scaling of Q and R (see the re-fit banner) and all four non-zero
entries round to the same `Float`, so `CortexReFITBench --smoke` was re-run on the re-fit constants
and reproduced the same values Plan 10-03 recorded, to every digit: `refit_bps`
0.37439506338290895 to **1.1950503004699202**, `kalman_only_bps` 0.15545586433053596 to
**0.0966477777818005**, `raw_bps` unchanged at 0.16089860247386525, and the synthetic
`refit_webgrid_bps` at **8.004715490389097**. Plan 10-05's repair is exactly the size it was.

| Gate | Before | After this plan |
|---|---|---|
| `diff .bench/refit_bps.json .planning/phases/07-*/refit_bps.json` (ci.yml:378-388) | identical | differs; `refit_bps` 0.37439506 to 1.19505030, `kalman_only_bps` 0.15545586 to 0.09664778, `raw_bps` unchanged |
| `Tools/scripts/bps-policy.sh` (committed Phase-8 `webgrid_bps.json`) | exit 0 | exit 1 on the committed-copy leg; the run-twice determinism leg still passes |
| `Tools/scripts/check_refit_uplift.py` on either file | exit 0 | exit 0 |
| Committed fixture files | unchanged | unchanged; neither was re-committed |

**Do not quote the new smoke numbers anywhere.** The regenerated synthetic `webgrid_bps.json` reads
`refit_webgrid_bps = 8.0047` against the committed 1.9530. That is a SYNTHETIC seeded replay through
an intent rotation whose heading is target-determined by construction, on a harness where incorrect
selections are structurally zero. Its proximity to the 8.5 BPS reference figure is an arithmetic
coincidence of a faster gain moving a synthetic cursor through more dwell selections per second, and
publishing it as progress would be the exact defect class this milestone exists to remove.

## Negative controls, executed

A gate that was never seen to fail is not a gate. Both controls were run on this machine on
2026-09-05 and both bit.

**Control 1, the provenance header.** Regenerate with an absent data dir, so the script takes its
honest default fallback, then run the package suite.

```
cp Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift /tmp/K.real.swift
uv run --project Decoder python Decoder/scripts/fit_kalman_gain.py --data-dir /nonexistent \
  --out Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift
swift test --package-path Packages/CortexReFIT     # exit 1
cp /tmp/K.real.swift Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift
swift test --package-path Packages/CortexReFIT     # exit 0
```

Result: exit **1**, failing test `Provenance header records a real-data noise fit, not the default`
(`noiseSourceIsRealData`), with 4 failed expectations: `indy-heldout` absent, `default` present,
`session=indy_20160630_01` absent, `R_offdiag=` absent. Restoring the real file gave exit **0** with
28 tests passing in 5 suites, and the restored file's sha256 matched the copy byte for byte.

**Re-executed after the 2026-09-05 re-fit**, on the shipped file, with the same outcome: 4 failed
expectations at `KalmanConstantsTests.swift:130`, `:131`, `:133` and `:135`, then exit 0 with 28
tests passing once restored. The shipped file's sha256 is
`428306fca56e018414e7676d56ac0265b0766a90a35482bfeb0534da14b2e9ea` both before and after the control,
so the control left nothing behind.

**Control 2, the stability check.** Scale every `K` row of a scratch copy by 10 and run the suite.

Result: exit **1**, failing test `The shipped closed-loop gain is Schur-stable on the observable
block` (`shippedGainIsSchurStable`), reporting `norm(M^64) = 1.4147763163776544e+34` and a
non-finite `M^4096`. Only that test failed; the provenance header test still passed, because the
header was untouched. The perturbed file was restored and never committed.

Control 2 was **not** re-executed after the re-fit, and the reason is recorded rather than glossed:
the re-fit left `K` bit-identical as `Float`, so the matrix that control perturbs is the same matrix
it was perturbing on the first run. Re-running it would re-derive the same transcript from the same
inputs.

**Control 3, the box cross-check (added 2026-09-05).** `_resolve_side_mm` compares the authoritative
`ndt1.replay_export.workspace_from_cursor` against this script's own section-3 restatement and raises
above 1e-6 mm. It was observed firing for real, mid-reconciliation, with the exporter already on the
recorded-cursor box and this script still on `10 x planar_cm`:

```
ValueError: ndt1.replay_export.workspace_from_cursor reports side_mm=17.17 but the
10-PREREGISTRATION section 3 arithmetic gives 171.7; the two definitions of the
cursor_bbox_square box have diverged and R would be normalised by the wrong constant
```

`Decoder/tests/test_kalman_residual.py::test_resolve_side_mm_raises_when_the_two_implementations_disagree`
pins it, driving the trap with the finger-derived 171.0725351294064 as the wrong value.

## Runbook

Two commands to reproduce the fit, plus the verification. The dataset and the checkpoints are
gitignored and are not in CI (Phase-9 D-21), so this is a human runbook, not a CI job.

```
uv sync --project Decoder --extra dev
uv run --project Decoder python Decoder/scripts/fit_kalman_gain.py \
  --data-dir Decoder/data --session indy_20160630_01 \
  --out Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift
```

Verify:

```
swift test --package-path Packages/CortexReFIT
./Tools/scripts/hotpath-policy.sh && ./Tools/scripts/hotpath-policy.sh --self-test
swiftformat --lint Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift
uv run --project Decoder pytest Decoder/tests -m "not slow" -q
uv run --project Decoder pytest Decoder/tests/test_kalman_residual.py -m slow -q
```

The fit takes about 6 minutes on an M5 Pro, almost all of it the 73,130 encoder forward passes over
the session. The last slow test repeats that work independently and was measured at 451.14 s here,
while sharing the machine with a Swift build. On a checkout without
`Decoder/data/`, the script still exits 0, writes a buildable file, and records
`noise source = default` in its header, which is the state the whole repository was in before this
plan.
