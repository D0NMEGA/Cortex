---
quick_id: 260621-iyg
slug: set-cortexmac-scheme-run-executable-to-c
date: 2026-06-21
status: complete
---

# Quick Task 260621-iyg — CortexMac scheme launches the app, not the daemon

## Problem

Running the `CortexMac` scheme in Xcode launched **CortexDaemon** (a CLI tool that
exits 70 on its IPC handshake) instead of **CortexMac.app**, so no window appeared.

Root cause (Context7-confirmed against the XcodeGen ProjectSpec **Run Action**):
the `schemes.CortexMac` block builds two targets (`CortexMac` + `CortexDaemon`) with
no `executable` set, so XcodeGen defaulted the launch target to *the first runnable
build target* — `CortexDaemon` (alphabetically first).

## Task

| # | Action | Files | Verify | Done |
|---|--------|-------|--------|------|
| 1 | Add `executable: CortexMac` to `schemes.CortexMac.run` in project.yml; regenerate | `project.yml` | regenerated `CortexMac.xcscheme` `<LaunchAction>` shows `BuildableName = "CortexMac.app"` / `BlueprintName = "CortexMac"`; `grep -c 57YW6M29S7 project.yml` == 3 | Running the CortexMac scheme opens the app window; daemon still builds as a peer |

## Constraints honored

- Only `project.yml` changed (one `executable:` line + clarifying comment).
- `CortexDaemon` kept in the scheme's `build.targets` — still built as a peer
  artifact (Plan 01-02 Critical Finding #4 intent preserved).
- `DEVELOPMENT_TEAM` untouched (`57YW6M29S7`). No other scheme modified.
- Ran in the main working tree so the regenerated (gitignored) `Cortex.xcodeproj`
  lands in the real checkout.
