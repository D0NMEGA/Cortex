// SelectionChannelTests — round-trip, clamp-vs-clear asymmetry and bit-range isolation
// invariants for `SelectionChannel` (see SelectionChannel.swift header). Unlike `TargetChannel`,
// out-of-range input here CLAMPS into [0, 1] rather than clearing, because a bad producer value
// must never reach the shader as a NaN radius or a NaN colour blend. A future refactor that
// "unifies" the two channels would break one or the other; nothing else in this file's scope
// would catch that, so the asymmetry is asserted deliberately.

import CortexRender
import Testing

@Suite("SelectionChannel")
struct SelectionChannelTests {
  /// SelectionChannel resolves to 1/65535 per field; this comfortably covers quantisation error.
  private let eps: Float = 1e-4

  @Test("a freshly constructed channel loads the idle state, with no marker to draw")
  func freshChannelLoadsIdleState() {
    let state = SelectionChannel().load()
    #expect(state == SelectionState.idle)
    #expect(state.hitFade == 0)
  }

  @Test("store then load round-trips all four fields within the 16-bit fixed-point resolution")
  func storeThenLoadRoundTripsAllFourFields() {
    let channel = SelectionChannel()
    channel.store(clickPulse: 0.12, hitX: 0.34, hitY: 0.56, hitFade: 0.78)
    let state = channel.load()
    #expect(abs(state.clickPulse - 0.12) < eps)
    #expect(abs(state.hitX - 0.34) < eps)
    #expect(abs(state.hitY - 0.56) < eps)
    #expect(abs(state.hitFade - 0.78) < eps)
  }

  @Test("each field occupies its own bit range and does not bleed into its neighbors")
  func fieldsDoNotBleedAcrossBitRanges() {
    // One field live at a time, the other three held at exactly 0: a shift-amount mistake in the
    // packing would leak the live value into a neighboring field, which a single round-trip with
    // four simultaneously distinct values would not reliably expose.
    let clickPulseOnly = SelectionChannel()
    clickPulseOnly.store(clickPulse: 1.0, hitX: 0, hitY: 0, hitFade: 0)
    let a = clickPulseOnly.load()
    #expect(abs(a.clickPulse - 1.0) < eps)
    #expect(a.hitX == 0)
    #expect(a.hitY == 0)
    #expect(a.hitFade == 0)

    let hitXOnly = SelectionChannel()
    hitXOnly.store(clickPulse: 0, hitX: 1.0, hitY: 0, hitFade: 0)
    let b = hitXOnly.load()
    #expect(b.clickPulse == 0)
    #expect(abs(b.hitX - 1.0) < eps)
    #expect(b.hitY == 0)
    #expect(b.hitFade == 0)

    let hitYOnly = SelectionChannel()
    hitYOnly.store(clickPulse: 0, hitX: 0, hitY: 1.0, hitFade: 0)
    let c = hitYOnly.load()
    #expect(c.clickPulse == 0)
    #expect(c.hitX == 0)
    #expect(abs(c.hitY - 1.0) < eps)
    #expect(c.hitFade == 0)

    let hitFadeOnly = SelectionChannel()
    hitFadeOnly.store(clickPulse: 0, hitX: 0, hitY: 0, hitFade: 1.0)
    let d = hitFadeOnly.load()
    #expect(d.clickPulse == 0)
    #expect(d.hitX == 0)
    #expect(d.hitY == 0)
    #expect(abs(d.hitFade - 1.0) < eps)
  }

  @Test("non-finite input maps to zero, per field, independently")
  func nonFiniteInputMapsToZeroPerField() {
    let channel = SelectionChannel()
    channel.store(clickPulse: .nan, hitX: Float.infinity, hitY: -Float.infinity, hitFade: 0.5)
    let state = channel.load()
    #expect(state.clickPulse == 0)
    #expect(state.hitX == 0)
    #expect(state.hitY == 0)
    #expect(abs(state.hitFade - 0.5) < eps)
  }

  @Test("out-of-range input clamps into [0, 1] rather than clearing — opposite of TargetChannel")
  func outOfRangeInputClampsInBothDirections() {
    let channel = SelectionChannel()
    channel.store(clickPulse: 2.0, hitX: -1.0, hitY: 2.0, hitFade: -1.0)
    let state = channel.load()
    #expect(state.clickPulse == 1.0) // 2.0 clamps to the upper bound
    #expect(state.hitX == 0.0) // -1.0 clamps to the lower bound
    #expect(state.hitY == 1.0) // 2.0 clamps to the upper bound
    #expect(state.hitFade == 0.0) // -1.0 clamps to the lower bound
  }
}
