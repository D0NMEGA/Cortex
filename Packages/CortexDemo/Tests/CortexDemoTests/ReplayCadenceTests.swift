// ReplayCadenceTests - the replay stride and the streaming dwell readout.
//
// The defect under test: `RecordedSpikeSource`'s default stride is its window length, so consecutive
// window indices are NON-OVERLAPPING. A throughput bench wants that. A replay loop does not: the GUI
// advanced one 32-bin window per 20 ms tick, which ran the session clock 32x faster than wall clock
// while the integrator still moved the cursor by `velocity * 0.020`. On screen that is a cursor
// creeping around its start point beside a task target changing every couple of frames.
// `CortexReplayBench` decodes one window per BIN and was never affected, so no published number
// moved; these cases pin the stride that lets the GUI match the bench.
import CortexCore
@testable import CortexDemo
import CortexRender
import Foundation
import simd
import Testing

@Suite("Replay cadence: window stride and the streaming click readout")
@MainActor
struct ReplayCadenceTests {
  static func loadFixture() throws -> ReplayExport {
    try ReplayExport(sidecarURL: RecordedSpikeSourceTests.fixtureSidecar)
  }

  // MARK: The stride

  @Test("stride 1 advances the trailing window one bin per index")
  func strideOneAdvancesOneBin() throws {
    let source = try RecordedSpikeSource(export: Self.loadFixture(), stride: 1)

    #expect(source.stride == 1)
    #expect(source.numBins == 32, "the window length is unchanged; only the step between windows is")
    // The first whole window ends at bin 31, and each index after it advances exactly one bin.
    #expect(source.lastBin(forWindow: 0) == 31)
    #expect(source.lastBin(forWindow: 1) == 32)
    #expect(source.lastBin(forWindow: 7) == 38)
    // 256 fixture bins: bins 31...255 can each end a whole window.
    #expect(source.windowCount == 225, "256 - 32 + 1 trailing windows")
  }

  @Test("the default stride is unchanged: non-overlapping windows")
  func defaultStrideIsNonOverlapping() throws {
    let export = try Self.loadFixture()
    let source = RecordedSpikeSource(export: export)
    let explicit = RecordedSpikeSource(export: export, stride: RecordedSpikeSource.modelSeqLen)

    #expect(source.stride == 32, "omitting the stride still means one whole window per index")
    #expect(source.windowCount == 8)
    for index in 0 ..< source.windowCount {
      #expect(source.lastBin(forWindow: index) == (index + 1) * 32 - 1)
      #expect(source.lastBin(forWindow: index) == explicit.lastBin(forWindow: index))
    }
  }

  @Test("a strided window still holds the bins ending at its last bin")
  func stridedWindowContentsFollowLastBin() throws {
    let export = try Self.loadFixture()
    let strided = RecordedSpikeSource(export: export, stride: 1)
    let whole = RecordedSpikeSource(export: export)

    // Window 1 under the default stride ends at bin 63; under stride 1 that is index 32. The two
    // sources must return the SAME bins for the same last bin, or the stride changed the data and
    // not just the cadence.
    #expect(strided.lastBin(forWindow: 32) == whole.lastBin(forWindow: 1))
    #expect(strided.window(32) == whole.window(1))
    #expect(strided.target(forWindow: 32) == whole.target(forWindow: 1))
    #expect(strided.trueVelocity(forWindow: 32) == whole.trueVelocity(forWindow: 1))
  }

  @Test("past the end still clamps to the last whole window")
  func strideOneClampsPastTheEnd() throws {
    let source = try RecordedSpikeSource(export: Self.loadFixture(), stride: 1)
    let last = source.window(source.windowCount - 1)

    #expect(source.lastBin(forWindow: source.windowCount - 1) == 255, "the fixture's final bin")
    #expect(source.window(source.windowCount) == last)
    #expect(source.window(Int.max / 2) == last)
  }

  // MARK: The dwell readout

  @Test("the selection channel clamps every field and resolves non-finite input to idle")
  func selectionChannelClampsAndRoundTrips() {
    let channel = SelectionChannel()
    #expect(channel.load() == .idle, "a fresh channel reads as no click and no hit marker")

    // Every field crosses as 16-bit fixed point, so values come back within 1/65535 rather than
    // bit-exact. That is finer than a pixel at any plausible window size; the four values sharing
    // ONE atomic word is what matters, so a frame can never draw a marker at a stale position
    // beside a fresh fade.
    channel.store(clickPulse: 0.5, hitX: 0.25, hitY: 0.75, hitFade: 0.5)
    let mid = channel.load()
    #expect(abs(mid.clickPulse - 0.5) < 1e-4)
    #expect(abs(mid.hitX - 0.25) < 1e-4)
    #expect(abs(mid.hitY - 0.75) < 1e-4)
    #expect(abs(mid.hitFade - 0.5) < 1e-4)

    // 0 and 1 are the values the shader branches on, and both must survive exactly.
    channel.store(clickPulse: 0, hitX: 1, hitY: 0, hitFade: 1)
    #expect(channel.load() == SelectionState(clickPulse: 0, hitX: 1, hitY: 0, hitFade: 1))

    // Out of range clamps; non-finite resolves to 0, NOT to 1. A garbage value must draw a resting
    // cursor and NO green marker rather than a hit, since a green square is read as evidence that
    // a click landed on target.
    channel.store(clickPulse: 2.0, hitX: -1, hitY: 0.5, hitFade: -1.0)
    let clamped = channel.load()
    #expect(clamped.clickPulse == 1)
    #expect(clamped.hitX == 0)
    #expect(clamped.hitFade == 0)
    // Non-finite resolves to 0 rather than clamping into range, INFINITY INCLUDED. Clamping it to
    // the top would paint a full-strength green square from a garbage value, and a green square is
    // read as evidence that a click landed on target.
    channel.store(clickPulse: .nan, hitX: .nan, hitY: .nan, hitFade: .infinity)
    #expect(channel.load() == .idle)
  }

  @Test("a click with the cursor off the target counts nothing and marks nothing")
  func clickOffTargetCountsNothing() throws {
    let source = try RecordedSpikeSource(export: Self.loadFixture(), stride: 1)
    let pipeline = ReplayPipeline(source: source, seed: 0xC0FFEE)

    // The synthetic decode fallback runs (no model in a clean clone), so this asserts the READOUT's
    // resting state, not a decoding result.
    for _ in 0 ..< 50 {
      pipeline.tick()
    }
    pipeline.setTarget(SIMD2<Float>(0.02, 0.98)) // a corner the cursor is nowhere near
    #expect(!pipeline.registerClick(), "a click off the cell is a miss")
    #expect(pipeline.selectionCount == 0)
    #expect(pipeline.selectionSwell == 0, "a miss leaves no green marker")
    #expect(pipeline.clickPulse == 1, "the cursor still shows that a click happened")
    #expect(pipeline.lastMiss != nil, "a miss is measured, not discarded")
  }
}

@Suite("The trial: one click, no repositioning")
@MainActor
struct TrialTests {
  static func loadFixture() throws -> ReplayExport {
    try ReplayExport(sidecarURL: RecordedSpikeSourceTests.fixtureSidecar)
  }

  private func freshPipeline() throws -> ReplayPipeline {
    try ReplayPipeline(source: RecordedSpikeSource(export: Self.loadFixture(), stride: 1), seed: 0xC0FFEE)
  }

  @Test("a new trial does not move the cursor")
  func trialBoundaryLeavesTheCursorAlone() throws {
    let pipeline = try freshPipeline()
    for _ in 0 ..< 20 {
      pipeline.tick()
    }
    // The whole claim of an open-loop replay is that nothing repositions the cursor. A trial
    // boundary is the one place a correction would be easy to slip in, so assert it does not.
    let before = pipeline.cursorPosition
    pipeline.registerClick()
    pipeline.beginTrial()
    #expect(pipeline.cursorPosition == before, "a trial boundary must not move the cursor")
  }

  @Test("a trial can be clicked once, and the next trial re-arms it")
  func oneClickPerTrial() throws {
    let pipeline = try freshPipeline()
    pipeline.tick()
    pipeline.setTarget(pipeline.cursorPosition) // put the target under the cursor
    #expect(pipeline.registerClick(), "a click with the cursor in the cell is a hit")
    #expect(pipeline.selectionCount == 1)
    #expect(!pipeline.registerClick(), "the same trial cannot be clicked twice")
    #expect(pipeline.selectionCount == 1)
    pipeline.beginTrial()
    pipeline.setTarget(pipeline.cursorPosition)
    #expect(pipeline.registerClick(), "the next trial can be clicked")
    #expect(pipeline.selectionCount == 2)
  }

  @Test("the green marker survives the trial boundary that produced it")
  func markerOutlivesItsTrial() throws {
    let pipeline = try freshPipeline()
    pipeline.tick()
    pipeline.setTarget(pipeline.cursorPosition)
    pipeline.registerClick()
    #expect(pipeline.selectionSwell == 1)
    // The click lands AT the boundary, so clearing the marker when the next trial opens would erase
    // it on the frame it appeared.
    pipeline.beginTrial()
    #expect(pipeline.selectionSwell == 1, "the marker fades on its own, not on the boundary")
  }

  @Test("the miss distance is recorded for every click, hit or miss")
  func missIsAlwaysMeasured() throws {
    let pipeline = try freshPipeline()
    pipeline.tick()
    pipeline.setTarget(SIMD2<Float>(0.02, 0.98))
    #expect(!pipeline.registerClick())
    let far = try #require(pipeline.lastMiss)
    pipeline.beginTrial()
    pipeline.setTarget(pipeline.cursorPosition)
    #expect(pipeline.registerClick())
    let near = try #require(pipeline.lastMiss)
    #expect(near < far, "a hit's miss distance is smaller than a miss's")
    #expect(pipeline.medianMiss != nil, "the median is available once clicks have happened")
  }
}

@Suite("The click: the cell, the pulse and the marker")
@MainActor
struct SelectionCommitTests {
  private func freshPipeline() throws -> ReplayPipeline {
    let source = try RecordedSpikeSource(export: ReplayCadenceTests.loadFixture(), stride: 1)
    return ReplayPipeline(source: source, seed: 0xC0FFEE)
  }

  @Test("the click pinch decays to zero and does not re-arm on its own")
  func clickPulseDecays() throws {
    let pipeline = try freshPipeline()
    pipeline.tick()
    pipeline.setTarget(pipeline.cursorPosition)
    pipeline.registerClick()
    #expect(pipeline.clickPulse == 1)
    var previous = pipeline.clickPulse
    for _ in 0 ..< 10 {
      pipeline.tick()
      #expect(pipeline.clickPulse <= previous, "the pinch must not grow: \(pipeline.clickPulse)")
      previous = pipeline.clickPulse
    }
    #expect(pipeline.clickPulse == 0, "200 ms is 10 ticks, so the pinch is fully released")
  }

  @Test("the green marker fades to zero on its own")
  func markerFades() throws {
    let pipeline = try freshPipeline()
    pipeline.tick()
    pipeline.setTarget(pipeline.cursorPosition)
    pipeline.registerClick()
    #expect(pipeline.selectionSwell == 1)
    for _ in 0 ..< 25 {
      pipeline.tick()
    }
    #expect(pipeline.selectionSwell == 0, "500 ms is 25 ticks, so the marker is gone")
    #expect(pipeline.selectionCount == 1, "and nothing re-counted while it faded")
  }

  @Test("the cell is the target: a cursor in a corner of the square counts")
  func cornerOfTheCellCounts() throws {
    let pipeline = try freshPipeline()
    // 99% of the way to a corner of the cell. Its distance from the centre is 1.4x the half-side,
    // so the old radial rule scored this as a miss while the viewer saw the dot inside the square.
    let half = pipeline.scoringHalfExtent
    let target = pipeline.target
    let corner = target + SIMD2<Float>(half * 0.99, half * 0.99)
    #expect(pipeline.isOnTarget(corner), "a point inside the drawn square must count")
    #expect(simd_distance(corner, target) > half, "and it is outside the radius that used to score")
    // Just outside the cell on one axis is a miss, so the square's edge really is the rule.
    #expect(!pipeline.isOnTarget(target + SIMD2<Float>(half * 1.01, 0)))
  }

  @Test("a target that is not on screen is not scored")
  func hiddenTargetIsNotScored() throws {
    let pipeline = try freshPipeline()
    pipeline.tick()
    // The task can put a target outside the pre-registered workspace box, and the GUI draws nothing
    // for it. A click must not land on a square the viewer cannot see, wherever the cursor is.
    pipeline.setTarget(pipeline.cursorPosition)
    let target = pipeline.target
    pipeline.clearTarget()
    #expect(!pipeline.isOnTarget(pipeline.cursorPosition), "an unseen target cannot be on target")
    #expect(!pipeline.registerClick(), "and it cannot be clicked")
    #expect(pipeline.selectionCount == 0)
    #expect(pipeline.target == target, "the steering target is left alone; only scoring stops")
  }
}
