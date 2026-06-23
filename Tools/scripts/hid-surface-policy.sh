#!/usr/bin/env bash
# Source: project-defined per CONTEXT.md D-04/D-06 and RESEARCH.md §1/§8 (the HID surface gate tokens).
# Purpose: build-failing structural grep gate for the Apple BCI HID surface's LOAD-BEARING commitments
# (SYS-01/05/06 structural). Mirrors the Phase-1 validate-privacy-manifest.sh / Phase-3 hotpath-policy.sh
# / Phase-6 render-policy.sh precedent — a static proxy that FAILS CI the moment a future commit
# silently (a) drops the ported descriptor's Usage-Page bytes, (b) drops one of the 5 report structs,
# (c) drops the virtual.device entitlement declaration, (d) weakens the #if CORTEX_HID_LIVE gate, or
# (e) ungates the live IOHIDUserDevice symbol into the free-team demo binary — WITH a negative-control
# --self-test that proves every check bites (and that a gated live symbol is ALLOWED).
#
# The surface this asserts already exists in Packages/CortexBCIHID + Apps/Cortex*/Cortex.entitlements
# after Plan 08-01 Tasks 1-2. This gate is the regression tripwire, not the implementation.
#
# ── REQUIRED-PRESENT (build-FAILS if a token is ABSENT) ───────────────────────────────────────────
#   1. Usage-Page byte pair 0x05,0x60          (BCIHIDDescriptor.swift) — the "Brain Control Interface"
#                                               page that anchors the ported descriptor (SYS-05).
#   2. all 5 report-struct names               (BCIHIDReports.swift)    — Signal/Button/Pointer/
#                                               ItemSelection/ScanInfo ports (SYS-01, T-08-01-01).
#   3. com.apple.developer.hid.virtual.device  (each of 3 entitlements) — the declared-and-gated HID
#                                               entitlement (SYS-01, D-04, T-08-01-04).
#   4. #if CORTEX_HID_LIVE                      (VirtualDeviceGate.swift)— the compile gate keeping the
#                                               live instantiation out of the free-team binary (D-04/D-06).
#
# ── FORBIDDEN ─────────────────────────────────────────────────────────────────────────────────────
#   A. the live IOHIDUserDevice report symbol MUST NOT appear in any CortexBCIHID source file that lacks
#      a #if CORTEX_HID_LIVE guard (T-08-01-02: an ungated live symbol AMFI-SIGKILLs the demo binary).
#      SCOPED like render-policy's iOS-only CADisplayLink check: the symbol is legal ONLY in a gated
#      file (VirtualDeviceGate.swift), so the self-test (iii) injects it into a NON-gated file to prove
#      the check bites, and (iv) proves a #if-CORTEX_HID_LIVE-wrapped occurrence is ALLOWED.
#   B. the Mac + Daemon entitlement files MUST NOT declare com.apple.security.app-sandbox — the Phase-1
#      Critical-Finding-#1 no-sandbox invariant, re-scoped to the HID gate (unsandboxed Mac binaries
#      use the App Group / declared entitlements without provisioning-profile authorization under free
#      signing). The iOS target is NOT checked here (iOS apps are always sandboxed).
#
# NOTE on token forms (literal-grep discipline, the Cortex Phase 1-6 reword precedent): the live symbol
# token is the literal `IOHIDUserDeviceHandleReportWithTimeStamp`. Any source comment that must mention
# it lives INSIDE the gated file (which carries #if CORTEX_HID_LIVE), so the scoped check stays green;
# the --self-test injects the literal into a NON-gated synthetic file to prove a genuine regression bites.
#
# Self-test:
#   ./hid-surface-policy.sh --self-test   # (0) clean synthetic tree -> exit 0; (i) strip each required
#                                         # token -> exit 1; (iii) inject the live symbol into a NON-gated
#                                         # file -> exit 1; (iv) the SAME symbol inside #if CORTEX_HID_LIVE
#                                         # -> exit 0 (scoping control); (B) inject app-sandbox -> exit 1.
#   HID_DIR=/tmp/syn ENT_DIR=/tmp/ent ./hid-surface-policy.sh   # repoint at a temp tree
#
# Exit codes:
#   0 -- all required tokens present, no forbidden tokens (the real tree after Tasks 1-2)
#   1 -- a required token is missing OR a forbidden token appears (a regression)

set -euo pipefail

# ── Scope (overridable for the self-test, mirroring render-policy.sh's RENDER_DIR/PROJECT_FILE) ─────
# HID_DIR — the CortexBCIHID source tree (default: the real package sources).
# ENT_DIR — the directory of per-target entitlement files (default: Apps; the 3 files are found under it).
HID_DIR="${HID_DIR:-Packages/CortexBCIHID/Sources/CortexBCIHID}"
ENT_DIR="${ENT_DIR:-Apps}"

# Per-file relative names (resolved under HID_DIR / ENT_DIR). Scoping each assertion to its owning file
# is the whole point — a token in the wrong file is as much a regression as a missing one.
DESCRIPTOR="BCIHIDDescriptor.swift"
REPORTS="BCIHIDReports.swift"
GATE="VirtualDeviceGate.swift"
ENT_MAC="CortexMac/Cortex.entitlements"
ENT_IOS="CortexiOS/Cortex.entitlements"
ENT_DAEMON="CortexDaemon/Cortex.entitlements"

# The 5 ported report-struct names (SYS-01). All must be present in REPORTS.
REPORT_STRUCTS=(
  "BCIInputSignalReport"
  "BCIInputButtonReport"
  "BCIInputPointerReport"
  "BCIInputItemSelection"
  "BCIOutputScanInfoReport"
)

# The live HID report symbol that must never appear ungated (forbidden A).
LIVE_SYMBOL="IOHIDUserDeviceHandleReportWithTimeStamp"

# ── require_in_file: assert a regex is PRESENT in a specific file under HID_DIR. Missing file or
# missing token is a FAIL. ($1=file under HID_DIR, $2=ERE, $3=label) ────────────────────────────────
require_in_file() {
  local rel="$1" pattern="$2" label="$3" path="$HID_DIR/$1"
  if [[ ! -f "$path" ]]; then
    echo "ERROR [required-missing] $label: file not found: $path" >&2
    return 1
  fi
  if grep -nE "$pattern" "$path" >/dev/null 2>&1; then
    echo "  ok  [required] $label  ($rel)"
    return 0
  fi
  echo "ERROR [required-missing] $label: '$pattern' not found in $rel" >&2
  return 1
}

# ── require_in_ent: assert a fixed string is PRESENT in an entitlement file under ENT_DIR.
# ($1=file under ENT_DIR, $2=string, $3=label) ──────────────────────────────────────────────────────
require_in_ent() {
  local rel="$1" needle="$2" label="$3" path="$ENT_DIR/$1"
  if [[ ! -f "$path" ]]; then
    echo "ERROR [required-missing] $label: entitlement file not found: $path" >&2
    return 1
  fi
  if grep -nF "$needle" "$path" >/dev/null 2>&1; then
    echo "  ok  [required] $label  ($rel)"
    return 0
  fi
  echo "ERROR [required-missing] $label: '$needle' not found in $rel" >&2
  return 1
}

# ── forbid_ungated_live_symbol: the SCOPED forbidden check. For every *.swift under HID_DIR, if the
# file references the live symbol it MUST also contain the #if CORTEX_HID_LIVE guard. A live symbol in
# a file WITHOUT the guard is a FAIL. (Mirrors render-policy's per-file-scoped forbidden idiom.) ──────
forbid_ungated_live_symbol() {
  local label="no ungated live HID symbol (T-08-01-02)" rc=0
  if [[ ! -d "$HID_DIR" ]]; then
    echo "  ok  [forbidden-absent] $label  ($HID_DIR missing -> vacuously clean)"
    return 0
  fi
  local f
  while IFS= read -r f; do
    if grep -qF "$LIVE_SYMBOL" "$f"; then
      if grep -qE '#if[[:space:]]+CORTEX_HID_LIVE' "$f"; then
        echo "  ok  [forbidden-scoped] $label: '$LIVE_SYMBOL' in $(basename "$f") is #if CORTEX_HID_LIVE-gated"
      else
        echo "ERROR [forbidden-present] $label: '$LIVE_SYMBOL' in $(basename "$f") WITHOUT a #if CORTEX_HID_LIVE guard" >&2
        rc=1
      fi
    fi
  done < <(find "$HID_DIR" -type f -name '*.swift' | sort)
  return $rc
}

# ── forbid_in_ent: assert a fixed string is ABSENT from an entitlement file (scoped forbidden check).
# Missing file is vacuously clean. ($1=file under ENT_DIR, $2=string, $3=label) ─────────────────────
forbid_in_ent() {
  local rel="$1" needle="$2" label="$3" path="$ENT_DIR/$1"
  if [[ ! -f "$path" ]]; then
    echo "  ok  [forbidden-absent] $label  ($rel missing -> vacuously clean)"
    return 0
  fi
  if grep -nF "$needle" "$path" >/dev/null 2>&1; then
    echo "ERROR [forbidden-present] $label: '$needle' found in $rel" >&2
    return 1
  fi
  echo "  ok  [forbidden-absent] $label  ($rel)"
  return 0
}

# ── scan: run every assertion. Returns 0 only if ALL pass. Used for the real tree and (with
# HID_DIR/ENT_DIR overridden) by the self-test. ─────────────────────────────────────────────────────
scan() {
  local rc=0

  echo "scanning CortexBCIHID sources: $HID_DIR"
  echo "scanning entitlement files:    $ENT_DIR"

  # REQUIRED-PRESENT (1-4)
  #   1. Usage-Page byte pair (tolerant of optional whitespace after the comma).
  require_in_file "$DESCRIPTOR" '0x05,[[:space:]]*0x60' "descriptor Usage-Page 0x05,0x60 (SYS-05)" || rc=1
  #   2. all 5 report-struct names.
  local s
  for s in "${REPORT_STRUCTS[@]}"; do
    require_in_file "$REPORTS" "$s" "report struct $s (SYS-01)" || rc=1
  done
  #   3. the virtual.device entitlement in each of the 3 entitlement files.
  require_in_ent "$ENT_MAC"    "com.apple.developer.hid.virtual.device" "HID entitlement (Mac, SYS-01/D-04)"    || rc=1
  require_in_ent "$ENT_IOS"    "com.apple.developer.hid.virtual.device" "HID entitlement (iOS, SYS-01/D-04)"    || rc=1
  require_in_ent "$ENT_DAEMON" "com.apple.developer.hid.virtual.device" "HID entitlement (Daemon, SYS-01/D-04)" || rc=1
  #   4. the compile gate.
  require_in_file "$GATE" '#if[[:space:]]+CORTEX_HID_LIVE' "#if CORTEX_HID_LIVE gate (D-04/D-06)" || rc=1

  # FORBIDDEN (A-B)
  #   A. no ungated live IOHIDUserDevice symbol anywhere in the CortexBCIHID sources.
  forbid_ungated_live_symbol || rc=1
  #   B. no app-sandbox on the Mac + Daemon entitlement files (Phase-1 CF#1 invariant, HID-scoped).
  forbid_in_ent "$ENT_MAC"    "com.apple.security.app-sandbox" "no app-sandbox (Mac, CF#1)"    || rc=1
  forbid_in_ent "$ENT_DAEMON" "com.apple.security.app-sandbox" "no app-sandbox (Daemon, CF#1)" || rc=1

  return $rc
}

# Absolute path to THIS script (so the self-test can re-invoke it with overridden scope, mirroring
# render-policy.sh's SELF pattern).
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── self_test: the negative control. Prove the gate BITES on (i) each missing required token and
# (iii) an injected ungated live symbol, prove (iv) a gated live symbol is ALLOWED, prove (B) an
# injected app-sandbox bites, and prove (0) a clean synthetic tree PASSES. ──────────────────────────
self_test() {
  local fails=0 rc

  # Run THIS script against an overridden HID_DIR + ENT_DIR; assert the exit code.
  # $1 = expected exit (0 clean / 1 bite); $2 = label; $3 = HID_DIR; $4 = ENT_DIR.
  assert_exit() {
    local want="$1" label="$2" hdir="$3" edir="$4"
    set +e
    ( env HID_DIR="$hdir" ENT_DIR="$edir" bash "$SELF" ) >/dev/null 2>&1
    rc=$?
    set -e
    if [[ "$rc" -eq "$want" ]]; then
      echo "  PASS [$label] exit=$rc (expected $want)"
    else
      echo "  FAIL [$label] exit=$rc (expected $want)" >&2
      fails=1
    fi
  }

  # write_clean_tree: populate $1 (a CortexBCIHID source dir) + $2 (an entitlements root with the 3
  # files) with a CLEAN synthetic stand-in containing EVERY required token and NO forbidden token. Each
  # negative-control case then mutates exactly one thing and re-asserts.
  write_clean_tree() {
    local hdir="$1" edir="$2"
    mkdir -p "$hdir" "$edir/CortexMac" "$edir/CortexiOS" "$edir/CortexDaemon"
    # Descriptor: the Usage-Page byte pair.
    printf 'public enum BCIHIDDescriptor { static let bytes: [UInt8] = [0x05, 0x60, 0x09, 0x01] }\n' > "$hdir/$DESCRIPTOR"
    # Reports: all 5 struct names.
    {
      printf 'public struct BCIInputSignalReport {}\n'
      printf 'public struct BCIInputButtonReport {}\n'
      printf 'public struct BCIInputPointerReport {}\n'
      printf 'public struct BCIInputItemSelection {}\n'
      printf 'public struct BCIOutputScanInfoReport {}\n'
    } > "$hdir/$REPORTS"
    # Gate: contains #if CORTEX_HID_LIVE, and the live symbol ONLY inside that gate (the allowed case).
    {
      printf 'public enum VirtualDeviceGate {\n'
      printf '#if CORTEX_HID_LIVE\n'
      printf '  static func send() { %s(d, t, &b, n) }\n' "$LIVE_SYMBOL"
      printf '#else\n'
      printf '  public static let isLive = false\n'
      printf '#endif\n'
      printf '}\n'
    } > "$hdir/$GATE"
    # The 3 entitlement files: each declares the HID key, none declares app-sandbox.
    local ent
    for ent in CortexMac CortexiOS CortexDaemon; do
      {
        printf '<plist><dict>\n'
        printf '  <key>com.apple.developer.hid.virtual.device</key><true/>\n'
        printf '</dict></plist>\n'
      } > "$edir/$ent/Cortex.entitlements"
    done
  }

  echo "== hid-surface-policy self-test =="

  # 0. Baseline: the clean synthetic tree must PASS (exit 0). If this fails, the stand-in is wrong.
  echo "-- clean synthetic tree --"
  local h e
  h="$(mktemp -d)"; e="$(mktemp -d)"
  write_clean_tree "$h" "$e"
  assert_exit 0 "clean tree" "$h" "$e"
  rm -rf "$h" "$e"

  # 1. REQUIRED negative-controls: strip exactly one required token; the gate MUST exit 1.
  echo "-- required-token negative controls (strip -> exit 1) --"

  # 1a. Strip the Usage-Page bytes from the descriptor -> exit 1.
  h="$(mktemp -d)"; e="$(mktemp -d)"; write_clean_tree "$h" "$e"
  printf 'public enum BCIHIDDescriptor { static let bytes: [UInt8] = [0x09, 0x01] }\n' > "$h/$DESCRIPTOR"
  assert_exit 1 "strip descriptor Usage-Page bytes" "$h" "$e"; rm -rf "$h" "$e"

  # 1b. Strip one report struct (drop BCIOutputScanInfoReport) -> exit 1.
  h="$(mktemp -d)"; e="$(mktemp -d)"; write_clean_tree "$h" "$e"
  {
    printf 'public struct BCIInputSignalReport {}\n'
    printf 'public struct BCIInputButtonReport {}\n'
    printf 'public struct BCIInputPointerReport {}\n'
    printf 'public struct BCIInputItemSelection {}\n'
  } > "$h/$REPORTS"
  assert_exit 1 "strip report struct BCIOutputScanInfoReport" "$h" "$e"; rm -rf "$h" "$e"

  # 1c. Strip the HID entitlement from the Daemon file -> exit 1.
  h="$(mktemp -d)"; e="$(mktemp -d)"; write_clean_tree "$h" "$e"
  printf '<plist><dict></dict></plist>\n' > "$e/CortexDaemon/Cortex.entitlements"
  assert_exit 1 "strip HID entitlement (Daemon)" "$h" "$e"; rm -rf "$h" "$e"

  # 1d. Strip the #if CORTEX_HID_LIVE gate -> exit 1 (required-missing).
  #     The synthetic gate file drops the guard AND the live symbol (so this isolates the missing-gate
  #     failure rather than also tripping the forbidden check).
  h="$(mktemp -d)"; e="$(mktemp -d)"; write_clean_tree "$h" "$e"
  printf 'public enum VirtualDeviceGate { public static let isLive = false }\n' > "$h/$GATE"
  assert_exit 1 "strip #if CORTEX_HID_LIVE gate" "$h" "$e"; rm -rf "$h" "$e"

  # 2. FORBIDDEN negative-controls.
  echo "-- forbidden-token negative controls --"

  # 2a (iii). Inject the live symbol into a NON-gated source file -> exit 1 (T-08-01-02).
  h="$(mktemp -d)"; e="$(mktemp -d)"; write_clean_tree "$h" "$e"
  printf 'enum Leak { static func go() { %s(d, t, &b, n) } }\n' "$LIVE_SYMBOL" > "$h/Leak.swift"
  assert_exit 1 "inject ungated live symbol (non-gated file)" "$h" "$e"; rm -rf "$h" "$e"

  # 2b (iv). CONTROL: the SAME live symbol WRAPPED in #if CORTEX_HID_LIVE must NOT trip the gate
  #          (the scoping control, mirroring render-policy's macOS-CADisplayLink-allowed control). The
  #          clean tree's VirtualDeviceGate already does exactly this, so add a SECOND gated file too.
  h="$(mktemp -d)"; e="$(mktemp -d)"; write_clean_tree "$h" "$e"
  {
    printf '#if CORTEX_HID_LIVE\n'
    printf 'enum AlsoLive { static func go() { %s(d, t, &b, n) } }\n' "$LIVE_SYMBOL"
    printf '#endif\n'
  } > "$h/AlsoLive.swift"
  assert_exit 0 "gated live symbol is ALLOWED (scoping control)" "$h" "$e"; rm -rf "$h" "$e"

  # 2c (B). Inject app-sandbox into the Mac entitlement file -> exit 1 (CF#1).
  h="$(mktemp -d)"; e="$(mktemp -d)"; write_clean_tree "$h" "$e"
  {
    printf '<plist><dict>\n'
    printf '  <key>com.apple.developer.hid.virtual.device</key><true/>\n'
    printf '  <key>com.apple.security.app-sandbox</key><true/>\n'
    printf '</dict></plist>\n'
  } > "$e/CortexMac/Cortex.entitlements"
  assert_exit 1 "inject app-sandbox (Mac)" "$h" "$e"; rm -rf "$h" "$e"

  if [[ "$fails" -eq 0 ]]; then
    echo "SELF-TEST OK: every required-token strip and every forbidden-token injection bites; the"
    echo "              gated live symbol is allowed; a clean tree passes."
    return 0
  else
    echo "SELF-TEST FAILED: at least one negative control did not bite (or the clean tree failed)." >&2
    return 1
  fi
}

# ── Entry point ──────────────────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

if scan; then
  echo "OK: HID surface policy clean — descriptor/struct/entitlement/gate commitments asserted, no forbidden tokens."
  exit 0
else
  echo "hid-surface-policy: FAILED — a HID surface commitment regressed (see ERROR lines above)." >&2
  exit 1
fi
