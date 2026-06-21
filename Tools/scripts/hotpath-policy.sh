#!/usr/bin/env bash
# Source: project-defined per CONTEXT.md D-15.
# Purpose: pre-armed grep gate for the hot-path directories (SC#2).
#
# In Phase 1, the policed directories contain only marker stubs and shared types.
# The gate is a NO-OP. The moment Phase 2 code lands in Packages/CortexIPC/Sources/**
# or hot-path code lands in Packages/CortexCore/Sources/**, this script bites.
#
# Forbidden Swift/C tokens (THREAD-03 commitment from REQUIREMENTS.md):
#   - dispatch_async          (uses cooperative dispatch -- bad on audio-callback hot path)
#   - lazy var                (lazy init introduces a hidden first-call cost -- bad on hot path)
#   - pthread_mutex           (locks unbounded; sub-microsecond hot path forbids them -- use lock-free SPSC ring)
#   - import Foundation       (Obj-C runtime not allowed on hot path -- too much retain/release/ARC)
#   - import ObjectiveC       (explicit Obj-C import -- same reason)
#
# Forbidden RUST tokens (Phase 3, D-R7) -- policed ONLY on the in-process ring hot-path source
# (Packages/CortexRing/rust/src/{spsc,ffi}.rs), NOT the whole crate (loom/test/bench files
# legitimately use std::thread, panic!, etc.):
#   - Mutex                   (a lock is unbounded on the sub-microsecond ring path -- the SPSC ring is the channel)
#   - RwLock                  (same: no reader/writer lock on the hot path)
#   - .lock(                  (a lock-acquire CALL site -- unbounded blocking)
#   - println!(               (stdout I/O blocks; forbidden on the hot path -- macro-CALL form, see note)
#   - panic!(                 (a panic unwinding across the extern "C" frame into Swift/C is UB -- macro-CALL form)
#
# NOTE on the Rust token forms (Phase 3, Plan 03-03 -- Rule 1 robustness): the Rust tokens are
# matched in their CALL form (`.lock(`, `println!(`, `panic!(`) -- mirroring the `.lock(` form the
# plan itself lists -- so the gate bites on a real macro INVOCATION, not on the bare word `panic!`
# appearing in a doc-comment. The committed `ffi.rs` (Spike A) documents "panic! unwinding across an
# extern \"C\" frame is UB" in prose and wraps every body in `catch_unwind`; policing the bare word
# would false-positive that clean, intentional documentation and fail CI. The CALL form is also the
# more accurate invariant ("no panic/println CALL on the hot path"). The negative-control self-test
# injects the CALL forms (e.g. `println!("x")`, `panic!("x")`), so the gate is still proven to bite.
#
# When Phase 3 work lands and the policy needs to extend to additional directories
# (e.g., Apps/CortexDaemon/), update DIRS below.
#
# Self-test:
#   ./hotpath-policy.sh --self-test         # injects EVERY forbidden token (Swift/C + Rust) into temp
#                                           # .swift/.c/.rs files and asserts the gate exits 1 on each,
#                                           # then asserts a clean tree exits 0. (Extends the Plan 01-06
#                                           # DIRS=/tmp/synthetic self-test to all three languages.)
#   DIRS=/tmp/synthetic ./hotpath-policy.sh # scan an arbitrary dir for the Swift/C token set
#   RUST_FILES="a.rs b.rs" ./hotpath-policy.sh  # scan arbitrary files for the Rust token set
#
# Exit codes:
#   0 -- no forbidden tokens found in the policed dirs/files (Phase 1 expected)
#   1 -- at least one forbidden token found (Phase 2/3 will see this if rules are violated)

set -euo pipefail

# ---------------------------------------------------------------------------
# Swift/C hot-path directory token set.
#
# DEVIATION FROM PLAN 01-06 (Rule 1): the plan's spec listed two default dirs
# (Packages/CortexIPC/Sources, Packages/CortexCore/Sources). The CortexCore/Sources
# directory was narrowed out of the Phase 1 default because Plan 01-01's intentional
# shared-type files (Time.swift, AppGroup.swift, CortexCore.swift) use `import Foundation`
# legitimately (FileManager, mach_*) -- they are NOT hot-path code. Including them in the
# default scope would false-positive the gate every CI run.
#
# CF#4 (Phase 2, D-05): police ONLY the Foundation-free hot-path target. CortexIPCSession
# legitimately `import Foundation` (CryptoKit/Keychain/FlatBuffers) and would false-positive
# this gate. Phase 3 (Plan 03-03, D-R7) adds the pthread USER_INTERACTIVE acquisition hot path
# Packages/CortexRing/Sources/CortexRingHotPath -- another Foundation-free target -- to the
# Swift/C scan, and adds the Rust ring-source scan below.
FORBIDDEN=("dispatch_async" "lazy var" "pthread_mutex" "import Foundation" "import ObjectiveC")

if [[ -z "${DIRS:-}" ]]; then
  DIRS_ARRAY=(
    "Packages/CortexIPC/Sources/CortexIPCTransport"
    "Packages/CortexRing/Sources/CortexRingHotPath"
  )
else
  # shellcheck disable=SC2206
  DIRS_ARRAY=($DIRS)
fi

# ---------------------------------------------------------------------------
# Rust ring hot-path file token set (Phase 3, D-R7). Scoped to the SPECIFIC ring sources, not
# the whole crate -- src/loom.rs, tests, and benches legitimately use std::thread / panic! / etc.
# A missing file is skipped (spsc.rs lands in Plan 02; the gate must stay green before/after).
RUST_FORBIDDEN=("Mutex" "RwLock" ".lock(" "println!(" "panic!(")

if [[ -z "${RUST_FILES:-}" ]]; then
  RUST_HOTPATH_FILES=(
    "Packages/CortexRing/rust/src/spsc.rs"
    "Packages/CortexRing/rust/src/ffi.rs"
  )
else
  # shellcheck disable=SC2206
  RUST_HOTPATH_FILES=($RUST_FILES)
fi

# ---------------------------------------------------------------------------
# scan_tree: run the gate over DIRS_ARRAY (Swift/C tokens) AND RUST_HOTPATH_FILES (Rust tokens).
# Echoes findings; returns 0 clean / 1 if any forbidden token is found. Used both for the real
# tree and (with DIRS/RUST_FILES overridden) by the self-test.
scan_tree() {
  local exit_code=0
  local dir pattern file

  # --- Swift/C directory scan ---
  for dir in "${DIRS_ARRAY[@]}"; do
    if [[ ! -d "$dir" ]]; then
      echo "skipping (does not exist): $dir"
      continue
    fi
    echo "scanning (swift/c) $dir"
    for pattern in "${FORBIDDEN[@]}"; do
      # grep -F (fixed string), recursive, line-numbered. `--include='*.rs'` is present so a stray
      # .rs dropped into a Swift hot-path dir is also scanned for the Swift/C set.
      if grep -r -n \
          --include='*.swift' --include='*.c' --include='*.h' --include='*.m' --include='*.mm' --include='*.rs' \
          -F "$pattern" "$dir" 2>/dev/null; then
        echo "ERROR: forbidden hot-path token '$pattern' found in $dir" >&2
        exit_code=1
      fi
    done
    # Any .rs living INSIDE a policed hot-path dir is ALSO scanned for the Rust token set (D-R7):
    # the hot path forbids locks / println!/panic! CALLs regardless of which dir the .rs sits in.
    # (The dedicated RUST_HOTPATH_FILES scan below additionally polices the ring sources in rust/src/,
    # which are NOT under a Swift DIRS dir.) The Swift/C and Rust token sets stay distinct.
    for pattern in "${RUST_FORBIDDEN[@]}"; do
      if grep -r -n --include='*.rs' -F "$pattern" "$dir" 2>/dev/null; then
        echo "ERROR: forbidden rust hot-path token '$pattern' found in $dir" >&2
        exit_code=1
      fi
    done
  done

  # --- Rust ring hot-path file scan ---
  for file in "${RUST_HOTPATH_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "skipping (does not exist): $file"
      continue
    fi
    echo "scanning (rust) $file"
    for pattern in "${RUST_FORBIDDEN[@]}"; do
      if grep -n -F "$pattern" "$file" 2>/dev/null; then
        echo "ERROR: forbidden rust hot-path token '$pattern' found in $file" >&2
        exit_code=1
      fi
    done
  done

  return $exit_code
}

# ---------------------------------------------------------------------------
# self_test: prove the gate BITES on every forbidden token across .swift / .c / .rs, then prove a
# clean tree passes. The negative control (the established Cortex discipline -- Phase-1 privacy-
# manifest negative control, loom's own #[should_panic]). Extends the Plan 01-06 DIRS=/tmp/synthetic
# self-test to all three languages (SC#2 row in 03-RESEARCH.md §5).
self_test() {
  local tmp rc fails=0

  # Helper: run THIS script with overridden scope and assert the expected exit code.
  # $1 = expected exit (0 clean / 1 bite); $2 = label; remaining = env assignments handled by caller.
  assert_exit() {
    local want="$1" label="$2"
    shift 2
    set +e
    ( "$@" ) >/dev/null 2>&1
    rc=$?
    set -e
    if [[ "$rc" -eq "$want" ]]; then
      echo "  PASS [$label] exit=$rc (expected $want)"
    else
      echo "  FAIL [$label] exit=$rc (expected $want)" >&2
      fails=1
    fi
  }

  echo "== hot-path-policy self-test =="

  # 1. Each Swift/C token in a temp .swift bites (exit 1).
  echo "-- Swift/C token set (.swift) --"
  for tok in "${FORBIDDEN[@]}"; do
    tmp="$(mktemp -d)"
    # Write the token verbatim into a .swift file under the scanned dir.
    printf '// synthetic hot-path violation\n%s\n' "$tok" > "$tmp/bad.swift"
    assert_exit 1 "swift:'$tok'" env DIRS="$tmp" RUST_FILES=" " bash "$SELF"
    rm -rf "$tmp"
  done

  # 2. A representative Swift/C token in a temp .c bites (exit 1) -- proves .c is scanned too.
  echo "-- Swift/C token set (.c) --"
  tmp="$(mktemp -d)"
  printf '/* synthetic */\nvoid f(void){ dispatch_async(0,0); }\n' > "$tmp/bad.c"
  assert_exit 1 "c:'dispatch_async'" env DIRS="$tmp" RUST_FILES=" " bash "$SELF"
  rm -rf "$tmp"

  # 3. Each Rust token (CALL form) in a temp .rs bites (exit 1).
  echo "-- Rust token set (.rs) --"
  declare -a rust_payloads=(
    'use std::sync::Mutex;'                       # Mutex
    'use std::sync::RwLock;'                       # RwLock
    'fn f(m:&M){ let _g = m.lock().unwrap(); }'    # .lock(
    'fn f(){ println!("no"); }'                    # println!(
    'fn f(){ panic!("boom"); }'                    # panic!(
  )
  for payload in "${rust_payloads[@]}"; do
    tmp="$(mktemp -d)"
    printf '// synthetic ring violation\n%s\n' "$payload" > "$tmp/bad.rs"
    assert_exit 1 "rust:'${payload:0:24}...'" env DIRS=" " RUST_FILES="$tmp/bad.rs" bash "$SELF"
    rm -rf "$tmp"
  done

  # 4. A clean .swift dir AND a clean .rs file pass (exit 0).
  echo "-- clean tree --"
  tmp="$(mktemp -d)"
  printf 'import Darwin\nlet x = 1\n' > "$tmp/ok.swift"
  printf 'pub fn add(a:u32,b:u32)->u32{ a.wrapping_add(b) }\n' > "$tmp/ok.rs"
  assert_exit 0 "clean swift+rust" env DIRS="$tmp" RUST_FILES="$tmp/ok.rs" bash "$SELF"
  rm -rf "$tmp"

  if [[ "$fails" -eq 0 ]]; then
    echo "SELF-TEST OK: the gate bites on every forbidden token (.swift/.c/.rs) and passes a clean tree."
    return 0
  else
    echo "SELF-TEST FAILED: at least one assertion did not hold." >&2
    return 1
  fi
}

# Absolute path to THIS script (so the self-test can re-invoke it with overridden scope).
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------------------
# Entry point.
if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

# A RUST_FILES value of only whitespace means "scan no Rust files" (used by the self-test when
# isolating the Swift/C scan). Normalize it to an empty array so the loop is a clean no-op.
if [[ -n "${RUST_FILES:-}" && -z "${RUST_FILES// /}" ]]; then
  RUST_HOTPATH_FILES=()
fi
# Likewise a whitespace-only DIRS means "scan no dirs" (self-test isolating the Rust scan).
if [[ -n "${DIRS:-}" && -z "${DIRS// /}" ]]; then
  DIRS_ARRAY=()
fi

if scan_tree; then
  echo "OK: hot-path policy clean across ${#DIRS_ARRAY[@]} dir(s) + ${#RUST_HOTPATH_FILES[@]} rust file(s)"
  exit 0
else
  exit 1
fi
