#!/usr/bin/env bash
# Tools/scripts/match-policy.sh -- DIST-02 / DIST-03 / D-06 match + TestFlight pipeline gate.
# Source: project-defined per CONTEXT.md D-06. Mirrors EXACTLY the render-policy.sh / hotpath-policy.sh
# idiom (build-failing static grep proxy + biting negative-control --self-test). This is the
# regression tripwire for the signing/distribution config, and it directly mirrors the Phase-1
# threat-model grep T-01-04-01 (no cert/URL leak) -- now hardened for the appstore swap (T-08-04-02/03).
#
# ── REQUIRED-PRESENT (build-FAILS if a token is ABSENT) ───────────────────────────────────────
#   1. type("appstore")           (Matchfile) -- appstore-signed builds for TestFlight (DIST-02/03).
#   2. an https:// git_url         (Matchfile) -- the PRIVATE certs repo over https (NOT a local
#                                   disk URL, NOT ssh) (DIST-02).
#   3. ENV["MATCH_PASSWORD"]       (Matchfile OR Fastfile) -- the match passphrase is read from ENV,
#                                   never a literal (T-08-04-03).
#
# ── FORBIDDEN (build-FAILS if a token is PRESENT) ─────────────────────────────────────────────
#   A. NO local-disk git URL scheme in the Matchfile -- a stale local mirror (the P1 placeholder
#      form) would not carry the appstore certs and re-opens the leak surface (T-08-04-02).
#   B. NO ssh git_url form (git@github.com:) in the Matchfile -- implies a deploy-key path leak and
#      bypasses the https token check (T-08-04-02).
#   C. NO literal MATCH_PASSWORD assignment anywhere in the Matchfile/Fastfile -- i.e. neither
#      `MATCH_PASSWORD = "…"` nor `MATCH_PASSWORD("…")`. The passphrase must come from ENV
#      (T-08-04-03). (The policed files describe these forbidden forms by INTENT in comments, never
#      as a bare assignment; the --self-test injects the REAL literal to prove the gate bites.)
#   D. NO ENV-default password literal: `ENV["MATCH_PASSWORD"] || "…"` (a hardcoded fallback secret).
#
# Self-test:
#   ./match-policy.sh --self-test   # clean tree -> 0; inject local-disk URL -> 1; downgrade
#                                   # appstore->development -> 1; drop the https git_url -> 1;
#                                   # inject a literal MATCH_PASSWORD = "secret" -> 1.
#   MATCHFILE=/tmp/Matchfile FASTFILE=/tmp/Fastfile ./match-policy.sh   # repoint at a temp tree
#
# Exit codes:
#   0 -- required tokens present, forbidden tokens absent (the real tree after Plan 08-04 Task 1)
#   1 -- a required token is missing OR a forbidden token appears (a regression)

set -euo pipefail

# ── Scope (overridable for the self-test) ───────────────────────────────────────────────────────
MATCHFILE="${MATCHFILE:-fastlane/Matchfile}"
FASTFILE="${FASTFILE:-fastlane/Fastfile}"

# The forbidden local-disk URL scheme literal is assembled at runtime so this gate file does not
# itself contain the bare token as prose (defense against a future tree-wide audit grep). The grep
# still matches the real literal in any policed file.
LOCAL_URL_SCHEME="$(printf 'fi%s://' 'le')"

# ── require_in_file: assert an ERE is PRESENT in a file (missing file/token = FAIL). ────────────
require_in_file() {
  local path="$1" pattern="$2" label="$3"
  if [[ ! -f "$path" ]]; then
    echo "ERROR [required-missing] $label: file not found: $path" >&2
    return 1
  fi
  if grep -nE "$pattern" "$path" >/dev/null 2>&1; then
    echo "  ok  [required] $label  ($path)"
    return 0
  fi
  echo "ERROR [required-missing] $label: '$pattern' not found in $path" >&2
  return 1
}

# ── require_in_either: assert an ERE is PRESENT in $1 OR $2 (used for MATCH_PASSWORD-from-ENV,
# which may live in the Matchfile comment or the Fastfile guard). ($1,$2=files, $3=ERE, $4=label) ─
require_in_either() {
  local a="$1" b="$2" pattern="$3" label="$4"
  if grep -nE "$pattern" "$a" >/dev/null 2>&1 || grep -nE "$pattern" "$b" >/dev/null 2>&1; then
    echo "  ok  [required] $label  ($a|$b)"
    return 0
  fi
  echo "ERROR [required-missing] $label: '$pattern' not found in $a or $b" >&2
  return 1
}

# ── forbid_fixed_in_file: assert a FIXED string is ABSENT (a match = FAIL). Missing file = clean. ─
forbid_fixed_in_file() {
  local path="$1" needle="$2" label="$3"
  if [[ ! -f "$path" ]]; then
    echo "  ok  [forbidden-absent] $label  ($path missing -> vacuously clean)"
    return 0
  fi
  if grep -nF "$needle" "$path" >/dev/null 2>&1; then
    echo "ERROR [forbidden-present] $label: '$needle' found in $path" >&2
    grep -nF "$needle" "$path" >&2 || true
    return 1
  fi
  echo "  ok  [forbidden-absent] $label  ($path)"
  return 0
}

# ── forbid_ere_in_file: assert an ERE is ABSENT (a match = FAIL). Missing file = clean. ──────────
forbid_ere_in_file() {
  local path="$1" pattern="$2" label="$3"
  if [[ ! -f "$path" ]]; then
    echo "  ok  [forbidden-absent] $label  ($path missing -> vacuously clean)"
    return 0
  fi
  if grep -nE "$pattern" "$path" >/dev/null 2>&1; then
    echo "ERROR [forbidden-present] $label: '$pattern' found in $path" >&2
    grep -nE "$pattern" "$path" >&2 || true
    return 1
  fi
  echo "  ok  [forbidden-absent] $label  ($path)"
  return 0
}

# ── scan: run every assertion. Returns 0 only if ALL pass. ──────────────────────────────────────
scan() {
  local rc=0
  echo "scanning Matchfile: $MATCHFILE"
  echo "scanning Fastfile:  $FASTFILE"

  # REQUIRED-PRESENT (1-3).
  require_in_file "$MATCHFILE" 'type\("appstore"\)'                         "type(appstore) present (DIST-02/03)" || rc=1
  require_in_file "$MATCHFILE" 'git_url\([^)]*https://'                      "https:// git_url present (DIST-02)" || rc=1
  require_in_either "$MATCHFILE" "$FASTFILE" 'ENV\[["'\'']MATCH_PASSWORD'    "MATCH_PASSWORD from ENV (T-08-04-03)" || rc=1

  # FORBIDDEN (A-D).
  #   A. no local-disk git URL scheme in the Matchfile.
  forbid_fixed_in_file "$MATCHFILE" "$LOCAL_URL_SCHEME" "no local-disk git URL in Matchfile (T-08-04-02)" || rc=1
  #   B. no ssh git_url form in the Matchfile.
  forbid_ere_in_file "$MATCHFILE" 'git@github\.com:'   "no ssh git_url in Matchfile (T-08-04-02)" || rc=1
  #   C. no literal MATCH_PASSWORD assignment in EITHER file (=, ||= , or paren-call with a string).
  forbid_ere_in_file "$MATCHFILE" 'MATCH_PASSWORD[[:space:]]*=[[:space:]]*["'\'']' "no literal MATCH_PASSWORD= in Matchfile (T-08-04-03)" || rc=1
  forbid_ere_in_file "$FASTFILE"  'MATCH_PASSWORD[[:space:]]*=[[:space:]]*["'\'']' "no literal MATCH_PASSWORD= in Fastfile (T-08-04-03)" || rc=1
  forbid_ere_in_file "$MATCHFILE" 'MATCH_PASSWORD\(["'\'']'                         "no MATCH_PASSWORD(\"…\") call in Matchfile (T-08-04-03)" || rc=1
  forbid_ere_in_file "$FASTFILE"  'MATCH_PASSWORD\(["'\'']'                         "no MATCH_PASSWORD(\"…\") call in Fastfile (T-08-04-03)" || rc=1
  #   D. no hardcoded ENV-default password literal: ENV["MATCH_PASSWORD"] || "secret".
  forbid_ere_in_file "$MATCHFILE" 'MATCH_PASSWORD["'\'']?\][[:space:]]*\|\|[[:space:]]*["'\'']' "no ENV-default password literal in Matchfile (T-08-04-03)" || rc=1
  forbid_ere_in_file "$FASTFILE"  'MATCH_PASSWORD["'\'']?\][[:space:]]*\|\|[[:space:]]*["'\'']' "no ENV-default password literal in Fastfile (T-08-04-03)" || rc=1

  return $rc
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── self_test: prove every check bites; prove a clean tree passes. ──────────────────────────────
self_test() {
  local fails=0 rc

  assert_exit() {
    local want="$1" label="$2" mfile="$3" ffile="$4"
    set +e
    ( env MATCHFILE="$mfile" FASTFILE="$ffile" bash "$SELF" ) >/dev/null 2>&1
    rc=$?
    set -e
    if [[ "$rc" -eq "$want" ]]; then
      echo "  PASS [$label] exit=$rc (expected $want)"
    else
      echo "  FAIL [$label] exit=$rc (expected $want)" >&2
      fails=1
    fi
  }

  # write_clean_tree: a CLEAN synthetic Matchfile (appstore + https git_url, no local-disk URL, no
  # literal password) + a CLEAN synthetic Fastfile (references ENV["MATCH_PASSWORD"] only).
  write_clean_tree() {
    local mfile="$1" ffile="$2"
    {
      printf 'git_url("https://github.com/example/certs.git")\n'
      printf 'storage_mode("git")\n'
      printf 'type("appstore")\n'
      printf 'team_id(ENV["ASC_TEAM_ID"])\n'
    } > "$mfile"
    {
      printf 'lane :beta do\n'
      printf '  # MATCH_PASSWORD comes from ENV["MATCH_PASSWORD"]\n'
      printf '  match(type: "appstore", readonly: is_ci)\n'
      printf 'end\n'
    } > "$ffile"
  }

  echo "== match-policy self-test =="
  local m f
  local LOCALURL; LOCALURL="$(printf 'fi%s://' 'le')"  # the real forbidden local-disk URL literal

  # 0. Baseline: clean synthetic tree must PASS (exit 0).
  echo "-- clean synthetic tree --"
  m="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$m" "$f"
  assert_exit 0 "clean tree" "$m" "$f"; rm -f "$m" "$f"

  # 1. FORBIDDEN: inject a local-disk git URL into the Matchfile -> exit 1 (T-08-04-02).
  echo "-- forbidden negative controls (inject -> exit 1) --"
  m="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$m" "$f"
  printf 'git_url("%sUsers/me/certs")\n' "$LOCALURL" > "$m"
  printf 'storage_mode("git")\ntype("appstore")\n' >> "$m"
  assert_exit 1 "inject local-disk git URL" "$m" "$f"; rm -f "$m" "$f"

  # 2. REQUIRED: downgrade type(appstore) -> type(development) -> exit 1.
  echo "-- required negative controls (strip -> exit 1) --"
  m="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$m" "$f"
  { printf 'git_url("https://github.com/example/certs.git")\n'; printf 'type("development")\n'; } > "$m"
  assert_exit 1 "downgrade appstore->development" "$m" "$f"; rm -f "$m" "$f"

  # 3. REQUIRED: drop / break the https git_url (replace with a local-disk one) -> exit 1.
  #    (this trips BOTH the missing-https required check AND the forbidden local-disk check.)
  m="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$m" "$f"
  { printf 'git_url("%sLibrary/certs")\n' "$LOCALURL"; printf 'type("appstore")\n'; } > "$m"
  assert_exit 1 "drop https git_url (->local-disk)" "$m" "$f"; rm -f "$m" "$f"

  # 3'. REQUIRED: drop the git_url line entirely -> exit 1 (missing-https required check).
  m="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$m" "$f"
  { printf 'storage_mode("git")\n'; printf 'type("appstore")\n'; } > "$m"
  assert_exit 1 "drop git_url entirely" "$m" "$f"; rm -f "$m" "$f"

  # 4. FORBIDDEN: inject a literal MATCH_PASSWORD = "secret" into the Matchfile -> exit 1.
  m="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$m" "$f"
  printf 'MATCH_PASSWORD = "supersecret"\n' >> "$m"
  assert_exit 1 "inject literal MATCH_PASSWORD= (Matchfile)" "$m" "$f"; rm -f "$m" "$f"

  # 4'. FORBIDDEN: inject a bare literal assignment into the Fastfile -> exit 1.
  m="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$m" "$f"
  printf 'MATCH_PASSWORD = "supersecret"\n' >> "$f"
  assert_exit 1 "inject literal MATCH_PASSWORD= (Fastfile)" "$m" "$f"; rm -f "$m" "$f"

  # 4''. FORBIDDEN: inject an ENV-default password literal -> exit 1.
  m="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$m" "$f"
  printf 'pw = ENV["MATCH_PASSWORD"] || "fallbacksecret"\n' >> "$f"
  assert_exit 1 "inject ENV-default password literal (Fastfile)" "$m" "$f"; rm -f "$m" "$f"

  # 5. FORBIDDEN: inject an ssh git_url -> exit 1 (T-08-04-02).
  m="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$m" "$f"
  { printf 'git_url("git@github.com:example/certs.git")\n'; printf 'type("appstore")\n'; } > "$m"
  assert_exit 1 "inject ssh git_url" "$m" "$f"; rm -f "$m" "$f"

  if [[ "$fails" -eq 0 ]]; then
    echo "SELF-TEST OK: local-disk-URL injection, appstore->development downgrade, missing/broken"
    echo "              https git_url, literal-password injections, and ssh git_url all bite; clean passes."
    return 0
  else
    echo "SELF-TEST FAILED: at least one negative control did not bite (or the clean tree failed)." >&2
    return 1
  fi
}

# ── Entry point ────────────────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

if scan; then
  echo "OK: match policy clean -- type(appstore) + https git_url + MATCH_PASSWORD-from-ENV, no leak."
  exit 0
else
  echo "match-policy: FAILED -- the match/TestFlight config regressed (see ERROR lines above)." >&2
  exit 1
fi
