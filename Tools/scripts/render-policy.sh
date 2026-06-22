#!/usr/bin/env bash
# Source: project-defined per CONTEXT.md D-10 (tier 1) and RESEARCH.md Decision 6/7 + the
# Hardware-strategy table (RENDER-01/04/06/07 primary, RENDER-03/08/09 grep).
# Purpose: build-failing structural grep gate for the renderer's LOAD-BEARING commitments (SC#1
# structural). Mirrors the Phase-1 validate-privacy-manifest.sh / Phase-3 hotpath-policy.sh
# precedent — a static proxy that FAILS CI the moment a future commit silently regresses a
# latency/120Hz/zero-copy invariant, WITH a negative-control --self-test that proves the gate bites.
#
# The renderer commitments this asserts already exist in Packages/CortexRender after Plans 01/03
# (and project.yml after Plan 04). This gate is the regression tripwire, not the implementation.
#
# ── REQUIRED-PRESENT (build-FAILS if a token is ABSENT) ───────────────────────────────────────
# Each is scoped to the SPECIFIC source file that owns it (the hotpath-policy.sh discipline:
# scope to the exact source, never the whole tree, to avoid false-positives). Tolerant greps
# (optional whitespace) so a benign reformat does not trip the gate.
#   1. DispatchSemaphore value: 1            (FrameSynchronizer.swift)  — ONE frame in flight, lowest
#                                              latency (RENDER-07/PERF-04). value:3 silently adds
#                                              ~8.3ms glass-to-glass.
#   2. maximumDrawableCount = 2              (MetalLayerConfig.swift)   — pairs with value:1 for one
#                                              in-flight frame (RENDER-07). 3 adds a 120Hz interval.
#   3. framebufferOnly = false              (MetalLayerConfig.swift)   — opens the compute
#                                              access::write scope to the drawable (RENDER-04).
#   4. zero-copy CPU->GPU upload            (renderer sources)         — storageModeShared OR a
#                                              setBytes call; the small-constant uniforms path is
#                                              setBytes (no staging buffer) (RENDER-06).
#   5. CAMetalDisplayLink                   (iOSDisplayLinkAdapter)    — the sanctioned iOS Metal
#                                              path (RENDER-01).
#   6. displayLink(target:                  (MacDisplayLinkAdapter)    — NSView.displayLink, the
#                                              sanctioned macOS Metal path (RENDER-08).
#   7. kernel void webgrid                  (Webgrid.metal)            — the compute-shader grid path
#                                              (RENDER-04).
#   8. CADisableMinimumFrameDurationOnPhone == true  (project.yml)     — unlocks ProMotion 120Hz in
#                                              the built iOS Info.plist (RENDER-03).
#   9. MTL_HUD_ENABLED                      (project.yml)              — the live frame-pacing HUD
#                                              scheme env (RENDER-09).
#
# ── FORBIDDEN (build-FAILS if a token is PRESENT) ─────────────────────────────────────────────
#   A. CADisplayLink in iOSDisplayLinkAdapter.swift ONLY  — RENDER-01: ZERO legacy display-link on
#      the iOS Metal path. SCOPED to the iOS adapter file ONLY — the macOS adapter LEGITIMATELY uses
#      CADisplayLink via NSView.displayLink (RENDER-08), so a tree-wide grep would false-positive the
#      sanctioned macOS path. (Same scoping rationale as hotpath-policy.sh's per-source Rust scan.)
#   B. storageModeManaged anywhere in the renderer sources  — RENDER-06 zero-copy: no managed/staging
#      buffer on a unified-memory Apple-Silicon target.
#   C. timed-present (present(at: / presentAtTime / present(afterMinimumDuration) in the adapters —
#      RESEARCH #5: the timed/timestamp-targeting present variants ASSERT under a Metal display link;
#      only the unparameterized cb.present(drawable) is legal.
#
# NOTE on token forms (literal-grep discipline, the Cortex Phase 1-5 reword precedent): the renderer
# comments describe forbidden APIs by INTENT (never the bare literal), so these greps bite on real
# CODE, not on documentation. The iOS adapter's comments say "the legacy per-screen display-link
# timer class" instead of writing CADisplayLink; the adapters say "the timed/timestamp-targeting
# present variants" instead of present(at:). The --self-test injects the literal CODE forms (a real
# CADisplayLink reference, a real present(at:...) call, a real storageModeManaged), so the gate is
# still proven to bite on a genuine regression.
#
# Self-test:
#   ./render-policy.sh --self-test   # (i) strip each required token -> assert exit 1; (ii) inject
#                                    # each forbidden token (CADisplayLink in the iOS stand-in,
#                                    # storageModeManaged, present(at:)) -> assert exit 1; (iii) a
#                                    # clean synthetic tree -> assert exit 0. Proves every check bites.
#   RENDER_DIR=/tmp/synthetic PROJECT_FILE=/tmp/p.yml ./render-policy.sh   # repoint at a temp tree
#
# Exit codes:
#   0 -- all required tokens present, no forbidden tokens (real tree after Plans 01/03/04)
#   1 -- a required token is missing OR a forbidden token appears (a regression)

set -euo pipefail

# ── Scope (overridable for the self-test, mirroring hotpath-policy.sh's DIRS= idiom) ───────────
# RENDER_DIR  — the renderer source tree (default: the real CortexRender sources).
# PROJECT_FILE — the XcodeGen spec carrying the plist key + scheme HUD env (default: project.yml).
RENDER_DIR="${RENDER_DIR:-Packages/CortexRender/Sources/CortexRender}"
PROJECT_FILE="${PROJECT_FILE:-project.yml}"

# Per-file relative names (resolved under RENDER_DIR). Scoping each assertion to its owning file is
# the whole point — a token in the wrong file is as much a regression as a missing one.
FRAME_SYNC="FrameSynchronizer.swift"
LAYER_CONFIG="MetalLayerConfig.swift"
IOS_ADAPTER="iOSDisplayLinkAdapter.swift"
MAC_ADAPTER="MacDisplayLinkAdapter.swift"
WEBGRID_METAL="Webgrid.metal"

# ── require_in_file: assert a regex is PRESENT in a specific file. Missing file or missing token
# is a FAIL (returns 1). Echoes the outcome. ($1=file under RENDER_DIR, $2=ERE, $3=label) ──────
require_in_file() {
  local rel="$1" pattern="$2" label="$3" path="$RENDER_DIR/$1"
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

# ── require_in_tree: assert a regex is PRESENT somewhere in the renderer tree (used for the
# zero-copy "storageModeShared OR setBytes" any-of check). ($1=ERE, $2=label) ──────────────────
require_in_tree() {
  local pattern="$1" label="$2"
  if [[ ! -d "$RENDER_DIR" ]]; then
    echo "ERROR [required-missing] $label: renderer dir not found: $RENDER_DIR" >&2
    return 1
  fi
  if grep -rnE "$pattern" "$RENDER_DIR" >/dev/null 2>&1; then
    echo "  ok  [required] $label  (tree)"
    return 0
  fi
  echo "ERROR [required-missing] $label: '$pattern' not found anywhere in $RENDER_DIR" >&2
  return 1
}

# ── require_in_project: assert a regex is PRESENT in the XcodeGen spec. ($1=ERE, $2=label) ─────
require_in_project() {
  local pattern="$1" label="$2"
  if [[ ! -f "$PROJECT_FILE" ]]; then
    echo "ERROR [required-missing] $label: project file not found: $PROJECT_FILE" >&2
    return 1
  fi
  if grep -nE "$pattern" "$PROJECT_FILE" >/dev/null 2>&1; then
    echo "  ok  [required] $label  ($PROJECT_FILE)"
    return 0
  fi
  echo "ERROR [required-missing] $label: '$pattern' not found in $PROJECT_FILE" >&2
  return 1
}

# ── forbid_in_file: assert a regex is ABSENT from a specific file (scoped forbidden check). A
# match is a FAIL (returns 1). ($1=file under RENDER_DIR, $2=ERE, $3=label) ─────────────────────
forbid_in_file() {
  local rel="$1" pattern="$2" label="$3" path="$RENDER_DIR/$1"
  if [[ ! -f "$path" ]]; then
    # A missing file cannot contain a forbidden token — vacuously clean (matches hotpath-policy's
    # "missing file is skipped" behavior so the gate stays green before/after a file lands).
    echo "  ok  [forbidden-absent] $label  ($rel missing -> vacuously clean)"
    return 0
  fi
  if grep -nE "$pattern" "$path" >/dev/null 2>&1; then
    echo "ERROR [forbidden-present] $label: '$pattern' found in $rel" >&2
    grep -nE "$pattern" "$path" >&2 || true
    return 1
  fi
  echo "  ok  [forbidden-absent] $label  ($rel)"
  return 0
}

# ── forbid_in_tree: assert a regex is ABSENT anywhere in the renderer tree. ($1=ERE, $2=label) ─
forbid_in_tree() {
  local pattern="$1" label="$2"
  if [[ ! -d "$RENDER_DIR" ]]; then
    echo "  ok  [forbidden-absent] $label  ($RENDER_DIR missing -> vacuously clean)"
    return 0
  fi
  if grep -rnE "$pattern" "$RENDER_DIR" >/dev/null 2>&1; then
    echo "ERROR [forbidden-present] $label: '$pattern' found in $RENDER_DIR" >&2
    grep -rnE "$pattern" "$RENDER_DIR" >&2 || true
    return 1
  fi
  echo "  ok  [forbidden-absent] $label  (tree)"
  return 0
}

# ── scan: run every assertion. Returns 0 only if ALL pass. Used for the real tree and (with
# RENDER_DIR/PROJECT_FILE overridden) by the self-test. ─────────────────────────────────────────
scan() {
  local rc=0

  echo "scanning renderer sources: $RENDER_DIR"
  echo "scanning project spec:     $PROJECT_FILE"

  # REQUIRED-PRESENT (1-9)
  require_in_file "$FRAME_SYNC"  'DispatchSemaphore\(value:[[:space:]]*1\)'           "value:1 one-in-flight gate (RENDER-07)" || rc=1
  require_in_file "$LAYER_CONFIG" 'maximumDrawableCount[[:space:]]*=[[:space:]]*2'    "maximumDrawableCount=2 (RENDER-07)"     || rc=1
  require_in_file "$LAYER_CONFIG" 'framebufferOnly[[:space:]]*=[[:space:]]*false'     "framebufferOnly=false (RENDER-04)"      || rc=1
  require_in_tree '(storageModeShared|setBytes)'                                      "zero-copy upload: storageModeShared|setBytes (RENDER-06)" || rc=1
  require_in_file "$IOS_ADAPTER"  'CAMetalDisplayLink'                                "CAMetalDisplayLink iOS path (RENDER-01)" || rc=1
  require_in_file "$MAC_ADAPTER"  'displayLink\(target:'                              "NSView.displayLink(target: macOS path (RENDER-08)" || rc=1
  require_in_file "$WEBGRID_METAL" 'kernel void webgrid'                              "compute kernel webgrid (RENDER-04)"     || rc=1
  require_in_project 'CADisableMinimumFrameDurationOnPhone:[[:space:]]*true'          "CADisableMinimumFrameDurationOnPhone=true (RENDER-03)" || rc=1
  require_in_project 'MTL_HUD_ENABLED'                                                "MTL_HUD_ENABLED scheme env (RENDER-09)"  || rc=1

  # FORBIDDEN (A-C)
  #   A. legacy display-link on the iOS Metal path — scoped to the iOS adapter ONLY. The macOS
  #      adapter's NSView.displayLink-vended CADisplayLink (RENDER-08) is explicitly allowed.
  forbid_in_file "$IOS_ADAPTER" 'CADisplayLink'                                       "no legacy display-link on the iOS Metal path (RENDER-01)" || rc=1
  #   B. no managed/staging buffer anywhere in the renderer (RENDER-06 zero-copy).
  forbid_in_tree 'storageModeManaged'                                                 "no managed/staging buffer (RENDER-06)"  || rc=1
  #   C. no timed/timestamp-targeting present in the adapters (asserts under a Metal display link).
  forbid_in_file "$IOS_ADAPTER" 'present\(at:|presentAtTime|present\(afterMinimumDuration' "no timed-present on iOS adapter (RESEARCH #5)" || rc=1
  forbid_in_file "$MAC_ADAPTER" 'present\(at:|presentAtTime|present\(afterMinimumDuration' "no timed-present on macOS adapter (RESEARCH #5)" || rc=1

  return $rc
}

# Absolute path to THIS script (so the self-test can re-invoke it with overridden scope, mirroring
# hotpath-policy.sh's SELF pattern).
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── self_test: the negative control. Prove the gate BITES on (i) each missing required token and
# (ii) each injected forbidden token, then prove a clean synthetic tree PASSES. The established
# Cortex discipline (Phase-1 privacy-manifest negative control, Phase-3 hotpath-policy self-test). ─
self_test() {
  local fails=0 rc

  # Run THIS script against an overridden RENDER_DIR + PROJECT_FILE; assert the exit code.
  # $1 = expected exit (0 clean / 1 bite); $2 = label; $3 = RENDER_DIR; $4 = PROJECT_FILE.
  assert_exit() {
    local want="$1" label="$2" rdir="$3" pfile="$4"
    set +e
    ( env RENDER_DIR="$rdir" PROJECT_FILE="$pfile" bash "$SELF" ) >/dev/null 2>&1
    rc=$?
    set -e
    if [[ "$rc" -eq "$want" ]]; then
      echo "  PASS [$label] exit=$rc (expected $want)"
    else
      echo "  FAIL [$label] exit=$rc (expected $want)" >&2
      fails=1
    fi
  }

  # write_clean_tree: populate $1 (a renderer dir) + $2 (a project file) with a CLEAN synthetic
  # stand-in containing EVERY required token and NO forbidden token. Each negative-control case then
  # mutates exactly one thing and re-asserts.
  write_clean_tree() {
    local rdir="$1" pfile="$2"
    mkdir -p "$rdir"
    printf 'let semaphore = DispatchSemaphore(value: 1)\n'                 > "$rdir/$FRAME_SYNC"
    {
      printf 'layer.maximumDrawableCount = 2\n'
      printf 'layer.framebufferOnly = false\n'
    }                                                                       > "$rdir/$LAYER_CONFIG"
    # Zero-copy: the real path is setBytes. Put it in the encoder stand-in.
    printf 'encoder.setBytes(&u, length: 40, index: 0)\n'                  > "$rdir/WebgridFrameEncoder.swift"
    # iOS adapter: CAMetalDisplayLink present, NO bare CADisplayLink, plain present only.
    printf 'let link = CAMetalDisplayLink(metalLayer: layer)\ncb.present(drawable)\n' > "$rdir/$IOS_ADAPTER"
    # macOS adapter: NSView.displayLink(target:) — note this stand-in does NOT contain the bare
    # CADisplayLink literal so the iOS-scoped forbidden check is isolated; the macOS path is allowed
    # to contain CADisplayLink in the real tree, which is exactly why the forbidden check is scoped.
    printf 'let l = view.displayLink(target: self, selector: #selector(tick))\ncb.present(drawable)\n' > "$rdir/$MAC_ADAPTER"
    printf 'kernel void webgrid(texture2d<float, access::write> out) {}\n' > "$rdir/$WEBGRID_METAL"
    {
      printf 'CADisableMinimumFrameDurationOnPhone: true\n'
      printf 'MTL_HUD_ENABLED\n'
    }                                                                       > "$pfile"
  }

  echo "== render-policy self-test =="

  # 0. Baseline: the clean synthetic tree must PASS (exit 0). If this fails, the stand-in is wrong.
  echo "-- clean synthetic tree --"
  local base prj
  base="$(mktemp -d)"; prj="$(mktemp)"
  write_clean_tree "$base" "$prj"
  assert_exit 0 "clean tree" "$base" "$prj"
  rm -rf "$base"; rm -f "$prj"

  # 1. REQUIRED negative-controls: strip exactly one required token; the gate MUST exit 1.
  echo "-- required-token negative controls (strip -> exit 1) --"

  # 1a. Strip value:1 (downgrade to value:3) -> exit 1.
  base="$(mktemp -d)"; prj="$(mktemp)"; write_clean_tree "$base" "$prj"
  printf 'let semaphore = DispatchSemaphore(value: 3)\n' > "$base/$FRAME_SYNC"
  assert_exit 1 "strip value:1 (->value:3)" "$base" "$prj"; rm -rf "$base"; rm -f "$prj"

  # 1b. Strip maximumDrawableCount=2 (->3) -> exit 1.
  base="$(mktemp -d)"; prj="$(mktemp)"; write_clean_tree "$base" "$prj"
  printf 'layer.maximumDrawableCount = 3\nlayer.framebufferOnly = false\n' > "$base/$LAYER_CONFIG"
  assert_exit 1 "strip maximumDrawableCount=2 (->3)" "$base" "$prj"; rm -rf "$base"; rm -f "$prj"

  # 1c. Strip framebufferOnly=false (->true) -> exit 1.
  base="$(mktemp -d)"; prj="$(mktemp)"; write_clean_tree "$base" "$prj"
  printf 'layer.maximumDrawableCount = 2\nlayer.framebufferOnly = true\n' > "$base/$LAYER_CONFIG"
  assert_exit 1 "strip framebufferOnly=false (->true)" "$base" "$prj"; rm -rf "$base"; rm -f "$prj"

  # 1d. Strip the zero-copy upload (remove setBytes, no storageModeShared) -> exit 1.
  base="$(mktemp -d)"; prj="$(mktemp)"; write_clean_tree "$base" "$prj"
  printf 'encoder.setComputePipelineState(p)\n' > "$base/WebgridFrameEncoder.swift"
  assert_exit 1 "strip zero-copy upload (setBytes/storageModeShared)" "$base" "$prj"; rm -rf "$base"; rm -f "$prj"

  # 1e. Strip CAMetalDisplayLink from the iOS adapter -> exit 1.
  base="$(mktemp -d)"; prj="$(mktemp)"; write_clean_tree "$base" "$prj"
  printf 'let link = somethingElse(metalLayer: layer)\ncb.present(drawable)\n' > "$base/$IOS_ADAPTER"
  assert_exit 1 "strip CAMetalDisplayLink (iOS)" "$base" "$prj"; rm -rf "$base"; rm -f "$prj"

  # 1f. Strip displayLink(target: from the macOS adapter -> exit 1.
  base="$(mktemp -d)"; prj="$(mktemp)"; write_clean_tree "$base" "$prj"
  printf 'let l = CVDisplayLinkCreateWithActiveCGDisplays()\ncb.present(drawable)\n' > "$base/$MAC_ADAPTER"
  assert_exit 1 "strip displayLink(target: (macOS)" "$base" "$prj"; rm -rf "$base"; rm -f "$prj"

  # 1g. Strip kernel void webgrid from the metal shader -> exit 1.
  base="$(mktemp -d)"; prj="$(mktemp)"; write_clean_tree "$base" "$prj"
  printf 'fragment float4 webgrid() { return 0; }\n' > "$base/$WEBGRID_METAL"
  assert_exit 1 "strip kernel void webgrid" "$base" "$prj"; rm -rf "$base"; rm -f "$prj"

  # 1h. Strip the plist key from project.yml -> exit 1.
  base="$(mktemp -d)"; prj="$(mktemp)"; write_clean_tree "$base" "$prj"
  printf 'MTL_HUD_ENABLED\n' > "$prj"
  assert_exit 1 "strip CADisableMinimumFrameDurationOnPhone=true" "$base" "$prj"; rm -rf "$base"; rm -f "$prj"

  # 1i. Strip MTL_HUD_ENABLED from project.yml -> exit 1.
  base="$(mktemp -d)"; prj="$(mktemp)"; write_clean_tree "$base" "$prj"
  printf 'CADisableMinimumFrameDurationOnPhone: true\n' > "$prj"
  assert_exit 1 "strip MTL_HUD_ENABLED" "$base" "$prj"; rm -rf "$base"; rm -f "$prj"

  # 2. FORBIDDEN negative-controls: inject exactly one forbidden token; the gate MUST exit 1.
  echo "-- forbidden-token negative controls (inject -> exit 1) --"

  # 2a. Inject the legacy display-link literal into the iOS adapter -> exit 1 (RENDER-01).
  base="$(mktemp -d)"; prj="$(mktemp)"; write_clean_tree "$base" "$prj"
  printf 'let link = CAMetalDisplayLink(metalLayer: layer)\nlet bad: CADisplayLink? = nil\ncb.present(drawable)\n' > "$base/$IOS_ADAPTER"
  assert_exit 1 "inject CADisplayLink into iOS adapter" "$base" "$prj"; rm -rf "$base"; rm -f "$prj"

  # 2a'. CONTROL: the SAME CADisplayLink literal in the macOS adapter must NOT trip the gate (the
  #      forbidden check is iOS-scoped; the macOS NSView.displayLink path legitimately names it).
  base="$(mktemp -d)"; prj="$(mktemp)"; write_clean_tree "$base" "$prj"
  printf 'private var link: CADisplayLink?\nlet l = view.displayLink(target: self, selector: #selector(tick))\ncb.present(drawable)\n' > "$base/$MAC_ADAPTER"
  assert_exit 0 "CADisplayLink in macOS adapter is ALLOWED (scoping control)" "$base" "$prj"; rm -rf "$base"; rm -f "$prj"

  # 2b. Inject storageModeManaged into the renderer tree -> exit 1 (RENDER-06).
  base="$(mktemp -d)"; prj="$(mktemp)"; write_clean_tree "$base" "$prj"
  printf 'let opts: MTLResourceOptions = .storageModeManaged\n' > "$base/Staging.swift"
  assert_exit 1 "inject storageModeManaged" "$base" "$prj"; rm -rf "$base"; rm -f "$prj"

  # 2c. Inject a timed present(at:) into the iOS adapter -> exit 1 (RESEARCH #5).
  base="$(mktemp -d)"; prj="$(mktemp)"; write_clean_tree "$base" "$prj"
  printf 'let link = CAMetalDisplayLink(metalLayer: layer)\ncb.present(at: t)\n' > "$base/$IOS_ADAPTER"
  assert_exit 1 "inject present(at: into iOS adapter" "$base" "$prj"; rm -rf "$base"; rm -f "$prj"

  if [[ "$fails" -eq 0 ]]; then
    echo "SELF-TEST OK: every required-token strip and every forbidden-token injection bites; the"
    echo "              scoped macOS CADisplayLink is allowed; a clean tree passes."
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
  echo "OK: render policy clean — all renderer commitments asserted, no forbidden tokens."
  exit 0
else
  echo "render-policy: FAILED — a renderer commitment regressed (see ERROR lines above)." >&2
  exit 1
fi
