# Cortex.app

Neuralink-quality iPad / Mac BCI input pipeline clone. Sub-25ms glass-to-glass neural
cursor decoder on Apple Silicon. NDT1 1.3M-param decoder runs in under 2ms on the M4
Neural Engine via CoreML, drives a 120Hz beam-raced Metal renderer, and integrates with
Apple's May 2025 BCI HID protocol.

> **Status:** Phase 1 / 10 (Foundation & 2026 Toolchain). See `.planning/STATE.md`
> for current position. Roadmap: `.planning/ROADMAP.md`.

## What's here

- `Apps/CortexiOS/` -- iPadOS 26 app target (Swift 6.2)
- `Apps/CortexMac/` -- native AppKit macOS 26 Tahoe app (no Mac Catalyst)
- `Apps/CortexDaemon/` -- background-helper bundle placeholder, App Group entitlement matched to apps
- `Packages/CortexCore/` -- shared Swift+C library (App Group helpers, time utilities, the load-bearing `cortex_shm.h` compile-time invariant)
- `Packages/CortexIPC/` -- empty stub, reserved for Phase 2 (kqueue + recvmsg + AES-GCM transport)
- `Packages/CortexRender/` -- empty stub, reserved for Phase 6 (CAMetalDisplayLink 120Hz renderer)
- `Packages/CortexDecoder/` -- empty stub, reserved for Phase 5 (CoreML deployment, ANE-resident NDT1)
- `Tools/scripts/` -- CI helpers (`validate-privacy-manifest.sh`, `hotpath-policy.sh`)
- `docs/cortex-spec.md` -- full technical specification (935-source research synthesis)
- `docs/adr/` -- architecture decision records

## Prerequisites

- macOS 26 Tahoe + Xcode 26.x (26.2 or later recommended; 26.3 is the CI pin per ADR-0001)
- Swift 6.2 toolchain (bundled with Xcode 26)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) + [SwiftLint](https://github.com/realm/SwiftLint): `brew install swiftformat swiftlint`
- (Optional) [xcbeautify](https://github.com/cpisciotta/xcbeautify) for prettier build output

## Build

```bash
xcodegen                                          # regenerate Cortex.xcodeproj from project.yml
open Cortex.xcworkspace                           # open in Xcode
# OR build from CLI:
xcodebuild build \
  -workspace Cortex.xcworkspace \
  -scheme CortexMac \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  -skipPackagePluginValidation \
  -skipMacroValidation
```

## Phase 1 limitations (intentional)

- **iPad on-device install will fail** if the iPad target's App Group entitlement is enforced.
  Personal Team cannot authorize App Group on iOS -- Phase 8 ($99 Apple Developer Program
  enrollment) activates this. iPad **simulator** builds work fine. See ADR-0001 section 2.
- **CI builds are unsigned.** `CODE_SIGNING_ALLOWED=NO` strips entitlements at build time,
  so CI cannot validate App Group runtime behavior. The "signed empty-shell" interpretation
  of Phase 1 SC#1 is satisfied by a manual local Mac build with Personal Team auto-signing.
  See ADR-0001 section 5.
- **fastlane is scaffolded but inactive.** `Gemfile`, `fastlane/Fastfile`, `fastlane/Matchfile`,
  `fastlane/Appfile` exist as Phase-1 placeholders. No real signing/notarize/TestFlight lanes
  are invoked in CI. See ADR-0001 section 5.

## Phase 1 SC#2 -- manual cross-process shm_open verification

Phase 1 success criterion #2 ("App Group container is provisioned and an entitlement-validated
empty `shm_open` test fixture in the container survives sandbox checks") is verified manually
on the developer Mac. Plan 07 documents the runbook; evidence file lands at
`.planning/phases/01-foundation-2026-toolchain/sc2-evidence.md`.

Quick summary:

1. Build `CortexMac` and `CortexDaemon` schemes locally with Personal Team auto-signing
   (Xcode > scheme > Signing & Capabilities).
2. Launch `CortexMac.app` (creates
   `~/Library/Group Containers/group.com.donovansantine.cortex.shared/` if absent).
3. Launch `CortexDaemon` as a separate process.
4. From CortexMac, call `shm_open("/cortex.samples", O_CREAT | O_RDWR, 0600)` -- verify
   success (fd >= 0).
5. From CortexDaemon, call `shm_open("/cortex.samples", O_RDWR, 0)` -- verify success
   and identical inode (`fstat`).
6. Capture screenshots and log output into
   `.planning/phases/01-foundation-2026-toolchain/sc2-evidence.md`.

## Spec

Full technical specification: [`docs/cortex-spec.md`](docs/cortex-spec.md).

Architectural decisions: [`docs/adr/`](docs/adr/).

## License

Not yet specified. Will be added at v0 / v1 milestone.
