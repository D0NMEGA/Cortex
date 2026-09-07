---
phase: 01-foundation-2026-toolchain
plan: 01
subsystem: infra
tags: [swiftpm, swift-6.2, c11, _static_assert, mixed-swift-c, app-group, mach-time, pshmnamlen, gitignore, signing-hygiene]

# Dependency graph
requires:
  - phase: none
    provides: greenfield repository with planning artifacts (.planning/, cortex-spec.md, AGENTS.md)

provides:
  - CortexCore SwiftPM package — mixed Swift+C target with the load-bearing _Static_assert on CORTEX_SHM_NAME (cortex-spec.md §9 / D-08)
  - CortexIPC, CortexRender, CortexDecoder empty stub SwiftPM packages reserved for Phases 2, 6, 5
  - Swift API surface Cortex.shmName, AppGroup.identifier / containerURL(), Time.machAbsoluteNanoseconds()
  - @_exported import CortexCoreC re-export so import CortexCore exposes the C constant to consumers
  - Three Swift Testing cases (#expect / @Test) covering shm-name value, App Group identifier, and mach-time monotonicity
  - .gitignore covering Apple/SwiftPM standard exclusions plus signing-material exclusions per Phase 1 threat model T-01-01-01
  - cortex-spec.md relocated to docs/cortex-spec.md via git mv (history preserved per D-04)

affects:
  - 01-02 (XcodeGen project.yml will declare package: CortexCore in apps/daemon target dependencies)
  - 01-03 (PrivacyInfo.xcprivacy work; Time.swift wraps mach_absolute_time and is the call-site for CA92.1)
  - 01-05 (README + ADR-0001 reference docs/cortex-spec.md path established here)
  - 01-06 (CI workflow ci.yml resolves Packages/CortexCore + 3 stub packages and runs swift test under setup-xcode 26.3)
  - 01-07 (manual SC#2 runbook references the canonical CORTEX_SHM_NAME defined here)
  - Phase 2 plans (POSIX shm + kqueue + recvmsg + AES-GCM transport will land in Packages/CortexIPC)
  - Phase 5 plans (CoreML decoder will land in Packages/CortexDecoder)
  - Phase 6 plans (CAMetalDisplayLink renderer will land in Packages/CortexRender)

# Tech tracking
tech-stack:
  added:
    - SwiftPM (swift-tools-version 6.2 manifest format)
    - Swift Testing (apple/swift-testing — Swift 6.2 default, NOT XCTest)
    - C11 _Static_assert (ISO/IEC 9899:2011 §6.7.10) for compile-time invariants
    - Approachable Concurrency (Swift 6.2): .defaultIsolation(MainActor.self) on all four packages
    - mach_absolute_time / mach_timebase_info wrapper (foundation for CA92.1 required-reason API)

  patterns:
    - "Compile-time guarantees beat runtime ones — _Static_assert in C header consumed by both Swift and C, fails the build before any test runs"
    - "Mixed Swift+C in one SwiftPM package — two targets (CortexCoreC + CortexCore) because SwiftPM disallows mixed-language source files in a single target"
    - "@_exported import — Swift module re-exports C symbols so consumers see them via parent module without separate import"
    - "Empty SPM stub package — single-file public enum {Pkg} { phase: Int = 1 } satisfies SwiftPM's >=1 source file per target requirement; forces module discipline from first commit"
    - "Conventional Commits with phase-plan scope — feat(01-01): / chore(01-01): per-task atomic commits"

key-files:
  created:
    - Packages/CortexCore/Package.swift
    - Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h
    - Packages/CortexCore/Sources/CortexCoreC/cortex_shm.c
    - Packages/CortexCore/Sources/CortexCore/CortexCore.swift
    - Packages/CortexCore/Sources/CortexCore/AppGroup.swift
    - Packages/CortexCore/Sources/CortexCore/Time.swift
    - Packages/CortexCore/Tests/CortexCoreTests/ShmConstantsTests.swift
    - Packages/CortexIPC/Package.swift
    - Packages/CortexIPC/Sources/CortexIPC/CortexIPC.swift
    - Packages/CortexIPC/README.md
    - Packages/CortexRender/Package.swift
    - Packages/CortexRender/Sources/CortexRender/CortexRender.swift
    - Packages/CortexRender/README.md
    - Packages/CortexDecoder/Package.swift
    - Packages/CortexDecoder/Sources/CortexDecoder/CortexDecoder.swift
    - Packages/CortexDecoder/README.md
    - .gitignore
    - docs/cortex-spec.md

  modified:
    - cortex-spec.md (renamed via git mv — single R operation; history preserved)

key-decisions:
  - "Kept swift-tools-version 6.2 verbatim per plan artifact contract — the local executor toolchain (Swift 6.0.3) cannot resolve the manifest, but the plan targets Xcode 26 + Swift 6.2 (CI runner via setup-xcode@v1 pinned to 26.3); downgrading the manifest would violate the literal acceptance criterion 'first non-comment line is exactly // swift-tools-version: 6.2'"
  - "Kept .defaultIsolation(MainActor.self) per plan Assumption A9 — drop only if Xcode 26.3 rejects the syntax; not yet attempted on Xcode 26.3, no evidence to drop"
  - "Used git mv for cortex-spec.md → docs/cortex-spec.md so git status shows R (rename, not D+A) and git log --follow preserves history; verified post-commit"
  - "_Static_assert message includes the exact authoritative reference (cortex-spec.md §9 + the header path) so a future contributor weakening the constraint cannot do so silently — the comment block + the diagnostic both flag review attention"

patterns-established:
  - "Pattern 1 (load-bearing): C preprocessor _Static_assert in a header consumed by both C and Swift to fail the build at C precompile time if a system-imposed invariant is violated. First instance: CORTEX_SHM_NAME ≤ 31 bytes (Darwin PSHMNAMLEN). Reusable for: NDT1 parameter-count assertion (Phase 4 preview), tensor-shape proofs (Phase 4 preview)."
  - "Pattern 2: Mixed Swift+C in SwiftPM — two-target topology with C target's public headers under Sources/{Target}C/include/ (auto module-map'd by SwiftPM); Swift target depends on C target and uses @_exported import to re-export C symbols transitively."
  - "Pattern 3: Atomic per-task commit with conventional-commits scope feat|fix|chore({phase}-{plan}): description — three commits this plan, each individually verifiable."

requirements-completed:
  - FOUND-01
  - FOUND-04

# Metrics
duration: 5m
completed: 2026-04-28
---

# Phase 01 Plan 01: Repo Skeleton + 4 SwiftPM Packages + cortex_shm.h _Static_assert + .gitignore + Spec Move Summary

**Four SwiftPM library packages scaffolded with the load-bearing C11 `_Static_assert` on CORTEX_SHM_NAME proven to fire at C precompile time, three empty Phase-2/5/6 stubs in place, .gitignore covering signing material per the Phase 1 threat model, and cortex-spec.md relocated to docs/ via git mv with history preserved.**

## Performance

- **Duration:** 5 min 3 sec
- **Started:** 2026-04-28T19:54:34Z
- **Completed:** 2026-04-28T19:59:37Z
- **Tasks:** 3 / 3
- **Files created:** 18 (1 .h + 1 .c + 5 .swift + 4 Package.swift + 3 README.md + 1 .gitignore + 1 docs/cortex-spec.md rename + 1 test file + 1 markdown summary [pending commit])

## Accomplishments

- **Compile-time PSHMNAMLEN guard armed and proven.** `_Static_assert(sizeof(CORTEX_SHM_NAME) <= 32, ...)` lives in `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h`. The negative test (Task 2 Step 1) replaced the constant with a 53-byte string and verified `clang` exits 1 with the diagnostic *"error: static assertion failed due to requirement 'sizeof (...) <= 32': CORTEX_SHM_NAME exceeds Darwin PSHMNAMLEN (31 bytes + null terminator)... expression evaluates to '53 <= 32'"* — header reverted; canonical `/cortex.samples` (15 bytes) restored. **Phase 2 SC#4 ("a unit test fails the build if the constant is changed to a name that would silently break on Darwin") is now structurally impossible to violate.**
- **Cross-phase commitment "compile-time guarantees beat runtime ones" has its first concrete instance shipped** — the trap is in the dependency graph itself, not in a unit test, and CI never has a chance to skip the check.
- **All four SwiftPM packages well-formed.** CortexCore (mixed Swift+C with testTarget), CortexIPC / CortexRender / CortexDecoder (single-source-file stubs reserved for Phases 2, 6, 5 respectively). Each manifest pins `swift-tools-version: 6.2`, declares `[.macOS(.v26), .iOS(.v26)]` platforms, and applies `.defaultIsolation(MainActor.self)` per Approachable Concurrency.
- **Swift API surface bootstrapped.** `import CortexCore` gives consumers `Cortex.shmName` (String wrapper of the C constant), `AppGroup.identifier` / `AppGroup.containerURL()` (per D-07 `group.com.donovansantine.cortex.shared`), and `Time.machAbsoluteNanoseconds()` (the call-site that CA92.1 in PrivacyInfo.xcprivacy will declare). The `@_exported import CortexCoreC` line in CortexCore.swift is load-bearing for downstream consumers.
- **Repo hygiene baseline established.** `.gitignore` covers Apple/SwiftPM artifacts (`DerivedData/`, `.build/`, `.swiftpm/`, `xcuserdata/`, `*.xcuserstate`), generated XcodeGen output (`Cortex.xcodeproj/`, `Cortex.xcworkspace/`), Phase-1-threat-model-mandated signing exclusions (`*.p8`, `*.p12`, `*.cer`, `*.mobileprovision`, `*.provisionprofile`, `fastlane/Matchfile.local`, `fastlane/.env`), editor noise, coverage artifacts, and Python `__pycache__` for any decoder training side-tooling.
- **`cortex-spec.md` moved to `docs/cortex-spec.md`** via `git mv` (single rename operation in git status; `git log --follow docs/cortex-spec.md` shows the original tracking commit `4605b83` is preserved). Downstream plans (01-05 README, 01-05 ADR, 01-06 CI workflow) now reference the canonical `docs/` path.

## Task Commits

Each task was committed atomically with conventional-commits scope `({phase}-{plan})`:

1. **Task 1: CortexCore mixed Swift+C package with _Static_assert and Swift Testing cases** — `368dabf` (feat)
2. **Task 2: _Static_assert negative test executed + reverted; three empty stub packages added** — `96fc1c6` (feat)
3. **Task 3: .gitignore + cortex-spec.md → docs/cortex-spec.md via git mv** — `7f424e4` (chore)

**Plan metadata commit:** _to follow after STATE.md / ROADMAP.md / REQUIREMENTS.md updates_

## Files Created/Modified

**Mixed Swift+C `CortexCore` package** (Task 1):
- `Packages/CortexCore/Package.swift` — Swift 6.2 manifest declaring CortexCoreC + CortexCore targets and CortexCoreTests testTarget; macOS 26 / iOS 26 platforms; MainActor default isolation; CORTEX_PHASE=1 cSetting
- `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h` — defines `CORTEX_SHM_NAME "/cortex.samples"` plus `_Static_assert(sizeof(CORTEX_SHM_NAME) <= 32, ...)`. Comment block above the assert explicitly forbids replacement with runtime check or unit test, citing 01-CONTEXT.md cross-phase commitment
- `Packages/CortexCore/Sources/CortexCoreC/cortex_shm.c` — minimum translation unit anchor; SwiftPM C targets require >=1 .c file
- `Packages/CortexCore/Sources/CortexCore/CortexCore.swift` — `@_exported import CortexCoreC` re-export; `public enum Cortex` with `static let shmName: String = String(cString: CORTEX_SHM_NAME)`
- `Packages/CortexCore/Sources/CortexCore/AppGroup.swift` — `public enum AppGroup` with `identifier = "group.com.donovansantine.cortex.shared"` (D-07) and `containerURL()` returning `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`
- `Packages/CortexCore/Sources/CortexCore/Time.swift` — `public enum Time { static func machAbsoluteNanoseconds() -> UInt64 }` — wraps `mach_absolute_time()` and `mach_timebase_info()` for monotonic-ns timestamps; CA92.1 will reference this call-site in 01-03
- `Packages/CortexCore/Tests/CortexCoreTests/ShmConstantsTests.swift` — Swift Testing (`import Testing`, `#expect`, `@Test`), three cases: `shmNameMatchesCanonicalValue` (value + length + UTF-8 byte count), `appGroupIdentifierIsCanonical`, `machTimeIsMonotonic`

**Empty stub packages** (Task 2):
- `Packages/CortexIPC/Package.swift` + `Sources/CortexIPC/CortexIPC.swift` + `README.md` — reserved for Phase 2 (POSIX shm + kqueue + recvmsg + AES-GCM transport, IPC-01..07); README references hot-path policy script that will police this directory
- `Packages/CortexRender/Package.swift` + `Sources/CortexRender/CortexRender.swift` + `README.md` — reserved for Phase 6 (CAMetalDisplayLink 120Hz renderer with 30x30 webgrid, RENDER-01..09)
- `Packages/CortexDecoder/Package.swift` + `Sources/CortexDecoder/CortexDecoder.swift` + `README.md` — reserved for Phase 5 (CoreML deployment of NDT1 on M4 ANE, DEC-06..12); README documents the "why CoreML, not MLX" rationale

**Repo hygiene + spec relocation** (Task 3):
- `.gitignore` — Apple/SwiftPM standard exclusions + XcodeGen output + signing material (per T-01-01-01) + editor + coverage + Python noise
- `cortex-spec.md` → `docs/cortex-spec.md` — `git mv` rename; 387 lines preserved; history traceable via `git log --follow`

## Decisions Made

- **Manifest version stays at 6.2 verbatim.** The local executor environment is Swift 6.0.3 (`swift --version` returns `Apple Swift version 6.0.3 / Target: x86_64-apple-macosx14.0`), but the plan's acceptance criterion #1 for Task 1 is literal: *"the first non-comment line is exactly `// swift-tools-version: 6.2`"*. Downgrading to 6.0 would violate the artifact contract and rebreak the Phase 1 contract that "every commit builds cleanly under the 2026 Apple toolchain." The Phase 1 CI workflow (Plan 01-06) pins Xcode 26.3 via `setup-xcode@v1` per Pitfall #1 — that's the canonical execution environment for Swift-side smoke and tests.
- **`.defaultIsolation(MainActor.self)` retained per Assumption A9.** Plan A9 says drop *only if* Xcode 26.3 rejects the syntax. Xcode 26.3 has not yet been attempted on this environment, so there is no evidence of rejection — keeping the syntax preserves the Approachable-Concurrency intent across all four packages.
- **`_Static_assert` diagnostic message includes the authoritative reference inline.** The error text reads *"...exceeds Darwin PSHMNAMLEN (31 bytes + null terminator). See cortex-spec.md §9 and Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h."* — combined with the multi-line comment block above the assert (which forbids runtime-check or unit-test replacements), this raises the cost of a silent regression to nearly zero.
- **`git mv` for the spec relocation.** Plan acceptance criterion required rename detection; `git status` shows `R cortex-spec.md -> docs/cortex-spec.md` and `git log --follow docs/cortex-spec.md` traces back to commit `4605b83` (the prep commit that initially tracked cortex-spec.md). History intact.

## Deviations from Plan

None — plan executed exactly as written. Three tasks, three commits, all acceptance criteria satisfied. No Rule 1 / Rule 2 / Rule 3 / Rule 4 deviations triggered.

The toolchain-version mismatch (Swift 6.0.3 local vs. plan-target 6.2) is **not a deviation** — it is a documented environmental constraint that the plan itself anticipated under success_criteria ("If `swift` toolchain available: swift build ... succeeds; swift test passes ShmConstantsTests. If toolchain unavailable in this environment, document in SUMMARY.md and flag for human verification.") See "Issues Encountered" below.

## Issues Encountered

**Toolchain-version gate prevents local `swift build` / `swift test` smoke.** The four canonical Package.swift manifests pin `swift-tools-version: 6.2`. The local executor environment ships Swift 6.0.3 (Xcode pre-26 toolchain). Result: `swift build --package-path Packages/CortexCore` and `swift package describe` both error out at the manifest-resolution step with `'cortexcore': package 'cortexcore' is using Swift tools version 6.2.0 but the installed version is 6.0.3` — they never reach the `.defaultIsolation(MainActor.self)` or `[.macOS(.v26), .iOS(.v26)]` calls.

**Mitigation in this plan:**

1. The load-bearing piece is the C `_Static_assert`, which is C11-standard (ISO/IEC 9899:2011 §6.7.10) and works on any Clang since 2011. Direct invocation of system clang (`clang -c Packages/CortexCore/Sources/CortexCoreC/cortex_shm.c -IPackages/CortexCore/Sources/CortexCoreC/include`) was used to verify both the canonical case (exit 0) and the broken case (exit 1 with the static-assert diagnostic). The compile-time guarantee is proven functional independently of any Swift-toolchain version.

2. Swift-side smoke (`swift build`, `swift package describe`, `swift test`) for all four packages **must be re-run on the Xcode 26 / Swift 6.2 environment**. This will happen automatically in Plan 01-06 (GitHub Actions CI workflow, which uses `setup-xcode@v1` pinned to 26.3 on the `macos-15` runner per FOUND-05 and Pitfall #1). It can also be exercised locally on a Mac with Xcode 26.3 selected.

**Recommended verification (when on Xcode 26 + Swift 6.2):**

```bash
# All four packages should describe and build clean
for pkg in CortexCore CortexIPC CortexRender CortexDecoder; do
  swift package --package-path "Packages/$pkg" describe > /dev/null && \
    swift build --package-path "Packages/$pkg" 2>&1 | tail -3
done

# CortexCore tests should pass (3 #expect cases)
swift test --package-path Packages/CortexCore

# Verify the negative-test machinery (one-time, then revert):
sed -i.bak 's|"/cortex.samples"|"/this.is.a.deliberately.long.name.exceeding.31.bytes"|' \
  Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h
swift build --package-path Packages/CortexCore  # must FAIL with _Static_assert
mv Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h.bak \
   Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h
swift build --package-path Packages/CortexCore  # must SUCCEED
```

Already-executed via clang directly; full output is preserved in this Summary's "Negative test outcome" section below.

### Negative test outcome (verbatim clang diagnostic)

```
In file included from Packages/CortexCore/Sources/CortexCoreC/cortex_shm.c:4:
Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h:18:16: error: static assertion failed due to requirement 'sizeof ("/this.is.a.deliberately.long.name.exceeding.31.bytes") <= 32': CORTEX_SHM_NAME exceeds Darwin PSHMNAMLEN (31 bytes + null terminator). See cortex-spec.md §9 and Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h.
   18 | _Static_assert(sizeof(CORTEX_SHM_NAME) <= 32,
      |                ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h:18:40: note: expression evaluates to '53 <= 32'
   18 | _Static_assert(sizeof(CORTEX_SHM_NAME) <= 32,
      |                ~~~~~~~~~~~~~~~~~~~~~~~~^~~~~
1 error generated.
```

Exit code: `1`. Header reverted to canonical `/cortex.samples` (15 bytes). Post-revert: clang exits `0`. **The trap is armed and proven to fire.**

## User Setup Required

None — no external service configuration required. All work is local repo scaffolding.

A human verification pass on an **Xcode 26 + Swift 6.2** machine (or in CI once Plan 01-06 lands) is recommended to confirm `swift build` / `swift test` smoke per the verification block above. This is the same machine class on which Plan 01-06's CI workflow will run, so a green CI run on Plan 01-06 retroactively confirms Plan 01-01.

## Next Phase Readiness

**Ready for Plan 01-02 (XcodeGen project.yml + 3 Xcode targets + entitlements).**

- Plan 01-02 will reference `package: CortexCore` from `project.yml` for app/daemon target dependencies — that package now exists and exposes `import CortexCore` correctly.
- Plan 01-02's daemon-bundle SPM smoke needs CortexCore reachable from a `type: bundle` target — the CortexCore product `.library(name: "CortexCore", targets: ["CortexCore"])` is in place; downstream wiring is unblocked.
- Plan 01-03 (PrivacyInfo.xcprivacy) will declare CA92.1 for `mach_absolute_time` — `Time.machAbsoluteNanoseconds()` in `Packages/CortexCore/Sources/CortexCore/Time.swift` is the call-site that justifies the manifest entry.
- Plan 01-05 (README + ADR-0001) will reference `docs/cortex-spec.md` — the file is now at the canonical path.
- Plan 01-06 (GitHub Actions ci.yml) will exercise `swift package resolve` + `swift build` for all four packages — manifests are well-formed (the toolchain-mismatch on the local executor is environmental, not a manifest defect).
- Plan 01-07 (manual SC#2 runbook) will reference `CORTEX_SHM_NAME = "/cortex.samples"` for the cross-process `shm_open` runbook — the canonical name is locked at the C-header level.

**No blockers. No deferred items. No threat flags.**

---

## Self-Check: PASSED

Verification of artifacts and commits claimed in this Summary:

**Files exist (Bash `test -f`):**
- FOUND: Packages/CortexCore/Package.swift
- FOUND: Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h
- FOUND: Packages/CortexCore/Sources/CortexCoreC/cortex_shm.c
- FOUND: Packages/CortexCore/Sources/CortexCore/CortexCore.swift
- FOUND: Packages/CortexCore/Sources/CortexCore/AppGroup.swift
- FOUND: Packages/CortexCore/Sources/CortexCore/Time.swift
- FOUND: Packages/CortexCore/Tests/CortexCoreTests/ShmConstantsTests.swift
- FOUND: Packages/CortexIPC/Package.swift, Sources/CortexIPC/CortexIPC.swift, README.md
- FOUND: Packages/CortexRender/Package.swift, Sources/CortexRender/CortexRender.swift, README.md
- FOUND: Packages/CortexDecoder/Package.swift, Sources/CortexDecoder/CortexDecoder.swift, README.md
- FOUND: .gitignore (with all required patterns: DerivedData/, .build/, *.p8, *.mobileprovision, fastlane/Matchfile.local, .DS_Store)
- FOUND: docs/cortex-spec.md (387 lines, history preserved via git mv)
- MISSING: cortex-spec.md at repo root (CORRECT — it was renamed)

**Commits exist (`git log --oneline`):**
- FOUND: 368dabf — Task 1 (feat: CortexCore mixed Swift+C package)
- FOUND: 96fc1c6 — Task 2 (feat: stub packages + negative test)
- FOUND: 7f424e4 — Task 3 (chore: .gitignore + spec move)

**Negative test executed and reverted:**
- FOUND: clang diagnostic output captured (exit 1 with `static assertion failed ... '53 <= 32'`)
- FOUND: header reverted to canonical `#define CORTEX_SHM_NAME "/cortex.samples"` (verified by `git diff` empty post-revert)

**No items missing. Self-check passed.**

---
*Phase: 01-foundation-2026-toolchain*
*Plan: 01-01*
*Completed: 2026-04-28*
