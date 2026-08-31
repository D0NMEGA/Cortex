# Phase 09 deferred items

Out-of-scope discoveries found during execution. Logged, not fixed, per the executor scope
boundary: only issues directly caused by the current task's changes are auto-fixed here.

| # | Found during | Item | Why deferred |
|---|--------------|------|--------------|
| 1 | Plan 09-01, Task 2 | `Decoder/tests/test_ane_compute_plan.py` slow tests are flaky. Two consecutive runs each failed a different test (`test_palettized_model_every_op_ane_eligible`, then `test_palettized_op_eligibility_matches_fp16`); a third run passed 3/3 with no code change in between. Suspected cause is reuse of the shared `Decoder/checkpoints/` build directory across `.mlpackage` / `.mlmodelc` compiles rather than a real ANE-eligibility regression. | Unrelated to Plan 09-01. These are `@pytest.mark.slow` CoreML/ANE tests (DEC-06) excluded from the quick gate the plan verifies (`-m "not slow"`), and they import only `ndt1.*` - nothing from `download_indy.py`, `indy_sessions.json`, or `test_download_integrity.py`. Fixing them would be a drive-by change to Phase 5 evidence code. |
| 2 | Plan 09-02 | `ty` reports `unresolved-import` on every file under `Decoder/`. Pre-existing, repo-wide, tool-configuration only. | No plan in this phase owns the Python tooling configuration; fixing it touches files outside 09-02's scope. Detail below. |

## Note on item 1

This matters beyond flakiness: `test_ane_compute_plan.py` is the committed evidence gate behind the
DEC-06 "226/226 ops ANE-eligible" claim. A gate that returns a different verdict on identical inputs
cannot support a published number. Worth a dedicated investigation (isolate each compile under
`tmp_path` instead of the shared `Decoder/checkpoints/`), but not inside this plan.

Phase 09 relevance: Plan 09-08 re-measures ANE op eligibility on the real-data checkpoint using this
same module (RD-05 / RD-06). The flake must be resolved or the run must be shown to be deterministic
before its op tally can be published as measured.

## Note on item 2: `ty` unresolved-import on every Decoder file

Found during 09-02. The editor/hook type checker runs `ty` from a tool install that does not see
`Decoder/.venv`, so it reports `unresolved-import` for `h5py`, `torch`, `pytest` and the
first-party `ndt1.*` package on every file under `Decoder/`. Reproduced on files this plan did not
touch:

```
uvx ty check Decoder/tests/test_data.py Decoder/src/ndt1/data.py
# 8 diagnostics, all unresolved-import, on code that is green under pytest and ruff
```

This is a tool-configuration gap, not a code defect: `uv run --project Decoder ruff check Decoder`
and `uv run --project Decoder pytest Decoder/tests -m "not slow"` both exit 0. The fix is a `ty`
environment setting pointing at the Decoder venv (or excluding `Decoder/` from the ambient
checker).
