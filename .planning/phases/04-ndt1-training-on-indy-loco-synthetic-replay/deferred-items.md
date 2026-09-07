# Phase 4 — Deferred Items (out-of-scope discoveries during execution)

> Logged per the executor SCOPE BOUNDARY rule: an executor only auto-fixes issues directly
> caused by its own plan's `files_modified`. Cross-plan / pre-existing issues in other files are
> recorded here and swept by the orchestrator's post-wave lint validation or the phase verifier.

| # | Item | Found during | Owner / file | Disposition |
|---|------|--------------|--------------|-------------|
| 1 | **ruff `I001` (import block un-sorted)** in `Decoder/tests/test_attention.py` — ruff's isort wants a blank line between the third-party `torch` imports and the first-party `from ndt1.attention …` / `from ndt1.loss …` imports. | Surfaced **independently by both Plan 04-04 and Plan 04-05** during their full-subsystem `ruff check Decoder/src Decoder/tests`. | **Plan 04-03** (`test_attention.py`, last touched by `c9fbf8c`; NOT in 04-04's or 04-05's `files_modified`). | **Resolved by orchestrator post-wave sweep.** Verified pre-existing & merge-surfaced (NOT caused by 04-04/04-05): it did not fire in 04-03's isolated worktree but appears in the merged base because ruff now resolves `ndt1.*` as a unified first-party import group (all sibling modules present together) that it expects separated from third-party by a blank line. Both executors correctly left it untouched (disjoint-files discipline). Fixed via `ruff check Decoder/tests/test_attention.py --fix` — see commit in the Wave-3 post-merge lint pass. |

## Notes

- This is the merge-surfaced cross-plan lint class that the orchestrator's post-wave validation is designed to catch. All 04-04 and 04-05 deliverables pass `ruff check` cleanly in isolation and in the merged context.
