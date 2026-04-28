# Phase 1: Foundation & 2026 Toolchain — Context

**Gathered:** 2026-04-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Stand up the Xcode 26 + Swift 6.2 repo skeleton for Cortex.app — two app targets (iPad and native AppKit Mac) consuming a shared SwiftPM core, an empty `CortexDaemon` placeholder bundle, App Group container, `PrivacyInfo.xcprivacy`, fastlane scaffolding, and `macos-15` GitHub Actions CI green on every PR.

By end of Phase 1, every commit builds cleanly under the 2026 Apple toolchain and Phase 2 can drop POSIX shm into the App Group container without re-doing entitlements.

**Not in this phase:** kqueue+recvmsg IPC code (Phase 2), AES-GCM crypto (Phase 2), Rust SPSC ring (Phase 3), any decoder or renderer code (Phases 4–6), real notarization or TestFlight (Phase 8).

</domain>

<decisions>
## Implementation Decisions

### Repo & Target Topology

- **D-01:** Two app targets in Xcode — `CortexiOS` (iPadOS 26) and `CortexMac` (native AppKit on macOS 26 Tahoe). **No Mac Catalyst** — Phase 6 RENDER-08 already requires `NSScreen.displayLink` on the Mac side, which Catalyst does not surface cleanly.
- **D-02:** Shared code lives in SwiftPM library packages from day 1 under `Packages/`:
  - `CortexCore` — shared types, time utilities, App Group helpers
  - `CortexIPC` — (empty in Phase 1) reserved for Phase 2 transport code
  - `CortexRender` — (empty) reserved for Phase 6 Metal renderer
  - `CortexDecoder` — (empty) reserved for Phase 5 CoreML deployment
  Both app targets and the daemon depend on `CortexCore`; later phases wire in `CortexIPC` etc. as those modules acquire content.
- **D-03:** A `CortexDaemon` placeholder target ships in Phase 1 (background-helper bundle, App Group entitlement matched to the apps). Empty `main()` is fine — the only Phase-1 functional requirement is that a cross-process `shm_open` from the daemon onto a region inside the App Group container survives sandbox checks (satisfies Phase 1 SC#2 in spirit and pre-positions Phase 2).
- **D-04:** Repo root layout by end of Phase 1:
  - `Apps/` — `CortexiOS/`, `CortexMac/`, `CortexDaemon/` Xcode target wrappers
  - `Packages/` — SwiftPM library packages (CortexCore + four empty siblings)
  - `Tools/` — CI scripts (`validate-privacy-manifest.sh`, hot-path policy grep, etc.)
  - `.github/workflows/` — `ci.yml` running on `macos-15`
  - `docs/` — `cortex-spec.md` moved in from repo root; `docs/adr/` scaffold seeded with `0001-foundation-and-2026-toolchain.md`
  - `fastlane/` — `Fastfile`, `Matchfile`, `Appfile` stubs (real signing deferred — see D-09)
  - `Cortex.xcworkspace` — wires the three Xcode targets and the SPM packages

### Bundle ID & App Group Naming

- **D-05:** Canonical bundle ID prefix: **`com.donovansantine.cortex`**.
- **D-06:** Per-target suffixes — `com.donovansantine.cortex.ios`, `com.donovansantine.cortex.mac`, `com.donovansantine.cortex.daemon`.
- **D-07:** App Group identifier: **`group.com.donovansantine.cortex.shared`**. Single shared container hosts the future shm region plus any shared `UserDefaults`. Both apps + daemon claim this group in their entitlements files.
- **D-08:** Canonical shm region name: **`/cortex.samples`** (15 bytes including leading `/`, well under Darwin `PSHMNAMLEN`'s 31-byte cap). Define once in a shared C header inside `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h`:
  ```c
  #define CORTEX_SHM_NAME "/cortex.samples"
  _Static_assert(sizeof(CORTEX_SHM_NAME) <= 32,
                 "CORTEX_SHM_NAME exceeds Darwin PSHMNAMLEN (31 bytes + null terminator)");
  ```
  **Compile-time enforcement, not a runtime CI lint.** Both Swift and C consumers import this header so the constant cannot drift. This is the load-bearing implementation note for this entire phase — Phase 2 SC#4 ("a unit test fails the build if the constant is changed") becomes structurally impossible to violate because the build itself fails before tests run.

### Signing & Apple Developer Enrollment

- **D-09:** Apple Developer Program enrollment is **deferred** (not yet active). Phase 1 ships with Personal Team auto-signing for local dev only. The $99 enrollment is paid when Phase 8 needs real notarization and TestFlight.
- **D-10:** fastlane scaffolding lands in Phase 1 as a placeholder — `Fastfile`, `Matchfile`, `Appfile` exist but `Matchfile` points to a TBD remote (local Git repo only, no GitHub remote yet). Phase 8 swaps in the real private GitHub repo + `MATCH_PASSWORD`.
- **D-11:** CI does **not** sign with a real Developer ID in Phase 1. The smoke build uses `CODE_SIGNING_ALLOWED=NO` (or ad-hoc `-`) because Personal Team profiles are tied to a logged-in Apple ID and don't operate cleanly headless on `macos-15` runners. SC#1's "signed empty-shell app" is satisfied locally on the dev machine; CI gates the build/lint/test path. **Researcher and planner: confirm the exact `xcodebuild` flags for unsigned-but-correct builds on macos-15 + Xcode 26.**
- **D-12:** App Store Connect API key (`.p8` JWT) is **not** provisioned in Phase 1. Skip until Phase 8.

### CI Scope on Day 1

- **D-13:** PR-blocking CI gate on every push runs:
  1. `xcodebuild build` for `CortexiOS` and `CortexMac` schemes (`CODE_SIGNING_ALLOWED=NO`)
  2. `swiftformat --lint .` (fails on formatter drift)
  3. `swiftlint --strict` (fails on warnings)
  4. SwiftPM resolution sanity check (`swift package resolve` from a clean clone)
- **D-14:** A `Tools/scripts/validate-privacy-manifest.sh` script parses `PrivacyInfo.xcprivacy` and asserts both that it's valid plist AND that `CA92.1` is declared as a reason for `mach_absolute_time`. Runs in CI on every PR. Catches FOUND-03 drift the moment a new required-reason API gets added without its manifest entry.
- **D-15:** A `Tools/scripts/hotpath-policy.sh` script greps `Packages/CortexIPC/Sources/**` and `Packages/CortexCore/Sources/**` for forbidden tokens — `dispatch_async`, `lazy var`, `pthread_mutex`, and `import Foundation` / `import ObjectiveC`. The scope-limited dirs are empty in Phase 1, so the gate is a no-op now. The moment Phase 2/3 code lands in those dirs, the gate bites. Pre-positions Phase 3 SC#2.
- **D-16:** GitHub Actions caches both DerivedData and `~/Library/Caches/org.swift.swiftpm`, keyed on `Package.resolved` hash + Xcode major version. Cold-build target: ~30 s on a warm cache (vs. ~3 min cold).

### Implementer's Discretion

The following implementation details aren't load-bearing for downstream phases — researcher/planner should pick reasonable defaults without re-asking:

- Exact SwiftFormat / SwiftLint rule sets (defer to community-standard configs unless the user has a preferred starting rule set)
- `.gitignore` contents (standard Apple/SwiftPM template)
- README content shape beyond "documents the architectural commitments and rejected-alternatives table" (DIST-04)
- ADR template format (lightweight Markdown is fine; lock the format only when the second ADR lands)
- LICENSE file (not specified — proceed without one in Phase 1; revisit at v0/v1)
- Branch protection rules in GitHub (set them to "require CI green" but otherwise default)

### Cross-Phase Commitments

These are project-level principles the user surfaced during this discussion. Apply them throughout the codebase:

- **Compile-time guarantees beat runtime ones.** Wherever an invariant *can* be enforced at the type system, preprocessor, or build-graph level, it MUST be — not via unit test, not via CI lint. Specific applications surfaced so far:
  - Phase 1: `_Static_assert` on `CORTEX_SHM_NAME` length
  - Phase 4 (preview): a parameter-count `_Static_assert` (or Swift `precondition` at module-init) on the NDT1 architecture so a regression to h=4 fails the build, not the regression test
  - Phase 4 (preview): tensor-shape proofs at the type level (where Swift / coremltools allow) so the BC1S `(B, C, 1, S)` layout cannot drift back to vanilla `(B, S, C)`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-Level Spec
- `cortex-spec.md` §6 — Build / CI / distribution checklist (notarytool, PrivacyInfo, fastlane, SwiftPM)
- `cortex-spec.md` §9 — macOS-specific gotchas, including the Darwin `PSHMNAMLEN` 31-byte limit driving D-08
- `cortex-spec.md` §10 — Sprint timeline, Phase 1 row
- `cortex-spec.md` §11 — Explicitly-rejected alternatives (informs README content per DIST-04)

> Note: `cortex-spec.md` is at repo root in Phase 1 *before* the `docs/` move (D-04). Once the move lands, all refs become `docs/cortex-spec.md`.

### Planning Artifacts
- `.planning/PROJECT.md` — Vision, 14-row Key Decisions table, Constraints
- `.planning/REQUIREMENTS.md` — FOUND-01 through FOUND-05 are this phase's acceptance bar
- `.planning/ROADMAP.md` — Phase 1 success criteria (4 numbered items) are the goal-backward verification target

### External Apple Documentation (planner: pull current versions via Context7 / WebFetch when wiring tasks)
- Apple "Describing use of required reason API" (PrivacyInfo.xcprivacy + CA92.1 reason code)
- Apple "App Group entitlement" + "Configuring App Groups" guides
- Apple "notarytool" + "stapler" reference (Phase 8, but DIST-01 origin)
- fastlane match docs (`fastlane.tools/actions/match`)
- GitHub Actions `actions/cache` reference (for D-16 cache key construction)
- Swift Package Manager manifest format for Swift 6.2

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
**None — greenfield repo.** The only files in the repository are `AGENTS.md` (project instructions) and `cortex-spec.md` (research synthesis). Phase 1 creates every Apple/SPM artifact from scratch.

### Established Patterns
None to honor. Phase 1 *establishes* the patterns that every later phase consumes: module boundaries, naming convention, CI gate shape, repo directory layout, ADR format.

### Integration Points
None yet. The integration points Phase 1 *creates* for downstream consumption:
- `CortexCore` package — Swift API surface for App Group access, time utilities (foundation for `mach_absolute_time` wrappers)
- Shared C header `cortex_shm.h` — defines `CORTEX_SHM_NAME` and the compile-time length proof; consumed by Phase 2's IPC primitive
- App Group entitlement `group.com.donovansantine.cortex.shared` — claimed by all three targets; Phase 2's POSIX shm + future Keychain access flow through it
- `PrivacyInfo.xcprivacy` — Phase 5 (CoreML) and Phase 9/10 (photodiode rig timing) will add more required-reason API entries; the validator script gates this growth

</code_context>

<specifics>
## Specific Ideas

- **The `_Static_assert` directive on `CORTEX_SHM_NAME` is not optional.** The user explicitly called this out as the right level of enforcement: "Compile-time guarantees beat runtime ones." Treat this as a load-bearing requirement, not advice. The shared C header carrying that assert is the canonical shape for any future invariant that crosses the Swift/C boundary.

- **The native AppKit Mac target (no Catalyst)** ties directly into Phase 6's RENDER-08 commitment to `NSScreen.displayLink`. Phase 1 cannot accidentally generate a Catalyst project from a "Multiplatform App" template — verify the template choice.

- **Empty SPM packages are intentional.** `CortexIPC`, `CortexRender`, `CortexDecoder` ship with a single empty `.swift` file in Phase 1 (so `swift build` succeeds) and a `README.md` describing what will land there. Forces module discipline from the first commit.

- **Hot-path policy script is a "trap pre-armed."** The script and its CI wiring exist now; the directories it polices are empty. The moment Phase 2/3 begin populating those dirs, the gate is automatically active — no Phase-3 wiring needed.

</specifics>

<deferred>
## Deferred Ideas

| Idea | Belongs in | Why deferred |
|------|------------|--------------|
| Apple Developer Program enrollment ($99/yr) | Phase 8 | No real notarization or TestFlight needed until v0 ships |
| fastlane match private GitHub repo + `MATCH_PASSWORD` | Phase 8 | Match doesn't operate without an Apple Developer team to manage certs for |
| App Store Connect API key (`.p8` JWT) | Phase 8 | Required only for `notarytool submit` and TestFlight upload |
| Real notarization smoke (`notarytool submit` in CI) | Phase 8 | Requires enrollment + ASC API key |
| TestFlight 100/10 000 tester wiring | Phase 8 | DIST-03 explicitly placed there |
| LICENSE file at repo root | v0 / v1 polish | Not specified in REQUIREMENTS.md; pick when publishing |
| README architectural commitments + rejected-alternatives table (DIST-04) | Phase 8 | Phase 1 README documents *what's scaffolded*; the credibility-grade README is a v0 distribution artifact |
| Static-analysis policies for additional dirs (e.g., `Packages/CortexDecoder`) | Phase 4 | Decoder doesn't run on the audio-callback hot path; different rules apply |
| Code-coverage threshold enforcement | Phase 8 or v0 | Phase 1 has no logic to cover; nothing meaningful to gate yet |
| Branch protection beyond "require CI green" | v0 | Solo project, can stay light-touch |

</deferred>

---

*Phase: 01-foundation-2026-toolchain*
*Context gathered: 2026-04-28*
