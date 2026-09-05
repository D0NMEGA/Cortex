---
status: PASS
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 01
subsystem: testing
tags: [pre-registration, numpy, h5py, webgrid, evidence-discipline, indy, refit]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    provides: the four checksum-pinned Indy sessions, the manifest with verified sha256 digests, the per-session held-out velocity R2, and the evidence-artifact format
  - phase: 07-refit-kalman-closed-loop-recalibration
    provides: WebgridAcquisition's continuous dwell-to-select semantics and the documented dwell / radius / timeout defaults
provides:
  - the Phase 10 measurement contract (10-PREREGISTRATION.md), which every later plan in the phase cites
  - the pre-registered R residual units (grid-units/s), workspace box, dual-N BPS rule, fourth-arm target source, Seam A / Seam B split, model-in-loop assertion, three artifact schemas and four disclosure strings
  - the RD-08 hit criterion as a three-row disposition table fixed before any hit count exists
  - the recorded-cursor webgrid replay reference for indy_20160630_01 (147 of 1,025 trials), bound to the manifest sha256
  - Decoder/scripts/webgrid_ceiling.py, the only place in the repo that reads cursor_pos
affects: [10-02, 10-03, 10-07, 10-09, 10-10, 10-11, 10-12, 10-14, refit-real-data-ablation, rd-08-replay, readme-republish]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pre-registration as a committed artifact whose git ancestry is the audit trail"
    - "Pure-function-plus-IO-layer split so every rule is unit-testable with no dataset present"
    - "Source self-check (D-09) extended from a test module to the script it tests"

key-files:
  created:
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-PREREGISTRATION.md
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-ceiling.json
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-ceiling-evidence.md
    - Decoder/scripts/webgrid_ceiling.py
    - Decoder/tests/test_webgrid_ceiling.py
    - .planning/phases/10-v1-real-data-closed-loop-launch/deferred-items.md
  modified: []

key-decisions:
  - "R is fit in grid-units/s, not cm/s: the two differ by k^2 and the committed default R = diag(0.25) was already documented as (grid-units/s)^2"
  - "The workspace box is cursor_bbox_square, derived from the session's own cursor track, because normalising on the 105 mm target field would clip real excursions through CursorIntegrator's [0,1] clamp"
  - "Both N normalisations are reported; N=900 stays the headline for continuity with Phase 8's 1.953 but carries the counterfactual-grid-score label in the same row as N=64"
  - "The fourth arm reverses the rotation target in time while the scoring target stays true, so all four arms remain comparable"
  - "Latency is split into Seam A (Phase-8 geometry, one variable changed) and Seam B (the full D-05 chain), because the Phase-8 8.3 ms had no IPC leg and was not model-backed"
  - "Neither seam is routed through the PERF-04 verdict: the real-data path emits no passed field and exits 0 whatever the p99 (D-09)"
  - "The RD-08 hit criterion is fixed as a three-row disposition table before any hit count exists, with row B (zero hits, not_met) named as the expected outcome"
  - "The replay reference is published as a recorded-cursor replay result, never as a bound on any decoder; the ceiling framing was rejected on review"
  - "The replay reference at the canonical geometry is 147, which is >= 1, so a decoded zero lands in row B and cannot be routed to row C's cannot-discriminate escape"

patterns-established:
  - "Pre-registration precedence: where the pre-registration and CONTEXT/RESEARCH disagree, the pre-registration governs and the disagreement is stated rather than resolved silently"
  - "Reproduction check without tuning: a control's rules are pinned on synthetic arrays with hand-known answers, so agreement with an expected table is evidence rather than circularity"
  - "Containment checks are made exact by construction rather than loosened with a tolerance"

requirements-completed: [RD-07, RD-08]

# Metrics
duration: 14min
completed: 2026-09-05
---

# Phase 10 Plan 01: Pre-registration and the recorded-cursor replay reference Summary

**Every Phase 10 measurement convention fixed in writing before any number exists, plus the recorded-cursor webgrid replay reference for indy_20160630_01 measured at 147 of 1,025 trials and bound to the manifest sha256.**

## Performance

- **Duration:** 14 min (first commit to last)
- **Started:** 2026-09-05T21:29:00Z
- **Completed:** 2026-09-05T21:43:00Z
- **Tasks:** 3
- **Files created:** 6

## Accomplishments

- `10-PREREGISTRATION.md` (478 lines) fixes the R residual units, the workspace box, the dual-N BPS
  rule and its label, the fourth arm's target source, the Seam A / Seam B latency split, the
  model-in-loop assertion, all three artifact schemas and all four disclosure strings, before any
  of the numbers they govern exists.
- Section 15 resolves the standing conflict between RD-08's "a 30x30 webgrid hit demonstrated" and
  D-11's "a zero is publishable" as a three-row disposition table, committed before the
  measurement, and names row B (zero hits, `not_met`) as the expected outcome on the pre-execution
  evidence rather than leaving it as a contingency.
- `webgrid_ceiling.py` reproduces the repo's continuous dwell-to-select rule, is the only place in
  the repo that reads `cursor_pos`, never indexes the waveform array, and has every rule
  unit-tested on synthetic arrays so the quick suite stays green with no dataset present.
- The measurement reproduces all twelve RESEARCH Correction 4 reference cells exactly
  (43/83/147/249/951/1023 at dwell 0.30 s; 153/242/334/449/1007/1025 at 0.10 s) over 1,025 trials.
- The reference at the canonical geometry is 147, which is `>= 1`. That closes the denominator side
  of the hit contract in advance: a decoded zero must land in row B (`not_met`) and cannot be routed
  to row C's cannot-discriminate escape.

## Task Commits

1. **Task 1: 10-PREREGISTRATION.md** - `864259b` (docs)
2. **Task 2: webgrid_ceiling.py, TDD** - `274c909` (test, RED) -> `ec1fccd` (feat, GREEN) -> `2dbc0d1` (fix, containment defect found in Task 3)
3. **Task 3: run and publish the reference** - `69ccd6f` (docs, both artifacts in one commit)

## Files Created

- `.planning/phases/10-v1-real-data-closed-loop-launch/10-PREREGISTRATION.md` - the phase's
  measurement contract, 18 sections, with the no-edit-after-measurement rule in its own frontmatter
- `Decoder/scripts/webgrid_ceiling.py` - the recorded-cursor dwell-to-select replay reference:
  four pure numpy functions, a manifest-bound I/O layer, explicit exception types only
- `Decoder/tests/test_webgrid_ceiling.py` - 13 hermetic tests, no dataset, including the D-09
  source self-check applied to both the test module and the script
- `.planning/phases/10-v1-real-data-closed-loop-launch/10-ceiling.json` - the 13 pre-registered
  top-level keys, `data_source: real`, bound to the session sha256
- `.planning/phases/10-v1-real-data-closed-loop-launch/10-ceiling-evidence.md` - machine, wheel
  versions, runbook, computed box, full radius-by-dwell table, reproduction check, hit contract
- `.planning/phases/10-v1-real-data-closed-loop-launch/deferred-items.md` - one out-of-scope
  tooling finding

## Decisions Made

Beyond the pre-registered decisions listed in the frontmatter, three were made during execution:

- **The strict-versus-inclusive dwell boundary is documented, not reconciled.**
  `WebgridAcquisition.runTrial` accepts a sample exactly on the radius (`<=`); this script is
  strictly inside (`<`), matching the reference implementation the pre-registered table was
  measured with. On continuous-valued millimetre distances the boundary is measure-zero. Choosing
  `<=` to "match Swift" would have silently changed the table this run is checked against.
- **The reproduction check is made non-circular by construction.** The dwell and segmentation rules
  are pinned independently in `test_webgrid_ceiling.py` on synthetic arrays whose answers are known
  by hand, so agreement with RESEARCH Correction 4 is evidence rather than a tautology. The plan
  forbade adjusting the script to match; nothing had to be adjusted, since all twelve cells agreed.
- **`10-ceiling.json` emits `canonical` per table row** rather than only naming the canonical cell
  at top level, so the canonical row is identifiable from the table alone.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] square_box containment failed on all 365,809 samples from a floating-point defect**

- **Found during:** Task 3 (the first real run, which exited 1 before producing any number)
- **Issue:** The box edge on the span-defining axis was computed as `centre +/- side/2`, which does
  not round-trip to the observed extreme. The `x_max` sample landed 1.4e-14 mm outside the box, so
  the strict containment check refused the whole session. Diagnosis confirmed all 365,809 samples
  are finite and the x span is the governing one: there was no data problem.
- **Fix:** The governing axis now takes the observed extremes verbatim. That is the same square in
  exact arithmetic, so it fixes the floating-point evaluation and not the convention, and
  `10-PREREGISTRATION` section 3 is unchanged. The check was deliberately **not** loosened into a
  tolerance: a tolerance wide enough to swallow this would also swallow a genuinely clipped
  excursion, which is the exact failure the check exists to catch.
- **Files modified:** `Decoder/scripts/webgrid_ceiling.py`, `Decoder/tests/test_webgrid_ceiling.py`
- **Verification:** `test_square_box_containment_is_exact_on_the_governing_axis` pins the exactness
  with `==` rather than `approx`, because `approx` would pass under the very defect it guards. It
  covers both axis orders. 13 tests green; the run then produced the number.
- **Committed in:** `2dbc0d1`

**2. [Rule 3 - Blocking] The gitignored dataset is absent in the worktree**

- **Found during:** Task 3
- **Issue:** `Decoder/data/` is gitignored, so the worktree had no `.mat` file and the
  dataset-gated measurement could not run.
- **Fix:** Created `Decoder/data/` and symlinked the already-materialized, checksum-pinned
  `indy_20160630_01.mat` from the canonical checkout, so the plan's runbook command ran verbatim
  with its default `--data-dir`. Nothing was re-downloaded and nothing was committed.
- **Verification:** `git check-ignore -v` reports `.gitignore:90:Decoder/data/` covers the link;
  `git status --short` shows no untracked dataset path. Recorded in the evidence artifact.
- **Committed in:** nothing to commit (gitignored)

**3. [Rule 1 - Bug] The reproduction-check table did not satisfy its own literal acceptance grep**

- **Found during:** Task 3 (acceptance check)
- **Issue:** The acceptance criterion greps for a bare `| 1.75 |` cell; the table wrote
  `| 1.75 mm |`, so the check failed.
- **Fix:** Moved the unit into the column header (`Radius (mm)`) and left bare numbers in the
  cells. This is the documented literal-grep-rewording pattern this project has used since Phase 1,
  and it reads better.
- **Files modified:** `.planning/phases/10-v1-real-data-closed-loop-launch/10-ceiling-evidence.md`
- **Verification:** The acceptance check now passes; no number changed.
- **Committed in:** `69ccd6f`

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking)
**Impact on plan:** All three were necessary to produce the plan's own artifacts. No scope creep,
no new dependency, no change to any pre-registered convention. Deviation 1 is the only one that
changed shipped code, and it is documented in the evidence artifact as well as here, because it
changed code during a measurement run.

## Deferred Items

One out-of-scope finding was logged and deliberately not fixed, in
`.planning/phases/10-v1-real-data-closed-loop-launch/deferred-items.md`: the editor hook's `ty`
pass resolves `Decoder/` imports against the Homebrew interpreter rather than the uv-managed
`Decoder/.venv`, so it reports `unresolved-import` for `h5py` and `pytest`. The same diagnostic
appears on the pre-existing `Decoder/src/ndt1/data.py`, and the project's own toolchain is clean
(`ruff check Decoder` zero findings, 221 tests passed). Fixing it would touch shared hook
configuration while other Phase 10 worktrees are running.

## Issues Encountered

The containment failure in Task 3 was the only blocker, and it was diagnosed rather than worked
around: the first move was to read the actual floating-point values and the offending sample index,
which showed the failure was one sample at the exact bounding-box extreme with a -1.4e-14 mm delta,
not a data-quality problem. Loosening the check would have hidden a real defect class.

## Verification

All commands run on `Apple M5 Pro`, macOS 26.5, in this worktree:

| Command | Result |
|---|---|
| `uv run --project Decoder ruff check Decoder` | exit 0, all checks passed |
| `uv run --project Decoder pytest Decoder/tests/test_webgrid_ceiling.py -q` | 13 passed |
| `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` | 221 passed, 9 deselected |
| The same, with `Decoder/data` moved away | 220 passed, 1 skipped, 9 deselected |
| `./Tools/scripts/decoder-policy.sh` | exit 0 |
| `./Tools/scripts/decoder-policy.sh --self-test` | exit 0, all three negative controls bite |
| Task 1 automated verify (10 literal greps plus one negative) | exit 0 |
| Task 3 automated verify (13 keys, data_source, sha256 length, disclosure) | `OK 147 / 1025 at r = 2.8613660406415042 mm` |
| `source_sha256` vs `Decoder/manifests/indy_sessions.json` | MATCH, 64 lowercase hex |

Every acceptance criterion in all three tasks was checked programmatically, including the negative
ones: the pre-registration contains no occurrence of the rejected ceiling framing, no unsourceable
Neuralink figure, and no "near-zero uplift is the published expectation" wording.

## Threat Model Coverage

All seven mitigations in the plan's register are implemented, not just planned:

| Threat ID | How it is closed |
|---|---|
| T-10-01-01 | `session_entry` refuses a `PENDING` or non-64-hex digest; the emitted JSON carries the full digest and `manifest_path`; the acceptance check compares the two files |
| T-10-01-02 | The pre-registration's frontmatter carries the `rule:` prohibition, and `864259b` precedes `69ccd6f`, which precedes every decoded-number commit |
| T-10-01-03 | `load_tracks` indexes only `target_pos` and `cursor_pos` and closes the file; `test_the_script_never_reads_the_waveform_array` asserts the dataset name set structurally |
| T-10-01-04 | The dwell rules are pinned on synthetic arrays with hand-known answers; nothing was adjusted to reproduce the expected table, and all twelve cells agreed anyway |
| T-10-01-05 | Only aggregate counts are committed; the dataset link is gitignored, verified with `git check-ignore`, and the suite is proven to pass with the dataset absent |
| T-10-01-07 | The objective, the evidence header, a `What this is not` paragraph and pre-registration section 16 all state it is one trajectory under one rule; the banned framings appear nowhere |
| T-10-01-08 | Section 15 fixes the three-row table before the measurement, forbids relaxation in every row, forbids an agent amending a success criterion, and routes `sc2_disposition` to a schema test that asserts presence and not value |

`T-10-01-06` remains the plan's accepted risk, unchanged: no new dependency was added and no
network call is made.

## Next Plan Readiness

- Every convention Plans 10-02 onward depend on is committed and citable. Plan 10-03's R fit has
  its units, its `k` conversion and its `noise source = indy-heldout` acceptance already fixed.
- The `cursor_bbox_square` box for `indy_20160630_01` is measured and committed
  (`side_mm` 171.68196243849025, `cell_mm` 5.7227320812830085, `acq_radius_mm` 2.8613660406415042),
  so the D-06 export and the RD-08 replay consume numbers rather than recompute them.
- `10-replay.json`'s consumer names are fixed as `replay_reference_hits` and
  `replay_reference_ref`; `ceiling_hits` and `ceiling_ref` are not emitted.
- Row C is ruled out at this geometry. A zero-hit RD-08 outcome is row B, `not_met`, which
  pre-registration section 15 routes to a blocking user checkpoint at Plan 10-10 Task 3. Downstream
  executors must not treat that as a defect to fix or a criterion to restate.
- Flagged, not edited: `ROADMAP.md:204` still describes "the 3-way ablation" while D-04 locks a
  fourth arm. Amending a success criterion is the user's call.

*Phase: 10-v1-real-data-closed-loop-launch*
*Completed: 2026-09-05*

## Self-Check: PASSED

All 5 created artifacts and both source files exist on disk. All 5 task commits resolve as commit
objects. The ordering claim holds: `864259b` (the pre-registration) is an ancestor of `69ccd6f`
(the measured number), so the contract is provably older than the result it governs (T-10-01-02).
