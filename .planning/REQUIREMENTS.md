# Requirements: Cortex.app, milestone v1.1

**Defined:** 2026-09-17
**Milestone:** v1.1 Technical Narrative and Decode-Gap Analysis
**Hard deadline:** 2026-09-18 (onsite with Neuralink engineers)
**Core Value:** A real-neural-data decoder running end-to-end under 25 ms, reproducibly.

## What this milestone is

A compilation milestone plus one bounded measurement. It adds no product capability and touches no
shipped v1.0 code path. Its output is a document you can talk from and one number that did not
exist before.

The governing constraint is inherited, not new: `10-PREREGISTRATION.md` forbids relaxing radius,
dwell or timeout to convert a zero into a hit. NAR-04 measures the tolerance the decoder would
require and reports it. That is a measurement of the decoder, not a relaxation of the rule, and the
distinction has to survive into the published wording.

## v1.1 Requirements

### Decode-gap analysis (Phase 11)

- [ ] **GAP-01**: The decoded trajectory is scored through the same acceptance machinery that
  `webgrid_ceiling.py` already applies to the recorded hand, at the canonical radius 2.8614 mm and
  dwell 0.30 s, reproducing the published 0 of 1,025 from the committed artifacts rather than
  restating it
- [ ] **GAP-02**: Acceptance radius is swept for the decoded trajectory across at least the radii
  the recorded-hand table already covers (1.75, 2.32, 2.86, 3.50, 7.50, 15.00 mm) at both dwells
  (0.10 s, 0.30 s), producing a decoded counterpart to `10-ceiling.json`
- [ ] **GAP-03**: The decoder's **effective acceptance radius** is reported: the smallest radius at
  which the decoded trajectory scores a stated non-zero hit fraction, expressed in mm and as a
  multiple of the 2.8614 mm canonical radius and of the task's own 7.50 mm half-pitch
- [ ] **GAP-04**: The 0 of 1,025 is decomposed into a geometry term and a decode term, stated as
  two separate losses: 1,025 to 147 attributable to the acceptance rule alone (already established
  for the recorded hand), and 147 to 0 attributable to the decode
- [ ] **GAP-05**: Velocity variance shrinkage is quantified: the ratio of decoded to recorded speed
  distributions, checked against the shrinkage a held-out R2 of 0.4238 predicts, so undershoot is
  measured rather than asserted
- [ ] **GAP-06**: Angular error between decoded and recorded velocity is reported as a distribution,
  not a mean alone
- [ ] **GAP-07**: Findings are committed as `11-decode-gap-evidence.md` carrying machine, OS, pinned
  wheel versions, seed or an explicit statement of determinism, session id, source sha256, and a
  copy-pasteable runbook, matching the format of `10-ceiling-evidence.md`
- [ ] **GAP-08**: The open-loop disclosure is carried verbatim into every artifact this phase
  produces: open-loop replay of a recorded session, the subject was not in the loop. No sentence
  frames any number here as closed-loop control, and no number is framed as a bound on what a
  decoder could achieve

### Sequential technical walkthrough (Phase 12)

- [ ] **NAR-01**: A single document walks the pipeline in data-flow order with one section per
  stage: acquisition hot path, IPC transport, lock-free SPSC ring, decoder, ReFIT-Kalman, renderer,
  BCI HID surface, evidence and gate layer
- [ ] **NAR-02**: Every stage section states the decision made, the specific alternative rejected,
  and the quantitative reason for rejecting it, with the precise technical vocabulary rather than a
  paraphrase
- [ ] **NAR-03**: Every number cited carries the device and the method that produced it, and no
  Mac-measured number is presented as an iPad-M4 number. Numbers trace to their committed
  `*-evidence.md`
- [ ] **NAR-04**: Every stage section names the weakness a reviewer would find, before the reviewer
  does. The known-weak items are named explicitly and not softened: 0 of 1,025 target acquisition,
  leave-one-session-out negative on all four folds, ReFIT uplift not surviving real spikes, NDT1
  losing to a linear ridge baseline, INT-01 and INT-02 (the hot path has no production caller and
  the daemon produce path is not on a USER_INTERACTIVE pthread), INT-03, and the six device- and
  account-gated deferrals
- [ ] **NAR-05**: The walkthrough closes with the Phase 11 decode-gap result as its answer to the
  0 of 1,025 question
- [ ] **NAR-06**: The retired 24.7 ms photodiode figure appears only as a retired spec target. The
  document passes `readme-policy.sh` and `honesty-sweep.sh` context rules as though it were a
  published artifact, because it is one
- [ ] **NAR-07**: Committed to the repo as markdown. No artifact is published and no external
  service receives repo content

## Out of scope for v1.1

Explicitly excluded, with reasoning, so none of it is attempted the night before the onsite.

| Excluded | Reason |
|---|---|
| Manifold / population-dynamics analysis (PCA, jPCA, participation ratio) | A real gap against the Neuroengineer posting and a genuine candidate for v1.2, but it is new analysis with an open-ended scope and this milestone has one working day |
| Wiring the daemon produce path to the `CortexAcquisition` pthread (INT-01 stronger fix, INT-02) | Touches a shipped hot path. Wrong risk to take the night before the onsite. Named honestly in NAR-04 instead |
| INT-03 (`BCIInputPointerReport` from real decoded position in the GUI apps) | Same reason |
| Phase 3 SC#1 Instruments System Trace | Cheapest remaining credibility item and needs no hardware, but it is a device-gated HUMAN-UAT capture that must never be auto-approved, and it does not change the narrative. First candidate for v1.2 |
| Retraining, re-tuning or re-fitting any model | Would invalidate committed evidence and cannot be re-verified in the time available |
| Any change to radius, dwell or timeout in a published result | Forbidden by `10-PREREGISTRATION.md` |
| Making the repo public | Private by explicit standing decision; not reopening it on a deadline |
| Runnable demo capture and recording | Deselected at scoping. The walkthrough is the deliverable |

## Deferred to v1.2 or later

Carried from the v1.0 Known Gaps, unchanged and not addressed here: SYS-01, SYS-02 (Apple-granted
HID entitlement), DIST-01, DIST-02, DIST-03 (paid Apple Developer enrollment), PERF-04 (iPad Pro
M4), the five partials THREAD-02, RENDER-02, RENDER-05, RD-06, RD-08, and the
`donny-tools.cjs summary-extract` frontmatter parser defect that keeps `verify gate` unusable on
this repo.

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| GAP-01 | Phase 11 | Pending |
| GAP-02 | Phase 11 | Pending |
| GAP-03 | Phase 11 | Pending |
| GAP-04 | Phase 11 | Pending |
| GAP-05 | Phase 11 | Pending |
| GAP-06 | Phase 11 | Pending |
| GAP-07 | Phase 11 | Pending |
| GAP-08 | Phase 11 | Pending |
| NAR-01 | Phase 12 | Pending |
| NAR-02 | Phase 12 | Pending |
| NAR-03 | Phase 12 | Pending |
| NAR-04 | Phase 12 | Pending |
| NAR-05 | Phase 12 | Pending |
| NAR-06 | Phase 12 | Pending |
| NAR-07 | Phase 12 | Pending |

**Coverage:**
- v1.1 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0

---
*Requirements defined: 2026-09-17*
*Last updated: 2026-09-17 at milestone start*
