---
phase: 01-foundation-2026-toolchain
plan: 02
subsystem: infra
tags: [xcodegen, project-yml, xcode-26, swift-6.2, app-group, entitlements, info-plist, mac-catalyst-opt-out, native-appkit, daemon-bundle, spm-consumption, critical-finding-1, critical-finding-4]

# Dependency graph
requires:
  - phase: 01-01
    provides: Packages/CortexCore SwiftPM library product (CortexCore + CortexCoreC), AppGroup.identifier, Cortex.shmName -- all three Xcode targets consume these
  - phase: 01-03
    provides: Apps/CortexiOS/PrivacyInfo.xcprivacy and Apps/CortexMac/PrivacyInfo.xcprivacy -- auto-included in their respective sources: directories so XcodeGen copies them into the built .app bundles per Pitfall #7

provides:
  - project.yml -- single XcodeGen declarative spec for CortexiOS (iPadOS 26 application), CortexMac (native AppKit macOS 26 with SUPPORTS_MACCATALYST: NO), and CortexDaemon (type bundle background-helper) plus the four CortexCore/CortexIPC/CortexRender/CortexDecoder SwiftPM packages
  - Apps/CortexiOS/Info.plist + Apps/CortexiOS/Cortex.entitlements + Apps/CortexiOS/App.swift + Apps/CortexiOS/ContentView.swift
  - Apps/CortexMac/Info.plist + Apps/CortexMac/Cortex.entitlements + Apps/CortexMac/App.swift + Apps/CortexMac/ContentView.swift
  - Apps/CortexDaemon/Info.plist + Apps/CortexDaemon/Cortex.entitlements + Apps/CortexDaemon/main.swift
  - .planning/phases/01-foundation-2026-toolchain/01-02-daemon-spm-smoke.md -- evidence file documenting structural verification done locally and the deferred xcodebuild re-run command set for the Xcode 26 environment
  - All three Cortex.entitlements files declare App Group group.com.donovansantine.cortex.shared (D-07 verbatim) so Plan 07's manual SC#2 runbook can verify cross-process shm_open
  - SUPPORTS_MACCATALYST: NO build setting + native AppKit lifecycle anchor (NSApplicationDelegateAdaptor) for CortexMac -- the defense-in-depth pair that protects RENDER-08

affects:
  - 01-06 (CI workflow ci.yml runs xcodegen on every PR; xcodebuild for CortexMac/CortexiOS schemes; the Critical Finding #4 daemon SPM smoke is exercised here for the first time on canonical Xcode 26 environment)
  - 01-07 (manual SC#2 runbook references Apps/CortexMac/Cortex.entitlements + Apps/CortexDaemon/Cortex.entitlements as the entitlement pair that authorizes cross-process container access)
  - Phase 2 plans (POSIX shm + kqueue daemon code lands in Apps/CortexDaemon/main.swift -- the Phase 1 stub is the placeholder)
  - Phase 6 plans (CADisableMinimumFrameDurationOnPhone gets added to Apps/CortexiOS/Info.plist when CAMetalDisplayLink renderer wires up; the project.yml info: properties block is the canonical surface)
  - Phase 8 plans (sandbox + paid Developer Program enrollment requires re-adding com.apple.security.app-sandbox to all three Cortex.entitlements files; ADR-0001 Consequences -> Negative bullet covers the Phase-8 re-activation path)

# Tech tracking
tech-stack:
  added:
    - XcodeGen 2.x (declarative project file generator -- generates Cortex.xcodeproj and Cortex.xcworkspace from project.yml; both gitignored)
    - macOS Bundle (MH_BUNDLE) target type for CortexDaemon (RESEARCH.md Pitfall #6 less-trodden path; Critical Finding #4 verification will resolve the disposition on Xcode 26 CI)
    - NSApplicationDelegateAdaptor (SwiftUI 2020+) -- anchors SwiftUI App lifecycle to the native AppKit runtime instead of the iOS-bridged path

  patterns:
    - "Single XcodeGen project.yml as Xcode topology source-of-truth -- the .xcodeproj and .xcworkspace are gitignored and regenerated on demand. PR-reviewable YAML eliminates pbxproj merge conflicts."
    - "Defense-in-depth Mac Catalyst opt-out -- SUPPORTS_MACCATALYST: NO build setting AND NSApplicationDelegateAdaptor source-level anchor; either alone could be regressed silently, together they form a structural pair."
    - "Daemon target dependencies declared on the Mac app target -- building CortexMac scheme transitively builds CortexDaemon as a peer artifact, so a single xcodebuild invocation in CI exercises the daemon-bundle SPM consumption (Critical Finding #4 mitigation surface)."
    - "Sandbox deferral as Phase-1 architectural choice -- documented in ADR-0001 Decision 4 and 5, threat-model T-01-02-01 mitigation, and the explicit absence of com.apple.security.app-sandbox in any of the three entitlements files. Plan 06 CI grep will fail if the literal token ever appears."
    - "Variadic source-directory inclusion auto-picks-up PrivacyInfo.xcprivacy -- the cross-phase note from 01-03 is honored without an explicit per-file entry because XcodeGen recurses Apps/CortexiOS/ and Apps/CortexMac/ for resources (Pitfall #7 mitigated)."

key-files:
  created:
    - project.yml
    - Apps/CortexiOS/Info.plist
    - Apps/CortexiOS/Cortex.entitlements
    - Apps/CortexiOS/App.swift
    - Apps/CortexiOS/ContentView.swift
    - Apps/CortexMac/Info.plist
    - Apps/CortexMac/Cortex.entitlements
    - Apps/CortexMac/App.swift
    - Apps/CortexMac/ContentView.swift
    - Apps/CortexDaemon/Info.plist
    - Apps/CortexDaemon/Cortex.entitlements
    - Apps/CortexDaemon/main.swift
    - .planning/phases/01-foundation-2026-toolchain/01-02-daemon-spm-smoke.md

  modified: []

key-decisions:
  - "project.yml uses unquoted YAML booleans for build settings (SUPPORTS_MACCATALYST: NO, ALWAYS_SEARCH_USER_PATHS: NO, ENABLE_USER_SCRIPT_SANDBOXING: NO). Verified against XcodeGen ProjectSpec docs which use the same form. XcodeGen converts these back to literal NO/YES strings when emitting pbxproj build settings."
  - "PrivacyInfo.xcprivacy paths are NOT explicitly listed under sources: -- relying on XcodeGen's directory recursion of Apps/CortexiOS/ and Apps/CortexMac/ to auto-pick them up as Copy Bundle Resources. Per RESEARCH.md Pitfall #7 + 01-03 cross-phase note, this is the documented XcodeGen pattern; the explicit Step 7 verification in 01-02-daemon-spm-smoke.md will confirm bundling on the Xcode 26 environment."
  - "Mac App.swift comments do NOT contain the literal Catalyst token (case-sensitive) per the plan's acceptance criterion. Comments instead reference 'iOS-bridged runtime' and 'iOS-bridged path'; the NSApplicationDelegateAdaptor remains the source-level lifecycle anchor; only the project.yml build setting line carries SUPPORTS_MACCATALYST: NO (which uses uppercase MACCATALYST not the case-sensitive Catalyst form)."
  - "project.yml does NOT contain the literal app-sandbox token in any line, comment included. The original plan's verbatim YAML had a comment block referencing the absence of com.apple.security.app-sandbox; that comment was reworded to use the words 'app sandbox entitlement' so the negative grep for the dotted token returns empty. Intent (sandbox deferred to Phase 8 per Critical Finding #1) preserved verbatim."
  - "Daemon-bundle SPM consumption smoke (plan's Task 3) is DEFERRED to the Xcode 26 environment because the local executor host has no Xcode 26 / xcodegen / Swift 6.2 installed (CommandLineTools + Swift 6.0.3). Structural correctness verified locally to the maximum extent possible (plutil -lint, YAML parse, required/forbidden token greps, swiftc -parse). The dynamic xcodebuild re-run command set is captured verbatim in 01-02-daemon-spm-smoke.md so Plan 01-06 CI (or a human on a Xcode 26 dev machine) can complete the verification gate. This matches the toolchain-mismatch precedent set by Plan 01-01 SUMMARY."

patterns-established:
  - "Pattern 1: XcodeGen project.yml as the only checked-in Xcode topology artifact. Generated .xcodeproj and .xcworkspace are gitignored. PRs review YAML diffs, not pbxproj diffs. Reusable for: every future target, every future build-setting tweak, every plan that adds an Xcode-level capability."
  - "Pattern 2: Defense-in-depth pair for Mac Catalyst opt-out -- the build setting (SUPPORTS_MACCATALYST: NO) AND the source-level lifecycle anchor (NSApplicationDelegateAdaptor). Reusable for: any 'we explicitly opt out of X runtime' pattern (e.g., Phase 8's sandbox-on-by-then needs both an entitlement entry and runtime feature checks)."
  - "Pattern 3: Cross-target dependency declaration in the application target so a single CI scheme build exercises a peer artifact. CortexMac depends on target: CortexDaemon, so building the CortexMac scheme builds both. Reusable for: any future Phase-2 helper bundles, Phase-5 ANE warm-up bundles, etc."
  - "Pattern 4: Toolchain-deferral disposition for plans that target Xcode 26 + Swift 6.2 when executed on a pre-26 environment. The structural pieces (plist content, YAML content, source-file content, grep gates) ship locally; the dynamic xcodebuild verification is captured as a re-run command set and the plan SUMMARY explicitly documents the gap. CI on macos-15 with setup-xcode@v1 is the canonical environment that closes the gap. First instance: Plan 01-01 (Swift 6.2 manifest); second: Plan 01-02 (xcodebuild build)."

requirements-completed:
  - FOUND-01
  - FOUND-02

# Metrics
duration: 6m
completed: 2026-04-30
---

# Phase 01 Plan 02: XcodeGen project.yml + 3 Xcode Targets + Entitlements + Info.plist + Daemon-Bundle SPM Smoke Summary

**Single project.yml XcodeGen spec drives three Xcode targets (CortexiOS iPadOS 26 app, CortexMac native AppKit macOS 26 with SUPPORTS_MACCATALYST: NO, CortexDaemon type-bundle background helper), each with its own Info.plist + Cortex.entitlements declaring App Group group.com.donovansantine.cortex.shared per D-07; all three targets depend on the Packages/CortexCore SwiftPM library; CortexMac transitively builds CortexDaemon as a peer artifact for Critical Finding #4 verification. Structural correctness verified locally (plutil lint clean, YAML parses cleanly, App Group grep count == 3, app-sandbox grep empty, Catalyst token grep empty); the dynamic xcodebuild build verification deferred to Xcode 26 environment per RESEARCH.md Q3 -- documented exhaustively in 01-02-daemon-spm-smoke.md with verbatim re-run command set.**

## Performance

- **Duration:** 6 min 21 sec
- **Started:** 2026-04-30T04:39:57Z
- **Completed:** 2026-04-30T04:46:18Z
- **Tasks:** 3 / 3
- **Files created:** 13 (1 project.yml + 3 Info.plist + 3 Cortex.entitlements + 5 Swift sources + 1 daemon-spm-smoke.md evidence)

## Accomplishments

- **FOUND-01 (Xcode 26 + Swift 6.2 macOS 26 / iPadOS 26 scaffolding) advanced from "skeleton + 4 SwiftPM packages" (post 01-01) to "skeleton + 4 SwiftPM packages + 3 Xcode targets + workspace topology + entitlements".** The XcodeGen spec at the repo root is the single source of truth for Xcode topology going forward; every later plan that adds an Xcode-level capability edits only project.yml.
- **FOUND-02 (App Group container scaffolding for shared-memory IPC) is now structurally complete on the entitlements layer.** All three target entitlements files declare `group.com.donovansantine.cortex.shared` verbatim (D-07). Plan 07's manual SC#2 runbook (cross-process `shm_open` between CortexMac and CortexDaemon) has its required entitlement scaffolding in place.
- **No `com.apple.security.app-sandbox` token in any of the three Cortex.entitlements files OR in the project.yml** -- per RESEARCH.md Critical Finding #1, sandbox + unauthorized App Group on Personal Team blocks container access. Phase 1 deliberately ships sandbox-OFF; Phase 8 re-adds with paid enrollment. Plan 06 CI's hot-path-policy script will catch any future regression that introduces the literal token.
- **Mac Catalyst opt-out is doubled.** `project.yml` sets `SUPPORTS_MACCATALYST: NO` AND `Apps/CortexMac/App.swift` uses `NSApplicationDelegateAdaptor` -- the SwiftUI App lifecycle is anchored to the native AppKit runtime, not the iOS-bridged path. Either alone could be regressed silently; together they form a structural pair. Phase 6 RENDER-08's `NSScreen.displayLink` requirement is now defensible.
- **CortexMac depends on `target: CortexDaemon`** so building the `CortexMac` scheme via xcodebuild transitively builds the daemon as a peer artifact. This is the explicit Critical Finding #4 verification surface the daemon's bundle-with-SPM-library consumption can be exercised on a single CI scheme build.
- **PrivacyInfo.xcprivacy auto-bundling honored.** The cross-phase note from 01-03 SUMMARY (the iOS and Mac PrivacyInfo manifests must end up in their respective `.app` bundles' Copy Bundle Resources) is satisfied by XcodeGen's directory recursion of `Apps/CortexiOS/` and `Apps/CortexMac/` -- explicit Step 7 verification in `01-02-daemon-spm-smoke.md` will confirm bundling on the Xcode 26 CI.
- **All structural acceptance criteria pass locally.** plutil -lint OK on six plist files; YAML parses cleanly; App Group grep count = 3; app-sandbox grep empty; Catalyst (case-sensitive) grep empty; swiftc -parse exits 0 on five Swift files.
- **The toolchain-deferral disposition is captured exhaustively.** `01-02-daemon-spm-smoke.md` snapshots the local toolchain status, lists every structural verification that DID run with verbatim outputs, and provides the full Step 1..7 xcodebuild re-run command set with all five `CODE_SIGN*` overrides and the two `-skip*Validation` flags preserved per RESEARCH.md Q3. Plan 01-06 (or a human on a Xcode 26 dev machine) closes the dynamic verification gap.

## Task Commits

Each task was committed atomically with conventional-commits scope `({phase}-{plan})`:

1. **Task 1: project.yml + entitlements + Info.plist for 3 Xcode targets** -- `eb40950` (feat)
2. **Task 2: source stubs (App.swift / ContentView.swift / main.swift) for 3 targets** -- `a61682b` (feat)
3. **Task 3: daemon-bundle SPM smoke evidence file (deferred xcodebuild re-run command set)** -- `86beda5` (docs)

**Plan metadata commit:** _to follow after STATE.md / ROADMAP.md / REQUIREMENTS.md updates_

## Files Created/Modified

**XcodeGen spec + entitlements + Info.plist** (Task 1):
- `project.yml` -- 155 lines. Declares 3 targets (CortexiOS application iOS, CortexMac application macOS, CortexDaemon bundle macOS), 4 packages (CortexCore + CortexIPC + CortexRender + CortexDecoder), 3 schemes. Sets bundleIdPrefix `com.donovansantine.cortex`, deployment targets `iOS: 26.0`/`macOS: 26.0`, `SWIFT_VERSION: 6.2`, `SWIFT_STRICT_CONCURRENCY: complete`. Mac target sets `SUPPORTS_MACCATALYST: NO` and `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO`. CortexMac depends on `target: CortexDaemon`. Each target's `info:` and `entitlements:` declares the inline plist properties XcodeGen will overlay onto the on-disk plist files at generate time.
- `Apps/CortexiOS/Info.plist` -- 24 lines, bare-minimum required keys (CFBundleExecutable, CFBundleIdentifier, CFBundlePackageType=APPL, LSRequiresIPhoneOS=true, UIRequiredDeviceCapabilities=[arm64]). XcodeGen overlays CFBundleDisplayName, UILaunchScreen, UIApplicationSceneManifest at generate time.
- `Apps/CortexiOS/Cortex.entitlements` -- 8 lines, declares only `com.apple.security.application-groups: [group.com.donovansantine.cortex.shared]`. NO sandbox.
- `Apps/CortexMac/Info.plist` -- 22 lines, bare-minimum keys (CFBundleExecutable, CFBundleIdentifier, CFBundlePackageType=APPL, LSMinimumSystemVersion, NSHighResolutionCapable=true). XcodeGen overlays CFBundleDisplayName, LSUIElement=false, NSPrincipalClass=NSApplication.
- `Apps/CortexMac/Cortex.entitlements` -- 8 lines, identical structure to iOS. NO sandbox.
- `Apps/CortexDaemon/Info.plist` -- 22 lines, bare-minimum keys (CFBundlePackageType=BNDL, LSUIElement=true, LSMinimumSystemVersion). Background-helper bundle.
- `Apps/CortexDaemon/Cortex.entitlements` -- 8 lines, identical structure. Same App Group as the Mac app so cross-process shm_open works on Plan 07's runbook.

**Source stubs** (Task 2):
- `Apps/CortexiOS/App.swift` -- 12 lines, `@main struct CortexiOSApp: App` with WindowGroup ContentView. Imports CortexCore for the App Group + shm-name surface.
- `Apps/CortexiOS/ContentView.swift` -- 18 lines, displays "Cortex.app -- Phase 1 / 10" header plus `CortexCore.AppGroup.identifier` and `Cortex.shmName` in monospaced footnotes.
- `Apps/CortexMac/App.swift` -- 30 lines, `@main struct CortexMacApp: App` with `@NSApplicationDelegateAdaptor(AppDelegate.self)`. Includes a Phase-1 placeholder `applicationDidFinishLaunching` that NSLogs the App Group identifier. Comments document the native-AppKit-not-iOS-bridged-runtime intent (without using the literal `Catalyst` token, per acceptance criterion).
- `Apps/CortexMac/ContentView.swift` -- 30 lines, mirrors iOS but additionally calls `CortexCore.AppGroup.containerURL()` and renders the path in a footnote so the Phase 1 SC#2 Mac smoke can observe the container live.
- `Apps/CortexDaemon/main.swift` -- 13 lines, top-level script (no `@main`). NSLogs the App Group identifier; runs RunLoop for 100ms so manual `ps`/`launchctl` observers can see the process.

**Smoke evidence + deferred-verification documentation** (Task 3):
- `.planning/phases/01-foundation-2026-toolchain/01-02-daemon-spm-smoke.md` -- 286 lines. Captures the local toolchain snapshot (CommandLineTools + Swift 6.0.3, no Xcode 26, no xcodegen), every structural verification that DID run with verbatim outputs (plutil lint, YAML parse, required-token grep, forbidden-token negative grep, swiftc -parse), the full Step 1..7 xcodebuild re-run command set with five `CODE_SIGN*` overrides and two `-skip*Validation` flags, plus the documented `type: tool` fallback path if the daemon-bundle SPM consumption fails per Pitfall #6. The disposition is `DEFERRED_TO_XCODE_26_ENVIRONMENT` -- canonical resolution venue is Plan 01-06 CI on macos-15 + Xcode 26.3.

## Decisions Made

- **`project.yml` is the single source of truth for Xcode topology.** Generated `.xcodeproj` and `.xcworkspace` are gitignored (.gitignore already covered them per Plan 01-01). PRs review YAML diffs only.
- **Defense-in-depth Mac Catalyst opt-out.** `project.yml` sets `SUPPORTS_MACCATALYST: NO` AND `Apps/CortexMac/App.swift` uses `NSApplicationDelegateAdaptor` -- the SwiftUI App lifecycle stays anchored to AppKit. Either alone could be regressed silently; together the pair is durable.
- **No `com.apple.security.app-sandbox` token in `project.yml` or any entitlements file.** Per RESEARCH.md Critical Finding #1, sandbox + unauthorized App Group on Personal Team blocks container access. The plan's verbatim YAML originally had a comment block referencing the absence of the dotted token; the comment was reworded to use the prose "the app sandbox entitlement" (without dot syntax) so the literal-token grep returns empty. Intent (sandbox deferred to Phase 8) preserved.
- **Mac App.swift comments do NOT contain the literal `Catalyst` token (case-sensitive).** Plan acceptance criterion forbids this token in Mac App.swift; comments rewritten to use "iOS-bridged runtime" / "iOS-bridged path" language while preserving the documented intent. Note: the build-setting line `SUPPORTS_MACCATALYST: NO` in project.yml uses uppercase `MACCATALYST` which does not match the case-sensitive `Catalyst` grep -- so the negative grep on Mac App.swift correctly returns empty without breaking the build setting.
- **PrivacyInfo.xcprivacy auto-bundling via `sources: - path: Apps/Cortex<X>` directory recursion.** No explicit per-file entry for the `.xcprivacy` -- XcodeGen treats it as a resource and adds it to the Copy Bundle Resources phase via directory traversal. Step 7 of the daemon-spm-smoke command set will confirm the bundling on the Xcode 26 environment.
- **Daemon target depends on `target: CortexDaemon` from CortexMac** (cross-target dependency, not just package). Building the CortexMac scheme transitively builds CortexDaemon. This is the Critical Finding #4 verification surface -- a single xcodebuild scheme build exercises both bundles + their SPM library consumption.
- **Toolchain-deferral disposition for the dynamic xcodebuild verification** matches the Plan 01-01 precedent. Local executor environment is Swift 6.0.3 + CommandLineTools (no Xcode 26, no xcodegen). Structural pieces (plist + YAML + source) verified locally to the maximum extent the toolchain allows; the dynamic verification deferred with a verbatim re-run command set captured in `01-02-daemon-spm-smoke.md`. Plan 01-06 CI on macos-15 + Xcode 26.3 is the canonical execution environment.

## Deviations from Plan

The plan executed structurally as written. The following adjustments were applied during execution as Rule 1 (auto-fix bug) deviations to satisfy the literal acceptance criteria text -- intent of the plan preserved verbatim in each case.

### Auto-fixed Issues

**1. [Rule 1 - Bug] project.yml comment contained literal `com.apple.security.app-sandbox` token**
- **Found during:** Task 1 verification (negative grep)
- **Issue:** The plan's verbatim YAML included a comment block under the CortexMac entitlements that said "NOT enabling com.apple.security.app-sandbox in Phase 1." This contained the literal forbidden token, violating the acceptance criterion `File project.yml does NOT contain com.apple.security.app-sandbox ANYWHERE`.
- **Fix:** Reworded the comment to "NOT enabling the app sandbox entitlement in Phase 1." -- intent preserved (sandbox deferred to Phase 8 per Critical Finding #1) without the literal forbidden token. The rest of the comment block (RESEARCH.md reference, Phase 8 path, ADR-0001 anchor) is unchanged.
- **Files modified:** `project.yml` (one comment line, line 91)
- **Commit:** `eb40950` (included in the Task 1 commit, not a separate commit)

**2. [Rule 1 - Bug] Apps/CortexMac/App.swift comment contained literal `Catalyst` token (case-sensitive)**
- **Found during:** Task 2 verification (negative grep)
- **Issue:** The plan's verbatim Swift source for Mac App.swift had comments using `Mac Catalyst` and `Catalyst cannot surface` -- the case-sensitive `Catalyst` token. The acceptance criterion requires `File Apps/CortexMac/App.swift does NOT contain the string Catalyst or UIApplicationDelegate`.
- **Fix:** Reworded the comments to use `iOS-bridged runtime` and `iOS-bridged path` -- intent preserved (this target uses native AppKit, not the bridged runtime path) without the literal token. The build-setting line `SUPPORTS_MACCATALYST: NO` in project.yml is allowed because it uses uppercase `MACCATALYST` which the case-sensitive `Catalyst` grep does not match.
- **Files modified:** `Apps/CortexMac/App.swift` (comment block, lines 1-7)
- **Commit:** `a61682b` (included in the Task 2 commit, not a separate commit)

### Toolchain-Deferral Disposition (NOT a deviation)

The dynamic xcodebuild verification gate from Task 3 (build CortexMac/CortexiOS/CortexDaemon schemes under `CODE_SIGNING_ALLOWED=NO` + 4 sibling overrides + 2 -skip flags + capture daemon bundle artifact path) is **deferred** to a Xcode 26 environment. The local executor host has CommandLineTools + Swift 6.0.3, no Xcode 26 application installed, no xcodegen. This matches the toolchain-mismatch precedent set by Plan 01-01 (Swift 6.2 manifest unable to resolve under Swift 6.0.3) and is explicitly anticipated by the prompt's project_constraints block:

> If the toolchain is unavailable, the executor should:
>   1. Write all the spec/plist/entitlements files exactly as the plan requires
>   2. Validate YAML/plist syntax with available tools
>   3. Document the gap in SUMMARY.md
>   4. Flag for human / CI verification (Plan 01-06's CI workflow on macos-15 will re-run this)

All four steps were followed. The structural verification done locally is comprehensive (plutil -lint clean on all six plist files, YAML parses cleanly via Python yaml.safe_load with three targets / four packages / three schemes, App Group grep count = 3, app-sandbox grep empty across all three entitlements + project.yml, case-sensitive Catalyst grep empty in Mac App.swift, swiftc -parse exits 0 on five Swift files). The dynamic gap is captured in `01-02-daemon-spm-smoke.md` with the verbatim re-run command set including all required signing and validation flags.

This is **not** a Rule 1/2/3/4 deviation -- it is a documented toolchain disposition that the plan and prompt both explicitly accommodate.

## Issues Encountered

**The xcodebuild dynamic verification gate cannot run on this host.** The local environment is `xcode-select -p` = `/Library/Developer/CommandLineTools` (CommandLineTools, not Xcode app), `xcodebuild` is the CommandLineTools stub, `xcodegen` is not installed, and `swift --version` is `Apple Swift version 6.0.3` (pre-6.2). This is the exact environmental constraint Plan 01-01 SUMMARY documented. The mitigation is identical: structural pieces (plist/YAML/source) verified locally to the max extent possible; dynamic re-run captured in the smoke evidence file with verbatim commands.

**Recommended verification (when on Xcode 26 + XcodeGen + Swift 6.2):**

```bash
# Step 1 -- Generate project + workspace
cd /Users/donmega/Desktop/Cortex
which xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen
test -d Cortex.xcodeproj && test -d Cortex.xcworkspace && echo "OK: project generated"

# Step 2 -- Build CortexMac scheme (peer-builds CortexDaemon)
xcodebuild build \
  -workspace Cortex.xcworkspace \
  -scheme CortexMac \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" \
  -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -10

# Step 3 -- Build CortexiOS scheme (Simulator)
xcodebuild build \
  -workspace Cortex.xcworkspace \
  -scheme CortexiOS \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" \
  -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -10

# Step 4 -- Build CortexDaemon scheme directly (Critical Finding #4)
xcodebuild build \
  -workspace Cortex.xcworkspace \
  -scheme CortexDaemon \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" \
  -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -10

# Step 5 -- Daemon target sees CortexCore module
xcodebuild -showBuildSettings \
  -workspace Cortex.xcworkspace \
  -scheme CortexDaemon \
  -configuration Debug \
  -destination 'generic/platform=macOS' 2>&1 \
  | grep -E '(OTHER_SWIFT_FLAGS|FRAMEWORK_SEARCH_PATHS|HEADER_SEARCH_PATHS)' | head

# Step 6 -- CortexDaemon.bundle exists on disk
DAEMON_BUNDLE=$(find ~/Library/Developer/Xcode/DerivedData -name "CortexDaemon.bundle" -type d 2>/dev/null | head -1)
test -n "$DAEMON_BUNDLE" && echo "OK: $DAEMON_BUNDLE" || { echo "ERROR: bundle not produced"; exit 1; }

# Step 7 -- PrivacyInfo.xcprivacy made it into both .app bundles (Pitfall #7)
find ~/Library/Developer/Xcode/DerivedData -name PrivacyInfo.xcprivacy -path '*Cortex*.app*' 2>&1 | head -5
```

The full re-run script and the documented `type: tool` fallback path (if Step 4 fails per Pitfall #6) are captured in `01-02-daemon-spm-smoke.md`.

## User Setup Required

None for Plan 01-02 itself -- all artifacts are local repo scaffolding.

A human with a Xcode 26 + Swift 6.2 dev machine (or the Plan 01-06 CI on macos-15 + setup-xcode@v1 pinning 26.3) closes the deferred xcodebuild verification gate. The seven-step re-run command set in `01-02-daemon-spm-smoke.md` is the canonical script.

If the daemon-bundle SPM consumption fails on the Xcode 26 environment per RESEARCH.md Pitfall #6 (`no such module 'CortexCore'` on the daemon link step), the executor should apply the documented `type: tool` fallback as a Rule 1 (auto-fix bug) deviation: change `CortexDaemon` from `type: bundle` to `type: tool` in `project.yml`, update `Apps/CortexDaemon/Info.plist` to set `LSBackgroundOnly: true` instead of `BNDL`, re-run `xcodegen` and the three xcodebuild commands, and update both `01-02-daemon-spm-smoke.md` (Outcome: FALLBACK_TO_TYPE_TOOL) and `docs/adr/0001-foundation-and-2026-toolchain.md` Consequences->Negative bullet to reflect the actual outcome. Plan 05's ADR pre-positioned this contingency.

## Cross-phase Notes

- **Plan 01-06 (GitHub Actions ci.yml on macos-15):** This plan's deferred xcodebuild verification gate is exactly the work Plan 01-06 performs. The CI workflow's `Build CortexMac (unsigned smoke)`, `Build CortexiOS (unsigned smoke, simulator)`, and `Verify CortexDaemon was built` steps execute the seven-step re-run command set verbatim. If the daemon-bundle SPM consumption fails, Plan 01-06 should apply the type: tool fallback as Rule 1.
- **Plan 01-07 (Manual SC#2 verification runbook):** The runbook references `Apps/CortexMac/Cortex.entitlements` and `Apps/CortexDaemon/Cortex.entitlements` as the entitlement pair that authorizes the cross-process App Group container access. Both files are now in place declaring `group.com.donovansantine.cortex.shared` verbatim per D-07. The CortexMac scheme builds the daemon as a peer artifact, so a single xcodebuild invocation on the dev machine produces both processes for the runbook.
- **Phase 2 plans (POSIX shm + kqueue + recvmsg + AES-GCM transport):** `Apps/CortexDaemon/main.swift` is the daemon entry point; the Phase-1 stub (NSLog + 100ms RunLoop block) is replaced by the real `kqueue`+`recvmsg` daemon code in Phase 2. The bundle's existing App Group entitlement + `import CortexCore` linkage means Phase 2's IPC code can drop in without re-doing entitlements.
- **Phase 6 (CAMetalDisplayLink renderer):** `Apps/CortexiOS/Info.plist` will get `CADisableMinimumFrameDurationOnPhone = YES` -- but the canonical place to add it is the `info: properties:` block in `project.yml` (under the CortexiOS target), so XcodeGen overlays it onto the on-disk plist. Don't edit the on-disk Info.plist directly; XcodeGen regenerates it.
- **Phase 8 (paid Developer Program enrollment + sandbox + TestFlight):** All three Cortex.entitlements files will need `com.apple.security.app-sandbox` re-added once paid enrollment + provisioning profile authorization is in place. The negative grep gate in Plan 06's CI's hot-path-policy script will fail loudly until that swap, which is intentional (Phase 1 acceptance is sandbox-OFF). ADR-0001 Consequences -> Negative bullet documents the swap procedure.

## Self-Check: PASSED

Verification of artifacts and commits claimed in this Summary:

**Files exist (`test -f` / `test -d`):**
- FOUND: project.yml (155 lines)
- FOUND: Apps/CortexiOS/Info.plist
- FOUND: Apps/CortexiOS/Cortex.entitlements
- FOUND: Apps/CortexiOS/App.swift
- FOUND: Apps/CortexiOS/ContentView.swift
- FOUND: Apps/CortexMac/Info.plist
- FOUND: Apps/CortexMac/Cortex.entitlements
- FOUND: Apps/CortexMac/App.swift
- FOUND: Apps/CortexMac/ContentView.swift
- FOUND: Apps/CortexDaemon/Info.plist
- FOUND: Apps/CortexDaemon/Cortex.entitlements
- FOUND: Apps/CortexDaemon/main.swift
- FOUND: .planning/phases/01-foundation-2026-toolchain/01-02-daemon-spm-smoke.md

**Commits exist (`git log --oneline`):**
- FOUND: eb40950 -- Task 1 (feat: project.yml + entitlements + Info.plist for 3 Xcode targets)
- FOUND: a61682b -- Task 2 (feat: source stubs for 3 Xcode targets)
- FOUND: 86beda5 -- Task 3 (docs: daemon-bundle SPM smoke deferral and re-run command set)

**Verification clauses re-executed:**
- All six plist files lint clean (`plutil -lint` returns OK on each) -- PASS
- project.yml YAML parses cleanly via Python yaml.safe_load (3 targets, 4 packages, 3 schemes) -- PASS
- App Group grep count == 3 (one per Cortex.entitlements file) -- PASS
- `app-sandbox` token absent from project.yml AND from all three Cortex.entitlements files -- PASS
- `Catalyst` (case-sensitive) AND `UIApplicationDelegate` absent from Apps/CortexMac/App.swift -- PASS
- `NSApplicationDelegateAdaptor` present in Apps/CortexMac/App.swift -- PASS
- `import CortexCore` present in all three target sources (iOS App, Mac App, Daemon main) -- PASS
- swiftc -parse exits 0 on the five new Swift files -- PASS
- daemon-bundle SPM smoke evidence file documents disposition `DEFERRED_TO_XCODE_26_ENVIRONMENT` -- PASS

**No items missing. Self-check passed.**

The dynamic xcodebuild build verification gate (BUILD SUCCEEDED for CortexMac/CortexiOS/CortexDaemon under `CODE_SIGNING_ALLOWED=NO`, plus CortexDaemon.bundle artifact existence on disk) is **deferred** to the Xcode 26 environment per documented toolchain disposition; the seven-step re-run command set in `01-02-daemon-spm-smoke.md` closes the gap when executed on macos-15 + Xcode 26.3 (Plan 01-06 CI) or any Xcode 26 dev machine.

---
*Phase: 01-foundation-2026-toolchain*
*Plan: 01-02*
*Completed: 2026-04-30*
