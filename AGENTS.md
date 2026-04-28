<!-- GSD:project-start source:PROJECT.md -->
## Project

**Cortex.app**

Cortex.app is a Neuralink-quality iPad/Mac BCI input pipeline clone — a credibility-grade demonstration that a single engineer can build a sub-25ms glass-to-glass neural cursor decoder on Apple Silicon. The decoder (NDT1, ~1.3M params) runs in <2ms on the M4 Neural Engine via CoreML, drives a 120Hz beam-raced Metal renderer, and integrates with Apple's May 2025 BCI HID protocol so the same artifact works as both a tech demo and a deployable assistive input device.

**Core Value:** **Glass-to-glass latency under 25ms, photodiode-instrumented and reproducible.** Every architectural choice serves this — the spec's defining claim is "Glass-to-glass latency 24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)." Without that defensible number, this is a tech demo. With it, it's a credibility artifact suitable for review by Bliss Chapman / Nir Even-Chen.

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

Conventions not yet established. Will populate as patterns emerge during development.
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
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-agent-profile` -- do not edit manually.
<!-- GSD:profile-end -->
