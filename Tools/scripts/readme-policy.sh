#!/usr/bin/env bash
# Tools/scripts/readme-policy.sh -- DIST-04 / D-06 / RD-10 README credibility + no-leak structural gate.
# Source: project-defined per CONTEXT.md "implementer's discretion" (DIST-04) under the honesty ethos
# (RESEARCH §7/§8), rewritten for Phase 10 (RD-10, 10-CONTEXT D-13 + D-14). Mirrors EXACTLY the
# Phase-6 render-policy.sh / Phase-8 notarize-policy.sh / match-policy.sh / Phase-9 decoder-policy.sh
# idiom: a build-failing static grep proxy for a load-bearing commitment, WITH a negative-control
# --self-test that proves every check bites. This is the regression tripwire for the
# credibility-grade README, not its author -- the README is the artifact handed to Bliss
# Chapman / Nir Even-Chen, and over-claiming (or leaking a credential into it) would forge the
# project's credibility. This gate keeps the disclosures present and the secrets absent on every PR.
#
# ── REQUIRED-PRESENT (build-FAILS if a token is ABSENT) ───────────────────────────────────────
# The README must keep publishing, on every commit:
#   - Rejected-alternatives tokens (a representative subset of the table, DIST-04):
#       MLX, _ANEClient, CocoaPods, altool
#   - The verbatim software-timed methodology phrase (D-07): `software-timed pipeline latency`.
#   - The honest-gate disclosure phrases (the load-bearing honesty section -- T-08-06-03):
#       a free/Personal-team-signing phrase, `ANE-eligible`, `synthetic`, `entitlement`.
#   - The Webgrid BPS evidence (PERF-02): the formula token `max(0` AND the `8.5` peak gap (D-17).
#   - The real-data provenance TRIPLE (D-14, RD-10): `indy_20160630_01` (the replayed session id),
#     `9d542cb51d4a` (the real velocity checkpoint's sha256 prefix -- the same 12-hex form as
#     ndt1.real_checkpoint.SHA_PREFIX_LEN and 09-decoder-metrics.json, so the README and the
#     metrics JSON name the same bytes in the same form), and `open-loop replay` (the limitation).
#     A real-data result may not be stated without naming the bytes it came from.
#
# ── RETIRED-CONTEXT-ONLY: the `24.7` figure (D-13, RD-10) ─────────────────────────────────────
# `photodiode` and the flat `24.7` LEFT the required set when v1 was re-pointed (2026-08-28) from
# photodiode-instrumented latency to real-neural-data decoding. In their place the figure is handled
# CONTEXT-SENSITIVELY, and the intent is one sentence: 24.7 ms is citable only as a RETIRED SPEC
# TARGET, never as an achieved measurement. A flat ban would be wrong too -- it would stop the README
# stating the target it is retiring, and that disclosure is itself the honest thing to publish.
#
# THREE rules, each with its own self-test control, all judging the same lowercased view of the file:
#   A  require_marker_on_matching_lines -- every line carrying 24.7 must ALSO carry
#      `retired spec target`, case-INSENSITIVELY. Closes: a case-SENSITIVE marker rejects the honest
#      uppercase sentence.
#   B  forbid_achievement_framing -- no line carrying 24.7 may frame it as an achieved measurement.
#      Scans the WHOLE line (both sides of the number, across table cells) after deleting explicit
#      negations. Closes: a suffix-only, pipe-terminated window misses `We measured 24.7 ...` (verb
#      BEFORE the number) and `| 24.7 ms | measured |` (verb in the next CELL).
#   C  require_needle_under_heading -- every line carrying 24.7 must sit under a Future-work /
#      retired heading. Closes: no earlier design checked the section at all, which is D-13's
#      actual requirement.
#
# WHY THREE RULES AND NOT ONE. An external cross-AI review (2026-09-05, `10-REVIEWS.md` D-1, a
# BLOCKER) EXECUTED a one-and-a-half-rule draft of this check and found it INVERTED: it rejected the
# two honest sentences and PASSED three dishonest ones, including "We measured 24.7 ms on the iPad
# Pro M4, beating the retired spec target." Those eight strings are now pinned as the `--self-test`
# adversarial corpus with their verdicts fixed in advance, in BOTH directions, and ci.yml runs
# `--self-test` beside the gate. A future simplification of these rules therefore REDDENS THE BUILD
# instead of silently re-opening the hole -- the corpus is the regression test for that inversion.
# A gate that PASSES a dishonest sentence is a build failure here, not a warning. Each rule also has
# a case that bites it ALONE (corpus 6 -> A, corpus 8 -> B, corpus 7 -> C), so gutting one rule
# cannot hide behind another still passing.
#
# ── FORBIDDEN-ABSENT (build-FAILS if a token is PRESENT -- no secret / PII leak, T-08-06-02) ───
# None of these may appear in the README (a copy-pasted credential/PII is a leak):
#   A. a PEM private-key header (an ASC `.p8` / signing key block).
#   B. a literal `MATCH_PASSWORD =` assignment (the match passphrase is ENV-only per Plan 04).
#   C. an email address (apple_id / contact PII) -- `<local>@<domain>.<edu|com|org|net>`.
#   D. an App Store Connect issuer-UUID assignment (`issuer ... <uuid>`).
# The forbidden literals are ASSEMBLED AT RUNTIME (printf fragments) so THIS gate file does not
# itself carry the bare token as a standalone literal -- defense against a future tree-wide audit
# grep scanning Tools/scripts/*, and the same discipline as notarize-policy.sh / match-policy.sh.
# The grep still matches the real literal in the README. The --self-test injects a REAL private-key
# header AND a REAL email into a synthetic README to prove the forbidden checks bite.
#
# NOTE on the already-public team ID: the README refers to the developer's free Personal team via
# the placeholder ID `57YW6M29S7`, which is ALREADY committed in project.yml (not a new leak) and
# is NOT an email, a key, a MATCH_PASSWORD literal, or a UUID -- so it does not match any forbidden
# pattern. The forbidden checks target genuine credentials/PII only.
#
# ── CONTROL ACCOUNTING ────────────────────────────────────────────────────────────────────────
# The repo-standing rule this file is the sharpest instance of: a gate whose required set changes
# without its self-test changing IN THE SAME COMMIT is silently disarmed, and nothing else in the
# repo would notice. The arithmetic, recorded here so a future edit has to restate it:
#
#     9 existing controls
#       - 2 removed : `strip photodiode disclosure` and `strip 24.7 v1 target`. Both go because
#                     their REQUIREMENTS went; a control for a check that no longer exists controls
#                     nothing. Removing them is correctness, not a weakening.
#       + 5 added   : 2 for D-13 (corpus case 1, which is a POSITIVE control, and corpus case 3,
#                     a negative one) and 3 for D-14 (one strip control per provenance literal).
#       = 12 non-baseline controls.
#
# `PASS [` lines are a DIFFERENT quantity and must not be conflated with the control count:
#     1 clean baseline + 7 retained controls + 3 D-14 strip controls + 8 adversarial corpus
#     cases = 19 `PASS [` lines.
#
# Self-test:
#   ./readme-policy.sh --self-test   # (i) clean synthetic README -> exit 0; (ii) strip each
#                                    # required disclosure phrase (e.g. `open-loop replay`) -> exit
#                                    # 1; (iii) inject a PEM private-key header / email /
#                                    # MATCH_PASSWORD / issuer UUID -> exit 1; (iv) run the eight
#                                    # adversarial 24.7 sentences, both directions.
#   README_FILE=/tmp/README.md ./readme-policy.sh   # repoint at a temp file
#
# Exit codes:
#   0 -- every required token present, no forbidden token present, and every 24.7 occurrence is a
#        retired-context one
#   1 -- a required token is missing, a forbidden token appears, or 24.7 is framed as achieved

set -euo pipefail

# ── Scope (overridable for the self-test, mirroring notarize-policy.sh's NOTARIZE_SCRIPT idiom) ──
README_FILE="${README_FILE:-README.md}"

# Forbidden literals assembled at runtime so this gate file carries no bare credential/PII token.
# The PEM-header and email patterns are full EREs passed to forbid_regex_in_file below; only the
# MATCH_PASSWORD env-var NAME is assembled here (its forbidden form is an inline `= value` assignment).
MATCH_PW_LITERAL="$(printf 'MATCH_%s' 'PASSWORD')"

# ── D-13 rule-B vocabularies, at file scope so they are greppable and reviewable in one place. ───
# ACHIEVEMENT_RE -- the closed set of ways English frames a number as an achieved result. Closed
# rather than open-ended so the rule stays quiet enough that nobody is ever tempted to disable it.
ACHIEVEMENT_RE='(measur|achiev|instrumented|verified|attained|clocked|beat|delivers|as fast as)'
# NEGATION_RE -- explicit negations, DELETED BEFORE the achievement scan so the honest
# "never measured" survives while "we measured" does not.
NEGATION_RE='(^|[^a-z])(never|not|no|without)[[:space:]]+(been[[:space:]]+)?(measur[a-z]*|achiev[a-z]*|instrumented|verified|attained)'

# ── require_fixed_in_file: assert a FIXED string is PRESENT in the file (missing file/token=FAIL).
# Fixed-string (-F) so regex metachars in a token (e.g. `max(0`) are literal. ($1=path $2=needle $3=label)
require_fixed_in_file() {
  local path="$1" needle="$2" label="$3"
  if [[ ! -f "$path" ]]; then
    echo "ERROR [required-missing] $label: file not found: $path" >&2
    return 1
  fi
  if grep -nF "$needle" "$path" >/dev/null 2>&1; then
    echo "  ok  [required] $label  ($path)"
    return 0
  fi
  echo "ERROR [required-missing] $label: '$needle' not found in $path" >&2
  return 1
}

# ── require_any_in_file: assert AT LEAST ONE of two fixed strings is present (the free-team OR
# Personal-team alternative). ($1=path $2=needleA $3=needleB $4=label) ──────────────────────────
require_any_in_file() {
  local path="$1" a="$2" b="$3" label="$4"
  if [[ ! -f "$path" ]]; then
    echo "ERROR [required-missing] $label: file not found: $path" >&2
    return 1
  fi
  if grep -nF "$a" "$path" >/dev/null 2>&1 || grep -nF "$b" "$path" >/dev/null 2>&1; then
    echo "  ok  [required] $label  ($path)"
    return 0
  fi
  echo "ERROR [required-missing] $label: neither '$a' nor '$b' found in $path" >&2
  return 1
}

# ── forbid_fixed_in_file: assert a FIXED string is ABSENT (a match = FAIL). ($1=path $2=needle $3=label)
forbid_fixed_in_file() {
  local path="$1" needle="$2" label="$3"
  if [[ ! -f "$path" ]]; then
    echo "  ok  [forbidden-absent] $label  ($path missing -> vacuously clean)"
    return 0
  fi
  if grep -nF "$needle" "$path" >/dev/null 2>&1; then
    echo "ERROR [forbidden-present] $label: '$needle' found in $path (a leak)" >&2
    grep -nF "$needle" "$path" >&2 || true
    return 1
  fi
  echo "  ok  [forbidden-absent] $label  ($path)"
  return 0
}

# ── forbid_regex_in_file: assert an ERE is ABSENT (a match = FAIL). ($1=path $2=ERE $3=label) ────
forbid_regex_in_file() {
  local path="$1" pattern="$2" label="$3"
  if [[ ! -f "$path" ]]; then
    echo "  ok  [forbidden-absent] $label  ($path missing -> vacuously clean)"
    return 0
  fi
  if grep -nE "$pattern" "$path" >/dev/null 2>&1; then
    echo "ERROR [forbidden-present] $label: /$pattern/ matched in $path (a leak)" >&2
    grep -nE "$pattern" "$path" >&2 || true
    return 1
  fi
  echo "  ok  [forbidden-absent] $label  ($path)"
  return 0
}

# ── needle_lines_lc: the "NN:text" lines carrying NEEDLE, lowercased. Shared by all three D-13
# rules so they cannot disagree about which lines they are judging. ($1=path $2=needle)
# `tr` is used rather than a sed case flag because BSD and GNU sed disagree about `s///I`, and the
# CI runner is macos-15 with BSD sed / BSD grep 2.6.0-FreeBSD (RESEARCH Pitfall 10).
needle_lines_lc() {
  grep -nF -- "$2" "$1" 2>/dev/null | tr 'A-Z' 'a-z' || true
}

# ── D-13 RULE A -- require_marker_on_matching_lines: every line carrying NEEDLE must ALSO carry
# MARKER, case-INSENSITIVELY. ($1=path $2=needle $3=marker $4=label)
# Case-insensitivity is load-bearing: the 2026-09-05 review showed a case-SENSITIVE version
# REJECTING the honest sentence "... -- RETIRED SPEC TARGET, never measured (Future work)."
require_marker_on_matching_lines() {
  local path="$1" needle="$2" marker="$3" label="$4" nums n marker_lc
  if [[ ! -f "$path" ]]; then
    echo "ERROR [context] $label: file not found: $path" >&2
    return 1
  fi
  marker_lc="$(printf '%s' "$marker" | tr 'A-Z' 'a-z')"
  nums="$(needle_lines_lc "$path" "$needle" | grep -vF -- "$marker_lc" | cut -d: -f1 || true)"
  if [[ -z "$nums" ]]; then
    echo "  ok  [context] $label  ($path)"
    return 0
  fi
  echo "ERROR [context] $label: '$needle' appears WITHOUT '$marker' on:" >&2
  for n in $nums; do sed -n "${n}p" "$path" | sed "s|^|  $n: |"; done >&2
  return 1
}

# ── D-13 RULE B -- forbid_achievement_framing: no line carrying NEEDLE may frame it as an
# achieved measurement, on EITHER side of the number and ACROSS table cells.
# ($1=path $2=needle $3=label)
# Two properties the 2026-09-05 review proved are load-bearing:
#   1. the scan covers the WHOLE line and does NOT stop at `|`. "We measured 24.7 ..." puts the
#      verb BEFORE the number and "| 24.7 ms | measured |" puts it in the next CELL; a
#      suffix-only, pipe-terminated window misses both.
#   2. explicit negations are DELETED BEFORE the scan, so the honest "never measured" survives
#      while "we measured" does not. This is why a bare verb regex cannot do this job: it either
#      false-positives on "never measured" or misses "achieves".
# The `photodiode-instrumented)` strip is narrow ON PURPOSE: that exact hyphenated token followed
# by a closing paren is part of the VERBATIM retired spec-target string the README quotes
# ("(p50, sigma=0.8 ms, n=10k, photodiode-instrumented)"). A bare "instrumented" anywhere else on
# the line still bites -- corpus case 8 proves it.
forbid_achievement_framing() {
  local path="$1" needle="$2" label="$3" nums n
  if [[ ! -f "$path" ]]; then
    echo "  ok  [achievement] $label  ($path missing -> vacuously clean)"
    return 0
  fi
  nums="$(needle_lines_lc "$path" "$needle" \
          | sed -E 's/photodiode-instrumented\)/)/g' \
          | sed -E "s/${NEGATION_RE}/\1 /g" \
          | grep -E "$ACHIEVEMENT_RE" | cut -d: -f1 || true)"
  if [[ -z "$nums" ]]; then
    echo "  ok  [achievement] $label  ($path)"
    return 0
  fi
  echo "ERROR [achievement] $label: '$needle' is framed as an ACHIEVED measurement on:" >&2
  for n in $nums; do sed -n "${n}p" "$path" | sed "s|^|  $n: |"; done >&2
  return 1
}

# ── D-13 RULE C -- require_needle_under_heading: every line carrying NEEDLE must sit under a
# markdown heading whose text matches HEADING_RE (a LOWERCASED ERE).
# ($1=path $2=needle $3=heading-ERE $4=label)
# D-13 says the figure "may appear only under a Future work or retired heading". The 2026-09-05
# review found no draft ever checked that. Lines inside fenced code blocks are STILL scanned for
# the needle; a `#` inside a fence does not become the governing heading.
# `h` is unset until the first heading, and an unset `h` matches no heading pattern, so a needle
# occurring in the preamble before ANY heading is an offender. That is intended.
# Interval expressions such as {1,6} are avoided in the awk program (BSD/GNU awk disagree).
require_needle_under_heading() {
  local path="$1" needle="$2" head_re="$3" label="$4" offenders
  if [[ ! -f "$path" ]]; then
    echo "ERROR [section] $label: file not found: $path" >&2
    return 1
  fi
  offenders="$(awk -v needle="$needle" -v hre="$head_re" '
    /^```/               { fence = 1 - fence; next }
    (fence == 0) && /^#/ { h = tolower($0) }
    index($0, needle) > 0 && h !~ hre { printf "  %d: %s\n", NR, $0 }
  ' "$path")"
  if [[ -z "$offenders" ]]; then
    echo "  ok  [section] $label  ($path)"
    return 0
  fi
  echo "ERROR [section] $label: '$needle' appears outside a /$head_re/ heading on:" >&2
  printf '%s\n' "$offenders" >&2
  return 1
}

# ── scan: run every assertion. Returns 0 only if ALL pass. ──────────────────────────────────────
scan() {
  local rc=0
  echo "scanning README: $README_FILE"

  # REQUIRED-PRESENT — rejected-alternatives subset (DIST-04).
  require_fixed_in_file "$README_FILE" "MLX"          "rejected: MLX (DIST-04)"          || rc=1
  require_fixed_in_file "$README_FILE" "_ANEClient"   "rejected: _ANEClient (DIST-04)"   || rc=1
  require_fixed_in_file "$README_FILE" "CocoaPods"    "rejected: CocoaPods (DIST-04)"    || rc=1
  require_fixed_in_file "$README_FILE" "altool"       "rejected: altool (DIST-04)"       || rc=1

  # REQUIRED-PRESENT — the verbatim software-timed methodology phrase (D-07).
  require_fixed_in_file "$README_FILE" "software-timed pipeline latency" "dual claim: software-timed methodology phrase (D-07)" || rc=1

  # RETIRED-CONTEXT-ONLY -- the photodiode spec target may be NAMED but never CLAIMED (D-13, RD-10).
  # THREE rules, each with its own self-test control. All three must hold on every line carrying the
  # number. The 2026-09-05 external review (10-REVIEWS.md D-1) EXECUTED a one-and-a-half-rule draft
  # and found it inverted: it rejected the honest sentences and passed "We measured 24.7 ms on the
  # iPad Pro M4, beating the retired spec target." Each rule below closes one of the three root causes.
  require_marker_on_matching_lines "$README_FILE" "24.7" "retired spec target" \
    "retired-A: every 24.7 line carries the retirement marker, case-insensitively (D-13)" || rc=1
  forbid_achievement_framing "$README_FILE" "24.7" \
    "retired-B: no achieved framing anywhere on a 24.7 line, either side, across cells (D-13)" || rc=1
  require_needle_under_heading "$README_FILE" "24.7" '(future work|retired)' \
    "retired-C: every 24.7 line sits under a Future-work/retired heading (D-13)" || rc=1

  # REQUIRED-PRESENT — the honest-gate disclosure phrases (the load-bearing honesty section).
  require_any_in_file   "$README_FILE" "Personal team" "free-team" "gate: free/Personal-team signing disclosure" || rc=1
  require_fixed_in_file "$README_FILE" "ANE-eligible" "gate: ANE-eligible-vs-placed disclosure"   || rc=1
  require_fixed_in_file "$README_FILE" "synthetic"    "gate: synthetic-vs-live-human BPS caveat"  || rc=1
  require_fixed_in_file "$README_FILE" "entitlement"  "gate: BCI-HID entitlement request-gating"  || rc=1

  # REQUIRED-PRESENT — Webgrid BPS evidence (PERF-02): the formula token + the 8.5 peak gap.
  require_fixed_in_file "$README_FILE" "max(0"        "Webgrid BPS formula token max(0 (PERF-02)" || rc=1
  require_fixed_in_file "$README_FILE" "8.5"          "Webgrid BPS gap to the 8.5 peak (PERF-02)" || rc=1

  # REQUIRED-PRESENT -- the real-data provenance triple (D-14, RD-10). A real-data result may not be
  # stated without naming the session it came from, the checkpoint bytes, and its limitation.
  require_fixed_in_file "$README_FILE" "indy_20160630_01" \
    "provenance: replayed session id (D-14)" || rc=1
  require_fixed_in_file "$README_FILE" "9d542cb51d4a" \
    "provenance: real velocity-checkpoint sha256 prefix (D-14)" || rc=1
  require_fixed_in_file "$README_FILE" "open-loop replay" \
    "provenance: open-loop-replay disclosure (D-03/D-14)" || rc=1

  # FORBIDDEN-ABSENT — no secret / PII leak (T-08-06-02).
  #   A. PEM private-key header (an ASC .p8 / signing key block).
  forbid_regex_in_file  "$README_FILE" '\-\-\-\-\-BEGIN[ A-Z]*PRIVATE KEY\-\-\-\-\-' "no PEM private-key header (T-08-06-02)" || rc=1
  #   B. a literal `MATCH_PASSWORD =` assignment (passphrase must be ENV-only, never inline).
  forbid_regex_in_file  "$README_FILE" "${MATCH_PW_LITERAL}[[:space:]]*=" "no inline MATCH_PASSWORD assignment (T-08-06-02)" || rc=1
  #   C. an email address (apple_id / contact PII): <local>@<domain>.<tld>.
  forbid_regex_in_file  "$README_FILE" '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(edu|com|org|net)' "no email/PII (T-08-06-02)" || rc=1
  #   D. an App Store Connect issuer-UUID assignment (`issuer ... <uuid>`).
  forbid_regex_in_file  "$README_FILE" 'issuer[^0-9a-f]*[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "no ASC issuer UUID (T-08-06-02)" || rc=1

  return $rc
}

# Absolute path to THIS script (so the self-test can re-invoke it with an overridden README path).
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── self_test: the negative control. Prove the gate BITES on (i) each stripped required disclosure
# and (ii) each injected forbidden secret, prove a clean synthetic README PASSES, and run the D-13
# adversarial corpus in BOTH directions. ────────────────────────────────────────────────────────
self_test() {
  local fails=0 rc

  # $1 = expected exit (0 clean / 1 bite); $2 = label; $3 = README path.
  assert_exit() {
    local want="$1" label="$2" rfile="$3"
    set +e
    ( env README_FILE="$rfile" bash "$SELF" ) >/dev/null 2>&1
    rc=$?
    set -e
    if [[ "$rc" -eq "$want" ]]; then
      echo "  PASS [$label] exit=$rc (expected $want)"
    else
      echo "  FAIL [$label] exit=$rc (expected $want)" >&2
      fails=1
    fi
  }

  # write_clean_readme: a CLEAN synthetic README carrying EVERY required phrase and NO forbidden
  # token. Each negative control then mutates exactly one thing and re-asserts.
  # It carries a real `## Future work` heading and a COMPLIANT 24.7 line so all three D-13 rules are
  # exercised on the baseline rather than passing vacuously. The number and its marker are on ONE
  # line because rule A is a same-line rule. That last line does three jobs at once: it satisfies A
  # (marker on the same line), B (only because BOTH the `photodiode-instrumented)` strip and the
  # `never measured` negation strip fire), and C (it follows the Future work heading).
  # `226/226` stays in the stand-in: honesty-sweep.sh excludes Tools/scripts/ by path precisely
  # because this file carries a gate-internal 226, and that exclusion's written reason must stay true.
  write_clean_readme() {
    local rfile="$1"
    {
      printf '# Synthetic clean README\n\n'
      printf 'Rejected: MLX, _ANEClient, CocoaPods, altool.\n'
      printf 'Claim: software-timed pipeline latency p99 ~8.3ms on the synthetic path.\n'
      printf 'Gates: the developer free-team / Personal team signs the Mac GUI; ANE-eligible 226/226.\n'
      printf 'Caveat: synthetic Indy replay.\n'
      printf 'Distribution: the BCI-HID entitlement is declared-and-gated.\n'
      printf 'Webgrid BPS B = max(0, log2(N)*(Sc-Si)/t); the gap to the 8.5 reference is stated.\n'
      printf 'Real data: open-loop replay of indy_20160630_01, checkpoint 9d542cb51d4a.\n'
      printf '\n## Future work (retired from v1): photodiode-instrumented latency\n\n'
      printf 'Glass-to-glass latency 24.7 +/- 1.3 ms (p50, sigma=0.8 ms, n=10k, photodiode-instrumented) is a retired spec target, never measured. The rig was never built.\n'
    } > "$rfile"
  }

  echo "== readme-policy self-test =="
  local r
  local EMAIL; EMAIL="$(printf 'someone@%s.com' 'example')"             # a real email literal, for injection
  local KEY;   KEY="$(printf -- '-----BEGIN %sPRIVATE KEY-----' '')"    # a real PEM header literal, for injection

  # 0. Baseline: the clean synthetic README must PASS (exit 0).
  echo "-- clean synthetic README --"
  r="$(mktemp)"; write_clean_readme "$r"
  assert_exit 0 "clean README" "$r"; rm -f "$r"

  # 1. REQUIRED negative-controls: strip exactly one required disclosure phrase -> exit 1.
  #    The former 1a `strip photodiode disclosure` and 1c `strip 24.7 v1 target` controls are GONE
  #    because their REQUIREMENTS are gone -- see the control accounting in the header block.
  echo "-- required-disclosure negative controls (strip -> exit 1) --"

  # 1b. Strip the `software-timed pipeline latency` methodology phrase -> exit 1.
  r="$(mktemp)"; write_clean_readme "$r"
  { grep -v 'software-timed pipeline latency' "$r"; } > "$r.tmp" && mv "$r.tmp" "$r"
  assert_exit 1 "strip software-timed methodology phrase" "$r"; rm -f "$r"

  # 1d. Strip the `synthetic` BPS caveat -> exit 1.
  r="$(mktemp)"; write_clean_readme "$r"
  { grep -v 'synthetic' "$r"; } > "$r.tmp" && mv "$r.tmp" "$r"
  assert_exit 1 "strip synthetic BPS caveat" "$r"; rm -f "$r"

  # 1e. Strip the `8.5` peak gap -> exit 1 (PERF-02).
  r="$(mktemp)"; write_clean_readme "$r"
  { sed 's/8\.5//g' "$r"; } > "$r.tmp" && mv "$r.tmp" "$r"
  assert_exit 1 "strip 8.5 peak gap" "$r"; rm -f "$r"

  # 2. FORBIDDEN negative-controls: inject exactly one secret/PII -> exit 1.
  echo "-- forbidden-secret negative controls (inject -> exit 1) --"

  # 2a. Inject a PEM private-key header -> exit 1.
  r="$(mktemp)"; write_clean_readme "$r"
  printf '%s\nMIIEv...\n-----END PRIVATE KEY-----\n' "$KEY" >> "$r"
  assert_exit 1 "inject PEM private-key header" "$r"; rm -f "$r"

  # 2b. Inject an email address -> exit 1.
  r="$(mktemp)"; write_clean_readme "$r"
  printf 'contact: %s\n' "$EMAIL" >> "$r"
  assert_exit 1 "inject email/PII" "$r"; rm -f "$r"

  # 2c. Inject an inline MATCH_PASSWORD assignment -> exit 1.
  r="$(mktemp)"; write_clean_readme "$r"
  printf '%s = hunter2\n' "$(printf 'MATCH_%s' 'PASSWORD')" >> "$r"
  assert_exit 1 "inject inline MATCH_PASSWORD" "$r"; rm -f "$r"

  # 2d. Inject an ASC issuer-UUID assignment -> exit 1.
  r="$(mktemp)"; write_clean_readme "$r"
  printf 'issuer "%s"\n' "11111111-2222-3333-4444-555555555555" >> "$r"
  assert_exit 1 "inject ASC issuer UUID" "$r"; rm -f "$r"

  # 3. D-14 provenance-triple negative controls: strip exactly one literal of the triple -> exit 1.
  #    Each uses sed rather than `grep -v` so the OTHER two literals survive on the same line and
  #    each case isolates the one check it is named for.
  echo "-- D-14 provenance-triple negative controls (strip -> exit 1) --"

  # 3a. Strip the replayed session id -> exit 1.
  r="$(mktemp)"; write_clean_readme "$r"
  { sed 's/indy_20160630_01//g' "$r"; } > "$r.tmp" && mv "$r.tmp" "$r"
  assert_exit 1 "strip indy_20160630_01 session id (D-14)" "$r"; rm -f "$r"

  # 3b. Strip the real velocity-checkpoint sha256 prefix -> exit 1.
  r="$(mktemp)"; write_clean_readme "$r"
  { sed 's/9d542cb51d4a//g' "$r"; } > "$r.tmp" && mv "$r.tmp" "$r"
  assert_exit 1 "strip 9d542cb51d4a checkpoint prefix (D-14)" "$r"; rm -f "$r"

  # 3c. Strip the open-loop-replay disclosure -> exit 1.
  r="$(mktemp)"; write_clean_readme "$r"
  { sed 's/open-loop replay//g' "$r"; } > "$r.tmp" && mv "$r.tmp" "$r"
  assert_exit 1 "strip open-loop replay disclosure (D-14)" "$r"; rm -f "$r"

  # -- D-13 ADVERSARIAL CORPUS (10-REVIEWS.md D-1) -----------------------------------------------
  # The external review EXECUTED an earlier draft of these rules against cases 1-5 and got the exact
  # opposite verdict on every one. These are the regression test for that inversion. A gate that
  # PASSES a dishonest sentence is a BUILD FAILURE here, not a warning.
  echo "-- D-13 adversarial corpus (both directions) --"

  r="$(mktemp)"; write_clean_readme "$r"
  printf 'Glass-to-glass latency 24.7 +/- 1.3 ms -- RETIRED SPEC TARGET, never measured (Future work).\n' >> "$r"
  assert_exit 0 "corpus/1 retired UPPERCASE + never measured -> passes" "$r"; rm -f "$r"

  r="$(mktemp)"; write_clean_readme "$r"
  printf 'The 24.7 ms figure is a RETIRED SPEC TARGET; no photodiode rig was ever built.\n' >> "$r"
  assert_exit 0 "corpus/2 retired UPPERCASE, no achievement verb -> passes" "$r"; rm -f "$r"

  r="$(mktemp)"; write_clean_readme "$r"
  printf 'We measured 24.7 ms on the iPad Pro M4, beating the retired spec target.\n' >> "$r"
  assert_exit 1 "corpus/3 achievement verb BEFORE the number -> bites" "$r"; rm -f "$r"

  r="$(mktemp)"; write_clean_readme "$r"
  printf '| latency | 24.7 ms | measured | retired spec target |\n' >> "$r"
  assert_exit 1 "corpus/4 achievement verb in another table CELL -> bites" "$r"; rm -f "$r"

  r="$(mktemp)"; write_clean_readme "$r"
  printf 'Our achieved latency is 24.7 ms; retired spec target.\n' >> "$r"
  assert_exit 1 "corpus/5 'achieved' inflection -> bites" "$r"; rm -f "$r"

  r="$(mktemp)"; write_clean_readme "$r"
  printf 'Glass-to-glass latency 24.7 +/- 1.3 ms, never measured (Future work).\n' >> "$r"
  assert_exit 1 "corpus/6 marker deleted -> RULE A alone bites" "$r"; rm -f "$r"

  r="$(mktemp)"; write_clean_readme "$r"
  printf '\n## Measured results\n\nGlass-to-glass latency 24.7 +/- 1.3 ms -- RETIRED SPEC TARGET, never measured.\n' >> "$r"
  assert_exit 1 "corpus/7 honest sentence under the WRONG heading -> RULE C alone bites" "$r"; rm -f "$r"

  r="$(mktemp)"; write_clean_readme "$r"
  printf 'We instrumented 24.7 ms on the bench; retired spec target.\n' >> "$r"
  assert_exit 1 "corpus/8 bare 'instrumented' outside the quoted compound -> bites" "$r"; rm -f "$r"

  if [[ "$fails" -eq 0 ]]; then
    echo "SELF-TEST OK: a clean README passes; stripping each required disclosure (software-timed"
    echo "              phrase, synthetic, 8.5, and each of the three D-14 provenance literals) bites;"
    echo "              injecting a private-key header, an email, an inline MATCH_PASSWORD, and an"
    echo "              issuer UUID each bites; and all eight D-13 adversarial sentences yield their"
    echo "              pinned verdict in BOTH directions (retired-context passes, achieved fails)."
    return 0
  else
    echo "SELF-TEST FAILED: at least one negative control did not bite (or the clean README failed)." >&2
    return 1
  fi
}

# ── Entry point ────────────────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

if scan; then
  echo "OK: readme policy clean -- commitments + rejected-alternatives + software-timed phrase +"
  echo "    every gate disclosure + the D-14 provenance triple present; every 24.7 occurrence is a"
  echo "    retired-context one; no private key / MATCH_PASSWORD / email / issuer-UUID leak."
  exit 0
else
  echo "readme-policy: FAILED -- a README disclosure regressed, a secret leaked, or the retired 24.7" >&2
  echo "               figure is presented as achieved (see the ERROR lines above)." >&2
  exit 1
fi
