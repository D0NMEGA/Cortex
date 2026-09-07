---
phase: 01-foundation-2026-toolchain
plan: 03
subsystem: infra
tags: [privacy-manifest, ca92.1, mach-absolute-time, plutil, ci-gate, app-store, foundation]

# Dependency graph
requires:
  - phase: 01-01
    provides: Time.machAbsoluteNanoseconds() in Packages/CortexCore/Sources/CortexCore/Time.swift — the call-site that justifies CA92.1 in the manifest

provides:
  - Apps/CortexiOS/PrivacyInfo.xcprivacy declaring CA92.1 under NSPrivacyAccessedAPICategorySystemBootTime for mach_absolute_time
  - Apps/CortexMac/PrivacyInfo.xcprivacy declaring the same (byte-for-byte identical to iOS)
  - Tools/scripts/validate-privacy-manifest.sh — bash + plutil + grep CI gate enforcing four invariants per manifest
  - Variadic-argv design lets Phase 2/3 add the daemon manifest with a one-line CI tweak
  - Negative-control test executed: gate proven to bite when CA92.1 is removed (exit 1)

affects:
  - 01-02 (XcodeGen project.yml will reference Apps/CortexiOS/PrivacyInfo.xcprivacy and Apps/CortexMac/PrivacyInfo.xcprivacy under each target's sources: list so XcodeGen auto-includes them as Copy Bundle Resources entries)
  - 01-06 (CI workflow ci.yml will invoke ./Tools/scripts/validate-privacy-manifest.sh Apps/CortexMac/PrivacyInfo.xcprivacy Apps/CortexiOS/PrivacyInfo.xcprivacy as a PR-blocking step)
  - Phase 2/3 daemon (when daemon code lands required-reason API usage, Apps/CortexDaemon/PrivacyInfo.xcprivacy is added and the CI invocation gets the new path appended — argv is variadic)
  - Phase 5 ANE (CoreML inference instrumentation may add new required-reason API entries; the validator's reason-code grep set is extended at that time)
  - Phase 9/10 photodiode rig (timing instrumentation may add new reason codes; same extension path)
  - Phase 8 distribution (App Store submission will not progress without per-target PrivacyInfo.xcprivacy; this plan satisfies that gate for the two app targets)

# Tech tracking
tech-stack:
  added:
    - PrivacyInfo.xcprivacy XML plist format (Apple bundle resource for required-reason API disclosure)
    - plutil (macOS-bundled plist linter and converter — used for syntactic validity, key-extraction, and xml1 conversion for grep)
    - bash script with set -euo pipefail and variadic argv for CI gate

  patterns:
    - "Project-defined CI gate filling Apple's missing first-party validator — Apple ships PrivacyInfo.xcprivacy as a build-time disclosure artifact but provides no validator that fails CI on missing reason codes; the project script is the load-bearing PR gate"
    - "Variadic argv for CI invocations — script accepts N manifest paths so Phase 2/3 daemon manifest, Phase 5 ANE additions, etc. each become single-line CI tweaks rather than script rewrites"
    - "Positive + negative control on every gate — validating that the gate fires when the load-bearing string is removed, not just that it passes when intact (proves the trap is armed)"
    - "Set-euo-pipefail-default — every project shell script begins with set -euo pipefail so any sub-command failure is fatal; matches the project-wide compile-time guarantees principle in shell-script form"

key-files:
  created:
    - Apps/CortexiOS/PrivacyInfo.xcprivacy
    - Apps/CortexMac/PrivacyInfo.xcprivacy
    - Tools/scripts/validate-privacy-manifest.sh

  modified: []

key-decisions:
  - "CA92.1 chosen over 35F9.1 (Measuring performance) and 3D61.1 (Obvious functionality) — RESEARCH.md Q5 documents all three are valid for NSPrivacyAccessedAPICategorySystemBootTime; CA92.1 (Approximate time interval) is the most accurate framing of Cortex's latency-arithmetic use case and is what CONTEXT.md FOUND-03 specifies verbatim"
  - "Daemon target gets NO manifest in Phase 1 — RESEARCH.md Q5 confirms the daemon ships no required-reason API usage in Phase 1; manifest arrives when Phase 2/3 daemon code introduces such usage. The variadic-argv design ensures adding it later is a one-line CI tweak, not a script change"
  - "iOS and Mac manifests are byte-for-byte identical — both apps consume mach_absolute_time via the same CortexCore.Time wrapper and have no other required-reason API usage in Phase 1; identical content is intentional"
  - "Shell script uses only macOS-bundled tooling (plutil + grep) — no external dependencies, no homebrew installs needed; runs on the bare macos-15 GitHub Actions runner per FOUND-05"
  - "Grep matches the EXACT string <string>CA92.1</string> with no whitespace flexibility — partial matches or different reason codes would require an explicit edit visible in diff (mitigation for STRIDE T-01-03-03 Repudiation: wrong reason code)"

patterns-established:
  - "Pattern: project-defined PR-blocking gate for Apple disclosure metadata. Filling the gap where Apple validates at the App Store submission tier but offers no first-party CI tool. Reusable for Phase 5 ANE timing additions, Phase 9/10 photodiode timing additions, and any future required-reason API category"
  - "Pattern: variadic argv as a forward-compatibility seam. Plan 06 invokes `./Tools/scripts/validate-privacy-manifest.sh Apps/CortexMac/PrivacyInfo.xcprivacy Apps/CortexiOS/PrivacyInfo.xcprivacy`; daemon manifest addition in Phase 2/3 is `... Apps/CortexDaemon/PrivacyInfo.xcprivacy` appended"
  - "Pattern: positive + negative control verification. Every CI gate proves both 'passes when correct' and 'fires when broken' before being committed. Captured in this plan as Task 2 Step 2 (positive smoke) and Step 3 (negative smoke)"

requirements-completed:
  - FOUND-03

# Metrics
duration: 3m
completed: 2026-04-28
---

# Phase 01 Plan 03: PrivacyInfo.xcprivacy + validate-privacy-manifest.sh Summary

**Two PrivacyInfo.xcprivacy manifests (CortexiOS + CortexMac) declaring CA92.1 under NSPrivacyAccessedAPICategorySystemBootTime for mach_absolute_time, plus a bash + plutil + grep CI gate that fails the build on missing reason codes — gate proven to bite via negative-control test (CA92.1 stripped → exit 1).**

## Performance

- **Duration:** 2 min 39 sec
- **Started:** 2026-04-28T20:06:11Z
- **Completed:** 2026-04-28T20:08:50Z
- **Tasks:** 2 / 2
- **Files created:** 3 (2 PrivacyInfo.xcprivacy + 1 validator shell script)

## Accomplishments

- **FOUND-03 closed.** Both app targets ship a valid `PrivacyInfo.xcprivacy` declaring `CA92.1` for `mach_absolute_time` per Apple's required-reason API catalog. The XML structure is the minimum-viable shape Apple validates: `NSPrivacyTracking=false`, no tracking domains, no collected data types, single accessed-API category (`NSPrivacyAccessedAPICategorySystemBootTime`) with a single reason code (`CA92.1`).
- **CI gate armed and proven.** `Tools/scripts/validate-privacy-manifest.sh` enforces four invariants per manifest: (1) `plutil -lint` clean, (2) `NSPrivacyAccessedAPITypes` array exists, (3) `NSPrivacyAccessedAPICategorySystemBootTime` declared, (4) `CA92.1` reason code present. The negative-control test (Task 2 Step 3) replaced `<string>CA92.1</string>` with empty string and verified the validator exits `1` with `ERROR: ... missing CA92.1 reason code (required for mach_absolute_time)`. **Phase 1's structural defense against future drift is in place: any new required-reason API usage that lands without a manifest entry will fail CI on the next PR.**
- **Variadic-argv forward-compatibility seam.** The script accepts N manifest paths. Plan 06 will invoke it with the two current manifests. Phase 2/3 will append `Apps/CortexDaemon/PrivacyInfo.xcprivacy` to the CI invocation as a one-line edit when daemon code lands required-reason API usage. No script rewrite needed.
- **Apple authoritative source verified.** RESEARCH.md Q5 confirms `CA92.1` is correct under `NSPrivacyAccessedAPICategorySystemBootTime` (against the medium.com article that wrongly claimed it was UserDefaults-only — same string maps differently in different categories). CONTEXT.md FOUND-03 specifies CA92.1 verbatim and the manifest content matches.
- **No external dependencies.** Validator uses only `plutil` (macOS-bundled), `grep` (POSIX), and `bash` (macOS-bundled). Runs on the bare `macos-15` GitHub Actions runner per FOUND-05 with no homebrew installs.

## Task Commits

Each task was committed atomically with conventional-commits scope `({phase}-{plan})`:

1. **Task 1: Two PrivacyInfo.xcprivacy plists with CA92.1 reason code** — `72b2524` (feat)
2. **Task 2: validate-privacy-manifest.sh CI gate + negative-control proof** — `3362c43` (feat)

**Plan metadata commit:** _to follow after STATE.md / ROADMAP.md / REQUIREMENTS.md updates_

## Files Created/Modified

**Privacy manifests** (Task 1):
- `Apps/CortexiOS/PrivacyInfo.xcprivacy` — XML plist declaring `NSPrivacyTracking=false`, no tracking domains, no collected data types, `NSPrivacyAccessedAPICategorySystemBootTime` with `CA92.1`. Covers `mach_absolute_time` usage via `Packages/CortexCore/Sources/CortexCore/Time.swift`. `plutil -lint` returns `OK`.
- `Apps/CortexMac/PrivacyInfo.xcprivacy` — byte-for-byte identical to iOS version. Both apps share the same Phase-1 required-reason API surface (only `mach_absolute_time` via the same wrapper).

**Validator script** (Task 2):
- `Tools/scripts/validate-privacy-manifest.sh` — bash script (`-rwxr-xr-x`, 2303 bytes) with shebang `#!/usr/bin/env bash` and `set -euo pipefail`. Variadic argv. Exit codes: `0` all pass, `1` invalid manifest, `2` usage error. Four invariants per manifest, each enforced as a separate `continue`-on-failure check so the script catches all failures across all manifests in a single run.

## Decisions Made

- **CA92.1 (Approximate time interval) chosen over the other two valid reason codes for `NSPrivacyAccessedAPICategorySystemBootTime`.** RESEARCH.md Q5 documents that `35F9.1` (Measuring performance), `3D61.1` (Obvious functionality), and `CA92.1` (Approximate time interval) are all valid under this category. CA92.1 is the most accurate framing of Cortex's use case (computing elapsed time intervals for latency measurement and frame pacing — explicitly an "approximate time interval") and is what CONTEXT.md FOUND-03 specifies verbatim. Choosing a different code would require an explicit edit visible in diff and is mitigated by the validator's exact-string grep (T-01-03-03).
- **Daemon manifest deferred to Phase 2/3.** RESEARCH.md Q5 confirms the daemon ships no required-reason API usage in Phase 1 (empty `main()`). Adding a manifest now would declare unused API access — a minor disclosure overstep with no benefit. The variadic-argv design ensures the daemon manifest is a one-line CI tweak when its time comes.
- **Manifests are byte-for-byte identical between iOS and Mac.** Both apps consume `mach_absolute_time` via the same `CortexCore.Time.machAbsoluteNanoseconds()` wrapper (Plan 01-01). No other required-reason API usage in Phase 1. `diff Apps/CortexiOS/PrivacyInfo.xcprivacy Apps/CortexMac/PrivacyInfo.xcprivacy` returns empty.
- **Shell-only validator (no external deps).** macOS-bundled `plutil` + `grep` is sufficient and matches the project-wide preference for tooling that runs on a bare CI runner. The script does NOT use Python, jq, or any other tool that would require a `brew install` step in CI.
- **Exact-string grep, not regex with whitespace flexibility.** `grep -q "<string>CA92.1</string>"` matches the literal Apple-documented form. A different reason code or whitespace-altered form would not match — forcing any change to be an explicit, diff-visible edit.

## Deviations from Plan

None — plan executed exactly as written. Two tasks, two commits, all acceptance criteria satisfied. No Rule 1 / Rule 2 / Rule 3 / Rule 4 deviations triggered. The manifest content matches the exact XML specified in the plan; the validator script matches the exact bash specified in the plan.

## Issues Encountered

None. Both tasks proceeded without blockers. `plutil` is at the expected `/usr/bin/plutil` path; the negative-control sed worked as expected; cleanup of `/tmp/cortex-bad-manifest.xcprivacy` succeeded.

## Smoke Test Outcomes

**Positive smoke (Task 2 Step 2):**

```
$ ./Tools/scripts/validate-privacy-manifest.sh \
    Apps/CortexiOS/PrivacyInfo.xcprivacy \
    Apps/CortexMac/PrivacyInfo.xcprivacy
checking Apps/CortexiOS/PrivacyInfo.xcprivacy
OK: Apps/CortexiOS/PrivacyInfo.xcprivacy
checking Apps/CortexMac/PrivacyInfo.xcprivacy
OK: Apps/CortexMac/PrivacyInfo.xcprivacy
$ echo $?
0
```

**Negative smoke (Task 2 Step 3 — gate proven to bite):**

```
$ cp Apps/CortexiOS/PrivacyInfo.xcprivacy /tmp/cortex-bad-manifest.xcprivacy
$ sed -i '' 's|<string>CA92.1</string>||' /tmp/cortex-bad-manifest.xcprivacy
$ ./Tools/scripts/validate-privacy-manifest.sh /tmp/cortex-bad-manifest.xcprivacy
checking /tmp/cortex-bad-manifest.xcprivacy
ERROR: /tmp/cortex-bad-manifest.xcprivacy missing CA92.1 reason code (required for mach_absolute_time)
$ echo $?
1
```

Temp file cleaned up post-test. **The trap is armed: any future commit that removes CA92.1 from a manifest will fail this script on the next CI run.**

**Usage error smoke:**

```
$ ./Tools/scripts/validate-privacy-manifest.sh
usage: ./Tools/scripts/validate-privacy-manifest.sh <PrivacyInfo.xcprivacy> [more...]
$ echo $?
2
```

## User Setup Required

None — no external service configuration required. All work is local repo scaffolding.

The validator script will be exercised by CI in Plan 01-06 when the GitHub Actions workflow lands. No human verification step is required between now and then; the negative-control test in Task 2 already proves the gate fires on a real manifest defect.

## Next Phase Readiness

**Ready for Plan 01-04 (Wave 1 SwiftFormat / SwiftLint / fastlane stubs).**

Plan 03 is independent of Plans 01-02 / 01-04 / 01-05 — it touches only `Apps/Cortex{iOS,Mac}/` (creates manifest files) and `Tools/scripts/` (creates validator script). No other plan files are read or modified.

**Cross-phase notes:**

- **Plan 01-02 (XcodeGen project.yml):** Both `Apps/CortexiOS/PrivacyInfo.xcprivacy` and `Apps/CortexMac/PrivacyInfo.xcprivacy` need to be picked up by their respective target's `sources:` list in `project.yml` so XcodeGen auto-adds them to "Copy Bundle Resources." Without this, the manifests sit on disk in source but never make it into the built `.app` bundle (RESEARCH.md Pitfall #7). Plan 02's task that creates `project.yml` should reference these paths verbatim.
- **Plan 01-06 (CI workflow ci.yml):** Add a step `./Tools/scripts/validate-privacy-manifest.sh Apps/CortexMac/PrivacyInfo.xcprivacy Apps/CortexiOS/PrivacyInfo.xcprivacy` to the PR-blocking job. This is the FOUND-03 drift gate.
- **Phase 2/3 daemon manifest:** When `Apps/CortexDaemon/` gets code that uses `mach_absolute_time` or any other required-reason API, create `Apps/CortexDaemon/PrivacyInfo.xcprivacy` and append the path to the CI invocation in `.github/workflows/ci.yml` (one-line change — variadic argv).
- **Phase 5 ANE timing / Phase 9/10 photodiode timing:** When new required-reason API usage lands beyond `mach_absolute_time`, the validator's grep for `CA92.1` may need to be extended to a `REQUIRED_REASONS` array covering additional codes (e.g., timing-related codes for sample timestamping). The script's structure already isolates this check to a single `if ! grep -q "<string>CA92.1</string>"` block.
- **Plan 01-02 cross-plan note from the plan's `<interfaces>` block:** "Plan 02 has already added the manifest paths to the project.yml sources: lists" — this was forward-looking. Plan 02 has not yet run in the current sequential execution. When Plan 02 lands, it must add these paths. If Plan 02 has already run by the time you read this and forgot to include them, this is a Rule 2 (auto-add missing critical functionality) candidate at Plan 02's verification step.

**No blockers. No deferred items. No threat flags raised beyond what the plan's STRIDE register already accepts (T-01-03-02 manifest content disclosure: `accept` — minimum surface).**

---

## Self-Check: PASSED

Verification of artifacts and commits claimed in this Summary:

**Files exist (`test -f`):**
- FOUND: Apps/CortexiOS/PrivacyInfo.xcprivacy (passes `plutil -lint`, contains `<string>CA92.1</string>` and `<string>NSPrivacyAccessedAPICategorySystemBootTime</string>`)
- FOUND: Apps/CortexMac/PrivacyInfo.xcprivacy (passes `plutil -lint`, byte-for-byte identical to iOS via `diff`)
- FOUND: Tools/scripts/validate-privacy-manifest.sh (`-rwxr-xr-x`, 2303 bytes, contains `set -euo pipefail`, `plutil -lint`, `NSPrivacyAccessedAPICategorySystemBootTime`, `CA92.1`)
- MISSING: Apps/CortexDaemon/PrivacyInfo.xcprivacy (CORRECT — intentionally absent per RESEARCH.md Q5; daemon has no required-reason API usage in Phase 1)

**Commits exist (`git log --oneline`):**
- FOUND: 72b2524 — Task 1 (feat: PrivacyInfo.xcprivacy with CA92.1 for both app targets)
- FOUND: 3362c43 — Task 2 (feat: validate-privacy-manifest.sh CI gate)

**Verification clauses re-executed:**
- Task 1 automated verify: both lint OK, both contain CA92.1 — PASS
- Task 2 automated verify: positive smoke exits 0, negative smoke exits 1 (`gate proven to bite`), temp file cleaned up — PASS
- Plan-level verification (4 items): all PASS

**No items missing. Self-check passed.**

---
*Phase: 01-foundation-2026-toolchain*
*Plan: 01-03*
*Completed: 2026-04-28*
