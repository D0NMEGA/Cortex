# ADR 0001 -- Foundation and 2026 Toolchain

**Status:** Accepted
**Date:** 2026-04-28
**Deciders:** @donovansantine

## Context

Cortex.app is greenfield in 2026. Apple's 2026 baseline is macOS 26 Tahoe, Xcode 26,
Swift 6.2 (Approachable Concurrency). The project requires a multi-target Apple
workspace (iPadOS 26 app + native AppKit macOS 26 app + a daemon bundle) sharing
SwiftPM library code, with a `PrivacyInfo.xcprivacy` declaration and `macos-15`
GitHub Actions CI green on every PR.

The defining project claim is "Glass-to-glass latency 24.7 +/- 1.3 ms (p50, sigma=0.8 ms,
n=10k, photodiode-instrumented)". Every architectural choice in this ADR serves that
claim -- directly (latency-sensitive paths) or indirectly (build/CI infrastructure that
keeps the project shippable).

## Decision

Phase 1 commits to the following eight foundational decisions. Each decision lists the
CONTEXT.md decision IDs (D-XX) it implements:

### 1. XcodeGen for project file generation (D-01, D-02, D-04)

Express the Xcode project structure declaratively in `project.yml`. Regenerate
`Cortex.xcodeproj` and `Cortex.xcworkspace` from the spec; gitignore the generated
files. Phase 1 has 3 Xcode targets -- Tuist's caching value would only kick in around
10+ targets. XcodeGen's YAML is human-reviewable in PRs, and we eliminate `.pbxproj`
merge conflicts entirely.

### 2. Two app targets, NO Mac Catalyst (D-01)

`CortexiOS` for iPadOS 26. `CortexMac` for native AppKit macOS 26 Tahoe.
**No Mac Catalyst.** Phase 6 RENDER-08 explicitly requires `NSScreen.displayLink`,
which Catalyst does not surface cleanly. Defense-in-depth:

- `project.yml` sets `SUPPORTS_MACCATALYST: NO` on the CortexMac target.
- `Apps/CortexMac/App.swift` uses `NSApplicationDelegateAdaptor` (native AppKit
  lifecycle anchor -- Catalyst cannot synthesize this).

### 3. SwiftPM-only dependency graph (D-02, FOUND-04)

Shared code in `Packages/` (CortexCore, CortexIPC, CortexRender, CortexDecoder)
consumed by all three Xcode targets via SwiftPM. **No CocoaPods.** CocoaPods is in
maintenance mode; SwiftPM is the 2026 standard. CI fails the build if a `Podfile`
or `Pods/` directory ever appears in the repo.

### 4. App Group entitlement scaffolded for all three targets (D-07, FOUND-02)

App Group identifier: `group.com.donovansantine.cortex.shared`. Declared in
`Apps/CortexiOS/Cortex.entitlements`, `Apps/CortexMac/Cortex.entitlements`, and
`Apps/CortexDaemon/Cortex.entitlements`.

**Critical platform asymmetry (RESEARCH.md Critical Finding #1):**

- **iPad / iOS:** App Group is a *restricted* entitlement requiring paid Apple
  Developer Program enrollment. Personal Team cannot authorize it. Phase 1 declares
  the entitlement but iPad-on-device install is deferred to Phase 8 (when paid
  enrollment lands). Phase 1 verifies iPad **simulator** builds only -- simulator
  silently ignores App Group.
- **Mac (CortexMac + CortexDaemon):** App Group container
  `~/Library/Group Containers/group.com.donovansantine.cortex.shared/` is accessible
  to **unsandboxed** Mac binaries WITHOUT provisioning-profile authorization
  (per Apple Developer Forums Thread 721701, eskimo's authoritative answer; and
  Apple DTS Thread 719897 on `shm_open` + App Group). Phase 1 SC#2 (cross-process
  `shm_open` between CortexMac and CortexDaemon) IS verifiable locally without paid
  enrollment, **provided the apps do NOT enable `com.apple.security.app-sandbox`**.

Phase 1 keeps `com.apple.security.app-sandbox` OFF on Mac targets. Phase 8 will
re-add sandbox once paid enrollment + provisioning profile authorization is in place.

### 5. Apple Developer Program enrollment deferred to Phase 8 (D-09, D-10, D-11, D-12)

The $99/year enrollment is paid when Phase 8 needs real notarization and TestFlight.
Phase 1 ships with:

- Personal Team auto-signing for local Mac dev only (no iPad on-device).
- CI builds with `CODE_SIGNING_ALLOWED=NO` (the "signed" qualifier in SC#1 is
  satisfied by a manual local Personal-Team-signed Mac build, not by CI).
- fastlane scaffolded as placeholder: `Gemfile` + `fastlane/Fastfile,Matchfile,Appfile`
  exist with the Matchfile pointing to a local `file:///` URL. No real lanes invoked
  in CI. See Phase 1 Plan 04.
- App Store Connect API key (`.p8` JWT) is NOT provisioned in Phase 1. Phase 8 adds it.

**Critical CI-vs-local asymmetry (RESEARCH.md Critical Finding #2):**

`CODE_SIGNING_ALLOWED=NO` produces an unsigned binary. **No signature -> no entitlement
enforcement.** This means CI cannot validate Phase 1 SC#2 (the cross-process shm test).
CI's `CODE_SIGNING_ALLOWED=NO` build is a *compile-only smoke* that proves the project
file, SwiftPM graph, and source code parse and link. SC#2 is a local-dev-machine
manual runbook (see Plan 07 evidence file).

### 6. PrivacyInfo.xcprivacy with CA92.1 reason code (D-14, FOUND-03)

Both app targets ship `PrivacyInfo.xcprivacy` declaring `CA92.1` (Approximate time
interval) under `NSPrivacyAccessedAPICategorySystemBootTime` -- the correct reason for
`mach_absolute_time` usage in latency-arithmetic and frame-pacing contexts.

Apple ships no first-party validator. `Tools/scripts/validate-privacy-manifest.sh`
uses `plutil` + `grep` to gate the manifest on every PR. The script is variadic so
adding the daemon manifest in Phase 2/3 (when daemon code introduces required-reason
API usage) is a one-line CI change.

The daemon target does NOT ship `PrivacyInfo.xcprivacy` in Phase 1 (no required-reason
API usage in an empty `main()`).

### 7. Compile-time enforcement of CORTEX_SHM_NAME length via _Static_assert (D-08, cross-phase commitment)

The shared C header `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h`
defines:

```c
#define CORTEX_SHM_NAME "/cortex.samples"

_Static_assert(sizeof(CORTEX_SHM_NAME) <= 32,
               "CORTEX_SHM_NAME exceeds Darwin PSHMNAMLEN (31 bytes + null terminator)");
```

`_Static_assert` (C11 standard, supported by Clang on every Apple platform) fires at
C precompile time. The build fails before any Swift source is touched. Phase 2's
SC#4 ("a unit test fails the build if the constant is changed to a name that would
silently break on Darwin") is therefore *structurally impossible to violate* -- the
build itself fails before tests run.

This implements the project-wide cross-phase commitment: **compile-time guarantees beat
runtime ones.** Wherever an invariant *can* be enforced at the type system,
preprocessor, or build-graph level, it MUST be -- not via unit test, not via CI lint.

Future applications surfaced so far:

- Phase 4: parameter-count `_Static_assert` (or Swift `precondition` at module init)
  on the NDT1 architecture so a regression to h=4 fails the build, not the test.
- Phase 4: tensor-shape proofs at the type level so the BC1S `(B, C, 1, S)` layout
  cannot drift back to vanilla `(B, S, C)`.

### 8. CI on macos-15 with Xcode 26.3 selected via setup-xcode action (D-13, D-16, FOUND-05)

GitHub Actions workflow runs on `macos-15` (Apple Silicon arm64) runner.

**Critical pin (RESEARCH.md Critical Finding #3):** The runner image
20260421.0007.1 ships Xcode 26.0.1, 26.1.1, 26.2, and 26.3 pre-installed but the
**default `xcodebuild` invokes Xcode 16.4**. CI MUST select 26.x explicitly via
`maxim-lobanov/setup-xcode@v1` with `xcode-version: '26.3'`.

Pin to **26.3** specifically -- avoid 26.0.1 / 26.1 RC due to known test-suite hangs
on `macos-15-arm64` (actions/runner-images issue 13264).

CI gate (every PR):

1. `xcodebuild build` for `CortexiOS` (iOS Simulator) and `CortexMac` (macOS) schemes,
   `CODE_SIGNING_ALLOWED=NO`.
2. `swiftformat --lint .` (fails on formatter drift).
3. `swiftlint --strict` (fails on warnings).
4. `swift package resolve` from a clean clone (catches SwiftPM regressions).
5. `Tools/scripts/validate-privacy-manifest.sh` against both app targets'
   PrivacyInfo.xcprivacy.
6. `Tools/scripts/hotpath-policy.sh` -- pre-armed grep gate for
   `Packages/CortexCore/Sources/**` and `Packages/CortexIPC/Sources/**` (no-op in
   Phase 1; bites the moment Phase 2/3 code lands).
7. Cache: SwiftPM (`.build`, `~/Library/Caches/org.swift.swiftpm`) and DerivedData
   keyed on `Package.resolved` hash + Xcode major.minor version.

Cold-cache build target: ~3 min. Warm-cache build target: ~30 s. Job timeout: 30 min.

## Consequences

### Positive

- Repo is greenfield-buildable on any developer machine with Xcode 26.x.
- `xcodegen && open Cortex.xcworkspace` is the minimal incantation; no `.pbxproj`
  merge conflicts ever.
- `_Static_assert` makes the Darwin shm-name limit structurally unviolatable.
- CI catches privacy manifest drift, hot-path violations, and SwiftPM resolution
  breakage on every PR.
- Phase 8 has a clean upgrade path: add Apple Developer Program enrollment, swap
  Matchfile URL to private GitHub, uncomment Appfile team_id, add real fastlane lanes,
  enable sandbox on Mac targets.

### Negative

- iPad on-device builds with App Group enabled fail until Phase 8 enrollment lands.
  Local iPad work in Phase 1 is simulator-only.
- CI cannot validate App Group entitlement runtime behavior (CODE_SIGNING_ALLOWED=NO
  strips entitlements). Phase 1 SC#2 verification is a local manual runbook (Plan 07).
- The "signed" qualifier in Phase 1 SC#1 is interpreted as "build-only smoke" for CI
  purposes; literal interpretation requires a manual local Personal-Team-signed Mac
  build.
- Adopting `com.apple.security.app-sandbox` on Mac targets is deferred to Phase 8 --
  Phase 1 Mac binaries run unsandboxed.
- XcodeGen + `type: bundle` macOS daemon target consuming a SwiftPM library is a
  less-trodden path. Plan 02 Task 3 includes a verification smoke. If broken, the
  fallback is `type: tool` (executable daemon) -- loses the bundle wrapper but is fully
  proven for SPM consumption. If the fallback was used, this section gets updated
  during execution to record it.

### Cross-phase commitments propagated

- **Compile-time guarantees beat runtime ones.** Phase 4-5 will get parameter-count
  and tensor-shape `_Static_assert`/`precondition` traps at module init.
- **No `_ANEClient` private API.** Phase 5 will rely solely on
  `MLModelConfiguration.computeUnits`. Phase 1 has no decoder code, but the PR
  template's "No `_ANEClient` references" check pre-positions the ban.
- **No CocoaPods.** Phase 1 enforces this structurally -- any `Podfile` or `Pods/`
  directory anywhere in the repo fails the CI hot-path policy script's filesystem
  scan (Plan 06).

## Alternatives considered (rejected)

| Alternative | Why rejected |
|-------------|--------------|
| **Tuist** instead of XcodeGen | Tuist's caching delivers value at 10+ Xcode targets; Phase 1 has 3. Overhead exceeds benefit at this size. |
| **Hand-rolled `.xcodeproj`** | `.pbxproj` merge conflicts are a known nightmare even for solo projects. XcodeGen eliminates them entirely. |
| **Mac Catalyst single binary** | Phase 6 RENDER-08 explicitly requires `NSScreen.displayLink`, which Catalyst cannot surface cleanly. Two separate targets is the only viable path. |
| **CocoaPods** | In maintenance mode (2024). REQUIREMENTS.md FOUND-04 explicitly forbids it. |
| **Pure SwiftPM (no `.xcodeproj`)** | SwiftPM cannot express App Group entitlements, Info.plist customization, or non-app bundles cleanly. Disqualifying for a multi-target App Store project. |
| **`com.apple.security.temporary-exception.shared-memory` entitlement** | Deprecated for App Store. cortex-spec.md section 4.3 mandates App Group container instead. |
| **Apple Developer Program enrollment in Phase 1** | Adds $99 cost and ~24-48 hours review delay. No real notarization or TestFlight is needed until Phase 8. Defer per D-09. |
| **`fastlane match init` in Phase 1** | Requires a Team ID (no enrollment yet) and would prompt for Apple Developer Portal access. Phase 1 commits Matchfile/Appfile/Fastfile as text only per RESEARCH.md Q8. |
| **Default Xcode on macos-15** (Xcode 16.4) | Builds with macOS 16 SDK; incompatible with macOS 26 / iPadOS 26 deployment targets. CI must pin Xcode 26.3 via setup-xcode action. |
| **Xcode 26.0.1 / 26.1 RC on macos-15** | Known test-suite hangs on macos-15-arm64 (~75-80% failure rate from actions/runner-images issue 13264). Pin to 26.2 or 26.3. |
| **`com.apple.security.app-sandbox` on Phase 1 Mac targets** | Sandbox + unauthorized App Group blocks container access on Personal Team. Phase 1 keeps sandbox OFF; Phase 8 adds it with paid enrollment. |
| **Runtime checks on `CORTEX_SHM_NAME` length** (instead of `_Static_assert`) | Runtime checks ship as code; compile-time checks are physically impossible to violate at runtime. The cross-phase commitment "compile-time guarantees beat runtime ones" mandates the `_Static_assert` form. |

## References

- `docs/cortex-spec.md` section 6 (build/CI/distribution checklist), section 9 (macOS-specific gotchas
  including Darwin PSHMNAMLEN), section 10 (sprint timeline Phase 1 row), section 11 (rejected
  alternatives -- informs DIST-04's credibility-grade README in Phase 8)
- `.planning/REQUIREMENTS.md` FOUND-01 through FOUND-05 (Phase 1 acceptance bar)
- `.planning/phases/01-foundation-2026-toolchain/01-CONTEXT.md` D-01 through D-16
  (decisions implemented by this ADR)
- `.planning/phases/01-foundation-2026-toolchain/01-RESEARCH.md` Critical Findings
  1-4 (load-bearing constraints this ADR honors)
- Apple Developer Forums Thread 721701 (App Groups: macOS vs iOS)
- Apple Developer Forums Thread 719897 (shm_open + App Group + sandbox)
- GitHub `actions/runner-images` macos-15-arm64-Readme.md (image 20260421.0007.1)
- GitHub `actions/runner-images` issue 13264 (Xcode 26.0.1 / 26.1 RC test hangs)
- maxim-lobanov/setup-xcode@v1 action documentation
