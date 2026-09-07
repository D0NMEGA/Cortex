---
status: PASS
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 10
subsystem: docs
tags: [citation-sweep, evidence-discipline, supersession, provenance, co-bps, palettization, ane, rd-03, rd-05, d-24]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 06d
    provides: "09-training-evidence.md and the co_bps section of 09-decoder-metrics.json, including the four-link supersession chain and the re-derived CO_BPS_MARGIN"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 07
    provides: "09-velocity-evidence.md and the velocity section of the metrics JSON, which supersede velocity_r2.json's 0.99985"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 08
    provides: "09-coreml-evidence.md, the 239-op tally, the palettization re-derivation, and the checkpoints-hidden attribution control that makes every difference attributable to the weights"
provides:
  - "Superseded banners on 04-training-evidence.md, 04-palettization-evidence.md and 05-velocity-head-evidence.md, each with a resolving relative link to its Phase-9 replacement and zero deleted lines"
  - "PROJECT.md: both co-bps 0.3804 citations labeled invalid on BOTH counts (synthetic data AND the visible-input objective), the palettization and ANE and p99 lines labeled by provenance, the v1 Phase-9 item checked off with the split result, and a Key Decisions row for the Option B session set"
  - "ROADMAP.md: Phase-4 and Phase-5 bullets labeled, all five Phase-9 success criteria annotated against what was measured, including SC#4 whose presumed conclusion is recorded as falsified"
  - "REQUIREMENTS.md: RD-01..RD-06 checked with their committed values and proving artifacts, RD-07..RD-10 left for Phase 10, DEC-06/DEC-08 226 tallies annotated with the 239 correction, RD traceability rows filled"
  - "deferred-items-09-10.md: seven out-of-scope citation discoveries handed to RD-09 and RD-10"
affects: [09-11, Phase 10, RD-09, RD-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Preserve, never delete: a superseded evidence artifact keeps its measured content byte-for-byte and gains a banner, so `git diff --numstat` showing 0 deletions is itself the audit check that nothing was retroactively rewritten"
    - "State the supersession reason count explicitly: 0.3804 is invalid on TWO independent counts, and a banner that names only one of them under-reports the correction"
    - "Say which superseded numbers were expected to reproduce and which were not, before quoting the new ones: the size ratio reproduces because compression does not depend on weight values, the NLL delta does not because k-means centroids are fit to them"
    - "A citation sweep must not launder a negative result: every summary line carrying the pooled co-bps also carries the four negative cross-session folds"
    - "Verify a plan-supplied fact before transcribing it: the plan's `finger_pos` widths claim and its `test_convert_velocity_output.py:55` attribution were both checked against the data and the code, and one of them was wrong"

key-files:
  created:
    - ".planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/deferred-items-09-10.md"
  modified:
    - ".planning/phases/04-ndt1-training-on-indy-loco-synthetic-replay/04-training-evidence.md"
    - ".planning/phases/04-ndt1-training-on-indy-loco-synthetic-replay/04-palettization-evidence.md"
    - ".planning/phases/05-ndt1-coreml-deployment-with-ane-residency-verified/05-velocity-head-evidence.md"
    - ".planning/PROJECT.md"
    - ".planning/ROADMAP.md"
    - ".planning/REQUIREMENTS.md"

key-decisions:
  - "Banner 0.3804 as invalid on BOTH counts, not just synthetic. The plan assumed one reason; 09-06b established a second, the visible-input objective, and the same code path produced the 1.9116 real-data figure that exposed it."
  - "Cite the correct producer of the superseded 0.99985. Phase 9's own artifacts attribute it to test_convert_velocity_output.py:55; velocity_r2.json is actually written by test_velocity_head.py:155. The banner names the real producer and the mis-attribution is logged for RD-09."
  - "Annotate ROADMAP SC#4 as MET with its presumed conclusion falsified, rather than quietly reinterpreting the criterion. The criterion asked for the report; the report says the encoder does not transfer."
  - "Extend the sweep to the 226 op tally on the three surfaces this plan owns. The success criteria require it and 226 is factually wrong on the shipped graph; 05-ane-eligibility-evidence.md and README carry the same number and are deferred to RD-09."
  - "Leave the ROADMAP Phase-9 progress row at 10/11 In progress rather than marking the phase complete, because 09-11's HUMAN-UAT gate is a separate agent's deliverable and is presented, not resolved."

patterns-established:
  - "Numeric provenance check: extract every number from the diff's added lines and assert each appears in 09-decoder-metrics.json or a Phase-9 evidence artifact before committing"
  - "Word-level ASCII audit: git diff --word-diff=porcelain isolates the text this plan actually authored from the pre-existing text on the same line, so the ASCII-only convention can be enforced without reformatting surrounding prose"

requirements-completed: [RD-03, RD-05]

# Metrics
duration: 22min
completed: 2026-09-02
---

# Phase 9 Plan 10: D-24 citation sweep Summary

**The repository stops citing the numbers this phase invalidated: co-bps 0.3804 is now labeled invalid on both counts wherever it appears on a decoder-owned surface, the Phase-5 op tally of 226 is corrected to 239 with the stale-artifact bug that produced it named, and the three superseded evidence artifacts carry forward-pointing banners with zero deleted lines.**

## Performance

- **Duration:** 22 min
- **Tasks:** 2 of 2
- **Files modified:** 6, plus 1 created
- **Commits:** 3

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Superseded banners on the three historical evidence artifacts | `b489fdf` | 04-training-evidence.md, 04-palettization-evidence.md, 05-velocity-head-evidence.md |
| 2 | Label the synthetic numbers on the three decoder-owned planning surfaces | `b52cd6e` | PROJECT.md, ROADMAP.md, REQUIREMENTS.md |
| - | Out-of-scope discoveries logged | `0675ccc` | deferred-items-09-10.md |

## What changed

### The three superseded artifacts (banner only, zero deletions)

`git diff --numstat` reports 26/0, 22/0 and 22/0 for the three files. Not one measured value, table row or methodology sentence was altered. That is the check D-24 asks for: a historical evidence artifact records what its phase actually measured, and the only honest correction is a banner.

**`04-training-evidence.md`** now leads with the two independent reasons its co-bps is invalid. The plan was written assuming one (the synthetic Poisson fallback that the file's own Methodology section already discloses). Plan 09-06b established a second: `train.py` fed the encoder unmasked spike counts and used the mask only to select which positions the loss was summed over, so the model could read the value at every position it was scored on. The same code path produced the first real-data figure of 1.9116, roughly 10x the NLB'21 `mc_rtt` range, which is what exposed it. The banner names both and points at the real number.

**`04-palettization-evidence.md`** separates the number that was expected to reproduce from the one that was not, and says why before quoting either. The size ratio 3.471x reproduces at 3.4134x because the architecture, the parameter count and which tensors clear `weight_threshold=2048` are unchanged by training. The Poisson-NLL delta 0.009114 does not reproduce (0.020352) because k-means centroids are fit to the actual weight values. The banner also records the finding behind that: coremltools uses its bundled `kmeans1d` only for tensors with at least 10,000 elements and falls through to scikit-learn's `KMeans` below that, so this model's 4,096-element positional encoding takes the scikit-learn path, which is why `scikit-learn>=1.5` is now a declared dependency of `Decoder/`.

**`05-velocity-head-evidence.md`** states precisely what 0.99985 was: a self-consistency check, not a decode result. See the deviation below on which test actually produced it.

### The three planning surfaces

**PROJECT.md** (13 added, 8 removed). Both 0.3804 citations are labeled synthetic and defective-objective and point at 0.4096 with its artifact. The DEC-05 palettization bullet and its Active-list twin are labeled random-init with the real-data replacements. The ANE bullet carries the 239 correction; the p99 bullet carries the real-weights 0.141083 ms on Apple M5 Pro with its CPU-placed, corroborating label. The v1 Phase-9 item is checked off with a four-bullet block giving the pooled co-bps, the within-versus-across-session split, the velocity R2 and the CoreML results, every one device- and method-labeled. The Key Decisions table gains a row for the Option B session set and its CoreML row now records the 226-to-239 correction and the `compile_model` defect that caused it.

**ROADMAP.md** (10 added, 4 removed). Exactly what changed, since the orchestrator asked:

| Line | Change |
| ---- | ------ |
| Phase-4 bullet (line 29) | co-bps 0.3804 labeled "on synthetic Poisson replay and under a defective objective", 3.471x labeled "on a randomly-initialized graph", both pointed at their Phase-9 re-derivations |
| Phase-5 bullet (line 30) | appended the 226-to-239 correction, naming the stale compiled artifact and the `shutil.move` nesting that caused it; notes eligibility survives |
| Phase-9 SC#1 | new sub-bullet: MET, 1.77 GB pinned, zero PENDING, four negative controls, one pre-filled pin re-verified |
| Phase-9 SC#2 | new sub-bullet: MET, four sessions at 96 channels, 285,359 bins, plus the truthy-`MATLAB_empty` deref defect found and fixed |
| Phase-9 SC#3 | new sub-bullet: MET, co-bps 0.4096 / 0.3814, margin 0.054, 0.3804 superseded twice over, sweep scoped to decoder-owned surfaces |
| Phase-9 SC#4 | new sub-bullet: **MET, and the presumed conclusion is falsified.** The criterion's own wording assumed "generalizes across four sessions"; the four negative LOSO folds say otherwise, and the annotation says so plainly |
| Phase-9 SC#5 | two new sub-bullets: MET with two corrections (op tally, 4-bit velocity collapse), plus the checkpoints-hidden attribution control |
| Plan list | `09-10-PLAN.md` checkbox flipped to `[x]`. **`09-11-PLAN.md` left unchecked** |
| Progress table row for Phase 9 | `0/11 | Planned | -` became `10/11 | In progress (09-11 HUMAN-UAT outstanding) | -` |

Nothing else in ROADMAP.md was touched. The Milestones block, the Future work section, and every other phase's rows are untouched.

**REQUIREMENTS.md** (14 added, 14 removed). RD-01 through RD-06 are checked, each with its committed value and the artifact that proves it; RD-07 through RD-10 remain unchecked. RD-06's check-off states explicitly that the canonical iPad-Pro-M4 capture is deferred and never auto-approved, so the checkbox does not imply a device measurement that did not happen. DEC-06 and DEC-08 gain the 239 correction inline. The six RD traceability rows moved from `TBD` to their plan lists.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 1 - Bug] The plan's attribution of the superseded 0.99985 is to the wrong test**

- **Found during:** Task 1, verifying the `05-velocity-head-evidence.md` banner before writing it.
- **Issue:** The plan instructed the banner to say `test_convert_velocity_output.py:55` generates labels as `last_bin @ w_true + 0.01 * noise`. That instruction was inherited from `09-velocity-evidence.md:69` and `Decoder/scripts/fit_velocity_real.py:13`, which say the same thing. But `velocity_r2.json`, the file `05-velocity-head-evidence.md` sources 0.99985 from, is written by `Decoder/tests/test_velocity_head.py:155`, in `test_load_ridge_reproduces_linear_map_and_records_r2`. That test uses `n = 800` with `split = 600`, giving the `n=200` the Phase-5 artifact reports; `test_convert_velocity_output.py` uses `n_windows = 64`.
- **Fix:** The banner cites the correct producer and its actual label construction, `x_all @ w_true + b_true + 0.01 * noise`. The substance of the Phase-9 claim is unaffected, since both tests build labels as a seeded linear map of the design matrix plus noise and are therefore both self-consistency checks. Only the file reference was wrong.
- **Files modified:** `05-velocity-head-evidence.md`
- **Commit:** `b489fdf`
- **Deferred:** correcting the two Phase-9 references is logged as item 5 in `deferred-items-09-10.md`; both files are outside this plan's `files_modified`.

**2. [Rule 2 - Missing critical labeling] Extended the sweep past the two lines the interfaces table named**

- **Found during:** Task 2.
- **Issue:** The plan's `<interfaces>` table located two PROJECT.md lines (41 and 55). Three more decoder-owned lines on the same surfaces cite numbers this phase invalidated: PROJECT.md's DEC-05 palettization bullet, its Active-list palettization twin, and the Key Decisions CoreML row with its 226 tally. REQUIREMENTS DEC-06 and DEC-08 carry the same 226. Leaving them unlabeled is exactly threat T-09-10-01, an unlabeled synthetic number reading as a real-data result, and the prompt's success criteria require the 226 correction explicitly.
- **Fix:** Labeled all five, each with the real-data replacement and its artifact. Every edit is an in-place clause append; no line was restructured or reformatted.
- **Files modified:** `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`
- **Commit:** `b52cd6e`

**3. [Rule 3 - Blocking] Rephrased an RD-03 cross-reference that would have broken the plan's own acceptance check**

- **Found during:** Task 2 verification.
- **Issue:** The RD-03 line originally ended "README and ADR-0002 remain for RD-09". The plan's acceptance check finds each requirement's line with `if rid in l`, so the literal `RD-09` inside the RD-03 line made the RD-09 lookup match RD-03's checked line and fail the assertion. A committed doc should not trip a documented gate.
- **Fix:** Rephrased to "remain for the Phase-10 repo-wide sweep". The plan's verification block now passes verbatim.
- **Files modified:** `.planning/REQUIREMENTS.md`
- **Commit:** `b52cd6e`

### Plan facts verified rather than transcribed

The plan's Key Decisions row asserted the chosen sessions "exercise both `finger_pos` widths". Nothing in the Phase-9 evidence artifacts states this, so it was checked directly against the data: `indy_20160624_03`, `indy_20160627_01` and `indy_20160630_01` are `(6, k)` and `indy_20160915_01` is `(3, k)`. The claim is true and is written with the specific layouts named rather than as a bare assertion.

Every number written into the three planning surfaces was extracted from the diff and checked against `09-decoder-metrics.json` or one of the four Phase-9 evidence artifacts. Two exceptions, both accounted for: `2,678,038` and `771,534` are the pre-existing Phase-4 byte counts on a line that was appended to, not introduced here; and the count of 498 spurious timestamps is sourced from `09-CONTEXT.md` C-05, which the ROADMAP annotation now cites by name.

## Scope boundary held

`git diff --name-only` across all three commits lists only the six planned files plus the deferred-items file. Untouched, and verified green afterward:

- `README.md`, `docs/adr/*` -- Phase 10, RD-09
- `Tools/scripts/readme-policy.sh` -- still REQUIRES the literal `photodiode` and `24.7` tokens; RD-10 rewrites it in lockstep with the README
- `Tools/scripts/bps-policy.sh` -- the ReFIT BPS numbers are Phase 10's; no BPS figure was relabeled, re-derived, or placed adjacent to a Phase-9 number in a way that implies real-data provenance
- `.planning/STATE.md` -- orchestrator-owned
- `.planning/phases/09-.../09-HUMAN-UAT.md` -- Plan 09-11's sole file, executed concurrently by another agent
- `.planning/phases/07-*`, `.planning/phases/08-*`

## Verification

```
uv run --project Decoder pytest Decoder/tests -m "not slow" -q   208 passed, 9 deselected in 4.59s
./Tools/scripts/decoder-policy.sh                                 exit 0
./Tools/scripts/decoder-policy.sh --self-test                     exit 0
./Tools/scripts/readme-policy.sh                                  exit 0
./Tools/scripts/readme-policy.sh --self-test                      exit 0
./Tools/scripts/bps-policy.sh                                     exit 0
./Tools/scripts/bps-policy.sh --self-test                         exit 0
git diff --numstat on the three Phase-4/5 artifacts                26/0, 22/0, 22/0 (zero deletions)
plan verification block (banners + citation sweep + scope)         all assertions pass
```

The three superseded artifacts' relative links were resolved against the filesystem before writing and re-checked after: all six targets exist.

## Known stubs

None. This plan is documentation-only; it changes no code, adds no test, and introduces no placeholder.

## Threat flags

None. No file this plan touched introduces a network endpoint, auth path, file-access pattern or schema at a trust boundary. The plan's own register was about citation integrity, and each disposition was met: every retained synthetic number gained a label on the same surface (T-09-10-01), all three historical artifacts show zero deletions (T-09-10-02), every written number traces to a committed artifact (T-09-10-03), the README and policy scripts were untouched and re-verified green (T-09-10-04), each RD checkbox cites its proving artifact and RD-07..RD-10 stay unchecked (T-09-10-05), and all six banner links resolve on disk (T-09-10-06).

## One deliberate non-ASCII character

The Key Decisions table's Outcome column marks a validated decision with a check glyph, in 16 of its 19 data rows (the other three read Pending, Superseded and Accepted). The new row matches that vocabulary, so the table reads consistently. Every other character this plan authored is ASCII, verified by a word-level diff that isolates inserted text from the pre-existing text on the same line.

## Self-Check: PASSED

- `.planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-10-SUMMARY.md` FOUND
- `.planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/deferred-items-09-10.md` FOUND
- Commit `b489fdf` FOUND
- Commit `b52cd6e` FOUND
- Commit `0675ccc` FOUND
