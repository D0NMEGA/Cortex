---
phase: 01-foundation-2026-toolchain
plan: 05
subsystem: infra
tags: [documentation, adr, readme, pr-template, architecture-decisions, phase-1-foundation]

# Dependency graph
requires:
  - phase: 01-01
    provides: "docs/cortex-spec.md path established; _Static_assert pattern documented in ADR"
  - phase: 01-03
    provides: "CA92.1 decision documented in ADR-0001 section 6"
  - phase: 01-04
    provides: "fastlane D-09/D-10 deferral cross-phase note honored in ADR-0001 section 5"

provides:
  - "README.md at repo root: Phase 1 status, prerequisites, build instructions, SC#2 runbook, spec and ADR links"
  - "docs/adr/README.md: lightweight ADR index (ADR-0001 entry), when-to-write guidance, MADR-inspired template, sequential numbering policy"
  - ".github/pull_request_template.md: What/Why/Verification/Open-questions structure with requirement ID traceability and architectural commitment checklist"
  - "docs/adr/0001-foundation-and-2026-toolchain.md: canonical record for Phase 1's eight foundational decisions with D-XX citations, three critical findings, 12 rejected alternatives, and references to Apple Forums and runner-images sources"

affects:
  - "Phase 2+ plans: ADR-0001 is the format precedent for ADR-0002+; next ADR is ADR-0002 (sequential numbering, no decimals)"
  - "Phase 8 DIST-04: credibility-grade publishable README deferred to Phase 8; Phase 1 README is intentionally minimal"
  - "All future PRs: .github/pull_request_template.md enforces requirement ID traceability on every PR"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ADR-as-historical-record: ADR-0001 cites specific CONTEXT.md D-XX IDs so any future codebase-vs-ADR drift is auditable"
    - "PR template as defense-in-depth: architectural commitment checks (_ANEClient ban, CocoaPods ban, _Static_assert preservation) in BOTH the ADR and the PR template"
    - "Sequential ADR numbering: 0001, 0002, 0003 -- no decimals; supersession via full new ADR referencing old one's number"

key-files:
  created:
    - README.md
    - docs/adr/README.md
    - docs/adr/0001-foundation-and-2026-toolchain.md
    - .github/pull_request_template.md

  modified: []

key-decisions:
  - "README kept minimal (Phase 1 is foundation, not a publishable artifact) -- the credibility-grade README with architectural commitments table and rejected-alternatives is DIST-04 (Phase 8)"
  - "ADR-0001 explicitly cites fastlane as Phase-1 placeholder per D-09/D-10 per the cross-phase note in Plan 04 SUMMARY"
  - "docs/adr/README.md template uses ## headers not #### so the template section visually matches ADR-0001's actual section shape"
  - "PR template's architectural commitment checklist mirrors Plan 06's CI gates -- contributors cannot pass CI while checklist is honest about a violation"

requirements-completed:
  - FOUND-01

# Metrics
duration: 4m
completed: 2026-04-30
---

# Phase 01 Plan 05: README + ADR Index/Template + PR Template + ADR-0001 Summary

**Four documentation files creating the project's self-documenting entry point: a top-level README, an ADR index and template, a PR template enforcing traceability, and ADR-0001 -- the canonical record for Phase 1's eight foundational architectural decisions.**

## Performance

- **Duration:** 4 min 5 sec
- **Started:** 2026-04-30T04:31:08Z
- **Completed:** 2026-04-30T04:35:13Z
- **Tasks:** 2 / 2
- **Files created:** 4

## Accomplishments

- **README.md at repo root** -- entry point for any human reader (or reviewer). Phase 1
  status prominent in the title block. Build instructions include the correct
  `CODE_SIGNING_ALLOWED=NO` flags for unsigned-but-compilable CI builds. Phase 1
  limitations section documents the three intentional deferral points (iPad on-device,
  CI signing, fastlane placeholder). SC#2 manual runbook is included inline with a
  6-step procedure referencing the evidence file path in `.planning/`. Links to
  `docs/cortex-spec.md` and `docs/adr/` are present.

- **docs/adr/README.md** -- ADR index + template. Index section already populated with
  ADR-0001. When-to-write guidance prevents ADR inflation (do NOT write for obvious
  decisions or local refactors). MADR-inspired template uses ## headers matching the
  actual ADR-0001 section shape. Sequential numbering policy stated explicitly: no
  decimals, supersession via new ADR.

- **.github/pull_request_template.md** -- What/Why/Verification/Open-questions. The
  Why section requires phase, plan, and requirement ID fields (FOUND-XX, IPC-XX,
  RENDER-XX, DEC-XX). The Verification section provides three tiers:
  (1) CI gate checklist, (2) local manual check checklist, (3) architectural commitment
  preservation checklist. Architectural commitments encoded: no `_ANEClient`, no
  CocoaPods, no `dispatch_async`/`pthread_mutex`/`import Foundation`/`import ObjectiveC`
  in hot-path packages, hot-path policy script passes, privacy manifest validator passes,
  no Mac Catalyst regression, `_Static_assert` preserved.

- **docs/adr/0001-foundation-and-2026-toolchain.md** -- the load-bearing ADR.
  Exactly 8 numbered decisions with D-XX citations throughout:
  (1) XcodeGen (D-01, D-02, D-04)
  (2) Two targets, no Mac Catalyst (D-01)
  (3) SwiftPM-only (D-02, FOUND-04)
  (4) App Group for all three targets (D-07, FOUND-02)
  (5) Deferred enrollment (D-09, D-10, D-11, D-12)
  (6) PrivacyInfo CA92.1 (D-14, FOUND-03)
  (7) _Static_assert compile-time guard (D-08, cross-phase commitment)
  (8) CI on macos-15 + Xcode 26.3 (D-13, D-16, FOUND-05)

  Three critical findings from RESEARCH.md explicitly named:
  - Critical Finding #1: iOS vs macOS App Group + Personal Team asymmetry
  - Critical Finding #2: CODE_SIGNING_ALLOWED=NO strips entitlements (CI-vs-local)
  - Critical Finding #3: macos-15 default Xcode is 16.4 not 26.x

  14 distinct D-XX tokens cited (D-01, D-02, D-03, D-04, D-05, D-07, D-08, D-09,
  D-10, D-11, D-12, D-13, D-14, D-16). Meets and exceeds the >=8 minimum.

  12 rejected alternatives in the alternatives table: Tuist, hand-rolled xcodeproj,
  Mac Catalyst, CocoaPods, Pure SwiftPM, temporary-exception entitlement, Phase-1
  enrollment, fastlane match init in Phase 1, default Xcode, Xcode 26.0.1/26.1 RC,
  sandbox on Phase 1 Mac targets, runtime checks instead of _Static_assert.

  fastlane explicitly documented as Phase-1 placeholder per D-09/D-10, honoring the
  cross-phase note from Plan 04 SUMMARY.

## Task Commits

Each task committed atomically:

1. **Task 1: README.md + docs/adr/README.md + .github/pull_request_template.md** -- `e658665` (docs)
2. **Task 2: docs/adr/0001-foundation-and-2026-toolchain.md** -- `f749e4d` (docs)

## Files Created/Modified

**Task 1 (three documentation files):**

- `/Users/donmega/Desktop/Cortex/README.md` -- 102 lines; Phase 1 status, prerequisites
  (Xcode 26.3, XcodeGen, SwiftFormat, SwiftLint), build command with full
  CODE_SIGNING_ALLOWED=NO flags, three Phase 1 limitations, SC#2 6-step runbook,
  spec and ADR links
- `/Users/donmega/Desktop/Cortex/docs/adr/README.md` -- 59 lines; ADR-0001 index entry,
  when-to-write guidance, MADR-inspired template with Context/Decision/Consequences/
  Alternatives sections, sequential numbering policy
- `/Users/donmega/Desktop/Cortex/.github/pull_request_template.md` -- 35 lines;
  What/Why/Verification/Open-questions; requirement ID fields; architectural commitment
  checklist (_ANEClient, CocoaPods, hot-path, privacy manifest, Mac Catalyst,
  _Static_assert); CI green checkbox

**Task 2 (load-bearing ADR):**

- `/Users/donmega/Desktop/Cortex/docs/adr/0001-foundation-and-2026-toolchain.md` -- 240 lines;
  8 numbered decisions, 14 D-XX citations, 3 critical findings, 12 rejected alternatives,
  cross-phase commitments section, references section citing Apple Forums threads and
  runner-images issue numbers

## Decisions Made

- **README kept minimal.** Phase 1 is a foundation -- the credibility-grade README with
  architectural commitments table and rejected-alternatives table (DIST-04) ships at
  Phase 8. Phase 1's README documents what is scaffolded and provides the SC#2 runbook
  reference. This matches the plan's explicit intent ("Phase 1 README documents
  *what's scaffolded*") and honors CONTEXT.md Implementer's Discretion ("README content
  shape beyond documenting architectural commitments is flexible").

- **ADR-0001 fastlane deferral documented explicitly.** The Plan 04 SUMMARY included
  an explicit cross-phase note: "Plan 05 ADR-0001 must explicitly document that fastlane
  is a Phase-1 placeholder per D-09/D-10." ADR-0001 section 5 documents this with
  Matchfile `file:///` URL, commented-out Appfile identity fields, and the Phase 8 swap
  path. The cross-phase note is honored.

- **docs/adr/README.md template uses ## headers.** Template section headings use ##
  (not #### as in some alternative MADR formats) so the template visually matches
  ADR-0001's actual section shape. This makes the template a usable scaffold, not just
  documentation about a scaffold.

- **PR template's architectural commitment checklist mirrors CI.** The checklist items
  (hot-path policy, privacy manifest validator, _ANEClient ban, CocoaPods ban) directly
  mirror Plan 06's planned CI gate steps. Contributors cannot honestly check off the
  list while a CI gate would fail -- defense-in-depth that does not require contributors
  to memorize CI behavior.

## Deviations from Plan

None -- plan executed exactly as written. Two tasks, two commits, all acceptance criteria
satisfied. No Rule 1 / Rule 2 / Rule 3 / Rule 4 deviations triggered.

## Threat Surface Scan

No new security-relevant surface introduced. All four files are documentation artifacts
with no network endpoints, no auth paths, no file access patterns, and no schema changes.
The threat register in the plan's `<threat_model>` covers all identified risks:

- T-01-05-01 (README information disclosure): accepted -- README mentions the team ID
  prefix `com.donovansantine.cortex` and App Group path; none are secrets
- T-01-05-02 (ADR drift from reality): mitigated -- ADR cites specific D-XX decision IDs
  making drift auditable at the next phase transition
- T-01-05-03 (PR template checklist drift from CI): mitigated -- checklist mirrors Plan 06
  CI gate; future CI gate changes must update both
- T-01-05-04 (external link rot): accepted -- ADR cites thread numbers/issue numbers not
  URL paths; archive.org searches work on numbers
- T-01-05-05 (PR template commitment visibility): accepted -- intentional; DIST-04 will
  publish them anyway
- T-01-05-06 (template check removal): mitigated -- branch protection + PR diff visibility

No threat flags raised.

## Known Stubs

None. All four documentation files are substantive -- no placeholder text, no "coming soon",
no hardcoded empty values. The README's "License: Not yet specified" is an intentional
Phase-1 deferral documented in CONTEXT.md Deferred Ideas, not a stub.

---

## Self-Check: PASSED

**Files exist:**

- FOUND: `/Users/donmega/Desktop/Cortex/README.md` (Phase 1, docs/cortex-spec.md, CODE_SIGNING_ALLOWED=NO, SC#2)
- FOUND: `/Users/donmega/Desktop/Cortex/docs/adr/README.md` (0001-foundation index, ADR template, ## Context/Decision/Consequences/Alternatives)
- FOUND: `/Users/donmega/Desktop/Cortex/.github/pull_request_template.md` (Verification, FOUND-, _Static_assert, validate-privacy-manifest, _ANEClient, CocoaPods)
- FOUND: `/Users/donmega/Desktop/Cortex/docs/adr/0001-foundation-and-2026-toolchain.md` (8 decisions, 3 critical findings, 14 D-XX citations, 12 alternatives)

**Commits exist:**

- FOUND: `e658665` -- docs(01-05): add README, ADR index/template, and PR template
- FOUND: `f749e4d` -- docs(01-05): add ADR-0001 foundation and 2026 toolchain

**Cross-phase notes honored:**

- FOUND: fastlane D-09/D-10 deferral documented in ADR-0001 section 5 (per 01-04-SUMMARY cross-phase note)
- FOUND: docs/cortex-spec.md path reference in README (established by 01-01 Plan via git mv)
- FOUND: CA92.1 decision cited in ADR-0001 section 6 (consistent with 01-03-SUMMARY)

---

## Cross-Phase Notes

- **ADR-0001 is the format precedent for ADR-0002+.** The next ADR must follow the same
  section shape (## Context, ## Decision, ## Consequences, ## Alternatives considered,
  ## References) with sequential numbering (0002, 0003, ...). Decimal numbers are
  explicitly forbidden; supersession requires a new ADR.

- **Phase 8 DIST-04:** The credibility-grade publishable README (with architectural
  commitments table, rejected-alternatives table, photodiode-instrumented latency claim,
  and audience-facing framing for Bliss Chapman / Nir Even-Chen) is a Phase 8 deliverable.
  Phase 1's README is intentionally minimal and serves as the entry point for the
  development-phase repo only.

- **Future PR template maintenance:** When CI gates change (new gates added in Phase 2/3/6),
  the `.github/pull_request_template.md` Verification section should be updated to match.
  Adding a new CI gate without updating the PR template creates a honesty gap -- contributors
  see the template as authoritative for what CI checks.

---
*Phase: 01-foundation-2026-toolchain*
*Plan: 01-05*
*Completed: 2026-04-30*
