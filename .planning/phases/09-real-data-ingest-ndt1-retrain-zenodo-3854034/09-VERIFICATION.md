---
status: PARTIAL
agent: donny-verifier
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
verified: 2026-09-03T04:00:52Z
verdict: human_needed
score: 5/5 roadmap success criteria verified
human_verification:
  - test: "Capture the canonical iPad Pro M4 p99 latency for the real-data with-velocity decoder (RD-06b). Runbook is verbatim in 09-HUMAN-UAT.md: rebuild `ndt1_real_vel_fp16.mlpackage` / `ndt1_real_vel_4bit.mlpackage` from the real checkpoints, pair a provisioned iPad Pro M4 (iPadOS 26) in Xcode 26.3, build-and-run CortexDecoderBench from the Xcode GUI (the free Personal team `57YW6M29S7` signs GUI-only), and transcribe p50/p99/n/deviceAnnotation/MLComputePlan preferred-device tally back into 09-coreml-evidence.md and 09-decoder-metrics.json."
    expected: "A canonical iPad-Pro-M4 p50/p99 latency and a measured preferred-compute-device tally are recorded, whatever they come out as (including a CPU-placed or unremarkable result, per D-25). The existing M5 Pro (0.141083 ms p99) and iPad Air M2 (0.5790 ms p99) rows stay untouched and byte-identical; the new row is added beside them, labeled canonical, never merged into or replacing the corroborating rows."
    why_human: "Requires a physical iPad Pro M4 running iPadOS 26, paired and trusted in Xcode, and a GUI-driven build-and-run because the project's only local signing identity is a free Apple Developer Personal team that cannot provision a device from the command line. No CI runner or dev-Mac substitute exists for on-device Neural Engine placement, which is precisely the property this gate exists to measure. Per project policy (D-17) this gate is never auto-approved even under `workflow.auto_advance: true`; 09-HUMAN-UAT.md and 09-11-SUMMARY.md both record this hardware as NOT AVAILABLE today, so the gate is correctly DEFERRED rather than fabricated. RD-06's own executor (Plan 09-11) left `requirements-completed: []` for exactly this reason: \"Marking RD-06 complete would assert a device measurement nobody took.\""
---

# Phase 9: Real-Data Ingest & NDT1 Retrain (Zenodo 3854034) Verification Report

**Phase Goal:** The four curated Indy M1-only sessions physically exist under `Decoder/data/`, are
SHA-256-pinned in the committed manifest, and every decoder number the repo publishes is re-derived
on real primate M1 spikes instead of the synthetic Poisson fallback, up to and including the
`.mlpackage` that ships. The decoder stops being a model that was only ever shown structured noise.

**Verified:** 2026-09-03T04:00:52Z
**Status:** PARTIAL  **Verdict:** human_needed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

Truths are the five ROADMAP.md Success Criteria for this phase (the roadmap contract), each
cross-checked against the actual codebase rather than accepted from the roadmap's own annotations.

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Manifest is corrected to the four real Indy M1-only sessions, zero `"PENDING"` sha256, integrity gate proven to bite on a corrupted file | [OK] VERIFIED | `Decoder/manifests/indy_sessions.json` has 4 sessions, `grep -c PENDING` = 0. Sizes sum to exactly 1,767,820,363 B (143,970,619 + 1,135,050,817 + 382,243,800 + 106,555,127), matching `09-ingest-evidence.md` and the orchestrator's independent sha256 recompute of `indy_20160630_01`. `decoder-policy.sh` (live run) confirms zero PENDING and checksum agreement with `09-decoder-metrics.json`. |
| 2 | `ndt1.data.load_session` ingests all four real sessions end to end: 96-channel gate, correct cell-array deref, plausible firing-rate band | [OK] VERIFIED | Code read: `Decoder/src/ndt1/data.py` discriminates empty MATLAB cells via `"MATLAB_empty" in dataset.attrs` (not truthy-ref), names `chan_names`-derived width in its `ValueError`, and extracts the planar pair as `finger[1:3, :]` (rows 1-2, not 0-1) with a code comment citing the measured `corr(cursor_pos[0], finger_pos[1]) == -1.0000` check. `Decoder/src/ndt1/qc.py` implements the population firing-rate band (`firing_rate_stats`, `PLAUSIBLE_BAND`). 285,359 total 20 ms bins over 5,707.2 s reported and reproduced in `09-ingest-evidence.md` / `09-training-evidence.md`. |
| 3 | Real-data held-out co-bps beats the mean-rate null by a documented margin, replacing synthetic 0.3804 | [OK] VERIFIED | `09-decoder-metrics.json`: pooled co-bps 0.40956884089908474 (train_null) / 0.3814331158199826 (test_mean_null), `CO_BPS_MARGIN=0.054` with `margin_rationale`. Checkpoint `ndt1_real_pooled.pt` on disk hashes to `f95b257bf2479b49102a2d8afee3c46d9008c51ba754d42a60a26762b7d3af8e`, an exact match to the sha256 recorded in the metrics JSON and `09-training-evidence.md` -- the published number is demonstrably measured from the checkpoint that exists on disk, not asserted. `Decoder/src/ndt1/train.py::masked_forward` + `Decoder/src/ndt1/loss.py::hide_scored_positions` genuinely corrupt the encoder input at scored positions (see Key Link Verification and Anti-Patterns below); `Decoder/tests/test_masked_input_isolation.py` (5/5 passed, live run) discriminates this by perturbation, not by source grep. `test_cobps_margin.py` (part of the 208-test quick suite, live run) holds the 4-link supersession chain and the margin in place. |
| 4 | Multi-session generalization reported (per-session + LOSO), not assumed | [OK] VERIFIED | `09-decoder-metrics.json.loso` carries 4 folds, each session held out exactly once (`test_metrics_schema.py::test_loso_is_a_full_rotation`, live-passing). Reported honestly as a split rather than a single number: within-session 4/4 positive (+0.2127, +0.1661, +0.2062, +0.2455); leave-one-session-out 4/4 **negative** against the held-out session's own mean (-0.1238, -0.3060, -0.7805, -0.1890, mean -0.3498). `09-training-evidence.md`, `PROJECT.md` and `ROADMAP.md` all state plainly "the encoder does not transfer to an unseen session" -- no summary line found anywhere claiming cross-session generalization. |
| 5 | 4-bit palettization delta + ANE eligibility re-measured on the real-data checkpoint; decoder p99 stays under 2 ms with real weights | [OK] VERIFIED | `09-decoder-metrics.json.ane`: `n_schedulable=239`, `all_eligible=true`, `cpu_only_ops=0`, `provenance` names the real checkpoint sha256, matching the file on disk. Checkpoint `ndt1_real_with_velocity.pt` hashes to `9d542cb51d4af4811f324fbc6bda0b503da7b15aafc98b5e1340e1a7f49cce65`, an exact match. `latency.p99_ms=0.141083` (M5 Pro, CPU-placed, labeled `corroborating`), well under the 2 ms budget; independently reproduced at p99 0.5790 ms on an iPad Air M2 (`09-perf-report-ipad-m2.json`), also under budget. 4-bit per-tensor destroys the velocity R2 (+0.423870 -> -1.786971); `09-coreml-evidence.md` recommends shipping fp16 instead, and no code or evidence presents the broken 4-bit number as the shipping choice. |

**Score:** 5/5 truths verified. A sixth item -- the canonical iPad-Pro-M4 p99 capture that would additionally strengthen truth 5 -- is not a written roadmap success criterion, but it is RD-06's own device gate and is routed to Human Verification Required below rather than silently counted as done.

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `Decoder/manifests/indy_sessions.json` | 4 sessions, zero PENDING, size_bytes+zenodo_md5 | [OK] VERIFIED | Confirmed live: 0 PENDING, sizes match `09-ingest-evidence.md` exactly |
| `Decoder/scripts/download_indy.py` | Magic-byte/size/md5 pre-checks before sha256 | [OK] VERIFIED | `_process_session` / `_check_payload` present per `09-01-SUMMARY.md`; integrity tests pass |
| `Decoder/tests/test_download_integrity.py` | Hermetic negative controls | [OK] VERIFIED | Part of 208-test quick suite (live, all passed) |
| `Decoder/tests/fixtures/tiny_v73.mat` | Committed v7.3 HDF5 fixture, tracked despite `.mat` ignore rule | [OK] VERIFIED | `git ls-files` context from PLAN/SUMMARY; fixture-driven tests pass live |
| `Decoder/src/ndt1/data.py` | `MATLAB_empty` guard, width-message fix, `finger_pos[1:3]` extraction | [OK] VERIFIED | Read directly; all three fixes present and commented with rationale |
| `Decoder/src/ndt1/kinematics.py` | `planar_velocity_250hz`, `bin_velocity`, `apply_lag`, `heldout_r2` | [OK] VERIFIED | Exports consumed by `fit_velocity_real.py`; velocity evidence reproduces to 4 decimal places against an independent CoreML re-scoring |
| `Decoder/src/ndt1/qc.py`, `Decoder/src/ndt1/sessions.py` | Firing-rate band, `available_sessions`/`pooled_splits`/`loso_folds` | [OK] VERIFIED | `grep` confirms all three session functions defined; consumed by `train_real.py` |
| `Decoder/scripts/train_real.py` | Pooled retrain + per-session co-bps + LOSO + metrics writer | [OK] VERIFIED | Produced the committed `09-decoder-metrics.json`; checkpoint hash on disk matches |
| `Decoder/src/ndt1/train.py` | `masked_forward` hides scored positions in BOTH train and eval paths | [OK] VERIFIED | Read directly (lines 90-112, 320-339): both `train_ndt1`'s loop and `evaluate_co_bps` call the same `masked_forward` |
| `Decoder/src/ndt1/loss.py` | `hide_scored_positions`, `stable_exp` / `LOG_RATE_LINEARIZE_ABOVE` | [OK] VERIFIED | Read directly; zeroing implementation and the linearized-exp numerical guard both present with documented rationale |
| `Decoder/tests/test_masked_input_isolation.py` | Perturbation-based regression test, discriminates by construction | [OK] VERIFIED | Read + run live: 5/5 passed. Perturbs scored-position counts and asserts bit-identical predictions; a second test asserts unmasked-context perturbation DOES move predictions (anti-degenerate control) |
| `Decoder/tests/test_loss_stability.py` | Proves the numerical guard is bit-identical below threshold | [OK] VERIFIED | Read + run live: 11/11 (folded into the 44-test targeted run). Includes a `torch.clamp`-would-be-wrong-signed control |
| `Decoder/scripts/fit_velocity_real.py` | Lag sweep, lambda sweep, ridge fit, held-out R2, with-velocity checkpoint | [OK] VERIFIED | Produced `ndt1_real_with_velocity.pt` (hash matches on disk); `09-velocity-evidence.md` numbers reproduce in CoreML to 4 decimals |
| `Decoder/src/ndt1/real_checkpoint.py` | `load_real_weights_if_present` returns a provenance label | [OK] VERIFIED | Cited and exercised by `rederive_coreml.py`; provenance strings appear verbatim in `09-decoder-metrics.json` |
| `Decoder/scripts/rederive_coreml.py` | Converts + palettizes both models, scans ANE, writes metrics | [OK] VERIFIED | Its outputs (`ane`, `palettization`, `latency` sections) are present and internally consistent in `09-decoder-metrics.json` |
| `Tools/scripts/decoder-policy.sh` | D-19 provenance gate + `--self-test` | [OK] VERIFIED | Ran live against the real repo state: clean pass. `--self-test` ran live: 4/4 cases pass (clean tree, PENDING reintroduction, data_source strip, checksum perturbation) |
| `Tools/scripts/check_decoder_provenance.py` | stdlib-only checksum set comparison | [OK] VERIFIED | Invoked by `decoder-policy.sh`, confirmed via live run output |
| `Decoder/tests/test_metrics_schema.py` | Shape/provenance gates, including the D-17 canonical-device-labeling rule | [OK] VERIFIED | Read directly; `test_latency_is_device_labeled_and_corroborating` structurally forbids a non-iPad device from being labeled anything but `corroborating`. Part of the 208-test quick suite |
| `.github/workflows/ci.yml` (`decoder-python` job) | Blocking CI: sync, ruff, quick suite, no-dataset proof, policy gate + self-test | [OK] VERIFIED | Read directly; triggers on `push`/`pull_request` to `main`; all 5 steps present in order |
| `09-decoder-metrics.json` | Provenance-bearing metrics with 3 `superseded_*` blocks + published run | [OK] VERIFIED | `superseded_visible_input_objective`, `superseded_truncated_budget`, `superseded_rule_stopped_at_floor` all present with `superseded_by` forward pointers; none deleted; top-level `co_bps`/`loso`/`velocity`/`ane`/`latency`/`palettization` sections all populated |
| `09-training-evidence.md`, `09-velocity-evidence.md`, `09-coreml-evidence.md`, `09-ingest-evidence.md` | RD-01/02/03/04/05/06 evidence with full methodology | [OK] VERIFIED | All four read in full; numbers cross-checked against the live JSON and live checkpoint hashes; no contradictions found |
| `09-HUMAN-UAT.md` | RD-06b device-gated runbook, never-auto-approve, honest deferral | [OK] VERIFIED | Read in full; disposition table has the canonical row reading `not measured` in every field, and the corroborating M2/M5 rows populated and cross-referenced |
| Phase-4/5 superseded banners (`04-training-evidence.md`, `04-palettization-evidence.md`, `05-velocity-head-evidence.md`) | Banner naming the Phase-9 replacement, measured content unchanged | [OK] VERIFIED | `grep -n SUPERSEDED` confirms banners present in all three; `git diff --numstat` style preservation claimed in `09-10-SUMMARY.md` is consistent with the artifacts as read |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `download_indy.py` | `indy_sessions.json` | `session['size_bytes']`/`['zenodo_md5']` read in `_process_session` | WIRED | Manifest fields present and consumed; live fetch already materialized 1.77 GB matching the pins |
| `train.py::train_ndt1` (loop) | `loss.py::hide_scored_positions` | `masked_forward(model, targets, mask)` | WIRED | Read directly; both the training loop's per-batch call and `evaluate_co_bps` route through the same function |
| `train.py::evaluate_co_bps` | `loss.py::hide_scored_positions` | same `masked_forward` call | WIRED | Confirmed identical code path -- this is the exact link the phase's four-iteration correction chain exists to guarantee |
| `test_masked_input_isolation.py` | `train.py`/`loss.py` | perturbation probe on `masked_forward`'s recorded encoder inputs | WIRED, DISCRIMINATING | Live run 5/5 passed; the test records what the encoder actually saw (via a wrapping `_RecordingModel`) rather than grepping source, so a fix applied to one call site and not the other would fail it |
| `train_real.py` | `sessions.py` | `available_sessions` + `pooled_splits` + `loso_folds` | WIRED | Confirmed by grep and by the committed metrics JSON's `sessions`/`loso` sections matching the D-12 per-session-then-pool split discipline |
| `09-decoder-metrics.json` | `indy_sessions.json` | `sessions[].sha256` copied from manifest at run time | WIRED | `decoder-policy.sh` live run: "4 session(s) agree on id and sha256... OK" |
| `fit_velocity_real.py` | `kinematics.py` | `planar_velocity_250hz -> bin_velocity -> apply_lag -> heldout_r2` | WIRED | `09-velocity-evidence.md` documents the refusal-to-start check (session/encoder hash mismatch aborts); output checkpoint hash matches disk |
| `rederive_coreml.py` | `real_checkpoint.py` | `load_real_weights_if_present` gates conversion | WIRED | `ane.provenance` and `latency.provenance` in the committed JSON both name the real checkpoint sha256, matching the file on disk exactly |
| `decoder-policy.sh` | `check_decoder_provenance.py` | bare `python3` invocation for checksum set comparison | WIRED | Live run shows the delegated comparison executing and reporting per-session agreement |
| `ci.yml` (`decoder-python`) | `decoder-policy.sh` + quick pytest | job steps in sequence | WIRED | Read directly: sync -> version print -> ruff -> quick suite -> empty-data-dir proof -> policy gate + self-test, in that order |
| `09-HUMAN-UAT.md` | `09-coreml-evidence.md` | corroborating Mac number cross-reference, both directions | WIRED | Both files cite the same p99 0.141083 ms figure and the same checkpoint sha256 |

### Data-Flow Trace (Level 4)

This is an ML evidence pipeline rather than a UI; "data flowing" here means every published number
traces to the real checkpoint bytes on disk rather than to a random-init stand-in or a hardcoded
value.

| Artifact | Data source | Produces real data | Status |
| --- | --- | --- | --- |
| `co_bps.pooled` / `co_bps.per_session` in `09-decoder-metrics.json` | `Decoder/checkpoints/ndt1_real_pooled.pt` | Checkpoint sha256 on disk (`f95b257b...`) matches the value recorded in the metrics JSON and in `09-training-evidence.md`, byte for byte | [OK] FLOWING |
| `velocity.heldout_r2` / `velocity.loso` | `Decoder/checkpoints/ndt1_real_with_velocity.pt` | Checkpoint sha256 on disk (`9d542cb5...`) matches the value recorded in the metrics JSON, and the CoreML-converted package independently reproduces the PyTorch R2 to 4 decimal places (`09-coreml-evidence.md`, "apparatus validated before the finding was read") | [OK] FLOWING |
| `ane.n_schedulable` / `ane.cpu_only_ops` | Compiled `.mlmodelc` of `ndt1_real_with_velocity.pt` | `provenance` field names the real checkpoint; an explicit attribution control (checkpoints moved aside, same code re-run) reproduces the untrained Phase-4/5 baseline exactly, proving the 226-to-239 delta is attributable to the weights, not to tooling drift | [OK] FLOWING |
| `latency.p99_ms` (M5 Pro) and the iPad Air M2 capture | Compiled 4-bit/fp16 `.mlpackage` built from the real checkpoint | `provenance` field names the real checkpoint sha256; the M2 capture is a raw, committed Xcode Performance Report (`09-perf-report-ipad-m2.json`), independently recomputed rather than transcribed | [OK] FLOWING |
| `decoder-policy.sh`'s checksum agreement check | `indy_sessions.json` <-> `09-decoder-metrics.json` | Live-run cross-check, not a static assertion: recomputes the set comparison against the files as they exist right now | [OK] FLOWING |
| Canonical iPad-Pro-M4 row (`latency.canonical`, `09-HUMAN-UAT.md` disposition table) | No source -- hardware absent | Every value field reads the literal string `not measured`; no number is present to trace | N/A -- correctly empty, not fabricated |

No hollow props or static fallbacks found: every "real" number checked resolves to a checkpoint whose
sha256 is independently verifiable on the machine that produced this report.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| Masking-fix regression discriminates | `pytest Decoder/tests/test_masked_input_isolation.py -q` | 5 passed | [OK] PASS |
| Loss-stability numerical guard is bit-identical below threshold | `pytest Decoder/tests/test_loss_stability.py -q` | 11 passed (part of 44/44 targeted run) | [OK] PASS |
| Margin re-derivation chain intact | `pytest Decoder/tests/test_cobps_margin.py -q` | passed (part of 44/44 targeted run) | [OK] PASS |
| Gradient clipping / plateau-stop machinery intact | `pytest Decoder/tests/test_grad_clipping.py Decoder/tests/test_plateau_stop.py -q` | passed (part of 44/44 targeted run) | [OK] PASS |
| Full quick decoder suite (CI-blocking tier) | `pytest Decoder/tests -m "not slow" -q` | 208 passed, 9 deselected in 4.88s | [OK] PASS |
| Lint gate | `ruff check Decoder` | All checks passed | [OK] PASS |
| Provenance gate against the live repo state | `Tools/scripts/decoder-policy.sh` | "decoder policy clean", exit 0 | [OK] PASS |
| Provenance gate self-test (4 negative controls) | `Tools/scripts/decoder-policy.sh --self-test` | 4/4 cases pass, exit 0 | [OK] PASS |
| README policy still requires the not-yet-retired photodiode/24.7 tokens (RD-10 is Phase 10's job, not Phase 9's) | `Tools/scripts/readme-policy.sh` / `--self-test` | clean pass; self-test 9/9 negative controls bite | [OK] PASS |
| Checkpoint provenance matches disk | `shasum -a 256 Decoder/checkpoints/ndt1_real_pooled.pt Decoder/checkpoints/ndt1_real_with_velocity.pt` | `f95b257bf2479b49...` and `9d542cb51d4af481...` -- exact match to every evidence document's cited hash | [OK] PASS |
| Manifest has zero PENDING entries | `grep -c PENDING Decoder/manifests/indy_sessions.json` | 0 | [OK] PASS |
| Committed slow co-bps gate (`@pytest.mark.slow`, non-CI-blocking by design) | `pytest Decoder/tests/test_heldout_cobps.py -m slow -q` | **CONFIRMED live during this verification**: `1 passed in 856.76s (0:14:16)`. The freshly written `Decoder/checkpoints/sc2_metrics.json` reads `held_out_co_bps: 0.6797322079523844` with a byte-identical per-epoch loss trajectory to the pre-existing artifact and to `deferred-items-09-09.md`'s documented 0.679732 -- a deterministic (`seed=0`) reproduction on real session data, run end-to-end on this machine during this verification, not merely a pre-existing artifact read. | [OK] PASS (live re-run, confirmed) |

**Note on the slow co-bps gate.** This test is `@pytest.mark.slow`, explicitly excluded from the
blocking `decoder-python` CI job by design (D-21: CI never trains). It is not the phase's headline
number -- that is `train_real.py`'s output, independently verified above via checkpoint-hash match --
it is a Phase-4-era regression smoke test whose own docstring only claims "converges to non-trivial
reconstruction loss." `deferred-items-09-09.md` documents it passing at HEAD with co-bps 0.679732 on
2026-09-02, and explicitly cautions that this number is NOT comparable to the headline 0.4096 (weaker,
non-D-12 split) and must not be quoted as a result. A live re-run was executed end-to-end during this
verification (started before the Requirements Coverage section was drafted, finished 14m16s later) and
reproduced `held_out_co_bps=0.6797322079523844` and the identical loss trajectory exactly, confirming
the claim by direct measurement rather than by reading a pre-existing artifact alone.

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
| --- | --- | --- | --- | --- |
| RD-01 | 09-01, 09-05, 09-09 | Four Indy M1-only sessions downloaded, SHA-256-pinned, integrity gate proven | [OK] SATISFIED | Manifest zero-PENDING (live-checked), 1,767,820,363 B total, `decoder-policy.sh` live pass, `09-ingest-evidence.md` |
| RD-02 | 09-02, 09-03, 09-04, 09-06, 09-07 | Real-session ingest correctness: cell-array deref, channel-width message, kinematics extraction | [OK] SATISFIED | `data.py`/`kinematics.py`/`qc.py`/`sessions.py` read directly; fixture-pinned tests pass live |
| RD-03 | 09-06 (+06b/c/d), 09-09, 09-10 | Real-data co-bps beats null, replaces synthetic 0.3804 | [OK] SATISFIED | 0.4096/0.3814 in committed JSON, checkpoint hash matches disk, 4-link supersession chain intact, Phase-4 artifact bannered |
| RD-04 | 09-06 (+06b/c/d), 09-09 | Multi-session generalization reported (per-session + LOSO) | [OK] SATISFIED | Full 4-fold rotation, honestly negative, reported not glossed; `test_loso_is_a_full_rotation` passes live |
| RD-05 | 09-08, 09-09, 09-10 | 4-bit palettization delta re-measured on real checkpoint | [OK] SATISFIED | Both models measured, R2 collapse found and reported, "ship fp16" recommendation on record, checkpoint hash matches disk |
| RD-06 | 09-07, 09-08, 09-09, 09-11 | Real-data `.mlpackage` re-conversion; ANE eligibility + <2ms p99 re-verified with real weights | [!] PARTIAL -- see split below | ANE eligibility (239/239, 0 CPU-only) and corroborating latency (M5 Pro + iPad Air M2) are SATISFIED and independently checkpoint-hash-verified. The canonical iPad-Pro-M4 capture is NOT done; it is an explicitly deferred, never-auto-approved hardware gate. Plan 09-11 itself records `requirements-completed: []` for exactly this reason ("Marking RD-06 complete would assert a device measurement nobody took") |

No orphaned requirements: the union of every plan's `requirements` frontmatter field
(`{RD-01..RD-06}`) matches exactly the six requirement IDs the orchestrator specified and exactly the
six rows REQUIREMENTS.md's traceability table maps to Phase 9. RD-07..RD-10 are correctly left to
Phase 10 in both REQUIREMENTS.md and ROADMAP.md; none of the eleven plans in this phase claims them.

### Deferred Items

Items not yet closed but explicitly scoped to Phase 10 by this phase's own decisions (D-24), with
matching Phase-10 roadmap success criteria.

| # | Item | Addressed In | Evidence |
| --- | --- | --- | --- |
| 1 | `README.md` (2 places), `ADR-0002`, `05-ane-eligibility-evidence.md` (7 places), `05-latency-evidence.md` still cite the stale 226/226 op tally and unlabeled synthetic BPS figures | Phase 10 (RD-09) | ROADMAP Phase 10 SC#3: "A repo-wide sweep leaves no synthetic-derived number presented as a real-data result: README, ADRs, and every `*-evidence.md` either carry the re-derived real-data number or explicitly label the number synthetic." `deferred-items-09-10.md` items 1-4 name these exact files and defer them to RD-09 by name |
| 2 | `Tools/scripts/readme-policy.sh` still REQUIRES the literal tokens `photodiode` and `24.7` | Phase 10 (RD-10) | ROADMAP Phase 10 SC#4: "`readme-policy.sh` is rewritten, not deleted: its required-disclosure set drops `photodiode`/`24.7`... Its negative-control `--self-test` is updated in lockstep." `deferred-items-09-10.md` item 7 confirms this was deliberately left untouched and still green |

Not deferred to a later phase (no roadmap evidence supports it, so these remain open backlog rather
than scheduled work): more sessions, session-conditioning, error bars / bootstrap intervals on any
co-bps or R2, a full-budget (200-epoch) LOSO rotation, and refitting the velocity readout on
palettized-encoder output. These are honestly recorded in `deferred-items-09-06d.md` and
`deferred-items-09-07.md`/`09-08.md` as backlog, not claimed as blocking this phase's goal, and not
claimed as scheduled for Phase 10 either.

### Anti-Patterns Found

No blockers found. Two informational notes, neither of which misrepresents a number or hides a
defect.

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| `09-training-evidence.md` | "Gaps" item 11 | States the committed slow gate is "still RED, and was not run under this plan" | [i] Info | Stale relative to the later, more authoritative `deferred-items-09-09.md`, which documents the gate running GREEN (0.679732) after Plan 09-09. Both documents are internally dated and the later one is clearly the current record; this is a documentation-freshness lag inside the same phase, not a fabricated or contradicted number. Does not affect any committed metric. |
| `09-velocity-evidence.md` (line 69) / `Decoder/scripts/fit_velocity_real.py` (line 13) | n/a | Attribute the superseded 0.99985 self-consistency number to the wrong test file (`test_convert_velocity_output.py:55` instead of `test_velocity_head.py`) | [i] Info | Citation-only error, caught and documented by the phase's own `deferred-items-09-10.md` item 5. The substance (both tests build seeded-linear-map labels) is correct; only the file pointer is wrong. Does not affect any committed number. |

Explicitly checked and NOT found: no `TODO`/`FIXME`/`placeholder` markers in the phase's touched
source files; no synthetic-Poisson number presented as a real-data result anywhere in
`09-*-evidence.md`, `PROJECT.md`, or `ROADMAP.md`'s Phase-9 section; no Mac or iPad-M2 latency number
presented as an iPad-M4 number (the schema test `test_latency_is_device_labeled_and_corroborating`
makes this a structural CI-enforced impossibility, not just a convention); the canonical iPad-M4
latency row reads the literal string `not measured` in every field it has, exactly as the phase's own
honesty clause requires; no LOSO or cross-session result is described anywhere as "the model
generalizes" -- every occurrence found (PROJECT.md, ROADMAP.md, `09-training-evidence.md`,
`09-velocity-evidence.md`) states the opposite, explicitly.

### Human Verification Required

#### 1. Canonical iPad Pro M4 decoder p99 (RD-06b)

**Test:** Follow the verbatim runbook in `09-HUMAN-UAT.md`: rebuild the real-data `.mlpackage`
artifacts on the dev Mac (`Decoder/scripts/rederive_coreml.py`), pair a provisioned iPad Pro M4
(iPadOS 26) in Xcode 26.3, copy the package to the device, and build-and-run `CortexDecoderBench`
**from the Xcode GUI** (the free Personal team `57YW6M29S7` signs GUI-only; a command-line
`xcodebuild` cannot provision the device). Read the printed p50/p99/min/max/count/deviceAnnotation
block from the Xcode console, and capture an Instruments Core ML trace for the per-op compute-unit
lane.

**Expected:** A canonical iPad-Pro-M4 p50/p99 and a measured `MLComputePlan` preferred-device tally
are written into `09-coreml-evidence.md`'s "Latency with real weights (RD-06b)" table and into
`09-decoder-metrics.json.latency.canonical_capture`, beside (never replacing) the existing
corroborating M5 Pro and iPad Air M2 rows. Any result is acceptable to record, including a CPU-placed
or otherwise unremarkable one (D-25 forbids re-running until a flattering number appears).

**Why human:** Requires physical iPad Pro M4 hardware, which the project does not currently have
(the same gap that deferred three Phase-8 HUMAN-UAT gates and the Phase-6 renderer canonical
capture). GUI-only provisioning under a free-tier Apple Developer account cannot be scripted.
On-device Neural Engine placement is a chip-and-scheduler property that cannot be measured on the
dev Mac or in CI -- that is the entire reason this gate exists. Per D-17 this measurement is never
auto-approved by an agent even with `workflow.auto_advance: true`, and `09-HUMAN-UAT.md` /
`09-11-SUMMARY.md` both record it as correctly DEFERRED today rather than fabricated. This is
consistent with this donny-verifier's own rule that a pending hardware-measurement item keeps phase
status at PARTIAL regardless of how many other truths are verified.

### Gaps Summary

No gaps were found in the sense of a failed truth, a missing/stub artifact, an unwired key link, or a
blocking anti-pattern. Every one of the five ROADMAP.md success criteria for this phase is verified
against the actual codebase, not merely against the SUMMARY narrative: the manifest and its checksums
are correct and live-checked; the loader defect (truthy `MATLAB_empty` refs) is fixed and pinned by a
committed fixture; the masking defect that made every earlier co-bps in this phase a
self-reconstruction score is fixed in both the training loop and the evaluation path, and the fix is
held in place by a perturbation-based test that discriminates by construction rather than by source
grep (verified live: 5/5 pass); the numerical-stability guard that let the corrected objective survive
a real-data forward-pass overflow is proven bit-identical below its threshold (verified live: 11/11
pass); the four-link supersession chain in `09-decoder-metrics.json` is intact, with nothing deleted;
the leave-one-session-out result is honestly reported as negative on all four folds and is not
papered over anywhere it is cited; the velocity-readout cross-session rotation is likewise reported
honestly at 2-of-4 positive with median -0.4270; the 4-bit palettization collapse on the shipped
with-velocity model was found, measured, and resolved with a "ship fp16" recommendation rather than
hidden; and no synthetic number, and no Mac or iPad-M2 number, is presented anywhere as a real-data
or canonical-iPad-M4 result -- the latter is now a structural, CI-enforced impossibility via
`test_latency_is_device_labeled_and_corroborating`. Every checkpoint sha256 cited in the evidence
documents was independently reproduced from the actual `.pt` files on this machine's disk during this
verification.

The one open item is RD-06's canonical iPad-Pro-M4 p99 capture, which is a physical-hardware
measurement the project correctly and explicitly declined to fabricate. It is not a defect in this
phase's work; it is the honest, policy-mandated deferral of a gate that cannot be closed without
hardware the project does not have. Per this verifier's protocol, any outstanding human-verification
item holds the phase at PARTIAL (verdict `human_needed`) rather than PASS, independent of how the
rest of the phase scores -- and this matches the phase's own executor judgment (Plan 09-11 left
`requirements-completed: []` rather than claim RD-06 complete). Once a provisioned iPad Pro M4 becomes
available and the runbook in `09-HUMAN-UAT.md` is run, this phase can be re-verified to PASS without
any code change.

---

_Verified: 2026-09-03T04:00:52Z_
_Verifier: donny-verifier_
