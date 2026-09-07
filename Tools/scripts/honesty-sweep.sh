#!/usr/bin/env bash
# Tools/scripts/honesty-sweep.sh -- RD-09 / RD-10 repo-wide labeling and preservation gate.
# Source: project-defined per 10-14-PLAN Task 1, under the honesty ethos (10-RESEARCH "Runtime state
# inventory"). Mirrors EXACTLY the decoder-policy.sh / readme-policy.sh idiom: a build-failing static
# scan for a load-bearing commitment, WITH a negative-control --self-test that proves every check
# bites, so a silently weakened gate reddens CI instead of passing everything.
#
# WHY THIS EXISTS. Plan 10-12 corrected the labels and added the superseded-evidence banners by hand.
# Nothing stopped the next commit from reintroducing a bare 1.953 in the README, deleting LAT-05
# while "tidying" the ROADMAP, or dropping the ADR index link. A one-time editorial sweep survives
# exactly until someone edits a file. This turns RD-09's sweep and RD-10's preservation requirement
# into structure.
#
# ---- WHAT THIS GATE CLAIMS, AND WHAT IT DOES NOT (review D-7, SC#3 scope) --------------------
# The label scan proves a BOUNDED claim: none of the FIVE enumerated superseded tokens appears, in
# the swept tree, on a line that does not also carry a labeling token. That is a tripwire against
# regression, not a completeness proof. A five-token scan cannot establish the universal claim that
# every synthetic figure in the repo is correctly presented -- that claim is carried by the RD-09
# human review plus the provenance gates (decoder-policy.sh, refit-real-policy.sh) which bind each
# PUBLISHED number to the bytes it was measured on. Adding a token to SUPERSEDED_TOKENS is how the
# tripwire grows; it does not make the claim universal, and no comment here should say that it does.
#
# ---- ASSERTIONS (build FAILS on any) ---------------------------------------------------------
#   (a) label      Every occurrence of a SUPERSEDED_TOKEN in the swept tree sits on a line that also
#                  carries a LABEL_TOKEN. Line-scoped, like readme-policy.sh's rule A: a label three
#                  sentences away does not legitimize a bare number a reader will quote alone.
#   (b) banner     Every *-evidence.md under phases 04-08 that names a superseded number also carries
#                  a case-insensitive `supersed` marker, i.e. a forward pointer to what replaced it.
#                  Historical evidence is never retroactively edited; it is bannered. (a) excludes
#                  that tree precisely so (b) can own it.
#   (c) preserve   All eight LAT-01..LAT-08 identifiers survive in BOTH ROADMAP.md and
#                  REQUIREMENTS.md. They are RETIRED, not deleted; deleting one converts a deferral
#                  into an erasure and rewrites what the project said it would do.
#   (d) adr        ADR-0003 exists, carries the four required headings and a Status line, is linked
#                  from the ADR index, AND states the retirement RATIONALE (`hardware-gated`,
#                  `largest credibility hole`). Headings and an index link establish that an ADR was
#                  written, not that it records WHY; SC#5 asks for the why (review D-7).
#   (e) grounds    README.md and docs/cortex-spec.md each state all four grounds of the BPS
#                  non-comparability disclosure, as four fixed tokens.
#   (f) supersede  Every ADR listed in SUPERSEDED_ADRS carries a dated, forward-pointing supersession
#                  note naming ADR-0003's filename. This is what pays for those ADRs being excluded
#                  from (a): an ADR is an immutable decision record, so a stale framing inside one is
#                  corrected by a supersession note, never by a retroactive edit -- the same trade
#                  as (a)-excludes / (b)-asserts for the historical phase tree.
#   (g) authority  No line naming the 8.5 Neuralink P1 figure may frame it with authority the figure
#                  does not have. D-17 settled that 8.5 is RETRIEVED and not independently
#                  sourceable; `verified`, `confirmed`, `independently sourced` and friends assert an
#                  authority no primary supports. This is the class of the 2026-09-07 REQUIREMENTS.md
#                  defect ("Neuralink P1 verified peak"), gated so it cannot come back.
#
# ---- D-09: THIS GATE ASSERTS LABELS AND STRUCTURE, NEVER THE VALUE OF A NUMBER ---------------
# Not one assertion above compares a measured quantity against a bar. D-09 forbids it: a red build on
# a measured finding is pressure to tune that finding, and a gate that can be satisfied by moving a
# number is an incentive to move the number. Every check here is satisfied by TELLING THE TRUTH about
# a number, never by changing it.
#
# ---- self-test (the negative controls) -------------------------------------------------------
#   ./honesty-sweep.sh --self-test
#     builds a CLEAN synthetic tree under mktemp -d that passes, then mutates exactly ONE thing per
#     case and asserts exit 1. Fourteen cases; each mutates one thing, so a passing case proves that
#     one assertion and nothing else. Two of them exist specifically to prove the EXCLUSIONS are not
#     blanket holes: the clean tree deliberately carries unlabeled tokens inside excluded paths and a
#     collision form inside a scanned one (so the baseline passing proves those exemptions are live),
#     and cases 10 and 11 move the same string into a NON-excluded position and require it to bite.
#
#   SWEEP_ROOT=/tmp/tree ./honesty-sweep.sh    # repoint every scope at a stand-in tree
#
# Exit codes:
#   0 -- every superseded occurrence is labeled, every superseded artifact banners its successor,
#        both planning files preserve LAT-01..LAT-08, ADR-0003 is present/linked/reasoned, both
#        published copies state the four non-comparability grounds, the superseded ADRs point
#        forward, and the 8.5 figure is nowhere framed as verified
#   1 -- an assertion failed (see the ERROR lines)

set -euo pipefail

# ---- Scope (overridable so the self-test can repoint at a temp tree) --------------------------
SWEEP_ROOT="${SWEEP_ROOT:-.}"
SWEEP_PHASES_DIR="${SWEEP_PHASES_DIR:-.planning/phases}"
SWEEP_ROADMAP="${SWEEP_ROADMAP:-.planning/ROADMAP.md}"
SWEEP_REQUIREMENTS="${SWEEP_REQUIREMENTS:-.planning/REQUIREMENTS.md}"
SWEEP_ADR_DIR="${SWEEP_ADR_DIR:-docs/adr}"
SWEEP_README="${SWEEP_README:-README.md}"
SWEEP_SPEC="${SWEEP_SPEC:-docs/cortex-spec.md}"
# The files in which the 8.5 Neuralink reference is PUBLISHED or SPECIFIED. Assertion (g) reaches
# into .planning/ on purpose: the 2026-09-07 defect was in a REQUIREMENT's own text, and excluding
# .planning/ from the token scan (see EXCLUDED_PATH_PREFIXES) must not make .planning/ invisible to
# the whole gate. Space-separated so the self-test can repoint it.
SWEEP_CITED_FILES="${SWEEP_CITED_FILES:-README.md docs/cortex-spec.md .planning/REQUIREMENTS.md .planning/PROJECT.md}"

# ---- Constants -------------------------------------------------------------------------------

# Superseded numbers. Each was measured on synthetic data, on an untrained graph, or under a
# defective objective, and each has a real-data replacement. Any occurrence in the swept tree must
# carry a labeling token on the SAME LINE.
#   1.953    the Phase-7/8 ReFIT Webgrid BPS, synthetic seed-locked replay
#   0.374    the Phase-7 ReFIT Fitts throughput, same synthetic replay
#   0.161    the Phase-7 raw-NDT1 Fitts throughput, the ablation's other arm
#   0.3804   the Phase-4 co-bps, produced under the masking defect Plan 09-06b corrected
#   226/226  the Phase-5 ANE op tally, read off a stale compiled artifact; corrected to 239/239
# `226/226` rather than a bare `226`: a bare 226 matches checksums, byte counts, op tallies and line
# numbers, and a gate that cries wolf gets disabled (T-10-14-08). The paired form is how the tally is
# actually written everywhere it is claimed.
SUPERSEDED_TOKENS=("1.953" "0.374" "0.161" "0.3804" "226/226")

# The same set plus 3.471, the Phase-4 palettized co-bps, for the evidence-banner check only. It is
# not in the label scan because it occurs nowhere outside the historical tree.
BANNER_TOKENS=("1.953" "0.374" "0.161" "0.3804" "226/226" "3.471")

# An occurrence is legitimate when its line also carries one of these. Kept short and greppable.
# Do NOT widen this list to clear a failing occurrence: that converts a real finding into a silent
# pass and is the T-10-14-06 threat. Add an entry only with a written reason.
LABEL_TOKENS=("synthetic" "superseded" "Superseded" "Phase-5 baseline" "Phase 5 baseline" \
              "retired" "historical" "stand-in" "fixture")

# Digit-string collisions: literal forms in which a token's digits do NOT name the superseded number.
# Stripped from a line BEFORE the token test. This is NOT a label exemption -- the line is still
# scanned for every other token, and the same digits in any other form still bite (control 11).
# The `226/226` entry in SUPERSEDED_TOKENS is this same disambiguation done inside the token itself;
# 0.161 cannot be disambiguated that way because the Fitts throughput is cited bare, so its
# collisions are enumerated instead:
#   0.1615, 0.1618  the Phase-6 render GPU frame time in ms (M5 Pro, two histogram runs,
#                   06-render-evidence.md). A real measurement that stands; demanding a "synthetic"
#                   label on it would be demanding a lie.
#   0.161 ms        the Seam B p99 latency, 160958 ns rendered in milliseconds (README Seam B
#                   table, Plan 10-06). The Phase-7 Fitts throughput is a bits-per-second figure and
#                   is never written with a millisecond unit.
COLLISION_FORMS=("0.1615" "0.1618" "0.161 ms")

# Paths excluded from the LABEL SCAN, each with its reason. Removing an entry here without
# understanding the reason breaks something real; adding one without a compensating assertion turns
# the gate into a hole.
#   .planning/            The internal planning journal, not a published claim.
#                         .planning/phases/ is HISTORICAL EVIDENCE: per project convention those
#                         artifacts are never retroactively edited, they are BANNERED -- assertion
#                         (b) owns that tree. The .planning/ root tracking files (ROADMAP, STATE,
#                         PROJECT, REQUIREMENTS) are machine-maintained by the workflow tooling,
#                         which rewrites phase-completion bullets and progress rows, so a label added
#                         there by hand is not durable. They are NOT invisible to this gate:
#                         assertion (c) asserts LAT-01..LAT-08 in ROADMAP.md and REQUIREMENTS.md, and
#                         assertion (g) scans REQUIREMENTS.md and PROJECT.md for unearned authority.
#                         RD-09's own criterion names README, ADRs and every *-evidence.md; all three
#                         classes remain in scope.
#   Tools/scripts/        Gate-internal synthetic fixtures. readme-policy.sh's write_clean_readme
#                         carries 226/226 and bps-policy.sh carries 1.953, both as stand-ins their
#                         own self-tests depend on; and this gate must not scan its own token list.
#   docs/adr/0001-, 0002- Superseded ADRs. An ADR is an immutable decision record: a stale framing is
#                         corrected by a dated supersession note pointing at the superseding ADR, not
#                         by editing the original sentence out. Assertion (f) requires that note, so
#                         this exclusion is paid for rather than free. ADR-0003 is NOT excluded -- it
#                         is the current record and its lines must carry their labels.
#   Decoder/scripts/fit_velocity_real.py, Decoder/scripts/rederive_coreml.py,
#   Decoder/tests/test_ane_compute_plan.py
#                         The literal 226 in these three files is a DELIBERATELY PRESERVED Phase-5
#                         baseline string used by Plan 09-08's attribution control, NOT a live claim
#                         (10-RESEARCH "Runtime state inventory": "do not sweep those"). A future
#                         maintainer who "fixes" them destroys that control.
EXCLUDED_PATH_PREFIXES=(
  ".planning/"
  "Tools/scripts/"
  "docs/adr/0001-"
  "docs/adr/0002-"
  "Decoder/scripts/fit_velocity_real.py"
  "Decoder/scripts/rederive_coreml.py"
  "Decoder/tests/test_ane_compute_plan.py"
)

# The ADRs excluded from the label scan above, and therefore required by assertion (f) to carry a
# dated supersession note naming ADR-0003.
SUPERSEDED_ADRS=("0001" "0002")

# ADR-0003 structural requirements.
ADR_HEADINGS=("## Context" "## Decision" "## Consequences" "## Alternatives considered")
# The retirement RATIONALE literals (review D-7, SC#5). ADR-0003 states both under ## Context.
ADR_RATIONALE=("hardware-gated" "largest credibility hole")

# The four grounds of the BPS non-comparability disclosure (review D-4, RD-09). The canonical string
# lives once in WebgridBPS.nonComparabilityDisclosure and a CortexReFIT unit test asserts the
# constant names all four; this is what makes the two PUBLISHED copies build-failing if a prose edit
# drops a ground. Four fixed tokens rather than the whole paragraph, deliberately: a line-wrap
# difference between the README's copy and the spec's must not redden the build, but silently losing
# a ground must. This is a DISCLOSURE check -- it never asserts that any formula changed, because
# bps-policy.sh pins the formula that guards the Phase-7 byte-identity fixture D-09 protects.
BPS_GROUNDS=("log2(N-1)" "9x9" "structurally zero" "click-type")

# ---- Assertion (g) vocabularies, at file scope so they are reviewable in one place ------------
# The figure whose authority is policed. D-17 keeps the 8.5 Neuralink P1 reference but requires it
# dated and sourced as RETRIEVED, and both README.md and docs/cortex-spec.md already say "not
# independently sourceable". An access date does not authenticate a number.
CITED_FIGURE="8.5"
# The closed set of ways English asserts that a figure carries external authority.
CITED_AUTHORITY_RE='(verified|confirmed|independently sourced|peer.reviewed|authenticated|authoritative)'
# Explicit negations, DELETED BEFORE the authority scan, so the honest "not independently sourced"
# survives while "verified peak" does not. Same shape as readme-policy.sh's NEGATION_RE.
CITED_NEGATION_RE='(^|[^a-z])(not|never|no|without)[[:space:]]+(independently[[:space:]]+|been[[:space:]]+)?(verified|confirmed|sourced|peer.reviewed|authenticated|authoritative)'

# ---- strip_collisions: delete every COLLISION_FORM from a string. ----------------------------
# Bash parameter substitution rather than sed: the forms contain `.`, which sed would read as a
# metacharacter, and none of them contains a glob metacharacter (RESEARCH Pitfall 10 -- keep the
# literals literal).
strip_collisions() {
  local s="$1" c
  for c in "${COLLISION_FORMS[@]}"; do
    s="${s//$c/}"
  done
  printf '%s' "$s"
}

# ---- is_excluded: does a repo-relative path start with an excluded prefix? ($1=rel path) -----
is_excluded() {
  local rel="$1" p
  for p in "${EXCLUDED_PATH_PREFIXES[@]}"; do
    case "$rel" in "$p"*) return 0 ;; esac
  done
  return 1
}

# ---- sweep_files: every regular file under SWEEP_ROOT, build and VCS noise pruned. ------------
# `find` rather than `git ls-files` so the self-test's temp tree walks identically to the real one
# and the gate has no VCS dependency. `grep -I` below skips anything binary that survives the prune.
sweep_files() {
  find "$SWEEP_ROOT" \
    \( -name '.git' \
       -o -name '.build' \
       -o -name 'build' \
       -o -name 'DerivedData' \
       -o -name '.bench' \
       -o -name '.venv' \
       -o -name 'node_modules' \
       -o -name 'target' \
       -o -name '*.xcodeproj' \
       -o -name '*.xcworkspace' \
       -o -name '*.mlpackage' \
       -o -name '*.mlmodelc' \
       -o -path "$SWEEP_ROOT/Decoder/data" \
       -o -path "$SWEEP_ROOT/Decoder/checkpoints" \
    \) -prune -o -type f -print 2>/dev/null | LC_ALL=C sort
}

# ---- require_fixed_in_file: assert a FIXED string is PRESENT. ($1=path $2=needle $3=label) ----
require_fixed_in_file() {
  local path="$1" needle="$2" label="$3"
  if [[ ! -f "$path" ]]; then
    echo "ERROR [required-missing] $label: file not found: $path" >&2
    return 1
  fi
  if grep -qF -- "$needle" "$path" 2>/dev/null; then
    return 0
  fi
  echo "ERROR [required-missing] $label: '$needle' not found in $path" >&2
  return 1
}

# ---- check_labels: assertion (a). ------------------------------------------------------------
# One grep per file for all five tokens at once, then a per-line decision in bash: strip the
# collision forms, ask whether a token survives, and if so require a LABEL_TOKEN on the same line.
# grep -F everywhere so `.` in a token stays literal (RESEARCH Pitfall 10).
label_offenders() {
  local f rel hits hit lineno text stripped tok labeled L found
  local -a gargs
  gargs=()
  for tok in "${SUPERSEDED_TOKENS[@]}"; do gargs+=(-e "$tok"); done
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    rel="${f#$SWEEP_ROOT/}"
    is_excluded "$rel" && continue
    hits="$(grep -I -nF "${gargs[@]}" -- "$f" 2>/dev/null || true)"
    [[ -n "$hits" ]] || continue
    while IFS= read -r hit; do
      [[ -n "$hit" ]] || continue
      lineno="${hit%%:*}"
      text="${hit#*:}"
      stripped="$(strip_collisions "$text")"
      found=""
      for tok in "${SUPERSEDED_TOKENS[@]}"; do
        case "$stripped" in *"$tok"*) found="$tok"; break ;; esac
      done
      [[ -n "$found" ]] || continue
      labeled=0
      for L in "${LABEL_TOKENS[@]}"; do
        case "$text" in *"$L"*) labeled=1; break ;; esac
      done
      [[ "$labeled" -eq 0 ]] || continue
      printf '  %s:%s: [%s] %s\n' "$rel" "$lineno" "$found" "$text"
    done <<< "$hits"
  done <<< "$(sweep_files)"
}

check_labels() {
  local offenders
  offenders="$(label_offenders)"
  if [[ -z "$offenders" ]]; then
    echo "  ok  [label] every superseded token in the swept tree carries a label on its own line"
    return 0
  fi
  echo "ERROR [label] a superseded number appears WITHOUT a labeling token on its own line." >&2
  echo "       Labels that legitimize an occurrence: ${LABEL_TOKENS[*]}" >&2
  echo "       Fix the CLAIM (say what the number is), do not widen the label list." >&2
  printf '%s\n' "$offenders" >&2
  return 1
}

# ---- check_banners: assertion (b). -----------------------------------------------------------
# Historical evidence is bannered, never retroactively edited, so the label scan excludes
# .planning/phases/ and this owns it: any *-evidence.md under phases 04-08 that NAMES a superseded
# number must also carry a forward-pointing `supersed` marker saying what replaced it.
check_banners() {
  local rc=0 f content stripped tok hit any=0
  for f in "$SWEEP_PHASES_DIR"/0[4-8]*/*-evidence.md; do
    [[ -f "$f" ]] || continue
    any=1
    content="$(cat "$f")"
    stripped="$(strip_collisions "$content")"
    hit=""
    for tok in "${BANNER_TOKENS[@]}"; do
      case "$stripped" in *"$tok"*) hit="$tok"; break ;; esac
    done
    [[ -n "$hit" ]] || continue
    if grep -qi 'supersed' "$f" 2>/dev/null; then
      continue
    fi
    echo "ERROR [banner] $f names the superseded '$hit' but carries no 'supersed' banner." >&2
    echo "       Historical evidence is never retroactively edited; it gets a forward-pointing" >&2
    echo "       banner naming what replaced the number. See 05-placement-evidence.md." >&2
    rc=1
  done
  if [[ "$any" -eq 0 ]]; then
    echo "ERROR [banner] no *-evidence.md found under $SWEEP_PHASES_DIR/0[4-8]* -- the banner" >&2
    echo "       assertion would pass vacuously, which is worse than failing." >&2
    return 1
  fi
  [[ "$rc" -eq 0 ]] && echo "  ok  [banner] every superseded evidence artifact points forward"
  return $rc
}

# ---- check_lat_preserved: assertion (c). -----------------------------------------------------
# LAT-01..LAT-08 are RETIRED, not deleted. The photodiode path was moved to "Future work (retired
# from v1)" on 2026-08-28 with every identifier preserved verbatim; deleting one would convert a
# deferral into an erasure, i.e. quietly unsay a commitment rather than record that it was dropped.
check_lat_preserved() {
  local rc=0 n id file
  for n in 1 2 3 4 5 6 7 8; do
    id="$(printf 'LAT-0%d' "$n")"
    for file in "$SWEEP_ROADMAP" "$SWEEP_REQUIREMENTS"; do
      if [[ ! -f "$file" ]]; then
        echo "ERROR [preserve] planning file not found: $file" >&2
        rc=1
        continue
      fi
      if ! grep -qF -- "$id" "$file" 2>/dev/null; then
        echo "ERROR [preserve] $id is MISSING from $file. LAT-01..LAT-08 are retired, not" >&2
        echo "       deleted (ADR-0003); removing one erases a commitment instead of recording" >&2
        echo "       that it was deferred." >&2
        rc=1
      fi
    done
  done
  [[ "$rc" -eq 0 ]] && echo "  ok  [preserve] LAT-01..LAT-08 present in both planning files"
  return $rc
}

# ---- adr_0003_path: the ADR-0003 file, or empty. ---------------------------------------------
adr_0003_path() {
  local f
  for f in "$SWEEP_ADR_DIR"/0003-*.md; do
    [[ -f "$f" ]] && { printf '%s' "$f"; return 0; }
  done
  return 0
}

# ---- check_adr: assertion (d). ---------------------------------------------------------------
# Existence, four headings, a Status line, the index link -- and the two RATIONALE literals. The
# rationale check exists because an ADR can carry every required heading and an index entry and
# still say nothing about WHY, and SC#5 asks for the why (review D-7).
check_adr() {
  local rc=0 adr base h lit
  adr="$(adr_0003_path)"
  if [[ -z "$adr" ]]; then
    echo "ERROR [adr] no $SWEEP_ADR_DIR/0003-*.md. The photodiode retirement has no decision" >&2
    echo "       record, so LAT-01..LAT-08 read as abandoned rather than deferred (RD-10)." >&2
    return 1
  fi
  base="$(basename "$adr")"
  for h in "${ADR_HEADINGS[@]}"; do
    require_fixed_in_file "$adr" "$h" "adr: required heading '$h'" || rc=1
  done
  require_fixed_in_file "$adr" '**Status:**' "adr: Status line" || rc=1
  require_fixed_in_file "$SWEEP_ADR_DIR/README.md" "$base" "adr: index links $base" || rc=1
  for lit in "${ADR_RATIONALE[@]}"; do
    require_fixed_in_file "$adr" "$lit" "adr: retirement rationale '$lit' (SC#5)" || rc=1
  done
  [[ "$rc" -eq 0 ]] && echo "  ok  [adr] $base: four headings, Status, index link, both rationale literals"
  return $rc
}

# ---- check_bps_grounds: assertion (e). -------------------------------------------------------
check_bps_grounds() {
  local rc=0 file g
  for file in "$SWEEP_README" "$SWEEP_SPEC"; do
    for g in "${BPS_GROUNDS[@]}"; do
      require_fixed_in_file "$file" "$g" "grounds: '$g' stated in $file (D-4)" || rc=1
    done
  done
  [[ "$rc" -eq 0 ]] && echo "  ok  [grounds] all four BPS non-comparability grounds in the README and the spec"
  return $rc
}

# ---- check_superseded_adrs: assertion (f). ---------------------------------------------------
# The price of excluding docs/adr/0001- and 0002- from the label scan. Each must carry ONE line that
# is simultaneously a supersession marker, a link to ADR-0003's filename, and a date -- so the note
# is dated and forward-pointing rather than a vague "this may be out of date". Requiring all three on
# one line is the same same-line discipline as assertion (a), for the same reason: a reader quotes
# the line, not the paragraph.
check_superseded_adrs() {
  local rc=0 id adr base f found
  base="$(adr_0003_path)"
  if [[ -z "$base" ]]; then
    echo "ERROR [supersede] cannot check supersession notes: ADR-0003 is missing." >&2
    return 1
  fi
  base="$(basename "$base")"
  for id in "${SUPERSEDED_ADRS[@]}"; do
    adr=""
    for f in "$SWEEP_ADR_DIR/$id"-*.md; do
      [[ -f "$f" ]] && adr="$f"
    done
    if [[ -z "$adr" ]]; then
      echo "ERROR [supersede] no $SWEEP_ADR_DIR/$id-*.md, but it is excluded from the label scan" >&2
      echo "       as a superseded ADR. An exclusion for a file that does not exist is a hole." >&2
      rc=1
      continue
    fi
    found="$(grep -i 'supersed' "$adr" 2>/dev/null \
             | grep -F -- "$base" \
             | grep -E '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' || true)"
    if [[ -n "$found" ]]; then
      continue
    fi
    echo "ERROR [supersede] $adr carries no dated supersession note pointing at $base." >&2
    echo "       It is excluded from the label scan BECAUSE it is a superseded decision record;" >&2
    echo "       without the note that exclusion is an unpaid hole. Add one line carrying the" >&2
    echo "       word Superseded, the link $base, and the date -- and leave the original text" >&2
    echo "       in place, because an ADR records what was decided, not what is currently true." >&2
    rc=1
  done
  [[ "$rc" -eq 0 ]] && echo "  ok  [supersede] every superseded ADR points forward, dated"
  return $rc
}

# ---- check_cited_authority: assertion (g). ---------------------------------------------------
# Lowercase the line, delete explicit negations, then look for an authority word. The negation strip
# is what lets "the 8.5 figure is not independently sourceable" pass while "verified peak (8.5 BPS)"
# fails -- a bare word list cannot tell those apart.
check_cited_authority() {
  local rc=0 file hits offenders
  for file in $SWEEP_CITED_FILES; do
    if [[ ! -f "$file" ]]; then
      echo "ERROR [authority] cited-figure file not found: $file" >&2
      rc=1
      continue
    fi
    hits="$(grep -nF -- "$CITED_FIGURE" "$file" 2>/dev/null || true)"
    [[ -n "$hits" ]] || continue
    offenders="$(printf '%s\n' "$hits" \
                 | tr 'A-Z' 'a-z' \
                 | sed -E "s/${CITED_NEGATION_RE}/\1 /g" \
                 | grep -E "$CITED_AUTHORITY_RE" || true)"
    [[ -n "$offenders" ]] || continue
    echo "ERROR [authority] $file frames the $CITED_FIGURE reference as carrying an authority it" >&2
    echo "       does not have. D-17: the figure is RETRIEVED and not independently sourceable to" >&2
    echo "       a Neuralink primary; an access date does not authenticate a number. Say 'cited'" >&2
    echo "       or 'retrieved', not 'verified'. Offending line(s):" >&2
    printf '%s\n' "$offenders" | sed 's|^|         |' >&2
    rc=1
  done
  [[ "$rc" -eq 0 ]] && echo "  ok  [authority] the $CITED_FIGURE reference is nowhere framed as verified"
  return $rc
}

# D-09: no assertion below compares a measured value against a bar.
# ---- scan: run every assertion. Returns 0 only if ALL pass. -----------------------------------
scan() {
  local rc=0
  echo "sweeping tree:        $SWEEP_ROOT"
  echo "  excluded by path:   ${EXCLUDED_PATH_PREFIXES[*]}"
  echo "  banner tree:        $SWEEP_PHASES_DIR/0[4-8]*/*-evidence.md"
  echo "  preservation:       $SWEEP_ROADMAP + $SWEEP_REQUIREMENTS"
  echo "  adr:                $SWEEP_ADR_DIR"

  check_labels           || rc=1   # (a)
  check_banners          || rc=1   # (b)
  check_lat_preserved    || rc=1   # (c)
  check_adr              || rc=1   # (d)
  check_bps_grounds      || rc=1   # (e)
  check_superseded_adrs  || rc=1   # (f)
  check_cited_authority  || rc=1   # (g)

  return $rc
}

# Absolute path to THIS script, so the self-test can re-invoke it with overridden scope
# (the decoder-policy.sh / readme-policy.sh SELF pattern).
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ---- self_test: the negative controls. -------------------------------------------------------
self_test() {
  local fails=0 rc

  # $1 = expected exit, $2 = label, $3 = stand-in tree root.
  assert_exit() {
    local want="$1" label="$2" t="$3"
    set +e
    ( env SWEEP_ROOT="$t" \
          SWEEP_PHASES_DIR="$t/.planning/phases" \
          SWEEP_ROADMAP="$t/.planning/ROADMAP.md" \
          SWEEP_REQUIREMENTS="$t/.planning/REQUIREMENTS.md" \
          SWEEP_ADR_DIR="$t/docs/adr" \
          SWEEP_README="$t/README.md" \
          SWEEP_SPEC="$t/docs/cortex-spec.md" \
          SWEEP_CITED_FILES="$t/README.md $t/docs/cortex-spec.md $t/.planning/REQUIREMENTS.md $t/.planning/PROJECT.md" \
          bash "$SELF" ) >/dev/null 2>&1
    rc=$?
    set -e
    if [[ "$rc" -eq "$want" ]]; then
      echo "  PASS [$label] exit=$rc (expected $want)"
    else
      echo "  FAIL [$label] exit=$rc (expected $want)" >&2
      fails=1
    fi
  }

  # write_clean: a CLEAN stand-in tree that must PASS. Three of its files carry an occurrence that
  # is deliberately NOT labeled, so the baseline passing is itself the positive control for the
  # three exemptions -- and cases 10 and 11 then prove those exemptions are not blanket holes:
  #   docs/adr/0001-a.md      unlabeled 1.953   -> exempt by the superseded-ADR path exclusion
  #   Tools/scripts/fixture.sh unlabeled 226/226 -> exempt by the gate-fixture path exclusion
  #   Packages/Demo/main.swift unlabeled 0.1618  -> exempt by the 0.161 collision form, in a
  #                                                 file that IS scanned
  write_clean() {
    local t="$1"
    mkdir -p "$t/.planning/phases/04-x" "$t/docs/adr" "$t/Tools/scripts" "$t/Packages/Demo"

    {
      printf '# Stand-in README\n\n'
      printf '## Results\n\n'
      printf '| ReFIT | 1.953 | 0.374 | synthetic seed-locked replay |\n'
      printf 'The BPS comparison is not like-for-like: the formula uses log2(N-1) elsewhere, the\n'
      printf 'grid is 9x9 rather than 6x6, incorrect selections are structurally zero here, and the\n'
      printf 'reference task is click-type rather than dwell.\n'
      printf 'Neuralink P1 reference 8.5 BPS: retrieved 2026-09-07, not independently sourceable.\n'
      printf 'Seam B p99 was 160958 ns (0.1618 ms) on this stand-in.\n'
    } > "$t/README.md"

    {
      printf '# Stand-in spec\n\n'
      printf 'BPS non-comparability: log2(N-1), a 9x9 grid, structurally zero incorrect\n'
      printf 'selections, and a click-type reference task.\n'
      printf 'The 8.5 figure is as cited by this repo; not independently sourceable.\n'
    } > "$t/docs/cortex-spec.md"

    {
      printf '# Stand-in evidence\n\n'
      printf '> **Superseded (stand-in banner).** Replaced by the real-data run.\n\n'
      printf 'Observed 0.374 and 0.3804 here.\n'
    } > "$t/.planning/phases/04-x/04-x-evidence.md"

    {
      printf '# Stand-in ROADMAP\n\n'
      printf '### Future work (retired from v1)\n\n'
      printf '**Requirements**: LAT-01, LAT-02, LAT-03, LAT-04\n'
      printf '**Requirements**: LAT-05, LAT-06, LAT-07, LAT-08\n'
    } > "$t/.planning/ROADMAP.md"

    {
      printf '# Stand-in REQUIREMENTS\n\n'
      printf -- '- [ ] LAT-01 LAT-02 LAT-03 LAT-04\n'
      printf -- '- [ ] LAT-05 LAT-06 LAT-07 LAT-08\n'
      printf -- '- [ ] PERF-02: document the path toward the Neuralink P1 cited reference\n'
      printf '      (8.5 BPS, as cited since Phase 7; not independently sourceable)\n'
    } > "$t/.planning/REQUIREMENTS.md"

    {
      printf '# Stand-in PROJECT\n\n'
      printf 'The 8.5 BPS reference is cited, dated and not independently sourceable.\n'
    } > "$t/.planning/PROJECT.md"

    {
      printf '# ADR 0003 -- stand-in\n\n'
      printf '**Status:** Accepted\n\n'
      printf '## Context\n\n'
      printf 'The rig is hardware-gated and was not the largest credibility hole.\n\n'
      printf '## Decision\n\nRetire it; preserve LAT-01 through LAT-08.\n\n'
      printf '## Consequences\n\nScanout stays unquantified.\n\n'
      printf '## Alternatives considered (rejected)\n\nBuy the rig anyway.\n'
    } > "$t/docs/adr/0003-c.md"

    {
      printf '# ADR 0001 -- stand-in\n\n'
      printf '**Status:** Accepted\n'
      printf '**Superseded in part by:** [ADR-0003](0003-c.md), 2026-08-28 -- see below.\n\n'
      printf '## Context\n\nThe headline was 1.953 BPS at the time.\n'
    } > "$t/docs/adr/0001-a.md"

    {
      printf '# ADR 0002 -- stand-in\n\n'
      printf '**Status:** Accepted\n'
      printf '**Superseded in part by:** [ADR-0003](0003-c.md), 2026-08-28 -- see below.\n\n'
      printf '## Context\n\nThe Fitts throughput was 0.374 at the time.\n'
    } > "$t/docs/adr/0002-b.md"

    {
      printf '# ADRs\n\n## Index\n\n'
      printf -- '- [ADR-0001](0001-a.md)\n'
      printf -- '- [ADR-0002](0002-b.md)\n'
      printf -- '- [ADR-0003](0003-c.md)\n'
    } > "$t/docs/adr/README.md"

    {
      printf '#!/usr/bin/env bash\n'
      printf '# A gate-internal stand-in carrying 226/226 with no label, as the real gates do.\n'
      printf 'echo "ANE-eligible 226/226"\n'
    } > "$t/Tools/scripts/fixture.sh"

    {
      printf '// A scanned source file carrying the render p99 collision form.\n'
      printf 'let renderP99Ms = 0.1618\n'
    } > "$t/Packages/Demo/main.swift"
  }

  echo "== honesty-sweep self-test =="
  local t

  # 0. Baseline. Also the POSITIVE control for all three exemptions: the clean tree carries an
  #    unlabeled 1.953 in an excluded ADR, an unlabeled 226/226 in an excluded gate fixture, and an
  #    unlabeled 0.1618 collision form in a file that IS scanned. If any exemption stopped working
  #    this case would fail.
  echo "-- clean synthetic tree (also proves the three exemptions are live) --"
  t="$(mktemp -d)"; write_clean "$t"
  assert_exit 0 "clean tree" "$t"; rm -rf "$t"

  # 1. (a) Strip the `synthetic` label from the 1.953 line -> exit 1.
  echo "-- label negative control --"
  t="$(mktemp -d)"; write_clean "$t"
  sed 's/ | synthetic seed-locked replay |/ | seed-locked replay |/' "$t/README.md" > "$t/r.tmp"
  mv "$t/r.tmp" "$t/README.md"
  assert_exit 1 "1 strip the synthetic label from the 1.953 line" "$t"; rm -rf "$t"

  # 2. (b) Remove the banner from the stand-in evidence file -> exit 1.
  echo "-- banner negative control --"
  t="$(mktemp -d)"; write_clean "$t"
  grep -v 'Superseded' "$t/.planning/phases/04-x/04-x-evidence.md" > "$t/e.tmp"
  mv "$t/e.tmp" "$t/.planning/phases/04-x/04-x-evidence.md"
  assert_exit 1 "2 remove the superseded-evidence banner" "$t"; rm -rf "$t"

  # 3. (c) Delete LAT-05 from the stand-in ROADMAP -> exit 1.
  echo "-- LAT preservation negative controls (both files) --"
  t="$(mktemp -d)"; write_clean "$t"
  sed 's/LAT-05, //' "$t/.planning/ROADMAP.md" > "$t/m.tmp"
  mv "$t/m.tmp" "$t/.planning/ROADMAP.md"
  assert_exit 1 "3 delete LAT-05 from the ROADMAP" "$t"; rm -rf "$t"

  # 3b. (c) Delete LAT-05 from the stand-in REQUIREMENTS -> exit 1. The other half of the pair:
  #     control 3 alone would pass a gate that only ever looked at the ROADMAP.
  t="$(mktemp -d)"; write_clean "$t"
  sed 's/LAT-05 //' "$t/.planning/REQUIREMENTS.md" > "$t/q.tmp"
  mv "$t/q.tmp" "$t/.planning/REQUIREMENTS.md"
  assert_exit 1 "3b delete LAT-05 from REQUIREMENTS" "$t"; rm -rf "$t"

  # 4. (d) Delete the 0003- link from the stand-in ADR index -> exit 1.
  echo "-- ADR negative controls --"
  t="$(mktemp -d)"; write_clean "$t"
  grep -v '0003-c.md' "$t/docs/adr/README.md" > "$t/i.tmp"
  mv "$t/i.tmp" "$t/docs/adr/README.md"
  assert_exit 1 "4 delete the ADR-0003 index link" "$t"; rm -rf "$t"

  # 5. (d) Remove the `## Alternatives considered` heading -> exit 1.
  t="$(mktemp -d)"; write_clean "$t"
  grep -v '## Alternatives considered' "$t/docs/adr/0003-c.md" > "$t/a.tmp"
  mv "$t/a.tmp" "$t/docs/adr/0003-c.md"
  assert_exit 1 "5 remove the Alternatives-considered heading" "$t"; rm -rf "$t"

  # 6. (d) Remove `hardware-gated`, leaving EVERY heading intact -> exit 1. Review D-7 / SC#5d:
  #    proves the gate checks the retirement RATIONALE and not only the structure.
  t="$(mktemp -d)"; write_clean "$t"
  sed 's/hardware-gated/awkward/' "$t/docs/adr/0003-c.md" > "$t/h.tmp"
  mv "$t/h.tmp" "$t/docs/adr/0003-c.md"
  assert_exit 1 "6 remove hardware-gated with every ADR heading intact" "$t"; rm -rf "$t"

  # 7. (e) Remove ONE of the four grounds from the stand-in README -> exit 1 (review D-4).
  echo "-- BPS non-comparability negative control --"
  t="$(mktemp -d)"; write_clean "$t"
  sed 's/structurally zero/not counted/' "$t/README.md" > "$t/g.tmp"
  mv "$t/g.tmp" "$t/README.md"
  assert_exit 1 "7 drop one of the four BPS grounds from the README" "$t"; rm -rf "$t"

  # 8. (f) Remove ADR-0001's supersession note -> exit 1. This is what makes the 0001/0002 path
  #    exclusion paid-for rather than free.
  echo "-- superseded-ADR supersession-note negative controls --"
  t="$(mktemp -d)"; write_clean "$t"
  grep -v 'Superseded in part by' "$t/docs/adr/0001-a.md" > "$t/s.tmp"
  mv "$t/s.tmp" "$t/docs/adr/0001-a.md"
  assert_exit 1 "8 remove ADR-0001's supersession note" "$t"; rm -rf "$t"

  # 8b. (f) Strip only the DATE from ADR-0002's note, leaving the word and the link -> exit 1.
  #     Proves the note must be dated, not merely present.
  t="$(mktemp -d)"; write_clean "$t"
  sed 's/, 2026-08-28 --/ --/' "$t/docs/adr/0002-b.md" > "$t/d.tmp"
  mv "$t/d.tmp" "$t/docs/adr/0002-b.md"
  assert_exit 1 "8b strip the date from ADR-0002's supersession note" "$t"; rm -rf "$t"

  # 9. (g) Reintroduce the 2026-09-07 REQUIREMENTS.md defect verbatim -> exit 1.
  echo "-- cited-figure authority negative control --"
  t="$(mktemp -d)"; write_clean "$t"
  printf -- '- [ ] PERF-02: document the path toward the Neuralink P1 verified peak (8.5 BPS)\n' \
    >> "$t/.planning/REQUIREMENTS.md"
  assert_exit 1 "9 call the 8.5 reference a verified peak" "$t"; rm -rf "$t"

  # 10. THE EXCLUSION IS NOT A BLANKET HOLE. The clean tree passes with an unlabeled 1.953 inside
  #     docs/adr/0001-a.md and an unlabeled 226/226 inside Tools/scripts/fixture.sh. Move the SAME
  #     strings into a file that is NOT excluded and the gate must bite. Without this case an
  #     exclusion and a hole look identical from the outside.
  echo "-- exclusion-is-not-a-hole negative control --"
  t="$(mktemp -d)"; write_clean "$t"
  {
    printf '// The headline was 1.953 BPS at the time.\n'
    printf '// ANE-eligible 226/226\n'
  } >> "$t/Packages/Demo/main.swift"
  assert_exit 1 "10 the same unlabeled strings bite in a NON-excluded file" "$t"; rm -rf "$t"

  # 11. THE COLLISION FORM IS NOT A BLANKET HOLE. The clean tree passes with an unlabeled 0.1618 in
  #     a SCANNED file. Add a bare unlabeled 0.161 to that same file and the gate must bite.
  echo "-- collision-form-is-not-a-hole negative control --"
  t="$(mktemp -d)"; write_clean "$t"
  printf 'let rawFittsThroughput = 0.161\n' >> "$t/Packages/Demo/main.swift"
  assert_exit 1 "11 a bare 0.161 bites in the same file whose 0.1618 is exempt" "$t"; rm -rf "$t"

  if [[ "$fails" -eq 0 ]]; then
    echo "SELF-TEST OK: a clean stand-in tree passes with its three exemptions live; and each of"
    echo "              stripping a label, removing an evidence banner, deleting LAT-05 from either"
    echo "              planning file, unlinking ADR-0003, removing an ADR heading, removing the"
    echo "              retirement rationale with every heading intact, dropping one BPS ground,"
    echo "              removing or undating a superseded ADR's forward pointer, calling the 8.5"
    echo "              reference verified, and moving an excluded string or a collision form into"
    echo "              scanned position -- bites."
    return 0
  else
    echo "SELF-TEST FAILED: at least one negative control did not bite (or the clean tree failed)." >&2
    return 1
  fi
}

# ---- Entry point -----------------------------------------------------------------------------
if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

if scan; then
  echo "OK: honesty sweep clean -- every superseded number in the swept tree is labeled on its own"
  echo "    line, every superseded evidence artifact points forward, LAT-01..LAT-08 survive in both"
  echo "    planning files, ADR-0003 is present, linked and reasoned, both published copies state"
  echo "    all four BPS non-comparability grounds, the superseded ADRs carry dated forward"
  echo "    pointers, and the 8.5 reference is nowhere framed as verified."
  exit 0
else
  echo "honesty-sweep: FAILED -- a labeling or preservation invariant regressed (see ERROR lines)." >&2
  exit 1
fi
