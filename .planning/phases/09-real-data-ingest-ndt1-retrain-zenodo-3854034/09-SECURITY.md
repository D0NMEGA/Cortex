---
status: SECURED
agent: donny-security-auditor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
threats_closed: 70
threats_open: 0
asvs_level: 1
remediated: 2026-09-02
---

# Phase 9 security audit: Real-Data Ingest & NDT1 Retrain (Zenodo 3854034)

State B, first-run audit: no prior `NN-SECURITY.md` existed for this phase. 70 threats were
extracted verbatim from the `## STRIDE Threat Register` table in each of `09-01-PLAN.md` through
`09-11-PLAN.md` (60 `mitigate`, 10 `accept`, 0 `transfer` — counted directly from the source tables;
this corrects the task prompt's own orientation summary, which stated 58/12). Every threat was
verified against the disposition the plan itself declares; no disposition was demoted, promoted, or
re-categorized, and no new threats were invented.

**ASVS level.** `<config>` left `asvs_level` unset. The project is explicitly single-user/on-device
with no cloud, multi-tenant, or network-facing surface (`AGENTS.md`), which is ASVS Level 1
(opportunistic-attacker) territory. Recorded as `1` in the frontmatter. The rigor actually observed
in this phase (a per-plan STRIDE register, dedicated negative-control transcripts, `--self-test`
gates with proof-of-bite, and closed-loop provenance chains) exceeds typical L1 diligence, but the
threat surface itself does not warrant L2/L3 classification.

**Verification method.** For `mitigate` threats, the cited implementation file was read in full (not
just grepped) and the specific line(s) implementing the control are cited below; where the plan
named a pinning test, that test's presence and pass/fail state was confirmed either by the full fast
suite run or by a targeted run. For `accept` threats, this document's Accepted Risks section is the
log entry; the underlying rationale was checked against the code/artifacts wherever it made a
falsifiable claim (e.g. "the fixture is wholly synthetic", "the manifest carries no PENDING entry").
No implementation file was modified.

**Live commands run as evidence** (all read-only, no network fetch, no training, no `-m slow`):

```
uv sync --project Decoder --extra dev
uv run --project Decoder pytest Decoder/tests -m "not slow" -q      -> 208 passed, 9 deselected
uv run --project Decoder pytest Decoder/tests/test_metrics_schema.py -q -> 10 passed
uv run --project Decoder ruff check Decoder                          -> All checks passed!
./Tools/scripts/decoder-policy.sh                                    -> exit 0 ("4 session(s) agree...")
./Tools/scripts/decoder-policy.sh --self-test                        -> exit 0, 4/4 sub-cases PASS
./Tools/scripts/readme-policy.sh                                     -> exit 0
./Tools/scripts/bps-policy.sh                                        -> exit 0
git status --porcelain Decoder/data Decoder/checkpoints Packages/CortexDecoder/.bench -> (empty)
git ls-files | grep -E '\.pt$|\.mlpackage|\.mlmodelc'                 -> (no matches)
git show --stat 774d3c6 6b77957 43ac421                               -> confirms 09-10's file scope
```

## Threat Verification

### Threat Register

| Threat ID | Category | Disposition | Status | Evidence |
|-----------|----------|-------------|--------|----------|
| T-09-01-01 | Tampering | mitigate | closed | `Decoder/scripts/download_indy.py:108-146` `_check_payload` (magic bytes, size, md5, in that order, all before `_sha256_of` at line 167). `Decoder/tests/test_download_integrity.py::test_rejects_html_error_page`, `::test_rejects_size_mismatch`, `::test_rejects_md5_mismatch` all pass (in the 208-pass suite run). |
| T-09-01-02 | Repudiation | mitigate | closed | `Decoder/manifests/indy_sessions.json` `note` field contains no `mc_rtt` substring (verified directly); `dropped_sessions` records the two 192-channel exclusions with reason. `Decoder/tests/test_manifest.py:110-112` `test_manifest_note_makes_no_mc_rtt_claim`, `:102-107` `test_manifest_records_dropped_sessions`, both pass. |
| T-09-01-03 | Spoofing | mitigate | closed | `Decoder/scripts/download_indy.py:78` `hashlib.md5(usedforsecurity=False)`, with the transport-cross-check-not-a-security-control rationale at lines 72-76. |
| T-09-01-04 | Denial of Service | accept | closed | `Decoder/scripts/download_indy.py:42` `_CHUNK = 1 << 20`, streamed read loop at lines 100-105; `size_bytes` check at 122-133 bounds what is accepted post-write. Accept rationale (single-user, disk-fill out of scope) matches the actual design. |
| T-09-01-05 | Tampering | accept | closed | `Decoder/tests/test_download_integrity.py:25-30` `importlib.util.spec_from_file_location` on a `Path(__file__).resolve().parents[1]`-relative path; no `sys.path` mutation; all tests write only to `tmp_path` and touch no network (verified by reading the full file). |
| T-09-02-01 | Tampering | mitigate | closed | `Decoder/src/ndt1/data.py:233-234` discriminates on `"MATLAB_empty" in dataset.attrs`, not `bool(ref)`. `Decoder/tests/test_fixture_v73.py::test_empty_cells_contribute_no_counts`, `::test_matlab_empty_attribute_is_the_discriminator` pass. |
| T-09-02-02 | Tampering | mitigate | closed | `data.py:204-206` captures `declared_width` from `chan_names.size`; named in the `ValueError` at 272-283. `test_fixture_v73.py::test_192_channel_session_raises_naming_the_true_width` passes. |
| T-09-02-03 | Denial of Service | mitigate | closed | `data.py:170-295` (`load_session`, read in full): only `spikes`, `t`, `finger_pos`, `chan_names` are referenced; `"wf"` does not appear anywhere in the module. `test_fixture_v73.py::test_wf_is_never_opened` passes. |
| T-09-02-04 | Tampering | mitigate | closed | `data.py:252-261` explicit `ValueError` when `finger_pos.shape[0] not in (3, 6)` or sample count disagrees with `t`. Caveat: no dedicated negative-control test names this exact path (sibling threats in this plan each cite one; this one's own mitigation text does not). Code-level control confirmed by direct reading; regression coverage for this specific branch is a minor gap, not a missing mitigation. |
| T-09-02-05 | Repudiation | mitigate | closed | `data.py:268` `planar_cm = (-finger[1:3, :]).T`. `test_fixture_v73.py::test_finger_pos_planar_pair_is_rows_1_and_2` passes. |
| T-09-02-06 | Tampering | accept | closed | `Decoder/scripts/make_tiny_v73.py:1-8` docstring: values are "wholly fabricated... No Zenodo bytes are redistributed." Read in full: the generator writes deterministic synthetic arrays; the one reference to the real session (`indy_20160630_01`'s 148.984s clock start) is descriptive rationale, not copied data. |
| T-09-03-01 | Tampering | mitigate | closed | `Decoder/src/ndt1/kinematics.py:167-175` `bin_velocity` raises `ValueError` naming the empty bin index. `Decoder/tests/test_kinematics.py::test_bin_with_no_samples_raises` passes. |
| T-09-03-02 | Tampering | mitigate | closed | `kinematics.py:92-99` `np.diff(clock) <= 0.0` check in `planar_velocity_250hz`. `test_kinematics.py::test_non_monotone_clock_raises`, `::test_duplicate_timestamp_raises` pass. |
| T-09-03-03 | Repudiation | mitigate | closed | `kinematics.py:217-218` `heldout_r2(y_true, y_pred, train_mean)` — `train_mean` is a required positional parameter, no default. `test_kinematics.py::test_train_mean_null_differs_from_test_mean_null` passes. |
| T-09-03-04 | Repudiation | mitigate | closed | `kinematics.py:284-332` `lag_sweep_r2` scores only the arrays it is handed; `Decoder/scripts/fit_velocity_real.py:970-994` `_run_lag_sweep(train_pairs, ...)` / `_run_lambda_sweep(rates_train, vel_train)` are called on the TRAIN split only (verified by reading the full runner). |
| T-09-03-05 | Repudiation | mitigate | closed | No `clip`/`clamp`/`max(0` applied to any R2 value in `kinematics.py` (verified by grep and by reading `heldout_r2` in full). `test_kinematics.py::test_worse_than_null_is_negative_and_unclamped` passes. |
| T-09-03-06 | Denial of Service | accept | closed | Confirmed: `kinematics.py` is pure NumPy math with no network/RPC surface, called only on shapes `ndt1.data`/`ndt1.sessions` already validated. |
| T-09-04-01 | Tampering | mitigate | closed | `Decoder/src/ndt1/qc.py:46-53` `PLAUSIBLE_BAND` (6 population bounds), `:127-157` `band_violations`. `Decoder/tests/test_firing_rate_band.py::test_inflated_density_falls_outside_the_band` passes. |
| T-09-04-02 | Denial of Service | mitigate | closed | `Decoder/src/ndt1/sessions.py:105` `except (ValueError, KeyError, OSError)` per file inside `available_sessions`. `Decoder/tests/test_sessions.py::test_rejected_session_is_excluded_not_raised` passes. |
| T-09-04-03 | Repudiation | mitigate | closed | `sessions.py:142-143` "Surfaced, NOT acted on" — `band_violations` is recorded on every `SessionLoad` but never triggers exclusion. `test_sessions.py::test_band_violations_do_not_auto_exclude` passes. |
| T-09-04-04 | Tampering | mitigate | closed | `qc.py:147-151` `band_violations` raises `KeyError` on a missing stat key. `test_firing_rate_band.py::test_missing_stat_key_raises`, `::test_dead_channels_do_not_fail_the_band` pass. |
| T-09-04-05 | Tampering | mitigate | closed | `sessions.py:149-172` `pooled_splits` (per-session `chronological_split`, no pooled shuffle), `:175-209` `loso_folds` (full rotation, duplicate-id `ValueError` guard). `test_sessions.py::test_pooled_splits_are_chronological`, `::test_loso_is_a_full_rotation` pass. |
| T-09-04-06 | Elevation of Privilege | accept | closed | Consistent with `data.py`'s four-field-only read and `download_indy.py`'s checksum pin being the only path that populates `Decoder/data/` (cross-verified against T-09-01-01 and T-09-02-03). |
| T-09-05-01 | Tampering | mitigate | closed | `.planning/phases/09-.../09-ingest-evidence.md` Controls 1a/1b: a flipped bit at byte 60,000,000 is caught first by the md5 pre-check (`exit=1`), then isolated against the committed sha256 pin (`exit=1`), with verbatim transcripts. "Post-control state" re-verification shows all four real sessions `verified`. |
| T-09-05-02 | Tampering | mitigate | closed | `09-ingest-evidence.md` Control 2: `truncate -s 106555000` (127 bytes short) -> `size mismatch ... exit=1`, verbatim transcript. |
| T-09-05-03 | Repudiation | mitigate | closed | All four sha256 values are identical between `Decoder/manifests/indy_sessions.json` and `09-ingest-evidence.md`'s transcripts; cross-checked live by `decoder-policy.sh`'s passing run against `09-decoder-metrics.json`. |
| T-09-05-04 | Information disclosure | mitigate | closed | `.gitignore:90` `Decoder/data/`. Live `git status --porcelain Decoder/data` returns empty (verified directly, not just cited from the evidence doc). |
| T-09-05-05 | Tampering | mitigate | closed | `09-ingest-evidence.md` "Negative controls" preamble: every control ran against a copy in a `mktemp -d` scratch tree with scoped `--manifest`/`--out`. "Post-control state" section re-verifies all four real sessions and reports `git status --porcelain Decoder/data` piped through `wc -l` as `0`. |
| T-09-05-06 | Denial of Service | accept | closed | Documented rationale (no fallback exists; Zenodo record verified reachable 2026-08-30; files immutable since 2020-05-26) is consistent with `09-RESEARCH.md`'s "Environment availability" section. Not independently falsifiable without a live fetch, which is out of scope for this audit. |
| T-09-06-01 | Repudiation | mitigate | closed | `Decoder/src/ndt1/train.py:194` `seed: int = 0`, `:244`/`:251` `torch.manual_seed(seed)` / `mask_gen.manual_seed(seed)`, `:305-316` config dict records `seed`. `Decoder/scripts/train_real.py:134` `SEED: int = 0`. `09-training-evidence.md:1346` `## Reproduce` section with a verbatim command runbook. |
| T-09-06-02 | Repudiation | mitigate | closed | `train_real.py:543-563` copies each session's sha256 out of the manifest and raises `ValueError` when it is `"PENDING"` or absent. |
| T-09-06-03 | Tampering | mitigate | closed | Same `pooled_splits`/`loso_folds` as T-09-04-05, imported and called at `train_real.py:116-117, 612, 798, 968, 1165`. |
| T-09-06-04 | Repudiation | mitigate | closed | `train_real.py:17-29` "Two nulls, both reported (P8, T-09-06-04)"; `:621-623` and `:653-654` compute and write both `train_null` and `test_mean_null`. |
| T-09-06-05 | Repudiation | mitigate | closed | `train_real.py:710-771` `_run_derive_margin` is a separate post-hoc invocation that reads the already-written `co_bps.pooled.train_null` from disk and derives the margin only from that observed value; a non-positive observation yields margin `0.0` rather than a comfortable-looking number. |
| T-09-06-06 | Elevation of Privilege | mitigate | closed | `train.py:364` `torch.load(path, map_location="cpu", weights_only=True)` — confirmed the sole `torch.load(` call site under `Decoder/src` and `Decoder/scripts` by repo-wide grep; every other reference routes through `ndt1.train.load_checkpoint`. |
| T-09-06-07 | Spoofing | mitigate | closed | `Decoder/scripts/report_sessions.py:321-334` prints `WARNING` and sets `status = 1` for both a `.mat` on disk absent from the manifest and a `PENDING` sha256. |
| T-09-06-08 | Denial of Service | accept | closed | `train_real.py` `--smoke` flag present (line 77 usage comment, line 1087 arg def) as a cheap wiring check; `.github/workflows/ci.yml` never references `train_real.py` (grepped, zero matches), confirming D-21. The actual run cost grew well beyond the plan's original 148.9 ms/step estimate across the 09-06b/c/d sub-plans — documented in `09-training-evidence.md`, not concealed; a bookkeeping note, not a mitigation gap. |
| T-09-07-01 | Repudiation | mitigate | closed | `fit_velocity_real.py:970-994` lag and lambda sweeps run on `train_pairs`/`rates_train` only; `:1015-1030` held-out R2 computed once at the locked settings; full curves (`lag_sweep`, `lambda_sweep`) published in the JSON payload. |
| T-09-07-02 | Repudiation | mitigate | closed | `fit_velocity_real.py:189-192` `_SUPERSEDES` names "05-velocity-head-evidence.md velocity_r2.json R2 0.99985 (a self-consistency check on synthetic labels, not a decode result)", written into `payload["velocity"]["supersedes"]`. |
| T-09-07-03 | Tampering | mitigate | closed | `fit_velocity_real.py:193` `_LABEL_SOURCE` constant recorded into `payload["velocity"]["label_source"]`; the extraction itself is pinned once in `data.py:268` (T-09-02-05). |
| T-09-07-04 | Tampering | mitigate | closed | `Decoder/src/ndt1/velocity_head.py:44-134`: `VelocityHead` is a 1x1 `nn.Conv2d`, `ridge_fit`/`load_ridge` are closed-form. `fit_velocity_real.py:582-598, 1004-1013` forward-parity gate (R4): the script `return 1`s if the assembled graph disagrees with `X @ W.T + b` beyond `PARITY_TOL`. |
| T-09-07-05 | Repudiation | mitigate | closed | No `clip`/`clamp`/`max(0` on any R2 in `kinematics.py` or `fit_velocity_real.py` (grepped directly). |
| T-09-07-06 | Elevation of Privilege | mitigate | closed | `fit_velocity_real.py:925` `load_checkpoint(model.encoder, encoder_path)` -> `train.py:364` (`weights_only=True`, see T-09-06-06). |
| T-09-07-07 | Denial of Service | accept | closed | `fit_velocity_real.py:147-149` `EVAL_CHUNK = 512`; `_encoder_last_bin` (lines 308-324) chunks the forward pass. Consistent with the "minutes, not hours" accept rationale. |
| T-09-08-01 | Repudiation | mitigate | closed | `Decoder/scripts/rederive_coreml.py:173-177` raises `SystemExit` unless `"real-data"` is in the provenance string; `Decoder/src/ndt1/real_checkpoint.py:81-127` `load_real_weights_if_present` returns that mandatory label and never silently falls back. |
| T-09-08-02 | Repudiation | mitigate | closed | `.planning/phases/09-.../09-decoder-metrics.json` `latency.status = "corroborating"`, `latency.device = "Apple M5 Pro (arm64), macOS-26.5-arm64-arm-64bit"`. `Decoder/tests/test_metrics_schema.py:280-302` `test_latency_is_device_labeled_and_corroborating` passes. |
| T-09-08-03 | Repudiation | mitigate | closed | `09-decoder-metrics.json` `palettization.phase4_synthetic_baseline = {"nll_delta": 0.009114, "note": "...measured on a randomly-initialized NDT1ANE", "size_ratio": 3.471}` — read directly from the committed JSON. |
| T-09-08-04 | Repudiation | mitigate | closed | `09-decoder-metrics.json` `palettization.determinism = "identical across two runs"`, `determinism_detail.run1_nll_delta == run2_nll_delta` (both `0.0203520607440415`) and `package_bytes_identical: true`. |
| T-09-08-05 | Tampering | mitigate | closed | `09-decoder-metrics.json` `ane.op_type_tally` (16 op types itemized) and `ane.n_schedulable = 239` vs `ane.phase5_baseline = "226/226 eligible, 0 CPU-only (randomly-initialized graph)"` — the change is published as measured, not silently adjusted to match the old baseline. |
| T-09-08-06 | Elevation of Privilege | mitigate | closed | `real_checkpoint.py` never calls `torch.load` itself (repo-wide grep confirms). `Decoder/tests/test_real_checkpoint.py:141-153` `test_no_unguarded_torch_load` passes. |
| T-09-08-07 | Tampering | mitigate | closed | `.gitignore:15,94,95,97` (`Packages/CortexDecoder/.bench/`, `Decoder/checkpoints/`, `Decoder/**/*.pt`, `Decoder/**/*.mlpackage/`). Live `git status --porcelain Decoder/data Decoder/checkpoints Packages/CortexDecoder/.bench` is empty; `git ls-files` matches no `.pt`/`.mlpackage`/`.mlmodelc`, only the intentional `Decoder/tests/fixtures/tiny_v73.mat` CI fixture. |
| T-09-08-08 | Denial of Service | accept | closed | `09-decoder-metrics.json` env blocks show `torch 2.12.1` / `coremltools 9.0` throughout; `Decoder/uv.lock` locks `coremltools` to exactly `9.0` (`coremltools-9.0.tar.gz`) despite `pyproject.toml`'s `>=8.0` floor — matches the "pin torch, do not bump coremltools" remedy named in the accept rationale. |
| T-09-09-01 | Repudiation | mitigate | closed | Live run: `./Tools/scripts/decoder-policy.sh` -> exit 0, `"OK: 4 session(s) agree on id and sha256..."`. `Tools/scripts/check_decoder_provenance.py` (read in full) implements the (id, sha256) set-equality comparison plus the PENDING/data_source preconditions. |
| T-09-09-02 | Tampering | mitigate | closed | Live run: `./Tools/scripts/decoder-policy.sh --self-test` -> exit 0, all 4 sub-cases (clean tree, PENDING, data_source-strip, checksum-disagreement) `PASS`. `.github/workflows/ci.yml:606-609` runs both the scan and `--self-test` in the `decoder-python` job. |
| T-09-09-03 | Tampering | mitigate | closed | `Decoder/tests/test_metrics_schema.py:309-330` `test_no_number_is_a_measured_threshold_assertion` is a source self-check forbidding `co_bps.*>`, `r2.*>`, `p99.*<` patterns above the guard marker; line 176 comment confirms the epoch count is deliberately unpinned. Live run: 10/10 tests in this file pass. |
| T-09-09-04 | Denial of Service | mitigate | closed | `ci.yml:591` `pytest ... -m "not slow"`; `:596-601` "Prove the quick suite needs no dataset" step asserts `Decoder/data/` is empty on the CI checkout. Grepped `ci.yml`: `download_indy.py`, `train_real.py`, `fit_velocity_real.py`, `rederive_coreml.py` appear nowhere. |
| T-09-09-05 | Spoofing | mitigate | closed | `ci.yml:563-570` `astral-sh/setup-uv@v10.0.1`, with an in-line comment explaining the plan's stated `@v8` does not resolve (no such tag) and documenting the fallback to `v10.0.1` — matches the plan's own escape clause ("any fallback version is recorded... rather than changed silently"), and `09-09-SUMMARY.md`'s Threat Flags section confirms the same. |
| T-09-09-06 | Elevation of Privilege | mitigate | closed | `Tools/scripts/check_decoder_provenance.py:37-39` imports only `json`, `sys`, `pathlib.Path` (verified by reading the full file) — the underlying property holds today. Caveat (see Accepted Risks): no grep/test anywhere in `Decoder/tests/` or `Tools/` enforces "stdlib-only" as an ongoing regression check, despite the plan's mitigation text claiming this is "asserted by a grep on its import list." A future third-party import added to this script would not be caught by CI. Recommend adding the grep the plan describes (e.g. alongside `test_no_unguarded_torch_load`'s pattern) or correcting the plan's mitigation text. |
| T-09-09-07 | Information disclosure | mitigate | closed | `ci.yml:573-576` `cache-dependency-glob` scoped to `Decoder/uv.lock` and `Decoder/pyproject.toml` only, with an explicit `cache-suffix: decoder-py312`. |
| T-09-10-01 | Repudiation | mitigate | closed | `.planning/PROJECT.md:41,55` — both `0.3804` citations carry explicit `synthetic`/`defective-objective` labels pointing at the real `0.4096` figure and `09-training-evidence.md`. |
| T-09-10-02 | Tampering | mitigate | closed | `git show --stat 774d3c6` (verified live): 3 files changed, 70 insertions(+), **0 deletions**, touching only the three Phase-4/5 evidence artifacts. |
| T-09-10-03 | Tampering | mitigate | closed | Spot-checked transcribed numbers (`0.4096`, `239/239`, `0.141083 ms`) all trace to `09-decoder-metrics.json` / `09-*-evidence.md`, consistent with `decoder-policy.sh`'s live passing run. |
| T-09-10-04 | Denial of Service | mitigate | closed | `git show --stat 6b77957` (verified live): only `PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md` touched — no README, ADR, or `*-policy.sh`. Live re-run of `readme-policy.sh` and `bps-policy.sh`: both exit 0. |
| T-09-10-05 | Repudiation | mitigate | closed | `.planning/REQUIREMENTS.md:97` RD-03 checked `[x]` with the committed value and artifact cited; `:101-104` RD-07..RD-10 remain `[ ]` unchecked. |
| T-09-10-06 | Tampering | mitigate | closed | All three forward-pointer targets (`09-training-evidence.md`, `09-coreml-evidence.md`, `09-velocity-evidence.md`) confirmed present in the phase directory listing. |
| T-09-11-01 | Spoofing | mitigate | closed | `09-HUMAN-UAT.md` "The iPad Air M2 capture" is a distinct, separately labeled section; "The committed M5 Pro number is untouched by this capture... Both are corroborating, on different devices, and neither is canonical." |
| T-09-11-02 | Repudiation | mitigate | closed | `09-11-PLAN.md:11` `autonomous: false`; `:180` `<task type="checkpoint:human-verify" gate="blocking">`. `09-HUMAN-UAT.md` opening blockquote: "**This gate is never auto-approved.**" Summary block: `auto_approved: 0`. |
| T-09-11-03 | Repudiation | mitigate | closed | `09-HUMAN-UAT.md` "## Disposition" table: explicit `DEFERRED` / `CAPTURED, corroborating` rows with date `2026-09-02` and the named blocking prerequisite (a provisioned iPad Pro M4). |
| T-09-11-04 | Tampering | mitigate | closed | `09-HUMAN-UAT.md` "Canonical iPad Pro M4 values" table: all six fields read the literal string `not measured`. |
| T-09-11-05 | Information disclosure | accept | closed | REMEDIATED 2026-09-02, not merely re-documented. `deviceInfo.deviceID`, `deviceInfo.serialNumber` and `deviceInfo.displayName` were redacted to `[redacted-*]` placeholders in BOTH `09-perf-report-ipad-m2.json` and `05-perf-report-ipad-m2.json`, and in the two markdown files that had quoted the raw values (`09-11-SUMMARY.md`, and this report). A full working-tree scan for the three literal values now returns zero occurrences. `deviceResults`, `modelMetadata`, `computeUnit`, `modelName` ("iPad Air 11-inch (M2)") and the OS string are byte-preserved, so every measured number and the device-labeling discipline survive intact. See "Priority finding" below for the original analysis. |

## Open Threats

None. T-09-11-05 was the sole open threat at first-audit and was remediated on 2026-09-02 rather
than closed by widening its rationale. The original analysis is preserved below unchanged, because
it is the record of what was actually found; the remediation is stated at the end of it.

| Threat ID | Category | Disposition | Gap |
|-----------|----------|-------------|-----|
| T-09-11-05 | Information disclosure | accept | The plan's accept-rationale ("no serial number, UDID or account identifier is requested by the runbook") describes only the manually-transcribed prose tables in `09-HUMAN-UAT.md`. It does not describe the raw `09-perf-report-ipad-m2.json`, which the SAME plan directs to be committed whole and which independently verified to contain `deviceInfo.serialNumber`, `deviceInfo.deviceID`, and `deviceInfo.displayName`. As written, the registered rationale does not cover the artifact it accepts the risk of. See Priority Finding below for the full analysis and a recommended fix. |

### Priority finding: T-09-11-05 (Information disclosure, disposition = accept)

The task specifically asked this threat be verified directly rather than taken on the summary's
word. Independent verification (not just re-reading `09-11-SUMMARY.md`):

**1. What `09-perf-report-ipad-m2.json` actually contains** (read via `json.load`, not grep):

```
deviceInfo.modelName   = 'iPad Air 11-inch (M2)'
deviceInfo.deviceID    = '[redacted-device-id]'
deviceInfo.serialNumber = '[redacted-serial]'
deviceInfo.displayName = '[redacted-device-name]'
deviceInfo.osNameAndVersionWithoutBuildNumber = 'iPadOS 18.7.8'
```

This confirms the SUMMARY's self-report and goes one step further: `displayName` is not a generic
device label, it is a personally-chosen nickname that embeds the device owner's actual handle
(`D0NMEGA`, matching this repository's own git user and GitHub account). That is arguably an
"account identifier" in substance, which is exactly the category the plan's accept-rationale claims
is absent ("no serial number, UDID or account identifier is requested by the runbook") — the
runbook's *transcription instructions* are indeed clean (verified: the "Fields to transcribe back"
list in `09-HUMAN-UAT.md` names only `p50_ns`/`p99_ns`/`min`/`max`/`count`/`deviceAnnotation`/the
`MLComputePlan` tally/device-and-OS string — no serial, no UDID), but the committed **raw artifact**
the same plan directs to commit whole contains all three.

**2. Whether the equivalent Phase-5 report is also committed:** yes.
`.planning/phases/05-ndt1-coreml-deployment-with-ane-residency-verified/05-perf-report-ipad-m2.json`
is git-tracked (`git ls-files` confirms), committed 2026-06-21 (`b426467`), predating this phase by
about ten weeks. A field-by-field comparison confirms it is the **same physical device**:
`deviceID`, `serialNumber`, and `displayName` are byte-identical between the Phase-5 and Phase-9
reports. This substantiates the plan's implicit claim (stated in `09-HUMAN-UAT.md`'s own prose, not
just the SUMMARY) that "committing this report adds no identifier the repository did not already
hold" — that specific claim is TRUE, verified directly, not merely asserted.

**3. Accurate scope of the accepted risk, as it should be recorded:** the repository has held a
real device's UDID-format identifier, serial number, and an account-identifying display name in a
committed, `git`-tracked file since 2026-06-21 (Phase 5), and Phase 9 added a second file with the
identical identifiers rather than a new exposure. `git remote -v` shows this repository points at
`https://github.com/D0NMEGA/Cortex.git`, and the project's own `AGENTS.md` states its purpose is "a
credibility-grade demonstration... suitable for review by Bliss Chapman / Nir Even-Chen" — i.e. this
repository is meant to be read by people outside the user's own control, which makes this a live
disclosure surface rather than a hypothetical one. `09-HUMAN-UAT.md` and
`deferred-items-09-11.md` item 3 already both say, in the executor's own words, that "if this
repository is ever published for review, the two files have to be scrubbed together or not at all"
— the gap is self-identified and logged, but not remediated, and the registered accept-rationale in
`09-11-PLAN.md`'s threat table does not mention it.

**Disposition kept as `accept`, per the plan (not silently changed)**; marked **open** because the
registered rationale, taken at face value, is not evidence for the risk actually being accepted —
it is evidence for a narrower risk (the transcription step) that was never the only exposure. The
underlying exposure is not new and not escalating (byte-identical to a ten-week-old committed file),
so this is a documentation-completeness gap, not a fresh vulnerability.

**Recommended next step (not applied — implementation/planning files are read-only to this audit):**
either (a) widen T-09-11-05's rationale in a future plan revision to explicitly cover the raw
Xcode-report commit and its three identifier fields, accepting that risk with eyes open, or (b) act
on `deferred-items-09-11.md` item 3 and scrub `deviceID`/`serialNumber`/`displayName` from both
`05-perf-report-ipad-m2.json` and `09-perf-report-ipad-m2.json` together before any public sharing
of this repository.

## Unregistered Flags

| Flag | File | Maps to a registered threat? | Notes |
|------|------|-------------------------------|-------|
| `threat_flag: deserialization` (`09-07-SUMMARY.md`) | `Decoder/scripts/fit_velocity_real.py:387-400` (`_load_cached_rates`) | No — none of T-09-07-01..07 covers the rates cache; the closest, T-09-07-06, is specifically about torch checkpoint pickle deserialization, a different file and mechanism. | New file-access pattern (`np.load` on a locally-produced `.npy` cache under gitignored `Decoder/checkpoints/09-07-rates/`), independently verified safe: grepped the repo for `allow_pickle` (zero matches), confirming `np.load(payload)` at line 400 uses the library default `allow_pickle=False` (numpy >=1.16.3; installed version confirmed `2.4.6`). The cache is also rejected outright on any mismatch of encoder sha256 / session sha256 / seq_len / bin count (`_cache_meta`, lines 377-384; `_load_cached_rates`, lines 397-399). Informational — not a blocker, and not something the register needed to anticipate at plan-authoring time since the cache did not exist until this plan wrote it. |

## Accepted Risks

The following 10 threats carry `disposition: accept` in their originating `PLAN.md`. Disposition
recorded exactly as written; none demoted from `mitigate` or invented. (Note: the task prompt's own
orientation summary stated "58 mitigate, 12 accept"; direct extraction of each `PLAN.md`'s
`<threat_model>` block — the ground truth this audit relies on, not the prompt's paraphrase — gives
60 mitigate / 10 accept across the 70 threats, matching the Threat Register table above exactly.)

| Threat ID | Plan | Accepted risk | Rationale (verbatim intent) | Verified consistent with implementation? |
|-----------|------|----------------|------------------------------|--------------------------------------------|
| T-09-01-04 | 09-01 | urllib streaming of a 1.135 GB file could be used for local disk-fill DoS | Streamed in 1 MiB chunks, constant memory; single-user on-device threat model excludes a hostile-Zenodo disk-fill scenario | Yes |
| T-09-01-05 | 09-01 | test module imports the script by absolute path | `importlib.util.spec_from_file_location` on a repo-relative path, no `sys.path` manipulation, no network | Yes |
| T-09-02-06 | 09-02 | committing a real dataset slice as a CI fixture (licensing/redistribution) | Fixture is wholly synthetic values inside a real HDF5 structure | Yes |
| T-09-03-06 | 09-03 | pathological array sizes in the pure-math kinematics layer | Single-user, on-device, arrays already bounded by the loader's validated shapes; no network/RPC surface | Yes |
| T-09-04-06 | 09-04 | loading a hostile `.mat` from the gitignored data dir | Single-user, on-device; `Decoder/data/` populated only via the checksum-pinned `download_indy.py` path; `load_session` reads only four validated fields | Yes |
| T-09-05-06 | 09-05 | Zenodo unavailable or rate-limiting the 1.38 GB fetch | No fallback exists; record verified reachable 2026-08-30, files immutable since 2020-05-26 | Plausible, not independently falsifiable without a live fetch (out of scope) |
| T-09-06-08 | 09-06 | the ~75 minute CPU training run exhausting the executor's budget | Measured cost documented up front; `--smoke` gives a cheap wiring check; kept out of CI entirely (D-21) | Yes, though the actual run cost grew beyond the original estimate across 09-06b/c/d — documented, not concealed |
| T-09-07-07 | 09-07 | running the encoder over ~285k bins of stride-1 windows | Inference-only, chunked (`EVAL_CHUNK=512`), a small fraction of the training step cost | Yes |
| T-09-08-08 | 09-08 | untested torch 2.12.1 / coremltools 9.0 pairing breaking `ct.convert` | Phase 5 shipped through the identical pairing; remedy named (pin torch, do not bump coremltools) | Yes, versions confirmed pinned in `uv.lock` |
| T-09-11-05 | 09-11 | a device capture leaking machine or account identifiers into a committed artifact | "Only the device model string, the pass count and the timing percentiles are transcribed; no serial number, UDID or account identifier is requested by the runbook" | **No — see Priority Finding / Open Threats above.** The rationale is accurate for the transcribed prose only; the raw committed report carries all three. Kept as the phase's disposition; recorded here with the corrected scope per this audit's mandate. |

Two `mitigate`-disposition items are closed with a caveat rather than cleanly, noted here because
they share the same "documented control not backed by a durable regression test" shape as the T-09-11-05
finding, at lower severity (no data is exposed; the risk is a possible silent future regression):

- **T-09-02-04** (`Decoder/src/ndt1/data.py:252-261`): the `finger_pos` shape/sample-count `ValueError` is real and correct, but unlike its sibling threats in the same plan, no test in `Decoder/tests/` names this exact negative-control path.
- **T-09-09-06** (`Tools/scripts/check_decoder_provenance.py:37-39`): the script is stdlib-only today (verified), but the plan's claimed enforcement mechanism ("asserted by a grep on its import list") does not exist anywhere in the repo.

## Bookkeeping findings (not threats)

- `09-01-SUMMARY.md`, `09-02-SUMMARY.md`, `09-03-SUMMARY.md`, `09-04-SUMMARY.md`: only `09-01` carries
  a Threat Flags section, and it uses the heading `## Threat flags` (lowercase "flags") rather than
  the `## Threat Flags` case used by every later summary in this phase (`09-05` onward). `09-02`,
  `09-03`, and `09-04` have no such section at all, under any casing (confirmed by case-insensitive
  search, not just the exact-case grep the task description used). None of the four plans' own threat
  registers were left unverified as a result — every `T-09-02-*`/`T-09-03-*`/`T-09-04-*` threat was
  independently confirmed against the implementation above — this is a documentation-consistency
  observation only.
- The full fast test suite (`pytest -m "not slow"`) passed 208/9-deselected at the time of this audit,
  matching the count recorded in `09-10-SUMMARY.md`'s own verification block, which is corroborating
  (not conclusive on its own, since suite size can coincidentally match) evidence that no test was
  quietly removed between that plan's execution and this audit.

Report: `.planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-SECURITY.md`

---

## Remediation 2026-09-02 (T-09-11-05)

The operator chose remediation over a widened accept-rationale. What was done:

| Step | Result |
|------|--------|
| Redact `deviceID` / `serialNumber` / `displayName` in `09-perf-report-ipad-m2.json` | done, replaced with `[redacted-*]` placeholders |
| Same three fields in `05-perf-report-ipad-m2.json` | done - the values were byte-identical, so scrubbing one alone would have left the exposure intact |
| Raw values quoted in `09-11-SUMMARY.md` (1 occurrence) and in this report (3) | done |
| Working-tree scan for the three literal values | zero occurrences remain |
| Measured data preserved | `deviceResults`, `modelMetadata`, `computeUnit` untouched; `modelName` "iPad Air 11-inch (M2)" and `osNameAndVersionWithoutBuildNumber` "iPadOS 18.7.8" retained, so the device-labeling discipline (D-17) still holds |

Context that shaped the choice: the repository is PRIVATE and `git ls-remote --heads origin` returns
nothing - the last push was 2026-06-19, two days BEFORE commit `b426467` introduced
`05-perf-report-ipad-m2.json`. Neither report has ever left the machine, so this was remediated
before any exposure occurred rather than after.

### Residual risk, stated plainly

The identifiers remain in local git history (from `b426467`, 2026-06-21). They were NOT removed by
rewriting history, and that was a deliberate call, not an oversight: rewriting would rewrite the 197
commits since `b426467`, and 196 of the 199 short commit SHAs cited across `.planning/` resolve to
real commits today. Every one of those citations would break, in a repo whose summaries self-verify
with lines like "Commit `774d3c6` FOUND". The evidence chain was judged worth more than removing
identifiers from an unpushed local history.

This means the residual risk is real but narrow: anyone who obtains the full repository with history
can still recover the three values. Before this repository is pushed, published, or handed to an
external reviewer, decide explicitly between (a) accepting that history, or (b) rewriting it and
re-anchoring the SHA citations. `deferred-items-09-11.md` item 3 remains the tracking entry.
