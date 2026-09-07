---
phase: 08-apple-bci-hid-integration-distribution-v0-ship
plan: 01
subsystem: system-integration
tags: [bci-hid, iohiduserdevice, corehid, hidvirtualdevice, smappservice, entitlements, switch-control, accessibility, swiftpm, structural-gate]

# Dependency graph
requires:
  - phase: 01-foundation-2026-toolchain
    provides: "3 XcodeGen targets + Cortex.entitlements (App Group) + project.yml topology + render-policy.sh/hotpath-policy.sh CI-gate idiom + Time.machAbsoluteNanoseconds wrapper"
  - phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm
    provides: "CF#1 (keychain-access-groups deferred to P8, single-process Keychain fallback) + D-09 (SMAppService named as the App-Store daemon form)"
provides:
  - "CortexBCIHID SwiftPM package: the 5 ported Apple BCI HID report structs (Signal RID1, Button RID2, Pointer RID3, ItemSelection RID4-in, ScanInfo RID4-out) with pure encode/decode"
  - "BCIHIDDescriptor.bytes — the full Apple BCI HID report descriptor ported VERBATIM as a Swift [UInt8]"
  - "BCIHIDButtonAction — the 22 documented high-level BCI button actions"
  - "VirtualDeviceGate — the #if CORTEX_HID_LIVE-gated live IOHIDUserDevice/HIDVirtualDevice seam (inert by default, AMFI-safe)"
  - "DaemonRegistration — the SMAppService.daemon(plistName:) register/status scaffold behind a mockable DaemonService protocol"
  - "com.apple.developer.hid.virtual.device + keychain-access-groups declared-but-inert across all 3 target entitlement files + project.yml"
  - "Switch Control / Accessibility Info.plist surface (CortexBCIHIDProtocolVersion + NSAccessibilityUsageDescription) on Mac + iOS"
  - "Tools/scripts/hid-surface-policy.sh — structural CI gate over the HID surface + biting negative-control self-test"
affects: [08-02-round-trip-scan-info, 08-03-closed-loop-demo, 08-06-readme-honesty, 08-07-human-uat-device-session]

# Tech tracking
tech-stack:
  added: [CoreHID, IOKit.hid, ServiceManagement]
  patterns:
    - "Wire-and-gate: buildable-now pure-value-type port + #if CORTEX_HID_LIVE compile gate keeping the live HID symbol out of the free-team binary; activation = Plan 07 HUMAN-UAT"
    - "Declared-but-inert entitlements (HID + keychain-access-groups) with an explicit gate-disclosure XML comment, mirrored source<->project.yml"
    - "Structural grep gate + negative-control self-test (hid-surface-policy.sh) mirroring render-policy.sh"
    - "nonisolated public value types for pure-data packages under .defaultIsolation(MainActor.self)"

key-files:
  created:
    - "Packages/CortexBCIHID/Package.swift"
    - "Packages/CortexBCIHID/Sources/CortexBCIHID/BCIHIDReports.swift"
    - "Packages/CortexBCIHID/Sources/CortexBCIHID/BCIHIDDescriptor.swift"
    - "Packages/CortexBCIHID/Sources/CortexBCIHID/BCIHIDButtonAction.swift"
    - "Packages/CortexBCIHID/Sources/CortexBCIHID/VirtualDeviceGate.swift"
    - "Packages/CortexBCIHID/Sources/CortexBCIHID/DaemonRegistration.swift"
    - "Packages/CortexBCIHID/Tests/CortexBCIHIDTests/BCIHIDReportTests.swift"
    - "Packages/CortexBCIHID/Tests/CortexBCIHIDTests/BCIHIDDescriptorTests.swift"
    - "Packages/CortexBCIHID/Tests/CortexBCIHIDTests/DaemonRegistrationTests.swift"
    - "Tools/scripts/hid-surface-policy.sh"
  modified:
    - "Apps/CortexMac/Cortex.entitlements"
    - "Apps/CortexiOS/Cortex.entitlements"
    - "Apps/CortexDaemon/Cortex.entitlements"
    - "Apps/CortexMac/Info.plist"
    - "Apps/CortexiOS/Info.plist"
    - "project.yml"
    - ".github/workflows/ci.yml"

key-decisions:
  - "Ported descriptor is byte-EXACT to Apple's published BCIDescriptor[] (Context7 primary source), including the repeated Usage Page before Signal Quality and the separate item-selection-input / scan-info-output Logical collections — more faithful than the 08-PLAN/RESEARCH header approximation"
  - "Live IOHIDUserDevice C API is referenced verbatim inside #if CORTEX_HID_LIVE but is NOT in the public Swift IOKit overlay; activating the flag needs a Plan-07 C-interop bridging module (or CoreHID HIDVirtualDevice). The default build links none of it (RESEARCH §9 [verify], Plan 01-02 scaffold-now precedent)"
  - "Pure value types are `nonisolated public` (SwiftFormat modifierOrder) so they cross isolation boundaries; .defaultIsolation(MainActor.self) retained on the package per A9; the daemon types stay MainActor-isolated and their test suite adopts @MainActor (CortexReFIT precedent)"
  - "large_tuple scoped-disabled (with re-enable) only around the button/pointer reports — they port Apple's fixed-size C arrays UInt8[4]/SInt8[3] as fixed-arity tuples, a faithful port not an ad-hoc large tuple"

patterns-established:
  - "hid-surface-policy.sh: scoped forbidden check — the live symbol is legal ONLY in a #if CORTEX_HID_LIVE-guarded file; the self-test proves an ungated occurrence bites AND a gated one is allowed (the render-policy scoping-control idiom)"
  - "Entitlement gate-disclosure comment: every declared-but-inert key carries an inline `// declared but INERT ... activation = HUMAN-UAT gate` rationale"

requirements-completed: [SYS-01, SYS-02, SYS-05, SYS-06]

# Metrics
duration: 26min
completed: 2026-06-23
---

# Phase 8 Plan 01: Apple BCI HID Surface Port + Declared-and-Gated Entitlements + Structural CI Gate Summary

**The public Apple BCI HID protocol (5 report structs + verbatim report descriptor + 22 button actions) ported into a new CortexBCIHID SwiftPM package, with the `com.apple.developer.hid.virtual.device` + `keychain-access-groups` entitlements declared-but-inert across 3 targets, the live IOHIDUserDevice/HIDVirtualDevice seam behind a `#if CORTEX_HID_LIVE` gate (AMFI-safe), an SMAppService daemon-registration scaffold, and a biting `hid-surface-policy.sh` structural CI gate.**

## Performance

- **Duration:** 26 min
- **Started:** 2026-06-23T05:54:07Z
- **Completed:** 2026-06-23T06:20:27Z
- **Tasks:** 3
- **Files modified:** 17 (10 created, 7 modified)

## Accomplishments
- Ported Apple's public BCI HID surface into `CortexBCIHID`: the 5 report structs with exact byte layouts (3/5/4/2/7) + pure `encode`/`decode`, the report descriptor byte array ported **verbatim** from Apple's primary source, and the 22-case button-action enum — 15 Swift Testing assertions green.
- Declared (and gated) `com.apple.developer.hid.virtual.device` + `keychain-access-groups` across all 3 target entitlement files AND the 3 project.yml `entitlements.properties` blocks; mirrored the Switch Control / Accessibility Info.plist surface (`CortexBCIHIDProtocolVersion`, `NSAccessibilityUsageDescription`) on Mac + iOS.
- Built the `#if CORTEX_HID_LIVE`-gated `VirtualDeviceGate` (verified: the live `IOHIDUserDeviceHandleReportWithTimeStamp` symbol is NOT in the default-built objects) and the `SMAppService.daemon(...)` register/status scaffold behind a mockable `DaemonService` protocol (4 daemon/gate tests green).
- Built `hid-surface-policy.sh` (shellcheck-clean) — a structural grep gate over the descriptor/struct/entitlement/gate commitments with a negative-control self-test that proves every required-token strip bites, the ungated-symbol injection bites, and a gated symbol is allowed — and wired the CortexBCIHID build-smoke + test step + the gate (+ `--self-test`) into CI.

## Task Commits

Each task was committed atomically:

1. **Task 1: Port BCI HID report structs + descriptor + button enum** - `9c396f4` (feat) — TDD: tests + impl landed together for the value-type port
2. **Task 2: Declare-and-gate entitlements + Info.plist mirror + VirtualDeviceGate + DaemonRegistration** - `647f14e` (feat)
3. **Task 3: hid-surface-policy.sh structural gate + CI wiring** - `e19b1c1` (chore)

_(Plan metadata commit — SUMMARY only — owned by the orchestrator per this plan's sequential-executor contract; STATE.md/ROADMAP.md not modified here.)_

## Files Created/Modified
- `Packages/CortexBCIHID/Package.swift` - SwiftPM manifest (swift-tools 6.2, .macOS(.v26)/.iOS(.v26), `.defaultIsolation(MainActor.self)`, no external deps)
- `Packages/CortexBCIHID/Sources/CortexBCIHID/BCIHIDReports.swift` - 5 ported `nonisolated public` Sendable/Equatable report structs + pure encode/decode + `BCIReportID` direction disambiguation
- `Packages/CortexBCIHID/Sources/CortexBCIHID/BCIHIDDescriptor.swift` - the full Apple BCI HID report descriptor `[UInt8]` (verbatim) + Usage-Page/Usage constants
- `Packages/CortexBCIHID/Sources/CortexBCIHID/BCIHIDButtonAction.swift` - the 22 documented high-level BCI button actions
- `Packages/CortexBCIHID/Sources/CortexBCIHID/VirtualDeviceGate.swift` - the `#if CORTEX_HID_LIVE` live IOHIDUserDevice/HIDVirtualDevice seam (inert stubs throw `.notEnabled` by default)
- `Packages/CortexBCIHID/Sources/CortexBCIHID/DaemonRegistration.swift` - `DaemonService` protocol + `DaemonRegistrationStatus` enum + `MockDaemonService` + `#if os(macOS)` `SMAppServiceDaemon` conformer
- `Packages/CortexBCIHID/Tests/CortexBCIHIDTests/{BCIHIDReportTests,BCIHIDDescriptorTests,DaemonRegistrationTests}.swift` - 19 tests across 3 suites
- `Apps/Cortex{Mac,iOS,Daemon}/Cortex.entitlements` - HID + keychain-access-groups declared-but-inert (with gate-disclosure comment)
- `Apps/Cortex{Mac,iOS}/Info.plist` - Switch Control / Accessibility mirror keys (additive)
- `project.yml` - registered CortexBCIHID under `packages:`; mirrored HID + keychain keys into the 3 entitlements.properties blocks
- `Tools/scripts/hid-surface-policy.sh` - structural HID-surface gate + `--self-test`
- `.github/workflows/ci.yml` - CortexBCIHID in build-smoke loop + test step + HID gate step (run + `--self-test`)

## Decisions Made
- **Descriptor ported byte-EXACT to Apple's primary source** (via Context7): includes the repeated `0x05,0x60` Usage Page before Signal Quality and the two separate RID-4 Logical collections (item-selection input `0x81,0x06` + scan-info output `0x91,0x03`). This is more faithful than the 08-PLAN/RESEARCH header literal, which collapsed the repeated Usage Page.
- **Live HID path is documented-but-deferred at the C-interop layer**: the `IOHIDUserDevice` C API is referenced verbatim inside `#if CORTEX_HID_LIVE`, but those symbols are not surfaced by the public Swift IOKit overlay; activating the flag requires the Plan-07 bridging module (or CoreHID `HIDVirtualDevice`). The default build links none of it (RESEARCH §9 [verify]; Plan 01-02 scaffold-now precedent). The gate's forbidden token is still present-and-scoped.
- **Isolation:** pure value types are `nonisolated public` (cross-isolation usable, SwiftFormat-ordered); the daemon types remain MainActor-isolated and `DaemonRegistrationTests` adopts `@MainActor` (the CortexReFIT KalmanConstantsTests precedent).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug/Fidelity] Descriptor ported byte-exact to Apple, header literal corrected**
- **Found during:** Task 1 (descriptor test) + Task 2 (descriptor completion)
- **Issue:** The 08-PLAN/RESEARCH "documented header" `[0x05,0x60,0x09,0x01,0xA1,0x01,0x09,0x02,0x85,0x01]` collapsed Apple's REPEATED Usage Page (the real canonical header is `...0xA1,0x01,0x05,0x60,0x09,0x02,0x85,0x01`). Reproducing the plan literal would have shipped a non-faithful descriptor.
- **Fix:** Pulled the authoritative `BCIDescriptor[]` via Context7 (Apple Accessibility docs) and ported it verbatim — repeated Usage Page + separate item-selection-input / scan-info-output Logical collections. Updated the descriptor test to assert the verified canonical header.
- **Files modified:** BCIHIDDescriptor.swift, BCIHIDDescriptorTests.swift
- **Verification:** `swift test` descriptor suite green; `hid-surface-policy.sh` asserts the `0x05,0x60` Usage-Page pair (present, twice).
- **Committed in:** 9c396f4 (Task 1) + 647f14e (Task 2 verbatim completion)

**2. [Rule 3 - Blocking] MainActor isolation vs nonisolated value types**
- **Found during:** Task 1 (first test build) + Task 2 (DaemonRegistrationTests build)
- **Issue:** `.defaultIsolation(MainActor.self)` (plan-mandated, matching other packages) made the pure-data `static let`/structs MainActor-isolated, so the nonisolated test context could not reference them ("main actor-isolated ... cannot be referenced from a nonisolated context"; "isolated conformance" errors).
- **Fix:** Marked the pure value types `nonisolated public` (report/descriptor/button); kept the daemon-registration types MainActor-isolated (they are service-management-adjacent) and gave `DaemonRegistrationTests` `@MainActor` — the CortexReFIT KalmanConstantsTests precedent.
- **Files modified:** BCIHIDReports.swift, BCIHIDDescriptor.swift, BCIHIDButtonAction.swift, DaemonRegistrationTests.swift
- **Verification:** `swift build` (default) + 19 tests green.
- **Committed in:** 9c396f4 (Task 1), 647f14e (Task 2)

**3. [Rule 3 - Blocking] Live-path imports + IOKit symbol availability**
- **Found during:** Task 2 (gated-build probe `swift build -DCORTEX_HID_LIVE`)
- **Issue:** (a) `import` inside an enum body is invalid at any condition (a syntax-placement error caught even when `#if` is false), breaking the DEFAULT build; (b) `IOHIDUserDevice`/`IOHIDUserDeviceCreate`/`IOHIDUserDeviceHandleReportWithTimeStamp` are NOT in the public Swift IOKit overlay (no `IOHIDUserDevice.h` in the SDK module map), so the gated build cannot resolve them without a C-interop bridge.
- **Fix:** Hoisted the live imports (`Darwin`/`Foundation`/`IOKit`) to file scope under their own `#if CORTEX_HID_LIVE` (fixing the default build); documented that the live path's IOKit symbols require the Plan-07 C-interop bridging module (or CoreHID `HIDVirtualDevice`) — verified `import CoreHID` + `HIDVirtualDevice` parse on macOS 26 as the modern fallback. The default build is OFF and links no live symbol (confirmed via `nm` on the built objects).
- **Files modified:** VirtualDeviceGate.swift
- **Verification:** default `swift build` clean; `nm` on the built `.o` shows no live symbol; `hid-surface-policy.sh` confirms the symbol is gated.
- **Committed in:** 647f14e (Task 2)

**4. [Rule 1 - Tooling conflict] SwiftLint large_tuple on the ported fixed-size arrays**
- **Found during:** Task 1 (SwiftLint --strict)
- **Issue:** SwiftLint --strict bans 3+ element tuples (`large_tuple`); the plan-mandated `buttons: (UInt8,UInt8,UInt8,UInt8)` / `position: (Int8,Int8,Int8)` (ports of Apple's `UInt8 buttons[4]` / `SInt8 position[3]`) tripped it. A blanket file-level disable then tripped `blanket_disable_command`.
- **Fix:** Scoped `// swiftlint:disable large_tuple` / `enable` bracketing ONLY the two tuple-using structs, with a rationale comment (faithful fixed-arity port, not an ad-hoc large tuple).
- **Files modified:** BCIHIDReports.swift
- **Verification:** SwiftLint --strict 0 violations on all 5 files.
- **Committed in:** 9c396f4 (Task 1)

**5. [Rule 3 - Tooling conflict] Test-naming form (acceptance grep vs SwiftFormat/SwiftLint)**
- **Found during:** Task 1 (SwiftFormat + SwiftLint on tests)
- **Issue:** SwiftFormat 0.61.1's `swiftTestingTestCaseNames` rewrites `@Test("desc") func camelCase()` into a backtick-named function, which SwiftLint --strict then rejects (`identifier_name`). The Task-1 acceptance grep `public struct BCIInput` also conflicts with SwiftFormat's `modifierOrder` (`public nonisolated struct`).
- **Fix:** Kept tests in the CI-passing CortexReFIT convention (`@Test("desc")` + camelCase func, variables >=3 chars); the acceptance grep was satisfied at the struct-NAME level (which is what the Task-3 gate — the real CI enforcement — asserts). Did NOT modify repo-wide `.swiftformat`/`.swiftlint.yml` (the existing CortexReFIT tests prove CI accepts this form).
- **Files modified:** BCIHIDReportTests.swift, BCIHIDDescriptorTests.swift
- **Verification:** `swift test` 19/19 green; SwiftLint --strict 0 violations on the 5 files; SwiftFormat `--lint` 0/3 on sources.
- **Committed in:** 9c396f4 (Task 1)

---

**Total deviations:** 5 auto-fixed (2 Rule-1 fidelity/tooling, 3 Rule-3 blocking). **Impact on plan:** All necessary for correctness, faithful porting, or CI-gate compliance. The descriptor fidelity fix makes the artifact MORE honest (verbatim Apple bytes). The acceptance-grep literal `public struct BCIInput` was superseded by `public nonisolated struct BCIInput` (struct names verified present; the Task-3 gate keys on names). No scope creep.

## Issues Encountered
- The Task-1 acceptance criterion grep `grep -c "public struct BCIInput..."` returns 0 because the modifier order is `public nonisolated struct` (SwiftFormat + Swift-6.2 isolation). The 5 structs are verified present by name (gate-asserted) and all behavior tests pass — the literal was a research-time expectation, not a functional requirement.

## User Setup Required
None - no external service configuration required. The live HID activation (entitlement grant + provisioned device + Accessibility permission) and the iPad-M4 on-device Switch Control registration are the Plan 07 HUMAN-UAT gate, not setup.

## Next Phase Readiness
- **Plan 02 (round-trip):** `BCIOutputScanInfoReport` (host->device scan-feedback channel) + `BCIInputItemSelection`/`BCIInputPointerReport` are ported and round-trip-tested — the closed-loop seam is ready.
- **Plan 03 (closed-loop demo):** CortexBCIHID is registered in project.yml; Plan 03 adds it as a CortexMac target dependency.
- **Plan 06 (README honesty):** the declared-but-gated entitlement posture + the software-vs-live disclosure are in place to document.
- **Plan 07 (HUMAN-UAT device session):** the `#if CORTEX_HID_LIVE` seam + the SMAppService scaffold are the activation point; the live path will need a C-interop bridging module for the IOKit `IOHIDUserDevice` symbols (or migrate to CoreHID `HIDVirtualDevice`).

## Known Stubs
- `VirtualDeviceGate` live path (`#if CORTEX_HID_LIVE`): inert by default (the design — D-04/D-06). The default-build stubs throw `.notEnabled`; the live IOKit symbols require the Plan-07 C-interop bridge. This is an INTENTIONAL gate, not an unresolved stub — `hid-surface-policy.sh` enforces it stays gated, and the live activation is the Plan 07 HUMAN-UAT checkpoint.
- `SMAppServiceDaemon.register()` performs a real `SMAppService.register()` but a successful live install needs a signed helper + bundled LaunchDaemons plist (paid signing, D-03) — gated to Plan 07. The mockable status path is unit-tested now.

## Self-Check: PASSED

- All 10 created files verified present on disk (6 sources + 3 test files + Package.swift + hid-surface-policy.sh) + the SUMMARY.
- All 3 task commits verified in git log: `9c396f4`, `647f14e`, `e19b1c1`.
- Full plan verification green: 19 tests (3 suites), `hid-surface-policy.sh` + `--self-test` both exit 0, `plutil -lint` 5/5 OK, default `swift build` clean (no live HID symbol in objects), all grep-present invariants hold.

---
*Phase: 08-apple-bci-hid-integration-distribution-v0-ship*
*Completed: 2026-06-23*
