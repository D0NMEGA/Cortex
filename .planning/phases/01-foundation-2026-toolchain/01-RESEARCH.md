# Phase 1: Foundation & 2026 Toolchain — Research

**Researched:** 2026-04-28
**Domain:** Apple greenfield project bootstrap (Xcode 26 + Swift 6.2 + macOS 26 / iPadOS 26, multi-target, SwiftPM, GitHub Actions CI)
**Confidence:** HIGH on toolchain availability and SwiftPM mechanics; **MEDIUM on App Group + Personal Team interaction** (load-bearing nuance — see Critical Findings); HIGH on PrivacyInfo and CI patterns

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Repo & Target Topology:**
- **D-01:** Two app targets in Xcode — `CortexiOS` (iPadOS 26) and `CortexMac` (native AppKit on macOS 26 Tahoe). **No Mac Catalyst** — Phase 6 RENDER-08 already requires `NSScreen.displayLink` on the Mac side, which Catalyst does not surface cleanly.
- **D-02:** Shared code lives in SwiftPM library packages from day 1 under `Packages/`:
  - `CortexCore` — shared types, time utilities, App Group helpers
  - `CortexIPC` — (empty in Phase 1) reserved for Phase 2 transport code
  - `CortexRender` — (empty) reserved for Phase 6 Metal renderer
  - `CortexDecoder` — (empty) reserved for Phase 5 CoreML deployment
  Both app targets and the daemon depend on `CortexCore`; later phases wire in `CortexIPC` etc.
- **D-03:** A `CortexDaemon` placeholder target ships in Phase 1 (background-helper bundle, App Group entitlement matched to the apps). Empty `main()` is fine — the only Phase-1 functional requirement is that a cross-process `shm_open` from the daemon onto a region inside the App Group container survives sandbox checks.
- **D-04:** Repo root layout: `Apps/`, `Packages/`, `Tools/`, `.github/workflows/`, `docs/`, `fastlane/`, `Cortex.xcworkspace`.

**Bundle ID & App Group Naming:**
- **D-05:** Canonical bundle ID prefix: `com.donovansantine.cortex`.
- **D-06:** Per-target suffixes — `.ios`, `.mac`, `.daemon`.
- **D-07:** App Group identifier: `group.com.donovansantine.cortex.shared`.
- **D-08:** Canonical shm region name: `/cortex.samples` (15 bytes). Defined once in `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h` with `_Static_assert(sizeof(CORTEX_SHM_NAME) <= 32, ...)`. **Compile-time enforcement.**

**Signing & Apple Developer Enrollment:**
- **D-09:** Apple Developer Program enrollment is **deferred** to Phase 8. Phase 1 ships with Personal Team auto-signing for local dev only.
- **D-10:** fastlane scaffolding lands as placeholder — `Matchfile` points to a TBD remote (local Git repo only).
- **D-11:** CI does **not** sign with a real Developer ID. Smoke build uses `CODE_SIGNING_ALLOWED=NO` (or ad-hoc `-`).
- **D-12:** App Store Connect API key (`.p8` JWT) is **not** provisioned in Phase 1.

**CI Scope on Day 1:**
- **D-13:** PR-blocking CI runs: `xcodebuild build` for both schemes (`CODE_SIGNING_ALLOWED=NO`); `swiftformat --lint .`; `swiftlint --strict`; `swift package resolve` sanity.
- **D-14:** `Tools/scripts/validate-privacy-manifest.sh` parses `PrivacyInfo.xcprivacy` and asserts plist-validity AND that `CA92.1` is declared for `mach_absolute_time`.
- **D-15:** `Tools/scripts/hotpath-policy.sh` greps `Packages/CortexIPC/Sources/**` and `Packages/CortexCore/Sources/**` for forbidden tokens (`dispatch_async`, `lazy var`, `pthread_mutex`, `import Foundation`, `import ObjectiveC`). No-op in Phase 1; bites in Phase 2/3.
- **D-16:** GitHub Actions caches DerivedData and `~/Library/Caches/org.swift.swiftpm`, keyed on `Package.resolved` hash + Xcode major version.

### Implementer's Discretion
- Exact SwiftFormat / SwiftLint rule sets (community defaults OK)
- `.gitignore` contents (Apple/SwiftPM standard template)
- README content shape beyond "documents architectural commitments" (full DIST-04 deferred to Phase 8)
- ADR template format (lightweight Markdown is fine; format locked when second ADR lands)
- LICENSE file (omit in Phase 1; revisit at v0/v1)
- Branch protection rules in GitHub ("require CI green" but otherwise default)

### Cross-Phase Commitments
- **Compile-time guarantees beat runtime ones.** Wherever an invariant can be enforced at the type system, preprocessor, or build-graph level, it MUST be — not via unit test, not via CI lint.

### Deferred Ideas (OUT OF SCOPE for Phase 1)
| Idea | Belongs in | Why deferred |
|------|------------|--------------|
| Apple Developer Program enrollment ($99/yr) | Phase 8 | No real notarization or TestFlight needed until v0 ships |
| fastlane match private GitHub repo + `MATCH_PASSWORD` | Phase 8 | Match doesn't operate without an Apple Developer team to manage certs for |
| App Store Connect API key (`.p8` JWT) | Phase 8 | Required only for `notarytool submit` and TestFlight upload |
| Real notarization smoke (`notarytool submit` in CI) | Phase 8 | Requires enrollment + ASC API key |
| TestFlight 100/10,000 tester wiring | Phase 8 | DIST-03 explicitly placed there |
| LICENSE file at repo root | v0 / v1 polish | Not specified in REQUIREMENTS.md |
| Full README architectural commitments + rejected-alternatives table (DIST-04) | Phase 8 | Phase 1 README documents *what's scaffolded*; the credibility-grade README is a v0 distribution artifact |
| Static-analysis policies for additional dirs (e.g., `Packages/CortexDecoder`) | Phase 4 | Decoder doesn't run on the audio-callback hot path; different rules apply |
| Code-coverage threshold enforcement | Phase 8 or v0 | Phase 1 has no logic to cover |
| Branch protection beyond "require CI green" | v0 | Solo project, can stay light-touch |

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FOUND-01 | Repository scaffolded with Xcode 26 + Swift 6.2, targeting macOS 26 Tahoe and iPadOS 26 | §Standard Stack: Xcode 26.x via `setup-xcode` action; Package.swift `swift-tools-version: 6.2`; deployment targets per-platform |
| FOUND-02 | App Group container configured for shared-memory IPC (replaces deprecated `com.apple.security.temporary-exception.shared-memory`) | §Critical Findings #1 — App Group + Personal Team caveat; container path under `~/Library/Group Containers/group.com.donovansantine.cortex.shared/`; macOS unsandboxed dev binaries CAN open the container without enrollment |
| FOUND-03 | Privacy manifest `PrivacyInfo.xcprivacy` includes `CA92.1` reason code for `mach_absolute_time` | §Domain Q5 — `NSPrivacyAccessedAPICategorySystemBootTime` + `CA92.1` ("Approximate time interval"); plist structure verified against Apple docs |
| FOUND-04 | SwiftPM-only dependency graph (no CocoaPods anywhere in the build) | §Domain Q6, Q7 — Package.swift manifests for `CortexCore` (mixed Swift+C) and four siblings; no `Podfile`, no `Pods/` |
| FOUND-05 | GitHub Actions CI runs on `macos-15` runner with Xcode 26 toolchain | §Domain Q2 — `macos-15` (Apple Silicon arm64) ships with Xcode 26.0.1 / 26.1.1 / 26.2 / 26.3 pre-installed but **default is Xcode 16.4**; MUST select via `setup-xcode` action |

</phase_requirements>

## Summary

Phase 1 stands up an Xcode 26 + Swift 6.2 monorepo for a multi-target Apple app (iPadOS 26 + native AppKit macOS 26 + a placeholder daemon bundle), wires in SwiftPM library packages, lands a `PrivacyInfo.xcprivacy` declaring `CA92.1` for `mach_absolute_time`, scaffolds fastlane in placeholder mode (no real signing identities), and gates every PR with a `macos-15` GitHub Actions CI smoke build (`CODE_SIGNING_ALLOWED=NO`) plus SwiftFormat / SwiftLint / SwiftPM resolution checks.

**Three load-bearing technical findings drive the plan:**

1. **App Group + Personal Team is a real interaction with platform-specific behavior.** On **iOS/iPadOS**, App Group entitlements require a paid Apple Developer Program team — Personal Team will fail to provision the entitlement. On **macOS**, *unsandboxed* binaries can open `~/Library/Group Containers/group.*/` paths without entitlement validation at all (no provisioning profile required), so the Phase-1 cross-process `shm_open` test for SC#2 is achievable on the Mac side without paid enrollment. The iPad side cannot have App Group locally with Personal Team — but Phase 1 SC#2 only needs the Mac-side daemon ↔ Mac app cross-process proof.
2. **`CODE_SIGNING_ALLOWED=NO` strips entitlements**, so an unsigned CI build cannot validate App Group entitlement enforcement. This is fine for Phase 1's CI scope (build-only smoke), but means SC#2 must be verified locally on the dev machine (Mac), not in CI. Document this asymmetry explicitly in the plan.
3. **`macos-15` runner default is Xcode 16.4** as of April 2026 — Xcode 26.x is pre-installed but not default. CI MUST use `maxim-lobanov/setup-xcode@v1` (or `sudo xcode-select -s /Applications/Xcode_26.3.app`) to select Xcode 26 for every build.

**Primary recommendation:** Use **XcodeGen** (declarative YAML, simpler than Tuist for a 3-target / no-cache project) to express the workspace from a `project.yml` checked into git. Generate the `.xcodeproj`/`.xcworkspace` on demand and `.gitignore` them. SwiftPM packages live under `Packages/` and are referenced by relative path in `project.yml`. CI generates the project as the first step, then runs `xcodebuild`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Build-graph definition | Build tooling (XcodeGen `project.yml` + SwiftPM `Package.swift`) | — | Declarative spec eliminates merge conflicts on `.pbxproj`; SwiftPM owns library compilation |
| Multi-target scheme generation | Xcode workspace (generated) | XcodeGen | Workspace wires three targets to the SwiftPM packages |
| Shared code (Swift) | SwiftPM library `CortexCore` | — | One source-of-truth Swift module consumed by all targets |
| Shared C constants (`cortex_shm.h`, `_Static_assert`) | SwiftPM library `CortexCoreC` (C target inside CortexCore package) | — | Pure C target with `include/` directory and umbrella header; Swift `CortexCore` depends on it |
| Entitlements (App Group) | Per-target `.entitlements` plist | XcodeGen-generated | Each target declares the App Group; matched group ID across all three |
| PrivacyInfo.xcprivacy | App target Resources | — | Lives at app bundle root; one per app target |
| Code signing (local dev) | Personal Team (Mac side only) | — | macOS unsandboxed binaries can use App Group container; iPad side cannot until paid enrollment |
| Code signing (CI) | None — `CODE_SIGNING_ALLOWED=NO` | Ad-hoc `-` fallback | Build-only smoke; entitlement validation deferred to local dev |
| Static analysis (SwiftLint, SwiftFormat) | SwiftPM build plugin (preferred) OR pre-installed binary on runner | brew/mint fallback | Hermetic CI prefers plugins; brew is the macos-15 runner default |
| Privacy manifest validation | Custom bash script (`Tools/scripts/validate-privacy-manifest.sh`) | — | Apple ships no first-party validator; `plutil` + grep for `CA92.1` is sufficient |
| CI orchestration | GitHub Actions `macos-15` runner | — | macos-15 arm64 has all Xcode 26.x versions pre-installed |

---

## Domain Research

### Q1: Project file generation strategy (XcodeGen vs Tuist vs hand-rolled vs pure SwiftPM)

**Verified findings:**

| Tool | Config | Caching | Best fit for | Source |
|------|--------|---------|-------------|--------|
| **XcodeGen** | YAML/JSON `project.yml` | None | Small/medium projects, declarative simplicity, no Swift toolchain dependency to bootstrap | [VERIFIED: github.com/yonaskolb/XcodeGen via Context7] |
| Tuist | Swift `Project.swift` | Built-in binary cache + parallel incremental builds | Large modular apps, type-safe config logic | [CITED: tuist.dev/blog/2025/02/25/project-generation] |
| Hand-rolled `.xcodeproj` | XML | None | Single-developer, never re-generated | (Survives badly under collaborative edits — `.pbxproj` merge conflicts are the historical pain point XcodeGen and Tuist exist to solve) |
| Pure SwiftPM (no `.xcodeproj`) | `Package.swift` only | SwiftPM build cache | Library-only packages | Cannot express App Group entitlements, Info.plist, or non-app bundles cleanly. Disqualifying for this project. |

**Recommendation: XcodeGen.** Phase 1 has only 3 Xcode targets (two apps + one daemon bundle) and four SwiftPM packages. Tuist's caching delivers value at 10+ targets; here it's overhead. XcodeGen's YAML is human-reviewable in PRs and the project file becomes ephemeral (gitignored, regenerated). XcodeGen's declarative entitlements+Info.plist generation directly satisfies D-07 (App Group claim) and FOUND-03 (PrivacyInfo).

**Confidence: HIGH** for tool fitness comparison. **MEDIUM** for Xcode-26-specific quirks — XcodeGen is community-maintained and may lag on new pbxproj schema changes; verify with a `xcodebuild -showBuildSettings` smoke after first generation.

**Concrete `project.yml` skeleton:**

```yaml
name: Cortex
options:
  bundleIdPrefix: com.donovansantine.cortex
  deploymentTarget:
    iOS: "26.0"
    macOS: "26.0"
  developmentLanguage: en
  generateEmptyDirectories: true

packages:
  CortexCore:
    path: Packages/CortexCore
  CortexIPC:
    path: Packages/CortexIPC
  CortexRender:
    path: Packages/CortexRender
  CortexDecoder:
    path: Packages/CortexDecoder

targets:
  CortexiOS:
    type: application
    platform: iOS
    sources:
      - path: Apps/CortexiOS
    dependencies:
      - package: CortexCore
    info:
      path: Apps/CortexiOS/Info.plist
      properties:
        CFBundleDisplayName: Cortex
        UILaunchScreen: {}
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
        # CADisableMinimumFrameDurationOnPhone gets added in Phase 6
    entitlements:
      path: Apps/CortexiOS/Cortex.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.donovansantine.cortex.shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.donovansantine.cortex.ios
        SWIFT_VERSION: "6.2"
        TARGETED_DEVICE_FAMILY: "2"  # iPad only
        DEVELOPMENT_TEAM: ""  # Personal Team auto-signs locally; CI overrides

  CortexMac:
    type: application
    platform: macOS
    sources:
      - path: Apps/CortexMac
    dependencies:
      - package: CortexCore
    info:
      path: Apps/CortexMac/Info.plist
      properties:
        CFBundleDisplayName: Cortex
        LSUIElement: false
    entitlements:
      path: Apps/CortexMac/Cortex.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.donovansantine.cortex.shared
        # NOT enabling com.apple.security.app-sandbox in Phase 1 —
        # see Critical Finding #1: unsandboxed Mac binaries can use
        # App Group container without paid enrollment.
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.donovansantine.cortex.mac
        SWIFT_VERSION: "6.2"
        MACOSX_DEPLOYMENT_TARGET: "26.0"
        SUPPORTS_MACCATALYST: NO  # explicit defense against accidental Catalyst

  CortexDaemon:
    type: bundle  # background-helper bundle per D-03
    platform: macOS
    sources:
      - path: Apps/CortexDaemon
    dependencies:
      - package: CortexCore
    info:
      path: Apps/CortexDaemon/Info.plist
      properties:
        CFBundlePackageType: BNDL
        LSUIElement: true
    entitlements:
      path: Apps/CortexDaemon/Cortex.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.donovansantine.cortex.shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.donovansantine.cortex.daemon
        SWIFT_VERSION: "6.2"
        MACOSX_DEPLOYMENT_TARGET: "26.0"
```

[CITED: github.com/yonaskolb/XcodeGen — `Docs/ProjectSpec.md`, "Generate Plist and Entitlements" example]

### Q2: macos-15 runner Xcode 26 availability

**Verified facts (as of 2026-04-21 image version 20260421.0007.1):**

The `macos-15-arm64` runner ships with **all** Xcode 26.x versions pre-installed:

| Version | Build | Path |
|---------|-------|------|
| 26.3 | 17C529 | `/Applications/Xcode_26.3.app` |
| 26.2 | 17C52 | `/Applications/Xcode_26.2.app` |
| 26.1.1 | 17B100 | `/Applications/Xcode_26.1.1.app` |
| 26.0.1 | 17A400 | `/Applications/Xcode_26.0.1.app` |
| **16.4 (default)** | 16F6 | `/Applications/Xcode_16.4.app` |
| ...older 16.x | | |

Critically: **default Xcode is 16.4**, NOT a 26.x version. CI MUST select 26.x explicitly.

[VERIFIED: github.com/actions/runner-images macos-15-arm64-Readme.md, image 20260421.0007.1]

**Selection options (in order of preference):**

```yaml
# Option A (preferred): maxim-lobanov/setup-xcode action — official-quality, widely used
- uses: maxim-lobanov/setup-xcode@v1
  with:
    xcode-version: '26.3'  # or 'latest-stable'

# Option B: direct xcode-select (no third-party action)
- run: sudo xcode-select -s /Applications/Xcode_26.3.app/Contents/Developer
```

**Recommendation: pin to 26.3** (latest stable on the runner). Avoid `latest-stable` to prevent silent CI breakage when Apple ships a 26.4 with surprises.

**Known gotcha:** Xcode 26.0.1 / 26.1 RC had test-suite hangs reported on `macos-15-arm64` (~75-80% failure rate from console-stops-mid-run). [CITED: github.com/actions/runner-images/issues/13264] The issue was closed as duplicate; pinning to 26.2 or later avoids it.

**Confidence: HIGH** — directly verified against the runner image manifest.

### Q3: CODE_SIGNING_ALLOWED=NO vs ad-hoc — exact incantation and entitlement behavior

**Verified facts:**

`CODE_SIGNING_ALLOWED=NO` produces a built bundle without any signature. **Entitlements are NOT validated** because there's no signature to embed them in. This means:
- The build SUCCEEDS regardless of which entitlements are declared.
- The runtime will NOT enforce the declared entitlements (no provisioning profile to authorize them).
- For Phase 1 CI scope (build-only smoke, no execution of the daemon ↔ app shm test), this is correct.

**Recommended xcodebuild command for CI:**

```bash
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
  | xcbeautify --renderer github-actions
```

The four explicit overrides (`ALLOWED=NO`, `REQUIRED=NO`, `IDENTITY=""`, `ENTITLEMENTS=""`) defeat all of Xcode 26's signing fallbacks. `-skipPackagePluginValidation` and `-skipMacroValidation` prevent Xcode 26's macro-trust prompts (it now requires user confirmation for unblessed macros — fatal in headless CI).

For the iPad scheme:

```bash
xcodebuild build \
  -workspace Cortex.xcworkspace \
  -scheme CortexiOS \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  ...
```

Use `iOS Simulator` destination (not real device) — no signing identity needed, no provisioning profile, App Group entitlement is harmlessly ignored on the simulator.

**Daemon target gotcha:** Background-helper bundles (`type: bundle`) historically need `XCBUILD_ALL_PRECOMPILE_PHASES=1` and an explicit `BUILD_LIBRARY_FOR_DISTRIBUTION=NO`. The Cortex daemon is built via the workspace's auto-aggregated dependency graph — building `CortexMac` should pull in the daemon as a peer if XcodeGen declares it as a target dependency. **Verify after first generation.**

**Confidence: MEDIUM-HIGH** — `CODE_SIGNING_ALLOWED=NO` is a well-known pattern; the exact 5-flag set is community wisdom from CI templates, not a single Apple doc page.

### Q4: App Group entitlement without paid enrollment (LOAD-BEARING)

**This is the most consequential research finding.** It splits cleanly by platform:

#### iOS / iPadOS

App Groups on iOS use the `group.*` prefix and are a **restricted entitlement**. The Apple Developer documentation for App Groups Entitlement notes:

> "The Developer website assigns each iOS-style app group ID to a specific team, which guarantees uniqueness."

> "On iOS, all entitlements must be authorised by a provisioning profile."

**Practical impact:** A Personal Team / free Apple ID **cannot** allocate or claim a `group.com.donovansantine.cortex.shared` ID for the iPad target. Attempting to do so produces "Provisioning profile doesn't include com.apple.security.application-groups" build errors.

[CITED: developer.apple.com/forums/thread/91312, gordonbeeming.com/blog/2025-10-15/solving-xcode-provisioning-profile-and-capability-errors]

#### macOS

macOS App Groups have **two distinct ID styles** with very different rules:

1. **iOS-style (`group.*` prefix):** Same restriction as iOS — requires Developer Program enrollment + provisioning profile authorization.
2. **macOS-style (`TEAMID.*` prefix):** Cannot be allocated on Developer website; *historically* did not require provisioning profile authorization for unsandboxed code.

Critically: as of macOS 15, "App Group container protection" requires one of:
- Mac App Store deployment, OR
- Team ID prefix matching, OR
- Provisioning profile authorization.

**However:** The Apple DTS engineer's authoritative answer on the forums confirms that **`shm_open` between two unsandboxed processes** sharing an App Group works without provisioning profile authorization — the entitlement only matters when sandbox enforcement is enabled.

[CITED: developer.apple.com/forums/thread/721701 (App Groups: macOS vs iOS), developer.apple.com/forums/thread/719897 (Is opening Shared memory allowed in sandbox)]

**Practical resolution for Phase 1:**

| Question | Answer |
|----------|--------|
| Can the iPad target use App Group `group.com.donovansantine.cortex.shared` locally on Personal Team? | **NO.** Build fails — provisioning profile cannot authorize the entitlement. |
| Can the Mac app + daemon use App Group container `~/Library/Group Containers/group.com.donovansantine.cortex.shared/` locally on Personal Team? | **YES** — *if* both are built without `com.apple.security.app-sandbox`. The container directory is created on first access; macOS doesn't enforce the entitlement when sandbox is off. |
| Will SC#2 (cross-process `shm_open` test) work in Phase 1 with deferred enrollment? | **YES on Mac side**, **NO on iPad side**. Phase 1 SC#2 is a Mac-side daemon ↔ Mac app test only. The iPad side gets the App Group entitlement *declared* in `.entitlements` (so it's ready for Phase 8 enrollment), but the entitlement-validated runtime check happens later. |
| Will CI verify SC#2? | **NO.** `CODE_SIGNING_ALLOWED=NO` strips entitlements; SC#2 is a local-dev-machine acceptance check, not a CI check. |

**Recommendation:** 
- Declare the App Group entitlement in **all three** target `.entitlements` files (positioned correctly for Phase 8).
- Do **NOT** enable `com.apple.security.app-sandbox` on either Mac target in Phase 1 — sandbox without proper App Group authorization will block container access. (Sandbox can be added in Phase 8 when paid enrollment lands.)
- Phase 1 SC#2 acceptance is verified by a **manual test runbook** for the user to execute on their Mac, not by CI.

**Confidence: MEDIUM-HIGH.** The cross-platform App Group nuance is well-documented across multiple Apple forum threads but Apple's own central doc page is shallow. The recommendation is the conservative path that keeps Phase 1 deliverable without enrollment.

### Q5: PrivacyInfo.xcprivacy for `mach_absolute_time` — `CA92.1` is correct

**Verified against Apple documentation:**

`mach_absolute_time` falls under `NSPrivacyAccessedAPICategorySystemBootTime`, which has **three** valid reason codes:

| Reason code | Meaning |
|-------------|---------|
| `35F9.1` | Measuring performance |
| `3D61.1` | Obvious functionality |
| **`CA92.1`** | **Approximate time interval** |

CONTEXT.md and REQUIREMENTS.md both specify `CA92.1`, which is the most accurate reason for Cortex's use case (computing elapsed time intervals for latency measurement and frame pacing — explicitly an "approximate time interval" use, not raw boot-time access).

[VERIFIED: developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api]

> ⚠️ Note: A medium.com article surfaced in my search incorrectly claimed `CA92.1` was for UserDefaults only. This is wrong — `CA92.1` is **also** the "App functionality" reason in the UserDefaults category. The same reason code string is used in multiple categories with category-specific meaning. The category dictates the meaning, not the code. The CONTEXT.md commitment to `CA92.1` for `mach_absolute_time` is correct.

**Phase 1 PrivacyInfo.xcprivacy structure (XML plist):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key>
  <false/>
  <key>NSPrivacyTrackingDomains</key>
  <array/>
  <key>NSPrivacyCollectedDataTypes</key>
  <array/>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array>
        <string>CA92.1</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
```

**File placement:**
- One `PrivacyInfo.xcprivacy` per app target (CortexiOS and CortexMac).
- Lives at the **bundle root** of the app — NOT in a subdirectory. Add it to the target's "Copy Bundle Resources" build phase via XcodeGen's `sources:` (XcodeGen auto-adds plist resources).
- The daemon bundle does NOT need its own `PrivacyInfo.xcprivacy` in Phase 1 (it ships no required-reason API usage; it's an empty `main()`). Add when daemon code lands in Phase 2/3.

**Validation tooling:** Apple ships **no first-party validator**. The CI script must be hand-rolled. The minimum viable check is:

```bash
#!/usr/bin/env bash
# Tools/scripts/validate-privacy-manifest.sh
set -euo pipefail
MANIFEST="$1"  # e.g., Apps/CortexMac/PrivacyInfo.xcprivacy
plutil -lint "$MANIFEST"
plutil -extract NSPrivacyAccessedAPITypes raw "$MANIFEST" >/dev/null
# Confirm CA92.1 reason code is declared
plutil -convert xml1 -o - "$MANIFEST" \
  | grep -q '<string>CA92.1</string>' \
  || { echo "ERROR: CA92.1 reason code missing from $MANIFEST"; exit 1; }
echo "OK: $MANIFEST is valid plist with CA92.1 declared"
```

Xcode 26 itself surfaces some `PrivacyInfo.xcprivacy` issues at build time (missing required-reason API for symbols it detects via static analysis), but the surface is *informational* — Xcode does not fail the build on a missing entry. The CI script is the load-bearing gate.

**Confidence: HIGH** for `CA92.1` being correct; **MEDIUM** for "Xcode 26 produces no build-time error on missing entries" — based on community reports, not exhaustively tested for the specific `mach_absolute_time` case.

### Q6: SwiftPM workspace pattern for two apps + N libraries + 1 helper bundle

**Verified pattern:**

| Layer | Tool | Owns |
|-------|------|------|
| Library compilation | SwiftPM `Package.swift` per package | Swift sources, C sources, header organization, dependency resolution |
| App + bundle compilation | XcodeGen-generated `.xcodeproj` | Target settings, entitlements, Info.plist, code signing, Run/Test schemes |
| Wiring layer | Xcode workspace (`.xcworkspace`) | References both `.xcodeproj` and `Packages/CortexCore/Package.swift` etc., produces unified scheme list |

**Empty SPM library minimum content (so `swift build` succeeds):**

```
Packages/CortexIPC/
├── Package.swift
├── Sources/
│   └── CortexIPC/
│       └── CortexIPC.swift   # File contents: just `// Reserved for Phase 2`
└── README.md
```

`Package.swift` for an empty stub:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "CortexIPC",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [.library(name: "CortexIPC", targets: ["CortexIPC"])],
  targets: [
    .target(
      name: "CortexIPC",
      swiftSettings: [
        .defaultIsolation(MainActor.self),  // Approachable Concurrency
      ]
    ),
  ]
)
```

[CITED: developer.apple.com/documentation/packagedescription/swiftsetting/defaultisolation, useyourloaf.com/blog/approachable-concurrency-in-swift-packages]

**Daemon bundle consuming SPM library:**

The daemon bundle target (declared in XcodeGen, not in any `Package.swift`) lists `CortexCore` as a `dependencies` entry. XcodeGen translates this into an Xcode "Embed Frameworks" or static-link build phase against the package product. This works for `type: bundle` targets — no special build-settings dance required.

> **Verify in Phase 1:** After XcodeGen generates the project, run `xcodebuild -showBuildSettings -target CortexDaemon` and confirm `OTHER_SWIFT_FLAGS` includes `-package-name CortexCore` (or the equivalent module map injection). If missing, escalate — daemon bundles can have surprising dependency resolution edge cases.

**Confidence: HIGH** for the workspace structure; **MEDIUM** for the daemon-bundle-depends-on-SPM specifics — needs first-generation smoke verification.

### Q7: C header inside a SwiftPM library (`cortex_shm.h`)

**Verified canonical pattern:** Mixed Swift+C in a single SwiftPM package requires **two targets** — one Swift, one C — because SwiftPM does not allow a single target to contain mixed-language source files.

Directory layout for the `CortexCore` package:

```
Packages/CortexCore/
├── Package.swift
├── Sources/
│   ├── CortexCore/                      # Swift target
│   │   ├── CortexCore.swift             # Re-exports CortexCoreC
│   │   ├── AppGroup.swift               # Swift API: container path discovery
│   │   └── Time.swift                   # Swift API: mach_absolute_time wrapper
│   └── CortexCoreC/                     # C target
│       ├── include/
│       │   └── cortex_shm.h             # Public header with _Static_assert
│       └── cortex_shm.c                 # Optional .c file (can be empty stub)
└── Tests/
    └── CortexCoreTests/
        └── ShmConstantsTests.swift      # Swift-side import test
```

`Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "CortexCore",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "CortexCore", targets: ["CortexCore"]),
  ],
  targets: [
    .target(
      name: "CortexCoreC",
      // No publicHeadersPath needed: SwiftPM auto-uses `include/` directory
      // The generated module map exposes everything in include/ as the
      // "CortexCoreC" Clang module.
      cSettings: [
        .define("CORTEX_PHASE", to: "1"),
      ]
    ),
    .target(
      name: "CortexCore",
      dependencies: ["CortexCoreC"],
      swiftSettings: [
        .defaultIsolation(MainActor.self),
      ]
    ),
    .testTarget(
      name: "CortexCoreTests",
      dependencies: ["CortexCore"]
    ),
  ]
)
```

[CITED: docs.swift.org/swiftpm — "Creating C language targets > Overview > Exposing C functions to Swift", verified via Context7 /apple/swift-package-manager]

**SwiftPM auto-generates the module map** for a C target with an `include/` directory. The Swift `CortexCore` target imports it as:

```swift
import CortexCoreC

public let cortexShmName = String(cString: CORTEX_SHM_NAME)
// ...
```

**The `_Static_assert` directive — verified to work:**

```c
// Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h
#ifndef CORTEX_SHM_H
#define CORTEX_SHM_H

#define CORTEX_SHM_NAME "/cortex.samples"

_Static_assert(sizeof(CORTEX_SHM_NAME) <= 32,
               "CORTEX_SHM_NAME exceeds Darwin PSHMNAMLEN (31 bytes + null terminator)");

#endif // CORTEX_SHM_H
```

`_Static_assert` is C11 standard, supported by Clang on every Apple platform. Triggers at C compilation time — the build fails before any Swift source is touched. [VERIFIED: C11 standard, confirmed against Clang documentation]

⚠️ **One known SwiftPM caveat surfaced in research:** `static_assert` in C++ headers can interact poorly with Swift's auto-synthesized member-wise initializers for C++ structs (issue swiftlang/swift#86730). This affects **C++** headers, not C. Since `cortex_shm.h` is pure C with no struct definitions, it is unaffected. If Phase 2/3 code adds C++ (e.g., for `rigtorp/SPSCQueue`), revisit.

**How the iOS / Mac / daemon targets consume the C header:**

- They depend on the `CortexCore` SPM library product (declared in XcodeGen `dependencies:`).
- Via `import CortexCore`, they get re-exported access to `CortexCoreC` symbols if `CortexCore.swift` does `@_exported import CortexCoreC` (recommended).
- The compile-time `_Static_assert` fires during the SPM build of `CortexCoreC`, which runs as a prerequisite of any target depending on `CortexCore`. **The Phase 1 invariant is built into the dependency graph itself** — exactly the "compile-time guarantees beat runtime ones" commitment.

**Confidence: HIGH** — directly verified against SwiftPM documentation and Context7 results.

### Q8: fastlane match in local-only mode

**Verified facts:**

`fastlane match` was designed around remote Git storage. There is no first-class "local-only" mode, but you can:

1. Initialize a local Git repository (e.g., `~/Library/Cortex-fastlane-certs/.git`) and reference it via `file://` URL.
2. Skip operations that require a Developer Team (since enrollment is deferred per D-09).

**Phase 1 placeholder Matchfile:**

```ruby
# fastlane/Matchfile
git_url("file:///Users/donmega/Library/Cortex-fastlane-certs")  # TBD: replaced with real GitHub URL in Phase 8
git_branch("main")
storage_mode("git")
type("development")  # development | adhoc | enterprise | appstore — Phase 8 sets to appstore
# app_identifier and team_id intentionally omitted — populated when enrollment lands
```

**Phase 1 placeholder Appfile:**

```ruby
# fastlane/Appfile
# app_identifier "com.donovansantine.cortex.mac"  # Commented out — no team yet
# apple_id "donovan.santine@utexas.edu"           # Commented out
# team_id ""                                       # Populated in Phase 8
```

**Phase 1 placeholder Fastfile:**

```ruby
# fastlane/Fastfile
default_platform(:mac)

platform :mac do
  desc "Phase 1 placeholder — fastlane scaffolding only"
  lane :placeholder do
    UI.message "fastlane scaffolded. Real lanes land in Phase 8 with paid enrollment."
  end
end
```

**Important:** Do NOT run `fastlane match init` in Phase 1 — it requires Apple Developer Portal access (and will prompt for Team ID). The Matchfile/Appfile/Fastfile are literal text files committed manually as placeholders.

**Confirm:** `bundle install` (Gemfile listing `fastlane`) should succeed without errors as a CI smoke. Don't actually invoke any fastlane lane in CI.

**Confidence: HIGH** for Matchfile syntax; **MEDIUM** for "fastlane match can be scaffolded without enrollment" — official docs imply enrollment is needed for any `match` invocation, but file-creation-only is unblocked.

### Q9: SwiftFormat 2026 + SwiftLint 2026

**SwiftFormat:**
- Latest series: 0.61.x (latest verified: 0.61.0+ as of late 2025; check `gh release view --repo nicklockwood/SwiftFormat` at planning time)
- Available as: SwiftPM command plugin, brew, mint, standalone binary

[CITED: github.com/nicklockwood/SwiftFormat — README]

**SwiftLint:**
- Latest series: 0.59.x (latest verified: 0.59.1)
- Available as: SwiftPM build-tool plugin (multiple community implementations: `lukepistrol/SwiftLintPlugin`, `usami-k/SwiftLintPlugin`), brew, standalone binary

[CITED: github.com/lukepistrol/SwiftLintPlugin]

**Recommendation: brew on the macos-15 runner, not SwiftPM plugins.** Reasoning:
1. macos-15 runner has brew pre-installed; `brew install swiftformat swiftlint` adds ~10s to cold runs (cached after first).
2. SwiftPM build plugins require Xcode 15's `ENABLE_USER_SCRIPT_SANDBOXING=NO` workaround, plus they run during Xcode build (not separable from `xcodebuild`). Phase 1 wants lint as a **separate** CI step that fails fast and clearly.
3. Plugins add a transitive dependency on the plugin author's release cadence.

**Starter `.swiftformat` config (Swift 6.2 + Approachable Concurrency-friendly):**

```
--swiftversion 6.2
--indent 2
--maxwidth 120
--linebreaks lf
--trimwhitespace always
--commas inline
--operatorfunc spaced
--ranges spaced
--semicolons never
--self remove
--patternlet hoist
--header strip
--exclude .build,Packages/*/.build,DerivedData
```

**Starter `.swiftlint.yml`:**

```yaml
disabled_rules:
  - line_length             # Already covered by SwiftFormat maxwidth
  - todo                    # Phase 1 codebase will have many TODOs
opt_in_rules:
  - empty_count
  - explicit_init
  - first_where
  - force_unwrapping
  - sorted_imports
  - unused_import
included:
  - Apps
  - Packages
excluded:
  - .build
  - Packages/*/.build
  - DerivedData
  - Apps/*/Generated
analyzer_rules:
  - unused_declaration
```

**Approachable Concurrency note:** As of SwiftLint 0.59, no concurrency-mode-specific rules need adjustment. SwiftLint reads `swift-tools-version: 6.2` in the package and adapts its parser.

**Confidence: HIGH** for tool versions; **MEDIUM** for "starter config is right" — opinion-laden, easy to revise per team taste.

### Q10: GitHub Actions cache key construction for SwiftPM + DerivedData

**Verified pattern (community-converged):**

```yaml
- name: Cache SwiftPM
  uses: actions/cache@v4
  with:
    path: |
      .build
      ~/Library/Caches/org.swift.swiftpm
      ~/Library/org.swift.swiftpm
    key: ${{ runner.os }}-spm-xcode26.3-${{ hashFiles('**/Package.resolved', '**/Package.swift') }}
    restore-keys: |
      ${{ runner.os }}-spm-xcode26.3-
      ${{ runner.os }}-spm-

- name: Cache DerivedData
  uses: actions/cache@v4
  with:
    path: ~/Library/Developer/Xcode/DerivedData
    key: ${{ runner.os }}-deriveddata-xcode26.3-${{ hashFiles('**/Package.resolved', '**/*.xcodeproj/project.pbxproj', 'project.yml') }}
    restore-keys: |
      ${{ runner.os }}-deriveddata-xcode26.3-
```

[CITED: github.com/marketplace/actions/xcode-cache, dev.to "Stop wasting GitHub Actions Minutes" — community-validated key format]

**Cache size considerations:**
- GitHub Actions per-repo cache limit: 10 GB total. DerivedData for a small Phase-1 project: 200-400 MB. SwiftPM cache: 50-200 MB. Safe.
- Cache eviction is LRU. With one PR/day, the cache stays warm. With infrequent commits, a full 30s build is the worst case.

**Apple-specific cache action consideration:** `irgaly/xcode-cache@v1` preserves file modification timestamps with nanosecond precision (Xcode's incremental build relies on these). For Phase 1's "build empty shell from scratch", this is overkill — `actions/cache@v4` is sufficient. Revisit when the codebase grows past 5-10k LOC and incremental build wins matter.

**Recommendation:** Use the two `actions/cache@v4` blocks above, keyed on Xcode major.minor + `Package.resolved` hash. Switch to `irgaly/xcode-cache` only if Phase-2+ build times exceed 2 minutes.

**Confidence: HIGH** for the pattern; **MEDIUM** for the recommendation about `irgaly/xcode-cache` — defer until performance pain materializes.

### Q11: PrivacyInfo.xcprivacy — minimum viable structure for Phase 1

Already covered in detail under Q5. **Minimum-viable file** for an app that uses only `mach_absolute_time` is the 14-line plist shown above. Two copies live in `Apps/CortexiOS/PrivacyInfo.xcprivacy` and `Apps/CortexMac/PrivacyInfo.xcprivacy` (one per app target). Daemon target needs its own only when it gains code calling required-reason APIs (Phase 2+).

### Q12: Branch protection and PR template for greenfield Apple project

**Branch protection (GitHub repo Settings → Branches):**
- Require PR before merge to `main`
- Require status checks to pass: select the `ci.yml` workflow's job names (e.g., `build-mac`, `build-ios`, `lint`)
- Do NOT require code review approvals (solo project — would block all merges)
- Allow force pushes: false (default)
- Allow deletions: false (default)
- Block bypass for admins: false (solo dev needs override capability for emergency fixes)

[VERIFIED: GitHub branch protection settings UI standards]

**PR template (`.github/pull_request_template.md`):**

```markdown
## What
Brief description of what this PR does.

## Why
Link to phase / requirement IDs (e.g., FOUND-02, IPC-04) and rationale.

## Verification
- [ ] CI green (build, lint, format, package resolve)
- [ ] Local manual checks performed (if applicable):
  - [ ] Mac app + daemon shm test (Phase 1 SC#2)
  - [ ] (Other phase-specific checks)
- [ ] No regression to architectural commitments (compile-time guarantees, no Catalyst, no `_ANEClient`, etc.)

## Open questions / follow-ups
- (none / list)
```

**Confidence: HIGH.**

### Q13: README + ADR scaffold for 2026 Apple project

**Phase 1 README (root `README.md`):** Per CONTEXT.md "Implementer's Discretion" — content shape is flexible. Minimum-viable for Phase 1:

```markdown
# Cortex.app

Neuralink-quality iPad/Mac BCI input pipeline clone — sub-25ms glass-to-glass neural cursor decoder on Apple Silicon.

> **Status:** Phase 1 / 10 (Foundation & 2026 Toolchain). See `.planning/STATE.md` for current position.

## What's here

- `Apps/CortexiOS` — iPadOS 26 app target (Swift 6.2)
- `Apps/CortexMac` — native AppKit macOS 26 Tahoe app (no Catalyst)
- `Apps/CortexDaemon` — placeholder background-helper bundle (App Group entitlement, empty `main()`)
- `Packages/CortexCore` — shared Swift+C library (App Group helpers, time utilities, `cortex_shm.h`)
- `Packages/CortexIPC` — empty stub, populated in Phase 2
- `Packages/CortexRender` — empty stub, populated in Phase 6
- `Packages/CortexDecoder` — empty stub, populated in Phase 5
- `docs/cortex-spec.md` — 935-source research synthesis (see also: rejected-alternatives table)
- `docs/adr/` — architecture decision records

## How to build

### Prerequisites
- macOS 26 Tahoe + Xcode 26.x (26.2 or later recommended)
- Swift 6.2 toolchain
- (Optional) [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate the project: `brew install xcodegen`
- (Optional) SwiftFormat + SwiftLint for local lint: `brew install swiftformat swiftlint`

### Build
```bash
xcodegen                                         # regenerate Cortex.xcodeproj from project.yml
open Cortex.xcworkspace                          # open in Xcode
# Or:
xcodebuild build -workspace Cortex.xcworkspace -scheme CortexMac -destination 'generic/platform=macOS'
```

### Phase 1 SC#2 manual verification
On a developer Mac with Personal Team auto-signing enabled:
1. Build CortexMac and CortexDaemon to a writable bundle path.
2. Launch CortexMac (it creates `~/Library/Group Containers/group.com.donovansantine.cortex.shared/` if absent).
3. Run the daemon binary as a separate process; confirm both can `shm_open("/cortex.samples", ...)` against a region inside the App Group container.
4. Document evidence (screenshot or log) in `.planning/phases/01-foundation-2026-toolchain/`.

## Spec
The full technical specification is in [`docs/cortex-spec.md`](docs/cortex-spec.md).

## License
TBD (deferred to v0/v1).
```

**ADR template (lightweight Markdown, MADR-inspired):**

```markdown
# ADR 0001 — Foundation and 2026 Toolchain

**Status:** Accepted
**Date:** 2026-04-28
**Deciders:** @donovansantine

## Context

Cortex.app is greenfield in 2026. Apple's 2026 baseline is macOS 26 Tahoe, Xcode 26, Swift 6.2 with Approachable Concurrency. The project requires a multi-target Apple workspace (iPadOS 26 app + native AppKit macOS 26 app + a daemon bundle) sharing SwiftPM library code, with a `PrivacyInfo.xcprivacy` declaration and `macos-15` GitHub Actions CI.

## Decision

1. **Project file generation: XcodeGen** (declarative YAML, no `.pbxproj` merge conflicts).
2. **Two app targets, no Catalyst.** CortexiOS for iPadOS, CortexMac for native AppKit. Phase 6 RENDER-08 requires `NSScreen.displayLink` which Catalyst cannot surface.
3. **SwiftPM-only dependency graph.** No CocoaPods. Shared code in `Packages/` consumed by all three targets.
4. **App Group entitlement scaffolded for all three targets** with macOS unsandboxed dev binaries enabling Phase-1 SC#2 cross-process `shm_open` test without requiring paid Developer Program enrollment.
5. **Apple Developer Program enrollment deferred to Phase 8.** Phase 1 CI uses `CODE_SIGNING_ALLOWED=NO`; local dev uses Personal Team auto-signing on Mac side only (iPad side gets entitlement *declared* for Phase 8 but is build-only locally).
6. **`PrivacyInfo.xcprivacy` with `CA92.1` ("Approximate time interval") under `NSPrivacyAccessedAPICategorySystemBootTime`.**
7. **Compile-time enforcement of `CORTEX_SHM_NAME` length** via `_Static_assert` in `cortex_shm.h` (Packages/CortexCore/Sources/CortexCoreC/include/).
8. **CI: `macos-15` runner, Xcode 26.3 selected via `setup-xcode` action.** Caches DerivedData and SwiftPM cache. Validates lint, format, package resolution, build (no signing).

## Consequences

- Phase 1 CI cannot validate App Group entitlement enforcement (CODE_SIGNING_ALLOWED=NO strips entitlements). SC#2 is verified manually on the developer Mac.
- iPad target's App Group entitlement is "declared but unauthorized" until Phase 8. Local builds for the iPad target will fail to install if the entitlement is enabled — Phase 1 keeps it declared but defers iPad on-device install to Phase 8.
- Switching to Tuist later (if scale demands) requires rewriting `project.yml` as `Project.swift` — manageable cost.
- Adopting `com.apple.security.app-sandbox` requires paid enrollment + provisioning profile. Sandbox is OFF in Phase 1 — added in Phase 8.

## Alternatives considered (rejected)

- **Tuist** — overkill for 3 Xcode targets; YAML simpler than Swift for this size.
- **Hand-rolled `.xcodeproj`** — `.pbxproj` merge conflicts are a known nightmare even for solo projects.
- **Mac Catalyst** — explicitly rejected per Phase 6 RENDER-08 (`NSScreen.displayLink` requires native AppKit).
- **CocoaPods** — explicitly rejected per cortex-spec.md §11 (deprecated/maintenance mode).
- **Pure SwiftPM (no `.xcodeproj`)** — cannot express App Group entitlements, Info.plist, or non-app bundles.
```

**Confidence: HIGH** — README + ADR are conventions, not technology. Both fit Phase 1's scope.

---

## Critical Findings

The four load-bearing findings the planner MUST honor:

### Finding #1 (LOAD-BEARING): App Group + Personal Team behaves differently on iOS vs macOS

- **iPad side (CortexiOS):** App Group entitlement **CANNOT** be authorized by Personal Team. Local on-device builds for iPad with App Group enabled will fail at install time. Workaround: declare the entitlement in `Apps/CortexiOS/Cortex.entitlements` (so Phase 8 work is positioned), but **do not run on-device locally with the entitlement active until Phase 8**. Simulator builds work fine (App Group is silently ignored on simulator).
- **Mac side (CortexMac + CortexDaemon):** App Group container `~/Library/Group Containers/group.com.donovansantine.cortex.shared/` is accessible to **unsandboxed** Mac binaries without provisioning profile authorization. Phase 1 SC#2 (cross-process `shm_open` test) IS achievable locally on Mac without paid enrollment, **provided the apps do NOT enable `com.apple.security.app-sandbox`**.

**Planner action:** 
- Phase 1 SC#2 verification is a **Mac-side-only manual test runbook** (not CI, not iPad).
- Do NOT add `com.apple.security.app-sandbox` to either Mac target in Phase 1.
- Document this explicitly in the README and the ADR.

### Finding #2 (LOAD-BEARING): `CODE_SIGNING_ALLOWED=NO` strips entitlements

`CODE_SIGNING_ALLOWED=NO` produces an unsigned binary. **No signature → no entitlement enforcement.** This means CI cannot validate Phase 1 SC#2 (the cross-process shm test) — CI's CODE_SIGNING_ALLOWED=NO build is a *compile-only smoke* that proves the project file, SwiftPM graph, and source code parse and link.

**Planner action:**
- Phase 1 SC#1 (CI builds an empty-shell signed app on every PR) — adjust expectation: CI builds an *unsigned* empty-shell app. The "signed" part of SC#1 is satisfied by a manual local Mac build with Personal Team. Document this asymmetry.
- Phase 1 SC#2 verification is local-dev-machine only.
- A separate non-blocking CI job *could* run a signed Mac build using ad-hoc `-` signing (no Apple ID needed), but this still cannot validate App Group runtime behavior — only that the bundle is sign-able.

### Finding #3 (LOAD-BEARING): macos-15 runner default Xcode is 16.4, NOT 26.x

The `macos-15-arm64` runner (image 20260421.0007.1) ships Xcode 26.0.1 / 26.1.1 / 26.2 / 26.3 pre-installed but **default is Xcode 16.4**. Using `xcodebuild` directly without selecting will silently invoke Xcode 16.4 and may build a binary incompatible with the macOS 26 / iPadOS 26 deployment targets.

**Planner action:**
- CI workflow MUST include `maxim-lobanov/setup-xcode@v1` with `xcode-version: '26.3'` (or `26.2` for stability — avoid 26.0.1 / 26.1 RC due to known test hang issues).
- Cache keys MUST include the Xcode version string so swapping versions invalidates the cache.

### Finding #4 (LOAD-BEARING): Daemon bundle target needs verification

XcodeGen + SwiftPM + a `type: bundle` macOS daemon target consuming a SwiftPM library is a less-trodden path. The pattern *should* work (SwiftPM library products are linkable into any Mach-O target), but Phase 1 must include an explicit verification step:

```bash
xcodebuild -showBuildSettings -workspace Cortex.xcworkspace -target CortexDaemon | grep -E '(OTHER_SWIFT_FLAGS|FRAMEWORK_SEARCH_PATHS|HEADER_SEARCH_PATHS)'
```

Confirm `CortexCore` and `CortexCoreC` modules are reachable. If broken, fall back to a `type: tool` (command-line executable) for the daemon — this loses the bundle wrapper but is fully proven for SPM consumption.

**Planner action:** include a Wave 0 task that runs this smoke and stops the phase if it fails (escalate to user with concrete error before continuing).

---

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Xcode | 26.3 (pin to specific point release) | IDE, compiler, code-signing, simulator | Required for macOS 26 / iPadOS 26 SDK access |
| Swift | 6.2 | Language + Approachable Concurrency | swift-tools-version: 6.2 in Package.swift |
| Swift Package Manager | bundled with Swift 6.2 | Library compilation + dependency graph | FOUND-04: SwiftPM only, no CocoaPods |
| XcodeGen | 2.x latest stable | Generate `.xcodeproj` from `project.yml` | Eliminates pbxproj merge conflicts; declarative YAML |
| GitHub Actions | macos-15 (Apple Silicon arm64) runner | CI build/lint/format gate | FOUND-05; only runner with Xcode 26.x pre-installed |
| SwiftFormat | 0.61.x latest | Code formatting | Industry standard, configurable, fast |
| SwiftLint | 0.59.x latest | Code linting | Industry standard, --strict mode for CI |
| fastlane | latest stable | Signing/distribution tooling (Phase 1 = placeholder) | Phase 8 will activate; Phase 1 commits scaffolding |

### Supporting

| Tool | Version | Purpose | When to use |
|------|---------|---------|-------------|
| `xcbeautify` | latest | Pretty xcodebuild output for CI logs | Wrap `xcodebuild` output in CI |
| `plutil` | bundled with macOS | Plist validation for PrivacyInfo manifest | `Tools/scripts/validate-privacy-manifest.sh` |
| `maxim-lobanov/setup-xcode@v1` | v1 | Select Xcode version on the runner | Required: macos-15 default is 16.4 |
| `actions/cache@v4` | v4 | DerivedData + SwiftPM cache | D-16 |
| `actions/checkout@v4` | v4 | Git checkout in CI | Standard |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| XcodeGen | Tuist | Tuist's caching matters at 10+ targets; Phase 1 has 3. Stick with XcodeGen. |
| brew SwiftFormat/SwiftLint | SwiftPM build plugins | Plugins require Xcode 15 sandbox workaround and run inside `xcodebuild`; brew gives faster fail-isolation. |
| `actions/cache@v4` | `irgaly/xcode-cache@v1` | irgaly preserves nanosecond mtimes for incremental builds; Phase 1's clean builds don't benefit. Revisit Phase 3+. |
| Personal Team auto-signing on Mac | Ad-hoc `-` signing | Personal Team gives proper code signature for App Group container access; ad-hoc may create container differently. |

### Installation (one-time on dev machine)

```bash
brew install xcodegen swiftformat swiftlint xcbeautify
gem install fastlane            # via Bundler in Phase 1 — see Gemfile
xcodes select 26.3              # if multiple Xcodes installed locally; install xcodes via brew
```

### CI installation

```yaml
- uses: maxim-lobanov/setup-xcode@v1
  with:
    xcode-version: '26.3'
- run: brew install xcodegen swiftformat swiftlint xcbeautify
```

---

## Architecture Patterns

### System Architecture Diagram

```
                   ┌──────────────────────────┐
                   │   .github/workflows/     │
                   │     ci.yml (macos-15)    │
                   └───────────┬──────────────┘
                               │
                               ▼
                   ┌──────────────────────────┐
                   │      project.yml          │
                   │      (XcodeGen spec)      │
                   └───────────┬──────────────┘
                               │ xcodegen
                               ▼
                   ┌──────────────────────────┐
                   │    Cortex.xcworkspace     │
                   │  (regenerated, gitignored)│
                   └─┬──────────┬──────────┬───┘
                     │          │          │
        ┌────────────▼──┐  ┌────▼────┐  ┌──▼────────┐
        │  CortexiOS    │  │CortexMac│  │CortexDaemon│
        │  (iPadOS 26)  │  │(AppKit) │  │  (bundle)  │
        └────────────┬──┘  └────┬────┘  └──┬────────┘
                     │          │          │
                     └─────┬────┴──────────┘
                           │ depends on
                           ▼
                ┌─────────────────────────┐
                │   Packages/CortexCore   │  ← only package with content in Phase 1
                │  ┌──────────┐           │
                │  │CortexCore│ Swift     │     Swift API surface:
                │  │          │           │     - AppGroup container path
                │  │          │           │     - mach_absolute_time wrapper
                │  └────┬─────┘           │
                │       │ @_exported      │
                │       ▼                 │
                │  ┌──────────┐           │
                │  │CortexCoreC│ C       │     C symbols:
                │  │  include/│           │     - CORTEX_SHM_NAME ("/cortex.samples")
                │  │ cortex_  │           │     - _Static_assert(sizeof <= 32) ← compile-time gate
                │  │  shm.h   │           │
                │  └──────────┘           │
                └─────────────────────────┘
                
        Packages/CortexIPC, CortexRender, CortexDecoder ── empty stubs (single .swift file)
        
        Per-target entitlements declare:
            com.apple.security.application-groups: [group.com.donovansantine.cortex.shared]
        
        Per-app-target Resources include:
            PrivacyInfo.xcprivacy → NSPrivacyAccessedAPICategorySystemBootTime / CA92.1
        
        CI flow (every PR):
            checkout → setup-xcode 26.3 → xcodegen → swift package resolve →
            xcodebuild build (CODE_SIGNING_ALLOWED=NO, both schemes) →
            swiftformat --lint . → swiftlint --strict →
            validate-privacy-manifest.sh → hotpath-policy.sh (no-op in Phase 1)
```

### Recommended Project Structure

```
Cortex/
├── Apps/
│   ├── CortexiOS/
│   │   ├── App.swift              # @main + scene
│   │   ├── ContentView.swift      # placeholder
│   │   ├── Info.plist
│   │   ├── Cortex.entitlements
│   │   └── PrivacyInfo.xcprivacy
│   ├── CortexMac/
│   │   ├── App.swift              # @main + AppKit AppDelegate
│   │   ├── ContentView.swift      # placeholder
│   │   ├── Info.plist
│   │   ├── Cortex.entitlements
│   │   └── PrivacyInfo.xcprivacy
│   └── CortexDaemon/
│       ├── main.swift             # empty `print("cortex daemon stub")` 
│       ├── Info.plist
│       └── Cortex.entitlements
├── Packages/
│   ├── CortexCore/
│   │   ├── Package.swift
│   │   ├── Sources/
│   │   │   ├── CortexCore/        # Swift target
│   │   │   │   ├── CortexCore.swift    # @_exported import CortexCoreC
│   │   │   │   ├── AppGroup.swift
│   │   │   │   └── Time.swift
│   │   │   └── CortexCoreC/       # C target
│   │   │       ├── include/
│   │   │       │   └── cortex_shm.h    # _Static_assert lives here
│   │   │       └── cortex_shm.c        # empty stub OR  one C function
│   │   └── Tests/
│   │       └── CortexCoreTests/
│   │           └── ShmConstantsTests.swift
│   ├── CortexIPC/
│   │   ├── Package.swift
│   │   ├── Sources/CortexIPC/CortexIPC.swift
│   │   └── README.md
│   ├── CortexRender/  (same shape)
│   └── CortexDecoder/ (same shape)
├── Tools/
│   └── scripts/
│       ├── validate-privacy-manifest.sh
│       └── hotpath-policy.sh
├── docs/
│   ├── cortex-spec.md          # moved from repo root in this phase
│   └── adr/
│       └── 0001-foundation-and-2026-toolchain.md
├── fastlane/
│   ├── Fastfile
│   ├── Matchfile
│   └── Appfile
├── .github/
│   ├── workflows/
│   │   └── ci.yml
│   └── pull_request_template.md
├── .gitignore
├── .swiftformat
├── .swiftlint.yml
├── Cortex.xcworkspace          # generated, gitignored
├── Cortex.xcodeproj            # generated, gitignored
├── Gemfile                     # for fastlane (Bundler)
├── Gemfile.lock
├── project.yml                 # XcodeGen spec (checked in)
├── Package.resolved            # SwiftPM workspace lockfile (checked in)
├── README.md
└── AGENTS.md                   # already exists, untouched
```

### Pattern 1: Compile-time invariant (the load-bearing pattern)

**What:** Use C preprocessor `_Static_assert` in a header consumed by both C and Swift to fail the build if an invariant breaks.

**When to use:** Whenever a constant or struct layout must satisfy a system constraint (e.g., max length, alignment).

**Example (Phase 1 cortex_shm.h):**

```c
// Source: project-defined; pattern verified via Clang C11 standard
#ifndef CORTEX_SHM_H
#define CORTEX_SHM_H

#define CORTEX_SHM_NAME "/cortex.samples"

_Static_assert(sizeof(CORTEX_SHM_NAME) <= 32,
               "CORTEX_SHM_NAME exceeds Darwin PSHMNAMLEN (31 bytes + null terminator)");

#endif // CORTEX_SHM_H
```

When the header is consumed by `import CortexCoreC` from Swift, the Clang precompile step still runs the static_assert, failing the build before Swift type-checks.

### Pattern 2: Declarative project file

**What:** Express Xcode project structure in YAML; regenerate `.xcodeproj` from spec; gitignore the generated files.

**When to use:** Multi-target Apple projects where `.pbxproj` merge conflicts are a recurring problem (and they always are once 2+ humans or 2+ branches touch it).

**Example (excerpt from Q1 above):** see `project.yml` skeleton.

### Pattern 3: Mixed Swift+C in one SwiftPM package

**What:** Two targets in one Package.swift — a C target with `include/` directory and a Swift target depending on it.

**When to use:** When Swift code needs to call into existing C code, or when a C constant must enforce a compile-time invariant visible to Swift (this project's exact case).

**Example:** see Q7 above.

### Anti-Patterns to Avoid

- **Single Universal app target with Catalyst checkbox.** Disqualified by Phase 6 RENDER-08 (NSScreen.displayLink). Use TWO app targets — iOS and native macOS.
- **Hand-editing `.pbxproj`.** Merge conflicts and silent target settings drift. Use XcodeGen.
- **Hand-rolling shm name length checks.** Use `_Static_assert` — runtime checks ship as code; compile-time checks are physically impossible to violate at runtime.
- **`com.apple.security.temporary-exception.shared-memory` entitlement.** Deprecated for App Store. Use App Group (FOUND-02). [VERIFIED: cortex-spec.md §4.3]
- **Defaulting `xcodebuild` to runner's default Xcode.** macos-15 default is 16.4, will silently build wrong SDK. Always pin via `setup-xcode`.
- **Sandbox-enabled Mac targets without paid enrollment.** Sandbox + unauthorized App Group = container access blocked. Defer sandbox to Phase 8.
- **CocoaPods anywhere.** FOUND-04 explicit. Use SwiftPM only.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Xcode project file | Hand-rolled `.xcodeproj`/`.pbxproj` | XcodeGen | pbxproj is opaque XML with mandatory UUIDs; merge conflicts are unrecoverable in practice |
| Plist parsing | Custom parser for `.xcprivacy` | `plutil` (macOS-bundled) | Apple plist format has subtle binary/XML/legacy quirks; `plutil` handles them |
| C/Swift bridging module map | Hand-written `module.modulemap` | SwiftPM auto-generated module map (just put headers in `include/`) | SwiftPM does the right thing for the umbrella-header pattern |
| Code formatter / linter | Project-local conventions enforced by code review | SwiftFormat + SwiftLint | Industry standards, fast, configurable, integrate with CI |
| GitHub Actions cache primitives | Bespoke S3 / GCS bucket | `actions/cache@v4` | Built-in, free, 10GB limit fits Phase 1 |
| Fastlane match alternatives | Bespoke certificate management | fastlane match (placeholder in Phase 1, real in Phase 8) | Industry standard for Apple cert management |
| Privacy manifest validator | Custom plist parser | `plutil -lint` + `grep` for required reason codes | Apple ships no validator; this 10-line bash script is correct |
| Xcode version selection on CI | `sudo xcode-select` shell command | `maxim-lobanov/setup-xcode@v1` | Action handles symlink + DEVELOPER_DIR + caveats Apple's docs miss |

**Key insight:** Phase 1 builds *no* runtime logic. Every "implementation task" is configuration. The hand-roll trap here is in the *configuration* layer (custom validators, custom shell scripts) — defeat it by leaning on existing conventions (XcodeGen YAML, SwiftPM module maps, GitHub Actions marketplace).

---

## Common Pitfalls

### Pitfall 1: macos-15 runner uses default Xcode 16.4 silently

**What goes wrong:** CI passes locally (developer Mac has Xcode 26.x explicitly selected), then fails or builds wrong SDK on CI (runner uses Xcode 16.4 default). Symptoms: cryptic "module not found" for macOS 26 SDK symbols, or the binary builds but is unusable on macOS 26 hardware.

**Why it happens:** Storage constraints on the macos-15 runner kept Xcode 26.x as opt-in. The default was set conservatively.

**How to avoid:** Always pin `xcode-version: '26.3'` via `setup-xcode` in CI. Document the requirement in README.

**Warning signs:** CI step "Print Xcode version" (run `xcodebuild -version` early in the workflow) — if it shows `Xcode 16.4`, the pin failed.

### Pitfall 2: Personal Team + iPad App Group install fails

**What goes wrong:** Developer adds App Group entitlement to CortexiOS, builds locally, hits Cmd-R on a physical iPad — install fails with "Provisioning profile doesn't include com.apple.security.application-groups".

**Why it happens:** iOS App Groups are a **restricted entitlement** requiring paid Developer Program enrollment. Personal Team cannot authorize it.

**How to avoid:** Two paths:
- **Path A (chosen for Cortex):** Declare the entitlement in the iPad target's `.entitlements` file (positions Phase 8) but **only run on iOS Simulator** locally in Phase 1 (simulator silently ignores App Group). Defer iPad on-device install to Phase 8 with paid enrollment.
- **Path B (rejected):** Remove App Group from iPad target until Phase 8. Requires re-doing entitlement work later — violates the "Phase 1 wires App Group so Phase 2 doesn't have to" goal.

**Warning signs:** Local Cmd-R install error mentioning App Groups; this is *expected* in Phase 1 if attempting iPad device install.

### Pitfall 3: `CODE_SIGNING_ALLOWED=NO` makes SC#1 a half-truth

**What goes wrong:** Phase 1 SC#1 says "CI builds a *signed* empty-shell app on every PR." Literal CI cannot do this without signing identities. If the planner takes SC#1 literally and tries to make CI sign the build, it will require either secrets in GitHub Actions (Apple Developer enrollment + ASC API key) or a brittle keychain-import-then-sign flow.

**Why it happens:** SC#1's "signed" word is aspirational — written before the signing-vs-CI tradeoff was fully thought through.

**How to avoid:** Re-read SC#1 with the user during planning. The pragmatic interpretation is:
- CI smoke proves *build*, not *signing*.
- "Signed empty-shell" is satisfied by a manual local Mac build with Personal Team auto-signing.
- Document this asymmetry in the README and ADR.
- Phase 8 reactivates the "signed in CI" target with real enrollment.

**Warning signs:** Planner proposes a CI step like "import signing certificate from secret" — this is the wrong path for Phase 1.

### Pitfall 4: Empty SPM package missing `Sources/{Name}/{Name}.swift` fails

**What goes wrong:** A `Package.swift` declares a target named `CortexIPC` but `Sources/CortexIPC/` is empty. `swift build` fails with "no source files for target".

**Why it happens:** SwiftPM requires at least one source file per target.

**How to avoid:** Each empty stub package gets one file with one comment:

```swift
// Packages/CortexIPC/Sources/CortexIPC/CortexIPC.swift
// Reserved for Phase 2 — POSIX shm + kqueue + recvmsg + AES-GCM transport.
// See REQUIREMENTS.md IPC-01 through IPC-07.
```

**Warning signs:** `swift package resolve` succeeds but `swift build` fails with "no source files".

### Pitfall 5: macOS sandbox enabled with App Group blocks container access

**What goes wrong:** Mac target enables `com.apple.security.app-sandbox = YES` and `com.apple.security.application-groups = [group.com.donovansantine.cortex.shared]`. Sandbox is OFF? container is accessible. Sandbox is ON without provisioning-profile-authorized App Group? Container access denied.

**Why it happens:** Sandbox enforces App Group entitlement against the provisioning profile's allowlist. Personal Team's profile doesn't include unauthorized entitlements.

**How to avoid:** Phase 1 keeps `com.apple.security.app-sandbox` OFF on all Mac targets. Sandbox is added in Phase 8 with paid enrollment.

**Warning signs:** Mac app launches but cannot read/write `~/Library/Group Containers/group.*/`; Console.app shows sandbox-deny messages.

### Pitfall 6: Daemon bundle build fails to consume SwiftPM library

**What goes wrong:** `CortexDaemon` is declared as `type: bundle` in XcodeGen with `dependencies: [package: CortexCore]`. Build fails with "no such module 'CortexCore'" because SwiftPM library products and `type: bundle` Mach-O combinations have edge cases.

**Why it happens:** XcodeGen translates `type: bundle` to MH_BUNDLE; not all SPM linkage paths handle bundles cleanly.

**How to avoid:** Phase 1 includes a Wave 0 verification step: after first XcodeGen run, build CortexDaemon and confirm CortexCore symbols are reachable. If broken, fall back to `type: tool` (executable) — this loses the bundle wrapper but is fully proven.

**Warning signs:** "no such module 'CortexCore'" or "Undefined symbols for architecture arm64: CortexCore.*" on CortexDaemon link step.

### Pitfall 7: PrivacyInfo.xcprivacy missing from app bundle Resources

**What goes wrong:** `PrivacyInfo.xcprivacy` exists in the source tree but is not added to the app target's "Copy Bundle Resources" build phase. The bundled app ships without the manifest. Apple's submission validator catches this in Phase 8 (App Store rejection) but Xcode 26 build does not.

**Why it happens:** XcodeGen needs the file in the target's `sources:` list to copy it.

**How to avoid:** Verify after first build:

```bash
xcodebuild build -scheme CortexMac ...
PRIVACY=$(find ~/Library/Developer/Xcode/DerivedData -name PrivacyInfo.xcprivacy -path '*Cortex.app*' | head -1)
test -f "$PRIVACY" || { echo "ERROR: PrivacyInfo.xcprivacy not in bundle"; exit 1; }
```

**Warning signs:** A grep for `PrivacyInfo.xcprivacy` inside the built `.app` bundle returns nothing.

---

## Code Examples

Verified patterns:

### Generate Xcode project from XcodeGen spec

```bash
# Source: github.com/yonaskolb/XcodeGen README
brew install xcodegen
xcodegen
# Generates Cortex.xcodeproj from project.yml in cwd
```

### SwiftPM Package.swift for mixed Swift+C target

```swift
// Source: docs.swift.org/swiftpm Creating C Language Targets, verified via Context7
// File: Packages/CortexCore/Package.swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "CortexCore",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "CortexCore", targets: ["CortexCore"]),
  ],
  targets: [
    .target(
      name: "CortexCoreC",
      cSettings: [.define("CORTEX_PHASE", to: "1")]
    ),
    .target(
      name: "CortexCore",
      dependencies: ["CortexCoreC"],
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    .testTarget(
      name: "CortexCoreTests",
      dependencies: ["CortexCore"]
    ),
  ]
)
```

### Compile-time shm-name-length assertion (the load-bearing pattern)

```c
// Source: C11 standard, ISO/IEC 9899:2011 §6.7.10 (Static assertions)
// File: Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h
#ifndef CORTEX_SHM_H
#define CORTEX_SHM_H

#define CORTEX_SHM_NAME "/cortex.samples"

_Static_assert(sizeof(CORTEX_SHM_NAME) <= 32,
               "CORTEX_SHM_NAME exceeds Darwin PSHMNAMLEN (31 bytes + null terminator)");

#endif // CORTEX_SHM_H
```

### Swift consumption of the C constant

```swift
// File: Packages/CortexCore/Sources/CortexCore/CortexCore.swift
@_exported import CortexCoreC

public enum Cortex {
  /// Canonical shared-memory region name. Compile-time-validated to fit Darwin PSHMNAMLEN.
  public static let shmName: String = String(cString: CORTEX_SHM_NAME)
}
```

### PrivacyInfo.xcprivacy for mach_absolute_time

```xml
<!-- Source: developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api -->
<!-- File: Apps/CortexMac/PrivacyInfo.xcprivacy (and Apps/CortexiOS/...) -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key>
  <false/>
  <key>NSPrivacyTrackingDomains</key>
  <array/>
  <key>NSPrivacyCollectedDataTypes</key>
  <array/>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array>
        <string>CA92.1</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
```

### Privacy manifest validator script

```bash
#!/usr/bin/env bash
# Source: project-defined; uses macOS-bundled plutil + grep
# File: Tools/scripts/validate-privacy-manifest.sh
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <PrivacyInfo.xcprivacy> [more...]"
  exit 2
fi

for MANIFEST in "$@"; do
  echo "checking $MANIFEST"
  plutil -lint "$MANIFEST" >/dev/null
  plutil -extract NSPrivacyAccessedAPITypes raw "$MANIFEST" >/dev/null
  if ! plutil -convert xml1 -o - "$MANIFEST" | grep -q '<string>CA92.1</string>'; then
    echo "ERROR: $MANIFEST missing CA92.1 reason code for mach_absolute_time"
    exit 1
  fi
  if ! plutil -convert xml1 -o - "$MANIFEST" \
      | grep -q '<string>NSPrivacyAccessedAPICategorySystemBootTime</string>'; then
    echo "ERROR: $MANIFEST missing NSPrivacyAccessedAPICategorySystemBootTime"
    exit 1
  fi
  echo "OK: $MANIFEST"
done
```

### Hot-path policy script (no-op in Phase 1, gate ready for Phase 2/3)

```bash
#!/usr/bin/env bash
# Source: project-defined per D-15
# File: Tools/scripts/hotpath-policy.sh
set -euo pipefail

DIRS=("Packages/CortexIPC/Sources" "Packages/CortexCore/Sources")
FORBIDDEN=("dispatch_async" "lazy var" "pthread_mutex" "import Foundation" "import ObjectiveC")

EXIT=0
for DIR in "${DIRS[@]}"; do
  if [[ ! -d "$DIR" ]]; then continue; fi
  for PATTERN in "${FORBIDDEN[@]}"; do
    if grep -r -n --include='*.swift' --include='*.c' --include='*.h' \
       -F "$PATTERN" "$DIR" 2>/dev/null; then
      echo "ERROR: forbidden hot-path token '$PATTERN' found in $DIR"
      EXIT=1
    fi
  done
done

exit $EXIT
```

### GitHub Actions ci.yml

```yaml
# Source: project-defined per D-13; verified against actions/runner-images macos-15 image
# File: .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-lint:
    runs-on: macos-15
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 26.3
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '26.3'

      - name: Print versions
        run: |
          xcodebuild -version
          swift --version

      - name: Install tooling
        run: brew install xcodegen swiftformat swiftlint xcbeautify

      - name: Cache SwiftPM
        uses: actions/cache@v4
        with:
          path: |
            .build
            ~/Library/Caches/org.swift.swiftpm
            ~/Library/org.swift.swiftpm
          key: ${{ runner.os }}-spm-xc26.3-${{ hashFiles('**/Package.resolved', '**/Package.swift') }}
          restore-keys: |
            ${{ runner.os }}-spm-xc26.3-
            ${{ runner.os }}-spm-

      - name: Cache DerivedData
        uses: actions/cache@v4
        with:
          path: ~/Library/Developer/Xcode/DerivedData
          key: ${{ runner.os }}-dd-xc26.3-${{ hashFiles('**/Package.resolved', 'project.yml') }}
          restore-keys: |
            ${{ runner.os }}-dd-xc26.3-

      - name: Generate Xcode project
        run: xcodegen

      - name: Resolve SwiftPM
        run: swift package resolve

      - name: SwiftFormat (lint)
        run: swiftformat --lint .

      - name: SwiftLint (strict)
        run: swiftlint --strict

      - name: Validate PrivacyInfo
        run: |
          ./Tools/scripts/validate-privacy-manifest.sh \
            Apps/CortexMac/PrivacyInfo.xcprivacy \
            Apps/CortexiOS/PrivacyInfo.xcprivacy

      - name: Hot-path policy (no-op in Phase 1)
        run: ./Tools/scripts/hotpath-policy.sh

      - name: Build CortexMac (unsigned smoke)
        run: |
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
            | xcbeautify --renderer github-actions

      - name: Build CortexiOS (unsigned smoke, simulator)
        run: |
          set -o pipefail
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
            | xcbeautify --renderer github-actions

      - name: Verify CortexDaemon was built (Phase 1 SC#2 prep)
        run: |
          DAEMON=$(find ~/Library/Developer/Xcode/DerivedData -name "CortexDaemon" -type d | head -1)
          test -d "$DAEMON" || { echo "ERROR: CortexDaemon bundle not produced"; exit 1; }
          echo "CortexDaemon bundle present at $DAEMON"
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `com.apple.security.temporary-exception.shared-memory` entitlement | App Group container | Pre-2020 deprecation | FOUND-02; cortex-spec.md §9 |
| `altool` for upload | `notarytool` | 2021 | DIST-01 (Phase 8, not Phase 1) |
| `CADisplayLink` for Metal | `CAMetalDisplayLink` | iOS 17 / macOS 14 (2023) | RENDER-01 (Phase 6) |
| CocoaPods | SwiftPM | CocoaPods maintenance mode (2024) | FOUND-04 |
| Xcode 16 / Swift 6.0 | Xcode 26 / Swift 6.2 (Approachable Concurrency) | September 2025 | FOUND-01 |
| GitHub-hosted Intel Macs | macos-15 (Apple Silicon) | August 2025 (`macos-latest` migration) | FOUND-05 |
| Hand-rolled `.pbxproj` | XcodeGen / Tuist generated | Long-standing community pattern | This phase |
| SwiftPM build plugin for SwiftLint (Xcode 15 sandboxing required workaround) | brew-installed binary on CI runner | Ongoing tradeoff | Q9 recommendation |

**Deprecated/outdated:**
- `CADisplayLink` for Metal (use `CAMetalDisplayLink`)
- `(B, S, C)` tensor layout (use BC1S — DEC-04)
- Mac Catalyst (RENDER-08 disqualifies)
- SCM_RIGHTS for FD passing (use mach_msg + MACH_MSG_PORT_DESCRIPTOR — IPC-03)
- shared-memory entitlement (use App Group)
- `_ANEClient` private API (App Store rejection)
- altool (use notarytool)
- CocoaPods (use SwiftPM)
- 4-head NDT1 (use h=1-2)
- `.all` for MLModelConfiguration.computeUnits (use `.cpuAndNeuralEngine`)

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | XcodeGen 2.x can correctly express a `type: bundle` macOS daemon target with App Group entitlement and SPM library dependency | Q1, Q6, Pitfall #6 | If XcodeGen has an edge case here, fall back to hand-edited `.xcodeproj` for the daemon target only OR use `type: tool` instead of `type: bundle`. Verified by Wave 0 smoke task. |
| A2 | macOS unsandboxed Mac binaries can use App Group container `~/Library/Group Containers/group.*` without provisioning profile authorization, even with Personal Team | Q4, Critical Finding #1 | If false, Phase 1 SC#2 cannot be verified locally without paid enrollment — Phase 1 SC#2 must be deferred to Phase 8 OR enrollment must be moved up. The forum thread cited (developer.apple.com/forums/thread/719897) is authoritative but old (~2024); verify by manual smoke test on dev machine before Phase 1 ends. |
| A3 | Xcode 26.3 on macos-15 runner does not have hang issues like 26.0.1/26.1 RC | Q2, Pitfall #1 | If 26.3 also hangs, pin to 26.2 (last known stable). |
| A4 | `_Static_assert` in pure C header consumed by Swift via SwiftPM module map fires at C precompile time without Swift import errors | Q7 | If false, Cortex would need a different mechanism — e.g., a Swift `precondition` at module init OR a build-graph task that runs `cc -fsyntax-only cortex_shm.h`. The C++ caveat (issue #86730) does not apply here (no C++ structs). |
| A5 | Personal Team auto-signing on macOS produces a binary that can access App Group container path | Q4, Pitfall #5 | If false, fall back to ad-hoc `-` signing and verify container behavior. Worst case: SC#2 verification needs unsigned binaries OR a manually-created App Group container directory. |
| A6 | `CODE_SIGN_ENTITLEMENTS=""` on the xcodebuild command line does NOT cause "missing entitlements file" error when the target has one declared in pbxproj | Q3 | If errors occur, drop the override and accept that entitlements file is parsed but ignored at link time. |
| A7 | The `macos-15-arm64` runner image will continue to ship Xcode 26.x for the duration of Phase 1 work | Q2 | If GitHub deprecates Xcode 26 from macos-15 (e.g., to free space for Xcode 27), CI must migrate to `macos-26` runner. Track via runner-images repo. |
| A8 | fastlane gem can be installed via Bundler in Phase 1 without requiring an Apple Developer Team or running any lane | Q8 | If `bundle install` fails for some fastlane transitive dependency, simplify Gemfile to defer fastlane to Phase 8. |
| A9 | `swift-tools-version: 6.2` Package.swift compiles with `defaultIsolation(MainActor.self)` swift-setting on Xcode 26.3 | Q6 | If a syntax error appears, drop the `defaultIsolation` setting from Package.swift (Approachable Concurrency benefits are advisory at this stage; not load-bearing for Phase 1). |
| A10 | Phase 1 SC#1's "signed" qualifier can be relaxed to "built and lintable" for CI purposes (with manual signed local Mac build satisfying the literal interpretation) | Critical Finding #2, Pitfall #3 | If user insists CI must produce a signed binary, must escalate to either (a) ad-hoc signing in CI (does NOT validate App Group) or (b) move Apple Developer enrollment to Phase 1 (overrides D-09). |

---

## Open Questions

1. **SC#1 "signed empty-shell" interpretation.**
   - What we know: CI cannot sign without paid enrollment OR ad-hoc signing (which doesn't validate entitlements).
   - What's unclear: Does "signed" in SC#1 mean "validates entitlements at runtime" (impossible without enrollment) or "produces a Mach-O with a non-empty `LC_CODE_SIGNATURE` load command" (achievable via ad-hoc)?
   - **Recommendation:** Surface to user during planning. Two acceptable resolutions: (a) accept "build-only smoke" as CI's interpretation and document the Personal-Team-signed local build as the literal SC#1 satisfaction; (b) add a non-blocking "ad-hoc sign smoke" CI job that signs with `-`. Both are tractable; (a) is simpler.

2. **Daemon bundle smoke verification — what fallback if XcodeGen + `type: bundle` + SPM consumption breaks?**
   - What we know: Pattern *should* work but is less-trodden.
   - What's unclear: Specific failure mode if it doesn't.
   - **Recommendation:** Wave 0 verification task with explicit pass/fail criteria. If broken, fall back to `type: tool` (executable daemon stub) — loses bundle wrapper but proven path. Document the change in the ADR.

3. **iOS App Group with Personal Team — is simulator-only Phase 1 acceptable?**
   - What we know: iOS App Group on Personal Team blocks device install but works on simulator.
   - What's unclear: Does the user want any iPad on-device build to work in Phase 1, or is "simulator-only iPad until Phase 8" acceptable?
   - **Recommendation:** Surface to user. Recommend "simulator-only iPad in Phase 1" as the path that lets us scaffold App Group correctly without paying $99 early.

4. **SwiftLint vs SwiftFormat scope overlap.**
   - What we know: Both tools have overlapping rules (e.g., line length, trailing commas).
   - What's unclear: Authoritative rule precedence.
   - **Recommendation:** SwiftFormat owns formatting; SwiftLint owns semantic style. Disable overlapping SwiftLint rules where SwiftFormat already enforces. Phase 1 starter configs above reflect this split.

5. **Should `Package.resolved` for a workspace with empty SPM packages be checked in?**
   - What we know: SwiftPM convention is to commit `Package.resolved` for app-level packages and NOT for libraries.
   - What's unclear: For the workspace-level resolved file (which exists if the workspace has a Package.resolved at root).
   - **Recommendation:** Commit `Package.resolved` at workspace root (so CI cache key on `hashFiles('**/Package.resolved')` is stable). For empty stub packages, no Package.resolved exists yet. This becomes a real question in Phase 2 when external dependencies land.

6. **Hot-path policy script — should it also gate `Apps/CortexDaemon` once daemon code lands?**
   - What we know: D-15 specifies `Packages/CortexIPC/Sources/**` and `Packages/CortexCore/Sources/**`.
   - What's unclear: The daemon's empty `main()` will eventually do hot-path work in Phase 3.
   - **Recommendation:** Phase 1 follows D-15 verbatim. Phase 3 plan task to extend the policy to daemon source dirs.

---

## Environment Availability

> All dependencies are tooling for the developer machine. The macos-15 runner has them either pre-installed or installable via brew.

| Dependency | Required By | Available on Dev Mac | Available on macos-15 runner | Fallback |
|------------|-------------|----------------------|------------------------------|----------|
| Xcode 26.x | All build steps | Assumed yes (M4 dev machine) | ✓ (26.0.1, 26.1.1, 26.2, 26.3 pre-installed; 16.4 default) | None — must select via setup-xcode |
| Swift 6.2 | Package.swift, all source | bundled with Xcode 26 | bundled with Xcode 26 | None |
| XcodeGen 2.x | Project file generation | brew install xcodegen | brew install xcodegen (in workflow) | Fall back to hand-edited .xcodeproj (last resort) |
| SwiftFormat 0.61.x | Lint step | brew install swiftformat | brew install swiftformat (in workflow) | Skip lint as separate step; note in plan |
| SwiftLint 0.59.x | Lint step | brew install swiftlint | brew install swiftlint (in workflow) | Skip lint as separate step |
| xcbeautify | Pretty CI output | brew install xcbeautify | brew install xcbeautify | Use raw xcodebuild output (less readable) |
| fastlane (gem) | Phase 1 = placeholder, Phase 8 = active | gem via Bundler | not in Phase 1 CI | Gemfile commits the dependency; no CI install yet |
| `plutil` | PrivacyInfo validator | bundled with macOS | bundled with macOS | None — required |
| `git` | All operations | bundled with Xcode CLT | bundled | None |
| Personal Team Apple ID | Local Mac signing | Assumed yes (user has Apple ID) | N/A (CI doesn't sign) | Ad-hoc signing |
| Apple Developer Program enrollment | Phase 8 | NOT yet | N/A | Deferred to Phase 8 (per D-09) |

**Missing dependencies with no fallback:** None — Phase 1 is achievable with what the user has (M4 dev machine + Apple ID, no $99 enrollment).

**Missing dependencies with fallback:** Apple Developer Program enrollment is missing but explicitly deferred per D-09; fallback is "Phase 1 SC#2 verified locally on Mac side only, iPad on-device install deferred to Phase 8."

---

## Validation Architecture

> Per `.planning/config.json` `workflow.nyquist_validation: true`, this section is required.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (Swift 6.2 default) + XCTest fallback for Xcode integration |
| Config file | None — Swift Testing is in-language; XCTest scheme test plan if needed |
| Quick run command | `swift test --package-path Packages/CortexCore` |
| Full suite command | `xcodebuild test -workspace Cortex.xcworkspace -scheme CortexMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` |

### Phase Requirements → Test Map

> Phase 1 ships almost no runtime logic. Most "tests" are CI checks (build, lint, format, plist validation, manual verification runbooks).

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FOUND-01 | Project builds with Xcode 26 + Swift 6.2 on macOS 26 / iPadOS 26 targets | smoke (build) | `xcodebuild build -workspace Cortex.xcworkspace -scheme CortexMac -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO ...` | ❌ Wave 0: ci.yml + project.yml |
| FOUND-01 | `_Static_assert` on `CORTEX_SHM_NAME` length fires if name exceeds 31 bytes | unit (compile-time) | `swift build --package-path Packages/CortexCore` (would fail to compile if asserted constraint broken) | ❌ Wave 0: cortex_shm.h |
| FOUND-01 | Swift target can import `CortexCoreC` and read `CORTEX_SHM_NAME` | unit (Swift Testing) | `swift test --package-path Packages/CortexCore --filter CortexCoreTests/ShmConstantsTests` | ❌ Wave 0: ShmConstantsTests.swift |
| FOUND-02 | App Group entitlement is declared on all three targets | static (entitlements file diff) | `grep -l 'group.com.donovansantine.cortex.shared' Apps/*/Cortex.entitlements \| wc -l` returns 3 | ❌ Wave 0: 3× .entitlements files |
| FOUND-02 | Cross-process `shm_open("/cortex.samples", ...)` works between CortexMac and CortexDaemon, both inside App Group container | manual (runbook) | local Mac: launch CortexMac, launch CortexDaemon as separate process, verify both can open shm region; document evidence | ❌ Wave 0: README runbook + manual evidence file |
| FOUND-03 | `PrivacyInfo.xcprivacy` exists for both app targets and is a valid plist | static (plutil + grep) | `./Tools/scripts/validate-privacy-manifest.sh Apps/CortexMac/PrivacyInfo.xcprivacy Apps/CortexiOS/PrivacyInfo.xcprivacy` | ❌ Wave 0: 2× .xcprivacy + script |
| FOUND-03 | `CA92.1` is declared as a reason code for `mach_absolute_time` in both manifests | static (validator script) | same as above | ❌ Wave 0: validator script + manifests |
| FOUND-03 | `PrivacyInfo.xcprivacy` is included in built app bundle | smoke (find inside .app) | `find ~/Library/Developer/Xcode/DerivedData -name PrivacyInfo.xcprivacy -path '*Cortex.app*'` returns at least one match | ❌ Wave 0: post-build CI step |
| FOUND-04 | No `Podfile`, no `Pods/` directory anywhere in repo | static | `! find . -name Podfile -o -name 'Pods' -type d 2>/dev/null \| grep -q .` | ❌ Wave 0: CI step |
| FOUND-04 | `swift package resolve` succeeds from clean clone | smoke | `rm -rf .build ~/Library/Caches/org.swift.swiftpm && swift package resolve` (CI does this naturally on cache miss) | ❌ Wave 0: ci.yml step |
| FOUND-04 | All four packages have valid Package.swift | smoke | for each: `cd Packages/$PKG && swift package describe` | ❌ Wave 0: 4× Package.swift |
| FOUND-05 | CI runs on macos-15 with Xcode 26.x selected | smoke (CI runtime check) | CI step: `xcodebuild -version` output starts with `Xcode 26.` | ❌ Wave 0: ci.yml |
| FOUND-05 | CI completes in <10 min on warm cache, <5 min cold | non-functional | observe CI run duration; assert via job timeout-minutes setting | ❌ Wave 0: ci.yml + manual observation |
| D-15 (cross-phase) | Hot-path policy script catches forbidden tokens when present | unit (test the script) | `echo 'dispatch_async(...)' > /tmp/test.swift && DIRS=/tmp ./Tools/scripts/hotpath-policy.sh; test $? -eq 1` | ❌ Wave 0: script + (optional) self-test |

### Sampling Rate

- **Per task commit:** `swift package resolve && swift test --package-path Packages/CortexCore` (≤30s) — fast feedback for SwiftPM changes.
- **Per wave merge:** Full ci.yml workflow (≤10 min on warm cache).
- **Phase gate:** Full ci.yml green + manual SC#2 runbook completed with evidence in repo.

### Wave 0 Gaps

- [ ] `Packages/CortexCore/Package.swift` — Swift+C target structure
- [ ] `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h` — with `_Static_assert`
- [ ] `Packages/CortexCore/Sources/CortexCoreC/cortex_shm.c` — empty stub or one C function
- [ ] `Packages/CortexCore/Sources/CortexCore/CortexCore.swift` — `@_exported import CortexCoreC`
- [ ] `Packages/CortexCore/Tests/CortexCoreTests/ShmConstantsTests.swift` — Swift-side import test
- [ ] `Packages/{CortexIPC,CortexRender,CortexDecoder}/Package.swift` — empty stub manifests
- [ ] `Packages/{CortexIPC,CortexRender,CortexDecoder}/Sources/{Pkg}/{Pkg}.swift` — single-file stubs
- [ ] `Apps/CortexiOS/{App.swift,ContentView.swift,Info.plist,Cortex.entitlements,PrivacyInfo.xcprivacy}`
- [ ] `Apps/CortexMac/{App.swift,ContentView.swift,Info.plist,Cortex.entitlements,PrivacyInfo.xcprivacy}`
- [ ] `Apps/CortexDaemon/{main.swift,Info.plist,Cortex.entitlements}`
- [ ] `project.yml` — XcodeGen spec
- [ ] `Tools/scripts/validate-privacy-manifest.sh`
- [ ] `Tools/scripts/hotpath-policy.sh`
- [ ] `.github/workflows/ci.yml`
- [ ] `.github/pull_request_template.md`
- [ ] `.swiftformat`
- [ ] `.swiftlint.yml`
- [ ] `.gitignore` (Xcode + Swift template)
- [ ] `Gemfile` + `Gemfile.lock` (fastlane)
- [ ] `fastlane/{Fastfile,Matchfile,Appfile}` — placeholders
- [ ] `docs/cortex-spec.md` — moved from repo root
- [ ] `docs/adr/0001-foundation-and-2026-toolchain.md`
- [ ] `README.md` — top-level
- [ ] Manual SC#2 runbook execution + evidence file (after build succeeds)

> **Important:** Phase 1 has near-zero unit-testable runtime behavior. The Validation Architecture is dominated by *static* checks (entitlements declared, manifest plist valid, no Pods, no Catalyst, etc.) and one *manual runbook* for SC#2. This is correct for a foundation phase — actual runtime tests grow exponentially in Phases 2-7. Don't pad with fake unit tests in Phase 1.

---

## Project Constraints (from AGENTS.md)

The following actionable directives are extracted from `./AGENTS.md` and constrain the planner:

1. **Apple Silicon (M4) only.** No x86 fallback. ARM64-only build settings.
2. **Xcode 26 + Swift 6.2 + macOS 26 Tahoe / iPadOS 26.** No regression to older toolchains. (Drives FOUND-01.)
3. **6-7 week sprint, v0 by week 5, v1 by week 7.** Phase 1 is week 1; cannot consume more than 5-7 days of effort.
4. **Single-user, on-device. No cloud, no multi-user, no real BCI hardware.** No multi-tenant entitlements (no `com.apple.developer.networking.*`, no iCloud, etc.).
5. **App Store path required.** No `_ANEClient`, no deprecated entitlements, privacy manifest required, notarized. (Phase 1 lays the groundwork — privacy manifest, no shared-memory entitlement, no `_ANEClient`. Notarization itself is Phase 8.)
6. **Hot-path threading rules** (from AGENTS.md): pthread + USER_INTERACTIVE only, no dispatch_async, no Obj-C runtime, no locks, no ARC. Phase 1 has no hot-path code, but `D-15` hot-path policy script is the trap pre-armed.
7. **GSD Workflow enforcement:** All file changes go through GSD commands (`/gsd-execute-phase` for planned work). Plan tasks must align with this.
8. **No emoji unless requested.** Code, docs, commit messages stay text-only.

The planner MUST verify the plan does not contradict any AGENTS.md directive.

---

## Sources

### Primary (HIGH confidence)
- **Apple Developer Documentation — Required Reason API** (developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) — `mach_absolute_time` reason codes, including verified `CA92.1`
- **Apple Developer Documentation — App Groups Entitlement** (developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)
- **Apple Developer Forums Thread 721701** — "App Groups: macOS vs iOS: Working" (eskimo's authoritative answer on iOS-style vs macOS-style App Group IDs and Personal Team behavior)
- **Apple Developer Forums Thread 719897** — "Is opening Shared memory allowed in sandbox" (Apple DTS engineer's authoritative answer on `shm_open` + App Group)
- **GitHub actions/runner-images macos-15-arm64-Readme.md** (image 20260421.0007.1) — verified Xcode 26.x availability and default-is-16.4
- **Swift Package Manager docs** (docs.swift.org/swiftpm) via Context7 `/apple/swift-package-manager` — C target with `include/` directory pattern, module map auto-generation
- **XcodeGen ProjectSpec.md** via Context7 `/yonaskolb/xcodegen` — entitlements + Info.plist generation, multi-platform target syntax, SwiftPM local package consumption

### Secondary (MEDIUM confidence)
- **fastlane match docs** (docs.fastlane.tools/actions/match) — Matchfile syntax (verified for git_url; "local-only mode" inferred not first-class)
- **github.com/maxim-lobanov/setup-xcode** — Xcode version selection action
- **github.com/nicklockwood/SwiftFormat README** — version 0.61.x latest, SwiftPM plugin caveats
- **github.com/lukepistrol/SwiftLintPlugin** — SwiftPM build plugin pattern (rejected in favor of brew)
- **swift.org Swift 6.2 release notes** — Approachable Concurrency, `defaultIsolation(MainActor.self)` setting
- **avanderlee.com / useyourloaf.com / mjtsai.com** — Approachable Concurrency in Swift Packages (cross-verified)

### Tertiary (LOW confidence — flagged in Open Questions)
- **github.com/actions/runner-images/issues/13264** — Xcode 26.0.1 / 26.1 RC test hang reports (single-source community report; pin to 26.2/26.3 to defensively avoid)
- **medium.com / blog posts** — anecdotal references to App Group + Personal Team behavior; superseded by Apple Forums sources

---

## Metadata

**Confidence breakdown:**

- **Standard stack (Xcode 26 / Swift 6.2 / SwiftPM):** HIGH — directly verified against runner image manifest and Swift toolchain docs.
- **Architecture (XcodeGen + multi-target + SwiftPM):** HIGH for the pattern; MEDIUM for Xcode-26-specific edge cases (verify after first generation).
- **App Group + Personal Team interaction (LOAD-BEARING):** MEDIUM-HIGH. The cross-platform nuance is well-documented across multiple Apple Forum threads (721701, 719897) but Apple's central docs are shallow. Recommendation is conservative.
- **PrivacyInfo CA92.1 correctness:** HIGH — verified against Apple's primary Required Reason API documentation.
- **CI patterns (cache, setup-xcode, xcodebuild flags):** HIGH for setup-xcode and cache; MEDIUM for the exact 5-flag CODE_SIGNING_ALLOWED=NO incantation (community wisdom, not single Apple doc).
- **fastlane scaffolding without enrollment:** MEDIUM — official docs imply enrollment is needed for any actual `match` invocation; Phase 1 commits files only.
- **`_Static_assert` in C header consumed by Swift via SPM:** HIGH for pure C; MEDIUM for any future C++ migration (issue #86730 caveat).

**Research date:** 2026-04-28
**Valid until:** 2026-05-28 (30 days — toolchain is stable post-Xcode 26.3 release; revisit when Xcode 27 ships or runner-image deprecates 26.x)

---

## Recommended Plan Skeleton

The planner should produce approximately the following plan structure (final granularity is the planner's call). All plans assume the Wave 0 list above is consumed in plan order.

### Plan 1: Repo skeleton + XcodeGen spec + SwiftPM package stubs (FOUND-01, FOUND-04)
- Create directory structure (`Apps/`, `Packages/`, `Tools/`, `docs/`, `fastlane/`, `.github/`)
- Write `project.yml` (XcodeGen spec) with three targets, four packages, deployment targets, bundle IDs, entitlements paths, Info.plist paths
- Write four `Package.swift` files (CortexCore mixed Swift+C; three empty stubs)
- Add minimum-viable source files for each package (one `.swift` per stub; CortexCore.swift + CortexCoreC structure)
- Write `cortex_shm.h` with `_Static_assert` (load-bearing, compile-time gate)
- Write `ShmConstantsTests.swift` (Swift-side smoke import)
- Write `.gitignore` (Apple/Swift standard template)
- Move `cortex-spec.md` from repo root to `docs/cortex-spec.md`
- Verify: `xcodegen` generates `.xcodeproj`/`.xcworkspace`; `swift build --package-path Packages/CortexCore` succeeds

### Plan 2: App and daemon target source stubs (FOUND-01, FOUND-02)
- Write `Apps/CortexiOS/{App.swift, ContentView.swift, Info.plist, Cortex.entitlements}`
- Write `Apps/CortexMac/{App.swift, ContentView.swift, Info.plist, Cortex.entitlements}` (native AppKit, no SwiftUI App lifecycle for the Mac side — defensive against accidental Catalyst behavior)
- Write `Apps/CortexDaemon/{main.swift, Info.plist, Cortex.entitlements}` with empty `main()`
- Three `Cortex.entitlements` files declare `group.com.donovansantine.cortex.shared` App Group
- Critically: do NOT enable `com.apple.security.app-sandbox` on Mac targets in Phase 1 (per Critical Finding #1)
- Verify: `xcodegen && xcodebuild build -workspace Cortex.xcworkspace -scheme CortexMac -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO` succeeds for both schemes; `CortexDaemon` bundle is produced

### Plan 3: Privacy manifest + validator (FOUND-03)
- Write `Apps/CortexiOS/PrivacyInfo.xcprivacy` and `Apps/CortexMac/PrivacyInfo.xcprivacy` with `NSPrivacyAccessedAPICategorySystemBootTime` + `CA92.1`
- Write `Tools/scripts/validate-privacy-manifest.sh` (plutil + grep)
- Add the manifests to each target's `sources:` in `project.yml` so they ship in the bundle
- Verify: `./Tools/scripts/validate-privacy-manifest.sh` passes; built `.app` bundle contains `PrivacyInfo.xcprivacy`

### Plan 4: GitHub Actions CI workflow + caches (FOUND-05, D-13, D-16)
- Write `.github/workflows/ci.yml` (full content from Q above — checkout, setup-xcode 26.3, brew install tooling, cache SwiftPM and DerivedData, generate, resolve, lint, format, validate manifest, hot-path policy, build both schemes)
- Write `Tools/scripts/hotpath-policy.sh` (no-op in Phase 1; gate ready for Phase 2/3)
- Write `.swiftformat` and `.swiftlint.yml`
- Verify: push to a feature branch; CI green; warm-cache build under 10 min; cold-cache build under 30 min

### Plan 5: fastlane scaffolding (placeholder per D-10)
- Write `Gemfile` listing `fastlane`
- Write `fastlane/{Fastfile, Matchfile, Appfile}` as placeholders (Matchfile points to `file:///Users/donmega/Library/Cortex-fastlane-certs`)
- Verify: `bundle install` succeeds locally; do NOT run any fastlane lane in CI
- Document in README that fastlane is placeholder until Phase 8

### Plan 6: Documentation (README, ADR, branch protection, PR template)
- Write top-level `README.md` (per Q13)
- Write `docs/adr/0001-foundation-and-2026-toolchain.md` (per Q13)
- Write `.github/pull_request_template.md`
- Configure GitHub repo branch protection rules ("require CI green" only)
- Verify: README renders correctly on GitHub; ADR cross-references all decision IDs

### Plan 7 (manual): Phase 1 SC#2 verification runbook + evidence
- User executes manual cross-process `shm_open` test on dev Mac:
  - Build CortexMac and CortexDaemon locally with Personal Team
  - Launch CortexMac (creates App Group container)
  - Launch CortexDaemon as separate process
  - Both call `shm_open("/cortex.samples", O_RDWR | O_CREAT, 0666)` — both succeed; both can read/write a small region
- User documents evidence (screenshots, log output) in `.planning/phases/01-foundation-2026-toolchain/sc2-verification-evidence.md`
- Phase 1 is GO/NO-GO on this manual runbook completion

### Plan 8 (Wave 0 verification gate — runs early, before Plans 4-7)
- After Plans 1+2+3 land, run smoke checks:
  - `xcodebuild -showBuildSettings -workspace Cortex.xcworkspace -target CortexDaemon` — confirm `CortexCore` modules are reachable (Critical Finding #4 mitigation)
  - `xcodebuild build` for both app schemes succeeds with `CODE_SIGNING_ALLOWED=NO`
  - `swift test --package-path Packages/CortexCore` succeeds
  - Manually break `cortex_shm.h` (set `CORTEX_SHM_NAME = "/this.is.way.too.long.to.fit.in.31.bytes"`) and confirm build FAILS at C precompile (proving the `_Static_assert` works); revert
- If Wave 0 fails, escalate to user with concrete error before Plans 4-7 begin

---

## Ready for Planning

Research complete. Planner can now create PLAN.md files for the seven plans (one optional manual runbook + one verification gate) sketched above.

**Critical handoff items the planner must NOT lose:**
- Critical Finding #1 (App Group + Personal Team): iPad simulator-only locally; Mac unsandboxed
- Critical Finding #2 (CODE_SIGNING_ALLOWED=NO strips entitlements): SC#2 is local Mac, not CI
- Critical Finding #3 (macos-15 default Xcode is 16.4): MUST select 26.3 via setup-xcode
- Critical Finding #4 (daemon bundle + SPM library is less-trodden): Wave 0 verification task is required
- Cross-phase commitment "compile-time guarantees beat runtime ones": embedded in `_Static_assert` in `cortex_shm.h`
- The 10 assumptions in the Assumptions Log — surface to user during planning if any might be wrong
