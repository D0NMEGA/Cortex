# Phase 4 — Deferred Items (out-of-scope discoveries)

Items discovered during plan execution that are OUTSIDE the executing plan's `files_modified`
scope (per the GSD SCOPE BOUNDARY rule — only auto-fix issues directly caused by the current
plan's changes). Logged here for the orchestrator / verifier to sweep after the wave merge.

---

## From Plan 04-04 (Wave 3 — training loop)

### D-04-04-01 — `test_attention.py` ruff `I001` import-sort (04-03's file)

- **Discovered:** running `ruff check Decoder/src Decoder/tests` after Plan 04-04's files landed.
- **File:** `Decoder/tests/test_attention.py:8` (committed by Plan **04-03** in `5e3a9b3`; NOT in
  04-04's `files_modified`, and unmodified by 04-04).
- **Issue:** `I001 [*] Import block is un-sorted or un-formatted` — ruff's isort wants a blank line
  between the third-party `torch` imports and the first-party `from ndt1.attention import ...`.
- **Why it surfaced now:** Plan 04-04 added new first-party `ndt1` modules (`metrics.py`,
  `train.py`); ruff's import grouping for `ndt1.*` in 04-03's test file shifted as a result, so an
  `I001` that 04-03's standalone run did not report now appears. (04-04's own files apply the same
  grouping and are ruff-clean.)
- **Disposition:** **NOT fixed** by 04-04 (out of scope — disjoint-files / scope-boundary rule).
  Trivial one-line autofix: `uv run --project Decoder ruff check --fix Decoder/tests/test_attention.py`.
  The orchestrator's post-wave hook/lint validation (or a 1-line follow-up) can apply it.
- **Impact:** lint-only; zero runtime effect. The 04-03 architecture/attention tests still pass.
