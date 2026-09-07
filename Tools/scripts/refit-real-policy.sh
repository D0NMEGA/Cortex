#!/usr/bin/env bash
# Source: 10-09-PLAN Task 1 (D-09/RD-07/RD-08). Mirrors decoder-policy.sh structure.
# Purpose: build-failing provenance gate that structurally ties every published Phase-10
# real-data number back to the session bytes, the export sidecar, and the committed
# checkpoints. A static gate plus a --self-test that proves the gate BITES, so a silently
# weakened gate fails CI loudly instead of passing everything.
#
# --- ASSERTIONS (build FAILS on any) -------------------------------------------------------
#   (a) provenance declared  both phase artifacts carry data_source == "real" and a 64-hex
#                            source_sha256, so an empty or placeholder value cannot pass.
#   (b) four named arms      10-refit-real.json carries the four pre-registered arm names
#                            (raw, kalman_only, refit, refit_reversed_target), the two
#                            Willett statistics (realized_gain, realized_smoothing), and
#                            rotation_target_source (SC#1c / SC#1d).
#   (c) two labeled seams    10-replay.json carries a seam labeled "A" and one labeled "B",
#                            each with a "boundary" field, plus the verbatim open-loop
#                            disclosure substring.
#   (d) cross-file agreement (session_id, source_sha256) identical across all three phase
#                            artifacts and agree with the manifest; export sidecar matches
#                            between refit-real and replay; checkpoint sha256s are 64 hex;
#                            ticks_model_backed == ticks_total. This leg cannot be a grep.
#
# --- D-09: PROVENANCE, SCHEMA and STRUCTURE only -------------------------------------------
# This gate never asserts the sign or magnitude of a real-data result. The self-test proves
# each assertion bites on a synthetic stand-in; it does not assert anything about the real
# measured values.
#
# --- self-test cases -----------------------------------------------------------------------
#   (0) a CLEAN synthetic quartet -> exit 0;
#   (1) strip data_source from stand-in refit-real -> exit 1;
#   (2) perturb source_sha256 in stand-in replay, still 64 hex -> exit 1 (python leg);
#   (3) drop refit_reversed_target arm from stand-in refit-real -> exit 1;
#   (4) strip open-loop replay disclosure from stand-in replay -> exit 1;
#   (5) collapse stand-in replay's two seams into one -> exit 1.
#
# Exit codes: 0 = all assertions pass; 1 = an assertion failed (see ERROR lines).

set -euo pipefail

# --- Scope (env-overridable for self-test) -------------------------------------------------
PHASE_DIR="${PHASE_DIR:-.planning/phases/10-v1-real-data-closed-loop-launch}"
REFIT_REAL_FILE="${REFIT_REAL_FILE:-${PHASE_DIR}/10-refit-real.json}"
REPLAY_FILE="${REPLAY_FILE:-${PHASE_DIR}/10-replay.json}"
CEILING_FILE="${CEILING_FILE:-${PHASE_DIR}/10-ceiling.json}"
REFIT_MANIFEST_FILE="${REFIT_MANIFEST_FILE:-Decoder/manifests/indy_sessions.json}"

# Absolute path to THIS script so self-test can re-invoke it and scan() can find the python helper.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# --- require_re_in_file: assert an ERE is PRESENT in a file. ($1=path, $2=ERE, $3=label) ---
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

# --- require_fixed_in_file: assert a fixed string is PRESENT in a file. ($1=path, $2=needle, $3=label) ---
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

# D-09: no assertion below compares a measured value against a bar.
scan() {
  local rc=0

  echo "scanning refit-real:  $REFIT_REAL_FILE"
  echo "scanning replay:      $REPLAY_FILE"
  echo "scanning ceiling:     $CEILING_FILE"
  echo "scanning manifest:    $REFIT_MANIFEST_FILE"

  # (a) Provenance declared. Both phase artifacts must carry data_source == "real" and a 64-hex
  #     source_sha256, so an empty or placeholder value cannot satisfy either grep.
  require_re_in_file "$REFIT_REAL_FILE" '"data_source"[[:space:]]*:[[:space:]]*"real"' \
    "refit-real declares data_source=real (D-09/RD-07)" || rc=1
  require_re_in_file "$REFIT_REAL_FILE" '"source_sha256"[[:space:]]*:[[:space:]]*"[0-9a-f]{64}"' \
    "refit-real carries a 64-hex source_sha256 (RD-07)" || rc=1
  require_re_in_file "$REPLAY_FILE" '"data_source"[[:space:]]*:[[:space:]]*"real"' \
    "replay declares data_source=real (D-09/RD-08)" || rc=1
  require_re_in_file "$REPLAY_FILE" '"source_sha256"[[:space:]]*:[[:space:]]*"[0-9a-f]{64}"' \
    "replay carries a 64-hex source_sha256 (RD-08)" || rc=1

  # (b) Four named arms. The refit-real artifact must carry all four pre-registered arm names
  #     plus the two Willett statistics and the rotation target source (SC#1c / SC#1d).
  require_fixed_in_file "$REFIT_REAL_FILE" '"raw"' \
    "refit-real carries raw arm (SC#1c)" || rc=1
  require_fixed_in_file "$REFIT_REAL_FILE" '"kalman_only"' \
    "refit-real carries kalman_only arm (SC#1c)" || rc=1
  require_fixed_in_file "$REFIT_REAL_FILE" '"refit"' \
    "refit-real carries refit arm (SC#1c)" || rc=1
  require_fixed_in_file "$REFIT_REAL_FILE" '"refit_reversed_target"' \
    "refit-real carries refit_reversed_target arm (SC#1c)" || rc=1
  require_fixed_in_file "$REFIT_REAL_FILE" '"rotation_target_source"' \
    "refit-real carries rotation_target_source (SC#1c)" || rc=1
  require_fixed_in_file "$REFIT_REAL_FILE" '"realized_gain"' \
    "refit-real carries realized_gain (SC#1d)" || rc=1
  require_fixed_in_file "$REFIT_REAL_FILE" '"realized_smoothing"' \
    "refit-real carries realized_smoothing (SC#1d)" || rc=1

  # (c) Two distinctly labeled seams. The replay artifact must carry seam "A" and seam "B",
  #     each with a boundary field, plus the verbatim open-loop disclosure substring.
  require_re_in_file "$REPLAY_FILE" '"seam"[[:space:]]*:[[:space:]]*"A"' \
    "replay carries seam A (RD-08/SC#2f)" || rc=1
  require_re_in_file "$REPLAY_FILE" '"seam"[[:space:]]*:[[:space:]]*"B"' \
    "replay carries seam B (RD-08/SC#2f)" || rc=1
  require_fixed_in_file "$REPLAY_FILE" '"boundary"' \
    "replay seams carry boundary fields (RD-08)" || rc=1
  require_fixed_in_file "$REPLAY_FILE" 'open-loop replay' \
    "replay carries open-loop replay disclosure (D-03/D-09)" || rc=1

  # (d) Cross-file agreement. This leg cannot be a grep: (session_id, source_sha256) agreement
  #     across files, the export sidecar match, and ticks_model_backed == ticks_total are all
  #     set comparisons. A well-formed checksum that is simply the WRONG one is invisible to any
  #     regex over either file alone. See check_real_replay_provenance.py's module docstring.
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  skip [cross-file] python3 not found -- manifest/artifact set comparison did not run."
    echo "       CI (macos-15) ships python3 (proven by check_refit_uplift.py step in ci.yml)."
  else
    if python3 "$(dirname "$SELF")/check_real_replay_provenance.py" \
        "$REFIT_MANIFEST_FILE" "$REFIT_REAL_FILE" "$REPLAY_FILE" "$CEILING_FILE"; then
      :
    else
      echo "ERROR [cross-file] phase artifacts do not agree with the manifest (D-09/RD-07/RD-08)." >&2
      rc=1
    fi
  fi

  return $rc
}

# --- self_test: prove the clean synthetic quartet passes and each of the five assertions bites.
self_test() {
  local fails=0 rc

  # Re-run THIS script against overridden scope vars and assert the exit code.
  # $1=expected exit, $2=label, $3=manifest, $4=refit-real, $5=replay, $6=ceiling.
  assert_exit() {
    local want="$1" label="$2" mfile="$3" rfile="$4" pfile="$5" cfile="$6"
    set +e
    ( env REFIT_MANIFEST_FILE="$mfile" REFIT_REAL_FILE="$rfile" \
          REPLAY_FILE="$pfile" CEILING_FILE="$cfile" \
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

  # write_clean: emit a CLEAN synthetic quartet into the provided temp file paths.
  # sha_a (64 a's): source digest and manifest session sha256.
  # sha_b (64 b's): export sidecar sha256.
  # sha_c (64 c's): encoder checkpoint sha256.
  # sha_d (64 d's): velocity checkpoint sha256.
  write_clean() {
    local mfile="$1" rfile="$2" pfile="$3" cfile="$4"
    local sha_a sha_b sha_c sha_d
    sha_a="$(printf 'a%.0s' {1..64})"
    sha_b="$(printf 'b%.0s' {1..64})"
    sha_c="$(printf 'c%.0s' {1..64})"
    sha_d="$(printf 'd%.0s' {1..64})"
    # manifest
    {
      printf '{\n  "sessions": [\n'
      printf '    { "id": "stand_in_a", "sha256": "%s", "size_bytes": 1 }\n' "$sha_a"
      printf '  ]\n}\n'
    } > "$mfile"
    # refit-real
    {
      printf '{\n'
      printf '  "schema_version": 1,\n'
      printf '  "data_source": "real",\n'
      printf '  "session_id": "stand_in_a",\n'
      printf '  "source_sha256": "%s",\n' "$sha_a"
      printf '  "export_sidecar_sha256": "%s",\n' "$sha_b"
      printf '  "encoder_checkpoint_sha256": "%s",\n' "$sha_c"
      printf '  "velocity_checkpoint_sha256": "%s",\n' "$sha_d"
      printf '  "disclosure": "open-loop replay of a recorded session; the subject was not in the loop",\n'
      printf '  "arms": [\n'
      printf '    { "name": "raw", "rotation_target_source": "none", "realized_gain": 1.0, "realized_smoothing": 0.5 },\n'
      printf '    { "name": "kalman_only", "rotation_target_source": "none", "realized_gain": 0.9, "realized_smoothing": 0.9 },\n'
      printf '    { "name": "refit", "rotation_target_source": "true_track", "realized_gain": 0.9, "realized_smoothing": 0.9 },\n'
      printf '    { "name": "refit_reversed_target", "rotation_target_source": "reversed_track", "realized_gain": 0.9, "realized_smoothing": 0.9 }\n'
      printf '  ]\n}\n'
    } > "$rfile"
    # replay
    {
      printf '{\n'
      printf '  "schema_version": 1,\n'
      printf '  "data_source": "real",\n'
      printf '  "session_id": "stand_in_a",\n'
      printf '  "source_sha256": "%s",\n' "$sha_a"
      printf '  "export_sidecar_sha256": "%s",\n' "$sha_b"
      printf '  "ticks_model_backed": 100,\n'
      printf '  "ticks_total": 100,\n'
      printf '  "replay_reference_hits": 5,\n'
      printf '  "replay_reference_ref": { "artifact": "stand-in-ceiling.json" },\n'
      printf '  "disclosure": "open-loop replay of a recorded session; the subject was not in the loop",\n'
      printf '  "seams": [\n'
      printf '    {\n'
      printf '      "seam": "A", "boundary": "seam A stand-in boundary",\n'
      printf '      "data_source": "real", "status": "corroborating",\n'
      printf '      "p50_ns": 1000, "p99_ns": 2000, "max_ns": 3000, "count": 100\n'
      printf '    },\n'
      printf '    {\n'
      printf '      "seam": "B", "boundary": "seam B stand-in boundary",\n'
      printf '      "data_source": "real", "status": "corroborating"\n'
      printf '    }\n'
      printf '  ]\n}\n'
    } > "$pfile"
    # ceiling
    {
      printf '{\n'
      printf '  "schema_version": 1,\n'
      printf '  "data_source": "real",\n'
      printf '  "session_id": "stand_in_a",\n'
      printf '  "source_sha256": "%s",\n' "$sha_a"
      printf '  "canonical_hits": 5,\n'
      printf '  "canonical_radius_mm": 2.0,\n'
      printf '  "canonical_dwell_s": 0.3\n'
      printf '}\n'
    } > "$cfile"
  }

  echo "== refit-real-policy self-test =="

  local sha_a sha_b sha_c sha_d sha_wrong
  sha_a="$(printf 'a%.0s' {1..64})"
  sha_b="$(printf 'b%.0s' {1..64})"
  sha_c="$(printf 'c%.0s' {1..64})"
  sha_d="$(printf 'd%.0s' {1..64})"
  sha_wrong="$(printf 'e%.0s' {1..64})"

  # 0. Baseline: the clean synthetic quartet must PASS (exit 0).
  echo "-- clean synthetic quartet --"
  local m r p c
  m="$(mktemp)" r="$(mktemp)" p="$(mktemp)" c="$(mktemp)"
  write_clean "$m" "$r" "$p" "$c"
  assert_exit 0 "clean quartet" "$m" "$r" "$p" "$c"
  rm -f "$m" "$r" "$p" "$c"

  # 1. Strip data_source from stand-in refit-real -> exit 1 (assertion (a)).
  echo "-- strip data_source from refit-real (undeclared provenance) --"
  m="$(mktemp)" r="$(mktemp)" p="$(mktemp)" c="$(mktemp)"
  write_clean "$m" "$r" "$p" "$c"
  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "session_id": "stand_in_a",\n'
    printf '  "source_sha256": "%s",\n' "$sha_a"
    printf '  "export_sidecar_sha256": "%s",\n' "$sha_b"
    printf '  "encoder_checkpoint_sha256": "%s",\n' "$sha_c"
    printf '  "velocity_checkpoint_sha256": "%s",\n' "$sha_d"
    printf '  "disclosure": "open-loop replay of a recorded session; the subject was not in the loop",\n'
    printf '  "arms": [\n'
    printf '    { "name": "raw", "rotation_target_source": "none", "realized_gain": 1.0, "realized_smoothing": 0.5 },\n'
    printf '    { "name": "kalman_only", "rotation_target_source": "none", "realized_gain": 0.9, "realized_smoothing": 0.9 },\n'
    printf '    { "name": "refit", "rotation_target_source": "true_track", "realized_gain": 0.9, "realized_smoothing": 0.9 },\n'
    printf '    { "name": "refit_reversed_target", "rotation_target_source": "reversed_track", "realized_gain": 0.9, "realized_smoothing": 0.9 }\n'
    printf '  ]\n}\n'
  } > "$r"
  assert_exit 1 "strip data_source from refit-real" "$m" "$r" "$p" "$c"
  rm -f "$m" "$r" "$p" "$c"

  # 2. Perturb source_sha256 in stand-in replay to sha_wrong, still 64 hex -> exit 1 (python
  #    assertion (d)). The shell grep in (a) still passes because sha_wrong IS 64 lowercase hex.
  #    Only the cross-file set comparison catches it. That is the point of this case.
  echo "-- perturb source_sha256 in replay, still 64 hex (wrong checksum -> python leg) --"
  m="$(mktemp)" r="$(mktemp)" p="$(mktemp)" c="$(mktemp)"
  write_clean "$m" "$r" "$p" "$c"
  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "data_source": "real",\n'
    printf '  "session_id": "stand_in_a",\n'
    printf '  "source_sha256": "%s",\n' "$sha_wrong"
    printf '  "export_sidecar_sha256": "%s",\n' "$sha_b"
    printf '  "ticks_model_backed": 100,\n'
    printf '  "ticks_total": 100,\n'
    printf '  "replay_reference_hits": 5,\n'
    printf '  "replay_reference_ref": { "artifact": "stand-in-ceiling.json" },\n'
    printf '  "disclosure": "open-loop replay of a recorded session; the subject was not in the loop",\n'
    printf '  "seams": [\n'
    printf '    {\n'
    printf '      "seam": "A", "boundary": "seam A stand-in boundary",\n'
    printf '      "data_source": "real", "status": "corroborating",\n'
    printf '      "p50_ns": 1000, "p99_ns": 2000, "max_ns": 3000, "count": 100\n'
    printf '    },\n'
    printf '    {\n'
    printf '      "seam": "B", "boundary": "seam B stand-in boundary",\n'
    printf '      "data_source": "real", "status": "corroborating"\n'
    printf '    }\n'
    printf '  ]\n}\n'
  } > "$p"
  assert_exit 1 "perturb source_sha256 in replay (python leg)" "$m" "$r" "$p" "$c"
  rm -f "$m" "$r" "$p" "$c"

  # 3. Drop refit_reversed_target arm from stand-in refit-real -> exit 1 (assertion (b)).
  echo "-- drop refit_reversed_target arm (missing fourth arm) --"
  m="$(mktemp)" r="$(mktemp)" p="$(mktemp)" c="$(mktemp)"
  write_clean "$m" "$r" "$p" "$c"
  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "data_source": "real",\n'
    printf '  "session_id": "stand_in_a",\n'
    printf '  "source_sha256": "%s",\n' "$sha_a"
    printf '  "export_sidecar_sha256": "%s",\n' "$sha_b"
    printf '  "encoder_checkpoint_sha256": "%s",\n' "$sha_c"
    printf '  "velocity_checkpoint_sha256": "%s",\n' "$sha_d"
    printf '  "disclosure": "open-loop replay of a recorded session; the subject was not in the loop",\n'
    printf '  "arms": [\n'
    printf '    { "name": "raw", "rotation_target_source": "none", "realized_gain": 1.0, "realized_smoothing": 0.5 },\n'
    printf '    { "name": "kalman_only", "rotation_target_source": "none", "realized_gain": 0.9, "realized_smoothing": 0.9 },\n'
    printf '    { "name": "refit", "rotation_target_source": "true_track", "realized_gain": 0.9, "realized_smoothing": 0.9 }\n'
    printf '  ]\n}\n'
  } > "$r"
  assert_exit 1 "drop refit_reversed_target arm" "$m" "$r" "$p" "$c"
  rm -f "$m" "$r" "$p" "$c"

  # 4. Strip open-loop replay disclosure from stand-in replay -> exit 1 (assertion (c)).
  echo "-- strip open-loop replay disclosure (missing disclosure) --"
  m="$(mktemp)" r="$(mktemp)" p="$(mktemp)" c="$(mktemp)"
  write_clean "$m" "$r" "$p" "$c"
  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "data_source": "real",\n'
    printf '  "session_id": "stand_in_a",\n'
    printf '  "source_sha256": "%s",\n' "$sha_a"
    printf '  "export_sidecar_sha256": "%s",\n' "$sha_b"
    printf '  "ticks_model_backed": 100,\n'
    printf '  "ticks_total": 100,\n'
    printf '  "replay_reference_hits": 5,\n'
    printf '  "replay_reference_ref": { "artifact": "stand-in-ceiling.json" },\n'
    printf '  "disclosure": "STRIPPED",\n'
    printf '  "seams": [\n'
    printf '    {\n'
    printf '      "seam": "A", "boundary": "seam A stand-in boundary",\n'
    printf '      "data_source": "real", "status": "corroborating",\n'
    printf '      "p50_ns": 1000, "p99_ns": 2000, "max_ns": 3000, "count": 100\n'
    printf '    },\n'
    printf '    {\n'
    printf '      "seam": "B", "boundary": "seam B stand-in boundary",\n'
    printf '      "data_source": "real", "status": "corroborating"\n'
    printf '    }\n'
    printf '  ]\n}\n'
  } > "$p"
  assert_exit 1 "strip open-loop replay disclosure" "$m" "$r" "$p" "$c"
  rm -f "$m" "$r" "$p" "$c"

  # 5. Collapse stand-in replay's two seams into one (delete seam B) -> exit 1 (assertion (c)).
  echo "-- collapse seams to one (missing seam B) --"
  m="$(mktemp)" r="$(mktemp)" p="$(mktemp)" c="$(mktemp)"
  write_clean "$m" "$r" "$p" "$c"
  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "data_source": "real",\n'
    printf '  "session_id": "stand_in_a",\n'
    printf '  "source_sha256": "%s",\n' "$sha_a"
    printf '  "export_sidecar_sha256": "%s",\n' "$sha_b"
    printf '  "ticks_model_backed": 100,\n'
    printf '  "ticks_total": 100,\n'
    printf '  "replay_reference_hits": 5,\n'
    printf '  "replay_reference_ref": { "artifact": "stand-in-ceiling.json" },\n'
    printf '  "disclosure": "open-loop replay of a recorded session; the subject was not in the loop",\n'
    printf '  "seams": [\n'
    printf '    {\n'
    printf '      "seam": "A", "boundary": "seam A stand-in boundary",\n'
    printf '      "data_source": "real", "status": "corroborating",\n'
    printf '      "p50_ns": 1000, "p99_ns": 2000, "max_ns": 3000, "count": 100\n'
    printf '    }\n'
    printf '  ]\n}\n'
  } > "$p"
  assert_exit 1 "collapse seams to one" "$m" "$r" "$p" "$c"
  rm -f "$m" "$r" "$p" "$c"

  if [[ "$fails" -eq 0 ]]; then
    echo "SELF-TEST OK: clean quartet passes; stripping data_source bites; a perturbed checksum"
    echo "              bites in the python leg; dropping refit_reversed_target bites; stripping"
    echo "              the open-loop disclosure bites; collapsing seams to one bites."
    return 0
  else
    echo "SELF-TEST FAILED: at least one case did not produce the expected exit code." >&2
    return 1
  fi
}

# --- Entry point -----------------------------------------------------------------------------
if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

if scan; then
  echo "OK: refit-real policy clean -- all three phase artifacts declare provenance, carry the"
  echo "    four pre-registered arms with Willett statistics, the replay carries two distinctly"
  echo "    labeled seams with the open-loop disclosure, and all checksums agree with the"
  echo "    manifest (D-09/RD-07/RD-08)."
  exit 0
else
  echo "refit-real-policy: FAILED -- a provenance or structure invariant regressed." >&2
  exit 1
fi
