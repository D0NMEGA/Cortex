# Cortex Decoder — NDT1 R&D subsystem (Phase 4)

Isolated Python subsystem for Cortex Phase 4: training a correctly-sized **NDT1**
(Ye & Pandarinath 2021 — Neural Data Transformer; ~1.3M params, 6 layers, h ∈ {1,2},
`d_model = 128`, 20 ms bins) on the O'Doherty Indy/Loco dataset (Zenodo 3854034) via
**masked spike reconstruction (Poisson NLL)**, then converting to a CoreML `.mlpackage`
in the ANE-conducive **BC1S `(B, C, 1, S)`** layout and **4-bit palettizing** it. This is
pure decoder R&D — no ANE deployment, residency, or `computeUnits` work here (that is
Phase 5).

This directory is a **dedicated top-level Python tree**, fully separate from the Swift /
SwiftPM source (`Apps/`, `Packages/`, `Tools/`). It has its own `pyproject.toml` + `uv.lock`
and a `uv`-managed virtual environment.

## Pinned interpreter (why 3.12, not the system 3.14)

The machine's default `python3` is **3.14**, which is **too new** for the `torch` and
`coremltools` (8.x) wheels this subsystem requires. The interpreter is therefore pinned to
**Python 3.12** via `Decoder/.python-version` and the `requires-python = ">=3.11,<3.13"`
bound in `pyproject.toml`. `uv` honors the pin and manages its own CPython — do **not** let
any tooling fall back to the system 3.14.

## Setup

```sh
# Resolve + create the venv from the committed lockfile (reproducible):
uv sync --project Decoder --extra dev
```

`uv` creates `Decoder/.venv/` (gitignored) using the pinned 3.12 interpreter.

## Running tests

```sh
# Quick run (structural / param / BC1S asserts — no training; ~10–20 s):
uv run --project Decoder pytest Decoder/tests -m "not slow" -q

# Full suite (includes the longer-running tests; excludes the committed evidence run):
uv run --project Decoder pytest Decoder/tests -q
```

The `slow` marker (registered in `pyproject.toml`) tags long-running training / conversion
tests so the quick CI run can exclude them with `-m "not slow"`.

## Linting

```sh
uv run --project Decoder ruff check Decoder/src Decoder/tests
```

`ruff.toml` selects the `BLE` (flake8-blind-except) rule, which makes a bare / blind
`except` a lint failure — encoding the project's hard "no bare `except`" rule as a gate.

## Artifact policy

**Code, configs, and manifests are committed; data and binary artifacts are not.** The
repo-root `.gitignore` excludes `Decoder/.venv/`, `Decoder/data/`, `*.mat` datasets,
`Decoder/checkpoints/`, `*.pt` / `*.ckpt` checkpoints, and `*.mlpackage/` model bundles.
Reproducibility comes from the committed `uv.lock` plus session-ID manifests + checksums,
not from committing the large dataset or model binaries.
