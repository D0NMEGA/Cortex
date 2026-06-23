#!/usr/bin/env bash
# Source: project-defined per 08-05-PLAN Task 3 (D-06/D-13) + 08-RESEARCH §8 (the BPS gate).
# Purpose: build-failing structural + determinism gate for the Webgrid information-rate BPS metric
# (PERF-01). Mirrors the Phase-1 validate-privacy-manifest.sh / Phase-3 hotpath-policy.sh / Phase-6
# render-policy.sh precedent — a static + dynamic proxy that FAILS CI the moment a future commit
# silently regresses the MANDATORY max(0,…) clamp, the log2(N) normalization, the committed JSON's
# documented formula/N, or the run-twice byte-identical determinism — WITH a negative-control
# --self-test that proves the gate bites (clamp-strip + formula-strip).
#
# The Webgrid BPS code + artifact this asserts already exist after 08-05 Tasks 1/2. This gate is the
# regression tripwire, not the implementation. The Phase-7 refit_bps.json + its CI guard are LEFT
# INTACT — this gate is ADDITIVE (it guards the separate webgrid_bps.json).
#
# ── REQUIRED-PRESENT (build-FAILS if a token is ABSENT) ───────────────────────────────────────
#   1. Swift.max(0,         (WebgridBPS.swift)  — the MANDATORY clamp (08-RESEARCH §0.4; CONTEXT D-11
#                                                 omitted it). A net-negative (Sc<Si) must never report
#                                                 a negative bitrate. Test 2 in WebgridBPSTests asserts
#                                                 it BITES; this gate asserts the token is PRESENT.
#   2. log2                 (WebgridBPS.swift)  — the log2(N) normalization that makes 30×30 comparable
#                                                 to BrainGate's 6×6 (PERF-01).
#   3. formula literal      (webgrid_bps.json)  — the DISCLOSURE pin `B = max(0, log2(N)*(Sc-Si)/t)`.
#                                                 NB: this is a DISCLOSURE pin, NOT the executed source
#                                                 of truth — the run-twice determinism leg + the
#                                                 WebgridBPSTests unit tests are the real correctness/
#                                                 stability guard; the string only catches a stale
#                                                 hand-edited JSON drifting from the documented formula.
#   4. n_targets 900        (webgrid_bps.json)  — N = 900 (the 30×30 grid incl. the delete/cancel key).
#
# ── DETERMINISM (build-FAILS if non-identical — D-13) ─────────────────────────────────────────
#   Run `swift run … CortexReFITBench --smoke` TWICE, capture .bench/webgrid_bps.json each time, and
#   `diff` them byte-for-byte. A non-identical pair fails. Guarded on `swift` availability (the
#   gen-flatbuffers.sh idiom): if swift is unavailable (e.g. a docs-only lint box), fall back to
#   diffing the COMMITTED webgrid_bps.json against a single fresh run is impossible without swift, so
#   the leg degrades to asserting the committed JSON simply exists + carries the formula/N (already
#   covered above) and prints a SKIP note. CI runs on a Swift toolchain, so the real run-twice leg fires.
#
# ── self-test (the negative control) ──────────────────────────────────────────────────────────
#   ./bps-policy.sh --self-test
#     (0) a CLEAN synthetic tree (stand-in WebgridBPS.swift WITH the clamp+log2, stand-in JSON WITH the
#         formula+n_targets) -> exit 0;
#     (1) strip the `Swift.max(0,` clamp from the stand-in source -> exit 1;
#     (2) strip the `formula` line from the stand-in JSON -> exit 1.
#   (The determinism leg is exercised by the REAL `swift run` in CI, not the synthetic self-test — the
#    self-test overrides the source/JSON scope and SKIPs the swift run, mirroring how render-policy.sh's
#    self-test exercises only the static greps.)
#
#   BPS_SWIFT_FILE=/tmp/w.swift BPS_JSON_FILE=/tmp/w.json ./bps-policy.sh   # repoint at a temp tree
#
# Exit codes:
#   0 -- clamp+log2 present, JSON formula+N present, run-twice byte-identical (real tree after 08-05)
#   1 -- a required token is missing OR the two runs differ (a regression)

set -euo pipefail

# ── Scope (overridable for the self-test, mirroring render-policy.sh's RENDER_DIR/PROJECT_FILE) ──
# BPS_SWIFT_FILE — the pure Webgrid BPS math source (default: the real WebgridBPS.swift).
# BPS_JSON_FILE  — the committed Webgrid BPS artifact (default: the real committed webgrid_bps.json).
# BPS_SKIP_DETERMINISM — set to 1 to skip the swift run-twice leg (the self-test sets this; it tests
#                        only the static greps on synthetic stand-ins, like render-policy.sh).
BPS_SWIFT_FILE="${BPS_SWIFT_FILE:-Packages/CortexReFIT/Sources/CortexReFIT/WebgridBPS.swift}"
BPS_JSON_FILE="${BPS_JSON_FILE:-.planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/webgrid_bps.json}"
BPS_SKIP_DETERMINISM="${BPS_SKIP_DETERMINISM:-0}"

# The generated artifact the determinism leg captures (the gitignored bench output).
BENCH_JSON="Packages/CortexReFIT/.bench/webgrid_bps.json"
# The DISCLOSURE formula literal (fixed-string — contains (), *, / so grep -F avoids regex headaches).
FORMULA_LITERAL='B = max(0, log2(N)*(Sc-Si)/t)'

# ── require_re_in_file: assert an ERE is PRESENT in a file. ($1=path, $2=ERE, $3=label) ─────────
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

# ── require_fixed_in_file: assert a FIXED STRING is PRESENT in a file. ($1=path, $2=string, $3=label) ─
require_fixed_in_file() {
  local path="$1" needle="$2" label="$3"
  if [[ ! -f "$path" ]]; then
    echo "ERROR [required-missing] $label: file not found: $path" >&2
    return 1
  fi
  if grep -nF -- "$needle" "$path" >/dev/null 2>&1; then
    echo "  ok  [required] $label  ($path)"
    return 0
  fi
  echo "ERROR [required-missing] $label: literal '$needle' not found in $path" >&2
  return 1
}

# ── check_determinism: run the bench --smoke TWICE and diff .bench/webgrid_bps.json byte-for-byte.
# Guarded on swift availability (gen-flatbuffers.sh idiom) + the self-test skip. ────────────────
check_determinism() {
  if [[ "$BPS_SKIP_DETERMINISM" == "1" ]]; then
    echo "  skip [determinism] BPS_SKIP_DETERMINISM=1 (self-test exercises only the static greps; the"
    echo "       run-twice leg fires on the real Swift toolchain in CI)."
    return 0
  fi
  if ! command -v swift >/dev/null 2>&1; then
    echo "  skip [determinism] swift not found — cannot run the harness twice on this box. The committed"
    echo "       webgrid_bps.json formula/N are still asserted above; CI runs on a Swift toolchain where"
    echo "       this run-twice byte-identical leg fires (D-13)."
    return 0
  fi
  echo "  .. [determinism] running CortexReFITBench --smoke twice for byte-identical webgrid_bps.json"
  local tmp1 tmp2
  tmp1="$(mktemp)"; tmp2="$(mktemp)"
  swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke >/dev/null 2>&1
  if [[ ! -f "$BENCH_JSON" ]]; then
    echo "ERROR [determinism] the bench did not write $BENCH_JSON on run 1" >&2
    rm -f "$tmp1" "$tmp2"; return 1
  fi
  cp "$BENCH_JSON" "$tmp1"
  swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke >/dev/null 2>&1
  cp "$BENCH_JSON" "$tmp2"
  if ! diff -q "$tmp1" "$tmp2" >/dev/null; then
    echo "ERROR [determinism] webgrid_bps.json is NOT byte-identical across two runs (D-13 violated):" >&2
    diff "$tmp1" "$tmp2" >&2 || true
    rm -f "$tmp1" "$tmp2"; return 1
  fi
  # Also assert the committed copy matches the regenerated output (regenerate-from-code provenance).
  if ! diff -q "$tmp2" "$BPS_JSON_FILE" >/dev/null; then
    echo "ERROR [determinism] the committed $BPS_JSON_FILE differs from the freshly-regenerated bench" >&2
    echo "       output — the committed artifact is stale/hand-edited (threat T-08-05-03). Diff:" >&2
    diff "$tmp2" "$BPS_JSON_FILE" >&2 || true
    rm -f "$tmp1" "$tmp2"; return 1
  fi
  echo "  ok  [determinism] webgrid_bps.json byte-identical across two runs AND == the committed copy."
  rm -f "$tmp1" "$tmp2"
  return 0
}

# ── scan: run every assertion. Returns 0 only if ALL pass. ──────────────────────────────────────
scan() {
  local rc=0

  echo "scanning Webgrid BPS source:   $BPS_SWIFT_FILE"
  echo "scanning committed BPS artifact: $BPS_JSON_FILE"

  # REQUIRED-PRESENT (1-4)
  require_re_in_file    "$BPS_SWIFT_FILE" 'Swift\.max\(0,' "MANDATORY max(0,…) clamp (08-RESEARCH §0.4, PERF-01)" || rc=1
  require_re_in_file    "$BPS_SWIFT_FILE" 'log2'           "log2(N) normalization (PERF-01)"                     || rc=1
  require_fixed_in_file "$BPS_JSON_FILE"  "$FORMULA_LITERAL" "formula disclosure pin (D-06)"                      || rc=1
  require_re_in_file    "$BPS_JSON_FILE"  '"n_targets"[[:space:]]*:[[:space:]]*900' "n_targets = 900 (30×30 incl. delete key)" || rc=1

  # DETERMINISM (run-twice byte-identical — D-13)
  check_determinism || rc=1

  return $rc
}

# Absolute path to THIS script (so the self-test can re-invoke it with overridden scope, mirroring
# render-policy.sh's SELF pattern).
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── self_test: the negative control. Prove the gate BITES on (1) a stripped clamp and (2) a stripped
# formula line, then prove a clean synthetic tree PASSES. The established Cortex discipline (the
# Phase-1 privacy-manifest negative control, the Phase-3/6 hotpath/render self-tests). ──────────
self_test() {
  local fails=0 rc

  # Run THIS script against an overridden source + JSON (determinism SKIPped — synthetic stand-ins
  # have no bench to run); assert the exit code. $1=expected exit, $2=label, $3=swift file, $4=json file.
  assert_exit() {
    local want="$1" label="$2" sfile="$3" jfile="$4"
    set +e
    ( env BPS_SWIFT_FILE="$sfile" BPS_JSON_FILE="$jfile" BPS_SKIP_DETERMINISM=1 bash "$SELF" ) >/dev/null 2>&1
    rc=$?
    set -e
    if [[ "$rc" -eq "$want" ]]; then
      echo "  PASS [$label] exit=$rc (expected $want)"
    else
      echo "  FAIL [$label] exit=$rc (expected $want)" >&2
      fails=1
    fi
  }

  # write_clean: a CLEAN synthetic stand-in source (WITH the clamp + log2) + JSON (WITH the formula +
  # n_targets). Each negative-control case then mutates exactly one thing and re-asserts.
  write_clean() {
    local sfile="$1" jfile="$2"
    {
      printf 'public enum WebgridBPS {\n'
      printf '  public static func targetBits(n: Int) -> Double { guard n >= 2 else { return 0 }; return log2(Double(n)) }\n'
      printf '  public static func bitsPerSecond(n: Int, correct: Int, incorrect: Int, seconds: Double) -> Double {\n'
      printf '    guard seconds > 0 else { return 0 }\n'
      printf '    return Swift.max(0, targetBits(n: n) * Double(correct - incorrect) / seconds)\n'
      printf '  }\n}\n'
    } > "$sfile"
    {
      printf '{\n'
      printf '  "formula" : "B = max(0, log2(N)*(Sc-Si)/t)",\n'
      printf '  "n_targets" : 900,\n'
      printf '  "refit_webgrid_bps" : 1.953\n'
      printf '}\n'
    } > "$jfile"
  }

  echo "== bps-policy self-test =="

  local s j
  # 0. Baseline: the clean synthetic tree must PASS (exit 0). If this fails, the stand-in is wrong.
  echo "-- clean synthetic tree --"
  s="$(mktemp)"; j="$(mktemp)"; write_clean "$s" "$j"
  assert_exit 0 "clean tree" "$s" "$j"; rm -f "$s" "$j"

  # 1. Strip the `Swift.max(0,` clamp from the source -> exit 1 (the mandatory-clamp negative control).
  echo "-- clamp-strip negative control (strip Swift.max(0, -> exit 1) --"
  s="$(mktemp)"; j="$(mktemp)"; write_clean "$s" "$j"
  # Rewrite the source WITHOUT the clamp (raw, unclamped formula — the CONTEXT D-11 regression).
  {
    printf 'public enum WebgridBPS {\n'
    printf '  public static func targetBits(n: Int) -> Double { guard n >= 2 else { return 0 }; return log2(Double(n)) }\n'
    printf '  public static func bitsPerSecond(n: Int, correct: Int, incorrect: Int, seconds: Double) -> Double {\n'
    printf '    guard seconds > 0 else { return 0 }\n'
    printf '    return targetBits(n: n) * Double(correct - incorrect) / seconds\n'  # <- no clamp
    printf '  }\n}\n'
  } > "$s"
  assert_exit 1 "strip Swift.max(0, clamp" "$s" "$j"; rm -f "$s" "$j"

  # 2. Strip the `formula` line from the JSON -> exit 1 (the formula-disclosure negative control).
  echo "-- formula-strip negative control (strip formula line -> exit 1) --"
  s="$(mktemp)"; j="$(mktemp)"; write_clean "$s" "$j"
  {
    printf '{\n'
    printf '  "n_targets" : 900,\n'
    printf '  "refit_webgrid_bps" : 1.953\n'   # <- formula line removed
    printf '}\n'
  } > "$j"
  assert_exit 1 "strip formula line" "$s" "$j"; rm -f "$s" "$j"

  if [[ "$fails" -eq 0 ]]; then
    echo "SELF-TEST OK: a clean tree passes; stripping the Swift.max(0, clamp bites; stripping the"
    echo "              formula line bites. (The run-twice determinism leg fires on the real toolchain in CI.)"
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
  echo "OK: bps policy clean — clamp + log2 + formula + N present, webgrid_bps.json run-twice byte-identical."
  exit 0
else
  echo "bps-policy: FAILED — a Webgrid BPS invariant regressed (see ERROR lines above)." >&2
  exit 1
fi
