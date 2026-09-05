---
phase: 10
slug: v1-real-data-closed-loop-launch
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-09-05
---

# Phase 10 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `10-RESEARCH.md` "Validation Architecture" (line 1055). This is the **plan-time
> seed**: the per-task map below is populated with SC-level rows because task IDs do not exist
> until the planner runs. `/donny-validate-phase` reconciles it against reality after execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (Python)** | pytest 8.x, config in `Decoder/pyproject.toml` (`testpaths = ["tests"]`, marker `slow`) |
| **Framework (Swift)** | Swift Testing (`import Testing`, `@Test`/`#expect`), per-package `swift test` |
| **Config file** | `Decoder/pyproject.toml`; per-package `Package.swift` |
| **Env bootstrap (REQUIRED FIRST)** | `uv sync --project Decoder --extra dev` |
| **Quick run command** | `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` |
| **Full suite command** | `uv run --project Decoder pytest Decoder/tests -q` plus `swift test` on CortexReFIT / CortexDemo / CortexDecoder plus every `*-policy.sh` and its `--self-test` |
| **Estimated runtime** | ~30 s Python quick; ~2-4 min Swift packages plus gates |

**Tier split (Phase 9 D-21, carried forward, reinforced by D-07).** CI gates correctness, structure
and provenance. CI never trains, never downloads the dataset, never reads the D-06 export, and
never asserts a measured number against a bar. Every automated command below must run green on a
checkout with an empty `Decoder/data/` and no export present.

**Standing caveat, new this phase.** The CI workflow has never executed (RESEARCH Correction 3:
`gh api .../actions/runs` returns `total_count: 0`). Every "CI-blocking" row describes where an
assertion is wired, not a run that has happened. Phase evidence must record locally-captured
transcripts, and the README's present-tense "enforced as CI structural gates" claim is itself in
scope for the RD-09 sweep.

---

## Sampling Rate

- **After every task commit:** `uv sync --project Decoder --extra dev && uv run --project Decoder pytest Decoder/tests -m "not slow" -q`, plus `swift test --package-path Packages/CortexReFIT` when Swift changed.
- **After every plan wave:** quick Python suite + `swift test` on CortexReFIT / CortexDemo / CortexDecoder + every policy gate with its `--self-test`.
- **Before `/donny-verify-work`:** full suite green, byte-identity check on `refit_bps.json` still passing, every evidence artifact committed with its runbook and device label, ADR-0003 written and indexed.
- **Max feedback latency:** ~30 s (Python quick), ~4 min (full).

---

## Per-Task Verification Map

Reconciled against the plan set on 2026-09-05. 17 plans, 46 tasks, 14 waves; every task carries an
`<automated>` verify and every task carries `<read_first>` and `<acceptance_criteria>`. The Wave-0
column now names the plan that CREATES each missing artifact rather than a bare cross mark.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | Created by | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|------------|--------|
| 10-03 T1/T2 (SC#1a) | 10-03 | 1 | RD-07 | T-10-03-01 | Gains fit from real residuals, not defaults | unit | `swift test --package-path Packages/CortexReFIT` (KalmanConstantsTests asserts header `noise source = indy-heldout`) | 10-03 | ⬜ pending |
| 10-03 T2 (SC#1b) | 10-03 | 1 | RD-07 | T-10-03-03 | Re-fit gain Schur-stable, zero position rows preserved | unit | `swift test --package-path Packages/CortexReFIT` (existing invariants) | existing | ⬜ pending |
| 10-09 T1 (SC#1c) | 10-09 | 6 | RD-07 | T-10-09-01 | Real-data ablation artifact is provenance-bound; **no assertion on sign or magnitude (D-09)** | gate | `./Tools/scripts/refit-real-policy.sh && ./Tools/scripts/refit-real-policy.sh --self-test` | 10-09 | ⬜ pending |
| 10-09 T2 (SC#1d) | 10-09 | 6 | RD-07 | T-10-09-03 | Gain and smoothing reported per arm (Willett confound) | schema | `uv run --project Decoder pytest Decoder/tests/test_real_replay_schema.py -q` | 10-09 | ⬜ pending |
| 10-05 T1 (SC#1e) | 10-05 | 3 | RD-07 | T-10-05-01 | Synthetic Phase-7 invariant still guards filter code, immune to the re-fit | gate | byte-diff `refit_bps.json` after `--smoke`; `python3 Tools/scripts/check_refit_uplift.py` | existing | ⬜ pending |
| 10-13 T1 (SC#1f) | 10-13 | 9 | RD-07 | T-10-13-04 | Honest gap stated with each reference's measurement condition | gate | `./Tools/scripts/readme-policy.sh --self-test` | 10-13 | ⬜ pending |
| 10-07 T1/T2 (SC#1g) | 10-07 | 4 | RD-07 | T-10-07-01 | The measured four-arm real-data ablation numbers | evidence | human-run; `10-refit-real.json` schema-verified by 10-09 | 10-07 | ⬜ pending |
| 10-04 T2 (SC#2a) | 10-04 | 2 | RD-08 | T-10-04-03 | NDT1 genuinely in the loop; no silent decode fallback | unit | `swift test --package-path Packages/CortexDemo` (seqLen from source; modelBackedTicks; lastDecodeFailure) | 10-04 | ⬜ pending |
| 10-01 T3 + 10-08 T1 (SC#2b) | 10-01, 10-08 | 0, 5 | RD-08 | T-10-08-03 | A webgrid hit reported against the PRE-REGISTERED true-cursor ceiling | evidence | `10-ceiling.json` committed before any decoded run; `ceiling_hits` asserted equal in 10-09's gate | 10-01 | ⬜ pending |
| 10-09 T2 (SC#2c) | 10-09 | 6 | RD-08 | T-10-08-03 | Hit-independent proxy present so a zero is interpretable (D-11) | schema | `uv run --project Decoder pytest Decoder/tests/test_real_replay_schema.py -q` | 10-09 | ⬜ pending |
| 10-08 T1 (SC#2d) | 10-08 | 5 | RD-08 | T-10-08-05 | Seam A p99 like-for-like with Phase 8 (one variable changed) | evidence | `CortexDemoBench --real` at the unchanged Phase-8 geometry | 10-04 | ⬜ pending |
| 10-06 T3 (SC#2e) | 10-06 | 4 | RD-08 | T-10-06-01 | Seam B decrypts, decodes and orders every frame; fails closed on tamper | smoke | `swift run --package-path Packages/CortexDemo CortexSeamBSmoke` (exit 0 skip when export absent); `--tamper` exits non-zero | 10-06 | ⬜ pending |
| 10-09 T2 (SC#2f) | 10-09 | 6 | RD-08 | T-10-08-01 | Two seams distinctly labeled; Seam B not presented as the Phase-8 number | schema | `uv run --project Decoder pytest Decoder/tests/test_real_replay_schema.py -q` | 10-09 | ⬜ pending |
| 10-14 T1 (SC#3a) | 10-14 | 10 | RD-09 | T-10-14-01 | No synthetic-derived number presented as a real-data result | gate | `./Tools/scripts/honesty-sweep.sh && ./Tools/scripts/honesty-sweep.sh --self-test` | 10-14 | ⬜ pending |
| 10-12 T3 + 10-14 T1 (SC#3b) | 10-12, 10-14 | 8, 10 | RD-09 | T-10-14-02 | Superseded evidence carries a forward banner | gate | `./Tools/scripts/honesty-sweep.sh` | 10-14 | ⬜ pending |
| 10-11 T1 (SC#3c) | 10-11 | 7 | RD-09 | T-10-11-04 | Methodology label no longer names photodiode as a scheduled phase; prefix pinned | unit | `swift test --package-path Packages/CortexDemo` (GlassToGlassTimerTests verbatim + hasPrefix) | existing | ⬜ pending |
| 10-13 T1 (SC#4a) | 10-13 | 9 | RD-10 | T-10-13-01 | `photodiode` / flat `24.7` no longer required | gate | `./Tools/scripts/readme-policy.sh --self-test` | 10-13 | ⬜ pending |
| 10-13 T1 (SC#4b) | 10-13 | 9 | RD-10 | T-10-13-02, T-10-13-03 | Retired-context `24.7` passes; achieved-context `24.7` fails | gate | `./Tools/scripts/readme-policy.sh --self-test` (cases 1f and 1g) | 10-13 | ⬜ pending |
| 10-13 T1 (SC#4c) | 10-13 | 9 | RD-10 | T-10-13-04 | D-14 provenance triple required, three strip controls | gate | `./Tools/scripts/readme-policy.sh --self-test` | 10-13 | ⬜ pending |
| 10-13 T1 (SC#4d) | 10-13 | 9 | RD-10 | T-10-13-01 | Every pre-existing control still bites; count 9 -> >= 14 | gate | `./Tools/scripts/readme-policy.sh --self-test 2>&1 \| grep -c 'PASS \['` >= 14 | 10-13 | ⬜ pending |
| 10-14 T1 (SC#5a) | 10-14 | 10 | RD-10 | T-10-14-03 | LAT-01..LAT-08 preserved verbatim in ROADMAP and REQUIREMENTS | gate | `./Tools/scripts/honesty-sweep.sh` | 10-14 | ⬜ pending |
| 10-13 T2 + 10-14 T1 (SC#5b) | 10-13, 10-14 | 9, 10 | RD-10 | T-10-14-04 | ADR-0003 exists, four headings, Status line, indexed | gate | `./Tools/scripts/honesty-sweep.sh` | 10-13 | ⬜ pending |
| 10-12 T1 (SC#5c) | 10-12 | 8 | RD-10 | T-10-12-02 | Honest-gates table reflects the new boundary | gate | `./Tools/scripts/readme-policy.sh --self-test` | 10-12 | ⬜ pending |
| 10-15 T1 (D-18) | 10-15 | 11 | RD-09 | T-10-15-01 | Lint toolchain version drift fails loudly | gate | `./Tools/scripts/toolchain-policy.sh && ./Tools/scripts/toolchain-policy.sh --self-test` | 10-15 | ⬜ pending |
| 10-15 T3 (D-18) | 10-15 | 11 | RD-09 | T-10-15-02 | `swiftformat --lint .` clean, no gate disarmed | gate | `swiftformat --lint .` plus the eleven policy gates and their self-tests | existing | ⬜ pending |
| 10-16 T2 (D-18) | 10-16 | 12 | RD-09 | T-10-16-01 | `identifier_name` clear with every JSON key byte-identical | gate | `swiftlint --strict`; byte-diff `refit_bps.json` and `webgrid_bps.json` | existing | ⬜ pending |
| 10-17 T1/T3 (D-18) | 10-17 | 13 | RD-09 | T-10-17-01, T-10-17-05 | Nothing secret or licence-encumbered is published; the CI claim matches the real run | gate + evidence | pre-push audit greps; `gh api .../actions/runs`; `./Tools/scripts/readme-policy.sh --self-test` | 10-17 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Test infrastructure exists on both sides. The gaps are fixtures, gates, and one missing seam.

- [ ] (Plan 10-09) `Tools/scripts/refit-real-policy.sh` + `--self-test` (5 controls), structurally copied from `decoder-policy.sh` - SC#1c, SC#1d
- [ ] (Plan 10-14) `Tools/scripts/honesty-sweep.sh` + `--self-test` - SC#3a, SC#3b, SC#5a, SC#5b
- [ ] (Plan 10-09) `Decoder/tests/test_real_replay_schema.py`, copying `test_metrics_schema.py`'s guard-split-marker self-check verbatim so the module cannot grow a measured-value assertion - SC#1d, SC#2c, SC#2f
- [ ] (Plan 10-02) A committed **synthetic** export fixture (few hundred bins, correct dtypes + sidecar) so the Swift reader and schema test run on a clean clone with no dataset. The D-20 `tiny_v73.mat` pattern applied to the export. **Without it every export-touching test is dataset-gated and CI covers none of it.**
- [ ] (Plan 10-06) The rolling 32-bin window accumulator between the IPC consumer and `SpikeInputBuffer`, with its own unit test
- [ ] (Plan 10-13) `readme-policy.sh`'s new `require_marker_on_matching_lines` helper + 5 new self-test cases + updated `write_clean_readme`
- [ ] (Plan 10-09 + 10-14) Three new `ci.yml` steps: real-data provenance gate, honesty sweep, Seam B smoke - each with its `--self-test` alongside, matching the existing seven policy-gate steps
- [ ] (Plan 10-10) `10-HUMAN-UAT.md` from the `09-HUMAN-UAT.md` template, for the iPad-M4 rows carried forward
- [ ] (Plan 10-01) The committed true-cursor ceiling script, run and its number published **before** the decoded run is scored

---

## Manual-Only Verifications

CI never touches the dataset (D-07, D-21). Every row below is human-run runbook evidence, not a
coverage gap.

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Kalman R fit from real residuals | RD-07 | Needs the 1.77 GB dataset and an encoder forward pass | `uv sync --project Decoder --extra dev`; materialize data; run the fit; commit regenerated `KalmanConstants.swift` + residual statistics into `10-refit-real-evidence.md` |
| Every real-data ablation number | RD-07 | Needs the export; D-09 forbids asserting result direction anywhere | Run the four arms; transcribe into the evidence artifact and metrics JSON |
| True-cursor webgrid ceiling | RD-08 | Reads `Decoder/data/*.mat` directly | Run the committed ceiling script; commit its output **before** the decoded run |
| Webgrid hit demonstration + recorded capture (D-16) | RD-08 | Needs a GUI session on the M5 Pro and the free-team GUI signing path | Run CortexMac from Xcode with `MTL_HUD_ENABLED=1`; capture recording; store as RD-08 evidence |
| Seam A and Seam B p99 | RD-08 | Latency values are never asserted against a bar in CI | `CortexDemoBench --full` with export and model wired; device-annotate as corroborating |
| iPad Pro M4 canonical captures (6 gates: Phase-8 latency, TestFlight, HID registration, Phase-9 decoder p99, Phase-10 Seam A p99, Phase-10 webgrid demo) | RD-08, RD-10 | Hardware absent / enrollment absent / entitlement request-gated | `10-HUMAN-UAT.md` (Plan 10-10), **never auto-approved**, all value fields `not measured` |
| M5-Pro recorded demo capture (D-16) | RD-08 | Needs a GUI session on the free Personal team | Plan 10-10 Task 2; `10-demo-capture-evidence.md` |
| "CI is green" | all | The workflow has never run | Capture local transcripts of every gate + `--self-test`; state in README that the workflow has not yet executed on a runner |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (46/46 carry `<automated>`)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (see the Wave 0 Requirements list below; every item is owned by a named plan)
- [x] No watch-mode flags
- [x] Feedback latency < 30s (quick) / < 4min (full)
- [x] Every new gate ships its `--self-test` in the same commit (refit-real, honesty-sweep, toolchain, and the readme-policy rewrite)
- [x] No gate asserts the sign or magnitude of a real-data result (D-09; enforced by a marker comment plus an acceptance grep in 10-09 and 10-14)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planner-reconciled 2026-09-05 against the 17-plan set. Execution status stays `pending` until `/donny-validate-phase` runs post-execution.
