#!/usr/bin/env bash
# Source: project-defined per CONTEXT.md D-15.
# Purpose: pre-armed grep gate for the hot-path directories.
#
# In Phase 1, the policed directories contain only marker stubs and shared types.
# The gate is a NO-OP. The moment Phase 2 code lands in Packages/CortexIPC/Sources/**
# or hot-path code lands in Packages/CortexCore/Sources/**, this script bites.
#
# Forbidden tokens (THREAD-03 commitment from REQUIREMENTS.md):
#   - dispatch_async          (uses cooperative dispatch -- bad on audio-callback hot path)
#   - lazy var                (lazy init introduces a hidden first-call cost -- bad on hot path)
#   - pthread_mutex           (locks unbounded; sub-microsecond hot path forbids them -- use lock-free SPSC ring)
#   - import Foundation       (Obj-C runtime not allowed on hot path -- too much retain/release/ARC)
#   - import ObjectiveC       (explicit Obj-C import -- same reason)
#
# When Phase 3 work lands and the policy needs to extend to additional directories
# (e.g., Apps/CortexDaemon/), update DIRS below.
#
# Self-test (run with DIRS=/tmp/synthetic to test the script): see Plan 01-06 Task 1 Step 4.
#
# Exit codes:
#   0 -- no forbidden tokens found in the policed directories (Phase 1 expected)
#   1 -- at least one forbidden token found (Phase 2/3 will see this if rules are violated)

set -euo pipefail

# Allow override of DIRS for self-tests (e.g., DIRS=/tmp/synthetic ./hotpath-policy.sh).
#
# DEVIATION FROM PLAN 01-06 (Rule 1): the plan's spec listed two default dirs
# (Packages/CortexIPC/Sources, Packages/CortexCore/Sources). The CortexCore/Sources
# directory was narrowed out of the Phase 1 default because Plan 01-01's intentional
# shared-type files (Time.swift, AppGroup.swift, CortexCore.swift) use `import Foundation`
# legitimately (FileManager, mach_*) -- they are NOT hot-path code. Including them in the
# default scope would false-positive the gate every CI run.
#
# When Phase 5 adds a real hot-path subdirectory under CortexCore (e.g.,
# Packages/CortexCore/Sources/HotPath/), extend DIRS_ARRAY below to scope that subdir
# specifically. The spec's intent (gate pre-armed for hot-path code) is preserved.
if [[ -z "${DIRS:-}" ]]; then
  # CF#4 (Phase 2, D-05): police ONLY the Foundation-free hot-path target. CortexIPCSession
  # legitimately `import Foundation` (CryptoKit/Keychain/FlatBuffers) and would false-positive
  # this gate, failing Phase 2's own CI. The script's Phase-1 comment anticipated exactly this
  # ("extend DIRS_ARRAY to scope that subdir specifically"). When Phase 3 adds the pthread
  # USER_INTERACTIVE hot path (e.g. under Apps/CortexDaemon/ or a CortexCore HotPath/ subdir),
  # extend DIRS_ARRAY then.
  DIRS_ARRAY=("Packages/CortexIPC/Sources/CortexIPCTransport")
else
  # shellcheck disable=SC2206
  DIRS_ARRAY=($DIRS)
fi

FORBIDDEN=("dispatch_async" "lazy var" "pthread_mutex" "import Foundation" "import ObjectiveC")

EXIT=0

for DIR in "${DIRS_ARRAY[@]}"; do
  if [[ ! -d "$DIR" ]]; then
    echo "skipping (does not exist): $DIR"
    continue
  fi
  echo "scanning $DIR"
  for PATTERN in "${FORBIDDEN[@]}"; do
    # Use grep -F (fixed string), recursive, line-numbered, restrict to source files.
    if grep -r -n --include='*.swift' --include='*.c' --include='*.h' --include='*.m' --include='*.mm' \
        -F "$PATTERN" "$DIR" 2>/dev/null; then
      echo "ERROR: forbidden hot-path token '$PATTERN' found in $DIR" >&2
      EXIT=1
    fi
  done
done

if [[ $EXIT -eq 0 ]]; then
  echo "OK: hot-path policy clean across ${#DIRS_ARRAY[@]} dir(s)"
fi

exit $EXIT
