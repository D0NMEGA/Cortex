# Phase 10 deferred items

Out-of-scope discoveries logged during execution. Each was found while doing other work, is not
caused by the task that found it, and was deliberately NOT fixed.

## The `ty` type-check hook resolves imports against the wrong Python environment

**Found during:** Plan 10-01, Tasks 2 and 3.

**Symptom:** the editor hook's `ty` pass reports `error[unresolved-import] Cannot resolve imported
module 'h5py'` and the same for `pytest` on any file under `Decoder/`.

**Why it is not a defect in this plan's code.** `h5py` is a declared dependency in
`Decoder/pyproject.toml` and `pytest` is in its `dev` optional-dependency extra; both are installed
in the uv-managed `Decoder/.venv`. The same diagnostic appears on the pre-existing
`Decoder/src/ndt1/data.py`, which has been committed since Phase 9, and `ty`'s own output names its
search path as `/opt/homebrew/lib/python3.14/site-packages`, not `Decoder/.venv`. So `ty` is
type-checking `Decoder/` against the Homebrew interpreter rather than the project environment.

**Evidence it is environmental, not real:** under the project's own toolchain,
`uv run --project Decoder ruff check Decoder` passes with zero findings and
`uv run --project Decoder pytest Decoder/tests -m "not slow" -q` is green at 220 passed, 1 skipped.

**Fix when someone picks it up:** point the hook's `ty` at the project environment (for example
`uv run --project Decoder ty check ...`, or set the interpreter path per-directory) so `Decoder/`
is checked against the environment it actually runs in. Not done here because it is a tooling
configuration change outside this plan's files, and changing it would touch the shared hook
configuration while other Phase 10 worktrees are running.

## `ClosedLoopPipelineTests` Test 2 cannot pass against the shipped 32-bin model

**Found during:** Plan 10-04, Task 3, while verifying that every pre-existing case still passes.

**Symptom.** With `CORTEX_MODEL_URL` pointing at the shipped
`Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage`, the Phase-8 case
`ClosedLoopPipelineTests.modelBackedDecodePathPresent` ("Test 2: NDT1 model-backed decode path is
present + compiled") fails at `ClosedLoopPipelineTests.swift:71` with `Expectation failed:
anyModelTick`. Without the variable set it returns early and passes, which is why it has always
looked green.

**Why.** The case builds `ClosedLoopPipeline(seed:target:modelURL:)`, which uses the default
`SyntheticSpikeSource` at `numBins` 8, and then asserts that at least one tick reported
`decodedByModel`. The shipped model's `spikes` input is `(1, 96, 1, 32)`, so it rejects the 8-bin
buffer on every tick and the pipeline falls back. This IS RESEARCH Pattern 2: the case asserts
"NDT1 genuinely in loop" against a configuration in which NDT1 structurally cannot be in the loop.

**Proven pre-existing, not caused by this plan.** The identical failure reproduces on a clean
checkout of commit `5bb164d`, which is before any `CortexDemo` file in this plan was touched:

```
git archive 5bb164d | tar -x -C <scratch>
CORTEX_MODEL_URL=<repo>/Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage \
  swift test --package-path <scratch>/Packages/CortexDemo --filter modelBackedDecodePathPresent
# -> Expectation failed: anyModelTick   (identical to the post-change tree)
```

The `try?` the old code used and the `do`/`catch` the new code uses both return nil and both fall
back, so the observable outcome is unchanged; only the reason is now recorded.

**Deliberately NOT fixed here.** Plan 10-04 Task 2 says in writing "Do not modify or delete any
existing case", and the repair is a one-line change to a Phase-8 artifact. Repairing it means
constructing that case's pipeline with a source at `RecordedSpikeSource.modelSeqLen` (32) so the
assertion exercises what it claims. `RecordedSpikeSourceTests` Test 9 already covers the same
ground for the new code and skips cleanly when no model is present.

**Who should pick it up.** Any later Phase-10 plan that runs the CortexDemo suite with
`CORTEX_MODEL_URL` set (10-06 and 10-09 are the likely ones) will see a red suite from this case
alone. Fix it in the same commit that first needs a model-wired green suite.
