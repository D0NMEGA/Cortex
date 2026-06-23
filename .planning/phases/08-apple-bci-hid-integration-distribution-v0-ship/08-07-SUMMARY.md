---
phase: 08-apple-bci-hid-integration-distribution-v0-ship
plan: 07
subsystem: validation-gates
tags: [human-uat, wire-and-gate, never-auto-approve, testflight, glass-to-glass, hid-registration, dist-01, dist-02, dist-03, perf-04, sys-01, sys-02, honesty-ethos, checkpoint]

# Dependency graph
requires:
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship (08-04)
    provides: fastlane :beta + notarize.sh (the Gate-1 live-submission driver) + notarize/match policy gates
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship (08-03)
    provides: CortexDemoBench + GlassToGlassTimer (targetPresentationTimestamp) — the Gate-2 latency driver; M5-Pro corroborating p99 ≈ 8.32ms
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship (08-01)
    provides: VirtualDeviceGate (#if CORTEX_HID_LIVE) + declared-but-inert virtual.device entitlement + hid-surface-policy.sh — the Gate-3 registration driver/proxy
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship (08-06)
    provides: README gate-disclosure table the runbook mirrors
provides:
  - 08-HUMAN-UAT.md — the 3 never-auto-approve runbooks (live TestFlight / iPad-M4 canonical latency / on-device HID registration), each with status + flip procedure + evidence slot + never-auto-approve note + recorded disposition
  - The recorded human disposition (2026-06-23): all 3 gates DEFERRED (prerequisites unavailable), none auto-approved — the documented v0 wire-and-gate terminal state
affects: [phase-08-verification, milestone-v0-ship, 09-photodiode-rig, 10-v1-launch]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Never-auto-approve HUMAN-UAT runbook: status + flip procedure (drives an already-built artifact) + evidence slot + explicit never-auto-approve note; disposition recorded as DEFERRED-with-paused-state or VERIFIED-with-captured-evidence (mirrors 06-HUMAN-UAT.md / sc2-evidence.md)"

key-files:
  created:
    - .planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/08-HUMAN-UAT.md
  modified: []

key-decisions:
  - "All 3 gates DEFERRED by human disposition (2026-06-23) — no paid Apple Developer enrollment + ASC .p8 (Gate 1), no provisioned iPad Pro M4 (Gate 2), no managed hid.virtual.device entitlement + Accessibility grant (Gate 3). None auto-approved despite auto_advance=true (the gsd-device-checkpoints-never-auto-approve memory + T-08-07-01)."
  - "v0 is fully runnable + credible TODAY on the free Personal team; the gates flip ready→done the day their prerequisites land, with NO further code change."

patterns-established:
  - "Wire-and-gate closing move: the gated half of every account/device/paid requirement is a presented (never auto-approved) checkpoint, not a fabricated green check."

requirements-completed: [SYS-01, SYS-02, DIST-01, DIST-02, DIST-03, PERF-04]  # structural/autonomous half complete + gated live half presented-and-tracked (deferred); live halves remain outstanding UAT in 08-HUMAN-UAT.md

# Metrics
duration: ~5min
completed: 2026-06-23
---

# Phase 8 Plan 07: Never-Auto-Approve HUMAN-UAT Runbooks Summary

**The 3 v0 gates (live TestFlight, iPad-M4 canonical latency, on-device HID registration) authored as never-auto-approve runbooks and presented — all 3 DEFERRED by human disposition, none fabricated.**

## Performance

- **Duration:** ~5 min (autonomous authoring) + human-disposition checkpoint
- **Completed:** 2026-06-23
- **Tasks:** 1 (checkpoint:human-verify — autonomous half + presented gates)
- **Files modified:** 1 created (08-HUMAN-UAT.md), updated with dispositions

## Accomplishments
- Authored `08-HUMAN-UAT.md` — the 3 never-auto-approve runbooks, each driving an already-built, CI-green artifact (Plans 01-06) and gated only on its live/paid/device prerequisite.
- Presented all 3 gates for human disposition (NOT auto-approved despite `auto_advance=true`).
- Recorded disposition: **all 3 DEFERRED** (prerequisites unavailable this session); paused state recorded per gate; no live lane run, no canonical number or HID registration fabricated.

## Task Commits

1. **Task 1 (autonomous half): Author the 3 never-auto-approve HUMAN-UAT runbooks** - `cfdc885` (docs)
2. **Disposition recorded (DEFERRED ×3) into 08-HUMAN-UAT.md** - committed with phase-completion docs

## Files Created/Modified
- `.planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/08-HUMAN-UAT.md` - the 3 runbooks (Gate 1 live TestFlight DIST-01/02/03; Gate 2 iPad-M4 canonical software-timed latency PERF-04; Gate 3 on-device Switch Control HID registration SYS-01/02), each with status + flip procedure + evidence slot + never-auto-approve note + recorded DEFERRED disposition.

## Decisions Made
- **All 3 gates DEFERRED.** Prerequisites not available: paid Apple Developer Program enrollment + ASC `.p8` (Gate 1), a provisioned iPad Pro M4 (Gate 2), the managed `com.apple.developer.hid.virtual.device` entitlement + Accessibility grant (Gate 3). The corroborating tier stands on its own (M5-Pro software-timed glass-to-glass p99 ≈ 8.32 ms; the structural CI policy gates) and is never substituted for a gated canonical number.
- **None auto-approved** despite `auto_advance=true` — auto-approving any gate would forge a load-bearing credibility claim (T-08-07-01; the `gsd-device-checkpoints-never-auto-approve` project memory). The disposition was made by explicit human decision.
- **Phase 8 marked complete** by human decision: the automated half (Plans 01-06, 59 tests + 5 policy gates + benches, all green per 08-VERIFICATION.md) is done; the 3 gated live halves are tracked as outstanding UAT (status: partial) in 08-HUMAN-UAT.md and surface in `/gsd-progress` until flipped.

## Deviations from Plan
None - plan executed exactly as written (autonomous authoring + presented checkpoint; disposition decided by human).

## Authentication Gates
All 3 gates are account/device/paid-gated and DEFERRED:
- **Gate 1** (DIST-01/02/03): paid Apple Developer Program enrollment + ASC `.p8` + private certs repo + `MATCH_PASSWORD`.
- **Gate 2** (PERF-04): provisioned iPad Pro M4 (iPadOS 26).
- **Gate 3** (SYS-01/02): managed `hid.virtual.device` entitlement + Accessibility grant + provisioned device session + the IOKit C-interop bridge.

## Known Stubs
None for the runbook itself. The live halves are intentionally inert until their prerequisites land (the wire-and-gate doctrine); each runbook documents the exact ready→done flip with no further code change.

## Issues Encountered
None.

## Next Phase Readiness
- v0 milestone code is shipped, CI-green, and credible today on the free Personal team.
- The 3 outstanding gates flip ready→done when enrollment / a provisioned iPad / the managed entitlement land — surfaced in `/gsd-progress` and `/gsd-audit-uat`.
- Phase 9 (photodiode rig) and Phase 10 (v1 launch) are the canonical-claim path; Gate 2's software-timed tier sets up the v1 photodiode glass-to-glass measurement.

## Self-Check: PASSED

---
*Phase: 08-apple-bci-hid-integration-distribution-v0-ship*
*Completed: 2026-06-23*
