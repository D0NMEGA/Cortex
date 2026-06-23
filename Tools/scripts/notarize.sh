#!/usr/bin/env bash
# Tools/scripts/notarize.sh -- DIST-01 notarization pipeline.
# Source: project-defined per CONTEXT.md D-01 (the wire-and-gate keystone). The flags below are
# AUTHORITATIVE from the local Xcode 26.3.0 toolchain (`xcrun notarytool submit --help`,
# /Applications/Xcode-26.3.0.app/...), cross-checked against 08-RESEARCH.md §3. The deprecated
# legacy uploader is fully replaced by `notarytool` -- this script contains ZERO references to that
# retired tool (notarize-policy.sh forbids its name; the day-one App Store deadline already
# requires notarytool).
#
# Pipeline: zip the built .app -> `xcrun notarytool submit` (ASC .p8 JWT auth, --wait) -> on
# Accepted, `xcrun stapler staple` the ticket onto the .app -> `xcrun stapler validate` ->
# `spctl --assess` Gatekeeper check. The submit blocks on Apple with --wait + --timeout 30m and
# emits parseable JSON (-f json) for CI log capture.
#
# SECRET DISCIPLINE (load-bearing): the ASC API key (.p8) + key-id + issuer are read from ENV only
#   ASC_KEY_PATH  -- filesystem path to AuthKey_<KEYID>.p8 (gitignored; *.p8 is in .gitignore)
#   ASC_KEY_ID    -- the 10+ alphanumeric Key ID
#   ASC_ISSUER_ID -- the Issuer UUID (Team keys; omit for an Individual key)
# Nothing is hardcoded. The key file itself is NEVER committed.
#
# WIRE-AND-GATE (CONTEXT D-01): this is the REAL pipeline NOW. The LIVE run is the Plan 07
# never-auto-approve HUMAN-UAT gate -- it needs paid Apple Developer Program enrollment + a real
# ASC `.p8` key. With the ASC_* vars unset (clean clone / CI), the script EXITS NON-ZERO with a
# clear message rather than half-running (real-but-gated). The day enrollment + the .p8 land,
# `fastlane beta` invokes this for real with no further code change.
#
# Usage: APP_PATH=/path/to/Cortex.app ./Tools/scripts/notarize.sh
#        (the mac :beta lane in fastlane/Fastfile sets APP_PATH from build_app's output)

set -euo pipefail

APP_PATH="${APP_PATH:-${1:-}}"

# --- ENV gate: live notarization is the Plan 07 HUMAN-UAT gate ----------------------------------
missing=()
[[ -n "${ASC_KEY_PATH:-}" ]]  || missing+=("ASC_KEY_PATH")
[[ -n "${ASC_KEY_ID:-}" ]]    || missing+=("ASC_KEY_ID")
[[ -n "${ASC_ISSUER_ID:-}" ]] || missing+=("ASC_ISSUER_ID")
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "notarize.sh: live notarization is the Plan 07 HUMAN-UAT gate (needs paid enrollment + ASC .p8)." >&2
  echo "notarize.sh: set ${missing[*]} (ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID) to run for real (CONTEXT D-01)." >&2
  exit 1
fi

if [[ -z "$APP_PATH" ]]; then
  echo "notarize.sh: no app to notarize -- set APP_PATH=/path/to/Cortex.app (or pass it as \$1)." >&2
  exit 1
fi
if [[ ! -e "$APP_PATH" ]]; then
  echo "notarize.sh: APP_PATH does not exist: $APP_PATH" >&2
  exit 1
fi

ZIP_PATH="${APP_PATH%.app}.zip"

echo "notarize.sh: zipping $APP_PATH -> $ZIP_PATH"
# ditto preserves the bundle structure + symlinks for notarization (the Apple-recommended zipper).
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "notarize.sh: submitting to Apple notary service (notarytool submit --wait)"
# notarytool submit with the ASC .p8 JWT (inline-key auth, CI-friendly -- no Keychain dependency).
# --wait blocks until Accepted/Invalid; --timeout caps the wait; -f json emits parseable output.
xcrun notarytool submit "$ZIP_PATH" \
  --key      "$ASC_KEY_PATH" \
  --key-id   "$ASC_KEY_ID" \
  --issuer   "$ASC_ISSUER_ID" \
  --wait \
  --timeout 30m \
  -f json

echo "notarize.sh: stapling the notarization ticket onto $APP_PATH"
xcrun stapler staple "$APP_PATH"

echo "notarize.sh: validating the stapled ticket"
xcrun stapler validate "$APP_PATH"

echo "notarize.sh: Gatekeeper assessment (spctl)"
spctl --assess -vv --type exec "$APP_PATH"

echo "notarize.sh: OK -- $APP_PATH notarized + stapled + Gatekeeper-assessed."
