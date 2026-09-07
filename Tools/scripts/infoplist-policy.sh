#!/usr/bin/env bash
# Source: project-defined. Phase 10 orchestrator follow-up, 2026-09-07.
# Purpose: build-failing gate for the Info.plist keys that XcodeGen silently drops.
#
# ── THE DEFECT THIS GATE EXISTS TO CATCH ─────────────────────────────────────────────────────────
# XcodeGen REGENERATES each target's Info.plist from `project.yml`'s `info.properties` block. It does
# NOT merge into the existing file. So a key that lives only in the tracked Apps/*/Info.plist is
# dropped from the built app on the next `xcodegen generate`, and the tracked file is rewritten
# without it.
#
# That is exactly what happened to two keys. Both entered the tracked plists in 2cdb878 (2026-06-23,
# Plan 08-01) and `project.yml` never carried either one -- they were written to the generator's
# OUTPUT instead of its INPUT. Every `xcodegen generate` from that day until 2026-09-07 stripped
# them, and NOTHING caught it, because no gate asserted them and the app still built. Eleven weeks,
# eight phases, green the whole way.
#
#   NSAccessibilityUsageDescription  A REQUIRED purpose string. Cortex registers as a Switch Control
#                                    / Accessibility HID input provider; without this key the
#                                    assistive-input path ships with no user-facing justification.
#   CortexBCIHIDProtocolVersion      Pins the Apple BCI HID protocol revision the descriptor ports
#                                    (SYS-01/05, "may-2025").
#
# ── WHAT IS ASSERTED ─────────────────────────────────────────────────────────────────────────────
# For each of the two app targets, BOTH sides must carry BOTH keys:
#   (a) the tracked Apps/<target>/Info.plist    -- what is committed and reviewed
#   (b) project.yml's info.properties block     -- what actually reaches the built app
#
# (b) is the load-bearing half and is the reason this gate exists. Asserting only (a) would have
# passed for all eleven weeks of the defect: the tracked file HAD the keys, right up until the next
# generate rewrote it. A gate that only reads the artifact the generator overwrites is not a gate.
#
# Self-test: `--self-test` runs the gate over synthetic trees, one control per assertion, and proves
# each bites ALONE. Controls 3 and 4 are the ones that matter -- they strip the key from project.yml
# while leaving the tracked plist intact, which is the exact shape of the real defect.

set -uo pipefail

PROJECT_YML="${PROJECT_YML:-project.yml}"
MAC_PLIST="${MAC_PLIST:-Apps/CortexMac/Info.plist}"
IOS_PLIST="${IOS_PLIST:-Apps/CortexiOS/Info.plist}"

REQUIRED_KEYS=("NSAccessibilityUsageDescription" "CortexBCIHIDProtocolVersion")

# -- require_key_in_plist: the key must be declared in the tracked plist. ($1=path $2=key $3=label)
require_key_in_plist() {
  local path="$1" key="$2" label="$3"
  if [[ ! -f "$path" ]]; then
    echo "ERROR [plist] $label: file not found: $path" >&2
    return 1
  fi
  if grep -qF -- "<key>$key</key>" "$path" 2>/dev/null; then
    echo "  ok  [plist] $label"
    return 0
  fi
  echo "ERROR [plist] $label: <key>$key</key> absent from $path" >&2
  return 1
}

# -- require_key_in_project_yml: the key must be declared under the named target's info.properties.
# ($1=path $2=key $3=plist-path-that-identifies-the-block $4=label)
#
# The block is located by its `path:` line rather than by target name, because that line is what ties
# an info block to a specific Info.plist unambiguously. The scan then runs to the next `info:` or
# `entitlements:` at the same depth, so a key under the OTHER target cannot satisfy this one --
# control 5 proves that.
require_key_in_project_yml() {
  local path="$1" key="$2" plist="$3" label="$4"
  if [[ ! -f "$path" ]]; then
    echo "ERROR [yml] $label: file not found: $path" >&2
    return 1
  fi
  local block
  block="$(awk -v plist="$plist" '
    $0 ~ "path: " plist "$" { inblock = 1; next }
    inblock && /^      (path|properties):/ { next }
    inblock && /^    [a-zA-Z]/ { inblock = 0 }
    inblock { print }
  ' "$path")"
  if [[ -z "$block" ]]; then
    echo "ERROR [yml] $label: no info block in $path with path: $plist" >&2
    return 1
  fi
  if printf '%s\n' "$block" | grep -qE "^[[:space:]]*${key}:" 2>/dev/null; then
    echo "  ok  [yml] $label"
    return 0
  fi
  echo "ERROR [yml] $label: '$key:' absent from the info.properties block for $plist" >&2
  echo "       XcodeGen regenerates Info.plist from that block, so the key will be STRIPPED from" >&2
  echo "       the built app on the next \`xcodegen generate\` even though the tracked plist has it." >&2
  return 1
}

scan() {
  local rc=0 k
  for k in "${REQUIRED_KEYS[@]}"; do
    require_key_in_plist "$MAC_PLIST" "$k" "Mac plist declares $k"  || rc=1
    require_key_in_plist "$IOS_PLIST" "$k" "iOS plist declares $k"  || rc=1
  done
  for k in "${REQUIRED_KEYS[@]}"; do
    require_key_in_project_yml "$PROJECT_YML" "$k" "Apps/CortexMac/Info.plist" "project.yml carries $k for CortexMac" || rc=1
    require_key_in_project_yml "$PROJECT_YML" "$k" "Apps/CortexiOS/Info.plist" "project.yml carries $k for CortexiOS" || rc=1
  done
  if [[ "$rc" -eq 0 ]]; then
    echo "infoplist-policy: OK"
  else
    echo "infoplist-policy: FAILED -- a key XcodeGen would strip is missing (see ERROR lines)." >&2
  fi
  return "$rc"
}

self_test() {
  local rc=0 t

  assert_exit() {
    local want="$1" name="$2" yml="$3" mac="$4" ios="$5" got
    PROJECT_YML="$yml" MAC_PLIST="$mac" IOS_PLIST="$ios" scan >/dev/null 2>&1
    got=$?
    if [[ "$got" -eq "$want" ]]; then
      echo "  PASS [$name] exit=$got (expected $want)"
    else
      echo "  FAIL [$name] exit=$got (expected $want)" >&2
      rc=1
    fi
  }

  write_clean_tree() {
    local d="$1" k
    mkdir -p "$d/Apps/CortexMac" "$d/Apps/CortexiOS"
    for p in "$d/Apps/CortexMac/Info.plist" "$d/Apps/CortexiOS/Info.plist"; do
      {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<plist version="1.0"><dict>'
        echo '  <key>CFBundleDisplayName</key><string>Cortex</string>'
        for k in "${REQUIRED_KEYS[@]}"; do echo "  <key>$k</key><string>x</string>"; done
        echo '</dict></plist>'
      } > "$p"
    done
    {
      echo 'targets:'
      echo '  CortexiOS:'
      echo '    info:'
      echo '      path: Apps/CortexiOS/Info.plist'
      echo '      properties:'
      echo '        CFBundleDisplayName: Cortex'
      for k in "${REQUIRED_KEYS[@]}"; do echo "        $k: x"; done
      echo '    entitlements:'
      echo '      path: Apps/CortexiOS/Cortex.entitlements'
      echo '  CortexMac:'
      echo '    info:'
      echo '      path: Apps/CortexMac/Info.plist'
      echo '      properties:'
      echo '        CFBundleDisplayName: Cortex'
      for k in "${REQUIRED_KEYS[@]}"; do echo "        $k: x"; done
      echo '    entitlements:'
      echo '      path: Apps/CortexMac/Cortex.entitlements'
    } > "$d/project.yml"
  }

  t="$(mktemp -d)"; write_clean_tree "$t"
  assert_exit 0 "clean tree" "$t/project.yml" "$t/Apps/CortexMac/Info.plist" "$t/Apps/CortexiOS/Info.plist"
  rm -rf "$t"

  # 1-2: the tracked plist loses a key.
  t="$(mktemp -d)"; write_clean_tree "$t"
  grep -v 'NSAccessibilityUsageDescription' "$t/Apps/CortexMac/Info.plist" > "$t/x" && mv "$t/x" "$t/Apps/CortexMac/Info.plist"
  assert_exit 1 "Mac plist loses NSAccessibilityUsageDescription" "$t/project.yml" "$t/Apps/CortexMac/Info.plist" "$t/Apps/CortexiOS/Info.plist"
  rm -rf "$t"

  t="$(mktemp -d)"; write_clean_tree "$t"
  grep -v 'CortexBCIHIDProtocolVersion' "$t/Apps/CortexiOS/Info.plist" > "$t/x" && mv "$t/x" "$t/Apps/CortexiOS/Info.plist"
  assert_exit 1 "iOS plist loses CortexBCIHIDProtocolVersion" "$t/project.yml" "$t/Apps/CortexMac/Info.plist" "$t/Apps/CortexiOS/Info.plist"
  rm -rf "$t"

  # 3-4: THE REAL DEFECT. project.yml loses the key while the tracked plist still has it. A gate that
  # read only the plist would pass here, and the next `xcodegen generate` would strip the built app.
  t="$(mktemp -d)"; write_clean_tree "$t"
  awk '!/^        NSAccessibilityUsageDescription:/' "$t/project.yml" > "$t/x" && mv "$t/x" "$t/project.yml"
  assert_exit 1 "project.yml loses NSAccessibilityUsageDescription, plists intact" "$t/project.yml" "$t/Apps/CortexMac/Info.plist" "$t/Apps/CortexiOS/Info.plist"
  rm -rf "$t"

  t="$(mktemp -d)"; write_clean_tree "$t"
  awk '!/^        CortexBCIHIDProtocolVersion:/' "$t/project.yml" > "$t/x" && mv "$t/x" "$t/project.yml"
  assert_exit 1 "project.yml loses CortexBCIHIDProtocolVersion, plists intact" "$t/project.yml" "$t/Apps/CortexMac/Info.plist" "$t/Apps/CortexiOS/Info.plist"
  rm -rf "$t"

  # 5: one target's block keeps the key and the other loses it. Proves the block scan is per-target
  # and a key under CortexiOS cannot satisfy the CortexMac assertion.
  t="$(mktemp -d)"; write_clean_tree "$t"
  awk 'BEGIN{inmac=0}
       /^  CortexMac:/{inmac=1}
       inmac && /^        NSAccessibilityUsageDescription:/{next}
       {print}' "$t/project.yml" > "$t/x" && mv "$t/x" "$t/project.yml"
  assert_exit 1 "only CortexMac loses the key in project.yml" "$t/project.yml" "$t/Apps/CortexMac/Info.plist" "$t/Apps/CortexiOS/Info.plist"
  rm -rf "$t"

  # 6: the info block is missing entirely.
  t="$(mktemp -d)"; write_clean_tree "$t"
  awk '!/^      path: Apps\/CortexMac\/Info.plist$/' "$t/project.yml" > "$t/x" && mv "$t/x" "$t/project.yml"
  assert_exit 1 "CortexMac info block has no path: line" "$t/project.yml" "$t/Apps/CortexMac/Info.plist" "$t/Apps/CortexiOS/Info.plist"
  rm -rf "$t"

  if [[ "$rc" -eq 0 ]]; then
    echo "infoplist-policy --self-test: OK -- every control bites"
  else
    echo "infoplist-policy --self-test: FAILED" >&2
  fi
  return "$rc"
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
else
  scan
fi
