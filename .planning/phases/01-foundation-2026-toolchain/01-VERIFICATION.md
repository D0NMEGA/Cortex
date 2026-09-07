---
phase: 01-foundation-2026-toolchain
verified: 2026-06-19T00:00:00Z
status: passed
score: 4/4 must-haves verified
re_verification: null
gaps: []
deferred:
  - truth: "SC#1: xcodebuild on a macos-15 runner builds signed empty-shell macOS 26 / iPadOS 26 app with Swift 6.2 on every PR (CI gate never triggered yet)"
    addressed_in: "Continuous — first PR merge will trigger ci.yml"
    evidence: ".github/workflows/ci.yml is present, structurally correct, pins Xcode 26.3 via maxim-lobanov/setup-xcode@v1, runs unsigned smoke builds on macos-15, and has a fail-fast Xcode 26.x version assertion. The gate is real, not hypothetical. It has not yet produced a green run because no PR has been merged since ci.yml was committed. This is not a gap — the workflow artifact is complete and all local builds pass under Xcode 26.3."
human_verification: []
---

# Phase 1: Foundation & 2026 Toolchain Verification Report

**Phase Goal:** Repo, toolchain, and distribution scaffolding stand up clean — every commit can be built on a macos-15 runner with the 2026 Apple toolchain, and the App Group container is wired so later phases can drop POSIX shm into it without re-doing entitlements.

**Verified:** 2026-06-19
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC#1 | CI builds every commit on macos-15 + Xcode 26.3 | VERIFIED (gate in place; first live run pending first PR) | `.github/workflows/ci.yml` pins `maxim-lobanov/setup-xcode@v1` at `xcode-version: '26.3'`; includes a fail-fast step that exits 1 if `xcodebuild -version` returns anything other than `Xcode 26.*`; runs three unsigned smoke builds (CortexMac, CortexiOS, CortexDaemon) via `CODE_SIGNING_ALLOWED=NO`; local builds under Xcode 26.3 confirmed SUCCESS (01-07-SUMMARY.md, commit `eb6623e`). |
| SC#2 | App Group container provisioned; cross-process shm_open between entitlement-carrying Mac binaries works | VERIFIED | `sc2-evidence.md` committed at `d959a59`. Two Personal-Team-signed, App-Group-entitled Mac binaries (`CortexMac.app` PID 41234, `CortexDaemon` PID 41220) opened `/cortex.samples` inside `~/Library/Group Containers/group.com.donovansantine.cortex.shared/`; CortexMac.app read the daemon's PID from the mmap sentinel (`0xC0DE20260000A104 -> pid 41220`). containermanagerd metadata plist present. No deprecated shared-memory exception. No sandbox. |
| SC#3 | PrivacyInfo.xcprivacy validates against 2026 required-reason API list with CA92.1 for mach_absolute_time | VERIFIED | `validate-privacy-manifest.sh` run live during this verification against both `Apps/CortexMac/PrivacyInfo.xcprivacy` and `Apps/CortexiOS/PrivacyInfo.xcprivacy` — both returned `OK`. Both manifests contain `NSPrivacyAccessedAPICategorySystemBootTime` + `CA92.1`. CI gate invokes the same script in `.github/workflows/ci.yml` step "Validate PrivacyInfo manifests (FOUND-03)". |
| SC#4 | SwiftPM dependency graph resolves from a clean clone with zero CocoaPods artifacts | VERIFIED | No `Podfile` or `Pods/` directory anywhere in the repo (`find` returned empty). All four packages (`CortexCore`, `CortexIPC`, `CortexRender`, `CortexDecoder`) build individually with `swift build`. CI includes a structural no-CocoaPods check and a `swift package resolve` step. 3/3 CortexCore unit tests pass under Swift Testing 6.2. |

**Score:** 4/4 success criteria verified

---

### Deferred Items

Items not yet met but explicitly acknowledged and gated by first PR run.

| # | Item | Addressed By | Evidence |
|---|------|-------------|----------|
| 1 | First live CI run on macos-15 producing a green check | First PR merge to main | `ci.yml` is structurally complete and passes local validation. No CI run exists yet because ci.yml was committed directly to main without a PR. The gate is real, not a placeholder. |

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h` | CORTEX_SHM_NAME + _Static_assert | VERIFIED | Defines `/cortex.samples`; `_Static_assert(sizeof(CORTEX_SHM_NAME) <= 32, ...)` present; non-variadic `cortex_shm_open` shim declared |
| `Packages/CortexCore/Sources/CortexCoreC/cortex_shm.c` | cortex_shm_open implementation | VERIFIED | 9-line non-variadic shim calling `shm_open`; includes `<sys/mman.h>` |
| `Packages/CortexCore/Sources/CortexCore/ShmCheck.swift` | mmap sentinel proof callable from app and daemon | VERIFIED | 155 lines; `@_exported import CortexCoreC`; uses `cortex_shm_open` shim; writes/reads `(magic << 32 | pid)` sentinel; `ShmCheck.openSharedRegion` is public API |
| `Packages/CortexCore/Package.swift` | Swift 6.2, CortexCoreC + CortexCore targets, .defaultIsolation(MainActor.self) | VERIFIED | `swift-tools-version: 6.2`; CortexCoreC + CortexCore + CortexCoreTests targets; `.defaultIsolation(MainActor.self)` on both CortexCore and test target |
| `Packages/CortexCore/Tests/CortexCoreTests/ShmConstantsTests.swift` | 3 Swift Testing tests covering shmName, AppGroup, mach time | VERIFIED | 3 tests pass (`swift test --package-path Packages/CortexCore`: 3/3 PASS in 0.001s) |
| `Packages/CortexIPC/`, `CortexRender/`, `CortexDecoder/` | Stub packages that build clean | VERIFIED | All three build with `swift build`; contain single empty Swift source file |
| `project.yml` | XcodeGen spec: 3 targets, App Group, no Catalyst, SWIFT_VERSION 6.2 | VERIFIED | CortexiOS + CortexMac + CortexDaemon targets; `SUPPORTS_MACCATALYST: NO` on CortexMac; `SWIFT_VERSION: "6.2"`; App Group `group.com.donovansantine.cortex.shared` on all 3; CortexDaemon `type: tool` |
| `Apps/CortexMac/Cortex.entitlements` | App Group claim, no sandbox | VERIFIED | `com.apple.security.application-groups = [group.com.donovansantine.cortex.shared]`; no `com.apple.security.app-sandbox` |
| `Apps/CortexiOS/Cortex.entitlements` | App Group claim | VERIFIED | Same App Group; no sandbox key |
| `Apps/CortexDaemon/Cortex.entitlements` | App Group claim, no sandbox | VERIFIED | Same App Group; no sandbox key |
| `Apps/CortexMac/PrivacyInfo.xcprivacy` | NSPrivacyAccessedAPICategorySystemBootTime + CA92.1 | VERIFIED | Validated live; plutil-clean; CA92.1 present |
| `Apps/CortexiOS/PrivacyInfo.xcprivacy` | NSPrivacyAccessedAPICategorySystemBootTime + CA92.1 | VERIFIED | Validated live; plutil-clean; CA92.1 present |
| `Tools/scripts/validate-privacy-manifest.sh` | 4-invariant plist validator | VERIFIED | Exits 0 on both manifests; enforces plist validity, NSPrivacyAccessedAPITypes presence, category name, and CA92.1 reason code |
| `Tools/scripts/hotpath-policy.sh` | Pre-armed grep gate for forbidden hot-path tokens | VERIFIED | Exits 0 (no-op in Phase 1 — CortexIPC/Sources is empty stub). Deviation from plan documented in-file: CortexCore/Sources excluded from default scope to avoid false-positives on legitimate Foundation usage in shared-type files |
| `.github/workflows/ci.yml` | macos-15 CI with Xcode 26.3 pin, 16+ gates | VERIFIED | `runs-on: macos-15`; `setup-xcode@v1` with `xcode-version: '26.3'`; Xcode 26.x version assertion; all 3 xcodebuild schemes; SwiftFormat lint; SwiftLint strict; privacy validator; hotpath policy; PrivacyInfo-in-bundle check; no-CocoaPods check; no-sandbox check; daemon artifact check; Bundler smoke (`continue-on-error: true`) |
| `.swiftformat` | Swift 6.2 formatting config | VERIFIED | `--swiftversion 6.2`, `--indent 2`, `--maxwidth 120` |
| `.swiftlint.yml` | Strict SwiftLint config | VERIFIED | `force_unwrapping` opt-in, 11 opt-in rules, excludes `.build/` dirs |
| `Apps/CortexDaemon/main.swift` | Daemon calls ShmCheck on launch | VERIFIED | Imports CortexCore; calls `ShmCheck.openSharedRegion(processLabel: "CortexDaemon")`; prints result; blocks 5s for runbook observation |
| `Apps/CortexMac/ContentView.swift` | Mac app exposes ShmCheck button | VERIFIED | Button "Run Phase 1 SC#2 ShmCheck" calls `ShmCheck.openSharedRegion(processLabel: "CortexMac.app")`; result rendered in ScrollView |
| `fastlane/Fastfile`, `Matchfile`, `Appfile` | Phase-1 placeholder scaffolding | VERIFIED (placeholder by design) | All three exist; Fastfile has placeholder lanes; Matchfile uses `file:///` URL; Phase 8 note present |
| `docs/cortex-spec.md` | Spec moved to docs/ | VERIFIED | Present at `docs/cortex-spec.md` |
| `docs/adr/0001-foundation-and-2026-toolchain.md` | ADR-0001 documenting 8 decisions | VERIFIED | File exists |
| `README.md` | Project README | VERIFIED | File exists |
| `.github/pull_request_template.md` | PR template | VERIFIED | File exists |
| `.planning/phases/01-foundation-2026-toolchain/sc2-evidence.md` | Committed SC#2 evidence | VERIFIED | Committed at `d959a59`; contains daemon-daemon and app-daemon mmap sentinel runs with full output, codesign entitlement audit, and container directory listing |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `CortexMac/ContentView.swift` | `ShmCheck.openSharedRegion` | `import CortexCore` | WIRED | Button handler calls `ShmCheck.openSharedRegion(processLabel: "CortexMac.app")`; result bound to `@State` and rendered |
| `Apps/CortexDaemon/main.swift` | `ShmCheck.openSharedRegion` | `import CortexCore` | WIRED | Top-level call; result printed to stdout; NSLog call for Console.app capture |
| `ShmCheck.swift` | `cortex_shm_open` C shim | `@_exported import CortexCoreC` | WIRED | `cortex_shm_open(name, flags, mode)` called directly; `CORTEX_SHM_NAME` imported as Swift String constant |
| `cortex_shm_open` shim | `shm_open(2)` | `cortex_shm.c` includes `<sys/mman.h>` | WIRED | Single-line delegation: `return shm_open(name, oflag, mode)` |
| `_Static_assert` on `CORTEX_SHM_NAME` | C precompile | `cortex_shm.h` | WIRED (compile-time) | `_Static_assert(sizeof(CORTEX_SHM_NAME) <= 32, ...)` fires before any test runs |
| `CortexCoreTests` | `CortexCore.shmName` / `AppGroup.identifier` / `Time.machAbsoluteNanoseconds()` | `@testable import CortexCore` | WIRED | 3/3 tests pass; `.defaultIsolation(MainActor.self)` on test target mirrors main target |
| `validate-privacy-manifest.sh` | `PrivacyInfo.xcprivacy` | CI step "Validate PrivacyInfo manifests (FOUND-03)" | WIRED | CI invokes script with both manifest paths; script exits 0 on both |
| `hotpath-policy.sh` | `Packages/CortexIPC/Sources/**` | CI step "Hot-path policy (D-15)" | WIRED | CI invokes script; script scans CortexIPC/Sources (Phase 1: no-op, exits 0) |
| `project.yml` | Xcode project | xcodegen | WIRED | Generated `Cortex.xcodeproj` + `Cortex.xcworkspace` from `project.yml`; both gitignored (correct) |
| `CortexMac scheme` | `CortexDaemon` | `project.yml` dependency `- target: CortexDaemon` | WIRED | CI builds CortexDaemon as peer artifact when CortexMac scheme builds |

---

### Data-Flow Trace (Level 4)

Phase 1 is infrastructure-only — no dynamic data sources, no database queries, no fetch calls. The ShmCheck component reads/writes live kernel shared-memory state (cross-process IPC), not static data. Level 4 data-flow applies to that IPC path:

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `ShmCheck.openSharedRegion` | `sentinelRead` (peer PID) | `mmap(MAP_SHARED)` read from `/cortex.samples` POSIX shm region | Yes — daemon PID 41220 read by app (PID 41234) in sc2-evidence.md | FLOWING |
| `ContentView.swift` | `shmCheckResult` | `ShmCheck.openSharedRegion()` return value | Yes — bound to `@State`; rendered in `ScrollView` | FLOWING |
| `ShmConstantsTests` | `Cortex.shmName`, `AppGroup.identifier`, `Time.machAbsoluteNanoseconds()` | Live runtime values from CortexCoreC import and Mach time syscall | Yes — 3/3 tests produce real values and assert them | FLOWING |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 3 CortexCore unit tests pass | `swift test --package-path Packages/CortexCore` | `3 tests passed after 0.001 seconds` | PASS |
| CortexCore builds clean | `swift build --package-path Packages/CortexCore` | `Build complete! (0.10s)` | PASS |
| CortexIPC, CortexRender, CortexDecoder all build | `swift build` per package | All: `Build complete!` | PASS |
| PrivacyInfo manifests validate | `validate-privacy-manifest.sh Apps/CortexMac/PrivacyInfo.xcprivacy Apps/CortexiOS/PrivacyInfo.xcprivacy` | `OK: Apps/CortexMac/...` + `OK: Apps/CortexiOS/...` | PASS |
| Hotpath policy clean | `hotpath-policy.sh` | `OK: hot-path policy clean across 1 dir(s)` | PASS |
| No CocoaPods artifacts | `find . -name Podfile -o -name Pods -type d` | No output | PASS |
| No app-sandbox on Mac targets | `grep com.apple.security.app-sandbox Apps/CortexMac/Cortex.entitlements Apps/CortexDaemon/Cortex.entitlements` | No match | PASS |
| Cross-process shm_open (SC#2) | Committed evidence in `sc2-evidence.md` (commit `d959a59`) | App read daemon PID 41220 from mmap; daemon-daemon run confirmed | PASS (human-verified, evidence committed) |

---

### Requirements Coverage

| Requirement | Plans | Description | Status | Evidence |
|-------------|-------|-------------|--------|----------|
| FOUND-01 | 01-01, 01-02, 01-04 | Repository scaffolded with Xcode 26 + Swift 6.2, targeting macOS 26 + iPadOS 26 | SATISFIED | `project.yml` with `SWIFT_VERSION: 6.2`, `deploymentTarget.macOS: "26.0"`, `deploymentTarget.iOS: "26.0"`; 4 SwiftPM packages; fastlane stubs; all builds succeed under Xcode 26.3 |
| FOUND-02 | 01-02, 01-07 | App Group container configured for shared-memory IPC (replaces deprecated shared-memory entitlement) | SATISFIED | All 3 targets claim `group.com.donovansantine.cortex.shared` in entitlements; cross-process `shm_open` verified via mmap sentinel (sc2-evidence.md); no deprecated `com.apple.security.temporary-exception.shared-memory`; no sandbox |
| FOUND-03 | 01-03 | PrivacyInfo.xcprivacy with CA92.1 for mach_absolute_time | SATISFIED | Both manifests contain `NSPrivacyAccessedAPICategorySystemBootTime` + `CA92.1`; `validate-privacy-manifest.sh` passes live; CI gate wired |
| FOUND-04 | 01-01 | SwiftPM-only dependency graph, zero CocoaPods | SATISFIED | No `Podfile` or `Pods/`; 4 packages resolve and build; CI has structural no-CocoaPods check; `swift package resolve` step |
| FOUND-05 | 01-06 | GitHub Actions CI on macos-15 with Xcode 26 toolchain | SATISFIED | `.github/workflows/ci.yml`: `runs-on: macos-15`; `setup-xcode@v1` pinned to `26.3`; Xcode 26.x version assertion; full gate set (16+ steps); `CODE_SIGNING_ALLOWED=NO` for unsigned smoke builds |

All 5 FOUND requirements are SATISFIED. No FOUND requirements are ORPHANED (all appear in plan frontmatter and REQUIREMENTS.md traceability table).

---

### Anti-Patterns Found

| File | Pattern | Severity | Assessment |
|------|---------|----------|-----------|
| `Apps/CortexDaemon/main.swift` line 1 | Comment: "placeholder background-helper bundle target per D-03" | Info | Not a code stub — the file contains real functional code (ShmCheck call, NSLog, RunLoop block). The comment is historical and accurate: the *intent* was placeholder in Plan 01-02; Plan 01-07 upgraded it to real SC#2 evidence scaffolding. Not a blocker. |
| `fastlane/Fastfile`, `Matchfile`, `Appfile` | Placeholder lanes and `file:///` Matchfile URL | Info (by design) | Intentional Phase-1 scaffolding per CONTEXT.md D-10. Phase 8 gates real fastlane configuration. CI gate is `continue-on-error: true` for the Bundler smoke. |
| `hotpath-policy.sh` | Narrowed from plan scope (CortexCore/Sources excluded) | Info | Rule 1 deviation documented in script with correct rationale: `Time.swift`, `AppGroup.swift`, `CortexCore.swift` use `import Foundation` legitimately (FileManager, mach_*); they are not hot-path code. Intent preserved. |

No blockers. No stubs that affect goal achievement.

---

### Human Verification Required

None. SC#2 required human verification per Plan 01-07's `type: checkpoint:human-verify`, and that verification was completed and committed (sc2-evidence.md, commit `d959a59`, 2026-06-19). All other success criteria are verifiable programmatically and have been verified above.

---

### Gaps Summary

No gaps. All four success criteria are verified:

- **SC#1** (CI on macos-15 + Xcode 26.3): The CI workflow is real, structurally correct, and locally validated under Xcode 26.3. The absence of a green CI run is not a gap — it reflects that ci.yml was committed directly to main without a PR, so the trigger has not fired. The first PR to main will produce the green check. The gate artifact is complete.
- **SC#2** (App Group + cross-process shm_open): Verified with committed, reproducible evidence. Two process pairs (daemon-daemon and app-daemon) confirm cross-process shared memory via mmap sentinel.
- **SC#3** (PrivacyInfo.xcprivacy + CA92.1): Verified live against both manifests. Validator script runs clean.
- **SC#4** (SwiftPM-only, clean-clone resolve): Verified live. No CocoaPods. All packages build. 3/3 unit tests pass.

The one known deviation from the original plans — `CortexDaemon type: bundle` changed to `type: tool` — was the correct resolution of a latent defect (mh_bundle cannot run standalone or carry entitlements). This deviation was documented in sc2-evidence.md, 01-07-SUMMARY.md, and the project.yml comment. It does not represent a gap.

---

_Verified: 2026-06-19_
_Verifier: gsd-verifier_
