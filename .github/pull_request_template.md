## What

Brief description of what this PR does.

## Why

Link to phase / requirement IDs (e.g., FOUND-02, IPC-04) and rationale. Reference the
relevant ADR(s) if a new architectural decision was made.

Phase: <!-- e.g., Phase 1 -- Foundation & 2026 Toolchain -->
Plan(s): <!-- e.g., 01-01-PLAN, 01-02-PLAN -->
Requirements addressed: <!-- e.g., FOUND-01, FOUND-04 -->

## Verification

- [ ] CI green (build, lint, format, package resolve, privacy manifest, hot-path policy)
- [ ] Local manual checks performed (if applicable):
  - [ ] Mac app + daemon `shm_open` test (Phase 1 SC#2)
  - [ ] `_Static_assert` negative test (verify the trap fires)
  - [ ] (Other phase-specific checks listed here)
- [ ] No regression to architectural commitments:
  - [ ] No `_ANEClient` references
  - [ ] No CocoaPods (`Podfile`, `Pods/`)
  - [ ] No `dispatch_async`, `pthread_mutex`, `import Foundation`, or `import ObjectiveC` in `Packages/CortexCore/Sources/` or `Packages/CortexIPC/Sources/`
  - [ ] Hot-path policy script (`Tools/scripts/hotpath-policy.sh`) passes
  - [ ] Privacy manifest validator (`Tools/scripts/validate-privacy-manifest.sh`) passes
  - [ ] No Mac Catalyst regression (CortexMac scheme builds; SUPPORTS_MACCATALYST=NO preserved)
- [ ] Compile-time guarantees preserved (no replacement of `_Static_assert` with runtime checks)

## Open questions / follow-ups

<!-- list any open items; "(none)" is a valid value -->
