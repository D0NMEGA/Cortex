---
phase: 10
slug: v1-real-data-closed-loop-launch
status: reconciled
nyquist_compliant: true
wave_0_complete: true
created: 2026-09-05
updated: 2026-09-08
audited_by: /donny-audit-phase 10 --validate (2026-09-07); donny-nyquist-auditor gap-fill (2026-09-08)
---

# Phase 10 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `10-RESEARCH.md` "Validation Architecture" (line 1055). Written 2026-09-05 as the
> plan-time seed, then **reconciled against the executed phase on 2026-09-07** by
> `/donny-audit-phase 10 --validate`. Every status in the map below was set by running the row's
> own command on this machine, not by reading a summary. **Gap-filled and re-verified on
> 2026-09-08** by donny-nyquist-auditor: the last outstanding row (`10-17 T2`) is closed against the
> user's recorded checkpoint decision, the stale 16/17 framing is corrected to 17/17, and every
> command in the map was re-run on this machine rather than assumed still green. See "Validation
> Audit 2026-09-08" at the end of this document.

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

**Standing caveat RETIRED 2026-09-07.** The plan-time seed recorded that the CI workflow had never
executed (`actions/runs` -> `total_count: 0`, empty `defaultBranchRef`, verified 2026-09-05). That is
no longer true. Re-verified against GitHub on 2026-09-07: `repos/D0NMEGA/Cortex/actions/runs`
returns **`total_count: 24`**, and the six most recent runs all report `conclusion: success`
(`cd87d6f`, `8df050f`, `9388476`, `037a252`, `0463abf`, `670de9f`). The first push and the first
runs are recorded in `10-launch-evidence.md`. "CI-blocking" rows now describe assertions that have
actually run on a hosted runner, so the README's present-tense "enforced as CI structural gates"
wording is now earned rather than aspirational.

Getting there took seven post-launch fixes, which is itself the finding: the gates had never been
executed, so several were broken in ways local runs could not reveal - `1613e32` (wrong runner
platform), `68a87fe` (SwiftPM resolved from the repo root instead of per package), `c75a401`
(E501 from the history scrub plus the toolchain pin), `b3aca9e` (arm64-only so the xcodebuild
smokes compile), `3d0a87c` (**the DEC-12 negative control had been failing since Phase 8**),
`a59b2bc` (**CortexRender's suite had never been run by CI at all**), `7e6b9eb` (CortexiOS had
never compiled - a Swift 6 data-race error). Two of those, `3d0a87c` and `a59b2bc`, are exactly the
class of defect a never-executed gate hides: a green local checkout beside a control that does not
bite and a suite nobody runs.

**D-18 consequence, recorded 2026-09-05, re-confirmed 2026-09-07:** the repository is **private**
(`gh repo view` -> `{"isPrivate": true, "visibility": "PRIVATE"}`, checked again during this audit).
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
| 10-03 T1/T2 (SC#1a) | 10-03 | 1 | RD-07 | T-10-03-01 | Gains fit from real residuals, not defaults | unit | `swift test --package-path Packages/CortexReFIT` (KalmanConstantsTests asserts header `noise source = indy-heldout`) | 10-03 | ✅ green |
| 10-03 T2 (SC#1b) | 10-03 | 1 | RD-07 | T-10-03-03 | Zero position rows preserved; R stays DIAGONAL (10-PREREGISTRATION s4 resolves the review D-7 conflict with `KalmanConstantsTests.swift:74-76`) | unit | `swift test --package-path Packages/CortexReFIT` (existing invariants, unchanged) | existing | ✅ green |
| 10-03 T2 (SC#1h) | 10-03 | 1 | RD-07 | T-10-03-06 | The SHIPPED gain is Schur-stable on the observable block - a real eigen-decay check, not a header string (review D-7) | unit | `swift test --package-path Packages/CortexReFIT` (`shippedGainIsSchurStable`); `rho_closed_loop` recorded in the generated header | 10-03 | ✅ green |
| 10-09 T1 (SC#1c) | 10-09 | 6 | RD-07 | T-10-09-01 | Real-data ablation artifact is provenance-bound; **no assertion on sign or magnitude (D-09)** | gate | `./Tools/scripts/refit-real-policy.sh && ./Tools/scripts/refit-real-policy.sh --self-test` | 10-09 | ✅ green |
| 10-09 T2 (SC#1d) | 10-09 | 6 | RD-07 | T-10-09-03 | Gain and smoothing reported per arm (Willett confound) | schema | `uv run --project Decoder pytest Decoder/tests/test_real_replay_schema.py -q` | 10-09 | ✅ green |
| 10-05 T1 (SC#1e) | 10-05 | 3 | RD-07 | T-10-05-01 | Synthetic Phase-7 invariant still guards filter code, immune to the re-fit | gate | byte-diff `refit_bps.json` after `--smoke`; `python3 Tools/scripts/check_refit_uplift.py` | existing | ✅ green |
| 10-13 T1 (SC#1f) | 10-13 | 9 | RD-07 | T-10-13-04 | Honest gap stated with each reference's measurement condition | gate | `./Tools/scripts/readme-policy.sh --self-test` | 10-13 | ✅ green |
| 10-07 T1/T2 (SC#1g) | 10-07 | 4 | RD-07 | T-10-07-01 | The measured four-arm real-data ablation numbers | evidence | human-run; `10-refit-real.json` schema-verified by 10-09 | 10-07 | 📄 evidence |
| 10-04 T2 (SC#2a) | 10-04 | 2 | RD-08 | T-10-04-03 | NDT1 genuinely in the loop; no silent decode fallback | unit | `swift test --package-path Packages/CortexDemo` (seqLen from source; modelBackedTicks; lastDecodeFailure) | 10-04 | ✅ green |
| 10-01 T3 + 10-08 T1 (SC#2b) | 10-01, 10-08 | 0, 5 | RD-08 | T-10-08-03 | A webgrid hit reported against the PRE-REGISTERED true-cursor ceiling | evidence | `10-ceiling.json` committed before any decoded run; equality asserted by `Tools/scripts/check_real_replay_provenance.py` assertion 7 (`replay_reference_hits == ceiling.canonical_hits`), run as refit-real-policy's python leg. **Key is `canonical_hits`, not `ceiling_hits`** - the seed named a field that does not exist | 10-01 | ✅ green |
| 10-09 T2 (SC#2c) | 10-09 | 6 | RD-08 | T-10-08-03 | The cursor-to-target distance proxy is RD-08's **primary** observable and is present whatever the hit count is; the decomposition carries FIVE factors including `velocity_amplitude_shrinkage`. Presence and shape only, never a value (D-09) | schema | `uv run --project Decoder pytest Decoder/tests/test_real_replay_schema.py -q` | 10-09 | ✅ green |
| 10-10 T3 + 10-09 T2 (SC#2i) | 10-10, 10-09 | 6 | RD-08 | T-10-10-10, T-10-01-08 | The RD-08/SC#2 hit contract is resolved BEFORE measurement (10-PREREGISTRATION s15) and the row is confirmed by the USER, never by an agent; `sc2_disposition` presence and membership asserted, value never asserted (D-09) | schema + checkpoint | `test_sc2_disposition_present_but_unasserted`; Plan 10-10 Task 3 is `checkpoint:decision`, `gate="blocking"` | 10-01 | ✅ green |
| 10-08 T1 (SC#2d) | 10-08 | 5 | RD-08 | T-10-08-05 | Seam A p99 like-for-like with Phase 8 (one variable changed) | evidence | `CortexDemoBench --real` at the unchanged Phase-8 geometry | 10-04 | 📄 evidence |
| 10-04 T3 (SC#2g) | 10-04 | 2 | RD-08 | T-10-04-08, T-10-04-09 | **No real-data latency is judged against the 25 ms PERF-04 bar** (review D-3), and the 120 Hz cadence is recorded as MODELLED (review D-7) | gate | `python3 -c` asserts `passed` and `budget_ns` are ABSENT from `Packages/CortexDemo/.bench/glass_to_glass_real.json` (the seed said `.bench/`; the binary writes under its own package); `frame_period_ns == 8333333`; `--real` exits 0 whatever the p99 | 10-04 | ✅ green |
| 10-06 T3 (SC#2h) | 10-06 | 4 | RD-08 | T-10-06-08 | Seam B accounting continues past the decode through cursor integration and HID pointer-report encode, so SC#2's renderer and HID legs are counted (review D-7) | smoke | `cursor_updates == pointer_reports_encoded == windows_completed` in `Packages/CortexDemo/.bench/seam_b.json` (seed said `.bench/`) | 10-06 | ✅ green |
| 10-06 T3 (SC#2e) | 10-06 | 4 | RD-08 | T-10-06-01, T-10-06-08 | Seam B decrypts, decodes and orders every frame; fails closed on tamper; **non-vacuous in CI** - with no export configured it runs the committed synthetic fixture rather than skipping (review D-7) | smoke | `swift run --package-path Packages/CortexDemo CortexSeamBSmoke` runs 256 frames / 225 windows on `tiny_replay.json` and exits 0; `--frames 8` FAILS the anti-vacuity precondition; `--tamper` exits non-zero | 10-06 | ✅ green |
| 10-09 T2 (SC#2f) | 10-09 | 6 | RD-08 | T-10-08-01 | Two seams distinctly labeled; Seam B not presented as the Phase-8 number | schema | `uv run --project Decoder pytest Decoder/tests/test_real_replay_schema.py -q` | 10-09 | ✅ green |
| 10-14 T1 (SC#3a) | 10-14 | 10 | RD-09 | T-10-14-01 | **Bounded claim (review D-7):** none of the five enumerated superseded tokens appears outside the historical tree unlabeled. NOT a universal proof that no synthetic number anywhere is presented as real - that is carried by the human RD-09 sweep plus the provenance gates | gate | `./Tools/scripts/honesty-sweep.sh && ./Tools/scripts/honesty-sweep.sh --self-test` | 10-14 | ✅ green |
| 10-11 T2 + 10-14 T1 (SC#3d) | 10-11, 10-14 | 7, 10 | RD-09 | T-10-11-08 | The BPS comparison's four non-comparability grounds are stated in the README and the spec; the pinned formula is unchanged (review D-4) | gate | `./Tools/scripts/honesty-sweep.sh` (four fixed tokens per file); `swift test --package-path Packages/CortexReFIT` asserts the constant names all four; `git diff --stat Tools/scripts/bps-policy.sh` empty | 10-11 | ✅ green |
| 10-12 T3 + 10-14 T1 (SC#3b) | 10-12, 10-14 | 8, 10 | RD-09 | T-10-14-02 | Superseded evidence carries a forward banner | gate | `./Tools/scripts/honesty-sweep.sh` | 10-14 | ✅ green |
| 10-11 T1 (SC#3c) | 10-11 | 7 | RD-09 | T-10-11-04 | Methodology label no longer names photodiode as a scheduled phase; prefix pinned | unit | `swift test --package-path Packages/CortexDemo` (GlassToGlassTimerTests verbatim + hasPrefix) | existing | ✅ green |
| 10-13 T1 (SC#4a) | 10-13 | 9 | RD-10 | T-10-13-01 | `photodiode` / flat `24.7` no longer required | gate | `./Tools/scripts/readme-policy.sh --self-test` | 10-13 | ✅ green |
| 10-13 T1 (SC#4b) | 10-13 | 9 | RD-10 | T-10-13-02, T-10-13-03, T-10-13-08 | **All eight adversarial-corpus strings from `10-REVIEWS.md` D-1 yield the correct verdict**, both directions; each of the three rules (marker / achievement framing / heading scope) bites ALONE | gate | `./Tools/scripts/readme-policy.sh --self-test 2>&1 \| grep 'corpus/'` prints 8 lines, all `PASS [corpus/`, zero `FAIL [corpus/` | 10-13 | ✅ green |
| 10-13 T1 (SC#4c) | 10-13 | 9 | RD-10 | T-10-13-04 | D-14 provenance triple required, three strip controls | gate | `./Tools/scripts/readme-policy.sh --self-test` | 10-13 | ✅ green |
| 10-13 T1 (SC#4d) | 10-13 | 9 | RD-10 | T-10-13-01 | Every surviving control still bites. **Control count 12** (9 - 2 removed + 5 added; one addition is a POSITIVE control) - **not 14** (review D-2). PASS-line count is a different quantity: **19** = 1 baseline + 7 retained + 3 D-14 + 8 corpus | gate | `./Tools/scripts/readme-policy.sh --self-test 2>&1 \| grep -c 'PASS \['` >= 19, **and** the executor states BOTH arithmetics separately in the commit body | 10-13 | ✅ green |
| 10-14 T1 (SC#5a) | 10-14 | 10 | RD-10 | T-10-14-03 | LAT-01..LAT-08 preserved verbatim in ROADMAP and REQUIREMENTS | gate | `./Tools/scripts/honesty-sweep.sh` | 10-14 | ✅ green |
| 10-13 T2 + 10-14 T1 (SC#5b) | 10-13, 10-14 | 9, 10 | RD-10 | T-10-14-04 | ADR-0003 exists, four headings, Status line, indexed | gate | `./Tools/scripts/honesty-sweep.sh` | 10-13 | ✅ green |
| 10-13 T2 + 10-14 T1 (SC#5d) | 10-13, 10-14 | 9, 10 | RD-10 | T-10-13-09 | ADR-0003 records the retirement RATIONALE, not only the headings: the literals `hardware-gated` and `largest credibility hole` are present (review D-7) | gate | `./Tools/scripts/honesty-sweep.sh` control 6 removes `hardware-gated` with every heading intact and the gate still bites | 10-13 | ✅ green |
| 10-12 T1 (SC#5c) | 10-12 | 8 | RD-10 | T-10-12-02 | Honest-gates table reflects the new boundary | gate | `./Tools/scripts/readme-policy.sh --self-test` | 10-12 | ✅ green |
| 10-15 T1 (D-18) | 10-15 | 11 | RD-09 | T-10-15-01 | Lint toolchain version drift fails loudly | gate | `./Tools/scripts/toolchain-policy.sh && ./Tools/scripts/toolchain-policy.sh --self-test` | 10-15 | ✅ green |
| 10-15 T3 (D-18) | 10-15 | 11 | RD-09 | T-10-15-02 | `swiftformat --lint .` clean, no gate disarmed | gate | `swiftformat --lint .` plus the eleven policy gates and their self-tests | existing | ✅ green |
| 10-16 T2 (D-18) | 10-16 | 12 | RD-09 | T-10-16-01 | `identifier_name` clear with every JSON key byte-identical | gate | `swiftlint --strict`; byte-diff `refit_bps.json` and `webgrid_bps.json` | existing | ✅ green |
| 10-17 T1/T3 (D-18) | 10-17 | 13 | RD-09 | T-10-17-01, T-10-17-05 | Nothing secret or licence-encumbered is published; the CI claim matches the real run | gate + evidence | pre-push audit greps; `gh api .../actions/runs`; `./Tools/scripts/readme-policy.sh --self-test` | 10-17 | ✅ green |
| 10-17 T2 (D-18) | 10-17 | 13 | RD-09 | T-10-17-08, T-10-17-09 | Repository visibility is a SEPARATE user decision from the push; the repo is private today and stays private unless the user chooses otherwise | checkpoint | `checkpoint:decision`, `gate="blocking"`; the audit records `isPrivate` before and after as two lines; under `private-push` no `gh repo edit` runs at all | 10-17 | ✅ green |
| 10-10 T2 (D-16) | 10-10 | 6 | RD-08 | T-10-10-07, T-10-10-08 | CortexMac builds and runs under the free Personal team via a signing-only `CODE_SIGN_ENTITLEMENTS` override, with every committed entitlements file and `project.yml` byte-identical | gate + evidence | `xcodebuild ... CODE_SIGN_ENTITLEMENTS=Tools/capture/CortexMac.capture.entitlements` reaches BUILD SUCCEEDED; `git diff --stat` over the three entitlements files and `project.yml` is EMPTY; `./Tools/scripts/hid-surface-policy.sh --self-test` exits 0 | 10-10 | ✅ green |

*Status: ✅ green (command run on this machine 2026-09-07, re-verified 2026-09-08, exit 0) · 📄 evidence (human-run, dataset-gated by D-07/D-21 - not a coverage gap) · ⬜ outstanding · ❌ red · ⚠️ flaky*

**10-17 T2 (D-18) closed 2026-09-08.** This row was `⬜ outstanding` at the 2026-09-07 audit because
the `checkpoint:decision`, `gate="blocking"` on repository visibility had not yet been answered. It
has since been resolved: the user was shown the verdict table and every FLAGGED row, and answered
`private-push` (push, leave visibility unchanged), recorded verbatim in commit `710e729`
(`docs(10-17): record the private-push decision and all five flag dispositions`,
`.planning/phases/10-v1-real-data-closed-loop-launch/10-prepush-audit.md:514-527`). `gh repo view
D0NMEGA/Cortex --json isPrivate,visibility` returns `{"isPrivate":true,"visibility":"PRIVATE"}` when
re-run today, 2026-09-08, matching the BEFORE/AFTER pair the plan recorded and confirming no drift
since the push. **This row is closed on the user's own recorded decision at a blocking checkpoint,
not by this or any other agent.** The checkpoint held until the user answered; this audit's only
contribution is re-verifying that today's live repository state still matches what was recorded.

---

## Wave 0 Requirements

Test infrastructure exists on both sides. The gaps are fixtures, gates, and one missing seam.

**All ten landed. Verified by existence and execution on 2026-09-07, not by reading a summary.**
Two counts in the seed were wrong and are corrected here: `refit-real-policy.sh --self-test` runs
**6** controls, not the 5 the list predicted (clean quartet, strip `data_source`, perturb
`source_sha256`, drop the `refit_reversed_target` arm, strip the open-loop disclosure, collapse the
seams), and the repo now carries **12** policy gates rather than eleven - `infoplist-policy.sh`
was added post-plan by `13288d8` after `xcodegen` was caught stripping two required Info.plist keys.

- [x] (Plan 10-09) `Tools/scripts/refit-real-policy.sh` + `--self-test` (5 controls), structurally copied from `decoder-policy.sh` - SC#1c, SC#1d
- [x] (Plan 10-14) `Tools/scripts/honesty-sweep.sh` + `--self-test` - SC#3a, SC#3b, SC#5a, SC#5b
- [x] (Plan 10-09) `Decoder/tests/test_real_replay_schema.py`, copying `test_metrics_schema.py`'s guard-split-marker self-check verbatim so the module cannot grow a measured-value assertion - SC#1d, SC#2c, SC#2f
- [x] (Plan 10-02) A committed **synthetic** export fixture (few hundred bins, correct dtypes + sidecar) so the Swift reader and schema test run on a clean clone with no dataset. The D-20 `tiny_v73.mat` pattern applied to the export. **Without it every export-touching test is dataset-gated and CI covers none of it.**
- [x] (Plan 10-06) The rolling 32-bin window accumulator between the IPC consumer and `SpikeInputBuffer`, with its own unit test
- [x] (Plan 10-13) `readme-policy.sh`'s four new helpers (`needle_lines_lc`, `require_marker_on_matching_lines`, `forbid_achievement_framing`, `require_needle_under_heading`) + 3 D-14 strip controls + the 8-case adversarial corpus + a `write_clean_readme` that carries a `## Future work` heading. **Control count 12, PASS lines 19.**
- [x] (Plan 10-10) `Tools/capture/CortexMac.capture.entitlements` + `Tools/capture/README.md` - without them CortexMac does not build under the free Personal team at all, so the D-16 capture is unreachable
- [x] (Plan 10-06 + 10-09 + 10-14) Three new `ci.yml` steps: the Seam B fixture smoke (wired by 10-06, verified by 10-09 - one step only, and it must be the fixture variant, not the vacuous clean-clone-skip variant), the real-data provenance gate (10-09), the honesty sweep (10-14) - each gate with its `--self-test` alongside, matching the existing seven policy-gate steps
- [x] (Plan 10-10) `10-HUMAN-UAT.md` from the `09-HUMAN-UAT.md` template, for the iPad-M4 rows carried forward
- [x] (Plan 10-01) The committed true-cursor ceiling script, run and its number published **before** the decoded run is scored

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
| ~~"CI is green"~~ **NO LONGER MANUAL** | all | ~~The workflow has never run~~ **Retired 2026-09-07: it has now run 24 times, latest 6 green.** Kept as a row so the change of status is legible rather than silently deleted | `gh api repos/D0NMEGA/Cortex/actions/runs --jq '.total_count'`; the seven fixes it took to get there are listed under Test Infrastructure above |

---

## Post-10-17 gap fill (donny-nyquist-auditor, 2026-09-07)

Two render-package channel types shipped after the Plan 10-17 wave (the free-running-cursor /
real-click / task's-own-board demo commits `037a252`..`cd87d6f`) had no test file. Neither maps to
a Per-Task Verification Map row above; they are demo-polish code, not a numbered plan task. Filled
by a targeted donny-nyquist-auditor pass; no implementation file was modified.

| Gap | File | Requirement covered | Test Type | Automated Command | Test File | Mutation Kill Rate | Status |
|-----|------|---------------------|-----------|--------------------|-----------|---------------------|--------|
| GAP 1 | `TargetChannel.swift` | Clear-not-clamp on non-finite/out-of-grid input (header's stated contract); (0,0) sentinel-collision; round-trip precision | unit | `swift test --package-path Packages/CortexRender --filter TargetChannelTests` | `Packages/CortexRender/Tests/CortexRenderTests/TargetChannelTests.swift` | 12/14 = 85.7% | green |
| GAP 2 | `SelectionChannel.swift` | Clamp-into-range (opposite of TargetChannel) on non-finite/out-of-range input; four fields do not bleed across bit ranges | unit | `swift test --package-path Packages/CortexRender --filter SelectionChannelTests` | `Packages/CortexRender/Tests/CortexRenderTests/SelectionChannelTests.swift` | 10/11 = 90.9% | green |

**Mutation tooling.** No Swift mutation-testing tool is installed or trusted in this environment:
`muter` has no Homebrew-core formula, and its community tap (`muter-mutation-testing/formulae`)
is refused by Homebrew's untrusted-tap gate. A maintainer who wants it can run:
```
brew tap muter-mutation-testing/formulae
brew trust muter-mutation-testing/formulae   # explicit trust required, not done here
brew install muter
```
In its absence, kill rate was measured by hand: both source files were copied verbatim into an
isolated scratch SwiftPM package outside this repo (never the real repo files) alongside the real
test files (import renamed), 25 hand-designed mutants covering boundary/relational operators,
shift-amount and bit-position constants, arithmetic rounding, guard deletion and
field-assignment swaps were applied one at a time, and `swift test`'s exit code decided killed vs.
survived. The driver script and per-mutant log are scratch-only (not committed); the mutant list
and verdicts are reproduced below for auditability.

TargetChannel (12/14 killed):
- Killed: lower/upper bound off-by-one on x and y (4), validity-bit position wrong in `store` and
  in `load` (2), empty-sentinel corrupted to alias a live (0,0) target (1), `clear()` dropped from
  the out-of-range branch (1), wrong-variable bound checks (2), the `+0.5` rounding offset dropped
  on qx and qy (2, killed by `roundTripIsAccurateWellBelowOneQuantisationStep`).
- Survived, both true equivalent mutants (proven, not a test gap): removing `x.isFinite` or
  `y.isFinite` from the `store` guard changes no observable behavior, because the remaining
  `x >= 0, x < 1` (resp. `y`) range check already rejects every non-finite `Float` -- +/-infinity
  fails one of the two comparisons and NaN fails both, since IEEE 754 NaN comparisons are always
  false. `TargetChannel.swift:41`'s guard carries two comparisons redundant with the `isFinite`
  checks by this argument; harmless, but worth a maintainer's awareness.

SelectionChannel (10/11 killed):
- Killed: hitX/clickPulse/hitY shift-amount and bit-boundary mutations (4), `quantise`'s upper and
  lower clamp bounds widened to allow overflow/negative encode (2, both trap at the `UInt16`
  conversion), `quantise`'s `isFinite` guard removed (1), `SelectionState.idle`'s `hitFade`
  default changed (1), `SelectionState.init`'s hitX/hitY assignment swapped (1), the `hitFade`
  term dropped from `store`'s bit-packing (1).
- Survived: dropping `quantise`'s `+0.5` rounding offset is a sub-quantisation-step precision
  change (worst case ~1/65535, the same class as TargetChannel's now-killed rounding mutants
  above). Not chased further given the file already clears the 80% bar at 90.9%; the technique
  that killed the TargetChannel analogue (`roundTripIsAccurateWellBelowOneQuantisationStep`)
  would generalize here if a maintainer wants 100%.

Both gaps meet the mutation_check step's 80% bar (TargetChannel 85.7%, SelectionChannel 90.9%).

**Observation (not fixed, not blocking): `TargetChannel` actor-isolation inconsistency.**
`TargetChannel.swift:28` declares `public final class TargetChannel: Sendable` without
`nonisolated`, while its two siblings (`CursorPositionChannel.swift:40`,
`SelectionChannel.swift:40`) both declare `nonisolated` explicitly. Under this package's
`.defaultIsolation(MainActor.self)` (`Package.swift`), that omission makes `TargetChannel`'s
`init`/`store`/`clear`/`load` MainActor-isolated -- confirmed empirically: a plain nonisolated
test function calling `TargetChannel().load()` fails to compile with "call to main actor-isolated
instance method 'load()' in a synchronous nonisolated context". `TargetChannelTests.swift`
accommodates this by annotating its `@Suite` `@MainActor`, a test-authoring choice, not an
implementation change. It does not currently break the build because every existing call site
(`MacDisplayLinkAdapter`, itself `@MainActor`) already runs on the main actor. It is inconsistent
with the class's own header ("A latest-value channel ... One atomic word, no queue, no back
pressure", the same cross-thread lock-free design as its two `nonisolated` siblings) and would
become a real defect the moment a non-MainActor caller (e.g. a render-thread read) is added.
Flagged for the orchestrator/maintainer; not fixed here per the read-only-implementation
constraint.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (**47/47** carry `<automated>`; the seed said 46/46, off by one against its own 47-task header - recounted `grep -c '<automated>'` across the 17 PLAN.md files)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (see the Wave 0 Requirements list below; every item is owned by a named plan)
- [x] No watch-mode flags
- [x] Feedback latency < 30s (quick) / < 4min (full)
- [x] Every new gate ships its `--self-test` in the same commit (refit-real, honesty-sweep, toolchain, and the readme-policy rewrite)
- [x] No gate asserts the sign or magnitude of a real-data result (D-09; enforced by a marker comment plus an acceptance grep in 10-09 and 10-14). **Reinforced after review D-3:** `CortexDemoBench --real` applies no PERF-04 verdict and emits no `passed`/`budget_ns`, so the 25 ms synthetic gate is never inherited by a real-data measurement; `sc2_disposition`'s VALUE is never asserted, only its presence and membership
- [x] No required suite includes `Decoder/tests/test_heldout_cobps.py` (review D-3; the full-suite command above deselects it and no plan re-adds it)
- [x] The Seam B CI step is non-vacuous: it consumes the committed synthetic fixture and fails if it resolves a source and completes zero windows (review D-7)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planner-reconciled 2026-09-05 against the 17-plan set; **execution-reconciled
2026-09-07** by `/donny-audit-phase 10 --validate`, which set every status above by running the
row's own command; **gap-filled and re-verified 2026-09-08** by donny-nyquist-auditor, which closed
the last outstanding row (`10-17 T2`, against the user's recorded `private-push` decision), corrected
the stale 16/17 phase-completion framing to 17/17, and re-ran every command in the map with zero
regressions found. Zero rows are outstanding as of this pass.

---

## Validation Audit 2026-09-07

| Metric | Count |
|--------|-------|
| Rows in the per-task map | 35 |
| Green (command run, exit 0) | 32 |
| Evidence (human-run, dataset-gated) | 2 |
| Outstanding | 1 |
| Gaps found outside the map | 2 |
| Resolved | 2 |
| Escalated | 0 |

### What was run

Not inferred from the SUMMARY files. Each of these was executed on this machine on 2026-09-07:

| Command | Result |
|---------|--------|
| `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` | 289 passed, 10 deselected |
| `swift test` on CortexReFIT / CortexDemo / CortexDecoder / CortexRender / CortexCore / CortexBCIHID | all exit 0 |
| 12 `*-policy.sh` gates, each with `--self-test` | 24/24 exit 0 |
| `readme-policy.sh --self-test \| grep -c 'PASS \['` | **19**, exactly as SC#4d requires |
| `readme-policy.sh --self-test \| grep 'corpus/'` | **8 lines, 8 PASS, 0 FAIL**, as SC#4b requires |
| `CortexSeamBSmoke` | 256 frames / 225 windows; `cursor_updates == pointer_reports_encoded == windows_completed == 225` |
| `CortexSeamBSmoke --frames 8` / `--tamper` | exit 133 / exit 1 - both negative controls bite |
| `glass_to_glass_real.json` inspection | no `passed`, no `budget_ns`, `frame_period_ns == 8333333` |
| `check_refit_uplift.py` | exit 0, uplift holds on the pinned seed |
| `swiftlint --strict` / `swiftformat --lint .` | 0 violations / 119 files; 0 of 121 need formatting |
| `gh api repos/D0NMEGA/Cortex/actions/runs` | `total_count: 24`, latest 6 `success` |

### Corrections made to this document

1. **The "CI has never executed" standing caveat was false** and is retired above, with the seven
   post-launch fixes it took to make the workflow green. Two of them (`3d0a87c`, `a59b2bc`) were
   real defects a never-run gate had been hiding since Phase 8.
2. **SC#2b named a field that does not exist.** The seed asserted `ceiling_hits`; the artifact and
   the checker both use `canonical_hits`, and the equality lives in
   `check_real_replay_provenance.py` assertion 7, not directly in `refit-real-policy.sh`.
3. **Three `.bench/` paths were wrong** - the binaries write under `Packages/CortexDemo/.bench/`.
4. **Two counts were wrong**: `refit-real-policy.sh` has 6 controls (seed said 5), and the repo has
   12 policy gates (seed said eleven).
5. **The sign-off said 46/46** against its own 47-task header. It is 47/47.

### Phase 10 is 17/17 (updated 2026-09-08; this section originally read "16/17" on 2026-09-07)

Plan `10-17` now has both a PLAN.md and a `10-17-SUMMARY.md` (written 2026-09-07 22:31, committed
alongside `7b47d67`). Its two rows are both closed:

- **`10-17 T1/T3` is green**, unchanged since 2026-09-07: the pre-push audit greps re-run clean (0
  keys, 0 personal emails, 0 tracked worktree paths; the single tracked `.mat` is `tiny_v73.mat`,
  the committed synthetic fixture, not dataset). The push happened, CI has now run 28 times (was 24
  on 2026-09-07), `readme-policy --self-test` is green, and `10-launch-evidence.md` /
  `10-first-ci-run-evidence.md` record it.
- **`10-17 T2` is now green**, closed 2026-09-08 against the user's `private-push` decision in
  commit `710e729`. See the closure note on the Per-Task Verification Map above and "Validation
  Audit 2026-09-08" below for the full evidence chain. **This audit does not close it by inference
  from `10-17-SUMMARY.md` existing** - it is closed against the user's own recorded checkpoint
  answer, cited by commit, cross-checked against a live `gh repo view` re-read.

The `*SUMMARY*` glob defect described here on 2026-09-07 is real and **still live today** - it is a
property of the glob pattern, not of any single day's file count, so more files landing does not fix
it. The bare `*SUMMARY*` glob still over-counts: it now returns **18** (grep -ci match count),
because it still counts `10-03a-RECONCILIATION-SUMMARY.md` alongside all 17 real plan summaries
(on 2026-09-07 this was 16 real summaries + 1 non-plan artifact = 17; today it is 17 + 1 = 18, since
`10-17-SUMMARY.md` landed in the meantime). The correct pattern remains `10-[0-9][0-9]-SUMMARY.md`,
which today gives **17**, matching `ROADMAP.md`'s own
`10. v1 Real-Data Closed Loop & Launch | v1 | 17/17 | Complete | 2026-09-08` row and `STATE.md`'s
`Phase 10 complete`. Anyone reconciling phase completion must keep using the anchored pattern, not
the bare glob; the earlier miscount (`fb778e7`) is exactly the failure mode of trusting the bare
glob, and it would recur today if `18` were read as "18 plan summaries."

### Gaps found outside the map, and filled

The seed's map covers the 17-plan set. It does not cover the demo-polish commits that landed after
the 10-17 wave (`037a252`..`cd87d6f`), and two channel types shipped there with no test file at all.
Both are now covered - see "Post-10-17 gap fill" above. `WebgridView.swift` (281 lines, SwiftUI) and
`Apps/CortexMac/*` remain manual-only: they are view and app-target code, consistent with how this
phase has treated GUI throughout. `fit_baseline_decoders.py` stays manual-only under the D-07/D-21
tier split - it needs the dataset, and CI never trains.

### Flagged for the maintainer, not fixed here

`TargetChannel.swift:28` declares `public final class TargetChannel: Sendable` without
`nonisolated`, while both sibling channels declare it. Under the package's
`.defaultIsolation(MainActor.self)` that silently makes the whole channel MainActor-isolated,
contradicting its own "lock-free latest-value channel" header. It is not a live defect (its only
call site is already `@MainActor`) and it was left untouched under the read-only-implementation
constraint. It becomes real the moment a render-thread caller reads it. Logged to
`deferred-items.md`. **Re-confirmed still unfixed and still correct 2026-09-08:** `swift test
--package-path Packages/CortexRender` was re-run this pass and the `TargetChannel`/`SelectionChannel`
suites both still pass (see "Validation Audit 2026-09-08" below); `git log` shows no commit touching
either file since `d400947` (2026-09-07), so the flag and its two mutation kill rates (85.7% / 90.9%)
are unchanged and not re-measured.

---

## Validation Audit 2026-09-08

Scope: three gaps in the 2026-09-07 map, assigned by the orchestrator. Nothing below was inferred
from a SUMMARY file; every result is a command re-run on this machine today, 2026-09-08. This trail
is appended after, not written over, the 2026-09-07 trail above; the two subsections that were
factually stale (the `10-17 T2` row and "Phase 10 is 16/17") were corrected in place where they live,
with a forward pointer to here, and are cross-referenced from "Gaps closed" below.

| Metric | Count |
|--------|-------|
| Gaps assigned | 3 |
| Resolved | 3 |
| Escalated | 0 |
| Rows in the per-task map | 35 (unchanged) |
| Green (command run, exit 0) | 33 (was 32; `10-17 T2` newly closed) |
| Evidence (human-run, dataset-gated) | 2 (unchanged) |
| Outstanding | 0 (was 1) |
| Regressions found vs. 2026-09-07 | 0 |

### What was run

| Command | Result | vs. 2026-09-07 |
|---------|--------|-----------------|
| `uv sync --project Decoder --extra dev` | resolved 53 packages, checked 32 | unchanged |
| `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` | 289 passed, 10 deselected | unchanged |
| `swift test --package-path Packages/CortexReFIT` | 32 tests, 5 suites, exit 0 | unchanged |
| `swift test --package-path Packages/CortexCore` | 15 tests, 1 suite, exit 0 | unchanged |
| `swift test --package-path Packages/CortexDecoder` | 25 tests, 5 suites, exit 0 | unchanged |
| `swift test --package-path Packages/CortexBCIHID` | 24 tests, 4 suites, exit 0 | unchanged |
| `swift test --package-path Packages/CortexRender` | 48 tests, 10 suites, exit 0 (`TargetChannel` and `SelectionChannel` suites both pass) | unchanged |
| `swift test --package-path Packages/CortexDemo` | 58 tests, 8 suites, exit 0 | unchanged |
| 12 gate scripts (11 `*-policy.sh` + `honesty-sweep.sh`), each plain + `--self-test` | 24/24 exit 0 | unchanged |
| `readme-policy.sh --self-test \| grep -c 'PASS \['` | 19 | unchanged |
| `readme-policy.sh --self-test \| grep 'corpus/'` | 8 lines, 8 PASS, 0 FAIL | unchanged |
| `swift run --package-path Packages/CortexDemo CortexSeamBSmoke` | 256 frames / 225 windows; `cursor_updates == pointer_reports_encoded == windows_completed == 225` | unchanged |
| `CortexSeamBSmoke --frames 8` | exit 133 (`Precondition failed: windows_completed is 0 after 8 accepted frames`) | unchanged |
| `CortexSeamBSmoke --tamper` | exit 1 (`AES-GCM open FAILED CLOSED at seq 128`) | unchanged |
| `Packages/CortexDemo/.bench/glass_to_glass_real.json` inspection | no `passed`, no `budget_ns`, `frame_period_ns == 8333333` | unchanged |
| `python3 Tools/scripts/check_refit_uplift.py` | exit 0, `refit_bps=0.3744 >= raw_bps=0.1609` | unchanged |
| `swiftlint --strict` | 0 violations, 119 files | unchanged |
| `swiftformat --lint .` | 0/121 need formatting, 19 skipped | unchanged |
| `gh api repos/D0NMEGA/Cortex/actions/runs --jq '.total_count'` | **28** | **+4** since 2026-09-07 (was 24); new runs `710e729`, `7089692`, `7b47d67`, `3a5054e` all `success` |
| `gh repo view --json isPrivate,visibility` | `{"isPrivate":true,"visibility":"PRIVATE"}` | unchanged |
| `git status --short` | 1 line: `10-RECORDS.md` modified (uncommitted local append from an unrelated `donny-tools verify gate` run - not a code or evidence artifact, not touched by this pass, out of scope for these 3 gaps) | new; noted, not acted on |

No mutation-testing step applies to this pass: no new test file was written. GAP 1 and GAP 2 are
documentation reconciliation against evidence already on disk and on GitHub, not missing test
coverage, and GAP 3 is re-execution of existing commands. The "Post-10-17 gap fill" mutation kill
rates recorded 2026-09-07 (TargetChannel 85.7%, SelectionChannel 90.9%, both above the 80% bar) are
carried forward unchanged, confirmed by `git log` showing no commit touching either source file since
`d400947`.

### Gaps closed

1. **`10-17 T2 (D-18)` row.** Was `⬜ outstanding`. Closed to `✅ green` against commit `710e729`
   (the user's recorded `private-push` decision: push, leave visibility unchanged) and a fresh
   `gh repo view` read today (`{"isPrivate":true,"visibility":"PRIVATE"}`). **Closed on the user's
   decision, recorded at a blocking checkpoint - not closed by an agent.** See the closure note on
   the Per-Task Verification Map above.
2. **"Phase 10 is 16/17" section.** Was false: `10-17-SUMMARY.md` now exists (written 2026-09-07
   22:31, committed in `7b47d67`), and the phase is 17/17, matching `ROADMAP.md`'s own
   `10. v1 Real-Data Closed Loop & Launch | v1 | 17/17 | Complete | 2026-09-08` row and `STATE.md`'s
   `Phase 10 complete`. Rewritten in place above under its own heading; the `*SUMMARY*` glob-miscount
   warning is preserved and re-verified still live (bare glob now over-counts to 18, anchored pattern
   `10-[0-9][0-9]-SUMMARY.md` correctly gives 17).
3. **Stale map commands.** No command in the map had been re-executed since 2026-09-07 at the start
   of this pass, and 13 commits had landed since (`96168ba` .. `3a5054e`, `git log 9861c28..HEAD`).
   Every row in "What was run" above was re-executed today; all match the 2026-09-07 results or
   improve on them (CI run count 24 -> 28), and none regressed.

### Escalated

None. No implementation defect was found in this pass; nothing needed a fix outside
`10-VALIDATION.md` itself.
