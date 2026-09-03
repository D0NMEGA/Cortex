---
phase: 9
slug: real-data-ingest-ndt1-retrain-zenodo-3854034
status: audited
nyquist_compliant: true
wave_0_complete: true
created: 2026-08-30
audited: 2026-09-02
automated_covered: 18
partial: 1
manual_only: 4
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
| RD-01a | Manifest has zero `"PENDING"` sha256 entries | CI-blocking | `./Tools/scripts/decoder-policy.sh` (exit 0) | `--self-test` "reintroduce a PENDING sha256" -> exit 1, PASS | ✅ green |
| RD-01b | Every session declares `id`, `url`, `sha256`, `size_bytes`, `md5`; direct (non-`/api/`) URL | CI-blocking | `pytest -k test_manifest` (10 tests) | `test_every_url_is_direct_file_not_api`, `test_every_session_declares_size_and_md5`, `test_sha256_is_pending_or_64_hex` | ✅ green |
| RD-01c | Integrity gate raises on a corrupted `.mat` | CI-blocking | `pytest -k test_rejects_sha256_mismatch` (`test_download_integrity.py`) | `test_matching_sha256_verifies_without_rewrite` is the discriminating control; `test_rejects_size_mismatch` and `test_rejects_md5_mismatch` cover the other two pre-checks | ✅ green |
| RD-01d | Downloader rejects a non-MATLAB payload (P2) | CI-blocking | `pytest -k test_rejects_html_error_page` | `test_valid_payload_fills_pending_sha256` proves real `MATLAB 7.3 MAT-f` magic bytes do not raise | ✅ green |
| RD-02a | Cell-array dereference skips `MATLAB_empty` cells | CI-blocking | `pytest -k test_empty_cells_contribute_no_counts` (`test_fixture_v73.py`) | `test_matlab_empty_attribute_is_the_discriminator` is the no-attribute variant control | ✅ green |
| RD-02b | Channel-axis transpose correct; 192-ch structure raises informatively | CI-blocking | `pytest -k "test_channel_axis_transpose_is_correct or test_192_channel_session_raises_naming_the_true_width"` | the 192-channel variant must raise naming 192, not the unit count | ✅ green |
| RD-02c | `finger_pos` planar pair is rows **1-2**, not 0-1 (P4) | CI-blocking | `pytest -k test_finger_pos_planar_pair_is_rows_1_and_2` | `test_finger_pos_sign_is_undone` and `test_six_row_finger_pos_uses_the_same_planar_rows`; the fixture's near-constant row 0 makes a 0-1 extractor fail | ✅ green |
| RD-02d | 20 ms binned per-channel rates fall in the pinned plausible band | CI-blocking (fixture) + evidence (real) | `pytest -k test_firing_rate_band` (9 tests) | `test_inflated_density_falls_outside_the_band`; `test_missing_stat_key_raises` stops a silently-skipped bound | ✅ green |
| RD-02e | All selected real sessions load end to end | evidence (human-run) | `report_sessions.py` -> `09-ingest-evidence.md` "Session set" | "Why two sessions were dropped" records both 192-channel exclusions with their measured width | ✅ green |
| RD-03a | Held-out chronological-tail co-bps on real spikes beats the train-split mean-rate null | evidence (human-run) | `pytest -m slow -k test_heldout_cobps_beats_mean_rate_null` with real `.mat` present | `09-training-evidence.md` publishes both nulls and the -8.1% drift; `test_masked_input_isolation.py` guards the corrected objective | ✅ green (requires the 1.77 GB dataset) |
| RD-03b | Committed margin re-derived from the observed value, not inherited | CI-blocking | `pytest -k test_cobps_margin` (11 tests) | `test_margin_is_not_the_phase4_synthetic_constant` plus three superseded-constant controls and `test_the_chain_has_all_four_links` | ✅ green |
| RD-03c | Published number traceable to the bytes it came from | CI-blocking | `./Tools/scripts/decoder-policy.sh` assertions (b) and (c) | `--self-test` strips `data_source` (exit 1) and perturbs one metrics checksum (exit 1); both PASS, and the clean-tree case passes | ✅ green |
| RD-04a | Per-session held-out co-bps for every pooled session | evidence + CI schema | `pytest -k test_per_session_cobps_covers_every_session` | `test_session_ids_and_checksums_match_the_manifest` fails if a session is dropped from the metrics JSON | ✅ green |
| RD-04b | Full four-fold LOSO rotation with mean and spread | evidence + CI schema | `pytest -k test_loso_is_a_full_rotation` (in `test_metrics_schema.py` and `test_sessions.py`) | a 3-fold array fails the length assertion; `test_loso_rejects_duplicate_session_ids` guards the rotation | ✅ green |
| RD-05a | Palettized package exists and is smaller; ratio recorded | evidence + CI structure | `pytest -m slow -k test_palettized_package_exists_and_is_smaller` | existing Phase-4 control retained | ✅ green (requires the built `.mlpackage`) |
| RD-05b | Palettization delta on BOTH models (Poisson-NLL on reconstruction, R2 on with-velocity) | evidence | `pytest -k test_palettization_reports_both_models` + metrics `palettization` | schema test fails if either key or its `model` label is absent; determinism recorded as identical across two runs | ✅ green |
| RD-06a | All schedulable ops ANE-eligible, zero CPU-only, on the with-velocity real-data model | evidence (M5 Pro corroborating; iPad-M4 optional, **never auto-approved**) | `pytest -m slow -k test_ane_compute_plan` + metrics `ane` | existing Phase-5 control: a deliberately CPU-only op must fail the count assertion | ✅ green — **239/239 eligible, 0 CPU-only.** The plan-time row said 226/226; the real-data graph schedules 239 because the graph changed. Published as measured with the per-op-type diff in `09-coreml-evidence.md`, not adjusted to fit the expectation |
| RD-06b | Decoder p99 under 2 ms with real weights | evidence (device-labeled) | `CortexDecoderBench` on the regenerated `.mlpackage` | n/a (measurement, device-gated per D-17) | ✅ green on **Apple M5 Pro, p99 0.141 ms, n=10k, `status: corroborating`, placement CPU**. iPad-M4 canonical capture DEFERRED (Plan 09-11, never auto-approved) |
| RD-06c | Python quick suite runs as a blocking CI gate | CI-blocking | the `decoder-python` job, `.github/workflows/ci.yml:556` | a deliberately failing quick test on a scratch branch must turn the job red | ⚠️ PARTIAL — the job exists and every command it runs is green locally, but `gh run list` returns `[]`: **the workflow has never executed.** The negative control is unrun |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Test infrastructure exists (pytest 8, 21 test modules, `slow` marker, `conftest.py`). The gaps are
fixtures and gate scaffolding, not framework installation.

- [x] `Decoder/manifests/indy_sessions.json` corrected to a genuine M1-only set — **`indy_20160624_03`,
      `indy_20160627_01`, `indy_20160630_01`, `indy_20160915_01`** (user-selected Option B: 1.77 GB,
      285,359 bins, 83-day span, exercises both `finger_pos` widths). Add `size_bytes` and `md5`
      fields; record why `indy_20160407_02` and `indy_20160411_01` were dropped (192-channel M1+S1).
      This is Wave 0 because everything downstream depends on it. Covers P1, P2, RD-01b.
- [x] `Decoder/tests/fixtures/tiny_v73.mat` plus its generator script (D-20). Must contain: `spikes`
      as an object-reference array with both `MATLAB_empty` payload shapes (`[0,0]` and `[0,1]`), a
      `t` vector **starting at 0.0** so the P3 negative control can bite, and a `finger_pos` with a
      near-constant row 0 and two varying rows so the P4 control can bite. Covers RD-02a/b/c/d.
- [x] `Tools/scripts/decoder-policy.sh` + `--self-test`, structurally copied from `bps-policy.sh`,
      with a bare-`python3` helper for checksum set comparison (`check_refit_uplift.py` precedent).
      Covers RD-01a, RD-03c.
- [x] `decoder-python` job in `.github/workflows/ci.yml` (shipped with `astral-sh/setup-uv@v10.0.1`; `@v8` does not exist). Covers RD-06c.
- [x] Multi-session fallback in `test_heldout_cobps.py::_load_binned` and
      `test_data.py::test_load_session_real_mat` (P5). Blocks every real-data test the moment data lands.
- [x] Metrics JSON schema plus `test_metrics_schema.py`. Covers RD-04a/b, RD-05b, RD-03b.

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

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planner sign-off 2026-08-30 (11 plans, 7 waves).

- [x] All tasks have `<automated>` verify; no MISSING references (the `tiny_v73.mat` fixture and the
      `decoder-policy.sh` gate are created inside Plans 09-02 / 09-09 before anything asserts on them)
- [x] Sampling continuity: every plan's tasks end in a runnable command; no 3 consecutive tasks
      without an automated verify
- [x] The six Wave 0 gaps map to plans: manifest -> 09-01, fixture -> 09-02, metrics schema -> 09-06
      (writer) + 09-09 (test), `decoder-policy.sh` -> 09-09, `decoder-python` CI job -> 09-09,
      multi-session test fallback (P5) -> 09-04
- [x] No watch-mode flags; quick-suite feedback latency ~2 s measured
- [x] Every CI-blocking command runs green on a checkout with an empty `Decoder/data/`

---

## Validation Audit 2026-09-02

| Metric | Count |
|--------|-------|
| Gaps found | 0 missing, 1 partial |
| Resolved | 0 (no new tests were needed) |
| Escalated | 1 (RD-06c) |

Run on the reconciled contract, not on the plan-time seed. Ground truth this audit measured:

- `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` -> **208 passed, 9 deselected in 4.71 s**
- `./Tools/scripts/decoder-policy.sh` -> exit 0, all four assertions ok
- `./Tools/scripts/decoder-policy.sh --self-test` -> exit 0; the clean-tree case passes and all three
  negative controls bite (reintroduced `PENDING`, stripped `data_source`, perturbed checksum)
- The 9 `slow` tests are the evidence tier and were deliberately not run: they need the gitignored
  1.77 GB dataset or a built `.mlpackage`. Their results live in the four committed evidence artifacts.

No requirement was found without coverage, so no test was generated. Three defects were in the
contract itself rather than in the test suite:

1. **Five `-k` selectors matched zero tests.** `test_download_integrity_gate`, `test_fixture_empty_cells`,
   `test_fixture_channel_axis`, `test_fixture_finger_pos_axes` and `test_cobps_margin_documented` were
   plan-time guesses at names the executor never used. Every behavior they described is covered, under
   the real names now in the map. A reader who had run the old commands would have seen "no tests ran"
   and could have read it as absence of coverage.
2. **RD-06a asserted 226/226 ANE ops.** The real-data with-velocity graph schedules **239**, all
   eligible, 0 CPU-only. The evidence artifact already published this as measured with a per-op-type
   diff against the Phase-5 baseline; only this contract still carried the superseded number.
3. **Every row read `pending` and `status: planned`** after a phase that shipped and was verified 5/5.

### Escalated: RD-06c

The `decoder-python` job is present at `.github/workflows/ci.yml:556`, triggers on push and PR to
`main`, pins `astral-sh/setup-uv@v10.0.1`, runs `pytest -m "not slow"` and then `decoder-policy.sh`
with its `--self-test`. Every one of those commands is green locally.

What is unproven is the gate itself: `gh run list` returns `[]`, so this workflow has never executed
on GitHub Actions. Its negative control (a deliberately failing quick test must turn the job red) has
therefore never been exercised, and the "CI-blocking" tier label on nine rows above describes an
intent rather than a demonstrated behavior. This is not specific to Phase 9 - no CI run exists for
this repository at all. It is recorded here rather than resolved, because arming it means pushing a
branch and opening a PR, which is out of an audit's scope.
