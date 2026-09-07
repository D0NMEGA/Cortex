---
phase: 04-ndt1-training-on-indy-loco-synthetic-replay
plan: 01
subsystem: infra
tags: [python, uv, pytest, ruff, torch, coremltools, numpy, h5py, scaffold, ndt1]

# Dependency graph
requires: []
provides:
  - "uv-managed Decoder/ Python subsystem (pinned CPython 3.12) — isolated from the Swift/SwiftPM tree"
  - "reproducible locked dep graph (Decoder/uv.lock): torch 2.12.1, coremltools 9.0, numpy 2.4.6, h5py 3.16.0, pytest 9.1.1, ruff 0.15.18"
  - "working `uv run --project Decoder pytest -m \"not slow\"` command (resolves 04-VALIDATION MISSING pytest/env reference)"
  - "shared seeded test fixtures for Waves 2-3: tiny_spike_counts (B=4,T=32,C=96), dummy_bc1s_input (1,96,1,32), autouse _seed; constants CHANNELS=96, SEQ_LEN=32"
  - "ruff BLE (no-bare-except) lint gate encoding the hard project rule"
  - ".gitignore globs for Decoder data/checkpoints/.mlpackage artifacts (code+manifests tracked, binaries not)"
affects: [04-02, 04-03, 04-04, 04-05]

# Tech tracking
tech-stack:
  added: [uv (0.11.21), CPython 3.12.13, torch 2.12.1, coremltools 9.0, numpy 2.4.6, h5py 3.16.0, pytest 9.1.1, ruff 0.15.18, hatchling]
  patterns: ["uv-pinned interpreter via .python-version (avoid system 3.14)", "src/ layout package (src/ndt1)", "seeded autouse fixtures in conftest as the shared cross-wave contract", "ruff BLE as a structural encode of the no-bare-except rule"]

key-files:
  created:
    - Decoder/pyproject.toml
    - Decoder/uv.lock
    - Decoder/.python-version
    - Decoder/ruff.toml
    - Decoder/README.md
    - Decoder/src/ndt1/__init__.py
    - Decoder/tests/__init__.py
    - Decoder/tests/conftest.py
    - Decoder/tests/test_env_smoke.py
  modified:
    - .gitignore

key-decisions:
  - "Pinned CPython 3.12.13 (uv-managed) over system 3.14.6 — 3.14 has no torch/coremltools wheels (04-RESEARCH §3 blocker)"
  - "coremltools resolved to 9.0 (not 8.x) — the `<9` ceiling in Task 1 step 6 was conditional on a resolution failure that did not occur; 9.0 satisfies `>=8.0` and the palettize_weights/OpPalettizerConfig APIs are stable 8→9"
  - "torch resolved to 2.12.1; coremltools 9.0 emits a soft compat advisory (most-tested torch is 2.7.0) — non-blocking for this scaffold but flagged for 04-05's ct.convert/palettize path"

patterns-established:
  - "Pattern: uv subsystem isolation — Decoder/ is a sibling top-level tree with its own pyproject.toml + uv.lock, never coupled to SwiftPM; all commands use `uv run --project Decoder`"
  - "Pattern: shared fixtures as contracts — conftest.py defines named fixtures (tiny_spike_counts, dummy_bc1s_input) + constants (CHANNELS=96, SEQ_LEN=32) downstream waves import by name, not re-derive"
  - "Pattern: lint-as-rule-gate — ruff BLE makes a bare/blind except a CI failure, encoding the project hard rule structurally"

requirements-completed: [DEC-02]

# Metrics
duration: 8min
completed: 2026-06-21
---

# Phase 4 Plan 01: Decoder Python Subsystem Scaffold Summary

**uv-managed `Decoder/` Python subsystem pinned to CPython 3.12 with a reproducible lockfile (torch 2.12.1 + coremltools 9.0 + numpy 2.4.6 + h5py 3.16.0), seeded conftest fixtures (96-ch spike + `(1,96,1,32)` BC1S), a ruff no-bare-except gate, and gitignored binary artifacts — `uv run --project Decoder pytest` is green from a clean clone.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-06-21 (Wave 1 of Phase 4)
- **Completed:** 2026-06-21
- **Tasks:** 2/2
- **Files modified:** 10 (9 created + .gitignore appended)

## Accomplishments
- Stood up the brand-new top-level `Decoder/` R&D subsystem with a `uv`-managed venv pinned to **CPython 3.12.13** (foreclosing the local 3.14 that lacks torch/coremltools wheels — the documented 04-RESEARCH §3 blocker).
- Resolved + committed `Decoder/uv.lock` — a hash-locked, reproducible dependency graph (torch 2.12.1, coremltools 9.0, numpy 2.4.6, h5py 3.16.0, pytest 9.1.1, ruff 0.15.18).
- Authored the shared seeded `conftest.py` fixtures that Waves 2-3 import as contracts: `tiny_spike_counts` (B=4, T=32, C=96), `dummy_bc1s_input` (1, 96, 1, 32 — the ANE-conducive BC1S layout), an autouse `_seed`, and constants `CHANNELS=96` / `SEQ_LEN=32`.
- Resolved the 04-VALIDATION "MISSING" pytest/env reference: `uv run --project Decoder pytest -m "not slow"` runs green (3 smoke tests pass) from the committed tree.
- Encoded the hard "no bare `except`" project rule as a structural gate via ruff `BLE`, and gitignored all binary/data artifacts (`.venv`, `data/`, `*.mat`, `checkpoints/`, `*.pt`, `*.ckpt`, `*.mlpackage/`, caches) while keeping code + configs + manifests tracked.

## Task Commits

Each task was committed atomically (with `--no-verify`, per worktree-parallel execution):

1. **Task 1: Initialize the uv-managed Decoder/ subsystem with a pinned interpreter and locked deps** — `cc1d761` (chore)
2. **Task 2: Author shared seeded test fixtures + an env smoke test, and gitignore binary artifacts** — `d534b5b` (test)

_Plan metadata commit (SUMMARY) made separately after self-check._

## Files Created/Modified
- `Decoder/.python-version` — pins `3.12` so uv never falls back to system 3.14
- `Decoder/pyproject.toml` — subsystem definition: `requires-python = ">=3.11,<3.13"`, deps (torch>=2.2, coremltools>=8.0, numpy>=1.26, h5py>=3.10), dev extras (pytest>=8.0, ruff>=0.6), pytest `slow` marker, hatchling build of `src/ndt1`
- `Decoder/uv.lock` — reproducible locked dependency graph (the supply-chain mitigation, T-04-01-01)
- `Decoder/ruff.toml` — `target-version py312`, line-length 100, lint select `E F I B UP BLE` (BLE = no-bare-except gate)
- `Decoder/README.md` — what the subsystem is, `uv run` quick/full commands, the pinned-interpreter rationale, and the artifact-gitignore policy
- `Decoder/src/ndt1/__init__.py` — package skeleton (docstring + `__all__: list[str] = []`)
- `Decoder/tests/__init__.py` — empty test-package marker
- `Decoder/tests/conftest.py` — seeded shared fixtures + `CHANNELS=96` / `SEQ_LEN=32` constants (cross-wave contract)
- `Decoder/tests/test_env_smoke.py` — 3 non-slow asserts proving env + fixtures are wired
- `.gitignore` — appended a path-scoped `Decoder/` artifact section (existing Swift/Xcode + generic Python rules untouched)

## Decisions Made
- **Pinned CPython 3.12.13 (uv-managed), not system 3.14.6** — the local default 3.14 has no torch/coremltools wheels (04-RESEARCH §3). uv already had 3.12.13 cached, so no interpreter download was needed.
- **coremltools resolved to 9.0, not 8.x** — Task 1 step 6 instructed "prefer the latest coremltools in `>=8,<9`" *only if a wheel failed to resolve*. No resolution failure occurred under 3.12, so the plain `coremltools>=8.0` floor resolved 9.0. 9.0 satisfies the spec floor and the DEC-05 APIs (`coremltools.optimize.coreml.palettize_weights`, `OpPalettizerConfig(nbits=4)`) are stable across the 8→9 boundary. Downstream plans should pin against **9.0**.
- **No interpreter-bound downgrade** — kept `requires-python = ">=3.11,<3.13"` exactly as specified (the coremltools-supported range); did not widen/narrow it.

## Deviations from Plan

None — plan executed exactly as written. Both tasks' actions, file contents, and acceptance criteria were followed verbatim; no Rule 1/2/3/4 deviations were required. (The one judgment call — accepting coremltools 9.0 instead of forcing `<9` — was explicitly the plan's intended behavior, since the `<9` ceiling was conditional on a resolution failure that did not occur. Documented under Decisions, not a deviation.)

## Issues Encountered
- **PostToolUse hook false alarm (environment mismatch, not a code defect):** after writing `conftest.py` / `test_env_smoke.py`, the hook's type-checker (`ty`) reported `unresolved-import` for `pytest` and `torch`, and `pytest` reported "no tests ran". Root cause: the hook runs against the machine's default Python (3.14), not the `Decoder/.venv` (3.12) where the deps are installed. The authoritative `<automated>` verify (`uv run --project Decoder pytest`) resolves all imports and passes 3/3 — confirming the hook noise was an interpreter mismatch, not a real failure. No action needed in this scaffold; downstream Python work in this subsystem must use `uv run --project Decoder` rather than bare `python3`/`pytest`.

## Threat Surface
No new security surface beyond the plan's `<threat_model>`. Both mitigations are in place and verified:
- **T-04-01-01 (supply-chain tampering):** floors pinned in `pyproject.toml` + hash-locked `uv.lock` committed; no unpinned `pip install` anywhere.
- **T-04-01-02 (artifact leak into git):** `.gitignore` globs verified — 7 representative artifact paths (`*.mat`, `checkpoints/*.pt`, `*.ckpt`, `*.mlpackage/`, caches, `.venv`) all `git check-ignore` positive, while code/config files (`__init__.py`, `conftest.py`, `pyproject.toml`) remain trackable. The venv is not staged (porcelain count 0).
- **T-04-01-04 (bare-except masking a broken env):** ruff `BLE` selected — bare/blind excepts fail lint.

## Known Stubs
None. The `__all__: list[str] = []` in `src/ndt1/__init__.py` is an intentional empty export list for a fresh package skeleton (the NDT1 model lands in 04-03), not a data stub flowing to any UI. No placeholder text, no TODO/FIXME, no mock-wired components. The scaffold's goal (a green `uv run pytest`) is fully achieved.

## Cross-Plan Notes (hand-forward)
- **For 04-02 (dataset loader):** `h5py 3.16.0` is locked — use it (not `scipy.io.loadmat`) for the v7.3/HDF5 `.mat` files. `CHANNELS=96` constant lives in `Decoder/tests/conftest.py`; reuse it for the channel-count==96 reconciliation test vs `CORTEX_CHANNEL_COUNT`.
- **For 04-03 (NDT1 model + SC1/SC3 tests):** import `dummy_bc1s_input` and `tiny_spike_counts` from `tests.conftest` — they are the shared seeded inputs. The BC1S fixture is exactly `(1, 96, 1, 32)`.
- **For 04-05 (ct.convert + palettize):** **pin/validate against coremltools 9.0** (resolved here, not 8.x). Note the soft compatibility advisory: coremltools 9.0 prints "Torch version 2.12.1 has not been tested with coremltools; Torch 2.7.0 is the most recent tested." This is non-blocking for import/scaffold, but the `ct.convert` + palettization path in 04-05 should validate the conversion under torch 2.12.1, and if "unexpected errors" surface, pin torch to ≤2.7 in `pyproject.toml` (the `torch>=2.2` floor permits it) and re-lock. This is a downstream concern, intentionally out of scope for the scaffold.

## Next Phase Readiness
- Wave 0 scaffold complete: `uv run --project Decoder pytest -m "not slow"` is green from the committed tree; the env is reproducible from `uv.lock`.
- The shared fixtures (`tiny_spike_counts`, `dummy_bc1s_input`, `_seed`) and constants (`CHANNELS=96`, `SEQ_LEN=32`) are defined and importable for Waves 2-3.
- No Phase-5 ANE scope (`computeUnits`, `_ANEClient`, `cpuAndNeuralEngine`) appears anywhere in the scaffold (negative-control grep clean).
- No blockers. One forward-looking advisory (coremltools-9.0 / torch-2.12 compat for 04-05) recorded above.

## Self-Check: PASSED

- All 9 created files + `.gitignore` + `04-01-SUMMARY.md` exist on disk (11/11 FOUND).
- Both task commits exist in git history: `cc1d761` (Task 1), `d534b5b` (Task 2).
- All 4 plan `<verification>` checks green: import smoke (3.12.13), quick suite (3 passed), ruff (exit 0), no artifacts in `git status`.

---
*Phase: 04-ndt1-training-on-indy-loco-synthetic-replay*
*Completed: 2026-06-21*
