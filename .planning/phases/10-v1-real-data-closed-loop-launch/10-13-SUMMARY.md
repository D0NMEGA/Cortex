---
status: PASS
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 13
subsystem: infra
tags: [ci, shell, grep, awk, policy-gate, self-test, adr, honesty-gate]

# Dependency graph
requires:
  - phase: 10-12
    provides: "The rewritten README this gate is asserted over, including its `### Future work (retired from v1)` heading, the D-14 provenance triple text, and the retired-target paragraph"
  - phase: 09
    provides: "`9d542cb51d4a` (the real velocity checkpoint sha256 prefix, SHA_PREFIX_LEN=12) and the four negative leave-one-session-out folds cited in ADR-0003"
  - phase: 08
    provides: "The original readme-policy.sh gate idiom (9 controls, `--self-test`, `README_FILE` override) and ADR-0002's format precedent"
provides:
  - "readme-policy.sh rewritten: `photodiode` and the flat `24.7` are out of the required-present set"
  - "Three independently-controlled D-13 rules over the retired figure: A same-line case-insensitive marker, B whole-line negation-aware achievement scan, C heading scope"
  - "An eight-case adversarial `--self-test` corpus pinning both directions, the regression test for the 10-REVIEWS D-1 inversion"
  - "The D-14 real-data provenance triple as required tokens, each with its own strip control"
  - "ADR-0003, the decision record for retiring LAT-01..LAT-08 and re-pointing v1"
affects: [10-14, 10-15, 10-16, 10-17]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Context-sensitive token policy: a claim may be NAMED but not CLAIMED, enforced by three orthogonal rules rather than one"
    - "Adversarial corpus as a self-test section: verdicts pinned in advance in BOTH directions, so an inverted rule reddens the build"
    - "Rule isolation as an acceptance criterion: each rule has a case that trips it and no other"

key-files:
  created:
    - docs/adr/0003-photodiode-retirement-and-real-data-v1.md
  modified:
    - Tools/scripts/readme-policy.sh
    - docs/adr/README.md
    - README.md
    - .github/workflows/ci.yml

key-decisions:
  - "The README's Future-work paragraph was reflowed so the retired figure and its retirement marker sit on ONE physical line. Rule A is a same-line rule and the plan's premise that the gate would pass on the README unchanged was wrong: the hard wrap at column ~100 had put `24.7` on line 133 and `retired spec target` on line 134. The gate was kept as specified and the artifact was fixed, not the reverse."
  - "The ci.yml comment block introducing this gate was rewritten because it still described `photodiode` and a flat `24.7` as required-present tokens. A stale comment that names the removed tokens actively invites the regression this plan exists to prevent."
  - "RD-10 is NOT marked complete in REQUIREMENTS.md. The ROADMAP splits it across this plan and 10-14 (`honesty-sweep.sh` + CI wiring); marking it now would be inaccurate."

patterns-established:
  - "Pattern 1: a required-set change and its self-test change ship in ONE commit, with the control arithmetic written into the gate's own header so a future edit has to restate it"
  - "Pattern 2: a same-line gate rule is annotated in the policed artifact with an HTML comment, so a future re-wrap does not silently break it"

# REQUIRED - copy ALL requirement IDs from this plan's `requirements` frontmatter field.
requirements-completed: [RD-10]

# Metrics
duration: 55 min
completed: 2026-09-07
---

# Phase 10 Plan 13: Rewrite readme-policy.sh with the three-rule 24.7 gate, plus ADR-0003 Summary

**The retired 24.7 ms figure is now structurally citable only as a retired spec target: three
independently-controlled shell rules (same-line case-insensitive marker, whole-line negation-aware
achievement scan, heading scope) replace the flat required token, with all eight adversarial strings
from the D-1 BLOCKER pinned as named `--self-test` cases in both directions, plus the D-14
provenance triple and ADR-0003 recording why the photodiode path was retired.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-09-07T06:36Z (approx)
- **Completed:** 2026-09-07T07:31:34Z
- **Tasks:** 2 planned, both complete
- **Files modified:** 5 (1 created, 4 modified)

## Accomplishments

- `readme-policy.sh` grew from 286 to 522 lines. `photodiode` and the flat `24.7` left the
  required-present set; the figure is now judged by three orthogonal rules, each with its own
  control, on a shared lowercased view so they cannot disagree about which lines they judge.
- **All eight adversarial strings yield the correct verdict, and each of the three rules is proven
  to bite ALONE.** The two honest sentences the earlier design rejected now pass; the three
  dishonest ones it passed now fail.
- The D-14 provenance triple (`indy_20160630_01`, `9d542cb51d4a`, `open-loop replay`) is required,
  each with its own `sed`-based strip control that leaves the other two literals intact so the case
  isolates the check it is named for.
- ADR-0003 records the retirement rationale in its own words, not just the four headings: the rig is
  `hardware-gated`, and it was not the project's `largest credibility hole`. It names all eight
  LAT identifiers, states the unquantified-scanout consequence as a `lower bound` caveat, and
  rejects five alternatives, the last with the executed transcript that refuted it.

## Task Commits

1. **Task 1: rewrite readme-policy.sh with the three-rule 24.7 gate, the provenance triple, and the
   adversarial corpus** -- `deb874c` (feat). Includes the README reflow that Rule A requires.
2. **Task 2: ADR-0003, why the photodiode path was retired and what replaced it** -- `76d20f3` (docs)
3. **Deviation fix: stale ci.yml comment for the rewritten gate** -- `28197e3` (fix)

## Files Created/Modified

- `Tools/scripts/readme-policy.sh` (286 -> 522 lines) -- the RD-10 rewritten gate: four new helpers
  (`needle_lines_lc`, `require_marker_on_matching_lines`, `forbid_achievement_framing`,
  `require_needle_under_heading`), `ACHIEVEMENT_RE`/`NEGATION_RE` at file scope beside
  `MATCH_PW_LITERAL`, the D-14 triple, a `write_clean_readme` stand-in with a real `## Future work`
  heading, and 12 controls plus the eight-case corpus.
- `docs/adr/0003-photodiode-retirement-and-real-data-v1.md` (144 lines, new) -- the decision record.
- `docs/adr/README.md` (+1 line) -- the index entry. The existing entries and the template are
  byte-identical; the diff is exactly one added line.
- `README.md` (+4/-3) -- the Future-work paragraph reflowed so the figure and its marker are on one
  line, plus a one-line HTML comment recording that same-line constraint.
- `.github/workflows/ci.yml` (+21/-13) -- comments and the step label only; the `run:` block is
  untouched.

## Verification

### The gate, both directions

```
./Tools/scripts/readme-policy.sh              -> exit 0   (against the real README.md at HEAD)
./Tools/scripts/readme-policy.sh --self-test  -> exit 0
grep -c 'PASS \['        -> 19   (expected >= 19)
grep -c 'PASS \[corpus/' ->  8   (expected 8)
grep -c 'FAIL \[corpus/' ->  0   (expected 0)
```

Full `--self-test` transcript:

```
== readme-policy self-test ==
-- clean synthetic README --
  PASS [clean README] exit=0 (expected 0)
-- required-disclosure negative controls (strip -> exit 1) --
  PASS [strip software-timed methodology phrase] exit=1 (expected 1)
  PASS [strip synthetic BPS caveat] exit=1 (expected 1)
  PASS [strip 8.5 peak gap] exit=1 (expected 1)
-- forbidden-secret negative controls (inject -> exit 1) --
  PASS [inject PEM private-key header] exit=1 (expected 1)
  PASS [inject email/PII] exit=1 (expected 1)
  PASS [inject inline MATCH_PASSWORD] exit=1 (expected 1)
  PASS [inject ASC issuer UUID] exit=1 (expected 1)
-- D-14 provenance-triple negative controls (strip -> exit 1) --
  PASS [strip indy_20160630_01 session id (D-14)] exit=1 (expected 1)
  PASS [strip 9d542cb51d4a checkpoint prefix (D-14)] exit=1 (expected 1)
  PASS [strip open-loop replay disclosure (D-14)] exit=1 (expected 1)
-- D-13 adversarial corpus (both directions) --
  PASS [corpus/1 retired UPPERCASE + never measured -> passes] exit=0 (expected 0)
  PASS [corpus/2 retired UPPERCASE, no achievement verb -> passes] exit=0 (expected 0)
  PASS [corpus/3 achievement verb BEFORE the number -> bites] exit=1 (expected 1)
  PASS [corpus/4 achievement verb in another table CELL -> bites] exit=1 (expected 1)
  PASS [corpus/5 'achieved' inflection -> bites] exit=1 (expected 1)
  PASS [corpus/6 marker deleted -> RULE A alone bites] exit=1 (expected 1)
  PASS [corpus/7 honest sentence under the WRONG heading -> RULE C alone bites] exit=1 (expected 1)
  PASS [corpus/8 bare 'instrumented' outside the quoted compound -> bites] exit=1 (expected 1)
SELF-TEST OK: a clean README passes; stripping each required disclosure (software-timed
              phrase, synthetic, 8.5, and each of the three D-14 provenance literals) bites;
              injecting a private-key header, an email, an inline MATCH_PASSWORD, and an
              issuer UUID each bites; and all eight D-13 adversarial sentences yield their
              pinned verdict in BOTH directions (retired-context passes, achieved fails).
```

The two sentences the earlier design REJECTED now pass (corpus/1 and corpus/2). The three it PASSED
now fail (corpus/3, corpus/4, corpus/5). That inversion is the D-1 BLOCKER and it is closed.

### Rule isolation: each of the three rules bites ALONE

Each case was rebuilt against the gate's own `write_clean_readme` stand-in and the reported ERROR
label captured. Exactly one label per case, no overlap:

```
===== corpus/6 marker deleted (expect [context] ONLY) =====
ERROR [context] retired-A
exit=1
===== corpus/8 bare instrumented (expect [achievement] ONLY) =====
ERROR [achievement] retired-B
exit=1
===== corpus/7 wrong heading (expect [section] ONLY) =====
ERROR [section] retired-C
exit=1
```

### Control accounting -- 12, not 14

Two quantities that must not be conflated. Both are written into the gate's own header block so a
future edit has to restate them.

**Control count = 12**, from `9 - 2 + 5`:

- 9 existing controls (1a-1e, 2a-2d).
- **-2 removed:** `strip photodiode disclosure` (1a) and `strip 24.7 v1 target` (1c). Both go
  because their REQUIREMENTS went. `require_fixed_in_file "$README_FILE" "photodiode"` and
  `require_fixed_in_file "$README_FILE" "24.7"` are gone from `scan()`, so a control that strips
  those tokens now controls nothing and would pass vacuously. Removing them is correctness, not a
  weakening. Verified: `grep -cE 'require_fixed_in_file .*"photodiode"'` -> 0 and
  `grep -cE 'require_fixed_in_file .*"24\.7"'` -> 0.
- **+5 added:** 2 for D-13 (corpus/1, which is a POSITIVE control, and corpus/3, a negative one) and
  3 for D-14 (one strip control per provenance literal).

**`PASS [` line count = 19**, a different quantity: 1 clean baseline + 7 retained controls
(1b, 1d, 1e, 2a, 2b, 2c, 2d) + 3 D-14 strip controls + 8 adversarial corpus cases. Measured: 19.
The count matches the plan; nothing was padded. The string `14` does not appear as a control count
anywhere in the script, this summary or the commit bodies (only as the decision ID `D-14`); verified
with `grep -nE '(^|[^0-9-])14([^0-9]|$)' | grep -v 'D-14'` -> 0 lines.

### Non-regression on the surviving checks

```
grep -cF '"8.5"'                            -> 1  (baseline 1, unchanged; D-17 keeps the token)
grep -cF 'software-timed pipeline latency'  -> 5  (baseline 5, unchanged)
grep -cF '[^|]{0,80}'                       -> 0  (the refuted suffix-only window is absent)
grep -cF "tr 'A-Z' 'a-z'"                   -> 2  (case-insensitivity implemented, not assumed)
grep -cF 'require_marker_on_matching_lines' -> 4  (definition + call + comments)
grep -cF 'forbid_achievement_framing'       -> 4
grep -cF 'require_needle_under_heading'     -> 4
grep -cF 'indy_20160630_01'                 -> 5  (requirement + strip control + prose)
grep -cF '9d542cb51d4a'                     -> 5
grep -cF 'open-loop replay'                 -> 6
grep -cF '## Future work'                   -> 2  (the stand-in has the heading rule C needs)
```

All four forbidden-absent regexes (PEM header, MATCH_PASSWORD, email, ASC issuer UUID) and their
four controls are byte-identical to HEAD.

### All six policy gates, with and without `--self-test`

```
readme-policy.sh                       exit=0
readme-policy.sh --self-test           exit=0
bps-policy.sh                          exit=0
bps-policy.sh --self-test              exit=0
render-policy.sh                       exit=0
render-policy.sh --self-test           exit=0
hid-surface-policy.sh                  exit=0
hid-surface-policy.sh --self-test      exit=0
decoder-policy.sh                      exit=0
decoder-policy.sh --self-test          exit=0
refit-real-policy.sh                   exit=0
refit-real-policy.sh --self-test       exit=0
```

### Test suites

```
uv sync --project Decoder --extra dev
uv run --project Decoder pytest Decoder/tests -m "not slow" -q
  -> 288 passed, 1 skipped, 10 deselected, 1 warning in 21.78s
     (the skip is test_data.py:157, "no loadable real .mat present (dataset is gitignored)")

swift test --package-path Packages/CortexDemo   -> 44 tests in 5 suites passed
swift test --package-path Packages/CortexReFIT  -> 32 tests in 5 suites passed
swift test --package-path Packages/CortexRender -> 19 tests in 4 suites passed
```

Every count matches the expectation stated in the plan.

### ADR-0003

```
lines                             : 144  (plan minimum 90)
## Context / ## Decision / ## Consequences / ## Alternatives considered : 1 each
**Status:**                       : 1
LAT-01..LAT-08                    : all eight named
hardware-gated (inside ## Context): True
largest credibility hole (## Context): True
lower bound (inside ### Negative) : True
04-training-evidence.md           : 2
alternatives rows                 : 5
non-ASCII                         : none
docs/adr/README.md index entry    : 1 (diff is exactly the one added line)
```

### LAT-01 through LAT-08 preserved verbatim

Confirmed present and unmodified. `.planning/ROADMAP.md` lines 266 and 273 carry
`**Requirements**: LAT-01, LAT-02, LAT-03, LAT-04` and
`**Requirements**: LAT-05, LAT-06, LAT-07, LAT-08` under "Future work (retired from v1)", and
`.planning/REQUIREMENTS.md` carries all eight checkbox lines with LAT-07's verbatim spec-target
wording. Neither file appears in this plan's diff (`git diff --numstat e71f09c..HEAD` lists only
`ci.yml`, `README.md`, `readme-policy.sh`, the new ADR and the ADR index), so preservation is
structural rather than asserted.

## Decisions Made

1. **The gate was kept as specified and the README was fixed, not the reverse.** See deviation 1.
   The plan's `<interfaces>` design was executed-verified by the planner before being written down;
   when it disagreed with the artifact, the artifact was the thing that was wrong.
2. **A one-line HTML comment now records the same-line constraint in the README itself.** Following
   the existing `<!-- CI-STATUS-CLAIM: ... -->` idiom at README line 32. Without it the next person
   who runs a prose re-wrap over that paragraph reintroduces exactly this failure with no warning
   until CI turns red. The comment deliberately avoids the tokens `24.7` and `retired spec target`
   so it cannot itself become a subject of the rules.
3. **RD-10 is not marked complete.** ROADMAP line 226 assigns the rest of RD-10 (and RD-09) to Plan
   10-14's `honesty-sweep.sh` and its CI wiring. `.planning/REQUIREMENTS.md` was left untouched.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The gate failed on the real README at HEAD: a hard wrap split Rule A's
same-line pairing**

- **Found during:** Task 1, at the acceptance-criterion check "the gate exits 0 on the real README".
- **Issue:** The plan states the gate "must pass on it unchanged". It did not. Rule A requires every
  line carrying `24.7` to also carry `retired spec target` on the SAME line, but README lines 133-135
  were wrapped at column ~100, putting the figure on line 133 and the marker on line 134. Observed
  failure, verbatim:

  ```
  ERROR [context] retired-A: every 24.7 line carries the retirement marker, case-insensitively
  (D-13): '24.7' appears WITHOUT 'retired spec target' on:
    133: Glass-to-glass latency 24.7 +/- 1.3 ms (p50, sigma=0.8 ms, n=10k, photodiode-instrumented) is a
  ```

  Rules B and C both reported `ok` on the same file, so this was purely the wrap, not a content
  problem. The plan's premise was factually wrong; the rule was not.
- **Fix:** Reflowed the paragraph so the figure and the marker share one physical line, and added a
  one-line HTML comment above it recording the same-line constraint. Every word of the paragraph is
  preserved and the rendered Markdown is unchanged (a soft line break inside a paragraph renders as
  a space). The alternative, weakening Rule A to a paragraph-scoped check, was rejected: the plan
  pins the design as executed-verified and says explicitly to fix the implementation rather than the
  expected verdict, and a paragraph-scoped marker rule would let a marker three sentences away
  legitimize an achieved-looking line.
- **Files modified:** `README.md`
- **Verification:** `./Tools/scripts/readme-policy.sh` -> exit 0 with all three D-13 rules reporting
  `ok`; all 21 assertion lines green; `--self-test` still exits 0.
- **Committed in:** `deb874c` (Task 1 commit, same commit as the gate itself)

**2. [Rule 1 - Bug] The ci.yml comment introducing this gate still described the pre-RD-10 required
set**

- **Found during:** Post-Task-2 verification of the CI invocation contract.
- **Issue:** `.github/workflows/ci.yml` lines 272-285 described the gate as asserting "the DUAL
  latency claim (the verbatim `software-timed pipeline latency` phrase NEXT TO the v1 photodiode
  SPEC-TARGET `24.7`)" and "the honest-gate disclosure (... ANE-eligible, photodiode, synthetic,
  entitlement)", and named "the disclosure-strip (photodiode/software-timed/24.7/synthetic/8.5)"
  negative controls. All of that became false in commit `deb874c`. A comment that names the removed
  tokens as required is not cosmetic drift: it is an instruction to a future maintainer to restore
  precisely what the v1 re-point removed.
- **Fix:** Rewrote the comment block to describe the new required set, the three context rules and
  what each closes, the D-14 triple, the eight-case corpus and the threats it covers, with an
  explicit "Do not 'restore' the old required tokens." line. Added `RD-10` to the step label.
- **Files modified:** `.github/workflows/ci.yml`
- **Verification:** `git diff` filtered to non-comment lines shows exactly one changed line, the
  step `name:`. The `run:` block, the bare-gate + `--self-test` invocation contract and the
  `README_FILE` env override are untouched. `ci.yml` still parses as YAML.
- **Committed in:** `28197e3`

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug).
**Impact on plan:** Both were caused directly by this plan's own change and both are strictly
in-scope. No scope creep: the file set is the three planned files plus `README.md` (required to make
Task 1's own acceptance criterion true) and a comment-only edit to `ci.yml`. No architectural change,
no new dependency, no test relaxed.

## Issues Encountered

**The plan's `files_modified` frontmatter under-declares the change set.** It lists three files; the
change is five. `README.md` was unavoidable (deviation 1) and `ci.yml` was a comment-only correction
(deviation 2). Flagging it so the phase verifier does not read the extra files as scope creep.

**No `## Known Stubs`.** Nothing was stubbed, mocked or deferred inside either task. Every rule in
the gate is wired to a real check with a real control, and every literal in ADR-0003 is sourced.

## Notes for Plans 10-14 through 10-17

1. **`honesty-sweep.sh` (10-14) can assert both ADR rationale literals as planned.**
   `grep -cF 'hardware-gated' docs/adr/0003-photodiode-retirement-and-real-data-v1.md` -> 2 and
   `grep -cF 'largest credibility hole' ...` -> 2, both inside `## Context`, in the exact form the
   plan specified.
2. **If 10-14's sweep applies any 24.7 rule repo-wide, scope it by path.** ADR-0003 quotes the D-1
   transcript verbatim inside a fenced code block, including the line
   `PASS  We measured 24.7 ms on the iPad Pro M4, beating the retired spec target.` That is an
   adversarial test string quoted as evidence, labelled as such in the surrounding prose, and it
   would trip a naive repo-wide Rule B. `Tools/scripts/readme-policy.sh` carries the same eight
   strings for the same reason. The `Tools/scripts/` path exclusion that 10-14 already plans (for the
   gate-internal `226`) covers the script; `docs/adr/0003-*` would need the same treatment, or the
   rule stays scoped to `README.md` as it is today. The gate's own heading rule (C) is also
   README-shaped and does not transfer to an ADR whose headings are Context/Decision/Consequences.
3. **`ADR-0001` still carries a stale framing that RD-09 should catch.** Its `## Context` says "The
   defining project claim is 'Glass-to-glass latency 24.7 +/- 1.3 ms (p50, sigma=0.8 ms, n=10k,
   photodiode-instrumented)'. Every architectural choice in this ADR serves that claim." That was
   true in Phase 1 and is false after the 2026-08-28 re-point. ADR-0003's References section notes
   the supersession in prose, which is the ADR-format-correct way to handle it, but the sentence in
   0001 itself is untouched. Out of scope here; 10-14's RD-09 sweep is the right owner.
4. **`README.md` line 133 is now load-bearing at the line level.** The HTML comment above it says so.
   Any plan that re-wraps the Future-work paragraph must keep the figure and `retired spec target`
   together or `readme-policy.sh` fails. This is the intended trade: a same-line rule cannot be
   satisfied by a marker on an adjacent line without becoming much weaker.
5. **Control and PASS-line counts are now pinned in three places** (the gate header, this summary,
   and the plan's acceptance criteria): 12 controls, 19 `PASS [` lines. `10-VALIDATION.md` asserted
   `>= 14` controls before the D-2 correction; if a stale `>= 14` survives anywhere in the phase
   artifacts it will contradict the corrected arithmetic.
6. **RD-10 is left unchecked in `.planning/REQUIREMENTS.md`** and no tracking file was touched.
   `.planning/ROADMAP.md` and `.planning/STATE.md` were not edited, per the execution boundary. The
   orchestrator owns advancing the plan counter, the progress bar and the ROADMAP row, and owns the
   decision of whether RD-10 flips after 10-14 completes its half.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 10-13 is complete and every gate in the repo is green. Wave 9 is done; 10-14 (`honesty-sweep.sh`
plus its CI wiring, RD-09/RD-10) is unblocked and has what it needs from this plan: the ADR literals
it asserts, the LAT preservation it checks, and the `Tools/scripts/` exclusion rationale it depends
on (the gate stand-in still carries `226/226`, so that exclusion's written reason remains true).

No blockers. One open item for the orchestrator: the requirement-tracking decision in note 6.

## Self-Check: PASSED

- `docs/adr/0003-photodiode-retirement-and-real-data-v1.md` -- FOUND on disk (144 lines)
- `Tools/scripts/readme-policy.sh` -- FOUND on disk (522 lines), `bash -n` clean, exits 0 both ways
- `docs/adr/README.md` -- FOUND, index entry present exactly once
- `README.md` -- FOUND, gate exits 0 against it
- `.github/workflows/ci.yml` -- FOUND, parses as YAML, invocation contract intact
- Commit `deb874c` -- FOUND in `git log`
- Commit `76d20f3` -- FOUND in `git log`
- Commit `28197e3` -- FOUND in `git log`

*Phase: 10-v1-real-data-closed-loop-launch*
*Completed: 2026-09-07*
