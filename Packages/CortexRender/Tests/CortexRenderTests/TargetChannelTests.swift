// TargetChannelTests — round-trip, sentinel-collision and clear-vs-clamp invariants for
// `TargetChannel` (see TargetChannel.swift header). A target the task never showed must never be
// drawn, so non-finite or out-of-grid input must CLEAR rather than invent a clamped position, and
// a live target parked at the origin must not read back as the empty sentinel.

import CortexRender
import Testing

/// `TargetChannel` (unlike its sibling `CursorPositionChannel`/`SelectionChannel`) is not marked
/// `nonisolated`, so under this package's `.defaultIsolation(MainActor.self)` its members are
/// MainActor-isolated. The suite is annotated to match rather than to work around it; this file
/// tests behavior only and does not touch that isolation question.
@Suite("TargetChannel")
@MainActor
struct TargetChannelTests {
  /// TargetChannel resolves to 1/65535 of the grid; this comfortably covers quantisation error.
  private let eps: Float = 1e-4

  @Test("a channel with nothing stored yields no target")
  func emptyChannelYieldsNil() {
    #expect(TargetChannel().load() == nil)
  }

  @Test("store then load round-trips within the 16-bit fixed-point resolution")
  func storeThenLoadRoundTrips() {
    let channel = TargetChannel()
    channel.store(x: 0.42, y: 0.73)
    guard let target = channel.load() else {
      Issue.record("a stored in-range target must load back, not clear")
      return
    }
    #expect(abs(target.x - 0.42) < eps)
    #expect(abs(target.y - 0.73) < eps)
  }

  @Test("storing the origin loads back as a live target, not the empty sentinel")
  func originIsALiveTargetNotTheSentinel() {
    // The empty sentinel is the all-zero word, which is also what (0, 0) would quantise to. Only
    // the validity bit tells them apart, so a target genuinely parked at the origin must not
    // vanish into "no target" -- that collision is the single most valuable case in this file.
    let channel = TargetChannel()
    channel.store(x: 0, y: 0)
    guard let target = channel.load() else {
      Issue.record("(0, 0) is a valid grid position and must not read back as no-target")
      return
    }
    #expect(target.x == 0)
    #expect(target.y == 0)
  }

  @Test("a value just inside the upper bound round-trips")
  func justInsideUpperBoundRoundTrips() {
    let channel = TargetChannel()
    channel.store(x: 0.999, y: 0.999)
    guard let target = channel.load() else {
      Issue.record("0.999 is inside [0, 1) and must load back, not clear")
      return
    }
    #expect(abs(target.x - 0.999) < eps)
    #expect(abs(target.y - 0.999) < eps)
  }

  @Test("x or y exactly at the upper bound clears rather than clamping to the edge")
  func exactlyAtUpperBoundClears() {
    let onX = TargetChannel()
    onX.store(x: 1.0, y: 0.5)
    #expect(onX.load() == nil)

    let onY = TargetChannel()
    onY.store(x: 0.5, y: 1.0)
    #expect(onY.load() == nil)
  }

  @Test("negative x or y clears rather than clamping to the edge")
  func negativeInputClears() {
    let onX = TargetChannel()
    onX.store(x: -0.1, y: 0.5)
    #expect(onX.load() == nil)

    let onY = TargetChannel()
    onY.store(x: 0.5, y: -0.1)
    #expect(onY.load() == nil)
  }

  @Test("out-of-grid input does not produce a clamped edge value")
  func outOfGridDoesNotClamp() {
    // The header is explicit: clamping would invent a location the task never showed. A
    // regression to clamp-to-edge would make this pass with x == 1.0 instead of nil, so assert
    // nil directly rather than a tolerance that a clamped edge value could also satisfy.
    let farHigh = TargetChannel()
    farHigh.store(x: 5.0, y: 0.5)
    #expect(farHigh.load() == nil)

    let farLow = TargetChannel()
    farLow.store(x: -5.0, y: 0.5)
    #expect(farLow.load() == nil)
  }

  @Test("NaN input clears rather than publishing")
  func nanInputClears() {
    let onX = TargetChannel()
    onX.store(x: .nan, y: 0.5)
    #expect(onX.load() == nil)

    let onY = TargetChannel()
    onY.store(x: 0.5, y: .nan)
    #expect(onY.load() == nil)
  }

  @Test("infinite input clears rather than publishing")
  func infiniteInputClears() {
    let onX = TargetChannel()
    onX.store(x: Float.infinity, y: 0.5)
    #expect(onX.load() == nil)

    let onY = TargetChannel()
    onY.store(x: 0.5, y: -Float.infinity)
    #expect(onY.load() == nil)
  }

  @Test("clear after a store returns nil")
  func clearAfterStoreReturnsNil() {
    let channel = TargetChannel()
    channel.store(x: 0.3, y: 0.6)
    #expect(channel.load() != nil)
    channel.clear()
    #expect(channel.load() == nil)
  }

  @Test("round-trip is accurate to within a small fraction of one quantisation step")
  func roundTripIsAccurateWellBelowOneQuantisationStep() {
    // x sits 0.9 of a quantisation step past 32768/65535 -- comfortably past the round-to-nearest
    // boundary (0.5) and past Float32's own rounding noise at this magnitude, so a
    // truncate-instead-of-round regression moves the decoded value by nearly a full step
    // (~1/65535) while round-to-nearest lands within a tenth of that. The shared `eps` above is
    // deliberately loose enough to tolerate either; this bound is tight enough to tell them apart.
    let x = Float(32768.9) / 65535
    let tight: Float = 5e-6
    let channel = TargetChannel()
    channel.store(x: x, y: x)
    guard let target = channel.load() else {
      Issue.record("an in-range target must load back")
      return
    }
    #expect(abs(target.x - x) < tight)
    #expect(abs(target.y - x) < tight)
  }

  @Test("an out-of-range store clears a previously published target, not merely skips publishing")
  func outOfRangeStoreClearsAnExistingTarget() {
    // Every clear-on-invalid test above starts from an already-empty channel, so none of them can
    // tell "actively cleared" apart from "never published in the first place". Store a valid
    // target first so the distinction is observable.
    let channel = TargetChannel()
    channel.store(x: 0.5, y: 0.5)
    #expect(channel.load() != nil)
    channel.store(x: 1.5, y: 0.5)
    #expect(channel.load() == nil)
  }
}
