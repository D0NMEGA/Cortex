---
status: partial
phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring
source: [03-VERIFICATION.md]
started: 2026-06-21T00:39:07Z
updated: 2026-06-21T00:39:07Z
---

## Current Test

[awaiting human testing on M4-class Apple Silicon]

## Tests

### 1. Instruments System Trace — SC#1 behavioural proof
expected: Run `CortexAcquisition.run(ring:frames:50_000_000)` driving the pthread acquisition worker on M4-class Apple Silicon (M4 / M4 Pro / M5 / M5 Pro). Capture Instruments → System Trace. The worker thread shows a `QOS_CLASS_USER_INTERACTIVE` band with ZERO `swift_task_*` / libdispatch frames in its call tree (proving the hot path runs under audio-callback rules with no Swift cooperative-runtime activity under load). Full step-by-step runbook: `instruments-evidence.md`.
result: [pending]
why_human: Instruments System Trace is a GUI profiler on a live process and requires real M4-class Apple Silicon — it cannot run in CI. The always-on CI proxy (`hotpath-policy.sh`, SC#2) is green; the `.trace` capture is the per-milestone hardware-evidence step following the D-18 split already applied in Phase 1 (SC#2) and Phase 2 (SC#1).

## Summary

total: 1
passed: 0
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
