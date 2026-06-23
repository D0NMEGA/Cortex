---
phase: 8
slug: apple-bci-hid-integration-distribution-v0-ship
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-23
updated: 2026-06-23
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded at plan-time from `08-RESEARCH.md` § Validation Architecture. The Per-Task map is completed by the planner once PLAN.md task IDs exist (done 2026-06-23).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift `swift test` / `xcodebuild test` (app + packages) · shell CI grep-gates (`Tools/scripts/*.sh` idiom) · deterministic Swift bench (`CortexReFITBench`, `CortexDemoBench`) · Python `uv … --extra dev` pytest (decoder, only if touched — not touched this phase) |
| **Config file** | `Package.swift` per package · `project.yml` (XcodeGen) · existing `Tools/scripts/hotpath-policy.sh` / `render-policy.sh` / `validate-privacy-manifest.sh` + the new `hid-surface-policy.sh` / `notarize-policy.sh` / `match-policy.sh` / `bps-policy.sh` / `readme-policy.sh` |
| **Quick run command** | `swift test --package-path Packages/<pkg>` + `bash Tools/scripts/<gate>-policy.sh && bash Tools/scripts/<gate>-policy.sh --self-test` |
| **Full suite command** | `swift test` across packages (CortexBCIHID, CortexDemo, CortexReFIT, CortexDecoder, …) + all `Tools/scripts/*-policy.sh` gates + `--self-test`s + the deterministic BPS + glass-to-glass bench --smoke runs |
| **Estimated runtime** | ~90-150 seconds (no live Apple network calls — those are the 3 gated HUMAN-UAT checkpoints) |

---

## Sampling Rate

- **After every task commit:** Run the relevant `swift test` target and/or the structural `*-policy.sh` gate (+ `--self-test`) for the files touched
- **After every plan wave:** Run the full suite (all swift tests + all policy gates + self-tests + the BPS + glass-to-glass bench --smoke)
- **Before `/gsd-verify-work`:** Full automated suite must be green; the 3 Manual-Only gates (Plan 07) presented (never auto-approved)
- **Max feedback latency:** ~150 seconds

---

## Per-Task Verification Map

> Task IDs are `8-<plan>-<task>`. Every automated requirement maps to ≥1 task with an `<automated>` verify; no 3 consecutive tasks without an automated check (this map satisfies the Nyquist contract — every task below carries an `<automated>` command).

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 8-01-01 | 01 | 1 | SYS-01/05 | T-08-01-01 | 5 report structs ported with exact byte layouts; signed Int8 pointer deltas not lost | unit | `swift test --package-path Packages/CortexBCIHID --filter BCIHIDReportTests` + `… --filter BCIHIDDescriptorTests` | ❌ W0 | ⬜ pending |
| 8-01-02 | 01 | 1 | SYS-01/02/05 | T-08-01-02/03 | virtual.device + keychain-access-groups declared-but-inert; live HID behind `#if CORTEX_HID_LIVE`; SMAppService scaffold | build + plutil | `swift build --package-path Packages/CortexBCIHID && plutil -lint Apps/Cortex{Mac,iOS,Daemon}/Cortex.entitlements Apps/Cortex{Mac,iOS}/Info.plist` | ❌ W0 | ⬜ pending |
| 8-01-03 | 01 | 1 | SYS-01/05/06 | T-08-01-04 | structural gate asserts descriptor bytes + struct names + entitlement key + gated instantiation; self-test bites | grep + self-test | `bash Tools/scripts/hid-surface-policy.sh && bash Tools/scripts/hid-surface-policy.sh --self-test` | ❌ W0 | ⬜ pending |
| 8-02-01 | 02 | 3 | SYS-03/04 | T-08-02-01/02/03 | Scan-Info output → Item-Selection/Pointer intent; instrumented log per cycle; deterministic intent | unit | `swift test --package-path Packages/CortexBCIHID --filter ScanInfoRoundTripTests` | ❌ W0 | ⬜ pending |
| 8-02-02 | 02 | 3 | SYS-03/04 | T-08-02-02 | the round-trip test is gated in CI (full package suite, no filter) | grep | `grep -n "CortexBCIHID" .github/workflows/ci.yml` | ✅ (ci.yml) | ⬜ pending |
| 8-03-01 | 03 | 5 | SYS-06 | T-08-03-01/05 | decoder + Kalman genuinely in loop (NeuralDecoder.decode + KalmanFilter.step present); no Lissajous; webgrid HIT | unit | `swift test --package-path Packages/CortexDemo --filter ClosedLoopPipelineTests` | ❌ W0 | ⬜ pending |
| 8-03-02 | 03 | 5 | PERF-04 | T-08-03-02/03 | software-timed uses targetPresentationTimestamp (not targetTimestamp); verbatim label embedded; p99<25ms M5 corroborating | unit + bench | `swift test --package-path Packages/CortexDemo --filter GlassToGlassTimerTests && swift run --package-path Packages/CortexDemo CortexDemoBench --smoke` | ❌ W0 | ⬜ pending |
| 8-03-03 | 03 | 5 | SYS-06/PERF-04 | T-08-03-01/04 | CortexMac GUI drives ClosedLoopPipeline (not Lissajous) + surfaces round-trip log; CI builds CortexDemo | build + grep | `swift build --package-path Packages/CortexDemo && grep -n "ClosedLoopPipeline" Apps/CortexMac/ContentView.swift` | ❌ W0 | ⬜ pending |
| 8-04-01 | 04 | 4 | DIST-01/02/03 | T-08-04-01/02/03/04 | notarytool+stapler (no altool); appstore match + https git_url + no file:// + creds from ENV | parse + grep | `ruby -c fastlane/Fastfile && ruby -c fastlane/Matchfile && bash -n Tools/scripts/notarize.sh && ! grep -rn altool Tools/scripts/notarize.sh fastlane/Fastfile` | ❌ W0 | ⬜ pending |
| 8-04-02 | 04 | 4 | DIST-01/02/03 | T-08-04-04/05 | structural gates verify the pipeline; live submit kept out of CI; self-tests bite | grep + self-test | `bash Tools/scripts/notarize-policy.sh --self-test && bash Tools/scripts/match-policy.sh --self-test` | ❌ W0 | ⬜ pending |
| 8-05-01 | 05 | 2 | PERF-01 | T-08-05-01 | B = max(0, log2(N)*(Sc-Si)/t), N=900; mandatory clamp returns 0 on net-negative | unit | `swift test --package-path Packages/CortexReFIT --filter WebgridBPSTests` | ❌ W0 | ⬜ pending |
| 8-05-02 | 05 | 2 | PERF-01/02/03 | T-08-05-02/03/04/05 | bench emits Webgrid BPS + Fitts-TP; honest caveat + gap to 8.5; Phase-7 refit_bps.json guard intact | bench + diff | `swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke && diff Packages/CortexReFIT/.bench/refit_bps.json .planning/phases/07-refit-kalman-closed-loop-recalibration/refit_bps.json` | ❌ W0 | ⬜ pending |
| 8-05-03 | 05 | 2 | PERF-01 | T-08-05-01/03 | BPS gate asserts the clamped formula + run-twice byte-identical; self-test bites | grep + determinism | `bash Tools/scripts/bps-policy.sh && bash Tools/scripts/bps-policy.sh --self-test` | ❌ W0 | ⬜ pending |
| 8-06-01 | 06 | 6 | DIST-04/PERF-02 | T-08-06-01/02/04 | README has commitments + rejected-alternatives + dual claim + every gate disclosure; no secret leak | grep | `grep -qi "software-timed" README.md && grep -qi "rejected" README.md && grep -qi "24.7" README.md` | ❌ W0 | ⬜ pending |
| 8-06-02 | 06 | 6 | DIST-04 | T-08-06-02/03 | README gate asserts required disclosures + no-leak; self-test bites | grep + self-test | `bash Tools/scripts/readme-policy.sh && bash Tools/scripts/readme-policy.sh --self-test` | ❌ W0 | ⬜ pending |
| 8-07-01 | 07 | 7 | SYS-01/02, DIST-01/02/03, PERF-04 | T-08-07-01/02/03/04 | 3 never-auto-approve runbooks authored; each gate presented (deferred-with-paused-state or verified-with-evidence) | checkpoint + file | `test -f .planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/08-HUMAN-UAT.md && grep -qi "never auto-approve" 08-HUMAN-UAT.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Nyquist continuity:** Every task (8-01-01 … 8-07-01) carries an `<automated>` command — there is no run of 3 consecutive tasks without an automated check. The `❌ W0` File-Exists markers are Wave-0 dependencies (the test/script/source the task itself creates); each is created within its own task, so no separate Wave-0 plan is required — the first task of each plan creates its own test surface alongside the implementation (TDD where `tdd="true"`).

---

## Wave 0 Requirements

> All "Wave 0" infrastructure below is created INLINE by the first task of the owning plan (TDD-style: the test/gate lands with the code), so there is no separate Wave-0 plan. The structural gates are the Cortex `*-policy.sh` idiom (trap pre-armed + negative-control self-test).

- [x] `Tools/scripts/hid-surface-policy.sh` — structural gate (Usage Page `0x60`, 5 report-struct names, `com.apple.developer.hid.virtual.device`, `#if CORTEX_HID_LIVE` guard + self-test) — **Plan 01 Task 3**
- [x] `Tools/scripts/notarize-policy.sh` — `notarytool submit` + `stapler staple` present, ZERO `altool` + self-test — **Plan 04 Task 2**
- [x] `Tools/scripts/match-policy.sh` — `type("appstore")` + private `https://` git_url + no `file://` + `MATCH_PASSWORD` from ENV + self-test — **Plan 04 Task 2**
- [x] `Tools/scripts/bps-policy.sh` — clamped `max(0, log2(N)*(Sc-Si)/t)` present + run-twice byte-identical + self-test — **Plan 05 Task 3**
- [x] `Tools/scripts/readme-policy.sh` — required disclosure phrases present + no secret/PII leak + self-test — **Plan 06 Task 2**
- [x] BCI HID report-struct round-trip unit tests (encode/decode of all 5 structs) — **Plan 01 Task 1** (`BCIHIDReportTests`)
- [x] In-app host-harness round-trip test (Scan-Info output → Item-Selection/Pointer input, instrumented log assertion) — **Plan 02 Task 1** (`ScanInfoRoundTripTests`)
- [x] Webgrid BPS unit tests (the clamp) — **Plan 05 Task 1** (`WebgridBPSTests`)
- [x] Glass-to-glass timer tests (targetPresentationTimestamp + verbatim label) — **Plan 03 Task 2** (`GlassToGlassTimerTests`)
- [x] Closed-loop pipeline tests (decoder genuinely in loop) — **Plan 03 Task 1** (`ClosedLoopPipelineTests`)

*Existing infrastructure (`hotpath-policy.sh` / `render-policy.sh` idiom, `CortexReFITBench`, swift test) covers the rest.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions | Plan/Gate |
|----------|-------------|------------|-------------------|-----------|
| Live `notarytool submit` + `fastlane match` + TestFlight upload | DIST-01/02/03 | Needs paid Apple Developer Program enrollment + ASC `.p8` key (not active) | Runbook (08-HUMAN-UAT.md Gate 1): set ASC_* + MATCH_PASSWORD ENV; run `fastlane beta`; confirm notarytool Accepted + `stapler validate` + TestFlight build visible; never auto-approve | Plan 07, Gate 1 |
| iPad Pro M4 canonical software-timed glass-to-glass latency capture | PERF-04 | Free team can't provision iPad headless; M5 Pro is corroborating-canonical (D-08) | Runbook (08-HUMAN-UAT.md Gate 2): build to a provisioned iPad Pro M4 via Xcode GUI; run the software-timed bench with the real `update.targetPresentationTimestamp`; record p99 < 25ms; never auto-approve | Plan 07, Gate 2 |
| On-device `IOHIDUserDevice`/`HIDVirtualDevice` registration as Switch Control HID provider | SYS-01/02 | Requires `com.apple.developer.hid.virtual.device` activation (managed profile) + Accessibility grant + provisioned session | Runbook (08-HUMAN-UAT.md Gate 3): activate the entitlement; build with `CORTEX_HID_LIVE`; grant Accessibility; instantiate the virtual device; confirm cursor moves under Switch Control; never auto-approve | Plan 07, Gate 3 |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (each task creates its own test/gate inline)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (created inline by the owning plan's first task)
- [x] No watch-mode flags
- [x] Feedback latency < 150s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planner-complete 2026-06-23 (Per-Task map filled with real task IDs; the 3 Manual-Only gates routed to Plan 07's never-auto-approve checkpoint).
