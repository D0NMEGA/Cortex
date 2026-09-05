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
