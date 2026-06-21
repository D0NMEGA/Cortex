---
quick_id: 260621-iyg
slug: set-cortexmac-scheme-run-executable-to-c
date: 2026-06-21
status: complete
commit: eab61b4
---

# Quick Task 260621-iyg — Summary

## What was done

Added one line to `project.yml` under `schemes.CortexMac.run`:

```yaml
    run:
      config: Debug
      executable: CortexMac   # launch the .app, not the daemon
```

Then `xcodegen generate` regenerated the project in the main working tree.

## Verification

| Check | Result |
|-------|--------|
| `CortexMac.xcscheme` `<LaunchAction>` `BuildableName` | `CortexMac.app` ✓ (was `CortexDaemon`) |
| `<LaunchAction>` `BlueprintName` | `CortexMac` ✓ |
| `grep -c 57YW6M29S7 project.yml` | 3 ✓ (team survived regen) |
| `DEVELOPMENT_TEAM = 57YW6M29S7` in pbxproj | 6 ✓ |
| `milestone:` in STATE.md | `v1.0` ✓ (untouched) |

## Notes

- `CortexDaemon` remains in the scheme's `build.targets`, so it still builds as a
  peer artifact when the CortexMac scheme builds (Critical Finding #4 intact) — it
  just no longer *launches*.
- No signed CLI build attempted (free Personal team `57YW6M29S7` is GUI-only).
- Running the CortexMac scheme in Xcode now opens the `Cortex.app` window
  (a Phase-1 status view). The daemon's standalone IPC-handshake exit-70 is
  unrelated to the app window and is separate Phase-2+ work.

**Commit:** `eab61b4` — `project.yml` only (1 line + comment).
