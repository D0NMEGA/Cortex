# Phase 1: Foundation & 2026 Toolchain — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `01-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-04-28
**Phase:** 01-foundation-2026-toolchain
**Areas discussed:** Repo & target topology, Bundle ID & App Group naming, Signing & Developer enrollment, CI scope on day 1

---

## Repo & Target Topology

### Q1: How should the iPad and Mac targets be organized in Xcode?

| Option | Description | Selected |
|--------|-------------|----------|
| Two app targets, shared SPM core | iOS target + native AppKit Mac target, both consuming shared SwiftPM core. Avoids Catalyst overhead; preserves `NSScreen.displayLink` for RENDER-08. | ✓ |
| Single Universal (Catalyst) | One target marked iPad + Mac Catalyst. Simpler config but conflicts with RENDER-08's locked decision. | |
| Single iOS app + Mac via Designed-for-iPad | iOS-only target run on Mac via "Designed for iPad". No AppKit access; cuts off NSScreen.displayLink. | |

**User's choice:** Two app targets, shared SPM core
**Notes:** Aligns with RENDER-08 commitment to native `NSScreen.displayLink` on Mac.

### Q2: Where do CortexCore / CortexIPC / CortexRender live as code units in Phase 1's scaffold?

| Option | Description | Selected |
|--------|-------------|----------|
| SwiftPM packages from day 1 | Empty SPM packages under `Packages/`, wired into both app targets. Forces module boundaries from the start. | ✓ |
| In-app folders, extract later | All code as folders inside app targets; extract to SPM later. Faster scaffold, invites cross-module leakage. | |
| Hybrid: SwiftPM + Cargo workspace | Top-level Cargo.toml stub for Phase 3 Rust SPSC ring. Heavier but aligns with THREAD-04/06. | |

**User's choice:** SwiftPM packages from day 1

### Q3: Should the acquisition daemon's skeleton ship in Phase 1 or wait for Phase 2?

| Option | Description | Selected |
|--------|-------------|----------|
| Placeholder bundle in Phase 1 | Empty `CortexDaemon` target with App Group entitlement; cross-process shm_open exercised now. | ✓ |
| Single-process fixture only | shm_open survives in-process only; daemon target deferred to Phase 2. | |
| Full XPC service skeleton in Phase 1 | NSXPCConnection-based service. Likely overkill — spec uses kqueue+recvmsg + mach_msg, not XPC. | |

**User's choice:** Placeholder bundle in Phase 1

### Q4: Repo root layout — which directories should exist by end of Phase 1?

| Option | Description | Selected |
|--------|-------------|----------|
| Apps/, Packages/, Tools/, .github/ | Standard 2026 Apple monorepo shape. | ✓ |
| docs/ with cortex-spec.md moved in | Stable canonical-ref paths; ADR scaffold under docs/adr/. | ✓ |
| fastlane/ at repo root | Fastfile + Matchfile + Appfile stubs pre-positioning Phase 8. | ✓ |
| No code dirs yet — just config + CI | Minimum-viable scaffold, defer dirs to later phases. | |

**User's choice:** First three options selected (multi-select)

---

## Bundle ID & App Group Naming

### Q1: What's the canonical bundle ID prefix?

| Option | Description | Selected |
|--------|-------------|----------|
| com.cortexapp | Studio/brand prefix matching project name. | |
| com.donovansantine.cortex | Personal reverse-DNS using real name. | ✓ |
| com.santine.cortex | Shortened personal prefix. Saves shm-name bytes. | |

**User's choice:** com.donovansantine.cortex

### Q2: Bundle ID suffix scheme per target?

| Option | Description | Selected |
|--------|-------------|----------|
| Platform suffix: .ios / .mac / .daemon | Reads naturally; daemon clearly distinct. | ✓ |
| Role suffix: .app / .helper | Shorter; relies on Xcode platform-disambiguation. | |
| Flat: same ID, separate platforms via Xcode | Simplest; breaks if daemon ever ships standalone. | |

**User's choice:** Platform suffix: .ios / .mac / .daemon

### Q3: App Group identifier format?

| Option | Description | Selected |
|--------|-------------|----------|
| group.{prefix}.shared | Single shared container; most idiomatic. | ✓ |
| group.{prefix}.ipc | Names container by purpose. | |
| group.{prefix}.cortex | Maximally explicit but redundant. | |

**User's choice:** group.{prefix}.shared → resolves to `group.com.donovansantine.cortex.shared`

### Q4: shm region name template inside the App Group (Darwin PSHMNAMLEN ≤ 31 bytes)?

| Option | Description | Selected |
|--------|-------------|----------|
| /cortex.samples (15 chars) | Short; root namespace; 16 bytes headroom. | ✓ |
| /{group_id_short}.samples | Encodes group identity in shm path. | |
| /cx.samples (10 chars) | Maximally compressed; less self-documenting. | |

**User's choice:** /cortex.samples (15 chars)
**User's note:** "SC#4 fails the build on names >31 bytes, so wire that check as a compile-time `static_assert(strlen(SHM_NAME) < 31)` in the C header that defines the constant, not just a CI lint. Compile-time guarantees beat runtime ones."

This note was promoted to a cross-phase commitment in CONTEXT.md and informs Phase 4's NDT1 parameter-count assertion strategy as well.

---

## Signing & Developer Enrollment

### Q1: Where are you with Apple Developer Program enrollment?

| Option | Description | Selected |
|--------|-------------|----------|
| Already enrolled (active team) | Real signing + notarization from day 1. | |
| Enrolling now / in progress | Personal Team placeholder until approval. | |
| Not yet — Personal Team only | Defer paid enrollment to Phase 8. | ✓ |

**User's choice:** Not yet — Personal Team only

### Q2: fastlane match certificate repo location?

| Option | Description | Selected |
|--------|-------------|----------|
| Private GitHub repo | Standard convention; needs MATCH_PASSWORD + deploy key. | |
| Local-only Git repo (no remote yet) | Placeholder Matchfile; Phase 8 wires the real remote. | ✓ |
| S3 / iCloud Drive backend | Alternative backend for non-Git storage. | |

**User's choice:** Local-only Git repo (no remote yet)

### Q3: What signing target does Phase 1 actually need to satisfy SC#1?

| Option | Description | Selected |
|--------|-------------|----------|
| Signed with Personal Team in CI | Free auto-signing; no notarization. | ✓ |
| Signed with paid Developer ID + notarization smoke | Full pipeline end-to-end; requires enrollment. | |
| Signed in CI, notarization deferred to Phase 8 | Real signing without notarytool. | |

**User's choice:** Signed with Personal Team in CI
**Notes:** Personal Team doesn't operate cleanly headless on `macos-15`. Practical CI implementation will use `CODE_SIGNING_ALLOWED=NO` (or ad-hoc `-`) for the smoke build; Personal Team signing remains for local dev only.

### Q4: Where does the App Store Connect API key (.p8) live?

| Option | Description | Selected |
|--------|-------------|----------|
| GitHub Actions secret + local Keychain | Standard 2026 setup once enrolled. | |
| Local-only until Phase 8 | .p8 in local Keychain only; CI can't sign. | |
| Skip until enrolled | No ASC API key in Phase 1. | ✓ |

**User's choice:** Skip until enrolled

---

## CI Scope on Day 1

### Q1: What does Phase 1's CI gate actually run on every PR?

| Option | Description | Selected |
|--------|-------------|----------|
| Smoke + format + lint | xcodebuild + SwiftFormat --lint + SwiftLint. | ✓ |
| Smoke build only | Just xcodebuild on every PR. | |
| Aggressive: + privacy + static-analysis policies | Smoke + format + lint + privacy validator + hot-path grep. | |

**User's choice:** Smoke + format + lint

### Q2: Privacy manifest validation in Phase 1?

| Option | Description | Selected |
|--------|-------------|----------|
| CI parses PrivacyInfo.xcprivacy | Validator script asserts CA92.1 reason present. | ✓ |
| Manual until Phase 5 | Manifest exists but no automated validation. | |

**User's choice:** CI parses PrivacyInfo.xcprivacy

Note: The user picked "Smoke + format + lint" in Q1 *and* the privacy validator in Q2. Combined effective CI scope: smoke + format + lint + privacy validator. Captured as such in CONTEXT.md D-13/D-14.

### Q3: Static-analysis policies for the future hot path — wire in Phase 1 or Phase 3?

| Option | Description | Selected |
|--------|-------------|----------|
| Wire policy in Phase 1, scope-limited to Packages/CortexIPC + CortexCore | Trap pre-armed for Phase 2/3 code. | ✓ |
| Defer to Phase 3 | Policy lands when hot-path code arrives. | |

**User's choice:** Wire policy in Phase 1, scope-limited to Packages/CortexIPC + CortexCore

### Q4: CI cache strategy for DerivedData / SPM resolution?

| Option | Description | Selected |
|--------|-------------|----------|
| actions/cache for DerivedData + ~/Library/Caches/org.swift.swiftpm | Standard 2026 setup; ~30s warm vs ~3min cold. | ✓ |
| Fresh every run | No cache; simplest. | |
| DerivedData only (no SPM cache) | Cache builds, resolve packages fresh. | |

**User's choice:** actions/cache for DerivedData + ~/Library/Caches/org.swift.swiftpm

---

## Implementer's Discretion

The user did not explicitly defer any decisions to the implementer in this discussion. Items in CONTEXT.md's "Implementer's Discretion" subsection (SwiftFormat/SwiftLint rule sets, .gitignore template, README content shape, ADR template format) were marked as such because they're below the threshold of user-facing decisions for this phase, not because the user said "you decide."

## Deferred Ideas

Captured as a structured table in CONTEXT.md `<deferred>`. Summary:
- Apple Developer Program enrollment + everything that depends on it (real notarization, fastlane match GitHub repo, ASC `.p8` key, TestFlight wiring) → Phase 8
- LICENSE file → v0/v1 polish
- Real DIST-04 README (architectural commitments + rejected-alternatives table) → Phase 8
- Code-coverage threshold → Phase 8 or v0 (no logic to cover yet)

## Cross-Phase Commitment Surfaced

**Compile-time guarantees beat runtime ones.** Surfaced from the user's note on Q4 of "Bundle ID & App Group naming." Promoted to project-level principle in CONTEXT.md `<decisions>` Cross-Phase Commitments. Applies to:
- Phase 1: `_Static_assert` on `CORTEX_SHM_NAME` length (replaces Phase 2 SC#4's runtime test)
- Phase 4: NDT1 parameter-count proof at module init / type level (replaces a regression test)
- Phase 4: BC1S `(B, C, 1, S)` tensor-shape proof where Swift/coremltools allow

This is the most important takeaway from the discussion — the user is establishing an engineering bar, not just answering Phase 1 questions.
