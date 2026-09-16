# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 - Real-Data Decoding

**Shipped:** 2026-09-16
**Phases:** 10 | **Plans:** 70 | **Tasks:** 193 | **Commits:** 546 | **Span:** 141 days

### What was built

- A real-data decoding pipeline: four checksum-pinned O'Doherty/Makin Indy M1 sessions (1.77 GB)
  through NDT1 (1,292,544 params) to a 239/239 ANE-eligible 4-bit `.mlpackage`, then ReFIT-Kalman
  and a 120 Hz beam-raced Metal renderer.
- A measurement layer that labels every number by the device and method that produced it, with
  twelve `*-policy.sh` CI gates (four carrying adversarial `--self-test` corpora) enforcing it.
- The Apple BCI HID protocol surface, notarization and TestFlight pipelines, all structurally
  complete with their live halves deferred behind never-auto-approved gates.
- A published negative result: 0 target acquisitions in 1,025 trials.

### What worked

- **Pre-registration.** `10-PREREGISTRATION.md` committed the disposition and action for a
  zero-hit outcome in Wave 0, before any hit count existed, and forbade relaxing radius, dwell or
  timeout. When the zero arrived there was no argument to have. This is the single highest-value
  process artifact in the milestone and it cost one document.
- **Negative controls on gates.** Every policy gate ships a `--self-test` that proves it bites.
  This caught real regressions and made "the gate passed" mean something.
- **Correcting rather than shipping a flattering number.** The masked-objective defect had inflated
  co-bps roughly tenfold; it was found, fixed, and the whole co-bps-versus-epoch curve published
  instead of a single figure. Same with the 226-vs-239 op tally read off a stale artifact.
- **Deferring instead of approximating.** Eleven hardware- and account-gated measurements were
  recorded as DEFERRED with their blocker named. None was fabricated, and the audit could tell
  exactly what was and was not measured.

### What was inefficient

- **The audit came at the end.** The interim audit covered Phases 1-2 and was never re-run until
  Phase 10 was done. INT-01, a requirement set describing a hot path with no production caller, sat
  undetected for seven phases. A mid-milestone audit after Phase 5 would have caught it while the
  fix was still cheap.
- **Tracking drift accumulated silently.** Eight requirement checkboxes lagged their SATISFIED
  verdicts, a coverage line was stale by two, Phase 9's status row said "verification pending" for
  13 days after it was verified, and two STATE.md deferred items stayed Open after CI closed them.
  None changed a measured result; all of it had to be reconciled by hand at the boundary.
- **Out-of-plan edits voided plan acceptance criteria.** A README rewrite (`30217d4`) passed all
  twelve gates while voiding two plan acceptance greps. Plan-time greps are not standing gates.
- **Tooling could not be trusted to count.** `summary-extract` mis-parses `requirements-completed`
  frontmatter, so `verify milestone-coverage` reported 0/75 satisfied against a true 56/11/0. The
  `*SUMMARY*` glob over-counted two phases. Both had to be worked around manually.

### Patterns established

- Pre-register the disposition of a result before measuring it, whenever a zero or a null is a
  plausible outcome.
- Every policy gate ships a negative control proving it bites, or it is not a gate.
- Any published number carries the device and method that produced it; a synthetic number is
  labeled synthetic and a Mac number is never presented as an iPad number.
- A requirement describes either the committed artifact or the running system, and says which.
- If an invariant must survive past its own plan, wire it into a `*-policy.sh` with `--self-test`.
  A grep in a plan's acceptance criteria protects nothing after that plan closes.

### Key lessons

1. **A gate that passes is not the same as a claim that holds.** Every THREAD requirement was
   SATISFIED with file-level evidence and enforced on every CI run, and the described hot path
   still ran nowhere. Artifact-level verification cannot detect an unwired artifact; only
   integration checking can. Audit integration mid-milestone, not at the end.
2. **The honest negative was worth more than the positive would have been.** The milestone's
   credibility rests on publishing 0/1025 under a rule written beforehand. A manufactured hit would
   have been worth less than nothing.
3. **Measure transfer, not just held-out performance.** Within-session held-out R2 0.4238 looked
   like a working decoder until leave-one-session-out flipped every sign. Held-out-within-session
   is an upper bound on a new recording day, not a description of one.
4. **Budget the training run before concluding from it.** A negative per-session verdict survived
   two corrections and turned out to be an artifact of a 12-epoch stopping rule; sixteen times the
   budget flipped every within-session sign. Check whether a null is a real null or a starved one.
5. **Reconcile tracking at phase close, not at milestone close.** Every drift item found in the
   audit was cheap to fix when it happened and tedious to fix in a batch four months later.

### Cost observations

- Not instrumented this milestone. Model mix, session count and per-phase token cost were not
  recorded, so there is no basis for a figure here. Worth instrumenting in v1.1 if cost is a
  question anyone intends to ask.

---

## Cross-Milestone Trends

### Process evolution

| Milestone | Phases | Plans | Span | Notable process change |
|---|---|---|---|---|
| v0 Software-Timed (internal) | 1-8 | 42 | 2026-04-28 to 2026-06-23 | Policy gates with negative controls established; never-auto-approve device gates introduced (D-17) |
| v1.0 Real-Data Decoding | 1-10 | 70 | 2026-04-28 to 2026-09-16 | Pre-registration of outcome dispositions; repo-wide honesty sweep in CI; milestone-level integration audit |

### Recurring issues

- Tracking artifacts (checkboxes, status rows, coverage counts, deferred-item states) drift from
  verified reality between phase close and milestone close. Seen in both milestones.
- donny state mutators write stale or wrong values into STATE.md (`status`, `stopped_at`,
  `completed_plans`, `milestone_name`). Re-read and restore after every state-writing command.
- Requirement text written at plan time describes intent; nothing forces it to be re-read against
  what shipped. INT-01 is the sharp case.
