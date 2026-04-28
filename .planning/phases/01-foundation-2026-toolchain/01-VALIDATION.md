---
phase: 1
slug: foundation-2026-toolchain
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-28
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Bootstrapped from `01-RESEARCH.md` § Validation Architecture; populated by gsd-planner during planning and refined as plans land.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (Swift 6.2 default) + XCTest fallback for Xcode-driven scheme tests |
| **Config file** | None — Swift Testing is in-language; XCTest test plan lives inside `Cortex.xcworkspace` schemes |
| **Quick run command** | `swift test --package-path Packages/CortexCore` |
| **Full suite command** | `xcodebuild test -workspace Cortex.xcworkspace -scheme CortexMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` |
| **Estimated runtime** | ~10–30s quick, ~3–5 min full |

> **Note for planner:** Phase 1 ships near-zero runtime logic. Most "tests" are static checks (entitlements declared, manifest plist valid, no Pods, no Catalyst regressions, `_Static_assert` fires when broken). Don't pad with synthetic unit tests in Phase 1.

---

## Sampling Rate

- **After every task commit:** `swift test --package-path Packages/CortexCore` (≤30s) — fast feedback for SwiftPM changes
- **After every plan wave:** Full `ci.yml` workflow (≤10 min on warm cache)
- **Before `/gsd-verify-work`:** Full ci.yml green AND manual SC#2 cross-process `shm_open` runbook completed with evidence file in repo
- **Max feedback latency:** 30s (quick) / 600s (full)

---

## Per-Task Verification Map

> Populated by gsd-planner during planning. Below is the research-derived skeleton — planner expands per-task IDs once plans are written.

| Req ID | Plan | Wave | Behavior | Threat Ref | Test Type | Automated Command | File Exists | Status |
|--------|------|------|----------|------------|-----------|-------------------|-------------|--------|
| FOUND-01 | TBD | TBD | Project builds with Xcode 26 + Swift 6.2 on macOS 26 / iPadOS 26 targets | — | smoke (build) | `xcodebuild build -workspace Cortex.xcworkspace -scheme CortexMac -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO` | ❌ W0: ci.yml + project.yml | ⬜ pending |
| FOUND-01 | TBD | TBD | `_Static_assert` on `CORTEX_SHM_NAME` length fires if name exceeds 31 bytes | — | unit (compile-time) | `swift build --package-path Packages/CortexCore` (would FAIL TO COMPILE if asserted constraint broken — verify by intentionally breaking it once) | ❌ W0: cortex_shm.h | ⬜ pending |
| FOUND-01 | TBD | TBD | Swift target can `@_exported import CortexCoreC` and read `CORTEX_SHM_NAME` | — | unit (Swift Testing) | `swift test --package-path Packages/CortexCore --filter CortexCoreTests/ShmConstantsTests` | ❌ W0: ShmConstantsTests.swift | ⬜ pending |
| FOUND-02 | TBD | TBD | App Group entitlement is declared on all three targets (CortexiOS, CortexMac, CortexDaemon) | — | static (entitlements file diff) | `grep -l 'group.com.donovansantine.cortex.shared' Apps/*/Cortex.entitlements \| wc -l` returns 3 | ❌ W0: 3× .entitlements files | ⬜ pending |
| FOUND-02 | TBD | TBD | Cross-process `shm_open("/cortex.samples", ...)` works between CortexMac and CortexDaemon, both inside App Group container | — | manual (runbook) | local Mac: launch CortexMac, launch CortexDaemon as separate process, verify both can open shm region; document evidence in `.planning/phases/01-foundation-2026-toolchain/sc2-evidence.md` | ❌ W0: README runbook + manual evidence file | ⬜ pending |
| FOUND-03 | TBD | TBD | `PrivacyInfo.xcprivacy` exists for both app targets and is a valid plist | — | static (plutil + grep) | `./Tools/scripts/validate-privacy-manifest.sh Apps/CortexMac/PrivacyInfo.xcprivacy Apps/CortexiOS/PrivacyInfo.xcprivacy` | ❌ W0: 2× .xcprivacy + script | ⬜ pending |
| FOUND-03 | TBD | TBD | `CA92.1` declared as reason for `mach_absolute_time` in both manifests | — | static (validator script) | same as above | ❌ W0: validator script + manifests | ⬜ pending |
| FOUND-03 | TBD | TBD | `PrivacyInfo.xcprivacy` is included in built `.app` bundle | — | smoke (find inside .app) | `find ~/Library/Developer/Xcode/DerivedData -name PrivacyInfo.xcprivacy -path '*Cortex.app*'` returns ≥1 match | ❌ W0: post-build CI step | ⬜ pending |
| FOUND-04 | TBD | TBD | No `Podfile`, no `Pods/` directory anywhere in repo | — | static | `! find . -name Podfile -o -name 'Pods' -type d 2>/dev/null \| grep -q .` | ❌ W0: CI step | ⬜ pending |
| FOUND-04 | TBD | TBD | `swift package resolve` succeeds from clean clone | — | smoke | `rm -rf .build ~/Library/Caches/org.swift.swiftpm && swift package resolve` (CI naturally exercises this on cache miss) | ❌ W0: ci.yml step | ⬜ pending |
| FOUND-04 | TBD | TBD | All four packages have valid `Package.swift` | — | smoke | for each package: `cd Packages/$PKG && swift package describe` | ❌ W0: 4× Package.swift | ⬜ pending |
| FOUND-05 | TBD | TBD | CI runs on `macos-15` with Xcode 26.x selected (NOT default 16.4) | — | smoke (CI runtime check) | CI step: `xcodebuild -version` output starts with `Xcode 26.` | ❌ W0: ci.yml + setup-xcode action | ⬜ pending |
| FOUND-05 | TBD | TBD | CI completes in <10 min on warm cache, <5 min cold | — | non-functional | observe CI run duration; assert via `timeout-minutes: 15` job setting | ❌ W0: ci.yml + manual observation | ⬜ pending |
| D-15 (cross-phase trap) | TBD | TBD | Hot-path policy script catches forbidden tokens when present | — | unit (test the script with a synthetic violation) | `echo 'dispatch_async(...)' > /tmp/test.swift && DIRS=/tmp ./Tools/scripts/hotpath-policy.sh; test $? -eq 1` | ❌ W0: script + (optional) self-test | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

The following files must exist before any other plan task runs (Wave 0 = scaffolding the test/validation surface):

- [ ] `Packages/CortexCore/Package.swift` — Swift+C target structure (Swift target depends on `CortexCoreC` C-only target)
- [ ] `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h` — defines `CORTEX_SHM_NAME` + `_Static_assert(sizeof(CORTEX_SHM_NAME) <= 32, ...)`
- [ ] `Packages/CortexCore/Sources/CortexCoreC/cortex_shm.c` — empty translation unit (or trivial helper) so the C target produces an object file
- [ ] `Packages/CortexCore/Sources/CortexCore/CortexCore.swift` — `@_exported import CortexCoreC` so consumers see the constant via `import CortexCore`
- [ ] `Packages/CortexCore/Tests/CortexCoreTests/ShmConstantsTests.swift` — Swift-side import + length test
- [ ] `Packages/{CortexIPC,CortexRender,CortexDecoder}/Package.swift` — empty stub manifests
- [ ] `Packages/{CortexIPC,CortexRender,CortexDecoder}/Sources/{Pkg}/{Pkg}.swift` — single-file empty stubs
- [ ] `Apps/CortexiOS/{App.swift, ContentView.swift, Info.plist, Cortex.entitlements, PrivacyInfo.xcprivacy}`
- [ ] `Apps/CortexMac/{App.swift, ContentView.swift, Info.plist, Cortex.entitlements, PrivacyInfo.xcprivacy}` — native AppKit (no Catalyst)
- [ ] `Apps/CortexDaemon/{main.swift, Info.plist, Cortex.entitlements}`
- [ ] `project.yml` — XcodeGen spec generating all three Xcode targets + workspace
- [ ] `Tools/scripts/validate-privacy-manifest.sh` — plutil + grep validator
- [ ] `Tools/scripts/hotpath-policy.sh` — grep gate for forbidden tokens, scoped to `Packages/CortexIPC/Sources/**` and `Packages/CortexCore/Sources/**`
- [ ] `.github/workflows/ci.yml` — macos-15 + setup-xcode@v1 pinned to 26.3 + actions/cache
- [ ] `.github/pull_request_template.md`
- [ ] `.swiftformat`
- [ ] `.swiftlint.yml`
- [ ] `.gitignore` (Xcode + Swift template)
- [ ] `Gemfile` + `Gemfile.lock` (fastlane via Bundler)
- [ ] `fastlane/{Fastfile, Matchfile, Appfile}` — placeholders (D-10)
- [ ] `docs/cortex-spec.md` — moved from repo root
- [ ] `docs/adr/0001-foundation-and-2026-toolchain.md`
- [ ] `README.md` — top-level
- [ ] Manual SC#2 runbook executed + evidence file (`sc2-evidence.md` or similar) committed after build succeeds

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Cross-process `shm_open` works between CortexMac and CortexDaemon inside App Group container | FOUND-02 (SC#2) | Headless CI cannot run two co-resident processes inside a real macOS sandbox with App Group entitlement enforced; `CODE_SIGNING_ALLOWED=NO` strips entitlements. Real validation requires a Personal-Team-signed local Mac build. | 1. Build `CortexMac` and `CortexDaemon` schemes locally with Personal Team auto-signing enabled. 2. Launch `CortexMac.app` from `~/Library/Developer/Xcode/DerivedData`. 3. Launch `CortexDaemon` as a separate process. 4. From CortexMac, call `shm_open("/cortex.samples", O_CREAT \| O_RDWR, 0600)` → verify success (fd ≥ 0). 5. From CortexDaemon, call `shm_open("/cortex.samples", O_RDWR, 0)` → verify success and identical inode (`fstat`). 6. Capture screenshots / logs into `.planning/phases/01-foundation-2026-toolchain/sc2-evidence.md`. 7. Commit evidence file. |
| iPad-on-device install with App Group entitlement works | FOUND-02 (SC#2 — iPad path) | Personal Team cannot claim App Group entitlements on iOS — requires paid Developer Program. **Deferred to Phase 8** when enrollment lands. Phase 1 verifies iPad simulator builds only. | iPad build verification in Phase 1: `xcodebuild build -scheme CortexiOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` succeeds. Real iPad device + App Group: deferred. |
| `_Static_assert` actually fires when the constant is broken | FOUND-01 / D-08 | Negative test — proves the trap works. Done once during Phase 1 execution; verifying machinery is automated thereafter. | 1. Edit `cortex_shm.h` to change `CORTEX_SHM_NAME` to something >31 bytes (e.g., `"/this.is.a.very.long.shm.name.that.exceeds.the.limit"`). 2. Run `swift build --package-path Packages/CortexCore`. 3. Verify build FAILS with the `_Static_assert` message. 4. Revert the edit. 5. Document in PR description / `sc2-evidence.md`. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies declared
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references in the verification map
- [ ] No watch-mode flags
- [ ] Feedback latency budget honored (≤30s quick, ≤600s full)
- [ ] Manual SC#2 runbook executed and evidence committed
- [ ] `_Static_assert` negative test executed at least once
- [ ] `nyquist_compliant: true` set in this file's frontmatter

**Approval:** pending
