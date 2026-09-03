---
status: PARTIAL
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 07
subsystem: decoder
tags: [ndt1, velocity, ridge, r2, lag, kinematics, finger-pos, held-out, pre-registration, evidence]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 06d
    provides: "the pooled encoder Decoder/checkpoints/ndt1_real_pooled.pt (sha256 f95b257b), 200 epochs under the corrected input-masking objective, and the metrics JSON this plan extends"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 03
    provides: "ndt1.kinematics: planar_velocity_250hz, bin_velocity, apply_lag, heldout_r2 and its required TRAIN-mean null, LAG_BINS_SWEEP"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 05
    provides: "1,767,820,363 bytes of manifest-pinned real Indy M1 data under Decoder/data/"
provides:
  - "Decoder/scripts/fit_velocity_real.py: the lag sweep, the alignment diagnostic, the lambda sweep, the closed-form fit, the held-out scoring and the forward-parity gate, with its four selection rules committed before the run"
  - "The first real velocity decode number this repository has: pooled held-out R2 0.4238 against a constant TRAIN-split mean-velocity null over 56,943 held-out bins, all four sessions positive (+0.1446 to +0.5069)"
  - "Decoder/checkpoints/ndt1_real_with_velocity.pt, sha256 9d542cb51d4af4811f324fbc6bda0b503da7b15aafc98b5e1340e1a7f49cce65: all 101 encoder tensors bit-identical to the Plan 09-06 pooled checkpoint, plus a 194-parameter ridge readout, for Plan 09-08 to convert"
  - "The measured retirement of velocity_r2.json's 0.99985, named in velocity.supersedes and dissected in the evidence"
  - "The answer to the lag warning this plan tripped: the two-sided -160 to +160 ms curve has an interior maximum at +20 ms, so the labels are not shifted"
  - "A forward-parity gate that measures, rather than assumes, that the design matrix is the tensor the shipped 1x1 conv consumes: 4.8e-05 cm/s"
  - "Decoder/checkpoints/09-07-rates/: 218 MB of cached per-session design matrices, hash-guarded, which makes any follow-up readout fit seconds rather than 21 minutes"
affects: [09-08, 09-09, 09-10, 09-11, RD-02, RD-06, Phase 10 RD-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pin a fitted readout to the graph that ships by running the full assembled forward pass and asserting it reproduces the arithmetic the reported metric came from; a design-matrix transform that the graph does not apply then fails loudly instead of silently"
    - "Answer a pre-registered warning with a measurement instead of a shrug: a one-sided sweep cannot distinguish a boundary optimum from shifted labels, so compute the other side of zero as a diagnostic that is explicitly excluded from the selection"
    - "Refuse a selection criterion that is monotone in the parameter it is supposed to select, and pre-register the closed-form tie-breaker instead, so the lock is decided by a rule rather than by whoever reads the curve"
    - "Verify provenance by hash, not by name: check every input session's sha256 and the encoder's own sha256 against the metrics file before producing a number that will be attributed to them"
    - "Call the split function rather than restate its arithmetic, so the block a readout is scored on cannot drift from the block the encoder was evaluated on"
    - "Commit the script, and therefore its selection rules, before the run that produces any published number; the commit ordering is the audit trail"

key-files:
  created:
    - Decoder/scripts/fit_velocity_real.py
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-velocity-evidence.md
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/deferred-items-09-07.md
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-07-SUMMARY.md
  modified:
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-decoder-metrics.json

key-decisions:
  - "The design matrix is the encoder's RAW output, not exp(log-rates), because the shipped module feeds the 1x1 conv the encoder output unchanged; exponentiating would have fit weights the graph never applies, and adding an exp to match would have added an op type D-09 forbids"
  - "The design matrix is built at stride 1, one row per bin, not one row per non-overlapping 32-bin window; that is both the 50 Hz serving geometry and the row layout apply_lag documents, and the plan's 8,900-window cost estimate assumed the other one"
  - "apply_lag runs PER SESSION before concatenation, so no neural-to-kinematic pair straddles two recordings weeks apart; this is why lag_sweep_r2 could not be called on the pooled matrix directly"
  - "Held-out design rows start a full window AFTER the split point, so no held-out prediction reads a bin the encoder trained on; the cost is 124 rows out of 285,235"
  - "Per session the null is that session's own train mean, which is the harder of the two available nulls; the pooled train mean would sit further from any single session's tail and inflate the number"
  - "The lambda lock is reported as 0.1 because the pre-registered rule says so, and the evidence states plainly that the choice is immaterial rather than dressing a sixth-significant-figure difference as a selection"
  - "No leave-one-session-out velocity fit was run: it is not in this plan's success criteria, and adding an unplanned measurement after seeing a favourable pooled number is the shape of the thing this phase's pre-registration chain exists to prevent"

patterns-established:
  - "When a plan's step would break the artifact it is trying to produce, implement the correct thing and add the assertion that would have caught the plan's version, so the deviation is auditable rather than argued"
  - "Cache the expensive stage of a measurement behind an input-hash guard, so the follow-up question a reader will ask costs seconds instead of a re-run"

requirements-completed: [RD-02]

# Metrics
duration: about 55m
completed: 2026-09-02
---

# Phase 9 Plan 07: the velocity readout, fit on real kinematics Summary

**The shipped model's velocity readout is now fit on real `finger_pos` movement instead of on labels
generated from the rates it regresses, and it decodes: pooled held-out R2 0.4238 against a constant
TRAIN-split mean-velocity null over 56,943 held-out bins, with all four sessions positive against
their own train means. Two of the plan's own steps would have broken the artifact if followed
literally, and the run tripped its own lag warning, which is answered by measurement rather than by
argument.**

## Performance

- **Duration:** about 55 min wall, of which 1,255.9 s was the measured run and 1,252.0 s of that was
  285,235 stride-1 encoder forward passes on CPU
- **Tasks:** 2 of 2
- **Files:** 4 created, 1 modified
- **Commits:** 4

## Accomplishments

### The number, and the shape it has

| | Held-out R2 against a constant TRAIN-split mean-velocity null |
|---|---|
| Pooled, 56,943 bins | **+0.4238** (`vx` +0.3430, `vy` +0.5338) |
| `indy_20160624_03` | +0.5046 |
| `indy_20160627_01` | +0.5069 |
| `indy_20160630_01` | **+0.1446** |
| `indy_20160915_01` | +0.4797 |

All four positive, and a 3.5x spread across them that a pooled figure alone would have hidden. `vy`
beats `vx` on every session by 0.11 to 0.20. The pooled figure is `1 - sum SS_res / sum SS_tot`, not
the mean of the axes: the mean would have been 0.4384 against the reported 0.4238.

Per session the null is that session's own train mean, which is the harder of the two available
nulls. This is within-pool held-out decoding on sessions the encoder trained on, exactly as
Plan 09-06d's positive co-bps half was, and like it, it says nothing about cross-session transfer.
No leave-one-session-out velocity fit was run, and the evidence says so instead of implying
otherwise.

### The lag warning, answered rather than noted

The TRAIN-only sweep put its argmax at 1 bin (20 ms), outside the 5-8 bin range anchored by
`nlb_tools`' `'lag': 140` for `mc_rtt` and by the PNAS 120-180 ms cross-correlation. The
pre-registration says that is a signal the alignment or the sign is wrong. A warning alone leaves
the question open, so the same TRAIN-only curve was computed at the eight NEGATIVE offsets, after
the pre-registered sweep and excluded from the selection by construction.

Over the full -160 ms to +160 ms curve the maximum is still +20 ms, and the curve falls away
monotonically on both sides: by 0.070 over the +160 ms arm and by 0.108 over the -160 ms arm. **The
optimum is interior, so the labels are not shifted**, which is precisely the failure the warning
exists to catch. The evidence offers an interpretation for why 20 ms rather than 140 ms (the
`nlb_tools` figure belongs to per-bin rates produced non-causally with a whole trial in view, while
here a trailing causal window ends at the bin being read) and labels it explicitly as an
interpretation of a measured curve, not a tested hypothesis.

### The gate that makes the checkpoint trustworthy

The run refuses to ship a head unless the fully assembled model reproduces `X @ W.T + b` on real
held-out windows. **Max abs disagreement 4.8e-05 cm/s**, which is float32 conv weights against a
float64 solve. That single assertion is what converts "the design matrix is the tensor the shipped
1x1 conv consumes" from a claim into a measurement, and it is the assertion that would have failed
loudly had the plan's exponentiation step been followed.

Verified independently after the run: all **101** encoder tensors in
`ndt1_real_with_velocity.pt` are `torch.equal` to the Plan 09-06 pooled checkpoint, the encoder
parameter count is unchanged at 1,292,544, and the model totals 1,292,738 with the 194-parameter
readout.

### What 0.99985 actually was

`Decoder/tests/test_convert_velocity_output.py:55` builds `vel = last_bin @ w_true + 0.01 * noise`
and then regresses `last_bin` onto it. It is a correct test of `load_ridge`, and it is not a decode
result. Nothing in `05-velocity-head-evidence.md` is retracted or edited: the number is superseded,
named in `velocity.supersedes`, and dissected in the new evidence so the replacement is auditable.

### Commit ordering as the audit trail

`ba47798` commits the script, and therefore its four selection rules, before the run that produced
any published number; `e9f3760` commits the numbers. `git merge-base --is-ancestor ba47798 e9f3760`
exits 0, and the only thing executed before `ba47798` was a 3000-bin `--smoke` wiring check writing
to gitignored scratch paths.

## Task Commits

1. **Task 1, pre-registration** - `ba47798` (feat): the script and its four rules, before the run
2. **Task 1, the measurement** - `e9f3760` (feat): the `velocity` section, 240 insertions and 0
   deletions to the metrics JSON
3. **Task 2** - `99c48d3` (docs): `09-velocity-evidence.md`
4. **Deferred items and this summary** - see `git log`

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 1 - Bug] The design matrix is NOT exponentiated, contrary to Task 1 step 3**

- **Found during:** Task 1, reading `model_ane.py` against the plan's step 3
- **Issue:** the plan says "If the encoder emits log-rates (`log_input=True`), exponentiate before
  the ridge". `NDT1ANEWithVelocity.forward` is `velocity_head(encoder(x))`: the 1x1 conv consumes
  the encoder's output unchanged. Fitting `W` on `exp(log_rates)` would have produced weights the
  shipped graph never applies, so the `.mlpackage` Plan 09-08 converts would have emitted a
  velocity computed from a different input than the one the weights were solved for. Matching the
  fit by inserting an `exp` into the graph was not an option either: D-09 forbids new op types.
  Phase 5's own fit path confirms the convention, using `rates[..., -1]` with no transform.
- **Fix:** fit on the encoder's raw output, and add the R4 forward-parity gate that runs the full
  assembled model on real held-out windows and aborts nonzero above 1e-4 cm/s.
- **Files modified:** `Decoder/scripts/fit_velocity_real.py`
- **Verification:** measured 4.8e-05 cm/s. Had the design matrix been exponentiated this gate would
  have failed by orders of magnitude rather than at the fp32 rounding floor.
- **Committed in:** `ba47798`

**2. [Rule 1 - Bug] Stride-1 design rows, not one row per non-overlapping window**

- **Found during:** Task 1, checking the plan's "(n_windows, 96)" against `apply_lag`'s contract
- **Issue:** `IndySpikeDataset` chunks into NON-overlapping windows, and the plan's threat model
  T-09-07-07 sizes the run at "roughly 8,900 windows", which is that count. With non-overlapping
  rows the design matrix is 32 bins per row, which breaks `apply_lag`'s documented
  `(n_bins, num_channels)` layout: "lag k" would silently have meant 32k bins, so the whole D-08
  sweep would have spanned 0 to 5.12 s rather than 0 to 160 ms. It also mismatches serving, which
  calls the model once per 20 ms bin with the trailing window.
- **Fix:** build the design matrix at stride 1 via `sliding_window_view`, giving 285,235 rows, one
  per bin from bin 31 onward.
- **Files modified:** `Decoder/scripts/fit_velocity_real.py`
- **Verification:** `_assert_bc1s_layout` compares the fast `(b, C, S) -> (b, C, 1, S)` construction
  against `ndt1.train.reshape_to_bc1s`'s `(b, S, C)` path with `torch.equal` on real bins, on every
  session, before any forward pass runs.
- **Cost, stated rather than hidden:** 21 minutes of CPU instead of about 40 seconds, which is why
  the run was detached and why the rates cache exists.
- **Committed in:** `ba47798`

**3. [Rule 2 - Missing critical] `apply_lag` per session, then concatenate**

- **Found during:** Task 1, step 4
- **Issue:** the plan says to concatenate the train halves and then call `lag_sweep_r2` on the
  result. Lagging a concatenation pairs the last rows of one recording with the first rows of
  another recorded weeks later. It is three fabricated pairs per session boundary per lag out of
  228,164, which is small and is exactly the class of fabricated input this phase exists to remove.
- **Fix:** lag per session, then concatenate. `lag_sweep_r2` therefore could not be called on the
  pooled matrix; a local composition performs the identical arithmetic through the same
  `apply_lag`, `ridge_fit` and `heldout_r2`, so there is still one definition of R2.
- **Files modified:** `Decoder/scripts/fit_velocity_real.py`
- **Committed in:** `ba47798`

**4. [Rule 2 - Missing critical] Held-out rows begin a full window after the split**

- **Found during:** Task 1, working out the row bookkeeping
- **Issue:** the plan does not specify where the held-out design rows start. Starting them at the
  split bin means the first 31 test rows read windows containing bins the encoder trained on.
- **Fix:** held-out rows start at split + `SEQ_LEN` - 1, so no held-out prediction reads a single
  trained-on bin. Cost: 124 rows out of 285,235.
- **Files modified:** `Decoder/scripts/fit_velocity_real.py`
- **Committed in:** `ba47798`

**5. [Rule 2 - Missing critical] Provenance is checked by hash, not by name**

- **Found during:** Task 1, step 1
- **Issue:** the plan requires aborting if the session id SET disagrees with the metrics JSON. Ids
  match while bytes differ, and the encoder is not checked at all, so a readout could be fit on
  different data or a different encoder than the JSON attributes it to.
- **Fix:** every session's sha256 and the encoder checkpoint's sha256 must also match
  `09-decoder-metrics.json` before any number is produced. All five matched.
- **Files modified:** `Decoder/scripts/fit_velocity_real.py`
- **Committed in:** `ba47798`

**6. [Rule 2 - Missing critical] The negative-offset alignment diagnostic**

- **Found during:** Task 1, after the sweep tripped its own warning
- **Issue:** the plan asks for a warning when the argmax falls outside 5-8 bins. It fired. A warning
  alone cannot distinguish "zero really is the optimum" from "the labels are shifted late and the
  one-sided sweep pinned its argmax at the boundary", because those look identical.
- **Fix:** compute the same TRAIN-only curve at eight negative offsets, after the pre-registered
  sweep, excluded from the selection by construction, published as
  `velocity.lag_alignment_diagnostic` with a machine-generated verdict string. `apply_lag`'s refusal
  of negative offsets was NOT weakened; the diagnostic swaps its arguments instead.
- **Verification:** two-sided maximum still at +20 ms, monotone decline on both sides.
- **Committed in:** `ba47798`

**7. [Rule 3 - Blocking] The lambda rule, because the plan's criterion cannot select**

- **Found during:** Task 1, step 5
- **Issue:** the plan says to sweep lambda "scoring in-sample train R2, lock one value". In-sample
  train R2 is monotone non-increasing in lambda by construction, so its argmax mechanically returns
  the smallest grid point every time. There was no rule that could have locked a value without
  someone choosing after seeing the curve.
- **Fix:** pre-register the rule instead. Lock `ridge_fit`'s existing 1.0 default, fixed in Phase 5
  before any real measurement existed, unless the whole-grid train-R2 spread exceeds 1e-3, in which
  case break the tie with closed-form generalized cross-validation on the train split alone
  (09-RESEARCH section 7 option 1, no extra split, no leak).
- **Outcome, reported rather than dressed up:** the tie-breaker fired on a 2.64e-2 spread produced
  almost entirely by lambda 100 and 1000, and locked 0.1. Across 0.01 to 10 the train R2 moves
  3.7e-4 and the cross-validation score moves in its sixth significant figure. The evidence says the
  lock is immaterial.
- **Committed in:** `ba47798`

**8. [Rule 2 - Missing critical] `chronological_split` is called, not restated**

- **Found during:** Task 1
- **Issue:** recomputing the split point inline would let the block the readout is scored on drift
  from the block the encoder was evaluated on under any future edit.
- **Fix:** `_split_design` calls `chronological_split` and takes `len(train)`.
- **Committed in:** `ba47798`

**9. [Rule 3 - Blocking] The run was detached and its expensive stage cached**

- **Found during:** planning the launch
- **Issue:** a 21-minute foreground call is inside the 600 s tool timeout twice over, and this phase
  has already lost two runs to that failure mode.
- **Fix:** `nohup` plus a log file plus `caffeinate -dimsu -w <pid>`, and a `--reuse-rates` cache
  under `Decoder/checkpoints/09-07-rates/` guarded by the encoder sha256, the session sha256, the
  sequence length and the bin count. A mismatched cache recomputes rather than failing.
- **Committed in:** `ba47798`

### Non-issue deviations

**10. Task 1 landed as two commits rather than one.** The script, and therefore its four selection
rules, is committed in `ba47798` before the run; the numbers follow in `e9f3760`. This mirrors
Plan 09-06d's `06eb61f` before `967f38e` and makes the ordering checkable with
`git merge-base --is-ancestor`.

**11. The metrics `velocity` section carries five keys beyond the plan's sketch:**
`design_matrix`, `lag_alignment_diagnostic`, `lambda_rule`, `forward_parity_max_abs_cm_s`,
`in_sample_train_r2`, plus `encoder`, `env`, `wall_clock_s` and `smoke` mirroring the file's
existing idiom. Every key the plan specifies is present with the specified shape, and the diff is
240 insertions and 0 deletions.

## Issues Encountered

**The plan's Task 1 contained two steps that would have broken the artifact.** Both are documented
above as deviations 1 and 2. They are worth naming together because they share a cause: the plan
described the design matrix in terms of `NDT1ANE`'s training-time geometry (non-overlapping windows,
rates as counts) rather than the shipped module's serving geometry (one window per 20 ms bin, the
conv reading the encoder's raw output). Either one alone would have produced a `.mlpackage` that
loads, converts, passes every shape assertion and emits wrong velocities. Neither would have been
caught by any test in the repository, which is why the forward-parity gate was added rather than
just the fix.

**The run tripped its own pre-registered warning.** The locked lag is 20 ms against an anchor of
140 ms. The measured answer is that the optimum is interior on a two-sided curve, so the alignment
is not the problem, but the disagreement with `nlb_tools` is real and the explanation offered for it
is an interpretation rather than a tested hypothesis. `deferred-items-09-07.md` item 4 records the
experiment that would test it.

**The result is favourable, and that is its own hazard.** A pooled +0.4238 with all four sessions
positive is a better outcome than 09-RESEARCH predicted for this architecture, and the temptation in
that situation is to stop asking questions. Three things were done instead of stopping: the
per-session spread (0.1446 to 0.5069) is reported alongside the pooled figure rather than under it;
the absence of any error bar and the fact that 56,943 autocorrelated bins are not 56,943 independent
samples are stated in the evidence rather than left to a reader; and the missing cross-session half
of the question is written down as a deferred item with the note that the cached design matrices
make it a seconds-long follow-up, rather than being quietly omitted.

## Deferred Items

Four, in `deferred-items-09-07.md`: no cross-session velocity readout, and it is now cheap because
the design matrices are cached; no error bar anywhere, the second artifact in this phase to carry
that gap; only one of the four sessions has a measured within-session drift figure, so the
suggestive coincidence with the weakest session cannot be called an explanation; and the untested
interpretation of why the lag is 20 ms rather than 140 ms.

## Known Stubs

None. Every path in `fit_velocity_real.py` is executed by the published run: no placeholder value,
no hardcoded empty result, no mock payload and no unwired branch. Values in the artifact that could
be mistaken for results are labeled where they appear: the lag and lambda sweeps' `train_r2` columns
are in-sample selection criteria scored on the rows the fit used, `in_sample_train_r2` is recorded
only to show the load path ran and is the kind of number D-10 replaces, and `--smoke` output carries
`"smoke": true` and is written to gitignored scratch paths that can never reach the published JSON.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: deserialization | `Decoder/scripts/fit_velocity_real.py` | New file-access pattern: `np.load` on a locally produced `.npy` rates cache under gitignored `Decoder/checkpoints/09-07-rates/`. Verified rather than assumed: `numpy 2.4.6`'s `np.load` defaults `allow_pickle=False`, so the payload cannot execute code, and the cache is rejected unless its recorded encoder sha256, session sha256, sequence length and bin count all match the current inputs. |

No new network endpoint, no auth path, no schema change at a trust boundary. No dataset byte and no
checkpoint entered git: `git status --porcelain Decoder/checkpoints Decoder/data` returns 0 lines
and `git ls-files` matches no `.pt` and exactly one `.mat`, the untouched Plan 09-02 CI fixture.

The register's dispositions held. T-09-07-01 (label leakage through lag or lambda selection): both
sweeps ran on TRAIN rows only, the held-out R2 was computed once at the locked settings, both full
curves are published, and the alignment diagnostic is excluded from the selection by construction.
T-09-07-02 (a self-consistency R2 presented as a decode result): `heldout_r2` requires its null
explicitly and `velocity.supersedes` names the 0.99985 artifact. T-09-07-03 (silent axis
regression): `velocity.label_source` records the rows-1-2 convention in the committed JSON and the
evidence carries the measured correlations. T-09-07-04 (the readout changing the graph): no training
loop, no new op type, and the forward-parity gate measures that the assembled graph computes exactly
the fitted linear map. T-09-07-05 (a low R2 quietly clamped or re-rolled): no clamp exists in the
script or in `heldout_r2`, and nothing was re-run with different settings. T-09-07-06 (checkpoint
deserialization): the encoder loads through `ndt1.train.load_checkpoint`, i.e.
`torch.load(weights_only=True)`.

## Verification

```
uv run --project Decoder ruff check Decoder                                  -> All checks passed
uv run --project Decoder pytest Decoder/tests -m "not slow" -q               -> 189 passed, 9 deselected
uv run --project Decoder python Decoder/scripts/fit_velocity_real.py --smoke -> 0
uv run --project Decoder python Decoder/scripts/fit_velocity_real.py         -> 0 (1,255.9 s)
git status --porcelain Decoder/checkpoints Decoder/data                      -> 0 lines
git diff --stat .../09-decoder-metrics.json                                  -> 240 insertions(+), 0 deletions
```

Both of the plan's inline verify blocks print `OK`. Every acceptance grep passes, including the
negative controls: no `max(0` or `np.clip(...r2` clamping, no bare or blind `except`, and the
evidence contains none of `photodiode`, `24.7`, `226/226`, the Neural Engine acronym, `p99` or
`palettiz` (those belong to Plan 09-08).

## Next Phase Readiness

- **Plan 09-08** has its input: `Decoder/checkpoints/ndt1_real_with_velocity.pt`, sha256
  `9d542cb51d4af4811f324fbc6bda0b503da7b15aafc98b5e1340e1a7f49cce65`, 1,292,738 parameters, with
  all 101 encoder tensors bit-identical to the Plan 09-06 pooled checkpoint. No new op type was
  introduced and no training loop was run, so the traced graph is the one Phase 5 characterized;
  Plan 09-08 should re-verify that rather than inherit the claim.
- **Plan 09-08 must also carry the parity number forward.** The PyTorch side of any converted-model
  parity check should be compared against 4.8e-05 cm/s, the measured float32-conv-versus-float64-
  solve floor, so a conversion delta can be separated from the readout's own rounding.
- **Plan 09-09** gains a `velocity` block to schema-assert: `lag_sweep` is exactly nine rows with
  `lag_bins` 0 to 8, `lambda_sweep` is six rows, `per_session` keys equal the four session ids, and
  `heldout_r2` carries `vx`, `vy`, `pooled` and `n`.
- **Plan 09-10** has one more superseded number to label: `05-velocity-head-evidence.md`'s 0.99985
  and `Decoder/checkpoints/velocity_r2.json`. Any document claiming this repository has never
  measured real velocity decode is now contradicted by `09-velocity-evidence.md`.
- **Phase 10 RD-07** can fit `R` from real `z_decoded` versus `v_true` residuals: the labels are
  real, the sign is explicit rather than inherited, and the readout is the one that ships.
- **Open constraint on everything downstream:** 0.4238 may be quoted only as the POOLED,
  WITHIN-POOL, held-out velocity R2 against a constant TRAIN-split mean-velocity null, at a 20 ms
  lag with 20 ms bins and a single-bin rank-2 linear readout, with the per-session range +0.1446 to
  +0.5069 attached and with no error bar claimed. It must never be set against the 0.633-0.838 range
  from arXiv 2406.06626 as a comparison in either direction: different bin width, different readout
  class, different protocol. It is not a cross-session transfer result and must not be quoted as
  one.

## Status rationale

`PARTIAL`, not `PASS`. Both tasks executed and committed, every verification command is green, the
success criteria are met, and no number was clamped or re-rolled. Four flagged gaps prevent a clean
`PASS`, all four recorded in `deferred-items-09-07.md`:

1. **No cross-session velocity readout was measured**, so only the within-pool half of this phase's
   central question has a velocity answer.
2. **No error bar exists anywhere in the artifact**, and the held-out bins are autocorrelated, so
   the reported precision is not established.
3. **The per-session spread has a suggestive but unestablished explanation**: one of four sessions
   has a measured drift figure.
4. **The lag interpretation is untested**, though the alignment question it raises is answered by
   measurement.

## Self-Check: PASSED

Files claimed created, verified present on disk:

- `Decoder/scripts/fit_velocity_real.py` FOUND (916 lines)
- `.planning/phases/09-.../09-velocity-evidence.md` FOUND (362 lines)
- `.planning/phases/09-.../deferred-items-09-07.md` FOUND (77 lines)
- `.planning/phases/09-.../09-07-SUMMARY.md` FOUND
- `.planning/phases/09-.../09-decoder-metrics.json` FOUND (modified, 240 insertions, 0 deletions)
- `Decoder/checkpoints/ndt1_real_with_velocity.pt` FOUND (gitignored, sha256 verified)

Commits claimed, verified in `git log 06e6fee..HEAD`: `ba47798` FOUND, `e9f3760` FOUND,
`99c48d3` FOUND.

Commit ORDERING verified, which is this task's load-bearing provenance claim:
`git merge-base --is-ancestor ba47798 e9f3760` exits 0, so the four selection rules were committed
before the commit carrying the numbers they produced. The only execution before `ba47798` was a
3000-bin `--smoke` wiring check writing to gitignored scratch paths.

Number provenance verified rather than trusted: every table in `09-velocity-evidence.md` was
rendered from the committed `09-decoder-metrics.json` by script rather than transcribed, and the
committed values were checked line by line against the run log at
`Decoder/checkpoints/09-07-logs/velocity.log`. The compute-time breakdown in the evidence was
measured (1.9 s to load the four sessions, 0.7 s to hash their 1.77 GB) rather than inferred from
the gap between timestamps.

The shipped checkpoint was reloaded from disk and its encoder compared tensor by tensor against
`ndt1_real_pooled.pt`: 101 of 101 `torch.equal`, 0 missing, 0 different.

Files this plan did NOT touch, as required by its file discipline: `kinematics.py`, `qc.py`,
`sessions.py`, `train.py`, `loss.py`, `velocity_head.py`, `model_ane.py`, `STATE.md`, `ROADMAP.md`,
`REQUIREMENTS.md`, `PROJECT.md`, the shared `deferred-items.md`, and every Phase 4 and Phase 5
artifact.

---
*Phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034*
*Completed: 2026-09-02*
