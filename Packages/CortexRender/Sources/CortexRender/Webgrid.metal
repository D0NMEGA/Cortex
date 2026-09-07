#include <metal_stdlib>
using namespace metal;

// Webgrid.metal — the 30×30 webgrid + bright-disc cursor compute kernel (RENDER-04).
//
// One compute thread per output pixel writes the full frame directly into the drawable texture
// (compute-direct-to-drawable, RESEARCH Decision 4 path (a) — requires CAMetalLayer.framebufferOnly
// = false, applied in MetalLayerConfig). ~900 cells of per-pixel math, well within the ≤0.4ms GPU
// budget on M-series.
//
// `struct WebgridParams` MIRRORS WebgridParams.swift FIELD-FOR-FIELD, BYTE-FOR-BYTE — the encoder
// uploads the Swift value as raw bytes (`setBytes`), so the field order here is load-bearing and
// MUST NOT be reordered (gridColumns/gridRows first, viewportWidth/viewportHeight last). All fields
// are 4-byte scalars (uint/float) with natural alignment, matching the Swift trivial value type.
struct WebgridParams {
  uint gridColumns;       // 30
  uint gridRows;          // 30
  float cellGap;          // inter-cell gap fraction (D-06)
  float cornerRadius;     // rounded-cell corner radius fraction (D-06)
  float cursorX;          // cursor X in grid-normalised [0,1]
  float cursorY;          // cursor Y in grid-normalised [0,1]
  float cursorRadius;     // ring OUTER radius, normalised to the grid's shorter extent (D-08)
  float proximityRadius;  // proximity-highlight falloff radius, same units (D-09)
  uint viewportWidth;     // drawable width  (px)
  uint viewportHeight;    // drawable height (px)
  float cursorDotRadius;  // inner-dot radius of the ring cursor, same units
  float cursorRingWidth;  // ring stroke width, same units
  float targetX;          // active target X, grid-normalised [0,1]
  float targetY;          // active target Y, grid-normalised [0,1]
  float targetRadius;     // half-extent of the drawn target = the ACQUISITION RADIUS
  uint  hasTarget;        // 1 when a target is active, 0 when none is
  float dwellProgress;    // dwell-to-select progress in [0,1]; contracts the ring
  float targetFlash;      // selection flash in [0,1], decaying; greens and swells the target
};

// Signed distance to a rounded box centered at the origin with half-size `halfExtent` and corner
// radius `r` (classic rounded-box SDF). Negative inside, zero on the edge, positive outside. Used to
// draw filled rounded cells with smooth (antialiased) edges (D-06). NOTE: the parameter is
// `halfExtent`, not `half` — `half` is the reserved 16-bit float type in MSL.
static inline float rounded_box_sdf(float2 p, float2 halfExtent, float r) {
  float2 q = abs(p) - (halfExtent - r);
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Dark webgrid palette (D-07): a near-black field ruled with faint white lines, so the only bright
// things on screen are the cursor and the active target. The cursor keeps its near-white
// high-luminance edge (the cleanest rising edge for a photodiode capture).
constant float4 kBackgroundColor = float4(0.02, 0.02, 0.04, 1.0);  // near-black field
constant float4 kGridLineColor   = float4(1.00, 1.00, 1.00, 1.0);  // white rule, applied at low alpha
constant float  kGridLineAlpha   = 0.15;                            // faint, so it reads as a substrate
constant float4 kCursorColor     = float4(0.95, 0.98, 1.00, 1.0);  // ring + inner dot (D-08)
constant float4 kTargetColor     = float4(0.90, 0.16, 0.20, 1.0);   // red selection square
constant float4 kAcquiredColor   = float4(0.20, 0.88, 0.40, 1.0);   // green, on a committed selection

kernel void webgrid(texture2d<float, access::write> out [[texture(0)]],
                    constant WebgridParams& p [[buffer(0)]],
                    uint2 gid [[thread_position_in_grid]]) {
  // (1) Pixel-bounds guard BEFORE any write — `framebufferOnly = false` opens the write scope, so
  //     this kernel is the sole writer and must never write outside the drawable extent
  //     (threat T-06-01-02). dispatchThreads is sized to texture.width/height, but threadgroups can
  //     overhang the grid edge, so the early-return is mandatory.
  const uint w = out.get_width();
  const uint h = out.get_height();
  if (gid.x >= w || gid.y >= h) {
    return;
  }

  // (2) Square-cell letterbox mapping: the grid occupies the largest centered square that fits the
  //     viewport, so cells stay square regardless of aspect ratio (preserve-square discretion).
  const float2 pixel = float2(gid) + 0.5;                 // pixel center
  const float side = float(min(w, h));                    // square grid extent in px
  const float2 origin = (float2(w, h) - side) * 0.5;      // top-left of the centered square
  const float2 g = (pixel - origin) / side;               // grid-normalised coords in [0,1]^2

  // Default: near-black background (covers the letterbox margins and inter-cell gaps).
  float4 color = kBackgroundColor;

  // Only shade inside the centered square; outside stays background.
  if (g.x >= 0.0 && g.x <= 1.0 && g.y >= 0.0 && g.y <= 1.0) {
    const float cols = float(max(p.gridColumns, 1u));     // DoS guard: never divide by zero
    const float rows = float(max(p.gridRows, 1u));        //            (T-06-01-03 cheap guard)

    // Which cell this pixel falls in, and its local position within that cell pitch [0,1)^2.
    const float2 cellPitch = float2(1.0 / cols, 1.0 / rows);
    const float2 cellLocal = float2(fract(g.x * cols), fract(g.y * rows));

    // (4) Ruled grid lines (D-06): the field is drawn as thin white rules on the cell boundaries
    //     rather than as 900 filled tiles, so the cursor and the target are the only bright things
    //     on screen. Line half-width is derived from the pixel size so the rule stays ~1px at any
    //     resolution instead of thickening as the window grows.
    const float2 pixelInGrid = float2(1.0 / side, 1.0 / side);   // one px in grid-normalised units
    const float lineHalf = max(pixelInGrid.x, pixelInGrid.y) * 0.5;
    // Distance to the nearest cell boundary on each axis, in grid-normalised units.
    const float2 toEdge = min(cellLocal, 1.0 - cellLocal) * cellPitch;
    const float edgeDist = min(toEdge.x, toEdge.y);
    const float aa = max(pixelInGrid.x, pixelInGrid.y);
    const float lineMask = 1.0 - smoothstep(lineHalf, lineHalf + aa, edgeDist);

    // (5) Subtle cursor-proximity brighten (D-09): lift the rule's alpha near the cursor with a
    //     smooth falloff over proximityRadius. Pure visual — no selection/scoring logic (D-01).
    const float2 cursor = float2(p.cursorX, p.cursorY);
    const float distToCursor = distance(g, cursor);
    const float prox = 1.0 - smoothstep(0.0, max(p.proximityRadius, 1e-4), distToCursor);
    const float lineAlpha = kGridLineAlpha * (1.0 + 1.4 * prox);   // brighter rule near the cursor

    if (lineMask > 0.0) {
      color = mix(color, kGridLineColor, saturate(lineMask * lineAlpha));
    }

    // (6) The active target, drawn AT ITS ACTUAL POSITION and sized to the acquisition radius --
    //     NOT snapped to a grid cell. The criterion tests distance to this point, so quantising the
    //     drawing to a cell put the square a median 2.26 mm from the scored point against a 2.86 mm
    //     radius, and a cursor centred in the square was scored as a miss with nothing on screen to
    //     explain it. `hasTarget == 0` draws nothing, so an absent target is a visual no-op.
    if (p.hasTarget != 0u) {
      {
        // A committed selection greens the square and swells it briefly, then decays back. The
        // swell is what makes a 300 ms event legible at 12 fps; the colour is what distinguishes it
        // from the cursor merely passing over the cell, which happens constantly and means nothing.
        const float flash = clamp(p.targetFlash, 0.0, 1.0);
        // Half-extent IS the acquisition radius, so the square a viewer sees is the region tested.
        // Generously rounded, which also brings the corners in toward the circle the criterion
        // actually uses; the residual overshoot is at the four corners only.
        // NOT named `half`: that is the reserved 16-bit float type in MSL, the same trap
        // `rounded_box_sdf`'s `halfExtent` parameter is named around.
        const float targetExtent = max(p.targetRadius, 1e-5) * (1.0 + 0.45 * flash);
        const float2 targetHalf = float2(targetExtent);
        const float2 fromCenter = g - float2(p.targetX, p.targetY);
        const float corner = 0.35 * targetExtent;
        const float dT = rounded_box_sdf(fromCenter, targetHalf, corner);
        const float aaT = max(pixelInGrid.x, pixelInGrid.y);
        const float targetMask = 1.0 - smoothstep(-aaT, aaT, dT);
        color = mix(color, mix(kTargetColor, kAcquiredColor, flash), targetMask);
      }
    }

    // (7) Ring cursor with an inner dot (D-08), drawn last so it sits on top — NO trail. The ring is
    //     the annulus between cursorRadius and cursorRadius - cursorRingWidth; the dot is a small
    //     filled disc at the same center. A NaN cursor position fails every comparison below and
    //     draws nothing (T-06-01-01: defensive — the authoritative clamp lives upstream at the
    //     integrator seam, Plan 02 D-04).
    //
    //     DWELL-TO-SELECT: holding inside the acquisition radius contracts the ring toward the dot,
    //     and committing the selection releases it back to full size (the producer resets progress
    //     to 0 on the committing tick). The contraction is the standard webgrid selection
    //     affordance, and it is driven by the SAME 0.30 s continuous-hold criterion the run is
    //     scored with — so a viewer sees selections happen at the rate they actually happen, which
    //     for a target-blind decode is the honest answer whatever that rate is.
    const float dwell = clamp(p.dwellProgress, 0.0, 1.0);
    const float aaC = max(pixelInGrid.x, pixelInGrid.y) * 1.0;
    // Contract to 35% of the resting radius at a full hold, never below the dot.
    const float restingOuter = max(p.cursorRadius, 1e-5);
    const float minOuter = max(max(p.cursorDotRadius, 1e-5) * 1.6, restingOuter * 0.35);
    const float ringOuter = mix(restingOuter, min(minOuter, restingOuter), dwell);
    const float ringInner = max(ringOuter - max(p.cursorRingWidth, 1e-5), 0.0);
    // Inside the outer edge AND outside the inner edge.
    const float ringMask =
      (1.0 - smoothstep(ringOuter - aaC, ringOuter + aaC, distToCursor))
      * smoothstep(ringInner - aaC, ringInner + aaC, distToCursor);
    const float dotMask =
      1.0 - smoothstep(max(p.cursorDotRadius, 1e-5) - aaC, max(p.cursorDotRadius, 1e-5) + aaC, distToCursor);
    color = mix(color, kCursorColor, saturate(ringMask + dotMask));
  }

  // (3)/(write) Single write per pixel into the drawable texture (extent-bounded by the guard above).
  out.write(color, gid);
}
