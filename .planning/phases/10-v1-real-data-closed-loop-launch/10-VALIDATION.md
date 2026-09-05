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
| **Full suite command** | `uv run --project Decoder pytest Decoder/tests -q --deselect Decoder/tests/test_heldout_cobps.py` plus `swift test` on CortexReFIT / CortexDemo / CortexDecoder plus every `*-policy.sh` and its `--self-test` |
| **Estimated runtime** | ~30 s Python quick; ~2-4 min Swift packages plus gates |

**Tier split (Phase 9 D-21, carried forward, reinforced by D-07).** CI gates correctness, structure
and provenance. CI never trains, never downloads the dataset, never reads the D-06 export, and
never asserts a measured number against a bar. Every automated command below must run green on a
checkout with an empty `Decoder/data/` and no export present.

**Standing caveat, new this phase.** The CI workflow has never executed. Verified against GitHub
on 2026-09-05, not inferred from local state: `repos/D0NMEGA/Cortex/actions/runs` returns
`total_count: 0`, and `defaultBranchRef` is **empty** - the remote exists but holds no commits.
Every "CI-blocking" row describes where an assertion is wired, not a run that has happened. Phase
evidence must record locally-captured transcripts, and the README's present-tense "enforced as CI
structural gates" claim is itself in scope for the RD-09 sweep.

**D-18 consequence, recorded 2026-09-05:** the repository is **private** (`isPrivate: true`).
Pushing `main` under D-18 makes CI run for the first time; it does **not** make the repo public.
Repository visibility is a separate, unmade decision. Any README wording written for a public
audience must not assume it.

**D-09 exclusion, added 2026-09-05 after the Codex audit.** The full-suite command deselects
`Decoder/tests/test_heldout_cobps.py`. That test asserts `heldout_co_bps > CO_BPS_MARGIN`
(`:176`) after training (`:124-126`), so including it in a required gate would let a negative
real-data result turn the build red - the exact "red build is pressure to tune" failure D-09
exists to prevent. It remains runnable on demand as an evidence-producing run; it is not a gate.

---

## Sampling Rate

- **After every task commit:** `uv sync --project Decoder --extra dev && uv run --project Decoder pytest Decoder/tests -m "not slow" -q`, plus `swift test --package-path Packages/CortexReFIT` when Swift changed.
- **After every plan wave:** quick Python suite + `swift test` on CortexReFIT / CortexDemo / CortexDecoder + every policy gate with its `--self-test`.
- **Before `/donny-verify-work`:** full suite green, byte-identity check on `refit_bps.json` still passing, every evidence artifact committed with its runbook and device label, ADR-0003 written and indexed.
- **Max feedback latency:** ~30 s (Python quick), ~4 min (full).

---

## Per-Task Verification Map

Reconciled against the plan set on 2026-09-05, then **re-reconciled the same day after the
`10-REVIEWS.md` revision** (17 plans, 47 tasks - Plan 10-10 gained a third task, the SC#2 disposition
checkpoint - 14 waves). Every task carries an `<automated>` verify, `<read_first>` and
`<acceptance_criteria>`. The Wave-0 column names the plan that CREATES each missing artifact.

**What the review changed in this table.** The `readme-policy.sh` control count is **12**, not 14
(review D-2), and its `--self-test` now prints **19** `PASS [` lines because it also runs an eight-case
adversarial corpus. The Seam B smoke is no longer a clean-clone skip: it consumes the committed
synthetic fixture and is asserted non-vacuous (review D-7). Four rows are new: the Schur-stability
check on the regenerated constants (SC#1h), the frame-cadence and renderer/HID delivery accounting
(SC#2g, SC#2h), the BPS non-comparability disclosure (SC#3d), and the ADR retirement-rationale check
(SC#5d).

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | Created by | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|------------|--------|
| 10-03 T1/T2 (SC#1a) | 10-03 | 1 | RD-07 | T-10-03-01 | Gains fit from real residuals, not defaults | unit | `swift test --package-path Packages/CortexReFIT` (KalmanConstantsTests asserts header `noise source = indy-heldout`) | 10-03 | ⬜ pending |
| 10-03 T2 (SC#1b) | 10-03 | 1 | RD-07 | T-10-03-03 | Zero position rows preserved; R stays DIAGONAL (10-PREREGISTRATION s4 resolves the review D-7 conflict with `KalmanConstantsTests.swift:74-76`) | unit | `swift test --package-path Packages/CortexReFIT` (existing invariants, unchanged) | existing | ⬜ pending |
| 10-03 T2 (SC#1h) | 10-03 | 1 | RD-07 | T-10-03-06 | The SHIPPED gain is Schur-stable on the observable block - a real eigen-decay check, not a header string (review D-7) | unit | `swift test --package-path Packages/CortexReFIT` (`shippedGainIsSchurStable`); `rho_closed_loop` recorded in the generated header | 10-03 | ⬜ pending |
| 10-09 T1 (SC#1c) | 10-09 | 6 | RD-07 | T-10-09-01 | Real-data ablation artifact is provenance-bound; **no assertion on sign or magnitude (D-09)** | gate | `./Tools/scripts/refit-real-policy.sh && ./Tools/scripts/refit-real-policy.sh --self-test` | 10-09 | ⬜ pending |
| 10-09 T2 (SC#1d) | 10-09 | 6 | RD-07 | T-10-09-03 | Gain and smoothing reported per arm (Willett confound) | schema | `uv run --project Decoder pytest Decoder/tests/test_real_replay_schema.py -q` | 10-09 | ⬜ pending |
| 10-05 T1 (SC#1e) | 10-05 | 3 | RD-07 | T-10-05-01 | Synthetic Phase-7 invariant still guards filter code, immune to the re-fit | gate | byte-diff `refit_bps.json` after `--smoke`; `python3 Tools/scripts/check_refit_uplift.py` | existing | ⬜ pending |
| 10-13 T1 (SC#1f) | 10-13 | 9 | RD-07 | T-10-13-04 | Honest gap stated with each reference's measurement condition | gate | `./Tools/scripts/readme-policy.sh --self-test` | 10-13 | ⬜ pending |
| 10-07 T1/T2 (SC#1g) | 10-07 | 4 | RD-07 | T-10-07-01 | The measured four-arm real-data ablation numbers | evidence | human-run; `10-refit-real.json` schema-verified by 10-09 | 10-07 | ⬜ pending |
| 10-04 T2 (SC#2a) | 10-04 | 2 | RD-08 | T-10-04-03 | NDT1 genuinely in the loop; no silent decode fallback | unit | `swift test --package-path Packages/CortexDemo` (seqLen from source; modelBackedTicks; lastDecodeFailure) | 10-04 | ⬜ pending |
| 10-01 T3 + 10-08 T1 (SC#2b) | 10-01, 10-08 | 0, 5 | RD-08 | T-10-08-03 | A webgrid hit reported against the PRE-REGISTERED true-cursor ceiling | evidence | `10-ceiling.json` committed before any decoded run; `ceiling_hits` asserted equal in 10-09's gate | 10-01 | ⬜ pending |
| 10-09 T2 (SC#2c) | 10-09 | 6 | RD-08 | T-10-08-03 | The cursor-to-target distance proxy is RD-08's **primary** observable and is present whatever the hit count is; the decomposition carries FIVE factors including `velocity_amplitude_shrinkage`. Presence and shape only, never a value (D-09) | schema | `uv run --project Decoder pytest Decoder/tests/test_real_replay_schema.py -q` | 10-09 | ⬜ pending |
| 10-10 T3 + 10-09 T2 (SC#2i) | 10-10, 10-09 | 6 | RD-08 | T-10-10-10, T-10-01-08 | The RD-08/SC#2 hit contract is resolved BEFORE measurement (10-PREREGISTRATION s15) and the row is confirmed by the USER, never by an agent; `sc2_disposition` presence and membership asserted, value never asserted (D-09) | schema + checkpoint | `test_sc2_disposition_present_but_unasserted`; Plan 10-10 Task 3 is `checkpoint:decision`, `gate="blocking"` | 10-01 | ⬜ pending |
| 10-08 T1 (SC#2d) | 10-08 | 5 | RD-08 | T-10-08-05 | Seam A p99 like-for-like with Phase 8 (one variable changed) | evidence | `CortexDemoBench --real` at the unchanged Phase-8 geometry | 10-04 | ⬜ pending |
| 10-04 T3 (SC#2g) | 10-04 | 2 | RD-08 | T-10-04-08, T-10-04-09 | **No real-data latency is judged against the 25 ms PERF-04 bar** (review D-3), and the 120 Hz cadence is recorded as MODELLED (review D-7) | gate | `python3 -c` asserts `passed` and `budget_ns` are ABSENT from `.bench/glass_to_glass_real.json`; `frame_period_ns == 8333333`; `--real` exits 0 whatever the p99 | 10-04 | ⬜ pending |
| 10-06 T3 (SC#2h) | 10-06 | 4 | RD-08 | T-10-06-08 | Seam B accounting continues past the decode through cursor integration and HID pointer-report encode, so SC#2's renderer and HID legs are counted (review D-7) | smoke | `cursor_updates == pointer_reports_encoded == windows_completed` in `.bench/seam_b.json` | 10-06 | ⬜ pending |
| 10-06 T3 (SC#2e) | 10-06 | 4 | RD-08 | T-10-06-01, T-10-06-08 | Seam B decrypts, decodes and orders every frame; fails closed on tamper; **non-vacuous in CI** - with no export configured it runs the committed synthetic fixture rather than skipping (review D-7) | smoke | `swift run --package-path Packages/CortexDemo CortexSeamBSmoke` runs 256 frames / 225 windows on `tiny_replay.json` and exits 0; `--frames 8` FAILS the anti-vacuity precondition; `--tamper` exits non-zero | 10-06 | ⬜ pending |
| 10-09 T2 (SC#2f) | 10-09 | 6 | RD-08 | T-10-08-01 | Two seams distinctly labeled; Seam B not presented as the Phase-8 number | schema | `uv run --project Decoder pytest Decoder/tests/test_real_replay_schema.py -q` | 10-09 | ⬜ pending |
| 10-14 T1 (SC#3a) | 10-14 | 10 | RD-09 | T-10-14-01 | **Bounded claim (review D-7):** none of the five enumerated superseded tokens appears outside the historical tree unlabeled. NOT a universal proof that no synthetic number anywhere is presented as real - that is carried by the human RD-09 sweep plus the provenance gates | gate | `./Tools/scripts/honesty-sweep.sh && ./Tools/scripts/honesty-sweep.sh --self-test` | 10-14 | ⬜ pending |
| 10-11 T2 + 10-14 T1 (SC#3d) | 10-11, 10-14 | 7, 10 | RD-09 | T-10-11-08 | The BPS comparison's four non-comparability grounds are stated in the README and the spec; the pinned formula is unchanged (review D-4) | gate | `./Tools/scripts/honesty-sweep.sh` (four fixed tokens per file); `swift test --package-path Packages/CortexReFIT` asserts the constant names all four; `git diff --stat Tools/scripts/bps-policy.sh` empty | 10-11 | ⬜ pending |
| 10-12 T3 + 10-14 T1 (SC#3b) | 10-12, 10-14 | 8, 10 | RD-09 | T-10-14-02 | Superseded evidence carries a forward banner | gate | `./Tools/scripts/honesty-sweep.sh` | 10-14 | ⬜ pending |
| 10-11 T1 (SC#3c) | 10-11 | 7 | RD-09 | T-10-11-04 | Methodology label no longer names photodiode as a scheduled phase; prefix pinned | unit | `swift test --package-path Packages/CortexDemo` (GlassToGlassTimerTests verbatim + hasPrefix) | existing | ⬜ pending |
| 10-13 T1 (SC#4a) | 10-13 | 9 | RD-10 | T-10-13-01 | `photodiode` / flat `24.7` no longer required | gate | `./Tools/scripts/readme-policy.sh --self-test` | 10-13 | ⬜ pending |
| 10-13 T1 (SC#4b) | 10-13 | 9 | RD-10 | T-10-13-02, T-10-13-03, T-10-13-08 | **All eight adversarial-corpus strings from `10-REVIEWS.md` D-1 yield the correct verdict**, both directions; each of the three rules (marker / achievement framing / heading scope) bites ALONE | gate | `./Tools/scripts/readme-policy.sh --self-test 2>&1 \| grep 'corpus/'` prints 8 lines, all `PASS [corpus/`, zero `FAIL [corpus/` | 10-13 | ⬜ pending |
| 10-13 T1 (SC#4c) | 10-13 | 9 | RD-10 | T-10-13-04 | D-14 provenance triple required, three strip controls | gate | `./Tools/scripts/readme-policy.sh --self-test` | 10-13 | ⬜ pending |
| 10-13 T1 (SC#4d) | 10-13 | 9 | RD-10 | T-10-13-01 | Every surviving control still bites. **Control count 12** (9 - 2 removed + 5 added; one addition is a POSITIVE control) - **not 14** (review D-2). PASS-line count is a different quantity: **19** = 1 baseline + 7 retained + 3 D-14 + 8 corpus | gate | `./Tools/scripts/readme-policy.sh --self-test 2>&1 \| grep -c 'PASS \['` >= 19, **and** the executor states BOTH arithmetics separately in the commit body | 10-13 | ⬜ pending |
| 10-14 T1 (SC#5a) | 10-14 | 10 | RD-10 | T-10-14-03 | LAT-01..LAT-08 preserved verbatim in ROADMAP and REQUIREMENTS | gate | `./Tools/scripts/honesty-sweep.sh` | 10-14 | ⬜ pending |
| 10-13 T2 + 10-14 T1 (SC#5b) | 10-13, 10-14 | 9, 10 | RD-10 | T-10-14-04 | ADR-0003 exists, four headings, Status line, indexed | gate | `./Tools/scripts/honesty-sweep.sh` | 10-13 | ⬜ pending |
| 10-13 T2 + 10-14 T1 (SC#5d) | 10-13, 10-14 | 9, 10 | RD-10 | T-10-13-09 | ADR-0003 records the retirement RATIONALE, not only the headings: the literals `hardware-gated` and `largest credibility hole` are present (review D-7) | gate | `./Tools/scripts/honesty-sweep.sh` control 6 removes `hardware-gated` with every heading intact and the gate still bites | 10-13 | ⬜ pending |
| 10-12 T1 (SC#5c) | 10-12 | 8 | RD-10 | T-10-12-02 | Honest-gates table reflects the new boundary | gate | `./Tools/scripts/readme-policy.sh --self-test` | 10-12 | ⬜ pending |
| 10-15 T1 (D-18) | 10-15 | 11 | RD-09 | T-10-15-01 | Lint toolchain version drift fails loudly | gate | `./Tools/scripts/toolchain-policy.sh && ./Tools/scripts/toolchain-policy.sh --self-test` | 10-15 | ⬜ pending |
| 10-15 T3 (D-18) | 10-15 | 11 | RD-09 | T-10-15-02 | `swiftformat --lint .` clean, no gate disarmed | gate | `swiftformat --lint .` plus the eleven policy gates and their self-tests | existing | ⬜ pending |
| 10-16 T2 (D-18) | 10-16 | 12 | RD-09 | T-10-16-01 | `identifier_name` clear with every JSON key byte-identical | gate | `swiftlint --strict`; byte-diff `refit_bps.json` and `webgrid_bps.json` | existing | ⬜ pending |
| 10-17 T1/T3 (D-18) | 10-17 | 13 | RD-09 | T-10-17-01, T-10-17-05 | Nothing secret or licence-encumbered is published; the CI claim matches the real run | gate + evidence | pre-push audit greps; `gh api .../actions/runs`; `./Tools/scripts/readme-policy.sh --self-test` | 10-17 | ⬜ pending |
| 10-17 T2 (D-18) | 10-17 | 13 | RD-09 | T-10-17-08, T-10-17-09 | Repository visibility is a SEPARATE user decision from the push; the repo is private today and stays private unless the user chooses otherwise | checkpoint | `checkpoint:decision`, `gate="blocking"`; the audit records `isPrivate` before and after as two lines; under `private-push` no `gh repo edit` runs at all | 10-17 | ⬜ pending |
| 10-10 T2 (D-16) | 10-10 | 6 | RD-08 | T-10-10-07, T-10-10-08 | CortexMac builds and runs under the free Personal team via a signing-only `CODE_SIGN_ENTITLEMENTS` override, with every committed entitlements file and `project.yml` byte-identical | gate + evidence | `xcodebuild ... CODE_SIGN_ENTITLEMENTS=Tools/capture/CortexMac.capture.entitlements` reaches BUILD SUCCEEDED; `git diff --stat` over the three entitlements files and `project.yml` is EMPTY; `./Tools/scripts/hid-surface-policy.sh --self-test` exits 0 | 10-10 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Test infrastructure exists on both sides. The gaps are fixtures, gates, and one missing seam.

- [ ] (Plan 10-09) `Tools/scripts/refit-real-policy.sh` + `--self-test` (5 controls), structurally copied from `decoder-policy.sh` - SC#1c, SC#1d
- [ ] (Plan 10-14) `Tools/scripts/honesty-sweep.sh` + `--self-test` - SC#3a, SC#3b, SC#5a, SC#5b
- [ ] (Plan 10-09) `Decoder/tests/test_real_replay_schema.py`, copying `test_metrics_schema.py`'s guard-split-marker self-check verbatim so the module cannot grow a measured-value assertion - SC#1d, SC#2c, SC#2f
- [ ] (Plan 10-02) A committed **synthetic** export fixture (few hundred bins, correct dtypes + sidecar) so the Swift reader and schema test run on a clean clone with no dataset. The D-20 `tiny_v73.mat` pattern applied to the export. **Without it every export-touching test is dataset-gated and CI covers none of it.**
- [ ] (Plan 10-06) The rolling 32-bin window accumulator between the IPC consumer and `SpikeInputBuffer`, with its own unit test
- [ ] (Plan 10-13) `readme-policy.sh`'s four new helpers (`needle_lines_lc`, `require_marker_on_matching_lines`, `forbid_achievement_framing`, `require_needle_under_heading`) + 3 D-14 strip controls + the 8-case adversarial corpus + a `write_clean_readme` that carries a `## Future work` heading. **Control count 12, PASS lines 19.**
- [ ] (Plan 10-10) `Tools/capture/CortexMac.capture.entitlements` + `Tools/capture/README.md` - without them CortexMac does not build under the free Personal team at all, so the D-16 capture is unreachable
- [ ] (Plan 10-06 + 10-09 + 10-14) Three new `ci.yml` steps: the Seam B fixture smoke (wired by 10-06, verified by 10-09 - one step only, and it must be the fixture variant, not the vacuous clean-clone-skip variant), the real-data provenance gate (10-09), the honesty sweep (10-14) - each gate with its `--self-test` alongside, matching the existing seven policy-gate steps
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
| Webgrid hit demonstration + recorded capture (D-16) | RD-08 | Needs a GUI session on the M5 Pro. **CortexMac does not build without a signing-only entitlements override** - the free Personal team cannot provision `com.apple.developer.hid.virtual.device`; verified 2026-09-05 | Build with `CODE_SIGN_ENTITLEMENTS=Tools/capture/CortexMac.capture.entitlements`, run with `MTL_HUD_ENABLED=1`, record the six named SC#2 observations, store as ILLUSTRATION. RD-08's evidentiary basis is the five headless committed artifacts listed in Plan 10-10 Task 3a, not this recording |
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
- [x] No gate asserts the sign or magnitude of a real-data result (D-09; enforced by a marker comment plus an acceptance grep in 10-09 and 10-14). **Reinforced after review D-3:** `CortexDemoBench --real` applies no PERF-04 verdict and emits no `passed`/`budget_ns`, so the 25 ms synthetic gate is never inherited by a real-data measurement; `sc2_disposition`'s VALUE is never asserted, only its presence and membership
- [x] No required suite includes `Decoder/tests/test_heldout_cobps.py` (review D-3; the full-suite command above deselects it and no plan re-adds it)
- [x] The Seam B CI step is non-vacuous: it consumes the committed synthetic fixture and fails if it resolves a source and completes zero windows (review D-7)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planner-reconciled 2026-09-05 against the 17-plan set. Execution status stays `pending` until `/donny-validate-phase` runs post-execution.
