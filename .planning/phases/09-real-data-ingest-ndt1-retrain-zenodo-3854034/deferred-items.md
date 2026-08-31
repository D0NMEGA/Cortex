# Phase 09 deferred items

Out-of-scope discoveries logged during execution. Not fixed, by the executor scope boundary.

## `ty` reports unresolved-import on every Decoder file (pre-existing, repo-wide)

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
checker). Deferred because no plan in this phase owns the Python tooling configuration, and
changing it touches files outside 09-02's scope.
