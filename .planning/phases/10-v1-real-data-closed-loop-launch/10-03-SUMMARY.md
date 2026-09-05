---
status: PASS
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 03
subsystem: infra
tags: [kalman, refit, numpy, scipy, torch, indy, evidence-discipline, code-generation, swift-testing]

# Dependency graph
requires:
  - phase: 10-v1-real-data-closed-loop-launch
    provides: 10-PREREGISTRATION sections 3, 4 and 5 (the workspace box, the grid-unit R convention, the Q rule and the no-silent-fallback rule), committed before this fit ran
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    provides: the pooled encoder and the shipped pooled ridge readout, the locked lag and lambda, the chronological-split window stack in fit_velocity_real.py, and the published per-session held-out R2
  - phase: 07-refit-kalman-closed-loop-recalibration
    provides: the observable-block DARE solver, the KalmanConstants.swift code-gen target and its structural invariants
provides:
  - a working data-present branch in fit_kalman_gain.py that fits R from the real held-out decoded-minus-true residual and Q from the empirical jerk variance, both in grid-units/s
  - the shipped KalmanConstants.swift fit on real residuals, with a provenance header carrying the session, row count, grid normalisation constant, R, the discarded R off-diagonal and the closed-loop spectral radius
  - KalmanConstantsTests.noiseSourceIsRealData, which fails the build if the header ever reverts to the default
  - KalmanConstantsTests.shippedGainIsSchurStable, the first check in the repo on the stability of the constants actually committed
  - 10-kalman-refit-evidence.md, with the residual statistics in both unit systems and both negative-control transcripts
  - four reusable pure helpers (to_grid_units, residual_covariance, jerk_variance, closed_loop_rho) and workspace_side_mm as an independent implementation of pre-registration section 3
affects: [10-05, 10-07, 10-09, 10-11, refit-real-data-ablation, rd-08-replay]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "The generated provenance header is the acceptance criterion, read back as a string by a test, so 'the script ran' can never be mistaken for 'the fit happened'"
    - "Provenance is verified rather than restated: the checkpoint digest, lag and lambda in the header are cross-checked against 09-decoder-metrics.json at fit time"
    - "A stability gate stated as a Gelfand nth-root bound, which is threshold-free and cannot certify an unstable gain"
    - "A second implementation of a pre-registered formula is allowed only when it cross-checks against the first and raises on disagreement"

key-files:
  created:
    - Decoder/tests/test_kalman_residual.py
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-kalman-refit-evidence.md
  modified:
    - Decoder/scripts/fit_kalman_gain.py
    - Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift
    - Packages/CortexReFIT/Tests/CortexReFITTests/KalmanConstantsTests.swift

key-decisions:
  - "The residual is the SHIPPED decoder's: the pooled encoder plus the pooled ridge readout from ndt1_real_with_velocity.pt, applied unchanged to the held-out tail. No readout is re-fit here, so R describes the noise of the decoder that actually ships and reproduces the published per-session R2 of +0.144602 to six decimals"
  - "workspace_side_mm implements 10-PREREGISTRATION section 3 locally instead of raising when ndt1.replay_export is absent, and cross-checks against that module whenever it is importable, raising on any disagreement above 1e-6 mm"
  - "The plan's literal stability bar (norm(M^64) < 1e-3) was replaced by norm(M^4096)^(1/4096) < 1: the closed loop is non-normal, so the committed default gain has rho 0.9802 but norm(M^64) 0.87, and the literal bar would have reddened the build on a correct gain"
  - "R is the diagonal, per pre-registration section 4 step 3; the measured off-diagonal (correlation -0.2716) is published in the shipped header as R_offdiag and in the evidence, and is not used"
  - "The header note is wrapped with break_on_hyphens disabled, because its key=value tokens are grepped as literals by the new test and a hyphen wrap would split one across two comment lines"
  - "fit_velocity_real.py's module-private helpers are imported rather than refactored into a public function, keeping the diff inside this plan's declared file set while still having exactly one implementation of the window stack"

patterns-established:
  - "Wiring check by reproduction: the residual pipeline recomputes a number Phase 9 already published (+0.144602) and prints both side by side, establishing pipeline identity without asserting on a measured value"
  - "Negative controls executed and transcribed with exit codes and failing test names, on the principle that a gate never seen to fail is not a gate"
  - "A degenerate-input control that accepts a disjunction (raises OR returns >= 1) rather than pinning a scipy internal"

requirements-completed: [RD-07]

# Metrics
duration: 31min
completed: 2026-09-05
---

# Phase 10 Plan 03: Kalman re-fit on real residuals Summary

**The ReFIT-Kalman gain is now fit from the real held-out decoded-minus-true residual of the shipped decoder: R = diag(0.15152282, 0.08984564) grid-units/s squared, sigma_jerk_sq = 6092.06, rho = 0.8188, with the provenance header reading `noise source = indy-heldout` and two Swift gates whose negative controls were executed.**

## Performance

- **Duration:** 31 min
- **Started:** 2026-09-05T21:47:00Z
- **Completed:** 2026-09-05T22:18:00Z
- **Tasks:** 3 (Task 1 was TDD, so 4 commits)
- **Files modified:** 5 (2 created, 3 modified)

## Accomplishments

- **The RD-07 re-fit is implemented, not just re-run.** Both branches of `fit_noise` used to return
  `default_noise` (10-RESEARCH Correction 1). The data-present branch now decodes the held-out
  chronological tail of `indy_20160630_01` with the shipped pooled readout, converts the residual to
  grid-units/s, and fits `R = diag(cov(resid))` and `sigma_jerk_sq = var(diff2(v_true)/dt^2)`.
- **The fit reproduces a published Phase-9 number exactly.** Scored on the same rows against the same
  null, the pipeline gives held-out R2 pooled `+0.144602`; `09-decoder-metrics.json` publishes
  `0.14460174271291293`. That agreement is the evidence that the residual comes from the same
  pipeline as the published R2, not from a re-implementation of it. It is printed, never asserted.
- **The shipped constants changed materially and the direction is explainable.** Measured R is 40 to
  64 percent below the documented 0.25 floor and is anisotropic; the fitted jerk intensity is 6092
  times the placeholder 1.0. The ratio is what the gain depends on, so K's velocity rows grew 8 to 9
  times and its acceleration rows 84 to 106 times, and the closed-loop spectral radius fell from
  0.9802 to 0.8188. The Phase-7 defaults were over-smoothing by a wide margin.
- **Two Swift gates, both proven to bite.** `noiseSourceIsRealData` reads the generated header as a
  string; `shippedGainIsSchurStable` is the first thing in the repo that checks the stability of the
  numbers actually committed rather than of a representative pair.
- **The honest fallback survives.** A checkout with no `Decoder/data/` still exits 0, writes a
  buildable file, and records `noise source = default`, now with a unit test pinning that.

## Task Commits

1. **Task 1 (RED): failing tests for the residual path** - `1c0254a` (test)
2. **Task 1 (GREEN): the residual fit in fit_kalman_gain.py** - `da6ff1a` (feat)
3. **Task 2: regenerate the constants and arm the two gates** - `f80e84f` (feat)
4. **Task 3: the evidence artifact** - `cf605ee` (docs)

**Plan metadata:** this summary (docs)

No refactor commit was needed: the GREEN implementation was written against the committed test list
and needed no cleanup pass.

## Files Created/Modified

- `Decoder/scripts/fit_kalman_gain.py` - the implemented residual path, four pure helpers
  (`to_grid_units`, `residual_covariance`, `jerk_variance`, `closed_loop_rho`), `workspace_side_mm`,
  `heldout_decoded_and_true`, the provenance-verification block against `09-decoder-metrics.json`,
  the always-emitted grid-normalisation header lines, and `--session`.
- `Decoder/tests/test_kalman_residual.py` - 9 quick tests plus 1 dataset-gated slow test, plus the
  D-09 source self-check over both this module and the script.
- `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift` - regenerated. Header reads
  `noise source = indy-heldout` and carries `session=`, `n_heldout=`, `grid_units_per_cm=`,
  `R=diag(...)`, `R_offdiag=`, `rho_closed_loop=`, both checkpoint digests and the residual RMS.
- `Packages/CortexReFIT/Tests/CortexReFITTests/KalmanConstantsTests.swift` - `noiseSourceIsRealData`
  and `shippedGainIsSchurStable` added beside the five existing invariants; none removed or weakened.
- `.planning/phases/10-v1-real-data-closed-loop-launch/10-kalman-refit-evidence.md` - 308 lines: the
  residual statistics in grid-units/s and cm/s, the Phase-7 defaults beside them, the method with the
  actual numbers, what the re-fit does not establish, both control transcripts, and the runbook.

## Verification

Every leg of the plan's verification block, run on the final tree:

| Command | Exit |
|---|---|
| `uv run --project Decoder ruff check Decoder` | 0 |
| `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` | 0 (230 passed, 10 deselected) |
| `uv run --project Decoder pytest Decoder/tests/test_kalman_residual.py -m slow -q` | 0 (1 passed in 451.14 s) |
| `swift test --package-path Packages/CortexReFIT` | 0 (28 tests in 5 suites, was 26) |
| `./Tools/scripts/hotpath-policy.sh` | 0 |
| `./Tools/scripts/hotpath-policy.sh --self-test` | 0 |
| `swiftformat --lint .../KalmanConstants.swift` | 0 |

Task-1 greps: `return default_noise(seed)` appears exactly once (the data-absent branch),
`Plan-03 hook` zero times, no bare or broad `except`, and the fallback run
(`--data-dir /nonexistent`) exits 0 and writes `noise source = default`.

### Negative controls, executed and recorded

- **Control 1 (provenance).** Regenerating with `--data-dir /nonexistent` made
  `swift test --package-path Packages/CortexReFIT` exit **1**, failing
  `noiseSourceIsRealData` ("Provenance header records a real-data noise fit, not the default") with
  4 failed expectations. Restoring the real file gave exit **0**, 28 tests passing, sha256
  `a330c023ffa202d6...` identical to the pre-control copy.
- **Control 2 (stability).** Scaling every `K` row of a scratch copy by 10 made `swift test` exit
  **1**, failing only `shippedGainIsSchurStable`, reporting `norm(M^64) = 1.41e34` and a non-finite
  `M^4096`. The perturbed file was restored and never committed.

## Cross-plan consequence: two synthetic byte-identity fixtures now differ

Changing `KalmanConstants.K` changes what `CortexReFITBench --smoke` produces. The plan anticipated
this for one fixture and required it be noted rather than fixed here; the second one is reported for
the same reason. **Plan 10-05 owns the repair** (it freezes a `phase7BaselineK` and injects it into
the smoke path so the synthetic fixture keeps guarding the filter code).

| Gate | State after this plan |
|---|---|
| `diff .bench/refit_bps.json .planning/phases/07-*/refit_bps.json` (`ci.yml:378-388`) | **exit 1**: `refit_bps` 0.37439506 to 1.19505030, `kalman_only_bps` 0.15545586 to 0.09664778, `raw_bps` unchanged |
| `Tools/scripts/bps-policy.sh` | **exit 1** on the committed-copy leg (Phase-8 `webgrid_bps.json`); the run-twice determinism leg still passes; `--self-test` exits 0 |
| `Tools/scripts/check_refit_uplift.py` on either file | exit 0 |
| Committed fixtures under `.planning/phases/07-*` and `08-*` | **unchanged**; neither was re-committed |

**One number here needs a guard rail.** The regenerated synthetic `webgrid_bps.json` reads
`refit_webgrid_bps = 8.0047` against the committed 1.9530. It is a seeded SYNTHETIC replay through a
rotation whose heading is target-determined by construction, with incorrect selections structurally
zero. Its proximity to the 8.5 BPS reference is arithmetic coincidence. It must not be quoted as
progress anywhere, and it is flagged as such in the evidence artifact.

## Decisions Made

- **The residual is the shipped decoder's, not a re-fit one.** Pre-registration section 4 says "at
  lag 1 bin and lambda 0.1", which admits either a locally re-fit ridge or the shipped pooled head.
  The shipped head was chosen because the Kalman filter runs downstream of the deployed decoder, so R
  must be that decoder's noise, and because it makes the residual and the published R2 describe the
  same artifact. The header records `readout=shipped_pooled_ridge` so the choice is not silent.
- **`lag_bins` and `lambda` are read from `09-decoder-metrics.json` at fit time**, and the run raises
  if they disagree with the pre-registered 1 and 0.1, or if the checkpoint digest is not the one that
  metrics file published. The header's `lag_bins=1 lambda=0.1` is therefore a verified fact.
- **R keeps the pre-registered diagonal.** The measured residual correlation is -0.2716, which is not
  negligible, and that is exactly why the disposition was fixed in advance. It is published as
  `R_offdiag=-0.03168725` rather than discarded, and the existing `noiseProvenanceShapes` invariant
  is byte-identical and still passes.
- **`side_mm` is 171.0725, not the "about 171.7" the pre-registration expected.** Section 3 said the
  script computes it rather than asserting it. The difference is that 171.7 was measured on the
  session's own `cursor_pos` while the box is defined on `10 * planar_cm`, and the two differ by the
  fitted slope 10.005. Both are recorded in the evidence; neither is adjusted toward the other.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `ndt1.replay_export` does not exist in this worktree**

- **Found during:** Task 1
- **Issue:** The plan says to obtain `side_mm` from `ndt1.replay_export.workspace_from_cursor` and to
  raise a named `ImportError` if it is absent. That module is built by Plan 10-02, which is executing
  in parallel in a different worktree, so raising would have made this plan unrunnable.
- **Fix:** `workspace_side_mm(planar_cm)` implements 10-PREREGISTRATION section 3 directly (10 times
  planar, axis-aligned bbox, longer side) and is unit-tested. `_resolve_side_mm` still prefers the
  exporter whenever it is importable and **raises** if the two disagree by more than 1e-6 mm, so once
  10-02 lands, drift is caught loudly instead of silently normalising R by the wrong constant. The
  header records which source was used (`side_mm_source=`).
- **Files modified:** `Decoder/scripts/fit_kalman_gain.py`, `Decoder/tests/test_kalman_residual.py`
- **Verification:** `test_workspace_side_mm_implements_the_preregistered_square_box`; the run printed
  `side_mm_source=10-PREREGISTRATION-section-3 (ndt1.replay_export not importable)`.
- **Committed in:** `da6ff1a`
- **Residual risk:** 10-02's plan names the function twice with different signatures, at its line 281
  (`workspace_from_cursor(target_mm_track, planar_cm)`) and its line 320
  (`workspace_from_cursor(planar_cm) -> dict`). This code calls the line-320 form, which is the one in
  that plan's authoritative interfaces block. If 10-02 ships the two-argument form instead, the
  cross-check raises `TypeError` on the next re-fit, which is loud and easy to fix, not silent.

**2. [Rule 1 - Bug] The plan's stability threshold would fail on a correct gain**

- **Found during:** Task 2
- **Issue:** The plan specified `#expect(norm64 < 1e-3)` on the 4x4 observable closed loop. Measured
  on the committed Phase-7 default constants, that matrix is strongly non-normal: rho is 0.9802 but
  `norm(M^1)` is 1.038 and `norm(M^64)` is 0.874. The literal bar would have failed on a perfectly
  Schur-stable gain, which is the false-red failure 10-PREREGISTRATION section 13 forbids.
- **Fix:** The test squares to `M^4096` and asserts `norm(M^4096)^(1/4096) < 1`. By Gelfand's formula
  that root upper-bounds the spectral radius, so it certifies stability with no tuned constant and an
  unstable gain can never pass it. The decay assertion from the plan is kept. The rationale, with the
  measured numbers, is written into the test's doc comment.
- **Files modified:** `Packages/CortexReFIT/Tests/CortexReFITTests/KalmanConstantsTests.swift`
- **Verification:** passes on the shipped gain (rho 0.8188); fails with a non-finite norm on the
  10x-perturbed control.
- **Committed in:** `f80e84f`

**3. [Rule 2 - Missing critical] Header tokens could be split across comment lines**

- **Found during:** Task 1
- **Issue:** `render_swift` wraps the provenance note with `textwrap.wrap`, which breaks on hyphens by
  default. The note is a list of `key=value` tokens that the new Swift test and the acceptance
  criteria grep as literals, so a hyphen wrap could have split one and silently broken the gate.
- **Fix:** `break_on_hyphens=False`, with the reason in a comment.
- **Files modified:** `Decoder/scripts/fit_kalman_gain.py`
- **Verification:** the emitted header keeps every token intact; `swiftformat --lint` still exits 0.
- **Committed in:** `da6ff1a`

**4. [Rule 2 - Missing critical] The header's lag, lambda and checkpoint were asserted, not verified**

- **Found during:** Task 1
- **Issue:** Emitting `lag_bins=1 lambda=0.1` from module constants would restate the
  pre-registration rather than describe how the loaded readout was actually fit, and nothing checked
  that the checkpoint on disk was the one whose R2 the evidence cites.
- **Fix:** `_phase09_velocity_record` reads `09-decoder-metrics.json`; the run raises if the velocity
  checkpoint's sha256 differs from the published one, or if the recorded lag and lambda differ from
  the pre-registered pair. Missing metrics degrade to the pre-registered constants rather than
  crashing.
- **Files modified:** `Decoder/scripts/fit_kalman_gain.py`
- **Verification:** the run printed the matching digest `9d542cb51d4a` and completed; the values now
  in the header came from the metrics file.
- **Committed in:** `da6ff1a`

**5. [Rule 3 - Blocking] Private helpers imported instead of refactoring `fit_velocity_real.py`**

- **Found during:** Task 1
- **Issue:** The plan permitted refactoring `fit_velocity_real.py` to expose a public
  `heldout_decoded_and_true` if its private helpers could not be imported cleanly. That file is not in
  this plan's `files_modified`, and this is a parallel wave.
- **Fix:** The helpers import cleanly by path (`_velocity_bins`, `_encoder_last_bin`, `_split_design`,
  `_sha256_of`), so they are imported rather than copied. There is still exactly one implementation of
  the window stack; only the diff got smaller. A comment records why.
- **Files modified:** `Decoder/scripts/fit_kalman_gain.py`
- **Verification:** the held-out R2 reproduces Phase 9's published value to six decimals, which is
  what proves the imported pipeline is the same pipeline.
- **Committed in:** `da6ff1a`

**Total deviations:** 5 auto-fixed (2 blocking under Rule 3, 2 missing-critical under Rule 2, 1 bug
under Rule 1).
**Impact on plan:** No scope creep. Deviations 1 and 5 are consequences of parallel execution and
both leave the result stricter than the plan asked for. Deviation 2 corrects a gate that would have
been red on correct code. Deviations 3 and 4 close two ways the provenance header could have lied.

## Issues Encountered

- **The worktree has no `Decoder/data/` or `Decoder/checkpoints/`**, both gitignored. They were
  symlinked in from the canonical checkout for the run and removed afterwards. Note for future
  worktree agents: git does **not** honour a per-worktree `.git/worktrees/<name>/info/exclude`, and
  the committed `.gitignore` patterns end in `/`, which match directories but not symlinks, so the two
  symlinks show up as untracked while they exist. They were never staged.
- **The editor hook's `ty` type checker reports `unresolved-import` for every `ndt1.*` import**,
  including pre-existing ones, because it runs outside the uv environment where `cortex-ndt1` is
  installed. Not a real finding; the project's gate is `ruff check` under `uv run`, which is clean.
- **The `--smoke` fixtures.** Covered above under cross-plan consequence, not repaired here.

## User Setup Required

None. The re-fit needs the gitignored `Decoder/data/indy_20160630_01.mat` and the two Phase-9
checkpoints, all already materialized on this machine; a checkout without them takes the documented
default path and stays buildable.

## Next Phase Readiness

- **10-05 is unblocked and now has a concrete obligation:** the re-fit gain ships, so its
  `phase7BaselineK` freeze plus injected-gain init is what restores the `ci.yml:378-388` byte-diff and
  `bps-policy.sh`. Both are red until it lands, with the committed fixtures untouched.
- **10-07 inherits a materially different filter.** The gain is 8 to 9 times larger on velocity and
  the closed loop is more damped, so the `kalman_only` and `refit` arms will not resemble the Phase-7
  synthetic numbers. That is expected and is not evidence of anything until the ablation runs.
- **RD-07 is half discharged.** Its first clause, "ReFIT-Kalman gains are re-fit on real data", is
  complete and evidenced. Its second clause, "raw-vs-ReFIT BPS ablation re-run on real Indy sessions
  with the honest remaining gap to 4.16 / 8.5 BPS stated", belongs to Plans 10-05 and 10-07. The ID is
  listed in `requirements-completed` per this plan's frontmatter contract; the second clause is not
  claimed here.
- **Note for whoever re-fits later:** the whole run is about 6 minutes of CPU because the encoder
  forward pass is not cached. `fit_velocity_real.py` has a rates cache keyed on the encoder and
  session digests; wiring this script into it would make a re-fit near-instant. Not needed for one
  run, so it was not built.

## Self-Check: PASSED

- All five plan files exist on disk.
- All four task commits exist in this worktree's history on top of the expected base `dce82c7`.
- The working tree is clean; the two setup symlinks were removed.

*Phase: 10-v1-real-data-closed-loop-launch*
*Completed: 2026-09-05*
