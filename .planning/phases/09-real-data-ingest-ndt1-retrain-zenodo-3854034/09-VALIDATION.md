---
phase: 9
slug: real-data-ingest-ndt1-retrain-zenodo-3854034
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-30
---

# Phase 9 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `09-RESEARCH.md` section "Validation Architecture".

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `pytest` 8.x (declared in `Decoder/pyproject.toml` `[project.optional-dependencies].dev`) |
| **Config file** | `Decoder/pyproject.toml` (`[tool.pytest.ini_options]`, `testpaths = ["tests"]`, marker `slow`) |
| **Env bootstrap (REQUIRED FIRST)** | `uv sync --project Decoder --extra dev` |
| **Quick run command** | `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` |
| **Full suite command** | `uv run --project Decoder pytest Decoder/tests -q` |
| **Estimated runtime** | quick ~15-30 s; full ~minutes plus human-run evidence runs |
| **Gate scripts** | `Tools/scripts/decoder-policy.sh` (new, D-19) plus its `--self-test`, mirroring `bps-policy.sh` |

**Tier split (Phase 2 D-18 / Phase 6 D-10 / this phase's D-21, unchanged).** CI gates correctness and
structure and NEVER trains, NEVER downloads the dataset, and NEVER asserts a measured number. Measured
numbers are committed evidence produced by a human-run runbook. Every automated command below must run
green on a checkout with an empty `Decoder/data/`.

A bare `uv run pytest` without `--extra dev` fails with a misleading `No module named numpy`. The sync
step is not optional.

---

## Sampling Rate

- **After every task commit:** `uv sync --project Decoder --extra dev && uv run --project Decoder pytest Decoder/tests -m "not slow" -q`
- **After every plan wave:** `uv run --project Decoder pytest Decoder/tests -q` plus `./Tools/scripts/decoder-policy.sh && ./Tools/scripts/decoder-policy.sh --self-test`
- **Before `/donny-verify-work`:** full suite green, `09-training-evidence.md` + metrics JSON committed, ANE and palettization evidence re-derived
- **Max feedback latency:** ~30 seconds (quick suite)

---

## Per-Requirement Verification Map

Task IDs are assigned by the planner; rows are keyed by requirement until then.

| Req | Behavior proved | Tier | Automated Command / Artifact | Negative Control (proves it bites) | Status |
|---|---|---|---|---|---|
| RD-01a | Manifest has zero `"PENDING"` sha256 entries | CI-blocking | `./Tools/scripts/decoder-policy.sh` | `--self-test` writes a stand-in manifest with one `"PENDING"`, asserts exit 1 | ⬜ pending |
| RD-01b | Every session declares `id`, `url`, `sha256`, `size_bytes`, `md5`; direct (non-`/api/`) URL | CI-blocking | `pytest -k test_manifest` (extend `test_manifest.py`) | stand-in session with `/api/` URL and missing `size_bytes`; both must fail | ⬜ pending |
| RD-01c | Integrity gate raises on a corrupted `.mat` | CI-blocking | `pytest -k test_download_integrity_gate` (new) | flip to a matching checksum; test must then pass, proving it discriminates | ⬜ pending |
| RD-01d | Downloader rejects a non-MATLAB payload (P2) | CI-blocking | same module: `<!DOCTYPE html>` first bytes assert `ValueError` | real `MATLAB 7.3 MAT-f` magic bytes must not raise | ⬜ pending |
| RD-02a | Cell-array dereference skips `MATLAB_empty` cells | CI-blocking | `pytest -k test_fixture_empty_cells` vs the D-20 fixture | generator variant omitting `MATLAB_empty` must fail the count assertion | ⬜ pending |
| RD-02b | Channel-axis transpose correct; 192-ch structure raises informatively | CI-blocking | `pytest -k test_fixture_channel_axis` | `(96, u)` must load; `(u, 192)` must raise naming 192 | ⬜ pending |
| RD-02c | `finger_pos` planar pair is rows **1-2**, not 0-1 (P4) | CI-blocking | `pytest -k test_fixture_finger_pos_axes` | extractor taking rows 0-1 must fail the near-constant-axis assertion | ⬜ pending |
| RD-02d | 20 ms binned per-channel rates fall in the pinned plausible band | CI-blocking (fixture) + evidence (real) | `pytest -k test_firing_rate_band` | fixture variant with 10x inflated density must fall outside the band | ⬜ pending |
| RD-02e | All selected real sessions load end to end | evidence | `report_sessions.py` per-session channel-yield table | a width-gate failure must appear in the excluded list with its measured width | ⬜ pending |
| RD-03a | Held-out chronological-tail co-bps on real spikes beats the train-split mean-rate null | evidence (human-run) | `pytest -m slow -k test_heldout_cobps` with real `.mat` present | shuffled (non-chronological) split must produce a materially different number; record as leak-detection control | ⬜ pending |
| RD-03b | Committed margin re-derived from the observed value, not inherited | CI-blocking | `pytest -k test_cobps_margin_documented` | margin set back to Phase-4's 0.05 with no rationale key must fail | ⬜ pending |
| RD-03c | Published number traceable to the bytes it came from | CI-blocking | `./Tools/scripts/decoder-policy.sh` assertions (b) and (c) | `--self-test` strips `data_source` (exit 1); perturbs one checksum so manifest and metrics disagree (exit 1) | ⬜ pending |
| RD-04a | Per-session held-out co-bps for every pooled session | evidence | `pytest -k test_metrics_schema` asserts key set matches manifest session ids | drop one session from metrics JSON; schema test must fail | ⬜ pending |
| RD-04b | Full four-fold LOSO rotation with mean and spread | evidence | schema test asserts `loso` length == session count, unique `held_out_session` | a 3-fold array must fail the length assertion | ⬜ pending |
| RD-05a | Palettized package exists and is smaller; ratio recorded | evidence + CI structure | existing `pytest -m slow -k test_palettized_package` | existing Phase-4 control retained | ⬜ pending |
| RD-05b | Palettization delta on BOTH models (Poisson-NLL on reconstruction, R2 on with-velocity) | evidence | metrics JSON `palettization.nll_delta` + `palettization.r2_delta`, each labeled with its model | schema test fails if either key or its `model` label is absent | ⬜ pending |
| RD-06a | 226/226 ops ANE-eligible, zero CPU-only, on the with-velocity real-data model | evidence (M5 Pro corroborating; iPad-M4 optional, **never auto-approved**) | existing `pytest -m slow -k test_ane_compute_plan` | existing Phase-5 control: a deliberately CPU-only op must fail the count assertion | ⬜ pending |
| RD-06b | Decoder p99 under 2 ms with real weights | evidence (device-labeled) | `CortexDecoderBench` on regenerated `.mlpackage` | n/a (measurement, device-gated per D-17) | ⬜ pending |
| RD-06c | Python quick suite runs as a blocking CI gate | CI-blocking | the `decoder-python` job in `ci.yml` | a deliberately failing quick test on a scratch branch must turn the job red | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Test infrastructure exists (pytest 8, 21 test modules, `slow` marker, `conftest.py`). The gaps are
fixtures and gate scaffolding, not framework installation.

- [ ] `Decoder/manifests/indy_sessions.json` corrected to a genuine M1-only set — **`indy_20160624_03`,
      `indy_20160627_01`, `indy_20160630_01`, `indy_20160915_01`** (user-selected Option B: 1.77 GB,
      285,359 bins, 83-day span, exercises both `finger_pos` widths). Add `size_bytes` and `md5`
      fields; record why `indy_20160407_02` and `indy_20160411_01` were dropped (192-channel M1+S1).
      This is Wave 0 because everything downstream depends on it. Covers P1, P2, RD-01b.
- [ ] `Decoder/tests/fixtures/tiny_v73.mat` plus its generator script (D-20). Must contain: `spikes`
      as an object-reference array with both `MATLAB_empty` payload shapes (`[0,0]` and `[0,1]`), a
      `t` vector **starting at 0.0** so the P3 negative control can bite, and a `finger_pos` with a
      near-constant row 0 and two varying rows so the P4 control can bite. Covers RD-02a/b/c/d.
- [ ] `Tools/scripts/decoder-policy.sh` + `--self-test`, structurally copied from `bps-policy.sh`,
      with a bare-`python3` helper for checksum set comparison (`check_refit_uplift.py` precedent).
      Covers RD-01a, RD-03c.
- [ ] `decoder-python` job in `.github/workflows/ci.yml` with `astral-sh/setup-uv@v8`. Covers RD-06c.
- [ ] Multi-session fallback in `test_heldout_cobps.py::_load_binned` and
      `test_data.py::test_load_session_real_mat` (P5). Blocks every real-data test the moment data lands.
- [ ] Metrics JSON schema plus `test_metrics_schema.py`. Covers RD-04a/b, RD-05b, RD-03b.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real-data pooled + LOSO training run | RD-03, RD-04 | ~1.5 h CPU; produces the committed numbers, never a CI gate (D-21) | `uv sync --project Decoder --extra dev`; `uv run --project Decoder python Decoder/scripts/download_indy.py`; `uv run --project Decoder pytest -m slow -q`; transcribe into `09-training-evidence.md` + metrics JSON |
| Lag sweep (0-160 ms) on the TRAIN split | RD-03 (D-08) | Sweep over 9 whole-bin offsets; the full curve is published, not just the argmax | script or slow test (Implementer's Discretion); record every swept value |
| Integrity negative control on a real fetched file | RD-01 | Requires the 1.77 GB dataset present | copy a fetched `.mat`, flip one byte, re-run `download_indy.py`, capture the `ValueError` transcript in the evidence artifact |
| Decoder p99 with real weights on device | RD-06 | Hardware-gated; M5 Pro corroborating, iPad-M4 canonical **never auto-approved** (D-17, standing device-checkpoint rule) | `CortexDecoderBench` against the regenerated `.mlpackage`; label the device explicitly |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
