---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Plans 01-01 and 01-03 complete (out-of-order, Wave 1); ready for Plan 01-02 (XcodeGen project.yml + 3 Xcode targets + entitlements)
last_updated: "2026-04-28T20:10:59Z"
last_activity: 2026-04-28 -- Plan 01-03 (PrivacyInfo.xcprivacy + validate-privacy-manifest.sh) complete
progress:
  total_phases: 10
  completed_phases: 0
  total_plans: 7
  completed_plans: 2
  percent: 29
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-28)

**Core value:** Sub-25ms photodiode-instrumented glass-to-glass latency on iPad Pro M4 — the defensible "24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)" claim is the single highest-leverage credibility artefact in the project.
**Current focus:** Phase 01 — foundation-2026-toolchain

## Current Position

Phase: 01 (foundation-2026-toolchain) — EXECUTING
Plan: 2 of 7 (next — 01-02 XcodeGen project.yml; 01-03 already complete out-of-order via Wave 1)
Status: Ready to execute Plan 01-02
Last activity: 2026-04-28 -- Plan 01-03 (PrivacyInfo.xcprivacy + validate-privacy-manifest.sh) complete

Progress: [███░░░░░░░] 29%

## Performance Metrics

**Velocity:**

- Total plans completed: 2
- Average duration: 4m
- Total execution time: ~8 minutes

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 2 | 8m | 4m |

**Recent Trend:**

- Last 5 plans: 01-01 (5m), 01-03 (3m)
- Trend: ↓ duration (two data points; Plan 03 lighter scope — 2 tasks, 3 files)

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent architectural commitments shaping all phases:

- CoreML on ANE (not MLX) — only path meeting <2ms p99 budget
- pthread + `QOS_CLASS_USER_INTERACTIVE` (not Swift Task) — Swift cooperative scheduling cannot meet 1ms deadlines
- `kqueue`+`recvmsg` + POSIX shm in App Group container (not Network.framework) — sub-µs vs 50-200µs
- `CAMetalDisplayLink` (not `CADisplayLink`) — beam-raced 120Hz with bundled drawable/encode/present callback
- AES-GCM via CryptoKit (not ChaCha20-Poly1305) — Apple Silicon FEAT_AES makes AES-GCM faster
- NDT1 with h=1-2 heads (not h=4 miscitation) and BC1S `(B,C,1,S)` layout (not vanilla `(B,S,C)`)
- 30×30 webgrid (not 6×6) — modern Bliss Chapman / Neuralink reference

**Plan 01-01:**

- Manifest version stays at 6.2 verbatim per artifact contract; toolchain mismatch on local executor (Swift 6.0.3) is environmental — Plan 01-06 CI on macos-15 with Xcode 26.3 is the canonical execution environment for Swift-side smoke
- `.defaultIsolation(MainActor.self)` retained on all four packages per Approachable Concurrency (drop only if Xcode 26.3 rejects, per Assumption A9 — no evidence of rejection yet)
- `_Static_assert` diagnostic message includes the authoritative reference inline (cortex-spec.md §9 + the header path) so a silent regression is structurally impossible — proven via clang negative test (53 bytes → exit 1, expression evaluates to `'53 <= 32'`)
- Used `git mv` for cortex-spec.md → docs/cortex-spec.md so rename is recorded as single R operation (not D+A); `git log --follow` traces back to commit 0818df0

**Plan 01-03:**

- CA92.1 (Approximate time interval) chosen over 35F9.1 (Measuring performance) and 3D61.1 (Obvious functionality) for `NSPrivacyAccessedAPICategorySystemBootTime` — RESEARCH.md Q5 documents all three are valid; CA92.1 most accurately frames Cortex's latency-arithmetic use case and matches CONTEXT.md FOUND-03 verbatim
- Daemon target gets NO `PrivacyInfo.xcprivacy` in Phase 1 — daemon ships no required-reason API usage; manifest arrives in Phase 2/3 when daemon code lands. Variadic-argv design in the validator script makes adding the daemon manifest a one-line CI tweak
- iOS and Mac manifests are byte-for-byte identical (`diff` returns empty) — both apps consume `mach_absolute_time` via the same `CortexCore.Time.machAbsoluteNanoseconds()` wrapper and have no other required-reason API usage in Phase 1
- Validator script uses only macOS-bundled `plutil` + `grep` — no homebrew installs, no Python, no jq. Runs on bare `macos-15` GitHub Actions runner per FOUND-05
- Negative-control test executed: stripping `<string>CA92.1</string>` from a temp copy made the validator exit 1 with `ERROR: ... missing CA92.1 reason code (required for mach_absolute_time)`. The trap is armed and proven to bite — Phase 1 has structural defense against future drift the moment Plan 01-06 wires this into CI

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-04-28T20:08:50Z
Stopped at: Plans 01-01 and 01-03 complete (Wave 1 out-of-order); ready for Plan 01-02 (XcodeGen project.yml + 3 Xcode targets + entitlements)
Resume file: .planning/phases/01-foundation-2026-toolchain/01-02-PLAN.md
