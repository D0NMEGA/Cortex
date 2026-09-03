#!/usr/bin/env bash
# Source: project-defined per 09-09-PLAN Task 1 (D-19) + 09-CONTEXT D-18/D-19/D-21.
# Purpose: build-failing provenance gate that structurally ties every published decoder number back
# to the bytes it was measured on. Mirrors the Phase-1 validate-privacy-manifest.sh negative-control
# idiom and the Phase-8 bps-policy.sh shape: a static gate plus a --self-test that proves the gate
# BITES, so a silently weakened gate fails CI loudly instead of passing everything.
#
# It asserts three things and nothing else. In particular it asserts NO measured value against any
# bar: the tier split (D-21 / Phase 2 D-18 / Phase 6 D-10) keeps CI on correctness and structure and
# leaves measured numbers to the committed evidence artifacts and the human runbook.
#
# --- ASSERTIONS (build FAILS on any) ---------------------------------------------------------
#   (a) no-pending  Decoder/manifests/indy_sessions.json contains zero "PENDING" sha256 entries.
#                   A PENDING checksum means that session's bytes were never verified, so every
#                   number attributed to it is unprovenanced (D-19a, RD-01a).
#   (b) declared    The committed 09-decoder-metrics.json carries data_source, a sessions array, and
#                   at least one 64-lowercase-hex sha256, so an empty or placeholder checksum cannot
#                   satisfy the grep leg (D-19b, RD-03c).
#   (c) agreement   The (id, sha256) pairs in the metrics JSON agree with the manifest's, checked by
#                   Tools/scripts/check_decoder_provenance.py. This leg cannot be a grep: agreement
#                   between two files is a set comparison, and a well-formed checksum that is simply
#                   the WRONG one is invisible to any regex over either file alone (D-19c, RD-03c).
#
# --- self-test (the negative control) --------------------------------------------------------
#   ./decoder-policy.sh --self-test
#     (0) a CLEAN synthetic manifest + metrics pair -> exit 0 (if this fails the stand-ins are wrong,
#         and a gate that always fails is as useless as one that never does);
#     (1) reintroduce one "sha256": "PENDING" into the stand-in manifest       -> exit 1;
#     (2) strip data_source from the stand-in metrics                          -> exit 1;
#     (3) perturb one stand-in metrics checksum, still 64 hex, so it disagrees -> exit 1.
#   Each case mutates exactly ONE thing relative to the clean tree, so a passing case proves that one
#   assertion and nothing else. Case 3 in particular is still well-formed hex, which is what makes it
#   a test of leg (c) rather than of leg (b).
#
#   The self-test needs python3 for case 3. macos-15 ships it (ci.yml already invokes bare python3
#   for check_refit_uplift.py), so this is not a real constraint; on a box without python3 the
#   self-test FAILS rather than reporting OK, because a gate whose third leg cannot run has not been
#   shown to bite.
#
#   DECODER_MANIFEST_FILE=/tmp/m.json DECODER_METRICS_FILE=/tmp/j.json ./decoder-policy.sh
#
# Exit codes:
#   0 -- no PENDING checksum, the metrics declare their provenance, and the two files agree
#   1 -- an assertion failed (see the ERROR lines)

set -euo pipefail

# --- Scope (overridable for the self-test, mirroring bps-policy.sh's BPS_SWIFT_FILE/BPS_JSON_FILE) -
# DECODER_MANIFEST_FILE -- the committed session manifest (the reproducibility record).
# DECODER_METRICS_FILE  -- the committed metrics artifact whose numbers must point back at it.
DECODER_MANIFEST_FILE="${DECODER_MANIFEST_FILE:-Decoder/manifests/indy_sessions.json}"
DECODER_METRICS_FILE="${DECODER_METRICS_FILE:-.planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-decoder-metrics.json}"

# The literal a never-verified session leaves behind, written by scripts/download_indy.py until the
# first verified fetch replaces it with the real digest.
PENDING_LITERAL='"PENDING"'

# --- require_re_in_file: assert an ERE is PRESENT in a file. ($1=path, $2=ERE, $3=label) ----------
require_re_in_file() {
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

# --- check_no_pending: assertion (a). Zero "PENDING" sha256 entries in the manifest. --------------
check_no_pending() {
  local path="$DECODER_MANIFEST_FILE" count
  if [[ ! -f "$path" ]]; then
    echo "ERROR [no-pending] manifest not found: $path" >&2
    return 1
  fi
  # grep -c exits 1 with no match, which set -e would take as a failure, hence the || true.
  count="$(grep -cF -- "$PENDING_LITERAL" "$path" || true)"
  if [[ "$count" == "0" ]]; then
    echo "  ok  [no-pending] zero $PENDING_LITERAL sha256 entries  ($path)"
    return 0
  fi
  echo "ERROR [no-pending] $count line(s) in $path still carry $PENDING_LITERAL. A PENDING sha256" >&2
  echo "       means that session's bytes were never verified, so any number attributed to it is" >&2
  echo "       unprovenanced. Re-run scripts/download_indy.py to write the real digest back" >&2
  echo "       (D-19a, RD-01a). Offending line(s):" >&2
  grep -nF -- "$PENDING_LITERAL" "$path" >&2 || true
  return 1
}

# --- check_checksums_agree: assertion (c). Set comparison across the two files. -------------------
# Guarded on python3 availability, the gen-flatbuffers.sh/bps-policy.sh idiom: a missing interpreter
# prints a skip line NAMING what went unchecked rather than silently passing. ci.yml already runs
# bare python3 for check_refit_uplift.py on macos-15, so this leg fires in CI.
check_checksums_agree() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  skip [agreement] python3 not found, so the manifest/metrics checksum SET COMPARISON did"
    echo "       not run. The grep legs above still fired. CI runs on macos-15, which ships python3."
    return 0
  fi
  if python3 Tools/scripts/check_decoder_provenance.py "$DECODER_MANIFEST_FILE" "$DECODER_METRICS_FILE"; then
    return 0
  fi
  echo "ERROR [agreement] the committed metrics do not agree with the manifest (D-19c, RD-03c)." >&2
  return 1
}

# --- scan: run every assertion. Returns 0 only if ALL pass. ---------------------------------------
scan() {
  local rc=0

  echo "scanning session manifest: $DECODER_MANIFEST_FILE"
  echo "scanning decoder metrics:  $DECODER_METRICS_FILE"

  # (a) No unverified session.
  check_no_pending || rc=1

  # (b) The metrics declare their provenance.
  require_re_in_file "$DECODER_METRICS_FILE" '"data_source"[[:space:]]*:' \
    "metrics declare data_source (D-19b)" || rc=1
  require_re_in_file "$DECODER_METRICS_FILE" '"sessions"[[:space:]]*:' \
    "metrics name the sessions they came from (D-19b)" || rc=1
  require_re_in_file "$DECODER_METRICS_FILE" '"sha256"[[:space:]]*:[[:space:]]*"[0-9a-f]{64}"' \
    "metrics carry a real 64-hex sha256, not a placeholder (D-19b)" || rc=1

  # (c) The two files agree.
  check_checksums_agree || rc=1

  return $rc
}

# Absolute path to THIS script, so the self-test can re-invoke it with overridden scope
# (bps-policy.sh's SELF pattern).
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# --- self_test: the negative control. Prove a clean tree passes and that each of the three
# assertions bites. The established Cortex discipline (the Phase-1 privacy-manifest CA92.1 control,
# the Phase-3/6/8 hotpath/render/bps self-tests). --------------------------------------------------
self_test() {
  local fails=0 rc

  # Re-run THIS script against an overridden manifest + metrics pair and assert the exit code.
  # $1=expected exit, $2=label, $3=manifest file, $4=metrics file.
  assert_exit() {
    local want="$1" label="$2" mfile="$3" jfile="$4"
    set +e
    ( env DECODER_MANIFEST_FILE="$mfile" DECODER_METRICS_FILE="$jfile" bash "$SELF" ) >/dev/null 2>&1
    rc=$?
    set -e
    if [[ "$rc" -eq "$want" ]]; then
      echo "  PASS [$label] exit=$rc (expected $want)"
    else
      echo "  FAIL [$label] exit=$rc (expected $want)" >&2
      fails=1
    fi
  }

  # write_clean: a CLEAN synthetic manifest + metrics pair that must PASS. Each case below then
  # mutates exactly one thing. The stand-in digests are 64 a's and 64 b's, which are valid lowercase
  # hex and therefore satisfy leg (b) on their own.
  write_clean() {
    local mfile="$1" jfile="$2" sha_a sha_b
    sha_a="$(printf 'a%.0s' {1..64})"
    sha_b="$(printf 'b%.0s' {1..64})"
    {
      printf '{\n'
      printf '  "record": "0000000",\n'
      printf '  "sessions": [\n'
      printf '    { "id": "stand_in_a", "sha256": "%s", "size_bytes": 1 },\n' "$sha_a"
      printf '    { "id": "stand_in_b", "sha256": "%s", "size_bytes": 2 }\n' "$sha_b"
      printf '  ]\n}\n'
    } > "$mfile"
    {
      printf '{\n'
      printf '  "schema_version": 1,\n'
      printf '  "data_source": "stand-in",\n'
      printf '  "manifest_path": "Decoder/manifests/indy_sessions.json",\n'
      printf '  "sessions": [\n'
      printf '    { "id": "stand_in_a", "sha256": "%s" },\n' "$sha_a"
      printf '    { "id": "stand_in_b", "sha256": "%s" }\n' "$sha_b"
      printf '  ]\n}\n'
    } > "$jfile"
  }

  echo "== decoder-policy self-test =="

  local m j sha_a sha_b sha_wrong
  sha_a="$(printf 'a%.0s' {1..64})"
  sha_b="$(printf 'b%.0s' {1..64})"
  sha_wrong="$(printf 'c%.0s' {1..64})"

  # 0. Baseline: the clean synthetic pair must PASS (exit 0). If this fails, the stand-ins are wrong.
  echo "-- clean synthetic tree --"
  m="$(mktemp)"; j="$(mktemp)"; write_clean "$m" "$j"
  assert_exit 0 "clean tree" "$m" "$j"; rm -f "$m" "$j"

  # 1. Reintroduce one "PENDING" sha256 into the manifest -> exit 1 (assertion (a)).
  echo "-- PENDING negative control (one unverified session -> exit 1) --"
  m="$(mktemp)"; j="$(mktemp)"; write_clean "$m" "$j"
  {
    printf '{\n'
    printf '  "record": "0000000",\n'
    printf '  "sessions": [\n'
    printf '    { "id": "stand_in_a", "sha256": "PENDING", "size_bytes": 1 },\n'
    printf '    { "id": "stand_in_b", "sha256": "%s", "size_bytes": 2 }\n' "$sha_b"
    printf '  ]\n}\n'
  } > "$m"
  assert_exit 1 "reintroduce a PENDING sha256" "$m" "$j"; rm -f "$m" "$j"

  # 2. Strip data_source from the metrics -> exit 1 (assertion (b)).
  echo "-- data_source-strip negative control (undeclared provenance -> exit 1) --"
  m="$(mktemp)"; j="$(mktemp)"; write_clean "$m" "$j"
  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "manifest_path": "Decoder/manifests/indy_sessions.json",\n'
    printf '  "sessions": [\n'
    printf '    { "id": "stand_in_a", "sha256": "%s" },\n' "$sha_a"
    printf '    { "id": "stand_in_b", "sha256": "%s" }\n' "$sha_b"
    printf '  ]\n}\n'
  } > "$j"
  assert_exit 1 "strip data_source" "$m" "$j"; rm -f "$m" "$j"

  # 3. Perturb one metrics checksum -> exit 1 (assertion (c)). Still 64 lowercase hex, so leg (b)
  #    passes and ONLY the set comparison can catch it. That is the point of this case.
  echo "-- checksum-disagreement negative control (well-formed but wrong -> exit 1) --"
  m="$(mktemp)"; j="$(mktemp)"; write_clean "$m" "$j"
  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "data_source": "stand-in",\n'
    printf '  "manifest_path": "Decoder/manifests/indy_sessions.json",\n'
    printf '  "sessions": [\n'
    printf '    { "id": "stand_in_a", "sha256": "%s" },\n' "$sha_wrong"
    printf '    { "id": "stand_in_b", "sha256": "%s" }\n' "$sha_b"
    printf '  ]\n}\n'
  } > "$j"
  assert_exit 1 "perturb one metrics checksum" "$m" "$j"; rm -f "$m" "$j"

  if [[ "$fails" -eq 0 ]]; then
    echo "SELF-TEST OK: a clean tree passes; a reintroduced PENDING sha256 bites; a stripped"
    echo "              data_source bites; a well-formed but disagreeing checksum bites."
    return 0
  else
    echo "SELF-TEST FAILED: at least one negative control did not bite (or the clean tree failed)." >&2
    return 1
  fi
}

# --- Entry point ---------------------------------------------------------------------------------
if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

if scan; then
  echo "OK: decoder policy clean -- no PENDING checksum, metrics declare their provenance, and the"
  echo "    committed numbers agree with the manifest bytes they were measured on."
  exit 0
else
  echo "decoder-policy: FAILED -- a provenance invariant regressed (see ERROR lines above)." >&2
  exit 1
fi
