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
  public var proximityRadius: Float
  /// Drawable width in pixels (for square-cell aspect mapping).
  public var viewportWidth: UInt32
  /// Drawable height in pixels (for square-cell aspect mapping).
  public var viewportHeight: UInt32
  /// Inner-dot radius of the ring cursor, normalised to the grid's shorter extent.
  public var cursorDotRadius: Float
  /// Ring stroke width of the ring cursor, normalised to the grid's shorter extent.
  public var cursorRingWidth: Float
  /// Active target column, or ``WebgridParams/noTarget`` when no target is active.
  public var targetColumn: UInt32
  /// Active target row, or ``WebgridParams/noTarget`` when no target is active.
  public var targetRow: UInt32

  /// Sentinel meaning "no active target", so the kernel draws no selection square.
  ///
  /// A sentinel rather than a separate bool keeps every field a 4-byte scalar, which is what makes
  /// the Swift/MSL byte mirror trivial.
  public static let noTarget: UInt32 = .max

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
    targetColumn: UInt32 = WebgridParams.noTarget,
    targetRow: UInt32 = WebgridParams.noTarget
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
    self.targetColumn = targetColumn
    self.targetRow = targetRow
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
    targetColumn: UInt32 = WebgridParams.noTarget,
    targetRow: UInt32 = WebgridParams.noTarget
  ) -> WebgridParams {
    WebgridParams(
      gridColumns: 30,
      gridRows: 30,
      cellGap: 0.08,
      cornerRadius: 0.25,
      cursorX: cursorX,
      cursorY: cursorY,
      cursorRadius: 0.020,
      proximityRadius: 0.12,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      cursorDotRadius: 0.006,
      cursorRingWidth: 0.0035,
      targetColumn: targetColumn,
      targetRow: targetRow
    )
  }
}
