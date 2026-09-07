<!-- GSD:project-start source:PROJECT.md -->
## Project

**Cortex.app**

Cortex.app is a Neuralink-quality iPad/Mac BCI input pipeline clone — a credibility-grade demonstration that a single engineer can build a sub-25ms glass-to-glass neural cursor decoder on Apple Silicon. The decoder (NDT1, ~1.3M params) runs in <2ms on the M4 Neural Engine via CoreML, drives a 120Hz beam-raced Metal renderer, and integrates with Apple's May 2025 BCI HID protocol so the same artifact works as both a tech demo and a deployable assistive input device.

**Core Value:** **Real primate M1 spikes decoded end to end, reproducibly, under a software-timed sub-25 ms budget.** NDT1 decodes the O'Doherty/Makin Indy M1 dataset (Zenodo 3854034, four checksum-pinned sessions) through the CoreML -> ReFIT-Kalman -> 120 Hz renderer -> BCI HID path. *Re-pointed 2026-08-28: the photodiode-instrumented "24.7 +/- 1.3 ms" figure is a RETIRED SPEC TARGET, never a measurement, preserved as Future work (LAT-01..LAT-08). It may not be cited as achieved.*

### Constraints

- **Tech stack**: Apple Silicon (M4) only — `FEAT_AES`, ANE, `CAMetalDisplayLink`, ProMotion all required. No x86 fallback.
- **Tech stack**: Xcode 26 + Swift 6.2 + macOS 26 Tahoe / iPadOS 26 — all 2026 baseline; older toolchains lack required APIs.
- **Performance**: Decoder inference <2ms p99 — non-negotiable for sub-25ms glass-to-glass.
- **Performance**: Renderer GPU time ≤0.4ms on M4 — leaves headroom for compositor.
- **Performance**: IPC round-trip sub-µs — disqualifies Network.framework (50-200µs).
- **Threading**: Hot path is audio-callback regime — no `dispatch_async`, no Obj-C runtime, no locks, no ARC retain/release. Pthread + USER_INTERACTIVE only.
- **Distribution**: Must ship through App Store path (no `_ANEClient`, no deprecated entitlements). Privacy manifest required. Notarized.
- **Timeline**: 6-7 week sprint; v0 by week 5, v1 by week 7.
- **Compatibility**: Single-user, on-device. No cloud, no multi-user, no real BCI hardware.
<!-- GSD:project-end -->

<!-- GSD:stack-start source:STACK.md -->
## Technology Stack

Technology stack not yet documented. Will populate after codebase mapping or first phase.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

**`Decoder/` requires the `dev` extra.** pytest and ruff are declared as an optional-dependency
extra, so a bare `uv run pytest` in a fresh worktree fails with a misleading
`No module named numpy`. Always sync first:

```bash
uv sync --project Decoder --extra dev
uv run --project Decoder pytest            # add -m slow for the evidence runs
```

`coremltools` is pinned at 9.0. The training/eval dataset lives in the gitignored `Decoder/data/`
and is materialized from the committed checksum manifest, never committed:

```bash
uv run --project Decoder python Decoder/scripts/download_indy.py
```

**Evidence discipline.** Any number the repo publishes is committed as a `*-evidence.md` artifact
with the machine, pinned wheel versions, seed, and a reproducible runbook, and is labeled with the
device and method that produced it (see `.planning/phases/04-*/04-training-evidence.md`). A number
measured on synthetic data is labeled synthetic; a number measured on a Mac is not presented as an
iPad-M4 number.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.agent/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## Workflow enforcement

Before using Edit, Write, or other file-changing tools, start work through a donny command so planning artifacts and execution context stay in sync. (The `gsd-*` suite was retired 2026-07-05; `donny-*` supersedes it one-for-one.)

Use these entry points:
- `/donny-quick` for small fixes, doc updates, and ad-hoc tasks
- `/donny-debug` for investigation and bug fixing
- `/donny-execute-phase` for planned phase work

Do not make direct repo edits outside a donny workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-agent-profile` -- do not edit manually.
<!-- GSD:profile-end -->
