---
status: PASS
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 03a
subsystem: infra
tags: [pre-registration, workspace-box, kalman, refit, numpy, h5py, indy, evidence-discipline]

# Dependency graph
requires:
  - phase: 10-v1-real-data-closed-loop-launch
    provides: 10-PREREGISTRATION section 3, Plan 10-01's recorded-cursor replay reference and its committed box, Plan 10-02's export and Plan 10-03's Kalman re-fit
provides:
  - 10-PREREGISTRATION section 3a, the dated amendment fixing the workspace box on the recorded cursor_pos track
  - ndt1.replay_export.workspace_from_cursor as the ONE authoritative box implementation, with webgrid_ceiling and fit_kalman_gain delegating to it
  - ndt1.replay_export.count_outside_box, which makes the containment argument executable at the export site
  - Decoder/scripts/export_replay.read_cursor_mm, the one h5py cursor reader on the export path
  - the regenerated indy_20160630_01 export sidecar and the re-fit KalmanConstants.swift, both on side_mm 171.68196243849025
affects: [10-05, 10-07, 10-09, 10-10, 10-11, rd-08-replay, refit-real-data-ablation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One authoritative implementation of a pre-registered formula, with the other call sites delegating and one deliberately-kept restatement acting as a cross-check tripwire"
    - "A pre-registration amendment quotes the superseded text verbatim, dates itself, names who decided, and states which published numbers did and did not move"
    - "A decisive argument for a convention is turned into an executable check at the site that depends on it, not left as prose"

key-files:
  created:
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-03a-RECONCILIATION-SUMMARY.md
  modified:
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-PREREGISTRATION.md
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-kalman-refit-evidence.md
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-02-SUMMARY.md
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-03-SUMMARY.md
    - Decoder/src/ndt1/replay_export.py
    - Decoder/src/ndt1/data.py
    - Decoder/scripts/export_replay.py
    - Decoder/scripts/webgrid_ceiling.py
    - Decoder/scripts/make_tiny_replay.py
    - Decoder/scripts/fit_kalman_gain.py
    - Decoder/tests/test_replay_export.py
    - Decoder/tests/test_kalman_residual.py
    - Decoder/tests/fixtures/tiny_replay.json
    - Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift

key-decisions:
  - "ndt1.replay_export.workspace_from_cursor is THE box: it is a library module both scripts already depend on, so making it authoritative needed no new module and no sys.path work"
  - "webgrid_ceiling.square_box delegates and renames onto its own committed 10-ceiling.json key set, rather than 10-ceiling.json being reissued on the shared schema: the artifact is published"
  - "fit_kalman_gain keeps workspace_side_mm as a second restatement, demoted in the docstring from authority to cross-check, because that duplication is what made the divergence loud instead of silent"
  - "The h5py cursor read stays in Decoder/scripts/export_replay.py and fit_kalman_gain imports it, keeping Decoder/src/ndt1/ free of cursor_pos reads as D-01 and Plan 10-02 both recorded"
  - "The amendment is a new dated section 3a with the superseded line quoted verbatim, which is the remedy the pre-registration's own no-edit rule prescribes"

patterns-established:
  - "A cross-check tripwire is documented with the incident where it fired, and pinned by a test that drives it with the real wrong value"
  - "A regenerated published artifact is proven unchanged by byte-diffing it against the committed copy, not by asserting that the change was safe"

requirements-completed: []

# Metrics
duration: 78min
completed: 2026-09-05
---

# Phase 10 Plan 03a: Workspace-box reconciliation Summary

**The pre-registered `cursor_bbox_square` box is now defined by the recorded `cursor_pos` track in one authoritative place, with section 3a recording the amendment; the export sidecar and the Kalman fit moved onto `side_mm` 171.68196243849025, and Plan 10-01's published 147 of 1,025 reproduces byte-identically.**

## What was wrong

`10-PREREGISTRATION` section 3 defined the workspace box as `cursor_mm = 10.0 * planar_cm`.
`planar_cm` is `(-finger[1:3, :]).T` (`Decoder/src/ndt1/data.py:401`), the finger track. Plans 10-02
and 10-03 implemented that literal text. Plan 10-01, which authored section 3, had boxed the
recorded `cursor_pos` array read directly from the `.mat` and published its reference number on that
box. Three artifacts, two boxes:

| Box | `side_mm` | `cell_mm` | `acq_radius_mm` |
|---|---|---|---|
| Recorded `cursor_pos` (10-01, and now everything) | 171.68196243849025 | 5.7227320812830085 | 2.8613660406415042 |
| `10.0 * planar_cm` (10-02 and 10-03, superseded) | 171.0725351294064 | 5.7024178376468795 | 2.8512089188234397 |

The user decided the box is the recorded `cursor_pos` track. Plan 10-01 is correct as published and
none of its numbers changed.

## The containment argument, measured

Section 3 already required that "every cursor sample must fall inside the box, and the script raises
if any does not". Measured over all 365,809 behaviour samples of `indy_20160630_01`:

| Check | Result |
|---|---|
| Recorded cursor samples outside the finger-derived box | **13 of 365,809** |
| Recorded cursor samples outside the recorded-cursor box | 0 |
| Finger-derived samples outside the recorded-cursor box | **0 of 365,809** |
| Finger-derived samples outside the finger-derived box | 0 |

The finger box is 171.07 mm on a side while the recorded cursor spans 171.68 mm on the same axis, so
no centring of it can contain the recorded track. It fails the pre-registered containment assertion
by construction. The recorded-cursor box is the only one of the two that contains both tracks, and
that check now runs on every export rather than living in prose: `export_replay` refuses to write if
any finger-derived sample escapes the box.

## Task commits

| # | Task | Commit | Type |
|---|---|---|---|
| 1 | Amend the pre-registration, visibly | `82c71da` | docs |
| 2 | One authoritative box, on the recorded track; export regenerated | `0079e6a` | fix |
| 3 | Re-fit the Kalman gain; regenerate the constants | `96d7d6b` | fix |
| 3 | Update the RD-07 evidence with the re-fit numbers | `3eba213` | docs |
| 4 | Correction notes on the 10-02 and 10-03 summaries | `1933ff2` | docs |

## Task 1: the amendment

`10-PREREGISTRATION.md` section 3's block now names the recorded `cursor_pos` array as `cursor_mm`,
and carries a pointer to the new **section 3a**, which quotes the superseded line verbatim and
records: what it said, what it says now, why (the containment table above), that the user decided,
and that no already-published number changed. The frontmatter gains an `amended:` key and section 18
records that 3a is the only amendment and that anything else claiming to amend the document is not
authorized by it.

This is the remedy the document's own no-edit rule prescribes: "a new dated section that supersedes
the old one and states what changed and why, leaving the original text intact."

The x10 frame relation is kept where it is still true and used, and is stated plainly not to define
the box. It remains a verified property of the session, is still hard-checked on every export by
`verify_frame_relation`, is still the cm-to-mm conversion, and is still the 10.0 in
`grid_units_per_cm = 10.0 / side_mm`. The amendment states why those uses are not interchangeable: a
unit conversion tolerates a fitted slope of 10.005 harmlessly, a bounding box built through it stops
containing the track.

## Task 2: one authoritative box

**`ndt1.replay_export.workspace_from_cursor` is authoritative.** It takes the recorded cursor track
in millimetres and performs no scaling. It was chosen because it is a library module that both
scripts already depend on, so no new module, no `sys.path` work and no test scaffolding was needed.

| Call site | After |
|---|---|
| `ndt1.replay_export.workspace_from_cursor` | **the one implementation** |
| `Decoder/scripts/webgrid_ceiling.py::square_box` | delegates, transposes `(2, N)` to `(n, 2)`, renames onto its committed `10-ceiling.json` key set |
| `Decoder/scripts/export_replay.py` | calls it on the track `read_cursor_mm` returns |
| `Decoder/scripts/make_tiny_replay.py` | calls it, converting its synthetic cm track to mm at the call site |
| `Decoder/scripts/fit_kalman_gain.py` | takes `side_mm` from it; keeps its own section-3 restatement only as a cross-check that raises above 1e-6 mm |

`count_outside_box` was factored out of the containment assertion so the export site can reuse it on
the other track. `read_cursor_mm` is the one h5py cursor reader on the export path;
`verify_frame_relation` no longer does I/O and takes the array. `Decoder/src/ndt1/` still contains no
`cursor_pos` read, which is what D-01 and Plan 10-02's own verification recorded.

**Plan 10-01's numbers are unchanged, and that was proven rather than argued.** Re-running
`webgrid_ceiling.py` after the delegation produced a file **byte-identical** to the committed
`10-ceiling.json`, `diff` clean, including the `env` block. The reference is still 147 of 1,025
trials at radius 2.8613660406415042.

**The regenerated export** (gitignored, nothing from `Decoder/exports/` or `Decoder/data/` was
committed):

| Field | Value |
|---|---|
| `workspace.side_mm` | **171.68196243849025** |
| `workspace.cell_mm` | **5.7227320812830085** |
| `workspace.acquisition_radius_mm` | **2.8613660406415042** |
| `workspace.grid_units_per_cm` | **0.058247237263394945** = 10.0 / 171.68196243849025 |
| `binary_sha256` | `5107b00911de761a60fe9ecc83dfef9b195d387ba42467586ef899755e57c48f` (**unchanged**) |
| sidecar sha256 | `a452ed69ef82d9c6f86d312e12defdadca843513a05092b0c1db1b9eb6dec4e3` (was `020272235bbf8cea83c0c07a091a572df008dfe3ec9de45755d4b052ce94d42d`) |
| Binary size, `n_bins`, `trials` | 31,019,840 bytes, 73,160, 1,025 (all unchanged) |

The binary is byte-identical because the box is sidecar metadata and no exported sample depends on
it. `read_export(verify_digest=True)` reads it back cleanly. The export's box is now byte-identical
to `10-ceiling.json`'s on all four bounds and both centre coordinates, so the two artifacts describe
the same square.

## Task 3: the re-fit

`R` scales as `k^2` with `k = 10.0 / side_mm`, so the predicted move was -0.7087 percent. Measured:

| Quantity | Before | After | Ratio |
|---|---|---|---|
| `side_mm` | 171.0725351294064 | **171.68196243849025** | 1.00356 |
| `grid_units_per_cm` (`k`) | 0.05845474 | **0.05824724** | 0.99645 |
| `R[0,0]` | 0.15152282 | **0.15044900** | 0.99291311 |
| `R[1,1]` | 0.08984564 | **0.08920892** | 0.99291311 |
| `R_offdiag` | -0.03168725 | **-0.03146268** | 0.99291311 |
| `sigma_jerk_sq` | 6092.058703 | **6048.884948** | 0.99291311 |
| `rho_closed_loop` | 0.818794 | **0.818794** | 1 |
| `K` as `Float` | as shipped | **bit-identical** | 1 |

**R moved by -0.7087 percent, as predicted.** The header reads `noise source = indy-heldout`, and
now records `side_mm=171.6820`, `grid_units_per_cm=0.05824724` and
`side_mm_source=ndt1.replay_export.workspace_from_cursor+section-3a-cross-check`.

**`K` did not move, and that is a fact worth carrying forward.** `Q` and `R` both scale by exactly
`k^2`, and the steady-state gain is invariant under a common positive scaling of the pair. The
float64 literals changed in their last one or two digits from DARE rounding, and all four non-zero
entries round to the same `Float` (verified bitwise). Empirically confirmed rather than assumed:
`CortexReFITBench --smoke` was re-run and reproduced Plan 10-03's recorded drift to every digit
(`refit_bps` 1.1950503004699202, `kalman_only_bps` 0.0966477777818005, `raw_bps` unchanged,
synthetic `refit_webgrid_bps` 8.004715490389097). **Plan 10-05's repair is exactly the size Plan
10-03 said it was.** The 8.0047 figure remains a synthetic seeded number that must not be quoted as
progress anywhere.

`10-kalman-refit-evidence.md` carries a dated re-fit banner with the reason, the before/after table,
what did not move and why, and the note that nothing was tuned: same code, same seed, same
checkpoints, same 14,600 rows, one corrected input constant, and a direction fixed by arithmetic
before the run.

## Task 4: the two summaries

`10-02-SUMMARY.md` and `10-03-SUMMARY.md` each gained a dated correction note at the end. Nothing in
either was rewritten or deleted.

- **10-02** flagged this exact discrepancy and correctly declined to resolve it. Its note marks
  discrepancy 1 RESOLVED in favour of `10-ceiling.json`, tabulates the current sidecar values, and
  corrects the handoff sha256 for Plan 10-09's provenance gate. Discrepancy 2, the `acq_radius_mm`
  versus `acquisition_radius_mm` spelling, is explicitly still open and unchanged.
- **10-03** recorded both `side_mm` values and adjusted neither. Its note marks that decision
  reversed by the user, tabulates the re-fit numbers, and records that two of its conclusions are
  strengthened rather than weakened: its cross-plan drift table and its 8.0047 guard rail both still
  hold exactly as written, because `K` is unchanged.

## Deviations

### Auto-fixed issues

**1. [Rule 3 - Blocking] `fit_kalman_gain.py` could not run at all on the merged tree**

- **Found during:** Task 3, on the first re-fit attempt.
- **Issue:** `TypeError: SessionLoad.__init__() missing 2 required positional arguments:
  'target_mm' and 'target_distinct'`. Plan 10-02 added both fields with no default; Plan 10-03's
  call site was written in a parallel worktree where they did not exist. Between `f80e84f` and this
  reconciliation, the committed `KalmanConstants.swift` could not be regenerated by its own
  generator on `main`.
- **Fix:** Both fields passed through from `load_session`. Not defaulted: a default would let a
  caller build a `SessionLoad` with a silently empty target track, which is the failure the
  no-default choice exists to prevent.
- **Files modified:** `Decoder/scripts/fit_kalman_gain.py`
- **Verification:** the fit runs end to end and the dataset-gated slow test passes.
- **Committed in:** `96d7d6b`

**2. [Rule 2 - Missing critical] The synthetic fixture generator was feeding centimetres to a
millimetre function**

- **Found during:** Task 2, checking who else calls `workspace_from_cursor`.
- **Issue:** `make_tiny_replay.py` passed `planar_cm` directly. After the amendment that would have
  declared a box a tenth of the fixture's own synthetic cursor excursion, which is exactly the class
  of silent unit error this reconciliation exists to remove.
- **Fix:** the conversion moved to the call site, with a comment recording that a synthetic session
  has no recorded cursor, so its cursor IS its finger track under the x10 relation.
- **Files modified:** `Decoder/scripts/make_tiny_replay.py`, `Decoder/tests/fixtures/tiny_replay.json`
- **Verification:** the regenerated fixture's binary is byte-identical and its workspace values are
  unchanged (the two forms are algebraically the same); only `source_sha256` moved, because that
  field is the sha256 of the generator itself.
- **Committed in:** `0079e6a`

**3. [Rule 1 - Bug] The `k^2` factor was documented as 295, having read 3400**

- **Found during:** Task 3, while rewriting the surrounding unit documentation.
- **Issue:** `fit_kalman_gain.py`'s module docstring and `test_kalman_residual.py`'s docstring both
  said fitting in cm/s instead of grid-units/s is wrong "by a factor of about 3400". The factor is
  `1 / grid_units_per_cm^2` = 1 / 0.00339274 = 295. The evidence artifact had it as 293 on the old
  box, so the 3400 was a docstring-only error, in no published result.
- **Fix:** all three now read 295, computed from the shipped `k`.
- **Files modified:** `Decoder/scripts/fit_kalman_gain.py`, `Decoder/tests/test_kalman_residual.py`,
  `10-kalman-refit-evidence.md`
- **Committed in:** `96d7d6b`, `3eba213`

**4. [Rule 2 - Missing critical] The containment argument was prose, not a check**

- **Found during:** Task 2.
- **Issue:** the entire justification for the amendment is that the recorded-cursor box contains
  both tracks. Nothing verified that, and nothing would notice if it stopped being true.
- **Fix:** `count_outside_box` factored out and used at the export site on the x10 finger track; the
  export refuses to write if any sample escapes. This is a correctness check on the mapping, not an
  assertion on a measured result, so it does not touch D-09.
- **Files modified:** `Decoder/src/ndt1/replay_export.py`, `Decoder/scripts/export_replay.py`,
  `Decoder/tests/test_replay_export.py`
- **Verification:** the export prints `0 of 365809 recorded cursor samples and 0 of 365809
  finger-derived samples fall outside the box`; the test drives the counter with a track the box
  provably cannot contain.
- **Committed in:** `0079e6a`

**5. [Rule 2 - Missing critical] The `ImportError` fallback made the cross-check optional**

- **Found during:** Task 3.
- **Issue:** `_resolve_side_mm` fell back to the local restatement when `ndt1.replay_export` was not
  importable. That was correct in Plan 10-03's worktree, where 10-02 had not landed, but on the
  merged tree it is unreachable code that would silently promote the non-authoritative
  implementation if it ever were reached.
- **Fix:** the import is now a hard module-scope import beside the other `ndt1` imports, and
  `workspace_side_mm` is documented as a cross-check rather than an authority.
- **Files modified:** `Decoder/scripts/fit_kalman_gain.py`
- **Committed in:** `96d7d6b`

**Total: 5 auto-fixed (1 blocking, 3 missing-critical, 1 bug). No Rule 4 escalation.** The one
decision that would have been Rule 4, which box to use, was already made by the user before this
task started.

### Deliberately not done

- **The two synthetic byte-identity gates were left red.** `ci.yml:378-388`'s `refit_bps.json` diff
  and `bps-policy.sh`'s committed-`webgrid_bps.json` leg are Plan 10-05's to repair. No committed
  synthetic fixture was modified. Their state is measured below.
- **`10-ceiling.json` and `10-ceiling-evidence.md` were not touched.** They were correct.
- **The `acq_radius_mm` versus `acquisition_radius_mm` spelling was not unified.** Unifying it means
  reissuing a published artifact for cosmetics.
- **STATE.md and ROADMAP.md were not updated**, per the task.

## Verification

Every command run on `Apple M5 Pro`, macOS 26.5 arm64, in this worktree. python 3.12.13, numpy
2.4.6, h5py 3.16.0, scipy 1.18.0, torch 2.12.1, Swift 6.2.4.

| Command | Result |
|---|---|
| `uv run --project Decoder ruff check Decoder` | **exit 0**, all checks passed |
| `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` | **273 passed**, 10 deselected |
| `uv run --project Decoder pytest Decoder/tests/test_kalman_residual.py -m slow -q` | **1 passed** in 336.77 s |
| `swift test --package-path Packages/CortexReFIT` | **28 tests in 5 suites passed** |
| `swiftformat --lint .../KalmanConstants.swift` | **exit 0**, 0/1 files require formatting |
| `./Tools/scripts/hotpath-policy.sh` and `--self-test` | **exit 0** both |
| `./Tools/scripts/decoder-policy.sh` and `--self-test` | **exit 0** both |
| `webgrid_ceiling.py` re-run, diffed against committed `10-ceiling.json` | **byte-identical** |
| `export_replay.py` re-run, sidecar values | side 171.68196243849025, cell 5.7227320812830085, radius 2.8613660406415042, `k` 0.058247237263394945 |
| `read_export(verify_digest=True)` on the regenerated export | OK, (73160, 96) / (73160, 2) / (73160, 2) / (73160,) |
| `Tools/scripts/bps-policy.sh` | **exit 1**, RED (pre-existing from 10-03, Plan 10-05 owns it) |
| `Tools/scripts/bps-policy.sh --self-test` | **exit 0**, the gate itself is intact |
| `check_refit_uplift.py` on the regenerated `refit_bps.json` | **exit 0** |
| `diff .bench/refit_bps.json .planning/phases/07-*/refit_bps.json` | **differs**, identically to what 10-03 recorded |
| `git status --short` | clean; nothing from `Decoder/exports/` or `Decoder/data/` |

**What did not pass, stated plainly.** `bps-policy.sh` exits 1 and the `ci.yml:378-388` byte-diff
fails. Both were already red when this task started, both are Plan 10-05's to repair, and both were
verified to be red in exactly the same way and by exactly the same values as Plan 10-03 recorded:
`refit_bps` 0.37439506338290895 to 1.1950503004699202, `kalman_only_bps` 0.15545586433053596 to
0.0966477777818005, `raw_bps` unchanged. This reconciliation added nothing to them.

**What was not run, and why.** The other 9 `slow` tests (CoreML conversion, palettization, held-out
co-bps) were not run: none of them imports `replay_export`, `workspace_from_cursor`,
`fit_kalman_gain` or `webgrid_ceiling`, verified by grep, and each costs a CoreML conversion. The
Kalman stability negative control (control 2 in the evidence artifact) was not re-executed, because
`K` is bit-identical as `Float`, so it would perturb the same matrix it perturbed on the first run.
That is recorded in the evidence artifact rather than left implicit.

## Notes for later plans

- **10-05:** unchanged obligation and unchanged size. The two red gates are red at exactly the values
  10-03 recorded. `K` did not move.
- **10-07 and 10-09:** the acquisition radius is **2.8613660406415042 mm** and `k` is
  **0.058247237263394945** everywhere in the phase now. `10-ceiling.json`, the export sidecar and
  `KalmanConstants.swift` all describe the same square. The sidecar's own sha256 changed to
  `a452ed69ef82d9c6f86d312e12defdadca843513a05092b0c1db1b9eb6dec4e3`; the `binary_sha256` did not.
- **Anyone re-running the export or the fit:** `Decoder/data/` and `Decoder/checkpoints/` are
  gitignored. This worktree used symlinks to the canonical checkout, and `git status` stayed clean
  because both are real directories holding symlinked files.
- **One environmental non-finding, not logged as deferred:** the editor hook's `ty` pass reports
  `unresolved-import` for `h5py`, `pytest` and every `ndt1.*` module, and does not model numpy
  structured-dtype field assignment. It runs outside the uv environment. The same diagnostics appear
  on files this task never touched. `ruff check` and `pytest` under `uv run` are the project's gates
  and both are green. Plans 10-01, 10-02 and 10-03 each recorded the same thing.

## Self-Check: PASSED

Files claimed as modified, all confirmed present on disk and in the commits above:
`10-PREREGISTRATION.md`, `10-kalman-refit-evidence.md`, `10-02-SUMMARY.md`, `10-03-SUMMARY.md`,
`Decoder/src/ndt1/replay_export.py`, `Decoder/src/ndt1/data.py`, `Decoder/scripts/export_replay.py`,
`Decoder/scripts/webgrid_ceiling.py`, `Decoder/scripts/make_tiny_replay.py`,
`Decoder/scripts/fit_kalman_gain.py`, `Decoder/tests/test_replay_export.py`,
`Decoder/tests/test_kalman_residual.py`, `Decoder/tests/fixtures/tiny_replay.json`,
`Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift`.

Commits claimed, all resolving as commit objects on top of the expected base
`f9361347b537fdd81e6e7337d839eb0b903b6cfe`: `82c71da`, `0079e6a`, `96d7d6b`, `3eba213`, `1933ff2`.

The two load-bearing claims were checked, not asserted: the regenerated `10-ceiling.json` is
byte-identical to the committed one, and the regenerated export sidecar reads
`side_mm` 171.68196243849025, `cell_mm` 5.7227320812830085, `acquisition_radius_mm`
2.8613660406415042 and `grid_units_per_cm` 0.058247237263394945.

*Phase: 10-v1-real-data-closed-loop-launch*
*Completed: 2026-09-05*
