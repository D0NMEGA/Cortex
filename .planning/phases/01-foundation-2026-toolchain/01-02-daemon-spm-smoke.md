# Plan 01-02 Daemon-Bundle SPM Consumption Smoke

**Date:** 2026-04-30
**Result:** DEFERRED_TO_XCODE_26_ENVIRONMENT

## Environment

The Plan 01-02 executor ran on a host that does NOT have the Xcode 26 toolchain
installed. Local environment captured at execution time:

| Tool | Status |
| ---- | ------ |
| `xcode-select -p` | `/Library/Developer/CommandLineTools` (CommandLineTools, not Xcode.app) |
| `xcodebuild` | Stub from CommandLineTools -- errors with `tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance` |
| `xcodegen` | Not installed (`brew install xcodegen` not run; awaiting CI/dev machine with full toolchain) |
| `swift --version` | `Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10 clang-1600.0.30.1)` -- pre-Swift-6.2 |
| `plutil` | `/usr/bin/plutil` (macOS-bundled, fully functional) |
| `yq` | Not installed; YAML parse smoke executed via Python `yaml.safe_load` instead |

This matches the environmental gap documented in [01-01-SUMMARY.md](01-01-SUMMARY.md)
(Issues Encountered -- Toolchain-version gate prevents local `swift build` / `swift test`
smoke). The canonical execution environment for the Xcode 26 + XcodeGen + xcodebuild
path is the macos-15 GitHub Actions runner with `setup-xcode@v1` pinned to 26.3 -- which
Plan 01-06 wires up.

## What Was Verified Locally

The structural correctness of the spec, plist, and entitlements files was verified to
the maximum extent the local toolchain allows:

### plist syntactic validity (`plutil -lint`)

```
Apps/CortexiOS/Cortex.entitlements: OK
Apps/CortexMac/Cortex.entitlements: OK
Apps/CortexDaemon/Cortex.entitlements: OK
Apps/CortexiOS/Info.plist: OK
Apps/CortexMac/Info.plist: OK
Apps/CortexDaemon/Info.plist: OK
```

All six plist files lint clean.

### YAML parse smoke (Python `yaml.safe_load`)

```
targets: ['CortexiOS', 'CortexMac', 'CortexDaemon']
packages: ['CortexCore', 'CortexIPC', 'CortexRender', 'CortexDecoder']
schemes: ['CortexiOS', 'CortexMac', 'CortexDaemon']
iOS sources: [{'path': 'Apps/CortexiOS'}]
Mac sources: [{'path': 'Apps/CortexMac'}]
daemon sources: [{'path': 'Apps/CortexDaemon'}]
mac SUPPORTS_MACCATALYST: False        # Python YAML 1.1 boolean coercion; XcodeGen passes through as "NO" string
daemon type: bundle
mac deps: [{'package': 'CortexCore'}, {'target': 'CortexDaemon'}]
```

`project.yml` parses cleanly. All three targets, four packages, and three schemes
round-trip through a strict YAML parser. The `SUPPORTS_MACCATALYST: NO` value coerces
to Python boolean `False` under YAML 1.1 boolean rules; XcodeGen converts it back to
the literal string `"NO"` when emitting the pbxproj build setting -- this is the
documented XcodeGen pattern (see XcodeGen ProjectSpec.md "Define Simple Build Settings"
example: `GENERATE_INFOPLIST_FILE: NO` etc.).

### Required-token grep on `project.yml`

```
$ grep -n 'SUPPORTS_MACCATALYST: NO' project.yml
100:        SUPPORTS_MACCATALYST: NO            # Defense-in-depth against accidental Catalyst (RENDER-08).

$ grep -c 'package: CortexCore' project.yml
3   # CortexiOS, CortexMac, CortexDaemon -- all three targets depend on CortexCore.

$ grep -n 'type: bundle' project.yml
106:    type: bundle                            # Background-helper bundle per D-03.

$ grep -n 'bundleIdPrefix: com.donovansantine.cortex' project.yml
17:  bundleIdPrefix: com.donovansantine.cortex
```

### Forbidden-token negative greps

```
$ grep -n 'com.apple.security.app-sandbox' project.yml
(empty)        # OK -- forbidden token absent per Critical Finding #1

$ grep -l 'com.apple.security.app-sandbox' Apps/*/Cortex.entitlements
(empty)        # OK -- no entitlements file declares sandbox

$ grep -E '(Catalyst|UIApplicationDelegate)' Apps/CortexMac/App.swift
(empty)        # OK -- Mac App.swift uses native AppKit lifecycle only
```

### App Group declaration count (must equal 3)

```
$ grep -l 'group.com.donovansantine.cortex.shared' Apps/CortexiOS/Cortex.entitlements Apps/CortexMac/Cortex.entitlements Apps/CortexDaemon/Cortex.entitlements | wc -l
       3
```

Expected `3` -- one per target. Confirms D-07 entitlement is declared on all three
targets so Plan 07's manual SC#2 runbook can verify cross-process `shm_open`.

### Swift-source syntactic smoke (`swiftc -parse`)

```
$ swiftc -parse Apps/CortexiOS/App.swift Apps/CortexiOS/ContentView.swift
(empty -- no errors)

$ swiftc -parse Apps/CortexMac/App.swift Apps/CortexMac/ContentView.swift
(empty -- no errors)

$ swiftc -parse Apps/CortexDaemon/main.swift
(empty -- no errors)
```

The local Swift 6.0.3 parses all five sources without syntax errors. CortexCore won't
resolve here (manifest pins 6.2 which 6.0.3 cannot read), but the standalone files
parse cleanly -- so the Xcode 26 + Swift 6.2 environment will only need to verify
linkage, not lex/parse.

## What MUST Be Verified When On Xcode 26 + XcodeGen

The deferred verification re-runs in two places:

1. **Local dev machine** with Xcode 26.3 selected (`xcode-select -s /Applications/Xcode_26.3.app`)
   AND `brew install xcodegen` AND XcodeGen 2.x in PATH.
2. **CI** -- Plan 01-06 workflow on `macos-15` runner with `setup-xcode@v1` pinning 26.3.

The full re-run command set is below. It corresponds 1:1 to the plan's `<verify>` block
and the per-step instructions in Task 3's `<action>`. **No flag elisions** -- the
five `CODE_SIGN*` overrides and the two `-skip*Validation` flags are individually
load-bearing per RESEARCH.md Q3.

### Step 1 -- Generate Cortex.xcodeproj + Cortex.xcworkspace

```bash
cd /Users/donmega/Desktop/Cortex
which xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen
test -d Cortex.xcodeproj && test -d Cortex.xcworkspace && echo "OK: project generated"
```

Expected: `xcodegen` exits 0; both directories exist.

### Step 2 -- Build the CortexMac scheme (peer-builds CortexDaemon via dependencies: [target: CortexDaemon])

```bash
set -o pipefail
xcodebuild build \
  -workspace Cortex.xcworkspace \
  -scheme CortexMac \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  2>&1 | tee /tmp/cortex-mac-build.log | tail -40
```

Expected: exit 0, last lines contain `BUILD SUCCEEDED`.

### Step 3 -- Build the CortexiOS scheme (iOS Simulator)

```bash
xcodebuild build \
  -workspace Cortex.xcworkspace \
  -scheme CortexiOS \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  2>&1 | tee /tmp/cortex-ios-build.log | tail -40
```

Expected: exit 0, `BUILD SUCCEEDED`.

### Step 4 -- Build the CortexDaemon scheme directly (Critical Finding #4 isolation)

```bash
xcodebuild build \
  -workspace Cortex.xcworkspace \
  -scheme CortexDaemon \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  2>&1 | tee /tmp/cortex-daemon-build.log | tail -40
```

Expected: exit 0, `BUILD SUCCEEDED`.

If this step fails with `no such module 'CortexCore'` or `Undefined symbols for
architecture arm64`, it confirms RESEARCH.md Pitfall #6 -- fall back to `type: tool`
per the action below.

### Step 5 -- Inspect daemon-target build settings (Critical Finding #4 explicit smoke)

```bash
xcodebuild -showBuildSettings \
  -workspace Cortex.xcworkspace \
  -scheme CortexDaemon \
  -configuration Debug \
  -destination 'generic/platform=macOS' 2>&1 \
  | grep -E '(OTHER_SWIFT_FLAGS|FRAMEWORK_SEARCH_PATHS|HEADER_SEARCH_PATHS|PACKAGE_RESOLVED_FILE)' \
  | head -30
```

Expected: `CortexCore` symbol appears reachable (header search paths or Swift module
references it).

### Step 6 -- Confirm the daemon bundle artifact exists on disk

```bash
DAEMON_BUNDLE=$(find ~/Library/Developer/Xcode/DerivedData -name "CortexDaemon.bundle" -type d 2>/dev/null | head -1)
test -n "$DAEMON_BUNDLE" && test -d "$DAEMON_BUNDLE" \
  && echo "OK: daemon bundle at $DAEMON_BUNDLE" \
  || { echo "ERROR: CortexDaemon.bundle not produced"; exit 1; }
```

Expected: at least one match returned; the bundle exists as a real directory.

### Step 7 -- Confirm PrivacyInfo.xcprivacy made it into the built app bundle (Pitfall #7)

```bash
PRIVACY_MAC=$(find ~/Library/Developer/Xcode/DerivedData -name PrivacyInfo.xcprivacy -path '*Cortex.app*' 2>/dev/null | head -1)
PRIVACY_IOS=$(find ~/Library/Developer/Xcode/DerivedData -name PrivacyInfo.xcprivacy -path '*CortexiOS.app*' 2>/dev/null | head -1)
test -f "$PRIVACY_MAC" && echo "OK: Mac PrivacyInfo bundled at $PRIVACY_MAC" || echo "WARN: Mac PrivacyInfo missing from bundle"
test -f "$PRIVACY_IOS" && echo "OK: iOS PrivacyInfo bundled at $PRIVACY_IOS" || echo "WARN: iOS PrivacyInfo missing from bundle"
```

Expected: both PrivacyInfo.xcprivacy files appear inside their respective `.app`
bundles (Plan 01-03 cross-phase note honored by `sources: - path: Apps/Cortex<X>` auto-
recursion).

## Fallback Path (only if Step 4 or Step 6 fails)

If the daemon bundle cannot consume `CortexCore` (per RESEARCH.md Pitfall #6):

1. Edit `project.yml` -- change `CortexDaemon` from `type: bundle` to `type: tool`
   (executable).
2. Remove `WRAPPER_EXTENSION: bundle` from the daemon's settings.
3. Remove `CFBundlePackageType: BNDL` from the daemon's `Info.plist` (replace with
   `LSBackgroundOnly: true` if needed).
4. Remove the `Apps/CortexDaemon/main.swift` "bundle" wording so the comment reflects
   reality (daemon is now a CLI binary).
5. Re-run `xcodegen` and re-run all three builds.
6. Update this file: change `Outcome:` line to `FALLBACK_TO_TYPE_TOOL` and document
   the project.yml diff.
7. Update `docs/adr/0001-foundation-and-2026-toolchain.md` Consequences -> Negative
   bullet about the daemon bundle to reflect the actual outcome (Plan 05's ADR already
   pre-positioned this contingency).

The fallback is functional -- the daemon is just a CLI binary instead of a bundle. Phase 2
IPC code does not depend on the daemon being a bundle specifically.

## Outcome

- [ ] type: bundle works with SPM library consumption (DEFERRED -- requires Xcode 26
      + XcodeGen + xcodebuild; not available locally; will run in Plan 01-06 CI)
- [ ] FALLBACK: switched to type: tool (executable). Updated project.yml.
      Updated ADR-0001. (NOT TRIGGERED YET)

**Disposition:** DEFERRED_TO_XCODE_26_ENVIRONMENT.

The plan's structural acceptance criteria (file existence, plist lint, App Group
declaration count, forbidden-token absence, YAML parseability, Swift source
syntactic validity) are all satisfied locally. The dynamic `xcodebuild` smoke is
deferred to the canonical execution environment -- macos-15 + Xcode 26.3 -- and
will be re-run as the Plan 01-06 CI workflow's primary purpose.

If Plan 01-06 CI surfaces a failure consistent with Pitfall #6 (`no such module
'CortexCore'` on the daemon link step), the executor of Plan 01-06 should apply
the Fallback Path above as a Rule 1 (auto-fix bug) deviation and document the
type: tool switch in 01-06-SUMMARY.md.
