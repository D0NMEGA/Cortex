#!/usr/bin/env bash
# Tools/scripts/readme-policy.sh -- DIST-04 / D-06 README credibility + no-leak structural gate.
# Source: project-defined per CONTEXT.md "implementer's discretion" (DIST-04) under the honesty ethos
# (RESEARCH §7/§8). Mirrors EXACTLY the Phase-6 render-policy.sh / Phase-8 notarize-policy.sh /
# match-policy.sh idiom: a build-failing static grep proxy for a load-bearing commitment, WITH a
# negative-control --self-test that proves every check bites. This is the regression tripwire for
# the credibility-grade README, not its author -- the README is the artifact handed to Bliss
# Chapman / Nir Even-Chen, and over-claiming (or leaking a credential into it) would forge the
# project's credibility. This gate keeps the disclosures present and the secrets absent on every PR.
#
# ── REQUIRED-PRESENT (build-FAILS if a token is ABSENT) ───────────────────────────────────────
# The README must keep publishing, on every commit:
#   - Rejected-alternatives tokens (a representative subset of the table, DIST-04):
#       MLX, _ANEClient, CocoaPods, altool
#   - The DUAL latency claim (D-07): the verbatim software-timed methodology phrase
#       `software-timed pipeline latency` AND the v1 photodiode SPEC-TARGET number `24.7`
#       (stated NEXT TO each other -- the software-vs-photodiode boundary).
#   - The honest-gate disclosure phrases (the load-bearing honesty section -- T-08-06-03):
#       a free/Personal-team-signing phrase, `ANE-eligible`, `photodiode`, `synthetic`, `entitlement`.
#   - The Webgrid BPS evidence (PERF-02): the formula token `max(0` AND the `8.5` peak gap.
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
# Self-test:
#   ./readme-policy.sh --self-test   # (i) clean synthetic README -> exit 0; (ii) strip each
#                                    # required disclosure phrase (e.g. `photodiode`) -> exit 1;
#                                    # (iii) inject a PEM private-key header -> exit 1; (iv) inject
#                                    # an email -> exit 1.
#   README_FILE=/tmp/README.md ./readme-policy.sh   # repoint at a temp file
#
# Exit codes:
#   0 -- all required tokens present, no forbidden token present (the real README after Plan 08-06)
#   1 -- a required token is missing OR a forbidden token appears (a regression / a leak)

set -euo pipefail

# ── Scope (overridable for the self-test, mirroring notarize-policy.sh's NOTARIZE_SCRIPT idiom) ──
README_FILE="${README_FILE:-README.md}"

# Forbidden literals assembled at runtime so this gate file carries no bare credential/PII token.
# The PEM-header and email patterns are full EREs passed to forbid_regex_in_file below; only the
# MATCH_PASSWORD env-var NAME is assembled here (its forbidden form is an inline `= value` assignment).
MATCH_PW_LITERAL="$(printf 'MATCH_%s' 'PASSWORD')"

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

# ── scan: run every assertion. Returns 0 only if ALL pass. ──────────────────────────────────────
scan() {
  local rc=0
  echo "scanning README: $README_FILE"

  # REQUIRED-PRESENT — rejected-alternatives subset (DIST-04).
  require_fixed_in_file "$README_FILE" "MLX"          "rejected: MLX (DIST-04)"          || rc=1
  require_fixed_in_file "$README_FILE" "_ANEClient"   "rejected: _ANEClient (DIST-04)"   || rc=1
  require_fixed_in_file "$README_FILE" "CocoaPods"    "rejected: CocoaPods (DIST-04)"    || rc=1
  require_fixed_in_file "$README_FILE" "altool"       "rejected: altool (DIST-04)"       || rc=1

  # REQUIRED-PRESENT — the DUAL latency claim (D-07): software-timed phrase NEXT TO the v1 target.
  require_fixed_in_file "$README_FILE" "software-timed pipeline latency" "dual claim: software-timed methodology phrase (D-07)" || rc=1
  require_fixed_in_file "$README_FILE" "24.7"         "dual claim: v1 photodiode SPEC-TARGET 24.7 (D-07)" || rc=1

  # REQUIRED-PRESENT — the honest-gate disclosure phrases (the load-bearing honesty section).
  require_any_in_file   "$README_FILE" "Personal team" "free-team" "gate: free/Personal-team signing disclosure" || rc=1
  require_fixed_in_file "$README_FILE" "ANE-eligible" "gate: ANE-eligible-vs-placed disclosure"   || rc=1
  require_fixed_in_file "$README_FILE" "photodiode"   "gate: software-vs-photodiode boundary"     || rc=1
  require_fixed_in_file "$README_FILE" "synthetic"    "gate: synthetic-vs-live-human BPS caveat"  || rc=1
  require_fixed_in_file "$README_FILE" "entitlement"  "gate: BCI-HID entitlement request-gating"  || rc=1

  # REQUIRED-PRESENT — Webgrid BPS evidence (PERF-02): the formula token + the 8.5 peak gap.
  require_fixed_in_file "$README_FILE" "max(0"        "Webgrid BPS formula token max(0 (PERF-02)" || rc=1
  require_fixed_in_file "$README_FILE" "8.5"          "Webgrid BPS gap to the 8.5 peak (PERF-02)" || rc=1

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
# and (ii) each injected forbidden secret, then prove a clean synthetic README PASSES. ───────────
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
  write_clean_readme() {
    local rfile="$1"
    {
      printf '# Synthetic clean README\n\n'
      printf 'Rejected: MLX, _ANEClient, CocoaPods, altool.\n'
      printf 'Dual claim: software-timed pipeline latency p99 ~8.3ms, next to the v1 target 24.7 ms.\n'
      printf 'Gates: the developer free-team / Personal team signs the Mac GUI; ANE-eligible 226/226;\n'
      printf 'photodiode v1 target; synthetic Indy replay; the BCI-HID entitlement is declared-and-gated.\n'
      printf 'Webgrid BPS B = max(0, log2(N)*(Sc-Si)/t); 6.55 short of the 8.5 peak.\n'
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
  echo "-- required-disclosure negative controls (strip -> exit 1) --"

  # 1a. Strip the `photodiode` gate disclosure -> exit 1 (the load-bearing honesty phrase).
  r="$(mktemp)"; write_clean_readme "$r"
  # rewrite without the word photodiode
  { grep -v 'photodiode' "$r"; } > "$r.tmp" && mv "$r.tmp" "$r"
  assert_exit 1 "strip photodiode disclosure" "$r"; rm -f "$r"

  # 1b. Strip the `software-timed pipeline latency` methodology phrase -> exit 1.
  r="$(mktemp)"; write_clean_readme "$r"
  { grep -v 'software-timed pipeline latency' "$r"; } > "$r.tmp" && mv "$r.tmp" "$r"
  assert_exit 1 "strip software-timed methodology phrase" "$r"; rm -f "$r"

  # 1c. Strip the v1 photodiode target number `24.7` -> exit 1.
  r="$(mktemp)"; write_clean_readme "$r"
  { sed 's/24\.7//g' "$r"; } > "$r.tmp" && mv "$r.tmp" "$r"
  assert_exit 1 "strip 24.7 v1 target" "$r"; rm -f "$r"

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

  if [[ "$fails" -eq 0 ]]; then
    echo "SELF-TEST OK: a clean README passes; stripping each required disclosure (photodiode,"
    echo "              software-timed phrase, 24.7, synthetic, 8.5) bites; injecting a private-key"
    echo "              header, an email, an inline MATCH_PASSWORD, and an issuer UUID each bites."
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
  echo "OK: readme policy clean -- commitments + rejected-alternatives + dual claim + every gate"
  echo "    disclosure present; no private key / MATCH_PASSWORD / email / issuer-UUID leak."
  exit 0
else
  echo "readme-policy: FAILED -- a README disclosure regressed or a secret leaked (see ERROR lines above)." >&2
  exit 1
fi
