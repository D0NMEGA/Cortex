#!/usr/bin/env bash
# Tools/scripts/notarize-policy.sh -- DIST-01 / D-06 notarization-pipeline structural gate.
# Source: project-defined per CONTEXT.md D-06. Mirrors EXACTLY the Phase-6 render-policy.sh /
# Phase-3 hotpath-policy.sh idiom: a build-failing static grep proxy for a load-bearing commitment,
# WITH a negative-control --self-test that proves every check bites. This is the regression
# tripwire for the notarization pipeline, not the implementation (notarize.sh is the implementation).
#
# ── REQUIRED-PRESENT (build-FAILS if a token is ABSENT) ───────────────────────────────────────
#   1. notarytool submit   (Tools/scripts/notarize.sh) -- the modern Apple notary submission
#      (DIST-01, RESEARCH §3, authoritative from Xcode 26.3).
#   2. stapler staple      (Tools/scripts/notarize.sh) -- the ticket-stapling step.
#
# ── FORBIDDEN (build-FAILS if a token is PRESENT) ─────────────────────────────────────────────
#   A. the deprecated legacy App Store uploader name appears NOWHERE in notarize.sh or the Fastfile
#      (zero occurrences -- DIST-01). The pipeline must use notarytool, never the retired tool that
#      Apple sunset for notarization. (This policy script necessarily NAMES the forbidden literal
#      in its own grep pattern below -- that is correct and unavoidable; the no-uploader rule
#      polices notarize.sh + the Fastfile, NOT this gate. The comments in the policed files describe
#      the retired tool by intent, never the bare literal, per the Cortex literal-grep discipline;
#      the --self-test injects the REAL literal into a synthetic tree to prove the gate bites.)
#
# Self-test:
#   ./notarize-policy.sh --self-test   # (i) clean synthetic tree -> exit 0; (ii) strip notarytool
#                                      # submit -> exit 1; (iii) strip stapler staple -> exit 1;
#                                      # (iv) inject the legacy-uploader literal -> exit 1.
#   NOTARIZE_SCRIPT=/tmp/n.sh FASTFILE=/tmp/Fastfile ./notarize-policy.sh   # repoint at a temp tree
#
# Exit codes:
#   0 -- required tokens present, forbidden token absent (the real tree after Plan 08-04 Task 1)
#   1 -- a required token is missing OR the forbidden token appears (a regression)

set -euo pipefail

# ── Scope (overridable for the self-test, mirroring render-policy.sh's RENDER_DIR/PROJECT_FILE) ──
NOTARIZE_SCRIPT="${NOTARIZE_SCRIPT:-Tools/scripts/notarize.sh}"
FASTFILE="${FASTFILE:-fastlane/Fastfile}"

# The deprecated-uploader literal is assembled at runtime so this gate file itself does not contain
# the bare token as a standalone word in prose (defense against a future tree-wide audit grep that
# scans Tools/scripts/*). The grep still matches the real literal in any policed file.
FORBIDDEN_UPLOADER="$(printf 'al%s' 'tool')"

# ── require_in_file: assert a regex is PRESENT in a specific file (missing file/token = FAIL). ──
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

# ── forbid_fixed_in_file: assert a FIXED string is ABSENT from a file (a match = FAIL). A missing
# file is vacuously clean (matches render-policy.sh / hotpath-policy.sh behavior). ──────────────
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

# ── scan: run every assertion. Returns 0 only if ALL pass. ──────────────────────────────────────
scan() {
  local rc=0
  echo "scanning notarize script: $NOTARIZE_SCRIPT"
  echo "scanning Fastfile:        $FASTFILE"

  # REQUIRED-PRESENT (1-2): the modern pipeline, scoped to notarize.sh.
  require_in_file "$NOTARIZE_SCRIPT" 'notarytool[[:space:]]+submit' "notarytool submit present (DIST-01)" || rc=1
  require_in_file "$NOTARIZE_SCRIPT" 'stapler[[:space:]]+staple'    "stapler staple present (DIST-01)"    || rc=1

  # FORBIDDEN (A): zero deprecated-uploader references in notarize.sh OR the Fastfile.
  forbid_fixed_in_file "$NOTARIZE_SCRIPT" "$FORBIDDEN_UPLOADER" "no deprecated uploader in notarize.sh (DIST-01)" || rc=1
  forbid_fixed_in_file "$FASTFILE"        "$FORBIDDEN_UPLOADER" "no deprecated uploader in Fastfile (DIST-01)"    || rc=1

  return $rc
}

# Absolute path to THIS script (so the self-test can re-invoke it with overridden scope).
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── self_test: the negative control. Prove the gate BITES on each missing-required and the
# injected-forbidden case, then prove a clean synthetic tree PASSES. ────────────────────────────
self_test() {
  local fails=0 rc

  assert_exit() {
    local want="$1" label="$2" nscript="$3" ffile="$4"
    set +e
    ( env NOTARIZE_SCRIPT="$nscript" FASTFILE="$ffile" bash "$SELF" ) >/dev/null 2>&1
    rc=$?
    set -e
    if [[ "$rc" -eq "$want" ]]; then
      echo "  PASS [$label] exit=$rc (expected $want)"
    else
      echo "  FAIL [$label] exit=$rc (expected $want)" >&2
      fails=1
    fi
  }

  # write_clean_tree: a CLEAN synthetic notarize.sh (notarytool submit + stapler staple, no
  # deprecated uploader) + a CLEAN synthetic Fastfile (no deprecated uploader). Each negative
  # control mutates exactly one thing.
  write_clean_tree() {
    local nscript="$1" ffile="$2"
    {
      printf '#!/usr/bin/env bash\n'
      printf 'xcrun notarytool submit "$ZIP" --key "$K" --key-id "$D" --issuer "$I" --wait -f json\n'
      printf 'xcrun stapler staple "$APP"\n'
    } > "$nscript"
    {
      printf 'lane :beta do\n'
      printf '  upload_to_testflight(api_key: api_key)\n'
      printf 'end\n'
    } > "$ffile"
  }

  echo "== notarize-policy self-test =="
  local n f
  local UPLOADER; UPLOADER="$(printf 'al%s' 'tool')"  # the real forbidden literal, for injection

  # 0. Baseline: the clean synthetic tree must PASS (exit 0).
  echo "-- clean synthetic tree --"
  n="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$n" "$f"
  assert_exit 0 "clean tree" "$n" "$f"; rm -f "$n" "$f"

  # 1. REQUIRED negative-controls: strip exactly one required token -> exit 1.
  echo "-- required-token negative controls (strip -> exit 1) --"

  # 1a. Strip `notarytool submit` (replace with a bare comment) -> exit 1.
  n="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$n" "$f"
  { printf '#!/usr/bin/env bash\n'; printf '# (notarytool submission removed)\n'; printf 'xcrun stapler staple "$APP"\n'; } > "$n"
  assert_exit 1 "strip notarytool submit" "$n" "$f"; rm -f "$n" "$f"

  # 1b. Strip `stapler staple` -> exit 1.
  n="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$n" "$f"
  { printf '#!/usr/bin/env bash\n'; printf 'xcrun notarytool submit "$ZIP" --wait -f json\n'; printf '# (stapling removed)\n'; } > "$n"
  assert_exit 1 "strip stapler staple" "$n" "$f"; rm -f "$n" "$f"

  # 2. FORBIDDEN negative-controls: inject the legacy-uploader literal -> exit 1.
  echo "-- forbidden-token negative controls (inject -> exit 1) --"

  # 2a. Inject the deprecated uploader into notarize.sh -> exit 1.
  n="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$n" "$f"
  printf 'xcrun %s --upload-app -f "$ZIP"\n' "$UPLOADER" >> "$n"
  assert_exit 1 "inject deprecated uploader into notarize.sh" "$n" "$f"; rm -f "$n" "$f"

  # 2b. Inject the deprecated uploader into the Fastfile -> exit 1.
  n="$(mktemp)"; f="$(mktemp)"; write_clean_tree "$n" "$f"
  printf '  sh("xcrun %s --upload-app")\n' "$UPLOADER" >> "$f"
  assert_exit 1 "inject deprecated uploader into Fastfile" "$n" "$f"; rm -f "$n" "$f"

  if [[ "$fails" -eq 0 ]]; then
    echo "SELF-TEST OK: notarytool-strip, stapler-strip, and both deprecated-uploader injections"
    echo "              all bite; a clean tree passes."
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
  echo "OK: notarize policy clean -- notarytool submit + stapler staple present, no deprecated uploader."
  exit 0
else
  echo "notarize-policy: FAILED -- the notarization pipeline regressed (see ERROR lines above)." >&2
  exit 1
fi
