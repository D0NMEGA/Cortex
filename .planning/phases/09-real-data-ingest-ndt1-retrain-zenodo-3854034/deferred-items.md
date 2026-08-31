# Phase 09 deferred items

Out-of-scope discoveries found during execution. Logged, not fixed, per the executor scope
boundary: only issues directly caused by the current task's changes are auto-fixed here.

| # | Found during | Item | Why deferred |
|---|--------------|------|--------------|
| 1 | Plan 09-01, Task 2 | `Decoder/tests/test_ane_compute_plan.py` slow tests are flaky. Two consecutive runs each failed a different test (`test_palettized_model_every_op_ane_eligible`, then `test_palettized_op_eligibility_matches_fp16`); a third run passed 3/3 with no code change in between. Suspected cause is reuse of the shared `Decoder/checkpoints/` build directory across `.mlpackage` / `.mlmodelc` compiles rather than a real ANE-eligibility regression. | Unrelated to Plan 09-01. These are `@pytest.mark.slow` CoreML/ANE tests (DEC-06) excluded from the quick gate the plan verifies (`-m "not slow"`), and they import only `ndt1.*` - nothing from `download_indy.py`, `indy_sessions.json`, or `test_download_integrity.py`. Fixing them would be a drive-by change to Phase 5 evidence code. |

## Note on item 1

This matters beyond flakiness: `test_ane_compute_plan.py` is the committed evidence gate behind the
DEC-06 "226/226 ops ANE-eligible" claim. A gate that returns a different verdict on identical inputs
cannot support a published number. Worth a dedicated investigation (isolate each compile under
`tmp_path` instead of the shared `Decoder/checkpoints/`), but not inside this plan.
