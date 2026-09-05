---
phase: 10
slug: v1-real-data-closed-loop-launch
status: draft
nyquist_compliant: false
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

Seeded at SC granularity. The planner MUST replace each row with concrete task IDs and keep the
assertion and negative control columns intact.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD SC#1a | TBD | TBD | RD-07 | - | Gains fit from real residuals, not defaults | unit | `swift test --package-path Packages/CortexReFIT` (KalmanConstantsTests asserts header `noise source = indy-heldout`) | ❌ W0 | ⬜ pending |
| TBD SC#1b | TBD | TBD | RD-07 | - | Re-fit gain Schur-stable, zero position rows preserved | unit | `swift test --package-path Packages/CortexReFIT` (existing invariants) | ✅ | ⬜ pending |
| TBD SC#1c | TBD | TBD | RD-07 | T-10-01 | Real-data ablation artifact is provenance-bound; **no assertion on sign or magnitude (D-09)** | gate | `./Tools/scripts/refit-real-policy.sh && ./Tools/scripts/refit-real-policy.sh --self-test` | ❌ W0 | ⬜ pending |
| TBD SC#1d | TBD | TBD | RD-07 | - | Gain and smoothing reported per arm (Willett confound) | schema | `uv run --project Decoder pytest Decoder/tests/test_real_replay_schema.py -q` | ❌ W0 | ⬜ pending |
| TBD SC#1e | TBD | TBD | RD-07 | - | Synthetic Phase-7 invariant still guards filter code | gate | byte-diff `refit_bps.json` after `--smoke`; `python3 Tools/scripts/check_refit_uplift.py` | ✅ | ⬜ pending |
| TBD SC#1f | TBD | TBD | RD-07 | - | Honest gap stated with each reference's measurement condition | gate | `./Tools/scripts/readme-policy.sh --self-test` | ✅ | ⬜ pending |
| TBD SC#2a | TBD | TBD | RD-08 | T-10-02 | NDT1 genuinely in the loop; no silent decode fallback | unit | `swift test --package-path Packages/CortexDemo` (seqLen derived from model, not source default) | ❌ W0 | ⬜ pending |
| TBD SC#2c | TBD | TBD | RD-08 | - | Hit-independent proxy present so a zero is interpretable (D-11) | schema | `uv run --project Decoder pytest Decoder/tests/test_real_replay_schema.py -q` | ❌ W0 | ⬜ pending |
| TBD SC#2e | TBD | TBD | RD-08 | T-10-03 | Seam B decrypts, decodes and orders every frame; fails closed on tamper | smoke | Seam B headless smoke (exit 0 skip when export absent) | ❌ W0 | ⬜ pending |
| TBD SC#2f | TBD | TBD | RD-08 | - | Two seams distinctly labeled; Seam B not presented as the Phase-8 number | schema | `uv run --project Decoder pytest Decoder/tests/test_real_replay_schema.py -q` | ❌ W0 | ⬜ pending |
| TBD SC#3a | TBD | TBD | RD-09 | - | No synthetic-derived number presented as real-data result | gate | `./Tools/scripts/honesty-sweep.sh && ./Tools/scripts/honesty-sweep.sh --self-test` | ❌ W0 | ⬜ pending |
| TBD SC#3b | TBD | TBD | RD-09 | - | Superseded evidence carries a forward banner | gate | `./Tools/scripts/honesty-sweep.sh` | ❌ W0 | ⬜ pending |
| TBD SC#3c | TBD | TBD | RD-09 | - | Methodology label no longer names photodiode as a scheduled phase | unit | `swift test --package-path Packages/CortexDemo` (GlassToGlassTimerTests verbatim string) | ✅ | ⬜ pending |
| TBD SC#4a | TBD | TBD | RD-10 | - | `photodiode` / flat `24.7` no longer required | gate | `./Tools/scripts/readme-policy.sh --self-test` | ✅ | ⬜ pending |
| TBD SC#4b | TBD | TBD | RD-10 | T-10-04 | Retired-context `24.7` passes; achieved-context `24.7` fails | gate | `./Tools/scripts/readme-policy.sh --self-test` (both directions) | ✅ | ⬜ pending |
| TBD SC#4c | TBD | TBD | RD-10 | - | D-14 provenance triple required | gate | `./Tools/scripts/readme-policy.sh --self-test` (three strip controls) | ✅ | ⬜ pending |
| TBD SC#4d | TBD | TBD | RD-10 | - | Every pre-existing control still bites; count 9 -> >=14 | gate | `./Tools/scripts/readme-policy.sh && ./Tools/scripts/readme-policy.sh --self-test` | ✅ | ⬜ pending |
| TBD SC#5a | TBD | TBD | RD-10 | - | LAT-01..LAT-08 preserved verbatim | gate | `./Tools/scripts/honesty-sweep.sh` | ❌ W0 | ⬜ pending |
| TBD SC#5b | TBD | TBD | RD-10 | - | ADR-0003 exists, correct headings, indexed | gate | `./Tools/scripts/honesty-sweep.sh` | ❌ W0 | ⬜ pending |
| TBD SC#5c | TBD | TBD | RD-10 | - | Honest-gates table reflects the new boundary | gate | `./Tools/scripts/readme-policy.sh --self-test` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Test infrastructure exists on both sides. The gaps are fixtures, gates, and one missing seam.

- [ ] `Tools/scripts/refit-real-policy.sh` + `--self-test` (5 controls), structurally copied from `decoder-policy.sh` - SC#1c, SC#1d
- [ ] `Tools/scripts/honesty-sweep.sh` + `--self-test` - SC#3a, SC#3b, SC#5a, SC#5b
- [ ] `Decoder/tests/test_real_replay_schema.py`, copying `test_metrics_schema.py`'s guard-split-marker self-check verbatim so the module cannot grow a measured-value assertion - SC#1d, SC#2c, SC#2f
- [ ] A committed **synthetic** export fixture (few hundred bins, correct dtypes + sidecar) so the Swift reader and schema test run on a clean clone with no dataset. The D-20 `tiny_v73.mat` pattern applied to the export. **Without it every export-touching test is dataset-gated and CI covers none of it.**
- [ ] The rolling 32-bin window accumulator between the IPC consumer and `SpikeInputBuffer`, with its own unit test
- [ ] `readme-policy.sh`'s new `require_marker_on_matching_lines` helper + 5 new self-test cases + updated `write_clean_readme`
- [ ] Three new `ci.yml` steps: real-data provenance gate, honesty sweep, Seam B smoke - each with its `--self-test` alongside, matching the existing seven policy-gate steps
- [ ] `10-HUMAN-UAT.md` from the `09-HUMAN-UAT.md` template, for the iPad-M4 rows carried forward
- [ ] The committed true-cursor ceiling script, run and its number published **before** the decoded run is scored

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
| iPad Pro M4 canonical captures | RD-10 | Hardware absent | `10-HUMAN-UAT.md`, **never auto-approved**, all value fields `not measured` |
| "CI is green" | all | The workflow has never run | Capture local transcripts of every gate + `--self-test`; state in README that the workflow has not yet executed on a runner |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s (quick) / < 4min (full)
- [ ] Every new gate ships its `--self-test` in the same commit (repo-standing rule)
- [ ] No gate asserts the sign or magnitude of a real-data result (D-09)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
