#!/usr/bin/env bash
# Record the Cortex macOS demo and produce a README-ready GIF.
#
# Everything that affects what lands in the frame is done by this script, not by hand: the window is
# moved to a fixed origin and resized to a fixed pixel size before recording starts, and recording
# begins only after the renderer has actually produced frames. That way the GIF starts at t = 0 of a
# real session rather than partway through one, and two runs are framed identically.
#
# Usage:
#   Tools/capture/record-demo.sh                 # build, launch, record, encode
#   Tools/capture/record-demo.sh --seconds 25    # longer capture
#   Tools/capture/record-demo.sh --no-build      # reuse the existing build
#
# One-time setup, and the script checks it for you: recording and window placement both need
# permission. Grant your terminal both of these in System Settings > Privacy & Security:
#   - Screen & System Audio Recording
#   - Accessibility            (so the window can be positioned; without it you get whatever
#                               position the window opened at, and the frame will not match)
# macOS will prompt on first run. If it does, grant, then quit and reopen the terminal and re-run.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO"

# --- Framing. Fixed so successive captures are comparable and so the GIF width matches GitHub's
# README column (about 890 px), avoiding a browser downscale that smears the grid. -----------------
WIN_X=60
WIN_Y=60
WIN_W=1120          # window points; the capture is cropped to the content area below
WIN_H=680
GIF_WIDTH=900       # final GIF width in px
FPS=12              # 12 is plenty for a cursor demo and roughly halves the size versus 24
SECONDS_TO_RECORD=20
DO_BUILD=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seconds) SECONDS_TO_RECORD="$2"; shift 2 ;;
    --fps) FPS="$2"; shift 2 ;;
    --width) GIF_WIDTH="$2"; shift 2 ;;
    --no-build) DO_BUILD=0; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

OUT_DIR="$REPO/Tools/capture/out"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
MOV="$OUT_DIR/cortex-demo-$STAMP.mov"
GIF="$OUT_DIR/cortex-demo-$STAMP.gif"
PALETTE="$OUT_DIR/.palette-$STAMP.png"

EXPORT_JSON="$REPO/Decoder/exports/indy_20160630_01.replay.json"
MODEL="$REPO/Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage"

log() { printf '  %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- Preconditions ------------------------------------------------------------------------------
command -v ffmpeg >/dev/null || die "ffmpeg not found. brew install ffmpeg"
EXPORT_HELP="Run: uv run --project Decoder python Decoder/scripts/download_indy.py && uv run --project Decoder python Decoder/scripts/export_replay.py"
[[ -f "$EXPORT_JSON" ]] || die "missing $EXPORT_JSON. $EXPORT_HELP"
# The json is only a manifest; the spikes live in the sibling .bin named inside it. Both are
# gitignored and materialized separately, so check the one that actually carries the data.
EXPORT_BIN="${EXPORT_JSON%.json}.bin"
[[ -f "$EXPORT_BIN" ]] || die "missing $EXPORT_BIN (the json is only its manifest). $EXPORT_HELP"
[[ -d "$MODEL" ]] || die "missing $MODEL"

# --- Build ---------------------------------------------------------------------------------------
# CODE_SIGN_ENTITLEMENTS is overridden to the capture entitlements: the BCI HID virtual-device
# entitlement is Apple-managed and cannot be provisioned by a free Personal team, so a build that
# requests it fails to sign. The capture entitlements keep the App Group (the shm IPC needs it) and
# drop only what free-team signing cannot grant.
if [[ "$DO_BUILD" == "1" ]]; then
  log "building CortexMac"
  xcodegen generate >/dev/null
  xcodebuild build \
    -project Cortex.xcodeproj -scheme CortexMac -configuration Debug \
    -destination 'generic/platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_ENTITLEMENTS=Tools/capture/CortexMac.capture.entitlements \
    -skipPackagePluginValidation -skipMacroValidation >/dev/null \
    || die "build failed. Run the same xcodebuild without the >/dev/null to see why."
fi

APP="$(find ~/Library/Developer/Xcode/DerivedData -name 'CortexMac.app' -type d 2>/dev/null | head -1)"
[[ -n "$APP" ]] || die "CortexMac.app not found in DerivedData"
log "app: $APP"

# --- Launch, then frame the window ---------------------------------------------------------------
pkill -x CortexMac 2>/dev/null || true

log "launching with the real replay export"
CORTEX_REPLAY_EXPORT="$EXPORT_JSON" \
CORTEX_MODEL_URL="$MODEL" \
  open -n "$APP"

# Wait for the window to exist before touching it. Polling beats a fixed sleep: a cold first launch
# can take several seconds while CoreML compiles the model.
log "waiting for the window"
for _ in $(seq 1 60); do
  if osascript -e 'tell application "System Events" to exists (window 1 of process "CortexMac")' 2>/dev/null | grep -q true; then
    break
  fi
  sleep 0.5
done

osascript <<OSA 2>/dev/null || log "WARNING: could not position the window (grant Accessibility to your terminal). Framing may be off."
tell application "System Events"
  tell process "CortexMac"
    set frontmost to true
    set position of window 1 to {$WIN_X, $WIN_Y}
    set size of window 1 to {$WIN_W, $WIN_H}
  end tell
end tell
OSA

# Read the frame BACK rather than assuming the request was honoured. SwiftUI enforces a minimum
# height for the two-pane layout (about 884 pt), so asking for 680 yields a taller window and a
# capture rect computed from the REQUESTED size clips off everything below the fold -- which is the
# arm captions and the instrumentation strip, the part that says what the demo is.
FRAME="$(osascript -e 'tell application "System Events" to tell process "CortexMac" to get {item 1 of position, item 2 of position, item 1 of size, item 2 of size} of window 1' 2>/dev/null | tr -d ' ')"
if [[ "$FRAME" =~ ^-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+$ ]]; then
  IFS=, read -r WIN_X WIN_Y WIN_W WIN_H <<<"$FRAME"
  log "window frame: ${WIN_W}x${WIN_H} at ${WIN_X},${WIN_Y}"
else
  log "WARNING: could not read the window frame back; using the requested ${WIN_W}x${WIN_H}"
fi

# Let the renderer settle so the capture opens on a live grid rather than a blank surface. This is
# the only fixed wait in the script and it is deliberately short.
sleep 2

# --- Record ---------------------------------------------------------------------------------------
# -R takes a screen rect in points, from the frame read back above; a couple of points are trimmed
# off the top for the title bar.
RECT="${WIN_X},$((WIN_Y + 28)),${WIN_W},$((WIN_H - 28))"
log "recording ${SECONDS_TO_RECORD}s of rect ${RECT}"
screencapture -v -V "$SECONDS_TO_RECORD" -R "$RECT" "$MOV" >/dev/null 2>&1 || die "screencapture failed. Grant Screen Recording to your terminal."
pkill -x CortexMac 2>/dev/null || true
[[ -f "$MOV" ]] || die "no movie produced"
log "movie: $(du -h "$MOV" | cut -f1)"

# --- Encode ----------------------------------------------------------------------------------------
# Two-pass palette. A single-pass GIF from a Metal render band-posterises the grid; generating a
# palette from the whole clip first keeps the cursor and grid lines clean at a fraction of the size.
encode() {
  local w="$1" fps="$2"
  ffmpeg -y -loglevel error -i "$MOV" \
    -vf "fps=${fps},scale=${w}:-1:flags=lanczos,palettegen=stats_mode=diff" "$PALETTE"
  ffmpeg -y -loglevel error -i "$MOV" -i "$PALETTE" \
    -lavfi "fps=${fps},scale=${w}:-1:flags=lanczos[v];[v][1:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
    "$GIF"
}

encode "$GIF_WIDTH" "$FPS"

# GitHub rejects images and GIFs over 10 MB. Step down rather than hand back a file that will not
# upload; each step is reported so the final settings are known and reproducible.
LIMIT=$((10 * 1024 * 1024))
for attempt in "800 10" "700 10" "640 8"; do
  size=$(stat -f%z "$GIF")
  [[ "$size" -le "$LIMIT" ]] && break
  set -- $attempt
  log "GIF is $((size / 1024 / 1024)) MB, over GitHub's 10 MB limit; re-encoding at ${1}px ${2}fps"
  encode "$1" "$2"
done
rm -f "$PALETTE"

size=$(stat -f%z "$GIF")
log ""
log "GIF:   $GIF"
log "size:  $((size / 1024 / 1024)) MB  ($size bytes; GitHub's limit is 10 MB)"
log "frames: $(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$GIF" 2>/dev/null || echo '?')"
log ""
log "Next: move it to docs/media/ and reference it from README.md."
