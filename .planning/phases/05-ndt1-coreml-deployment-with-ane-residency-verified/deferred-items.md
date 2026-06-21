# Phase 05 — Deferred / Out-of-Scope Items

Out-of-scope discoveries logged during execution (per the executor scope-boundary rule: only
auto-fix issues directly caused by the current task's changes; log unrelated discoveries here).

## From Plan 05-04 (latency bench)

### Plan-03 `VelocityOutputTests.decode()` hardcodes `seqLen = 8` — cannot run against an arbitrary-seqLen model

- **Discovered during:** Plan 05-04 Task 2, while driving a REAL `.mlpackage` through the decode
  path for the first time (the bench at `seqLen = 32`).
- **Observation:** `Packages/CortexDecoder/Tests/CortexDecoderTests/VelocityOutputTests.swift`
  builds its `SpikeInputBuffer` with `seqLen = 8`. The converted NDT1 model has a STATIC input
  shape `(1, 96, 1, S)` (no `RangeDim`), so a model built at `S = 32` is rejected by that test with
  `MultiArray shape (1 x 96 x 1 x 8) does not match (1 x 96 x 1 x 32)`. In the canonical CI / clean
  state (no `CORTEX_DECODER_MODEL_URL`) the test SKIPS, so this is latent — it only surfaces if a
  user points the env var at a model whose `S` differs from the test's hardcoded 8.
- **Why NOT fixed here:** it is a Plan-03 test fixture, unrelated to the 05-04 bench (the bench uses
  `seqLen = 32`, matching the model it documents building). Reworking the Plan-03 test to read `S`
  from the model description is a separate, bounded improvement.
- **Suggested fix (future):** have `VelocityOutputTests.decode()` derive `seqLen` from
  `model.modelDescription.inputDescriptionsByName["spikes"]` (the constraint's shape) instead of a
  hardcoded literal, so it round-trips against any built artifact. Alternatively, document the
  expected `S` via a second env var.
- **Status:** Open (low priority — the bench is the canonical DEC-11 driver and exercises the real
  rank-4 decode path end-to-end; the model-backed XCTest remains a skip-by-default smoke).
