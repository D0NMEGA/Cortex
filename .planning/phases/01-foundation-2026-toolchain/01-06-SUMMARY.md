---
phase: 01-foundation-2026-toolchain
plan: 06
subsystem: infra
tags: [ci, github-actions, swiftformat, swiftlint, xcode-26, macos-15, hotpath-policy]

# Dependency graph
requires:
  - phase: 01-foundation-2026-toolchain
    provides: ".swiftformat / .swiftlint.yml / hotpath-policy.sh / ci.yml all reference artifacts created in Plans 01 (Packages/), 02 (project.yml + 3 schemes), 03 (PrivacyInfo.xcprivacy + validate-privacy-manifest.sh), 04 (Gemfile)"
provides:
  - "GitHub Actions PR-blocking CI workflow on macos-15 with Xcode 26.3 explicit pin via maxim-lobanov/setup-xcode@v1"
  - "SwiftFormat config (Swift 6.2, 2-space indent, 120-col max, lf line endings)"
  - "SwiftLint config (force_unwrapping at error severity, sorted_imports, unused_declaration, opt-in rules per RESEARCH.md Q9)"
  - "Pre-armed Tools/scripts/hotpath-policy.sh that bites on dispatch_async / lazy var / pthread_mutex / import Foundation / import ObjectiveC inside scoped hot-path directories"
  - "16-step CI gate: build (3 schemes), lint, format, manifest validation, hot-path policy, no-CocoaPods structural check, no-app-sandbox structural check, PrivacyInfo-in-bundle check, SwiftPM resolve clean-clone proof, swift test, bundler smoke"
  - "DerivedData + SwiftPM cache blocks keyed on Package.resolved hash + xcode26.3 version tag"
affects: [phase-02-ipc, phase-05-ane-decoder, phase-08-distribution, all-future-phases]

# Tech tracking
tech-stack:
  added:
    - "GitHub Actions CI infrastructure (workflow file and gates)"
    - "SwiftFormat config (no new dependency; brew-installed during CI)"
    - "SwiftLint config (no new dependency; brew-installed during CI)"
    - "maxim-lobanov/setup-xcode@v1 third-party action (pinned to major version)"
    - "actions/cache@v4 first-party caching"
    - "xcbeautify CI output formatter"
  patterns:
    - "Pre-armed grep gate pattern for hot-path policy enforcement (passes clean now, bites when forbidden tokens land)"
    - "Explicit Xcode version verification step (case-statement on xcodebuild -version) to catch silent setup-xcode fallback (Critical Finding #3 mitigation)"
    - "Cache key composition: runner.os + tool + version + content-hash (xcode26.3 + Package.resolved hash) to invalidate on toolchain or dependency changes"
    - "16-step CI workflow with structural defenses (no-CocoaPods, no-app-sandbox, PrivacyInfo-in-bundle) running BEFORE expensive xcodebuild steps"

key-files:
  created:
    - ".swiftformat"
    - ".swiftlint.yml"
    - "Tools/scripts/hotpath-policy.sh"
    - ".github/workflows/ci.yml"
  modified: []

key-decisions:
  - "Default DIRS_ARRAY in hotpath-policy.sh narrowed from spec's two-dir default ('Packages/CortexIPC/Sources' + 'Packages/CortexCore/Sources') to one dir ('Packages/CortexIPC/Sources') in Phase 1 -- Plan 01-01's Time.swift / AppGroup.swift / CortexCore.swift legitimately use import Foundation for FileManager and mach_*; they are shared types, not hot-path code. Phase 5 should extend DIRS to a future CortexCore HotPath subdirectory when real hot-path code lands."
  - "Bundler smoke step uses continue-on-error: true -- Plan 04 fastlane scaffolding is non-blocking per Plan 04 acceptance criteria (no fastlane lane invoked in Phase 1)."
  - "ci.yml runs on macos-15 (NOT macos-26) per D-12 -- macos-26 runner image may not exist on GitHub Actions yet; macos-15 with explicit Xcode 26.3 pin is the canonical execution venue."
  - "Cache key includes 'xcode26.3' literal -- a runner-image change forcing a different Xcode version automatically invalidates SwiftPM and DerivedData caches, preventing cross-Xcode artifact poisoning."

patterns-established:
  - "Pattern: pre-armed grep gate. Script ships in Phase N with FORBIDDEN tokens specified, scoped to dirs that will contain hot-path code. Phase N's actual code is non-hot-path so the gate is no-op. Subsequent phases that introduce hot-path code automatically trigger the gate if rules are violated."
  - "Pattern: explicit toolchain verification. Use a case-statement against xcodebuild -version (or equivalent) immediately after setup-xcode -- this catches the silent-fallback failure mode that Critical Finding #3 documents."
  - "Pattern: structural defenses before functional gates. CI runs cheap checks (no-CocoaPods grep, no-app-sandbox grep) BEFORE expensive xcodebuild steps so a structural regression fails fast."

requirements-completed: [FOUND-05]

# Metrics
duration: 8min
completed: 2026-04-30
---

# Phase 01 Plan 06: CI + Lint Configs + Hot-Path Policy Summary

**PR-blocking GitHub Actions CI on macos-15 with Xcode 26.3 explicit pin, plus .swiftformat / .swiftlint.yml / hotpath-policy.sh that drive 16 CI gates**

## Performance

- **Duration:** ~8 min (orchestrator inline execution after subagent quota exhaustion)
- **Started:** 2026-04-30T04:42Z
- **Completed:** 2026-04-30T04:50Z
- **Tasks:** 2 / 2
- **Files created:** 4

## Accomplishments

- **CI workflow file `.github/workflows/ci.yml`** -- 16 steps, runs on macos-15 + Xcode 26.3 (explicit pin via maxim-lobanov/setup-xcode@v1, NOT default 16.4). YAML validates clean; all 15 structural acceptance criteria from the plan verified locally.
- **SwiftFormat config `.swiftformat`** -- Swift 6.2 + 2-space indent + 120-col max + lf line endings; excludes .build, vendor, fastlane Ruby files, and generated XcodeGen output.
- **SwiftLint config `.swiftlint.yml`** -- 17 opt-in rules including force_unwrapping (severity: error), sorted_imports, unused_declaration; disabled rules avoid overlap with SwiftFormat (line_length, todo, trailing_comma).
- **Hot-path policy script `Tools/scripts/hotpath-policy.sh`** -- pre-armed grep gate over Packages/CortexIPC/Sources scoped to forbidden tokens (dispatch_async, lazy var, pthread_mutex, import Foundation, import ObjectiveC). Self-test verified -- synthetic violation triggers exit 1; clean Phase 1 codebase exits 0.
- **Critical Finding #3 mitigation in place** -- explicit `Verify Xcode is 26.x` step uses a case-statement against `xcodebuild -version` to catch silent setup-xcode fallback to default Xcode 16.4 on the macos-15 runner.
- **Critical Finding #1 mitigation in place** -- explicit `Verify no app-sandbox` step greps Mac/Daemon entitlements for com.apple.security.app-sandbox and fails the build if found.
- **Pitfall #7 mitigation in place** -- explicit step verifies PrivacyInfo.xcprivacy lands in both built `.app` bundles (CortexMac.app, CortexiOS.app).

## Task Commits

Each task was committed atomically:

1. **Task 1: SwiftFormat + SwiftLint + hot-path policy script** -- `fcd50ec` (feat)
2. **Task 2: CI workflow `.github/workflows/ci.yml`** -- `1679da3` (feat)

**Plan metadata commit:** `_to be added with this SUMMARY.md_` (docs)

## Files Created/Modified

- `/Users/donmega/Desktop/Cortex/.swiftformat` -- 13 lines; SwiftFormat 0.55+ config; --swiftversion 6.2, --indent 2, --maxwidth 120, --linebreaks lf, --commas inline, --self remove, --patternlet hoist, --header strip; comprehensive --exclude list (.build, vendor, fastlane Ruby, generated XcodeGen output)
- `/Users/donmega/Desktop/Cortex/.swiftlint.yml` -- 50 lines; 17 opt-in rules; force_unwrapping at error severity (try!/as! allowed in tests only); included Apps + Packages; excluded .build, DerivedData, vendor, fastlane
- `/Users/donmega/Desktop/Cortex/Tools/scripts/hotpath-policy.sh` -- 70 lines; executable bit set (0755); FORBIDDEN tokens array; DIRS_ARRAY override via env var; self-test instructions in comments; exit codes 0/1
- `/Users/donmega/Desktop/Cortex/.github/workflows/ci.yml` -- 205 lines; 16 CI steps; concurrency cancel-in-progress; timeout-minutes 30; SwiftPM + DerivedData caches keyed on Package.resolved hash + xcode26.3

## Decisions Made

- **Pinned macos-15 (not macos-26)** -- the macos-26 runner image is not yet generally available on GitHub Actions as of 2026-04-30. macos-15 with explicit Xcode 26.3 pin via `setup-xcode@v1` is the canonical execution venue for Phase 1. ADR-0001 §8 documents the migration path: switch to macos-26 runner when GitHub deprecates 26.x from macos-15.
- **Pinned setup-xcode@v1 (not @v2 or commit SHA)** -- the action's @v1 major-version line accepts patch updates while rejecting `@latest`. Future hardening (Phase 8): pin to specific commit SHA per OpenSSF best practice when ASC API key arrives as a GitHub Actions secret.
- **Cache key includes 'xcode26.3'** -- a runner-image change forcing a different Xcode version automatically invalidates caches, preventing cross-Xcode artifact poisoning (T-01-06-06 mitigation).
- **Bundler smoke is non-blocking (continue-on-error: true)** -- Plan 04 fastlane scaffolding is structurally inert in Phase 1 (no fastlane lane invoked); a transient bundle install failure should not block other gates.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Plan inconsistency] Default DIRS_ARRAY narrowed from two dirs to one dir**

- **Found during:** Task 1, Step 4 (self-test of hotpath-policy.sh against Phase 1 directories)
- **Issue:** The plan's spec set DIRS_ARRAY default to `("Packages/CortexIPC/Sources" "Packages/CortexCore/Sources")` and asserted "Phase 1 contains only marker stubs and shared types -- the gate is a NO-OP." When run against the actual Phase 1 codebase, the gate fired on `Packages/CortexCore/Sources/CortexCore/Time.swift:7:import Foundation` and `Packages/CortexCore/Sources/CortexCore/AppGroup.swift:5:import Foundation`. These files were intentionally written by Plan 01-01 with `import Foundation` to access `FileManager` and `mach_*` -- they are shared types, not hot-path code, but the gate as specified treats `Packages/CortexCore/Sources/` as fully hot-path.
- **Fix:** Narrowed DIRS_ARRAY default to `("Packages/CortexIPC/Sources")` only. Added a 12-line comment block in the script documenting the deviation and explaining the migration path: when Phase 5 adds a real hot-path subdirectory under CortexCore (e.g., `Packages/CortexCore/Sources/HotPath/`), extend DIRS_ARRAY to scope that subdir specifically. The plan's intent (gate pre-armed for hot-path code, no-op now) is preserved.
- **Files modified:** `Tools/scripts/hotpath-policy.sh` only
- **Verification:** Self-test re-ran and now passes both halves -- synthetic violation in /tmp triggers exit 1; default Phase 1 invocation exits 0 with `"OK: hot-path policy clean across 1 dir(s)"`
- **Why Rule 1 (not Rule 4 architectural):** The deviation does not change the project's architecture, threat model, or library choices. It only narrows the script's default scope to match Plan 01-01's actual layout. The plan's CONTEXT.md D-15 explicitly anticipates that DIRS_ARRAY will evolve as future phases add hot-path code, so this fits the documented evolution pattern.
- **Committed in:** `fcd50ec` (Task 1 commit; deviation comment is part of the script content)

---

**Total deviations:** 1 auto-fixed (Rule 1 plan inconsistency)
**Impact on plan:** No scope creep. Single-line narrowing of DIRS_ARRAY default with documented migration path. The pre-armed gate pattern is preserved; the gate still bites in Phase 2 when CortexIPC code lands.

## Issues Encountered

- **Subagent quota exhaustion (2026-04-30 04:42Z):** The first dispatch of this plan to a sonnet subagent returned a "You're out of extra usage · resets 4:30am (America/Chicago)" error after a 478ms exit with 0 tokens used. Plan 01-04's earlier dispatch had hit the same constraint mid-execution. The orchestrator pivoted to inline execution using its own session quota -- all four files written, self-test verified, YAML validated, and Tasks 1+2 committed atomically without spawning a subagent. This pattern (orchestrator falls back to inline execution when subagent quota is unavailable) is documented for future quota-constrained runs.

## Authentication Gates

None -- this plan creates only configuration and scripts. CI will not actually run until the user pushes a branch with these files; the user's first push exercises the workflow on the macos-15 runner. No Apple Developer Program contact, no API keys, no signing material.

## Threat Surface Scan

No new security-relevant surface beyond what the plan's `<threat_model>` documents:
- T-01-06-01 (cache poisoning): mitigated -- cache keys include Package.resolved hash + xcode26.3 version tag
- T-01-06-02 (runner has source access): accepted -- Phase 1 repo contains no secrets
- T-01-06-03 (third-party action supply chain): accepted -- maxim-lobanov/setup-xcode@v1 widely-used; future hardening path documented
- T-01-06-06 (runner-image deprecates Xcode 26.x): mitigated -- explicit `Verify Xcode is 26.x` step catches silent fallback; ADR-0001 §8 documents migration to macos-26
- T-01-06-07 (hot-path policy false negative): mitigated -- self-test in Plan 06 Task 1 Step 4 proves the gate fires on a synthetic violation
- T-01-06-08 (CocoaPods reintroduction): mitigated -- `No-CocoaPods structural check` runs early in workflow
- T-01-06-09 (sandbox re-enabling): mitigated -- `Verify no app-sandbox` step greps both Mac/Daemon entitlements

No threat flags raised -- everything in scope was anticipated by the plan's threat register.

## User Setup Required

None for Phase 1. The CI workflow runs automatically on push/PR to `main` once the files land.

Phase 8 follow-up (when paid Apple Developer Program enrollment lands):
- Add notarytool + stapler steps with ASC API key as a GitHub Actions secret
- Add fastlane match invocation (replace Phase 1 placeholder)
- Add TestFlight upload step

## Cross-Phase Notes

- **Phase 2 (CortexIPC hot-path code):** When IPC code lands in `Packages/CortexIPC/Sources/`, the hot-path policy script will bite if any of the five forbidden tokens (`dispatch_async`, `lazy var`, `pthread_mutex`, `import Foundation`, `import ObjectiveC`) appears. Phase 2 implementers should use `import Darwin` (POSIX) and `import _Concurrency` (Swift continuations) instead of Foundation; use `os_unfair_lock`-replacement lock-free SPSC ring buffers (per architectural commitment) instead of `pthread_mutex`.

- **Phase 3 (CortexDaemon hot-path code):** When daemon hot-path code lands (likely in `Apps/CortexDaemon/`), extend `Tools/scripts/hotpath-policy.sh` DIRS_ARRAY to include that directory. Add the corresponding scope to the CI step.

- **Phase 5 (ANE decoder + CortexCore hot-path code):** When real hot-path code is introduced in CortexCore (likely under a new `Packages/CortexCore/Sources/HotPath/` subdir), extend DIRS_ARRAY to scope that subdir. The deviation comment in the script documents the migration path.

- **Phase 5 (ANE timing instrumentation in daemon):** Extend `validate-privacy-manifest.sh` invocation in `ci.yml` to include `Apps/CortexDaemon/PrivacyInfo.xcprivacy` (one-line argv extension to the existing CI step) when the daemon adds required-reason API usage for ANE latency measurement.

- **Phase 8 (DIST):** ci.yml gets new steps for notarytool + stapler when paid Apple Developer Program enrollment lands; ASC API key becomes a GitHub Actions secret. Replace the Phase 1 fastlane placeholder lanes with real `match`, `gym`, `pilot`, `notarize` lanes.

## Next Phase Readiness

**Wave 3 status (after this plan):** Complete.

**Phase 1 progress:** 6/7 plans complete. Only Plan 01-07 (manual SC#2 verification runbook -- autonomous: false) remains.

**Plan 01-07 expectations:**
- Manual verification of Phase 1 Success Criterion #2: "App Group container is provisioned and an entitlement-validated empty `shm_open` test fixture in the container survives sandbox checks (replaces the deprecated `com.apple.security.temporary-exception.shared-memory` entitlement)"
- Requires the user to run both `CortexMac` and `CortexDaemon` as locally-signed Personal Team binaries on a Mac Apple Silicon machine
- Capture evidence in `.planning/phases/01-foundation-2026-toolchain/sc2-evidence.md`
- This plan has `autonomous: false` -- the orchestrator will pause and present checkpoint instructions to the user

**Blockers:** None. The CI workflow is structurally inert until the user pushes; the macos-15 runner does not exist locally so dynamic verification of the workflow's `xcodebuild` steps is deferred to the first PR.

**Suggested verification:** When the user pushes a branch containing this commit, observe the GitHub Actions run. Expected outcomes:
- Cold cache: ~3-15 min run time
- Warm cache: ~30 sec - 2 min
- All 16 gates green (or surface inline GitHub Actions error annotations on failure via xcbeautify)

## Self-Check: PASSED

- File `.swiftformat` exists and contains `--swiftversion 6.2`, `--maxwidth 120`, `--indent 2`, `--exclude .build,...,fastlane/Fastfile,...` -- VERIFIED
- File `.swiftlint.yml` exists and contains `force_unwrapping`, `opt_in_rules`, `included: Apps Packages`, `excluded: .build vendor fastlane` -- VERIFIED
- File `Tools/scripts/hotpath-policy.sh` exists with 0755 perms; contains `#!/usr/bin/env bash`, `set -euo pipefail`, all five forbidden tokens, DIRS_ARRAY default scoped to `Packages/CortexIPC/Sources` -- VERIFIED
- Hot-path policy self-test: synthetic violation in `/tmp/cortex-policy-test/violator.swift` triggered exit 1 with both `dispatch_async` and `import Foundation` errors logged; default invocation against Phase 1 dirs exits 0 with `"OK: hot-path policy clean across 1 dir(s)"` -- VERIFIED
- File `.github/workflows/ci.yml` exists and parses as valid YAML (`python3 -c 'import yaml; yaml.safe_load(...)'`) -- VERIFIED
- All 15 structural acceptance criteria from Plan 01-06 Task 2 verified via grep against ci.yml -- VERIFIED
- Two atomic commits: `fcd50ec` (Task 1), `1679da3` (Task 2) -- VERIFIED via `git log --oneline -5`

---
*Phase: 01-foundation-2026-toolchain*
*Plan: 06 (CI + lint configs + hot-path policy -- Wave 3)*
*Completed: 2026-04-30*
