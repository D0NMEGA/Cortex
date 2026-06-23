---
phase: 08-apple-bci-hid-integration-distribution-v0-ship
plan: 06
subsystem: distribution-docs
tags: [readme, adr, credibility, dist-04, perf-02, honesty-ethos, ci-gate, no-leak, dual-latency-claim, webgrid-bps, wire-and-gate]

# Dependency graph
requires:
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship (08-03)
    provides: GlassToGlassTimer.methodologyLabel (verbatim D-07 label) + CortexDemoBench software-timed p99 ≈ 8.3ms (M5 corroborating)
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship (08-05)
    provides: webgrid_bps.json (refit 1.953 BPS, 6.55 gap to 8.5) + 08-bps-evidence.md (synthetic-replay honesty disclosure)
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship (08-04)
    provides: notarize-policy.sh / match-policy.sh single-file structural-gate idiom the readme-policy.sh gate mirrors
provides:
  - README.md — the credibility-grade v0 README (5 architectural-commitments + 12-row rejected-alternatives tables + dual v0/v1 latency claim + 6 honest-gate disclosures + run-the-demo)
  - docs/adr/0002-v0-ship-and-bci-hid-integration.md — ADR-0002 recording the wire-and-gate doctrine (D-01/D-04/D-07/D-11/D-12), mirroring ADR-0001 format
  - Tools/scripts/readme-policy.sh — structural gate (required disclosures present + no secret/PII leak) with a biting --self-test
  - ci.yml "README credibility + no-leak gate (DIST-04, D-06)" step
affects: [phase-08-verification, phase-08-validation, milestone-v0-ship, 09-photodiode-rig, 10-v1-launch]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Credibility-grade README pattern: every performance number stated WITH its device + its gate (no naked claim)"
    - "Dual latency claim: software-timed v0 (measured, M5 corroborating, verbatim methodology label) stated NEXT TO the photodiode v1 SPEC TARGET (24.7ms, pending — NOT claimed measured)"
    - "README structural gate (single-file scope override + require/forbid helpers + SELF re-invocation + --self-test), mirroring notarize-policy.sh / match-policy.sh"
    - "Forbidden secret/PII literals assembled at runtime (printf fragments) so the gate file carries no bare credential token"
    - "ADR-0002 follows the ADR-0001 format precedent (## Context / ## Decision / ## Consequences / ## Alternatives considered; sequential numbering, no decimals)"

key-files:
  created:
    - docs/adr/0002-v0-ship-and-bci-hid-integration.md
    - Tools/scripts/readme-policy.sh
  modified:
    - README.md
    - docs/adr/README.md
    - .github/workflows/ci.yml

key-decisions:
  - "The README states a DUAL latency claim: the software-timed M5-Pro p99 ≈ 8.3ms (corroborating, with the verbatim 'software-timed pipeline latency — excludes the compositor's 1-3 frames of scanout…' label) NEXT TO the canonical '24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)' framed as the v1 SPEC TARGET / pending-capture — NOT as already-measured (D-07)"
  - "Cited the REAL committed numbers only: software-timed p50≈4.2ms/p99≈8.3ms from 08-03's glass_to_glass.json; Webgrid refit 1.953 BPS + the 6.55 gap to 8.5 from 08-05's webgrid_bps.json/08-bps-evidence.md. No invented numbers"
  - "All 3 Manual-Only gates disclosed as ready-but-gated, not done: live TestFlight (free-team signs Mac GUI only), iPad-M4 canonical latency (HUMAN-UAT), on-device BCI-HID registration (entitlement request-gated)"
  - "readme-policy.sh forbids a PEM private-key header, an inline MATCH_PASSWORD=, an email/PII, and an ASC issuer-UUID; the already-public placeholder team ID 57YW6M29S7 is NOT a leak (not a key/email/UUID/password) so the team is referred to via it + 'free Personal team'"
  - "ci.yml: ADDED the README gate step after the match-policy step (Wave-6 owner); existing Plans 01/02/03/04/05 jobs untouched (47 steps parse clean)"

patterns-established:
  - "Honesty-as-product README: the dual claim + the gate-disclosure table make the artifact credible to the Bliss Chapman / Nir Even-Chen audience precisely because it discloses, not hides, every gate"
  - "Structural doc gate: a disclosure that matters is grep-asserted with a biting --self-test, extending the ADR-0001 'compile-time guarantees beat runtime ones' discipline to the documentation surface"

requirements-completed: [DIST-04, PERF-02]

# Metrics
duration: 17min
completed: 2026-06-23
---

# Phase 8 Plan 06: Credibility-Grade v0 README + ADR-0002 Summary

**Published the v0 credibility artifact: a README with the 5 architectural-commitments table, the 12-row rejected-alternatives table, the DUAL latency claim (software-timed M5-Pro p99 ≈ 8.3ms with the verbatim methodology label, stated NEXT TO the canonical 24.7 ± 1.3 ms photodiode number framed as the v1 SPEC TARGET — NOT claimed measured), the measured Webgrid 1.953 BPS with the honest 6.55 gap to 8.5, and the load-bearing honest-gates section disclosing all 6 gates; plus ADR-0002 recording the wire-and-gate doctrine and a `readme-policy.sh` structural gate (required disclosures present + no secret/PII leak) with a biting `--self-test`, wired into CI without overwriting any existing job.**

## Performance

- **Duration:** ~17 min
- **Tasks:** 2
- **Files modified/created:** 5 (2 created, 3 modified)

## Accomplishments

- **DIST-04 (README):** Rewrote `README.md` (57-line Phase-1 minimal → 233-line v0 credibility artifact) with: the Core Value + instrumentation-honesty thesis; the **architectural-commitments table** (CoreML-on-ANE-not-MLX / pthread-not-Task / kqueue-not-Network.framework / CAMetalDisplayLink-zero-copy / AES-GCM-not-ChaCha20, each with rationale + the validated number — 226/226 ANE-eligible, p99=208ns IPC, GPU p99=0.162ms, etc.); the **rejected-alternatives table** (all 12 entries: MLX, Network.framework, Swift Task, ChaCha20, _ANEClient, CocoaPods, hardware PTP, NDT2, (B,S,C), h=4, CADisplayLink, 6×6, altool); the **dual latency claim**; the **Webgrid BPS** section; the **honest-gates** disclosure table; a **run-the-demo** section pointing at the CortexMac GUI closed loop (MTL_HUD); and the preserved build/prerequisites (updated for v0).
- **PERF-02 (gap to 8.5):** The README cites the real measured **ReFIT 1.953 Webgrid BPS** (raw 1.292, Kalman-only 1.183) from `webgrid_bps.json`, with the formula `B = max(0, log2(N)*(Sc-Si)/t)` (N=900), the explicit **6.55-BPS gap to the 8.5 peak**, the synthetic-replay caveat, and the Si=0 upper-bound disclosure — all cross-linked to `08-bps-evidence.md`.
- **D-07 (dual claim, honestly):** The software-timed number (p50≈4.2ms / **p99≈8.3ms**, M5-Pro corroborating) carries the **verbatim** `software-timed pipeline latency — excludes the compositor's 1-3 frames of scanout, which is exactly the delta the v1 photodiode rig (Phases 9-10) quantifies` label, stated directly next to the canonical **24.7 ± 1.3 ms (p50, σ=0.8 ms, n=10k, photodiode-instrumented)** number, which is explicitly framed as the **v1 SPEC TARGET / pending capture — NOT measured today**.
- **Honesty ethos (all 6 gates disclosed):** free-team signing (Mac GUI only; TestFlight gated), ANE-eligible-vs-placed (226/226 eligible, CPU-scheduled at scale), iPad-M4 deferral (M5 corroborating, iPad HUMAN-UAT), BCI-HID entitlement request-gating (declared-but-inert), software-vs-photodiode boundary (v0 excludes the compositor), synthetic-vs-live-human BPS (synthetic Indy replay, not a live retrain). The 3 Manual-Only gates are disclosed as ready-but-gated, not done.
- **ADR-0002:** `docs/adr/0002-v0-ship-and-bci-hid-integration.md` records the wire-and-gate doctrine (D-01), declared-and-gated BCI HID (D-04), software-vs-photodiode boundary (D-07), Webgrid-BPS-not-Fitts (D-11), and synthetic-vs-live framing (D-12), mirroring ADR-0001's 4-section format; the ADR index (`docs/adr/README.md`) lists it.
- **readme-policy.sh + CI:** A structural gate mirroring `notarize-policy.sh`/`match-policy.sh` — 13 REQUIRED-PRESENT checks (rejected tokens + the dual-claim phrases + the 5 gate-disclosure phrases + the BPS formula/8.5) and 4 FORBIDDEN-ABSENT no-leak checks (PEM private-key header, inline `MATCH_PASSWORD=`, email/PII, ASC issuer-UUID). Real README → exit 0; `--self-test` → exit 0 with all 9 negative controls biting. Wired into `ci.yml` as a new step; existing jobs untouched (47 steps parse clean).

## Task Commits

Each task was committed atomically:

1. **Task 1: README + ADR-0002** — `9c61b64` (docs) — README.md rewrite + docs/adr/0002-v0-ship-and-bci-hid-integration.md + docs/adr/README.md index entry.
2. **Task 2: readme-policy.sh + CI wiring** — `13c7ae1` (chore) — Tools/scripts/readme-policy.sh (mode 100755) + the ci.yml "README credibility + no-leak gate" step.

## Files Created/Modified

- `README.md` — the v0 credibility artifact (commitments + rejected-alternatives tables, dual v0/v1 latency claim, Webgrid BPS + gap, honest-gates table, run-the-demo, updated build/prereqs).
- `docs/adr/0002-v0-ship-and-bci-hid-integration.md` — ADR-0002 (wire-and-gate doctrine; D-01/D-04/D-07/D-11/D-12), ADR-0001 format.
- `docs/adr/README.md` — added ADR-0002 to the index.
- `Tools/scripts/readme-policy.sh` — required-disclosure + no-leak structural gate with a biting `--self-test` (runtime-assembled forbidden literals).
- `.github/workflows/ci.yml` — new "README credibility + no-leak gate (DIST-04, D-06)" step (gate + `--self-test`), placed after the match-policy step; no existing job overwritten.

## Decisions Made

- **Dual claim, stated honestly** — the software-timed M5 number is the v0 claim (labeled, corroborating); the canonical 24.7ms photodiode number is the v1 SPEC TARGET, pending, never presented as measured. This is the load-bearing credibility distinction (D-07).
- **Real numbers only** — every cited figure traces to a committed artifact (`glass_to_glass.json` for the software-timed p50/p99; `webgrid_bps.json` + `08-bps-evidence.md` for 1.953 BPS / the 6.55 gap). No invented numbers.
- **No-leak gate forbids genuine credentials/PII only** — the already-public placeholder team ID `57YW6M29S7` (committed in `project.yml`) is not a key/email/UUID/`MATCH_PASSWORD`, so it does not match any forbidden pattern; the team is referred to via it + "free Personal team". Forbidden literals are assembled at runtime so the gate file itself carries no bare credential token (the `notarize-policy.sh`/`match-policy.sh` discipline).
- **CI step ADDED, not overwritten** — placed after the Wave-6 match-policy step; the Plans 01/02/03/04/05 jobs are untouched (verified: 47 steps parse, all sampled prior gate steps present).

## Deviations from Plan

None — the plan executed exactly as written. (One in-flight correction was made before any commit: the initial draft of `readme-policy.sh` passed a stray `--` as the regex argument to `forbid_regex_in_file`; this was caught and fixed before the script's first run, so it never reached a commit and is not a plan deviation.)

## Authentication Gates

None — this plan is static documentation + a grep gate. No CLI login, API key, or external service was required.

## Known Stubs

None — the README cites only real committed numbers; no placeholder/empty values flow anywhere. The "pending v1 photodiode capture" is not a stub — it is the honestly-disclosed v1 SPEC TARGET (the never-auto-approve Gate 2 of Plan 07 / Phases 9-10), explicitly framed as not-yet-measured.

## Issues Encountered

- None blocking. Confirmed no git pre-commit hooks / `.pre-commit-config` / lefthook / husky exist in the repo, so normal `git commit` (no `--no-verify`) is the correct sequential-executor path.

## Self-Check: PASSED

All claimed files exist on disk — `README.md`, `docs/adr/0002-v0-ship-and-bci-hid-integration.md`, `docs/adr/README.md`, `Tools/scripts/readme-policy.sh` (FOUND ×4). Both task commit hashes exist in git history — `9c61b64`, `13c7ae1` (FOUND ×2). Final verification sweep green: `readme-policy.sh` → exit 0 on the real README (13 required + 4 forbidden checks pass); `readme-policy.sh --self-test` → exit 0 (clean README passes; 5 disclosure-strip + 4 secret-injection controls all bite); README contains `software-timed`/`rejected`/`24.7`; `grep -n readme-policy ci.yml` matches the gate run + `--self-test` (lines 288-289); all 10 sampled prior CI gate steps present (no job overwritten); STATE.md / ROADMAP.md NOT touched by either of my commits (orchestrator-owned).

---
*Phase: 08-apple-bci-hid-integration-distribution-v0-ship*
*Completed: 2026-06-23*
