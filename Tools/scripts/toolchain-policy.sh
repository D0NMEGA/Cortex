#!/usr/bin/env bash
# Source: project-defined per 10-15-PLAN Task 1 (D-18) + 10-CONTEXT D-18.
# Purpose: build-failing gate that ties the lint VERDICT to the lint TOOL VERSION it was measured
# under. Mirrors the Phase-9 decoder-policy.sh shape (env-overridable scope, scan, SELF, assert_exit,
# write_clean, --self-test dispatch) and the Phase-1 validate-privacy-manifest.sh negative-control
# idiom: a static gate plus a --self-test that proves the gate BITES.
#
# --- WHY -------------------------------------------------------------------------------------
# ci.yml installs SwiftFormat and SwiftLint with a bare `brew install`, which is UNPINNED. The
# violation count on a runner is therefore whatever Homebrew shipped that morning. Phase 10 spends
# two plans clearing the repo's SwiftFormat and SwiftLint backlog; a sweep measured under
# 0.61.1/0.63.3 and then gated under some later pair is not a remediation, it is a coin flip. This
# gate converts silent version drift into a loud, deliberate decision.
#
# --- ASSERTIONS (build FAILS on any) ---------------------------------------------------------
#   (a) pin-present   The pin file exists and defines SWIFTFORMAT_VERSION and SWIFTLINT_VERSION,
#                     both non-empty. A pin file that lost a variable pins nothing.
#   (b) swiftformat   `swiftformat --version` equals SWIFTFORMAT_VERSION. If swiftformat is absent
#                     the leg prints a `skip` line NAMING what was not checked -- never a silent pass.
#   (c) swiftlint     `swiftlint version` equals SWIFTLINT_VERSION, same skip discipline.
#   (d) ci-wired      .github/workflows/ci.yml references Tools/toolchain-versions.env, so a future
#                     edit that drops the pin from CI fails HERE rather than silently un-pinning the
#                     runner. This leg is why the gate is not just a local convenience.
#
# --- REJECTED ALTERNATIVE --------------------------------------------------------------------
# Downloading pinned GitHub release artifacts and verifying them by sha256 would be a HARDER pin:
# it would defeat a compromised Homebrew bottle, not merely a version bump. It was rejected. It adds
# a supply-chain surface of its own (a release URL and a checksum this repo would then have to keep
# current), plus a download step to every CI run, and this project's Homebrew-based install path is
# already established from Phase 1. The property that actually matters here is that drift becomes
# LOUD and DELIBERATE rather than invisible, and assert-and-fail delivers exactly that at zero added
# supply-chain surface. Threat T-10-15-07 records the residual (a substituted bottle at the pinned
# version) as ACCEPTED.
#
# --- self-test (the negative control) --------------------------------------------------------
#   ./toolchain-policy.sh --self-test
#     (0) a CLEAN stand-in pin whose versions match the locally installed tools -> exit 0 (if this
#         fails the stand-in is wrong, and a gate that always fails is as useless as one that never
#         does);
#     (1) delete SWIFTFORMAT_VERSION from the stand-in                          -> exit 1 (leg a);
#     (2) set SWIFTLINT_VERSION to the impossible 0.0.0                         -> exit 1 (leg c);
#     (3) point TOOLCHAIN_PIN_FILE at a nonexistent path                        -> exit 1 (leg a);
#     (4) point TOOLCHAIN_CI_FILE at a ci.yml stand-in with the pin reference stripped -> exit 1
#         (leg d). Added beyond the plan's three: leg (d) is the leg that catches a future edit
#         un-pinning CI, and an assertion with no negative control has not been shown to bite.
#   Each case mutates exactly ONE thing relative to the clean stand-in.
#
#   Cases 1 and 2 REQUIRE the tools to be installed: if swiftformat/swiftlint are absent the version
#   legs skip, the negative control cannot bite, and the self-test FAILS rather than reporting OK --
#   the decoder-policy.sh python3 discipline. ci.yml installs both immediately before this step.
#
#   TOOLCHAIN_PIN_FILE=/tmp/pin.env ./toolchain-policy.sh
#
# Exit codes:
#   0 -- the pin is complete, the installed tools match it, and CI still references it
#   1 -- an assertion failed (see the ERROR lines)

set -euo pipefail

# --- Scope (overridable for the self-test, the decoder-policy.sh DECODER_*_FILE pattern) ----------
# TOOLCHAIN_PIN_FILE -- the committed pin the installed tools are asserted against.
# TOOLCHAIN_CI_FILE  -- the workflow that must keep referencing that pin.
TOOLCHAIN_PIN_FILE="${TOOLCHAIN_PIN_FILE:-Tools/toolchain-versions.env}"
TOOLCHAIN_CI_FILE="${TOOLCHAIN_CI_FILE:-.github/workflows/ci.yml}"

# The literal ci.yml must carry. Kept as a variable so the ERROR message and the grep cannot drift.
PIN_PATH_LITERAL='Tools/toolchain-versions.env'

# --- read_pin: parse one KEY=VALUE out of the pin file WITHOUT sourcing it. ($1=key) --------------
# Deliberately not `source`: the pin file is data, and a gate that executes the thing it is policing
# can be made to pass by that thing. sed also tolerates trailing whitespace and inline comments.
read_pin() {
  local key="$1"
  sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*([^#[:space:]]+).*/\1/p" \
    "$TOOLCHAIN_PIN_FILE" 2>/dev/null | tail -1
}

# --- check_pin_present: assertion (a). The pin file exists and defines both variables. ------------
check_pin_present() {
  local path="$TOOLCHAIN_PIN_FILE" rc=0 key val
  if [[ ! -f "$path" ]]; then
    echo "ERROR [pin-present] pin file not found: $path" >&2
    echo "       The lint toolchain is then UNPINNED and the violation count on a runner is whatever" >&2
    echo "       Homebrew ships that day (D-18). Restore Tools/toolchain-versions.env." >&2
    return 1
  fi
  for key in SWIFTFORMAT_VERSION SWIFTLINT_VERSION; do
    val="$(read_pin "$key")"
    if [[ -z "$val" ]]; then
      echo "ERROR [pin-present] $key is missing or empty in $path. A pin file that lost a variable" >&2
      echo "       pins nothing: that tool's version on a runner becomes whatever brew installs." >&2
      rc=1
    else
      echo "  ok  [pin-present] $key=$val  ($path)"
    fi
  done
  return $rc
}

# --- check_tool_version: assertions (b) and (c). ($1=tool, $2=version argv, $3=pin key) -----------
# Guarded on tool availability, the bps-policy.sh/decoder-policy.sh idiom: a missing tool prints a
# skip line NAMING what went unchecked rather than silently passing.
check_tool_version() {
  local tool="$1" version_arg="$2" key="$3" pinned installed
  pinned="$(read_pin "$key")"
  if [[ -z "$pinned" ]]; then
    # check_pin_present already reported this; do not double-count it as a second failure.
    return 0
  fi
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "  skip [$tool] not found on PATH, so its version was NOT checked against the pinned"
    echo "       $key=$pinned. CI installs it immediately before this gate runs, so this"
    echo "       leg fires there; locally it means the sweep cannot be reproduced on this box."
    return 0
  fi
  installed="$("$tool" "$version_arg" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$installed" == "$pinned" ]]; then
    echo "  ok  [$tool] installed $installed == pinned $pinned"
    return 0
  fi
  echo "ERROR [$tool] version drift: installed $installed, pinned $pinned ($key in $TOOLCHAIN_PIN_FILE)." >&2
  echo "       The committed lint baseline and the Phase-10 sweep were measured under $pinned, so a" >&2
  echo "       verdict from $installed is not comparable to them. REMEDY, in ONE commit: re-run the" >&2
  echo "       sweep under $installed, update" >&2
  echo "       .planning/phases/10-v1-real-data-closed-loop-launch/10-lint-baseline.md with the new" >&2
  echo "       counts, THEN set $key=$installed here. Do not bump the pin alone -- that" >&2
  echo "       silently re-points the gate at an unmeasured version, which is the drift this gate" >&2
  echo "       exists to catch." >&2
  return 1
}

# --- check_ci_wired: assertion (d). ci.yml still references the pin. ------------------------------
check_ci_wired() {
  local path="$TOOLCHAIN_CI_FILE"
  if [[ ! -f "$path" ]]; then
    echo "ERROR [ci-wired] workflow not found: $path" >&2
    return 1
  fi
  if grep -qF -- "$PIN_PATH_LITERAL" "$path"; then
    echo "  ok  [ci-wired] $path references $PIN_PATH_LITERAL"
    return 0
  fi
  echo "ERROR [ci-wired] $path no longer references $PIN_PATH_LITERAL, so the runner's lint" >&2
  echo "       toolchain is un-pinned again and CI's verdict is version-dependent (D-18). Restore the" >&2
  echo "       pin sourcing in the 'Install tooling' step." >&2
  return 1
}

# --- scan: run every assertion. Returns 0 only if ALL pass. ---------------------------------------
scan() {
  local rc=0

  echo "scanning toolchain pin: $TOOLCHAIN_PIN_FILE"
  echo "scanning workflow:      $TOOLCHAIN_CI_FILE"

  # (a) The pin is complete.
  check_pin_present || rc=1

  # (b)(c) The installed tools match it.
  check_tool_version swiftformat --version SWIFTFORMAT_VERSION || rc=1
  check_tool_version swiftlint version SWIFTLINT_VERSION || rc=1

  # (d) CI still uses it.
  check_ci_wired || rc=1

  return $rc
}

# Absolute path to THIS script, so the self-test can re-invoke it with overridden scope
# (the decoder-policy.sh / bps-policy.sh SELF pattern).
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# --- self_test: the negative control. Prove a clean pin passes and that each assertion bites. -----
self_test() {
  local fails=0 rc

  # Re-run THIS script against an overridden pin + workflow and assert the exit code.
  # $1=expected exit, $2=label, $3=pin file, $4=ci file.
  assert_exit() {
    local want="$1" label="$2" pfile="$3" cfile="$4"
    set +e
    ( env TOOLCHAIN_PIN_FILE="$pfile" TOOLCHAIN_CI_FILE="$cfile" bash "$SELF" ) >/dev/null 2>&1
    rc=$?
    set -e
    if [[ "$rc" -eq "$want" ]]; then
      echo "  PASS [$label] exit=$rc (expected $want)"
    else
      echo "  FAIL [$label] exit=$rc (expected $want)" >&2
      fails=1
    fi
  }

  # write_clean: a CLEAN stand-in pin whose versions are the ones ACTUALLY installed on this box, so
  # the baseline case must pass here regardless of which versions that is. Each case below then
  # mutates exactly one thing.
  write_clean() {
    local pfile="$1"
    {
      printf '# stand-in pin written by toolchain-policy.sh --self-test\n'
      printf 'SWIFTFORMAT_VERSION=%s\n' "$SF_INSTALLED"
      printf 'SWIFTLINT_VERSION=%s\n' "$SL_INSTALLED"
    } > "$pfile"
  }

  echo "== toolchain-policy self-test =="

  # The version legs SKIP when a tool is absent, which would make cases 1 and 2 unable to bite. A
  # negative control that cannot fire has not proven anything, so fail loudly instead of reporting OK
  # (the decoder-policy.sh python3 precedent).
  local missing=""
  command -v swiftformat >/dev/null 2>&1 || missing="$missing swiftformat"
  command -v swiftlint >/dev/null 2>&1 || missing="$missing swiftlint"
  if [[ -n "$missing" ]]; then
    echo "SELF-TEST FAILED: not installed:$missing. The version legs would SKIP, so the drift" >&2
    echo "                  negative controls could not bite and this self-test would report OK" >&2
    echo "                  without having tested anything. Install them and re-run." >&2
    return 1
  fi

  local SF_INSTALLED SL_INSTALLED p c
  SF_INSTALLED="$(swiftformat --version 2>/dev/null | tr -d '[:space:]')"
  SL_INSTALLED="$(swiftlint version 2>/dev/null | tr -d '[:space:]')"
  echo "   installed: swiftformat $SF_INSTALLED / swiftlint $SL_INSTALLED"

  # 0. Baseline: a stand-in pin matching the installed tools must PASS (exit 0).
  echo "-- clean stand-in pin --"
  p="$(mktemp)"; write_clean "$p"
  assert_exit 0 "clean pin" "$p" "$TOOLCHAIN_CI_FILE"; rm -f "$p"

  # 1. Delete SWIFTFORMAT_VERSION -> exit 1 (assertion (a)).
  echo "-- missing-variable negative control (a half-pin pins nothing -> exit 1) --"
  p="$(mktemp)"
  printf 'SWIFTLINT_VERSION=%s\n' "$SL_INSTALLED" > "$p"
  assert_exit 1 "delete SWIFTFORMAT_VERSION" "$p" "$TOOLCHAIN_CI_FILE"; rm -f "$p"

  # 2. Pin swiftlint to an impossible version -> exit 1 (assertion (c)). This is the drift case: the
  #    file is well-formed and complete, and only the comparison against the INSTALLED tool catches it.
  echo "-- version-drift negative control (well-formed pin, impossible version -> exit 1) --"
  p="$(mktemp)"
  {
    printf 'SWIFTFORMAT_VERSION=%s\n' "$SF_INSTALLED"
    printf 'SWIFTLINT_VERSION=0.0.0\n'
  } > "$p"
  assert_exit 1 "pin swiftlint to 0.0.0" "$p" "$TOOLCHAIN_CI_FILE"; rm -f "$p"

  # 3. Point at a nonexistent pin file -> exit 1 (assertion (a)).
  echo "-- missing-file negative control (no pin at all -> exit 1) --"
  assert_exit 1 "nonexistent pin file" "/nonexistent/toolchain-versions.env" "$TOOLCHAIN_CI_FILE"

  # 4. A workflow that no longer references the pin -> exit 1 (assertion (d)). The pin itself is
  #    clean here, so ONLY the ci-wired leg can catch it. That is what makes this a test of leg (d).
  echo "-- un-wired-CI negative control (pin dropped from the workflow -> exit 1) --"
  p="$(mktemp)"; write_clean "$p"
  c="$(mktemp)"
  if [[ -f "$TOOLCHAIN_CI_FILE" ]]; then
    grep -vF -- "$PIN_PATH_LITERAL" "$TOOLCHAIN_CI_FILE" > "$c" || true
  else
    printf 'name: stand-in\n' > "$c"
  fi
  assert_exit 1 "strip the pin reference from ci.yml" "$p" "$c"; rm -f "$p" "$c"

  if [[ "$fails" -eq 0 ]]; then
    echo "SELF-TEST OK: a pin matching the installed tools passes; a half-written pin bites; a"
    echo "              well-formed pin naming a version that is not installed bites; a missing pin"
    echo "              file bites; and a workflow that dropped the pin reference bites."
    return 0
  else
    echo "SELF-TEST FAILED: at least one negative control did not bite (or the clean pin failed)." >&2
    return 1
  fi
}

# --- Entry point ---------------------------------------------------------------------------------
if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

if scan; then
  echo "OK: lint toolchain pinned -- the installed SwiftFormat and SwiftLint match the committed pin,"
  echo "    and CI still sources it, so the lint verdict is reproducible rather than date-dependent."
  exit 0
else
  echo "toolchain-policy: FAILED -- the lint toolchain pin regressed (see ERROR lines above)." >&2
  exit 1
fi
