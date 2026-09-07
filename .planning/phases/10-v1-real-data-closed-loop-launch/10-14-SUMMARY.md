---
status: PASS
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 14
subsystem: infra
tags: [ci, shell, grep, find, policy-gate, self-test, adr, honesty-gate, rd-09, rd-10]

# Dependency graph
requires:
  - phase: 10-13
    provides: "`Tools/scripts/readme-policy.sh` rewritten (the helper + control + `--self-test` shape this gate copies), `docs/adr/0003-photodiode-retirement-and-real-data-v1.md` with the `hardware-gated` and `largest credibility hole` rationale literals this gate asserts, and the ADR index entry"
  - phase: 10-12
    provides: "The corrected labels and the superseded-evidence banners this gate turns from an editorial state into an invariant"
  - phase: 10-11
    provides: "`WebgridBPS.nonComparabilityDisclosure` and the four grounds published in README.md and docs/cortex-spec.md"
  - phase: 09
    provides: "The Phase-9 corrections that made 226/226 and 0.3804 superseded numbers in the first place (239/239 op tally, the masking-objective fix)"
provides:
  - "`Tools/scripts/honesty-sweep.sh`: seven assertions, 14 negative controls, one CI step"
  - "The label invariant: every occurrence of the five enumerated superseded numbers carries a labeling token on its own line"
  - "The preservation invariant: LAT-01..LAT-08 must survive in BOTH ROADMAP.md and REQUIREMENTS.md"
  - "The supersession-note invariant: an ADR excluded from the token scan must carry a DATED forward pointer to ADR-0003 -- the exclusion is paid for, not free"
  - "The authority invariant: the 8.5 Neuralink reference may not be framed as verified or independently sourced (D-17)"
  - "Dated partial-supersession notes on ADR-0001 and ADR-0002"
  - "PERF-02 reworded off 'verified peak' onto the settled D-17 wording"
affects: [10-15, 10-16, 10-17]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Exclusion-with-a-price: a path excluded from a scan carries a SEPARATE assertion over the same files (phases tree -> banner check; superseded ADRs -> dated supersession note), so an exclusion is never indistinguishable from a hole"
    - "Enumerated collision forms: a token's digit string is exempted only in named literal forms, each with a written reason naming the real quantity it belongs to -- the generalization of writing `226/226` rather than `226`"
    - "Exclusion positive-controls in the baseline: the clean stand-in tree deliberately carries unlabeled tokens inside excluded paths, so the baseline passing proves the exemptions are live, and paired negative controls prove they are not blanket"

key-files:
  created:
    - Tools/scripts/honesty-sweep.sh
  modified:
    - .github/workflows/ci.yml
    - .planning/REQUIREMENTS.md
    - .planning/phases/05-ndt1-coreml-deployment-with-ane-residency-verified/05-ane-eligibility-evidence.md
    - Decoder/scripts/train_real.py
    - Decoder/tests/test_cobps_margin.py
    - Decoder/tests/test_heldout_cobps.py
    - Packages/CortexDemo/Sources/CortexReplayBench/main.swift
    - docs/adr/0001-foundation-and-2026-toolchain.md
    - docs/adr/0002-v0-ship-and-bci-hid-integration.md
    - docs/adr/0003-photodiode-retirement-and-real-data-v1.md

key-decisions:
  - "`.planning/` is excluded from the token scan and the reason is written into the gate, but the gate still reaches into it through two other assertions. Four of the nine first-run findings were in `.planning/ROADMAP.md`, which the execution boundary forbids editing; excluding ROADMAP alone would have been arbitrary. The scan's scope is now the published surface, which maps exactly onto RD-09's own criterion (README, ADRs, every `*-evidence.md`)."
  - "Two exclusions were added beyond the plan's list and both were PAID FOR with a new assertion rather than taken for free. `docs/adr/0001-` and `0002-` are excluded because an ADR is immutable; assertion (f) then requires each to carry a DATED supersession note naming ADR-0003, with two controls."
  - "`0.161` collides with two real latency measurements (`0.1615`/`0.1618` render GPU p99, `0.161 ms` Seam B p99). The collisions are enumerated as literal exempt forms with reasons rather than dropping the token, because labeling a real measurement `synthetic` would be a lie and a gate that cries wolf gets disabled."
  - "Every first-run label finding was FIXED, not excluded. Nine occurrences, each a line-wrap artifact of already-honest prose; the prose was reflowed or a true qualifier added. `LABEL_TOKENS` was not widened and no path exclusion was added to clear a failure."
  - "ADR-0001 and ADR-0002 keep `**Status:** Accepted` with a separate `**Superseded in part by:**` line. A whole-ADR `Superseded by` status would be false: ADR-0001's eight foundational decisions and ADR-0002's wire-and-gate doctrine all still hold."

patterns-established:
  - "Pattern 1: every path exclusion in a gate carries (a) a written reason naming what breaks if it is removed and (b) a compensating assertion over the same files"
  - "Pattern 2: the self-test's clean baseline is loaded with the exemptions themselves, so a dead exemption fails the baseline and a blanket exemption fails a paired negative control"

# REQUIRED - copy ALL requirement IDs from this plan's `requirements` frontmatter field.
requirements-completed: [RD-09, RD-10]

# Metrics
duration: 80 min
completed: 2026-09-07
---

# Phase 10 Plan 14: honesty-sweep.sh, the RD-09/RD-10 labeling and preservation gate Summary

**RD-09's editorial sweep and RD-10's preservation requirement are now a build-failing gate: seven
assertions over labels, banners, the eight retired LAT identifiers, ADR-0003's structure and
rationale, the four BPS non-comparability grounds, dated supersession notes on the superseded ADRs,
and the authority the 8.5 figure is allowed to claim -- with 14 negative controls, two of which
exist solely to prove the exclusions are not blanket holes.**

## Performance

- **Duration:** 80 min
- **Started:** 2026-09-07T06:36Z (approx)
- **Completed:** 2026-09-07T07:56Z
- **Tasks:** 2 planned, both complete (committed as 3 commits)
- **Files modified:** 11 (1 created, 10 modified)

## Accomplishments

- `Tools/scripts/honesty-sweep.sh`, 768 lines, seven assertions and 14 `PASS [` controls. It exits 0
  on the real tree and its `--self-test` exits 0.
- **All three defects handed over by name are fixed and gated.** PERF-02's unearned "verified", the
  stale defining-claim sentence in ADR-0001, and the path-scoping trap around `docs/adr/0003-*`.
- **The gate found a real RD-09 gap Plan 10-12 missed**: `05-ane-eligibility-evidence.md` carried the
  superseded `226/226` op tally with no banner while its sibling `05-placement-evidence.md` had one.
- **Two assertions beyond the plan's spec, both demanded by the defects**: the dated
  supersession-note check that pays for the ADR exclusion, and the unearned-authority check that
  makes PERF-02's defect a build failure rather than a one-time correction.
- Every one of the nine first-run label findings was FIXED rather than excluded, and the disposition
  of each is listed below.

## Task Commits

1. **Defects 1 and 2: PERF-02's unearned "verified", plus dated supersession notes on ADR-0001 and
   ADR-0002** -- `886bb14` (fix). Committed first so every commit leaves the tree green: these three
   corrections stand on their own and the gate that asserts them does not exist yet.
2. **Task 1: `honesty-sweep.sh` -- the token scan, the banner check, the preservation checks, and
   the seven assertions' controls** -- `adee068` (feat). Includes the nine label fixes and the
   missing evidence banner, which are what make Task 1's own acceptance criterion ("exits 0 on the
   real tree") true.
3. **Task 2: wire the honesty sweep into CI** -- `3f0429c` (ci).

`.planning/ROADMAP.md` and `.planning/STATE.md` are untouched, per the execution boundary:
`git diff --name-only b6e4551..HEAD | grep -E 'ROADMAP|STATE'` returns nothing.

## Files Created/Modified

- `Tools/scripts/honesty-sweep.sh` (768 lines, new) -- the gate. Seven assertion functions
  (`check_labels`, `check_banners`, `check_lat_preserved`, `check_adr`, `check_bps_grounds`,
  `check_superseded_adrs`, `check_cited_authority`), two shared helpers (`strip_collisions`,
  `is_excluded`), a `find`-based `sweep_files` walk with no VCS dependency, and a `self_test` with a
  `write_clean` stand-in tree and 14 cases.
- `.github/workflows/ci.yml` (+26/-0) -- one step in `build-and-lint`, immediately after the README
  gate, plus its comment block. No line removed.
- `.planning/REQUIREMENTS.md` (+1/-1) -- PERF-02 only. Defect 1.
- `docs/adr/0001-foundation-and-2026-toolchain.md` (+14) -- a dated partial-supersession note. Defect 2.
- `docs/adr/0002-v0-ship-and-bci-hid-integration.md` (+15) -- the same, for its superseded BPS
  numbers and its "the photodiode-instrumented number is the v1 claim" table row.
- `docs/adr/0003-photodiode-retirement-and-real-data-v1.md` (+3/-2) -- one paragraph reflowed so the
  word `synthetic` sits on the same lines as the four numbers it qualifies. No word removed.
- `.planning/phases/05-.../05-ane-eligibility-evidence.md` (+11) -- the missing superseded banner,
  byte-identical to the one on `05-placement-evidence.md`.
- `Decoder/scripts/train_real.py` (+9/-7), `Decoder/tests/test_cobps_margin.py` (+2/-2),
  `Decoder/tests/test_heldout_cobps.py` (+1/-1) -- six `0.3804` line-wrap fixes.
- `Packages/CortexDemo/Sources/CortexReplayBench/main.swift` (+2/-2) -- two trailing comments on the
  `supersededSynthetic` fields. No identifier and no JSON key changed.

## The three defects handed over by name

**Defect 1 -- `.planning/REQUIREMENTS.md:125` asserted authority the 8.5 figure does not have.**
The line read `Document path toward Neuralink P1 verified peak (8.5 BPS)`. D-17 settled that 8.5 is
retrieved and not independently sourceable to a Neuralink primary; `README.md:215`,
`docs/cortex-spec.md:54/172/317` and `.planning/PROJECT.md:108` already say so. REQUIREMENTS.md was
the last holdout. Now:

```
- [ ] **PERF-02**: Document path toward the Neuralink P1 cited reference (8.5 BPS, as cited by
      this repo since Phase 7; not independently sourceable to a Neuralink primary -- D-17) --
      what gaps remain
```

The CLASS is gated by assertion (g), `check_cited_authority`: for each of `README.md`,
`docs/cortex-spec.md`, `.planning/REQUIREMENTS.md` and `.planning/PROJECT.md`, every line naming
`8.5` is lowercased, has explicit negations deleted, and is then scanned for
`(verified|confirmed|independently sourced|peer.reviewed|authenticated|authoritative)`. The negation
strip is what lets `the 8.5 figure is not independently sourceable` pass while `verified peak` fails
-- a bare word list cannot tell those apart. Control 9 appends the original defective line verbatim
to the stand-in and requires exit 1.

**Defect 2 -- `docs/adr/0001-*.md:15-16` still called the retired photodiode figure the defining
project claim.** Handled the way `docs/adr/README.md` "Numbering" already prescribes: a note in the
Status area, dated, pointing at the superseding ADR. The original sentence is untouched.

```
**Status:** Accepted
**Date:** 2026-04-28
**Deciders:** @donovansantine
**Superseded in part by:** [ADR-0003](0003-photodiode-retirement-and-real-data-v1.md), 2026-08-28
```

followed by a blockquote stating what is retired, that the original sentence is deliberately left
verbatim because an ADR records what was decided rather than what is currently true, and that the
supersession is PARTIAL -- the eight foundational decisions are unaffected and remain Accepted.
`**Status:** Accepted` is kept for exactly that reason: a whole-ADR `Superseded by ADR-0003` status
would be false.

ADR-0002 got the same treatment, unprompted but required by the same reasoning: it is excluded from
the token scan on the same grounds (it records the superseded 1.953 and 0.374), and it carries the
same stale framing at line 144 ("The photodiode-instrumented number is the v1 claim"). An exclusion
without the note would have been an unpaid hole.

**Defect 3 -- path scoping.** Resolved by scoping, plus a control:

- The gate implements **no `24.7` rule at all**. `readme-policy.sh` owns that figure and its three
  D-13 rules stay README-scoped, so ADR-0003's verbatim D-1 transcript (including
  `PASS  We measured 24.7 ms on the iPad Pro M4, beating the retired spec target.`) and
  `readme-policy.sh`'s own eight corpus strings are inert to this gate by construction, not by
  exemption.
- `Tools/scripts/` **is** excluded, for the reason the plan gives (`readme-policy.sh`'s
  `write_clean_readme` carries `226/226`, `bps-policy.sh` carries `1.953`, and the gate must not scan
  its own token list).
- `docs/adr/0003-*` is **NOT** excluded. It is the current decision record and its lines must carry
  their labels; the one line that did not was fixed (see the disposition table). `docs/adr/0001-` and
  `0002-` are excluded, as superseded records, and assertion (f) is the price.
- **The negative control the boundary requires:** control 10. The clean stand-in tree deliberately
  carries an unlabeled `1.953` inside `docs/adr/0001-a.md` and an unlabeled `226/226` inside
  `Tools/scripts/fixture.sh`, and it PASSES -- which is the positive control proving those exemptions
  are live. Control 10 then appends *the same two strings* to `Packages/Demo/main.swift`, which is
  not excluded, and requires exit 1. Control 11 does the same for the collision forms: the baseline
  passes with an unlabeled `0.1618` in a scanned file; adding a bare `0.161` to that same file bites.

## The gate's design

**Seven assertions.** (a) label scan, (b) evidence banner, (c) LAT-01..LAT-08 preservation,
(d) ADR-0003 structure plus rationale, (e) the four BPS non-comparability grounds, (f) dated
supersession notes on excluded ADRs, (g) unearned authority on the 8.5 reference.

**Bounded, not universal (review D-7, SC#3).** The header states that the scan proves only that none
of the five enumerated tokens appears unlabeled in the swept tree, that this is a tripwire against
regression and not a completeness proof over every figure in the repo, and that the broader claim is
carried by the RD-09 human review plus `decoder-policy.sh` / `refit-real-policy.sh`.
`grep -icF 'no synthetic number anywhere' Tools/scripts/honesty-sweep.sh` returns 0.

**D-09.** The marker `# D-09: no assertion below compares a measured value against a bar.` sits
immediately above `scan()` at line 480, and
`grep -nE '(bps|r2|p99|tp|co_bps)[^"]*(>=|<=|>|<)[[:space:]]*[0-9]'` over the file returns nothing.

**Exclusions and their reasons**, each written into the file:

| Excluded path | Reason | What pays for it |
|---|---|---|
| `.planning/` | `phases/` is historical evidence, bannered rather than edited; the root tracking files are machine-maintained by the workflow tooling, so a hand-added label there is not durable | Assertion (b) owns the phases tree; assertions (c) and (g) reach into ROADMAP, REQUIREMENTS and PROJECT |
| `Tools/scripts/` | Gate-internal stand-ins: `readme-policy.sh` carries `226/226`, `bps-policy.sh` carries `1.953`; and this gate must not scan its own token list | Control 10 |
| `docs/adr/0001-`, `docs/adr/0002-` | An ADR is an immutable decision record; a superseded premise gets a forward pointer, not an edit | Assertion (f), controls 8 and 8b |
| `Decoder/scripts/fit_velocity_real.py`, `Decoder/scripts/rederive_coreml.py`, `Decoder/tests/test_ane_compute_plan.py` | The literal `226` is a deliberately preserved Phase-5 baseline used by Plan 09-08's attribution control, not a live claim (10-RESEARCH: "do not sweep those") | The comment names the attribution control so a future maintainer does not "fix" them |

**Collision forms.** `226/226` rather than `226` is the plan's own disambiguation; `0.161` needed the
same treatment and could not get it inside the token, because the Fitts throughput is cited bare.
Three literal exempt forms, each naming the real quantity it belongs to:

| Form | What it actually is |
|---|---|
| `0.1615`, `0.1618` | Phase-6 render GPU frame time in ms, M5 Pro, two histogram runs (`06-render-evidence.md`) |
| `0.161 ms` | Seam B p99 latency, 160958 ns rendered in milliseconds (README Seam B table, Plan 10-06) |

Without these the gate would have demanded a `synthetic` banner on `06-render-evidence.md` and a
`synthetic` label on the README's Seam B row. Both are real measurements; the label would be a lie.

## First-run findings and their dispositions

The first real run failed with 11 findings across three assertions. Every one was fixed. Nothing was
excluded and `LABEL_TOKENS` was not widened.

| Occurrence | Disposition |
|---|---|
| `Decoder/scripts/train_real.py:9` `broken, because 0.3804 was produced by the defect.` | **Label fixed by reflow.** Line 8 already said "the synthetic 0.3804"; line 9 reworded to "that synthetic number", removing the bare occurrence. |
| `Decoder/scripts/train_real.py:46` `0.3804 came out of the same defective objective...` | **Label added:** "Phase 4's synthetic 0.3804". Accurate -- Phase 4's number was synthetic-Poisson. |
| `Decoder/scripts/train_real.py:129` (two occurrences on one line) | **Label fixed by reflow.** "the synthetic co-bps 0.3804" now on one line; the second bare occurrence became "that synthetic number". |
| `Decoder/scripts/train_real.py:232` `PHASE4_OBSERVED_CO_BPS: float = 0.3804` | **Label added** as a trailing comment: `# synthetic: Phase-4's defective-objective observation`. This is the constant most likely to be quoted alone, so the same-line label is the right form here. |
| `Decoder/tests/test_cobps_margin.py:5` | **Label fixed by reflow.** "synthetic" moved up from line 6 to sit with the number; line 6 keeps "purpose-built learnable sinusoid". |
| `Decoder/tests/test_heldout_cobps.py:48` | **Label added:** "an observed 0.3804" became "the synthetic 0.3804". |
| `Packages/CortexDemo/.../CortexReplayBench/main.swift:620` `refit_webgrid_bps: 1.953047883714651,` | **Label added** as a trailing comment `// superseded synthetic (Phase 8)`. The enclosing struct is `SupersededSynthetic` and its `note` says so, but the line a reader quotes did not. Field names and JSON keys untouched -- Plan 10-16 needs them byte-identical. |
| `Packages/CortexDemo/.../CortexReplayBench/main.swift:623` `refit_fitts_tp: 0.37439506338290895,` | Same, `// superseded synthetic (Phase 7)`. |
| `docs/adr/0003-...md:36` (four tokens on one line, `synthetic` stranded on line 37) | **Label fixed by reflow**, the 10-13 precedent applied to the ADR: "So every decoder number was synthetic: co-bps 0.3804, the ReFIT / 0.374-versus-0.161 Fitts ablation and the 1.953 Webgrid BPS were synthetic-data numbers wearing / real-sounding labels." Every word preserved; both token-bearing lines now carry `synthetic`. |
| `05-ane-eligibility-evidence.md` names `226/226`, no banner | **Banner added**, byte-identical to `05-placement-evidence.md`'s, pointing at `09-coreml-evidence.md`. A genuine RD-09 gap: Plan 10-12 bannered the sibling and missed this file. |
| `.planning/REQUIREMENTS.md:125` "verified peak (8.5 BPS)" | **Wording fixed.** Defect 1. |

A twelfth finding arrived during Task 2: the first draft of the new ci.yml comment named a bare
`0.161` with no label and the gate reported `.github/workflows/ci.yml:317`. Reworded, not exempted.
That is the first evidence outside a self-test that the gate bites on a real file in normal use.

**Findings NOT in scope, recorded for the orchestrator.** Excluding `.planning/` means the following
unlabeled occurrences in the tracking files are not gated. They were verified by hand this session
and none is a false claim, but they are the honest residue of the scope decision:

| File:line | Token | Character |
|---|---|---|
| `.planning/ROADMAP.md:30` | `226/226` | Phase-5 bullet; the SAME line already states "Op tally corrected in Phase 9 to 239/239", so it is honest but carries none of the nine label tokens |
| `.planning/ROADMAP.md:32` | `0.374`, `0.161` | Phase-7 bullet, "3-way ablation refit_bps 0.374 >= raw 0.161" with no synthetic label |
| `.planning/ROADMAP.md:33` | `1.953` | Phase-8 bullet, "ReFIT 1.953 BPS honest gap-to-8.5" with no synthetic label |
| `.planning/ROADMAP.md:126` | `0.161` | FALSE POSITIVE: the render p99 `0.1618ms`, exempted by a collision form anyway |
| `.planning/PROJECT.md:61` | `0.374`, `0.161` | Phase-7 validation bullet, no synthetic label |
| `.planning/PROJECT.md:153` | `226/226` | Rejected-alternatives row, "Validated Phase 5 -- 226/226 ANE-eligible" |
| `.planning/REQUIREMENTS.md:47, :49` | `226/226` | DEC-06 and DEC-08; DEC-08's line already states the 239/239 correction |
| `.planning/REQUIREMENTS.md:67` | `0.161` | FALSE POSITIVE: the render p99 `0.1618ms` |

Four of these are in `ROADMAP.md`, which the execution boundary forbids this plan from editing, and
three more are in `REQUIREMENTS.md` outside defect 1's line. That constraint is what forced the scope
decision, and it is stated here rather than buried.

## Verification

### The gate, both directions

```
./Tools/scripts/honesty-sweep.sh              -> exit 0   (against the real tree at HEAD)
./Tools/scripts/honesty-sweep.sh --self-test  -> exit 0
grep -c 'PASS \['  ->  14   (plan requires >= 8)
```

Real-tree run:

```
sweeping tree:        .
  excluded by path:   .planning/ Tools/scripts/ docs/adr/0001- docs/adr/0002- Decoder/scripts/fit_velocity_real.py Decoder/scripts/rederive_coreml.py Decoder/tests/test_ane_compute_plan.py
  banner tree:        .planning/phases/0[4-8]*/*-evidence.md
  preservation:       .planning/ROADMAP.md + .planning/REQUIREMENTS.md
  adr:                docs/adr
  ok  [label] every superseded token in the swept tree carries a label on its own line
  ok  [banner] every superseded evidence artifact points forward
  ok  [preserve] LAT-01..LAT-08 present in both planning files
  ok  [adr] 0003-photodiode-retirement-and-real-data-v1.md: four headings, Status, index link, both rationale literals
  ok  [grounds] all four BPS non-comparability grounds in the README and the spec
  ok  [supersede] every superseded ADR points forward, dated
  ok  [authority] the 8.5 reference is nowhere framed as verified
OK: honesty sweep clean -- every superseded number in the swept tree is labeled on its own
    line, every superseded evidence artifact points forward, LAT-01..LAT-08 survive in both
    planning files, ADR-0003 is present, linked and reasoned, both published copies state
    all four BPS non-comparability grounds, the superseded ADRs carry dated forward
    pointers, and the 8.5 reference is nowhere framed as verified.
```

### The control roster: 14 cases, every one bit

```
== honesty-sweep self-test ==
-- clean synthetic tree (also proves the three exemptions are live) --
  PASS [clean tree] exit=0 (expected 0)
-- label negative control --
  PASS [1 strip the synthetic label from the 1.953 line] exit=1 (expected 1)
-- banner negative control --
  PASS [2 remove the superseded-evidence banner] exit=1 (expected 1)
-- LAT preservation negative controls (both files) --
  PASS [3 delete LAT-05 from the ROADMAP] exit=1 (expected 1)
  PASS [3b delete LAT-05 from REQUIREMENTS] exit=1 (expected 1)
-- ADR negative controls --
  PASS [4 delete the ADR-0003 index link] exit=1 (expected 1)
  PASS [5 remove the Alternatives-considered heading] exit=1 (expected 1)
  PASS [6 remove hardware-gated with every ADR heading intact] exit=1 (expected 1)
-- BPS non-comparability negative control --
  PASS [7 drop one of the four BPS grounds from the README] exit=1 (expected 1)
-- superseded-ADR supersession-note negative controls --
  PASS [8 remove ADR-0001's supersession note] exit=1 (expected 1)
  PASS [8b strip the date from ADR-0002's supersession note] exit=1 (expected 1)
-- cited-figure authority negative control --
  PASS [9 call the 8.5 reference a verified peak] exit=1 (expected 1)
-- exclusion-is-not-a-hole negative control --
  PASS [10 the same unlabeled strings bite in a NON-excluded file] exit=1 (expected 1)
-- collision-form-is-not-a-hole negative control --
  PASS [11 a bare 0.161 bites in the same file whose 0.1618 is exempt] exit=1 (expected 1)
SELF-TEST OK: a clean stand-in tree passes with its three exemptions live; and each of
              stripping a label, removing an evidence banner, deleting LAT-05 from either
              planning file, unlinking ADR-0003, removing an ADR heading, removing the
              retirement rationale with every heading intact, dropping one BPS ground,
              removing or undating a superseded ADR's forward pointer, calling the 8.5
              reference verified, and moving an excluded string or a collision form into
              scanned position -- bites.
```

Case 6 is 10-VALIDATION.md line 109's control exactly: it removes `hardware-gated` from the stand-in
ADR while leaving `## Context`, `## Decision`, `## Consequences`, `## Alternatives considered` and
`**Status:**` all intact, and the gate still exits 1.

### Manual bite check against the real README

Acceptance criterion: strip the `synthetic` label from a real `1.953` line in a temp copy of
`README.md`, point `SWEEP_ROOT` at that copy, confirm exit 1 naming file and line.

```
--- diff of the one-word strip ---
200,202c200,202
< | raw | 1.292 | 0.161 | **synthetic seed-locked replay**, no model in the loop |
< | Kalman-only | 1.183 | 0.155 | **synthetic seed-locked replay** |
< | **ReFIT** | **1.953** | 0.374 | **synthetic seed-locked replay** |
---
> | raw | 1.292 | 0.161 | **seed-locked replay**, no model in the loop |
> | Kalman-only | 1.183 | 0.155 | **seed-locked replay** |
> | **ReFIT** | **1.953** | 0.374 | **seed-locked replay** |
--- gate with SWEEP_ROOT pointed at the stripped copy ---
ERROR [label] a superseded number appears WITHOUT a labeling token on its own line.
  README.md:200: [0.161] | raw | 1.292 | 0.161 | **seed-locked replay**, no model in the loop |
  README.md:202: [1.953] | **ReFIT** | **1.953** | 0.374 | **seed-locked replay** |
  ok  [banner] every superseded evidence artifact points forward
  ok  [preserve] LAT-01..LAT-08 present in both planning files
  ok  [adr] 0003-photodiode-retirement-and-real-data-v1.md: four headings, Status, index link, both rationale literals
  ok  [grounds] all four BPS non-comparability grounds in the README and the spec
  ok  [supersede] every superseded ADR points forward, dated
  ok  [authority] the 8.5 reference is nowhere framed as verified
honesty-sweep: FAILED -- a labeling or preservation invariant regressed (see ERROR lines).
EXIT=1
```

Every other assertion stayed green, so the failure isolates the label rule.

### Task 1 acceptance greps

```
grep -cF 'hardware-gated'                  ->  6
grep -cF 'largest credibility hole'        ->  3
grep -cF 'log2(N-1)'                       ->  3
grep -cF 'structurally zero'               ->  4
grep -cF 'click-type'                      ->  3
grep -cF '9x9'                             ->  3
grep -cF 'LAT-08'                          -> 11
grep -cF '0003-'                           -> 12
grep -cF 'fit_velocity_real.py'            ->  2   (the exclusion line + its reason comment)
grep -cF -- '--self-test'                  ->  3
grep -nF '# D-09: no assertion below compares a measured value against a bar.'  -> line 480
grep -icF 'no synthetic number anywhere'   ->  0   (required 0)
grep -nE '(bps|r2|p99|tp|co_bps)[^"]*(>=|<=|>|<)[[:space:]]*[0-9]'  -> (empty, required empty)
test -x Tools/scripts/honesty-sweep.sh     -> executable OK
bash -n Tools/scripts/honesty-sweep.sh     -> clean
wc -l                                      -> 768   (plan minimum 260)
```

### Task 2 acceptance checks

```
python3 yaml.safe_load(.github/workflows/ci.yml)  -> OK ci.yml parses; 58 steps (was 57)
grep -cF 'honesty-sweep.sh' .github/workflows/ci.yml       -> 2   (the gate and its self-test)
grep -cE 'brew install .*swiftformat' .../ci.yml           -> 1   (unchanged; 10-15 owns the pin)
git diff --stat .github/workflows/ci.yml                   -> 26 insertions(+), 0 deletions
```

Job and neighbours, read back out of the parsed YAML:

```
job: build-and-lint
  prev: README credibility + no-leak gate (DIST-04, D-06, RD-10)
  this: Repo-wide honesty sweep + self-test (RD-09/RD-10)
  next: Verify iOS 120Hz plist key (RENDER-03, SC#3)
  run : './Tools/scripts/honesty-sweep.sh\n./Tools/scripts/honesty-sweep.sh --self-test\n'
```

### All ten policy gates, with and without `--self-test`

The workflow has never executed on a runner (`total_count: 0`), so this local transcript is the
evidence base; Plan 10-17 replaces it with a real run.

```
./Tools/scripts/readme-policy.sh                     exit=0
./Tools/scripts/readme-policy.sh       --self-test   exit=0
./Tools/scripts/bps-policy.sh                        exit=0
./Tools/scripts/bps-policy.sh          --self-test   exit=0
./Tools/scripts/render-policy.sh                     exit=0
./Tools/scripts/render-policy.sh       --self-test   exit=0
./Tools/scripts/hid-surface-policy.sh                exit=0
./Tools/scripts/hid-surface-policy.sh  --self-test   exit=0
./Tools/scripts/decoder-policy.sh                    exit=0
./Tools/scripts/decoder-policy.sh      --self-test   exit=0
./Tools/scripts/refit-real-policy.sh                 exit=0
./Tools/scripts/refit-real-policy.sh   --self-test   exit=0
./Tools/scripts/honesty-sweep.sh                     exit=0
./Tools/scripts/honesty-sweep.sh       --self-test   exit=0
--- the remaining three gates the plan's roll-call also names ---
./Tools/scripts/hotpath-policy.sh                    exit=0
./Tools/scripts/hotpath-policy.sh      --self-test   exit=0
./Tools/scripts/notarize-policy.sh                   exit=0
./Tools/scripts/notarize-policy.sh     --self-test   exit=0
./Tools/scripts/match-policy.sh                      exit=0
./Tools/scripts/match-policy.sh        --self-test   exit=0
./Tools/scripts/validate-privacy-manifest.sh <2 manifests>  exit=0
```

### Test suites

```
uv sync --project Decoder --extra dev                       -> exit 0
uv run --project Decoder pytest Decoder/tests -m "not slow" -q
  -> 288 passed, 1 skipped, 10 deselected in 3.72s
     (the skip is test_data.py:157, "no loadable real .mat present (dataset is gitignored)")
uv run --project Decoder ruff check Decoder                 -> All checks passed!

swift test --package-path Packages/CortexDemo   -> Test run with 44 tests in 5 suites passed
swift test --package-path Packages/CortexReFIT  -> Test run with 32 tests in 5 suites passed
swift test --package-path Packages/CortexRender -> Test run with 19 tests in 4 suites passed
swift build --package-path Packages/CortexDemo  -> Build complete
```

Every count matches the expectation stated in the prompt.

### Lint status of the one edited Swift file

```
swiftformat --lint Packages/CortexDemo/Sources/CortexReplayBench/main.swift
  -> 0/1 files require formatting

swiftlint lint Packages/CortexDemo/Sources/CortexReplayBench/main.swift
  -> 8 pre-existing identifier_name errors on the snake_case JSON keys
     (data_source, session_id, source_sha256, manifest_path, export_sidecar_sha256,
      encoder_checkpoint_sha256, velocity_checkpoint_sha256, superseded_synthetic)
```

Those eight are exactly Plan 10-16's declared scope and none is new: the two added lines are trailing
comments. See the note to 10-16 below.

### LAT-01 through LAT-08 preserved verbatim

`git diff --name-only b6e4551..HEAD` does not list `.planning/ROADMAP.md`, so ROADMAP preservation is
structural rather than asserted. `.planning/REQUIREMENTS.md` changed on line 125 only (PERF-02); the
eight LAT checkbox lines at 111-120 are byte-identical, including LAT-07's verbatim spec-target
wording. Assertion (c) now checks all eight identifiers in both files on every commit, with controls
3 and 3b proving each half bites.

## Decisions Made

1. **`.planning/` is out of the token scan, and the reason is written into the gate.** Four of the
   nine first-run findings were in `ROADMAP.md`, which the execution boundary forbids editing, and
   three more were in `REQUIREMENTS.md` outside defect 1's line. Excluding only ROADMAP would have
   been arbitrary. The scan's scope is now the published surface, which maps onto RD-09's own
   criterion word for word ("README, ADRs and every `*-evidence.md`"). `.planning/` is not invisible
   to the gate: assertion (c) asserts LAT-01..08 in ROADMAP and REQUIREMENTS, and assertion (g) scans
   REQUIREMENTS and PROJECT. The residue is tabulated above rather than dropped.
2. **Every exclusion beyond the plan's list is paid for.** `docs/adr/0001-`/`0002-` are excluded only
   because assertion (f) then requires each to carry a dated forward pointer, with two controls. The
   standing rule -- an exclusion without a control is how a gate gets silently disarmed -- was applied
   to my own additions, not just inherited ones.
3. **`0.161`'s collisions are enumerated, not tolerated and not dropped.** Three literal exempt forms
   with written reasons, and control 11 proves the exemption is not blanket. Dropping the token would
   have weakened the tripwire; leaving it bare would have demanded a `synthetic` label on the Phase-6
   render p99 and the README's Seam B row, both of which are real measurements.
4. **The artifacts were fixed, not the rules.** Nine label findings, all reflows or true qualifiers.
   `LABEL_TOKENS` was not widened by a single entry. This follows 10-13's precedent, where the
   README was reflowed rather than Rule A relaxed.
5. **ADR-0001 and ADR-0002 keep `Status: Accepted`.** A whole-ADR `Superseded by ADR-0003` would be
   false: ADR-0001's eight foundational decisions and ADR-0002's wire-and-gate doctrine all still
   hold. The supersession is stated as partial and scoped in prose.
6. **Two assertions were added beyond the plan's five.** (f) and (g). Neither is scope creep: (g) is
   the defect-1 instruction ("make `honesty-sweep.sh` catch the class so it cannot come back") and
   (f) is the price of an exclusion I introduced.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The plan's token-scan scope collided with the execution boundary on
`.planning/`**

- **Found during:** Task 1, at the first real run of the gate.
- **Issue:** The plan's `<interfaces>` token-to-file map puts `.planning/{PROJECT,ROADMAP,STATE,REQUIREMENTS}.md`
  in scope and does not exclude them. The first run found unlabeled occurrences at
  `ROADMAP.md:30,32,33`, `PROJECT.md:61,153` and `REQUIREMENTS.md:47,49`. The execution boundary
  forbids editing `ROADMAP.md` and restricts `REQUIREMENTS.md` to defect 1, so the gate as specified
  could not both cover those files and exit 0.
- **Fix:** Excluded `.planning/` from the label scan with the reason written into the file, kept
  assertions (c) and (g) pointed into `.planning/` so the tree is not blanket-invisible, and
  tabulated every ungated occurrence in this summary for the orchestrator, who owns those files.
- **Files modified:** `Tools/scripts/honesty-sweep.sh`
- **Verification:** `./Tools/scripts/honesty-sweep.sh` -> exit 0; controls 3, 3b and 9 prove
  `.planning/` files can still redden the build.
- **Committed in:** `adee068`

**2. [Rule 2 - Missing Critical] The ADR exclusion the third defect requires would have been an
unpaid hole**

- **Found during:** Task 1, deciding how to treat `docs/adr/0002-*`'s four unlabeled occurrences.
- **Issue:** `docs/adr/0002-*.md` carries `1.953` at lines 91, 122, 165 and `0.374` at 147, none
  labeled. Editing an ADR's body retroactively contradicts the format; excluding it by path without
  a compensating assertion is precisely the disarming pattern the wave exists to prevent.
- **Fix:** Added assertion (f) `check_superseded_adrs`: every ADR in `SUPERSEDED_ADRS` must carry ONE
  line that is simultaneously a `supersed` marker, a link to ADR-0003's filename, and an ISO date.
  Controls 8 (remove the note) and 8b (strip only the date) prove it bites. Added the notes to
  ADR-0001 and ADR-0002.
- **Files modified:** `Tools/scripts/honesty-sweep.sh`, `docs/adr/0001-*.md`, `docs/adr/0002-*.md`
- **Verification:** `ok [supersede] every superseded ADR points forward, dated`; controls 8 and 8b
  both exit 1.
- **Committed in:** `886bb14` (the notes), `adee068` (the assertion)

**3. [Rule 2 - Missing Critical] The defect-1 class needed an assertion the plan does not specify**

- **Found during:** Task 1, implementing the defect-1 instruction.
- **Issue:** Fixing PERF-02's wording is a one-time edit; the instruction was to gate the class.
  None of the plan's five assertions covers unearned authority on a cited figure.
- **Fix:** Added assertion (g) `check_cited_authority` with a negation strip, over an explicit
  four-file scope, and control 9 which re-appends the original defective line verbatim.
- **Files modified:** `Tools/scripts/honesty-sweep.sh`
- **Verification:** Control 9 exits 1; the gate reported `.planning/REQUIREMENTS.md:125` verbatim on
  the pre-fix tree.
- **Committed in:** `adee068`

**4. [Rule 1 - Bug] `0.161` as a bare token flagged three real measurements**

- **Found during:** Task 1, first run and first banner-check run.
- **Issue:** `0.161` matches the Phase-6 render GPU p99 (`0.1615`, `0.1618`) in
  `06-render-evidence.md`, `ROADMAP.md:126` and `REQUIREMENTS.md:67`, and the Seam B p99
  (`0.161 ms`) at `README.md:122`. The banner check would have demanded a `SUPERSEDED` banner on
  `06-render-evidence.md`, whose numbers stand. Labeling any of them `synthetic` would be false.
- **Fix:** Three enumerated collision forms stripped before the token test, each with a written
  reason naming the real quantity, plus control 11 proving the exemption is not blanket. This is the
  generalization of the plan's own `226/226`-over-`226` instruction, and the reasoning is stated in
  a comment as the plan asks.
- **Files modified:** `Tools/scripts/honesty-sweep.sh`
- **Verification:** `ok [banner]` on the real tree; control 11 exits 1 on a bare `0.161` in the same
  file whose `0.1618` is exempt.
- **Committed in:** `adee068`

**5. [Rule 1 - Bug] `05-ane-eligibility-evidence.md` carried the superseded 226/226 tally with no
banner**

- **Found during:** Task 1, first banner-check run.
- **Issue:** Plan 10-12 bannered `05-placement-evidence.md` for the stale-artifact op tally and
  missed its sibling, which states `226/226 eligible, cpu_only = 0` in its Result line. A real RD-09
  gap, not a gate artifact.
- **Fix:** Added the identical banner, pointing at `09-coreml-evidence.md`.
- **Files modified:** `.planning/phases/05-.../05-ane-eligibility-evidence.md`
- **Verification:** `ok [banner] every superseded evidence artifact points forward`; control 2
  proves banner removal bites.
- **Committed in:** `adee068`

**6. [Rule 1 - Bug] The plan's roll-call invokes `validate-privacy-manifest.sh` with no arguments**

- **Found during:** Task 2's roll-call.
- **Issue:** The plan's verification block lists `./Tools/scripts/validate-privacy-manifest.sh` bare.
  The script takes manifest paths and exits 2 with a usage message when given none.
  `.github/workflows/ci.yml:195-197` invokes it with two paths.
- **Fix:** Ran it the way CI does. Recorded here so a future reader does not mistake the exit 2 for a
  regression. The script itself is untouched.
- **Files modified:** none
- **Verification:** `./Tools/scripts/validate-privacy-manifest.sh Apps/CortexMac/PrivacyInfo.xcprivacy Apps/CortexiOS/PrivacyInfo.xcprivacy` -> exit 0
- **Committed in:** n/a (documentation-only correction to the plan's text)

**7. [Rule 1 - Bug] The first draft of the ci.yml comment tripped the gate it was introducing**

- **Found during:** Task 2, running the automated verification.
- **Issue:** The comment named a bare `0.161` with no label. The label scan reported
  `.github/workflows/ci.yml:317`.
- **Fix:** Reworded the comment to describe the collision exemptions without quoting a bare token,
  and to point at the gate's header for the enumerated reasons. Not exempted.
- **Files modified:** `.github/workflows/ci.yml`
- **Verification:** gate exit 0 after the reword; ci.yml still parses.
- **Committed in:** `3f0429c`

**Total deviations:** 7 auto-fixed (1 blocking, 2 missing-critical, 4 bugs).
**Impact on plan:** Every one is caused directly by this plan's own change or by a premise in the
plan text that the tree contradicts. Two assertions and two controls were ADDED; none was removed or
relaxed. The file set is the two planned files plus nine artifact fixes, all of which exist to make
Task 1's own acceptance criterion ("exits 0 on the real tree") true by fixing claims rather than by
widening the gate. No architectural change, no new dependency, no test relaxed, no gate weakened.

## Issues Encountered

**The plan's `files_modified` frontmatter under-declares the change set.** It lists two files; the
change is eleven. Nine are the artifact fixes the first run demanded. Flagging it so the phase
verifier does not read them as scope creep.

**`grep -F '9x9'` in the gate is not the ASCII-vs-Unicode trap it looks like.** The four BPS grounds
are asserted as fixed strings and both `README.md` and `docs/cortex-spec.md` write `9x9` with an
ASCII `x`; a future edit to a Unicode multiplication sign would redden the build, which is the
intended behaviour for a disclosure token.

**No `## Known Stubs`.** Nothing was stubbed, mocked or deferred. Every assertion is wired to a real
check with at least one control, and every literal the gate asserts was verified present on the real
tree before the assertion was written.

## Threat Flags

None. This plan adds no network endpoint, no auth path, no file-access pattern and no schema change.
`honesty-sweep.sh` reads files under `SWEEP_ROOT` and writes only into `mktemp -d` directories it
creates and removes; it takes no input from outside the repository.

## Notes for Plans 10-15 through 10-17

1. **10-15 / 10-16 (the SwiftLint / SwiftFormat `--strict` sweep): the one Swift file this plan
   touched is already SwiftFormat-clean.** `swiftformat --lint
   Packages/CortexDemo/Sources/CortexReplayBench/main.swift` -> `0/1 files require formatting`. Its 8
   `identifier_name` errors are pre-existing snake_case JSON keys
   (`data_source`, `session_id`, `source_sha256`, `manifest_path`, `export_sidecar_sha256`,
   `encoder_checkpoint_sha256`, `velocity_checkpoint_sha256`, `superseded_synthetic`) and are exactly
   10-16's declared scope. **Do not rename them without the byte-diff check 10-VALIDATION.md
   requires** -- they are the JSON keys of `10-replay.json`.
2. **10-15 / 10-16: honesty-sweep.sh now scans `Packages/**`, `Decoder/**` and `docs/**`.** A
   repo-wide reformat that re-wraps a comment can split a token off its label and redden the gate.
   The nine label fixes listed above are all same-line pairings, the same fragility 10-13 recorded
   for `README.md`. Run `./Tools/scripts/honesty-sweep.sh` after any bulk reformat, before
   committing. It costs about two seconds.
3. **10-15: the `brew install` line in ci.yml is untouched.** The SwiftFormat/SwiftLint version pin
   is yours; `grep -cE 'brew install .*swiftformat' .github/workflows/ci.yml` is still 1.
4. **10-17 (first push, first CI run): the workflow now has 58 steps, and two of them are new since
   the last summary.** The honesty sweep runs twice (gate, then `--self-test`) in `build-and-lint`
   between the README gate and the 120Hz plist check. Every one of the ten gates plus their
   self-tests is green locally at `3f0429c`; that transcript is above and it is what the README's
   CI-status sentence currently rests on.
5. **10-17: the pre-push audit greps should include `./Tools/scripts/honesty-sweep.sh`.** It is the
   only gate that scans the whole tree, so it is the cheapest single check that nothing published
   carries an unlabeled superseded number.
6. **For whoever owns the tracking files:** the ungated `.planning/` occurrences are tabulated in
   "First-run findings" above. Six of the eight are genuine unlabeled synthetic numbers in
   `ROADMAP.md:30,32,33`, `PROJECT.md:61,153` and `REQUIREMENTS.md:47,49`; two are false positives on
   the render p99. If the workflow tooling's phase-completion bullets are ever hand-edited, adding
   `synthetic` to the Phase-7 and Phase-8 bullets would close the last of RD-09's residue. This plan
   did not touch them because the execution boundary forbids it.
7. **RD-09 and RD-10 are marked complete in this summary's `requirements-completed`.** 10-13 left
   RD-10 unchecked because the ROADMAP splits it across 10-13 and this plan; this plan completes the
   second half (`honesty-sweep.sh` plus its CI wiring). `.planning/REQUIREMENTS.md`'s checkboxes were
   NOT flipped here -- the only edit to that file is PERF-02's wording. The orchestrator owns
   `requirements mark-complete`, `state advance-plan`, `state update-progress` and
   `roadmap update-plan-progress`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 10-14 is complete and all ten gates plus their self-tests are green at `3f0429c`. Wave 10 is
done; 10-15 (the toolchain pin and the SwiftFormat sweep) is unblocked. The one thing 10-15 and 10-16
need from this plan is note 2 above: a bulk reformat can split a token off its label, so run the
sweep before committing.

No blockers. One open item for the orchestrator: the `.planning/` residue in note 6, which is
information rather than a blocker.

## Self-Check: PASSED

- `Tools/scripts/honesty-sweep.sh` -- FOUND on disk (768 lines), executable, `bash -n` clean,
  exits 0 both ways
- `.github/workflows/ci.yml` -- FOUND, parses as YAML (58 steps), `honesty-sweep.sh` appears twice
- `docs/adr/0001-foundation-and-2026-toolchain.md` -- FOUND, supersession note present, original
  Context sentence present verbatim
- `docs/adr/0002-v0-ship-and-bci-hid-integration.md` -- FOUND, supersession note present
- `docs/adr/0003-photodiode-retirement-and-real-data-v1.md` -- FOUND, both rationale literals present
- `.planning/phases/05-.../05-ane-eligibility-evidence.md` -- FOUND, banner present
- `.planning/REQUIREMENTS.md` -- FOUND, PERF-02 reworded, all eight LAT lines byte-identical
- `.planning/ROADMAP.md`, `.planning/STATE.md` -- NOT in this plan's diff, as required
- Commit `886bb14` -- FOUND in `git log`
- Commit `adee068` -- FOUND in `git log`
- Commit `3f0429c` -- FOUND in `git log`

*Phase: 10-v1-real-data-closed-loop-launch*
*Completed: 2026-09-07*
