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

/// The finite board of whole cells the task uses, grid-normalised.
///
/// A lattice alone is infinite. Drawn to the pane edge it cuts cells in half at the left, the right
/// and the centre seam, and a viewer cannot tell how large the board is supposed to be. This names
/// it: a square of whole cells, centred on the targets, with background around it.
public nonisolated struct Board: Sendable, Equatable {
  public let centreX: Float
  public let centreY: Float
  /// Half the board's side. 0 draws no board and no rules.
  public let half: Float

  public init(centreX: Float, centreY: Float, half: Float) {
    self.centreX = centreX
    self.centreY = centreY
    self.half = half
  }

  /// The whole grid-normalised square, for a caller with no task board of its own.
  public static let wholeGrid = Board(centreX: 0.5, centreY: 0.5, half: 0.5)

  /// A board of `cells` whole cells at `pitch`, centred on `centre`.
  public static func cells(_ cells: Int, pitch: Float, centre: SIMD2<Float>) -> Board {
    guard cells > 0, pitch > 0, pitch.isFinite, centre.x.isFinite, centre.y.isFinite else {
      return .wholeGrid
    }
    return Board(centreX: centre.x, centreY: centre.y, half: Float(cells) * pitch / 2)
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
  /// Half the side of the target CELL, in the same units as ``cursorRadius``.
  ///
  /// The criterion is `max(|dx|, |dy|) <= targetHalfExtent`: the cursor's centre is inside the cell.
  /// The kernel draws that square, sharp-edged, with no inset and no separate tolerance shape, so
  /// the drawn edge and the scored edge are the same line and a viewer can check any selection by
  /// looking at it. Calling it a radius was the source of a real defect: a circular rule drawn as a
  /// square left 19.3% of what a viewer saw as the target outside the region being scored.
  public var targetHalfExtent: Float
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
  /// The click animation in `[0, 1]`; the kernel pinches the cursor ring as it decays.
  public var clickPulse: Float
  /// The green hit marker: where the last click landed a hit, grid-normalised. See ``hitFade``.
  public var hitX: Float
  public var hitY: Float
  /// How recently that hit happened, `1 → 0`. 0 draws no marker.
  ///
  /// The click lands at the trial boundary, so the square it hit is no longer the active target.
  /// This is what keeps it on screen, green, beside the new red target, long enough to read.
  public var hitFade: Float
  /// The BOARD: the finite region of whole cells the task actually uses, grid-normalised.
  ///
  /// The lattice is infinite and used to be drawn to the pane edge, which cut cells in half at the
  /// left, right and centre seam and left no way to tell how big the board was meant to be. This
  /// session presents 64 targets on an 8x8 lattice at a 15 mm pitch: the board is 8 cells across,
  /// centred on the targets, and everything outside it is background.
  public var boardCentreX: Float
  public var boardCentreY: Float
  /// Half the board's side, in the same units. 0 draws no board and no rules.
  public var boardHalf: Float

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
    targetHalfExtent: Float = 0.5 / 30.0,
    hasTarget: UInt32 = 0,
    gridPitchX: Float = 1.0 / 30.0,
    gridPitchY: Float = 1.0 / 30.0,
    gridPhaseX: Float = 0,
    gridPhaseY: Float = 0,
    clickPulse: Float = 0,
    hitX: Float = 0,
    hitY: Float = 0,
    hitFade: Float = 0,
    boardCentreX: Float = 0.5,
    boardCentreY: Float = 0.5,
    boardHalf: Float = 0.5
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
    self.targetHalfExtent = targetHalfExtent
    self.hasTarget = hasTarget
    self.gridPitchX = gridPitchX
    self.gridPitchY = gridPitchY
    self.gridPhaseX = gridPhaseX
    self.gridPhaseY = gridPhaseY
    self.clickPulse = clickPulse
    self.hitX = hitX
    self.hitY = hitY
    self.hitFade = hitFade
    self.boardCentreX = boardCentreX
    self.boardCentreY = boardCentreY
    self.boardHalf = boardHalf
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
    targetHalfExtent: Float = 0.5 / 30.0,
    selection: SelectionState = .idle,
    board: Board = .wholeGrid
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
      targetHalfExtent: targetHalfExtent,
      hasTarget: target == nil ? 0 : 1,
      gridPitchX: lattice.pitchX,
      gridPitchY: lattice.pitchY,
      gridPhaseX: lattice.phaseX,
      gridPhaseY: lattice.phaseY,
      clickPulse: selection.clickPulse,
      hitX: selection.hitX,
      hitY: selection.hitY,
      hitFade: selection.hitFade,
      boardCentreX: board.centreX,
      boardCentreY: board.centreY,
      boardHalf: board.half
    )
  }
}
