# Milestones

## v1.0 Real-Data Decoding (Shipped: 2026-09-16)

**Phases completed:** 10 phases, 70 plans, 193 tasks
**Timeline:** 2026-04-28 to 2026-09-16 (141 days, 546 commits)
**Code:** 18,816 Swift / 17,690 Python / 4,679 shell / 1,197 Rust / 191 Metal
**Archive:** [v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md) | [v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md) | [v1.0-MILESTONE-AUDIT.md](milestones/v1.0-MILESTONE-AUDIT.md)

**Delivered:** A reproducible pipeline that decodes real primate M1 spikes end to end on Apple
Silicon, and an honest measurement that it does not yet acquire targets.

### Key accomplishments

- Real neural data replaced synthetic Poisson replay throughout. Four O'Doherty/Makin Indy M1
  sessions (Zenodo 3854034, 1.77 GB) are checksum-pinned byte for byte, and the integrity gate was
  proven to refuse a one-bit corruption, a 127-byte truncation, and an HTML error page while passing
  the pristine file. Every decoder number in the repo was re-derived on this data.
- NDT1 (1,292,544 params, 6 layers, BC1S) trains on real spikes and converts to a 4-bit palettized
  `.mlpackage` that is 239/239 ANE-eligible with zero CPU-only ops and 3.4134x smaller. The velocity
  readout, fit on real `finger_pos` movement, reaches pooled held-out R2 0.4238 over 56,943 bins,
  positive on all four sessions against their own train-split means.
- The transport and render layers hit their budgets with margin: shm round trip p99 208 ns
  (n=199,000), GPU frame time p99 0.162 ms against a 0.4 ms budget (60 s soak, 243,724 frames, 0
  dropped), and a measured 120.00 FPS sustained over 30 s on the real-session replay.
- A masked-objective defect that had inflated co-bps roughly tenfold was found and corrected rather
  than shipped. The encoder had been able to read the positions it was scored on, so co-bps 1.9116
  was measuring self-reconstruction. With the scored positions hidden, the honest number is far
  lower, and the phase published the full co-bps-versus-epoch curve instead of a single figure.
- Cross-session transfer was measured, not assumed. Leave-one-session-out rotation flips every
  within-session positive verdict: the model beats a per-channel mean firing rate on held-out data
  from sessions it trained on, and loses on every session it has never seen. 0.4238 is therefore an
  upper bound on a new recording day, not a description of one.
- Honesty is enforced mechanically, not by convention. Twelve `*-policy.sh` gates run every CI
  build, four of them with adversarial `--self-test` corpora proven to bite, including a repo-wide
  sweep that fails the build if a synthetic-derived number is presented as a real-data result.

### The headline result is negative

Phase 10 success criterion 2 required a 30x30 webgrid hit on the real-data closed loop. The measured
result is **0 hits out of 1,025 trials** on both target-blind arms.

This was adjudicated under pre-registered rule B. `10-PREREGISTRATION.md` section 15 committed the
disposition and its action in Wave 0, before any hit count existed, and rule 1 forbade relaxing
radius, dwell, or timeout to manufacture a hit. The capability is absent and is published as absent.
Publishing the negative result **is** the pre-registered action; there is no remediation to plan.

v1.0 demonstrates a reproducible real-data decoding pipeline and reports that it does not yet
acquire targets. The repo's headline says so.

### Known gaps

Carried into the next milestone. None blocks the shipped artifact; all are recorded, not waived.

**Deferred device and account gates (6 requirements, never auto-approved per D-17).** Each has a
SATISFIED structural verdict with its live half deferred because the measurement cannot be taken:

| Requirement | Outstanding | Blocked on |
|---|---|---|
| SYS-01, SYS-02 | Live on-device HID registration | Apple-granted `com.apple.developer.hid.virtual.device` |
| DIST-01, DIST-02, DIST-03 | Live notarize / match / TestFlight | Paid Apple Developer Program enrollment |
| PERF-04 | Canonical glass-to-glass p99 | An iPad Pro M4 |

Five further partials (THREAD-02, RENDER-02, RENDER-05, RD-06, RD-08) are checked `[x]` on their
verified half with the deferred capture named inline. Of all 11, exactly one needs no purchase and no
Apple approval: **Phase 3 SC#1's Instruments System Trace**, which `03-HUMAN-UAT.md:17` accepts on
M4 / M4 Pro / M5 / M5 Pro. It is the cheapest credibility item available next milestone.

**INT-01 (closed 2026-09-16, commit `1dcdab9`).** `CortexAcquisition`, the pthread hot path
THREAD-01..04/06 describe, has no production caller; the shipped decode loop is a `@MainActor` Timer
(`ReplayDriver.swift:158`), and Phase 6 mirrors the ring design in a separate Swift `VelocityRing`
per D-03. The divergence was decided and documented but never carried back into the requirement text
or the README. Resolved by amending both to read as artifact-level claims naming what the demo
actually runs, consistent with DEC-08's ANE-placement reframing and RD-08's published zero. The
stronger fix, wiring the daemon's produce path to the pthread it already links, remains open.

**INT-02 (open, minor).** The daemon's produce path runs on its ordinary calling thread, not a
`QOS_CLASS_USER_INTERACTIVE` pthread. Same disposition as INT-01.

**INT-03 (open, minor).** The GUI apps never build a `BCIInputPointerReport` from the real decoded
position; that path is exercised only by the CI-only `CortexSeamBSmoke` tool. Deliberate and
documented at `ScanInfoRoundTrip.swift:39-42`; noted inline on SYS-06.

**Tooling.** `donny-tools.cjs summary-extract` mis-parses `requirements-completed` frontmatter, so
`verify milestone-coverage` reports 0/75 satisfied against a manual 3-source count of 56 satisfied /
11 partial / 0 unsatisfied. Reproducible at `02-01-SUMMARY.md:60`. Until fixed, `verify gate` cannot
gate this repo.

**CI has not run on HEAD.** Last CI run was `3a5054e` (2026-09-08). All 12 policy gates, 235 Swift
tests, and 289 Python tests pass locally at the tagged commit.

### Note on v0

v0 "Software-Timed" (Phases 1-8, declared shipped 2026-06-23) was an internal checkpoint. It was
never archived through `milestone complete`, so its phases are included in this v1.0 archive rather
than carrying a separate `milestones/v0-*` record. Its own gates (live TestFlight, iPad-M4 canonical
latency, on-device HID registration) are the DIST and SYS rows above, still deferred.
