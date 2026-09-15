---
status: PASS
agent: donny-executor
phase: quick-260915-fk9
plan: 01
subsystem: docs, Decoder
tags: [figure, evidence, readme, honesty, phase-10]
requires: [Decoder/scripts/webgrid_ceiling.py, Decoder/data/indy_20160630_01.mat]
provides: [docs/media/radius-rule.gif, Decoder/scripts/radius_rule_figure.py, Decoder/scripts/grid_shift_search.py, Decoder/scripts/grid_sync_drift.py, 10-radius-rule-figure-evidence.md]
affects: [README.md, .gitignore, .planning/phases/10-v1-real-data-closed-loop-launch/deferred-items.md]
tech-stack:
  added: []
  patterns: [__file__-anchored sys.path bootstrap, file-level ruff noqa E402, per-invocation --with deps]
key-files:
  created:
    - Decoder/scripts/radius_rule_figure.py
    - Decoder/scripts/grid_shift_search.py
    - Decoder/scripts/grid_sync_drift.py
    - docs/media/radius-rule.gif
    - docs/media/radius-rule-synced-first-target.png
    - docs/media/radius-rule-drifted.png
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-radius-rule-figure-evidence.md
  modified:
    - README.md
    - .gitignore
    - .planning/phases/10-v1-real-data-closed-loop-launch/deferred-items.md
decisions:
  - "D-A implemented as written: no dependency added, matplotlib/pillow supplied with --with; Decoder/pyproject.toml and Decoder/uv.lock untouched, confirmed by diff over the whole commit range."
  - "D-B implemented as written: the 7.27 MB GIF ships as rendered; the compression table was re-measured with gifsicle 1.96 rather than transcribed."
  - "README caption says 5.723 mm Webgrid cell, not the plan draft's 2.861 mm: 2.861 mm is the half-cell (the acceptance radius), and the figure's own rendered arithmetic is 15 / 5.723 = 2.6211."
  - "Three atomic per-task commits instead of the plan's single commit; each task's .planning edits were committed with that task, so no .planning edit was ever left uncommitted across a commit boundary."
metrics:
  duration: ~20 min
  tasks: 3
  files: 10
  completed: 2026-09-15
---

# Quick Task 260915-fk9: Land the Phase 10 radius-rule figure Summary

Landed the radius-rule comparison figure, its three analysis scripts and a provenance record, so the
README's "Why the acquisition count is zero" argument shows the thing it previously only described in
a three-row table. The committed generator reproduces the shipped GIF **byte for byte**.

## What shipped

| Task | Name | Commit | Files |
|---|---|---|---|
| 1 | Land the three scripts, ruff-clean and behaviour-identical | `cca1da4` | `Decoder/scripts/{radius_rule_figure,grid_shift_search,grid_sync_drift}.py` |
| 2 | Prove the scripts reproduce the artifact, record evidence | `f1d1125` | `10-radius-rule-figure-evidence.md` |
| 3 | Land media, caption the README, close the deferred item | `cf2ba1e` | `docs/media/` x3, `README.md`, `.gitignore`, `deferred-items.md` |

The changed set across all three commits is exactly the 10 paths in the plan's `files_modified`, no
more and no less.

## The load-bearing result

The reformat was the risk in this task: 66 ruff findings had to be cleared across 29 dense lines of a
generator whose every number is load-bearing. Two independent checks show it changed nothing.

**Byte-identical reproduction.** The committed generator, rerun from the repo root after the
reformat, produced a GIF with sha256 `7bab0426ab76e88bdbbf2dcc0a8906cf00998f4766351a29d10155f2e3cfa4a5`,
identical to the shipped artifact: same 7,274,376 bytes, same 537 images at 912x532. The plan only
required matching frame count and dimensions; byte-identity was achieved and is recorded as observed.

**AST constant comparison.** Parsing the pre- and post-reformat revisions and diffing the multiset of
string literals, f-string templates and numeric constants (implicit concatenation folded) yields an
identical multiset apart from three intended changes: the two cwd-relative `sys.path` strings
replaced by `__file__` anchoring, and the data path split across the repo-root join. No printed
string, on-figure string, assert message, colour, font size or figure constant moved.

Every regression value the plan pinned was reproduced: window trials 29-42 at 21.4 s realtime,
`r=2.8614` window 2/14 and session 147/1025, `r=7.5000` window 13/14 and session 951/1025, 537 frames
at 912x532. All of the generator's internal assertions held, including the end-state check that the
animation's final counters equal the independently recomputed window truth.

## Verification

| Check | Result |
|---|---|
| `uv run --project Decoder ruff check Decoder` (ci.yml:714, blocking) | exit 0 |
| `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` | 289 passed, 10 deselected |
| `./Tools/scripts/readme-policy.sh` | exit 0, 21 checks ok |
| `./Tools/scripts/readme-policy.sh --self-test` | exit 0 |
| `./Tools/scripts/honesty-sweep.sh` | exit 0, 7 assertions ok |
| `./Tools/scripts/honesty-sweep.sh --self-test` | exit 0 |
| `./Tools/scripts/toolchain-policy.sh` (proves D-A moved no pin) | exit 0 |
| `git status --porcelain` | clean |
| `Decoder/pyproject.toml`, `Decoder/uv.lock` in commit range | untouched |
| Media sha256 vs verified sources | 3/3 OK |
| `.planning/STATE.md` frontmatter | still `status: executing` |

## Honesty constraints

All four held. Both panes are labelled as the animal's recorded hand and not a decoder output, in the
generator docstring, the evidence file, and the README caption (on its own bolded line adjacent to
the image). The open-loop-replay limitation is stated in all three. 92.8% appears nowhere in the
added text, so it cannot land beside a decode claim. The artifact is uncropped, unscaled and
un-recompressed, so the on-frame excerpt-selection rule and full-session totals survive. Nothing was
transcribed: every count in the evidence file came from the captured run, and the D-B compression
numbers were re-measured here.

The evidence file also records the machine honestly as an **Apple M5 Pro Mac render carrying no
performance claim**, which keeps it clear of the repo's iPad-M4 measurement discipline.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 3 - Blocking] Worktree branch was based on the wrong commit**
- **Found during:** pre-task branch check
- **Issue:** `git merge-base HEAD a8790bf` returned `3a5054e`, so the worktree was based one commit
  behind. The prescribed `git reset --soft a8790bf` moved HEAD forward but left the working tree
  stale, staging the exact **reverse** of `a8790bf`: reverting `10-RECORDS.md`, `10-VALIDATION.md`
  and `deferred-items.md`, and deleting `10-SECURITY.md` (305 lines).
- **Fix:** restored those four paths from HEAD (`git checkout HEAD -- .planning/phases/10-*/`) before
  doing any work, so the task's commits could not silently revert the Phase 10 audit.
- **Commit:** n/a (pre-work correction; tree was clean before Task 1)

**2. [Rule 3 - Blocking] The gitignored dataset is not present in a worktree**
- **Found during:** Task 2 setup
- **Issue:** the generator reads the 382 MB gitignored `Decoder/data/indy_20160630_01.mat`, which
  exists only in the main checkout.
- **Fix:** created `Decoder/data/` in the worktree with the `.mat` symlinked in. A first attempt that
  symlinked the whole directory showed up as untracked, because `.gitignore:90` is `Decoder/data/` in
  directory form and does not match a symlink; the real-directory form is covered by the existing
  rule and leaves `git status` clean. Nothing about this is committed.
- **Commit:** n/a (gitignored)

**3. [Rule 1 - Bug] The plan's ruff violation count was low by 21**
- **Found during:** Task 1
- **Issue:** the plan tabulated 45 violations across E401/E402/E501/E701/E702/F401/F541. The measured
  count was **66**: it omitted 13 `E501` (line-too-long, limit 100) and 8 `I001` (import sorting).
- **Fix:** cleared all 66. E501 was resolved by implicit string concatenation split at safe
  boundaries, so every printed and on-figure string is preserved character for character, which the
  AST comparison then confirmed. The gate is `ruff check Decoder`, not the plan's table.
- **Commit:** `cca1da4`

**4. [Rule 1 - Bug] The plan misidentified the F541 line**
- **Found during:** Task 1
- **Issue:** the plan said F541 was `print(f"\n--- what box size WOULD align ...")`. That line has no
  `f` prefix and is already clean; the actual F541 is the final line,
  `print(f"the box is CURSOR-derived ...")`.
- **Fix:** dropped the `f` from the line that actually carried it. Printed text byte-identical.
- **Commit:** `cca1da4`

**5. [Rule 1 - Bug] The plan's draft caption mislabelled the Webgrid cell**
- **Found during:** Task 3
- **Issue:** the draft caption read "15 mm is not an integer multiple of the 2.861 mm cell". The runs
  in Task 2 show the 30x30 **cell** is 5.722732 mm and 2.861366 mm is its **half-cell**, which is the
  acceptance radius. The figure's own rendered arithmetic is `15 / 5.723 = 2.6211`. The plan defended
  the wording as "safe: it is rendered into the figure itself", but the figure renders the cell
  value, not the radius.
- **Fix:** caption says "the 5.723 mm Webgrid cell". This is honesty constraint 4 and threat
  T-Q-fk9-04 (caption drifting from what the figure shows) doing their job. Both statements are
  arithmetically true, but only one matches the artifact.
- **Commit:** `cf2ba1e`

**6. [Rule 2 - Missing] File-level ruff E402 exemption**
- **Found during:** Task 1
- **Issue:** after the `__file__` bootstrap, ruff flags the `webgrid_ceiling` import as E402, as the
  plan anticipated conditionally.
- **Fix:** added `# ruff: noqa: E402` with a reason comment to all three scripts, matching the
  committed idiom at `Decoder/scripts/export_ridge_decoder.py`. Verified empirically (ruff did flag
  it) rather than added on assumption.
- **Commit:** `cca1da4`

### Deliberate departures

**7. Three commits, not one.** The plan's Task 3 step 5 asked for a single commit, because a
post-commit hook reverts *uncommitted* `.planning` edits. The executor contract requires per-task
atomic commits. Both were satisfied by committing each task's `.planning` edits **with that task**,
so no `.planning` edit was ever pending across a commit boundary. Confirmed safe afterwards: the
working tree is clean, all three commits are intact, and the evidence file and deferred-items edit
both survive. No git hooks are in fact installed in this repo (`.git/hooks` holds only samples), so
the revert behaviour is harness-level.

**8. Cited "one of the 64 targets" in the caption.** The plan permitted taking
`grid_shift_search.py`'s "max targets centred by any global shift: N of 64" from captured stdout or
omitting it. N is 1, now re-derived and recorded in the evidence file, and it explains why the drift
is structural rather than an artifact of the chosen phase, so it is included.

### Observed, out of scope

**9. `ty` reports unresolved imports on the new generator.** The editor hook's `ty` pass reports
`Cannot resolve imported module matplotlib` plus ~15 cascading attribute errors on the `panes` dict.
This is pre-existing deferred item #1 in the Phase 10 file: `ty` resolves against its own
`.../uv/tools/ty/lib/python3.14/site-packages`, not `Decoder/.venv`. It emits 12 diagnostics of the
same class on already-committed scripts (`webgrid_ceiling.py`, `export_ridge_decoder.py`), and it is
**not a CI gate** (no `ty` step in `ci.yml`). For this file the unresolved import is additionally
expected by design: D-A deliberately keeps matplotlib out of the project environment. Not fixed, not
newly deferred, since the existing item already owns it.

**10. Pre-existing dead code left alone in the generator.** `panes = []` is assigned twice and
`X0, Y0` / `WS_X0, WS_Y0` are unused. Ruff does not flag module-level unused bindings, and the plan
forbids touching expressions, so these are preserved to keep the reformat provably behaviour-free.
Removing them would be a separate, deliberate edit.

## Authentication gates

None.

## Self-Check: PASSED

All 7 created files verified present on disk. All 3 commits verified present in `git log`. The
plan's `must_haves` contains-checks and all three `key_links` patterns verified:
`uv run --project Decoder --with matplotlib --with pillow` in the generator docstring,
`from webgrid_ceiling import` in the generator, `docs/media/radius-rule.gif` in the README, and the
pinned artifact sha256 in the evidence file.
