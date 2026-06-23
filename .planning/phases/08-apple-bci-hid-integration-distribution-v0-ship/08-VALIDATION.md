---
phase: 8
slug: apple-bci-hid-integration-distribution-v0-ship
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-23
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded at plan-time from `08-RESEARCH.md` § Validation Architecture. The Per-Task map is completed by the planner once PLAN.md task IDs exist.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift `swift test` / `xcodebuild test` (app + packages) · shell CI grep-gates (`Tools/scripts/*.sh` idiom) · deterministic Swift bench (`CortexReFITBench`) · Python `uv … --extra dev` pytest (decoder, only if touched) |
| **Config file** | `Package.swift` per package · `project.yml` (XcodeGen) · existing `Tools/scripts/hotpath-policy.sh` / `render-policy.sh` / `validate-privacy-manifest.sh` |
| **Quick run command** | `swift test --package-path Packages/CortexReFIT` + `bash Tools/scripts/<new-hid/notarize/match/bps>-policy.sh` |
| **Full suite command** | `swift test` across packages + all `Tools/scripts/*-policy.sh` gates + deterministic BPS harness run-twice diff |
| **Estimated runtime** | ~60-120 seconds (no live Apple network calls — those are gated HUMAN-UAT) |

---

## Sampling Rate

- **After every task commit:** Run the relevant `swift test` target and/or the structural `*-policy.sh` gate for the files touched
- **After every plan wave:** Run the full suite (all swift tests + all policy gates + BPS harness)
- **Before `/gsd-verify-work`:** Full automated suite must be green; the 3 Manual-Only gates presented (never auto-approved)
- **Max feedback latency:** ~120 seconds

---

## Per-Task Verification Map

> Filled by the planner once PLAN.md task IDs exist. Every automated requirement below must map to ≥1 task with an `<automated>` verify; no 3 consecutive tasks without an automated check.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 8-01-01 | 01 | 1 | SYS-01/05 | T-08-HID | virtual.device entitlement declared but inert under free signing; no live HID instantiation in demo binary | unit + grep | `swift test --filter BCIHIDReportTests` + `bash Tools/scripts/hid-surface-policy.sh` | ❌ W0 | ⬜ pending |
| … | … | … | (planner completes from § Validation Architecture) | | | | | | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Tools/scripts/hid-surface-policy.sh` — structural gate: Usage Page `0x60`, 5 report-struct names, `com.apple.developer.hid.virtual.device` key, gated-instantiation `#if` guard (+ negative-control self-test)
- [ ] `Tools/scripts/notarize-policy.sh` — assert `notarytool submit` + `stapler staple` present, **zero** `altool` (+ negative-control)
- [ ] `Tools/scripts/match-policy.sh` — assert `type("appstore")` + private `https://` git_url + no `file://` + `MATCH_PASSWORD` from ENV
- [ ] `Tools/scripts/bps-policy.sh` — assert deterministic Webgrid BPS harness exists and run-twice output is byte-identical
- [ ] BCI HID report-struct round-trip unit tests (encode/decode of all 5 structs) — Swift test target
- [ ] In-app host-harness round-trip test (Scan-Info output → Item-Selection/Pointer input, instrumented log assertion)

*Existing infrastructure (`hotpath-policy.sh` idiom, `CortexReFITBench`, swift test) covers the rest.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Live `notarytool submit` + `fastlane match` + TestFlight upload | DIST-01/02/03 | Needs paid Apple Developer Program enrollment + ASC `.p8` key (not active) | Runbook (reuse `sc2-evidence.md` form): run `fastlane beta`, confirm notarytool Accepted + TestFlight build visible; never auto-approve |
| iPad Pro M4 canonical software-timed glass-to-glass latency capture | PERF-04 | Free team can't provision iPad headless; M5 Pro is corroborating-canonical (D-08) | Runbook: build to provisioned iPad via Xcode GUI, run software-timed bench, record p99 < 25ms; never auto-approve |
| On-device `IOHIDUserDevice`/`HIDVirtualDevice` registration as Switch Control HID provider | SYS-01/02 | Requires `com.apple.developer.hid.virtual.device` activation (managed profile) + Accessibility grant + provisioned session | Runbook: enable entitlement, instantiate virtual device, confirm cursor moves under Switch Control; never auto-approve |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
