#!/usr/bin/env bash
# Source: project-defined per CONTEXT.md D-14 / RESEARCH.md Q5.
# Purpose: validate Apple PrivacyInfo.xcprivacy manifests against project requirements.
#
# Phase 1 invariants enforced:
#   1. File is a valid Apple plist (plutil -lint clean)
#   2. NSPrivacyAccessedAPITypes array exists
#   3. NSPrivacyAccessedAPICategorySystemBootTime is declared
#   4. CA92.1 reason code is present (covers mach_absolute_time per Apple required-reason API list)
#
# When Phase 2/3 lands required-reason API usage beyond mach_absolute_time, extend the
# REQUIRED_REASONS array below. When the daemon target gets its own manifest, add it
# to the CI invocation in .github/workflows/ci.yml — argv is variadic.
#
# Exit codes:
#   0 — all manifests pass
#   1 — at least one manifest failed validation
#   2 — usage error (no manifests passed)
#
# Source for CA92.1 / NSPrivacyAccessedAPICategorySystemBootTime mapping:
# https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <PrivacyInfo.xcprivacy> [more...]" >&2
  exit 2
fi

EXIT=0

for MANIFEST in "$@"; do
  if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: $MANIFEST does not exist" >&2
    EXIT=1
    continue
  fi

  echo "checking $MANIFEST"

  # 1. Plist syntactic validity.
  if ! plutil -lint "$MANIFEST" >/dev/null; then
    echo "ERROR: $MANIFEST failed plutil -lint" >&2
    EXIT=1
    continue
  fi

  # 2. NSPrivacyAccessedAPITypes array exists.
  if ! plutil -extract NSPrivacyAccessedAPITypes raw "$MANIFEST" >/dev/null 2>&1; then
    echo "ERROR: $MANIFEST missing NSPrivacyAccessedAPITypes array" >&2
    EXIT=1
    continue
  fi

  # 3. NSPrivacyAccessedAPICategorySystemBootTime category declared.
  XML=$(plutil -convert xml1 -o - "$MANIFEST")
  if ! grep -q "<string>NSPrivacyAccessedAPICategorySystemBootTime</string>" <<< "$XML"; then
    echo "ERROR: $MANIFEST missing NSPrivacyAccessedAPICategorySystemBootTime category" >&2
    EXIT=1
    continue
  fi

  # 4. CA92.1 reason code present.
  if ! grep -q "<string>CA92.1</string>" <<< "$XML"; then
    echo "ERROR: $MANIFEST missing CA92.1 reason code (required for mach_absolute_time)" >&2
    EXIT=1
    continue
  fi

  echo "OK: $MANIFEST"
done

exit $EXIT
