---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Plan 01-01 complete; ready for Plan 01-02
last_updated: "2026-04-28T19:59:37Z"
last_activity: 2026-04-28 -- Plan 01-01 (CortexCore + 3 stubs + .gitignore + spec move) complete
progress:
  total_phases: 10
  completed_phases: 0
  total_plans: 7
  completed_plans: 1
  percent: 1
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-28)

**Core value:** Sub-25ms photodiode-instrumented glass-to-glass latency on iPad Pro M4 — the defensible "24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)" claim is the single highest-leverage credibility artefact in the project.
**Current focus:** Phase 01 — foundation-2026-toolchain

## Current Position

Phase: 01 (foundation-2026-toolchain) — EXECUTING
Plan: 2 of 7 (next)
Status: Plan 01-01 complete; ready for Plan 01-02 (XcodeGen project.yml + 3 Xcode targets + entitlements)
Last activity: 2026-04-28 -- Plan 01-01 complete (CortexCore + 3 stubs + .gitignore + spec move)

Progress: [█░░░░░░░░░] 14%

## Performance Metrics

**Velocity:**

- Total plans completed: 1
- Average duration: 5m
- Total execution time: ~5 minutes

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 1 | 5m | 5m |

**Recent Trend:**

- Last 5 plans: 01-01 (5m)
- Trend: — (only one data point)

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

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-04-28T19:59:37Z
Stopped at: Plan 01-01 complete; ready for Plan 01-02 (XcodeGen project.yml + 3 Xcode targets + entitlements)
Resume file: .planning/phases/01-foundation-2026-toolchain/01-02-PLAN.md
