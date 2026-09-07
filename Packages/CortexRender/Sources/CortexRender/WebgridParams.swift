// WebgridParams — the CPU→GPU uniforms payload for the 30×30 webgrid compute kernel.
//
// This struct is uploaded to the GPU as RAW BYTES (via `setBytes`, or a `storageModeShared`
// buffer — RENDER-06, zero-copy), so its field layout is load-bearing: the Metal-side
// `struct WebgridParams` in `Webgrid.metal` MUST mirror this field order BYTE-FOR-BYTE
// (gridColumns/gridRows first, viewportWidth/viewportHeight last). Field-ordering discipline is
// modelled on the `#[repr(C)] CortexFrame` ABI in `Packages/CortexRing/rust/include/cortex_ring.h`:
// fixed-width fields, explicit order, no reference fields.
//
// All fields are trivial scalars (`UInt32`/`Float`) — no `simd` vectors, no reference types — so
// the byte layout trivially matches the C/MSL struct (`uint`/`float` scalars) with natural 4-byte
// alignment and no padding surprises.

/// The ruled lattice the grid draws: spacing and offset in grid-normalised units.
public nonisolated struct GridLattice: Sendable, Equatable {
  public let pitchX: Float
  public let pitchY: Float
  public let phaseX: Float
  public let phaseY: Float

  public init(pitchX: Float, pitchY: Float, phaseX: Float, phaseY: Float) {
    self.pitchX = pitchX
    self.pitchY = pitchY
    self.phaseX = phaseX
    self.phaseY = phaseY
  }

  /// The uniform 30x30 substrate, anchored at the workspace corner.
  public static let uniform30 = GridLattice(
    pitchX: 1.0 / 30.0, pitchY: 1.0 / 30.0, phaseX: 0, phaseY: 0
  )

  /// A lattice at `pitch`, phased so that `reference` sits at a cell CENTRE.
  ///
  /// Used to draw the task's own target lattice: pass any observed target position and the rules
  /// land so every target of that lattice fills a cell.
  public static func centred(on reference: SIMD2<Float>, pitch: SIMD2<Float>) -> GridLattice {
    func phase(_ ref: Float, _ p: Float) -> Float {
      guard p > 0, ref.isFinite else { return 0 }
      let raw = (ref - 0.5 * p).truncatingRemainder(dividingBy: p)
      return raw < 0 ? raw + p : raw
    }
    return GridLattice(
      pitchX: pitch.x, pitchY: pitch.y,
      phaseX: phase(reference.x, pitch.x), phaseY: phase(reference.y, pitch.y)
    )
  }
}

/// Uniforms describing the webgrid + cursor for one frame, shared Swift↔Metal.
///
/// `Sendable` because it crosses into the display-link callback (Plan 03) under the package's
/// `.defaultIsolation(MainActor.self)` + `SWIFT_STRICT_CONCURRENCY: complete` posture; it is a
/// trivial value type, so the conformance is sound (no captured reference state).
///
/// Coordinate spaces:
/// - `cursorX`/`cursorY` are in grid-normalised `[0, 1]` space (mapped to the letterboxed
///   square-cell grid extent in the kernel).
/// - `cursorRadius`/`proximityRadius` are normalised to the grid's shorter extent (the kernel
///   scales them to pixels), so they stay resolution-independent.
public nonisolated struct WebgridParams: Sendable, Equatable {
  /// Number of columns in the grid (30 — D-01 30×30 substrate).
  public var gridColumns: UInt32
  /// Number of rows in the grid (30 — D-01 30×30 substrate).
  public var gridRows: UInt32
  /// Gap fraction between adjacent cells (D-06 small gaps), in units of one cell pitch.
  public var cellGap: Float
  /// Rounded-cell corner radius as a fraction of the cell's half-extent (D-06 rounded cells).
  public var cornerRadius: Float
  /// Cursor X position in grid-normalised `[0, 1]` space.
  public var cursorX: Float
  /// Cursor Y position in grid-normalised `[0, 1]` space.
  public var cursorY: Float
  /// Bright filled-disc cursor radius (D-08), normalised to the grid's shorter extent.
  public var cursorRadius: Float
  /// Cursor-proximity cell-highlight falloff radius (D-09), normalised to the grid's shorter extent.
  ///
  /// ``grid30x30`` passes 0, which disables the lift. At the original 0.12 the falloff reached 3.6
  /// cells from the cursor, so it read on screen as a soft grey blob following the cursor rather
  /// than as a highlight, and it was the brightest thing in a capture after the cursor itself. The
  /// parameter and the kernel's falloff are kept because the effect is sound at a small radius.
  public var proximityRadius: Float
  /// Drawable width in pixels (for square-cell aspect mapping).
  public var viewportWidth: UInt32
  /// Drawable height in pixels (for square-cell aspect mapping).
  public var viewportHeight: UInt32
  /// Inner-dot radius of the ring cursor, normalised to the grid's shorter extent.
  public var cursorDotRadius: Float
  /// Ring stroke width of the ring cursor, normalised to the grid's shorter extent.
  public var cursorRingWidth: Float
  /// Active target X in grid-normalised `[0, 1]`, meaningful only when ``hasTarget`` is 1.
  public var targetX: Float
  /// Active target Y in grid-normalised `[0, 1]`, meaningful only when ``hasTarget`` is 1.
  public var targetY: Float
  /// The ACQUISITION RADIUS, in the same units as ``cursorRadius``.
  ///
  /// The criterion is `distance(cursor, target) <= targetRadius`: a CIRCLE. The kernel draws the
  /// square INSCRIBED in that circle and outlines the circle itself, so every point inside the
  /// square satisfies the criterion. Drawing a square of half-extent `targetRadius` instead put
  /// 19.3% of the drawn area outside the scored circle -- measured, not estimated: a rounded box of
  /// half-extent R with corner 0.35R reaches 1.269R at its corners -- so roughly one in five ticks
  /// with the cursor visibly inside the red square was scored as a miss, with nothing on screen to
  /// explain it.
  public var targetRadius: Float
  /// 1 when a target is active, 0 when none is. A scalar rather than a sentinel so every field
  /// stays a 4-byte value and the Swift/MSL byte mirror stays trivial.
  public var hasTarget: UInt32
  /// Rule spacing in grid-normalised units. Defaults to `1/30`, the uniform 30x30 substrate.
  ///
  /// A pitch and a phase rather than a column count, because the ruled lattice has to be able to
  /// line up with the TASK's target lattice. This session's targets step 15 mm apart on a workspace
  /// 171.68 mm across, which is 2.62 cells of a 30x30 grid -- an irrational step, so no 30x30 grid
  /// can ever have a target sit on a cell. Drawing the task's own pitch is the only way the squares
  /// land on the lattice without moving them off the point the criterion scores.
  public var gridPitchX: Float
  public var gridPitchY: Float
  /// Offset of the first rule from the grid origin, in the same units, so the lattice can be phased
  /// onto the target positions rather than onto the workspace corner.
  public var gridPhaseX: Float
  public var gridPhaseY: Float
  /// Dwell-to-select progress in `[0, 1]`; the kernel shrinks the cursor ring as it climbs.
  ///
  /// The standard webgrid selection affordance: holding on a target contracts the ring, and
  /// committing the selection releases it back to full size. 0 draws the resting cursor.
  public var dwellProgress: Float
  /// 1 once this trial's target has been acquired, 0 before. Greens the target and HOLDS it green.
  ///
  /// A latch rather than a fading value, because the cursor ring releases to full size both on a
  /// commit and on a broken hold: green is the only thing on screen that distinguishes them, and a
  /// viewer scrubbing a recording has to be able to see which trials were acquired.
  public var targetAcquired: Float
  /// How recently the acquisition happened, decaying `1 → 0`. Swells the target briefly.
  public var targetSwell: Float

  /// Memberwise initializer (explicit so the public API is stable across the FFI/MSL mirror).
  public init(
    gridColumns: UInt32,
    gridRows: UInt32,
    cellGap: Float,
    cornerRadius: Float,
    cursorX: Float,
    cursorY: Float,
    cursorRadius: Float,
    proximityRadius: Float,
    viewportWidth: UInt32,
    viewportHeight: UInt32,
    cursorDotRadius: Float = 0.006,
    cursorRingWidth: Float = 0.0035,
    targetX: Float = 0,
    targetY: Float = 0,
    targetRadius: Float = 0.5 / 30.0,
    hasTarget: UInt32 = 0,
    gridPitchX: Float = 1.0 / 30.0,
    gridPitchY: Float = 1.0 / 30.0,
    gridPhaseX: Float = 0,
    gridPhaseY: Float = 0,
    dwellProgress: Float = 0,
    targetAcquired: Float = 0,
    targetSwell: Float = 0
  ) {
    self.gridColumns = gridColumns
    self.gridRows = gridRows
    self.cellGap = cellGap
    self.cornerRadius = cornerRadius
    self.cursorX = cursorX
    self.cursorY = cursorY
    self.cursorRadius = cursorRadius
    self.proximityRadius = proximityRadius
    self.viewportWidth = viewportWidth
    self.viewportHeight = viewportHeight
    self.cursorDotRadius = cursorDotRadius
    self.cursorRingWidth = cursorRingWidth
    self.targetX = targetX
    self.targetY = targetY
    self.targetRadius = targetRadius
    self.hasTarget = hasTarget
    self.gridPitchX = gridPitchX
    self.gridPitchY = gridPitchY
    self.gridPhaseX = gridPhaseX
    self.gridPhaseY = gridPhaseY
    self.dwellProgress = dwellProgress
    self.targetAcquired = targetAcquired
    self.targetSwell = targetSwell
  }

  /// The modern 30×30 webgrid (D-01) — 900 cells, NOT the rejected 6×6 (REQUIREMENTS Out-of-Scope).
  ///
  /// Fills `gridColumns`/`gridRows` = 30, small inter-cell gaps and rounded corners (D-06), and
  /// sensible cursor-disc / proximity-highlight radii (D-08/D-09). Only the cursor position and the
  /// drawable extent vary per frame.
  ///
  /// - Parameters:
  ///   - cursorX: cursor X in grid-normalised `[0, 1]` space.
  ///   - cursorY: cursor Y in grid-normalised `[0, 1]` space.
  ///   - viewportWidth: drawable width in pixels.
  ///   - viewportHeight: drawable height in pixels.
  public static func grid30x30(
    cursorX: Float,
    cursorY: Float,
    viewportWidth: UInt32,
    viewportHeight: UInt32,
    target: ActiveTarget? = nil,
    lattice: GridLattice = .uniform30,
    targetRadius: Float = 0.5 / 30.0,
    dwellProgress: Float = 0,
    targetAcquired: Float = 0,
    targetSwell: Float = 0
  ) -> WebgridParams {
    WebgridParams(
      gridColumns: 30,
      gridRows: 30,
      cellGap: 0.08,
      cornerRadius: 0.25,
      cursorX: cursorX,
      cursorY: cursorY,
      cursorRadius: 0.020,
      proximityRadius: 0,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      cursorDotRadius: 0.006,
      cursorRingWidth: 0.0035,
      targetX: target?.x ?? 0,
      targetY: target?.y ?? 0,
      targetRadius: targetRadius,
      hasTarget: target == nil ? 0 : 1,
      gridPitchX: lattice.pitchX,
      gridPitchY: lattice.pitchY,
      gridPhaseX: lattice.phaseX,
      gridPhaseY: lattice.phaseY,
      dwellProgress: dwellProgress,
      targetAcquired: targetAcquired,
      targetSwell: targetSwell
    )
  }
}
