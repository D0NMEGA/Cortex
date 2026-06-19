---
phase: 01-foundation-2026-toolchain
plan: 07
subsystem: infra
tags: [sc2, shm-open, app-group, entitlements, code-signing, xcode-26, personal-team, mmap, cross-process-ipc, daemon, checkpoint, human-verify]

# Dependency graph
requires:
  - phase: 01-foundation-2026-toolchain
    provides: "cortex_shm.h CORTEX_SHM_NAME (Plan 01), project.yml + CortexMac/CortexDaemon entitlements (Plan 02), PrivacyInfo.xcprivacy (Plan 03), CI-validated source tree (Plan 06)"
provides:
  - "VERIFIED Phase 1 SC#2: cross-process shm_open between CortexMac.app and CortexDaemon, both Personal-Team-signed + App-Group-entitled, inside the App Group container -- committed evidence in sc2-evidence.md"
  - "ShmCheck surface in CortexCore (shm_open + ftruncate + mmap sentinel proof), callable from the Mac app (button) and the daemon (launch)"
  - "CortexDaemon as a standalone runnable executable (type: tool / mh_execute) -- the corrected daemon packaging that can run + carry entitlements"
  - "Closed the deferred Plan 01-02 dynamic xcodebuild smoke (CortexMac + CortexDaemon BUILD SUCCEEDED on Xcode 26.3)"
affects: [phase-02-ipc, phase-08-distribution]

# Tech tracking
tech-stack:
  added:
    - "Xcode 26.3 (17C529) installed via xcodes 2.0.2 (aria2-accelerated); local Personal Team signing (team 57YW6M29S7)"
  patterns:
    - "Non-variadic C shim (cortex_shm_open) so Swift can call a C variadic syscall"
    - "Cross-process mmap sentinel (write magic|pid, read peer pid) as the robust shared-memory proof where Darwin st_ino is degenerate (always 0)"
    - "Daemon as standalone mh_execute (not loadable mh_bundle) so it runs as its own entitled process"

key-files:
  created:
    - "Packages/CortexCore/Sources/CortexCore/ShmCheck.swift (Task 1; upgraded to mmap sentinel proof)"
    - ".planning/phases/01-foundation-2026-toolchain/sc2-evidence.md (committed SC#2 evidence -- PASS)"
  modified:
    - "project.yml (CortexDaemon type: bundle -> tool)"
    - "Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h + cortex_shm.c (cortex_shm_open shim)"
    - "Packages/CortexCore/Sources/CortexCore/CortexCore.swift (String(cString:) deprecation)"
    - "Packages/CortexCore/Package.swift (test target .defaultIsolation(MainActor.self))"
    - "Apps/CortexiOS|CortexMac/Info.plist (xcodegen idempotent sync)"
  deleted:
    - "Apps/CortexDaemon/Info.plist (orphaned after daemon became a tool)"

key-decisions:
  - "SC#2 verified with the ROBUST proof (cross-process mmap sentinel), not the plan's inode comparison -- Darwin POSIX shm fstat returns st_ino=0 in every process, so an inode 'match' is degenerate (0==0)."
  - "CortexDaemon changed from type: bundle to type: tool. A loadable mh_bundle cannot run standalone (cannot execute binary file) nor carry entitlements; D-03's functional requirement (daemon does cross-process shm_open) mandates mh_execute. Resolves the disposition Plan 01-02 deferred to Xcode 26."
  - "Final App-Store daemon packaging (XPC service / launchd helper) deferred to Phase 2 -- a bare command-line tool is not App-Store-distributable."
  - "Did NOT auto-approve the human-verify checkpoint despite workflow.auto_advance=true -- a hardware-gated, evidence-producing SC#2 verification cannot be honestly auto-approved without real evidence."

patterns-established:
  - "Pattern 1: C variadic syscall -> non-variadic shim in CortexCoreC, called from Swift. Reusable for any future C variadic (open, fcntl, ioctl, etc.)."
  - "Pattern 2: shared-memory verification via mmap sentinel (write pid, peer reads pid). Reusable as a Phase 2 IPC smoke test."
  - "Pattern 3: toolchain-deferred verification surfaces real defects -- installing the canonical toolchain (Xcode 26.3) exposed 6 latent issues that CommandLineTools-only development hid."

requirements-completed: [FOUND-02]

# Metrics
duration: ~95min (dominated by Xcode 26.3 ~15GB download/install)
completed: 2026-06-19
---

# Phase 01 Plan 07: SC#2 Manual Runbook — Cross-process shm_open VERIFIED

**Phase 1 Success Criterion #2 is PASSED with committed, reproducible evidence: two Personal-Team-signed, App-Group-entitled Mac binaries (CortexMac.app + the CortexDaemon executable) both `shm_open("/cortex.samples")` inside the App Group container, and data written by one is read by the other — CortexMac.app read the daemon's PID (41220) straight out of the shared region.**

## Performance

- **Duration:** ~95 min (the Xcode 26.3 ~15 GB download/unxip dominated; active work ~25 min)
- **Completed:** 2026-06-19
- **Tasks:** 2/2 (Task 1 ShmCheck surface — done earlier at 2f116bc + upgraded; Task 2 human-verify checkpoint — PASS)
- **Environment:** Apple M5 Pro, macOS 26, Xcode 26.3 (17C529), Swift 6.2.4, Personal Team 57YW6M29S7

## Accomplishments

1. **Installed the canonical toolchain.** Xcode 26.3 via `xcodes` (after clearing a corrupt 81 KB "Unauthorized" `.xip` stub that was short-circuiting the download); added the user's Apple ID → Personal Team `57YW6M29S7`.
2. **Executed the SC#2 runbook and captured PASS evidence** (`sc2-evidence.md`):
   - **daemon ↔ daemon** (automated): run #2 read run #1's PID from `/cortex.samples`.
   - **app ↔ daemon** (plan-required): CortexMac.app read the daemon's PID (41220).
   - App Group container provisioned by macOS `containermanagerd`; both binaries' codesign entitlement audit shows `application-groups` + full chain to Apple Root CA, no sandbox, no deprecated shared-memory exception.

## Deviations / defects surfaced by the real toolchain (Rule 1 / Rule 3 fixes)

Phase 1 (01-01…01-06) was authored on CommandLineTools only; the real Xcode 26.3 exposed and we fixed:

| # | Defect | Severity | Fix | Commit |
|---|--------|----------|-----|--------|
| 1 | `shm_open` variadic → unimportable in Swift | build break | `cortex_shm_open` C shim | 35dc1e8 |
| 2 | `String(cString:)` deprecation ×2 | warning | use `CORTEX_SHM_NAME` directly | 35dc1e8 |
| 3 | test target missing MainActor isolation | test build break | mirror `.defaultIsolation` | 35dc1e8 |
| 4 | Info.plist drift vs xcodegen output | hygiene | commit idempotent plists | 36646c7 |
| 5 | CortexDaemon `type: bundle` can't run/entitle standalone | blocking (SC#2) | `type: tool` (mh_execute) | 5ed2558 |
| 6 | inode proof degenerate on Darwin (st_ino=0) | blocking (credibility) | mmap sentinel proof | ca23b4f |

Also closed in passing: the **deferred Plan 01-02 dynamic xcodebuild smoke** (CortexMac + CortexDaemon `BUILD SUCCEEDED` on Xcode 26.3) and the Plan 01-01/01-02 toolchain-deferral items that were waiting on an Xcode 26 environment.

## Verification

- `swift build` (CortexCore): warning-clean. `swift test`: 3/3 pass.
- `xcodebuild` CortexMac scheme (CortexMac + CortexDaemon, signed): BUILD SUCCEEDED.
- Daemon runs standalone; both binaries dev-signed with App Group entitlement (codesign audit in evidence).
- Cross-process shared memory proven twice (daemon↔daemon, app↔daemon) via mmap sentinel.

## Cross-phase notes

- **Phase 2:** `ShmCheck.swift` is one-shot evidence scaffolding — **remove it** when the real IPC primitive (kqueue + recvmsg + POSIX shm) lands. Also **decide the production daemon packaging** (XPC service vs. launchd helper) for the App Store path; `type: tool` is a Phase-1 placeholder only.
- **Phase 8 (paid enrollment):** repeat this runbook with the iPad target on a real device (on-device App Group needs paid enrollment) — the SC#2 extension deferred per RESEARCH.md Critical Finding #1.
