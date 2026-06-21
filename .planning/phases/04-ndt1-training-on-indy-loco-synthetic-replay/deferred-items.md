# Phase 4 — Deferred Items (out-of-scope discoveries during execution)

> Logged per the executor SCOPE BOUNDARY rule: only issues directly caused by the current
> plan's changes are auto-fixed. Pre-existing / cross-plan issues in files outside the plan's
> `files_modified` are recorded here and left for the owning plan or the verifier.

| # | Item | Found during | Owner / file | Disposition |
|---|------|--------------|--------------|-------------|
| 1 | **ruff `I001` (import block un-sorted)** in `Decoder/tests/test_attention.py` — ruff wants a blank line between the third-party `torch` imports and the first-party `from ndt1.attention …` / `from ndt1.loss …` imports. | Plan 04-05 full-subsystem `ruff check Decoder/src Decoder/tests` | **Plan 04-03** (`test_attention.py` is 04-03's file, last touched by `5e3a9b3`; NOT in 04-05's `files_modified`). | **Deferred — out of scope for 04-05.** Verified pre-existing & merge-surfaced, NOT caused by 04-05: the error persists with `convert.py`/`palettize.py` temporarily removed, so it is independent of this plan's files. It did not fire in 04-03's isolated worktree but surfaces in the merged base `b4d1fd3` because ruff now resolves `ndt1.*` as a first-party import group (all sibling modules + the installed package are present together), which it expects separated from third-party by a blank line. **One-line fix** (insert a blank line after `import torch.nn.functional as F`, or `ruff check Decoder/tests/test_attention.py --fix`) — left for Plan 04-03's owner / the Phase-4 verifier so 04-05 does not touch a cross-plan file (disjoint-files discipline). All five 04-05 files are individually ruff-clean. |

## Notes

- This is the same class of merge-surfaced cross-plan lint that the orchestrator's post-wave
  hook validation is designed to catch. 04-05's own deliverables (`convert.py`, `palettize.py`,
  and its three tests) pass `ruff check` cleanly in isolation and in context.
