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
  float cursorRadius;     // disc radius, normalised to the grid's shorter extent (D-08)
  float proximityRadius;  // proximity-highlight falloff radius, same units (D-09)
  uint viewportWidth;     // drawable width  (px)
  uint viewportHeight;    // drawable height (px)
};

// Signed distance to a rounded box centered at the origin with half-size `halfExtent` and corner
// radius `r` (classic rounded-box SDF). Negative inside, zero on the edge, positive outside. Used to
// draw filled rounded cells with smooth (antialiased) edges (D-06). NOTE: the parameter is
// `halfExtent`, not `half` — `half` is the reserved 16-bit float type in MSL.
static inline float rounded_box_sdf(float2 p, float2 halfExtent, float r) {
  float2 q = abs(p) - (halfExtent - r);
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Dark Neuralink-style palette (D-07): near-black background, cool-toned (blue) cells, near-white
// high-luminance cursor (the cleanest rising edge for the Phase 9 photodiode).
constant float4 kBackgroundColor = float4(0.02, 0.02, 0.04, 1.0);  // near-black
constant float4 kCellColor       = float4(0.10, 0.16, 0.32, 1.0);  // cool blue cell
constant float4 kCursorColor     = float4(0.95, 0.98, 1.00, 1.0);  // bright disc (D-08)

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

    // (4) Filled rounded cell (D-06): shrink the drawable cell box by half the gap on each side,
    //     then test the rounded-box SDF. cellGap is a fraction of the cell pitch; cornerRadius is a
    //     fraction of the cell's half-extent. SDF gives a smooth 1px-antialiased edge.
    const float2 cellHalf = (0.5 - p.cellGap * 0.5) * float2(1.0, 1.0);  // half-size in cell-local units
    const float2 fromCenter = cellLocal - 0.5;
    const float radius = clamp(p.cornerRadius, 0.0, 1.0) * min(cellHalf.x, cellHalf.y);
    const float d = rounded_box_sdf(fromCenter, cellHalf, radius);
    // Antialias width ~ one pixel expressed in cell-local units (cell pitch maps `cellPitch` per px).
    const float aa = max(cellPitch.x, cellPitch.y) * 1.5;
    const float cellMask = 1.0 - smoothstep(-aa, aa, d);  // 1 inside the rounded cell, 0 in the gap

    if (cellMask > 0.0) {
      // (5) Subtle cursor-proximity brighten (D-09): scale cell luminance up near the cursor with a
      //     smooth falloff over proximityRadius. Pure visual — no selection/scoring logic (D-01).
      const float2 cursor = float2(p.cursorX, p.cursorY);
      const float distToCursor = distance(g, cursor);
      const float prox = 1.0 - smoothstep(0.0, max(p.proximityRadius, 1e-4), distToCursor);
      const float brighten = 1.0 + 0.6 * prox;            // up to +60% near the cursor
      const float4 litCell = float4(kCellColor.rgb * brighten, kCellColor.a);
      color = mix(color, litCell, cellMask);
    }

    // (6) Bright filled-disc cursor (D-08), drawn last so it sits on top — NO trail. A pixel is part
    //     of the cursor when its grid-space distance to the cursor center is < cursorRadius. A NaN
    //     cursor position simply fails this test and draws no disc (T-06-01-01: defensive — the
    //     authoritative clamp lives upstream at the integrator seam, Plan 02 D-04).
    const float2 cursor = float2(p.cursorX, p.cursorY);
    const float distToCursor = distance(g, cursor);
    const float aaC = max(cellPitch.x, cellPitch.y) * 0.75;
    const float cursorMask = 1.0 - smoothstep(p.cursorRadius - aaC, p.cursorRadius + aaC, distToCursor);
    color = mix(color, kCursorColor, cursorMask);
  }

  // (3)/(write) Single write per pixel into the drawable texture (extent-bounded by the guard above).
  out.write(color, gid);
}
