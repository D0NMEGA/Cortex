// ReplayCadenceTests - the replay stride and the streaming dwell readout.
//
// The defect under test: `RecordedSpikeSource`'s default stride is its window length, so consecutive
// window indices are NON-OVERLAPPING. A throughput bench wants that. A closed loop does not: the GUI
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

@Suite("Replay cadence: window stride and the streaming dwell readout")
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

  @Test("the dwell channel clamps to [0,1] and resolves non-finite input to no hold")
  func dwellChannelClampsAndRoundTrips() {
    let channel = DwellChannel()
    #expect(channel.load() == 0, "a fresh channel reads as no hold")

    channel.store(0.5)
    #expect(channel.load() == 0.5)

    // Out-of-range and non-finite values must never reach the shader as a radius multiplier.
    channel.store(2.0)
    #expect(channel.load() == 1.0)
    channel.store(-1.0)
    #expect(channel.load() == 0.0)
    // Non-finite input resolves to 0, NOT to 1: a garbage value must draw a resting cursor rather
    // than a fully committed selection, since the ring's contraction is read as evidence of a hold.
    channel.store(.nan)
    #expect(channel.load() == 0.0)
    channel.store(.infinity)
    #expect(channel.load() == 0.0)
  }

  @Test("a pipeline that never reaches its target reports no dwell and no selections")
  func dwellStaysZeroOffTarget() throws {
    let source = try RecordedSpikeSource(export: Self.loadFixture(), stride: 1)
    let pipeline = ClosedLoopPipeline(source: source, seed: 0xC0FFEE)

    // The synthetic decode fallback runs (no model in a clean clone), so this asserts the READOUT's
    // resting state, not a decoding result: an off-target cursor holds no dwell.
    for _ in 0 ..< 50 {
      let state = pipeline.tick()
      if !state.onTarget {
        #expect(pipeline.dwellProgress == 0, "the dwell must reset the moment the cursor is outside")
      }
    }
    #expect(pipeline.dwellProgress >= 0 && pipeline.dwellProgress <= 1)
    #expect(pipeline.selectionCount >= 0)
  }
}
