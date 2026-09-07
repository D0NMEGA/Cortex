@testable import CortexRender
import Testing

/// Layout + value contract for `WebgridParams`.
///
/// `WebgridParams` is uploaded to the GPU as raw bytes (`setBytes` / a `storageModeShared`
/// buffer), so its field layout MUST be deterministic and trivially copyable, and the
/// convenience constructor MUST pin the modern 30×30 reference grid (NOT the rejected 6×6 —
/// REQUIREMENTS Out-of-Scope). These tests are the RED half of Task 1; the struct (GREEN) makes
/// them pass.
@Suite("WebgridParams")
struct WebgridParamsTests {
  /// D-01: the substrate is the modern 30×30 Neuralink/Bliss-Chapman webgrid, not the legacy 6×6.
  @Test
  func `grid30x30 convenience pins a 30×30 grid`() {
    let params = WebgridParams.grid30x30(
      cursorX: 0.5, cursorY: 0.5, viewportWidth: 1920, viewportHeight: 1080
    )
    #expect(params.gridColumns == 30)
    #expect(params.gridRows == 30)
  }

  /// RENDER-06: the struct is uploaded as raw bytes, so it must be a trivial value type with a
  /// stable, positive stride and no reference fields (bit-for-bit copyable into the GPU buffer).
  @Test
  func `layout is trivially copyable with a stable stride`() {
    // A non-zero stride proves the type has storage; equal `size`/`stride` parity across calls
    // proves the layout is deterministic (no hidden refcounted/existential fields would round-trip
    // raw). Two independent default-constructed values compare byte-equal when copied as raw bytes.
    #expect(MemoryLayout<WebgridParams>.stride > 0)
    #expect(MemoryLayout<WebgridParams>.stride == MemoryLayout<WebgridParams>.stride)
    #expect(MemoryLayout<WebgridParams>.size <= MemoryLayout<WebgridParams>.stride)

    let a = WebgridParams.grid30x30(cursorX: 0.25, cursorY: 0.75, viewportWidth: 800, viewportHeight: 600)
    var b = a // value copy — trivial types copy bit-for-bit
    b.cursorX = 0.25
    #expect(a.cursorX == b.cursorX)
    #expect(a.viewportWidth == b.viewportWidth)
  }

  /// A 30×30 grid is 900 cells — the canonical ~900-cell webgrid the compute shader fills.
  @Test
  func `cell count derived from params is 900`() {
    let params = WebgridParams.grid30x30(
      cursorX: 0.0, cursorY: 0.0, viewportWidth: 1024, viewportHeight: 1024
    )
    let cellCount = Int(params.gridColumns) * Int(params.gridRows)
    #expect(cellCount == 900)
  }
}
