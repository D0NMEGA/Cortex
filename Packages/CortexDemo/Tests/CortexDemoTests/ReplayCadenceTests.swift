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

  @Test("the selection channel clamps every field and resolves non-finite input to idle")
  func selectionChannelClampsAndRoundTrips() {
    let channel = SelectionChannel()
    #expect(channel.load() == .idle, "a fresh channel reads as no hold and nothing acquired")

    // The fractions cross as 16-bit fixed point, so they come back within 1/65535 rather than
    // bit-exact. That is finer than the ring radius or the colour blend they drive can resolve; the
    // three values sharing ONE atomic word is what matters, so a frame can never draw a green
    // target beside a stale dwell.
    channel.store(dwell: 0.5, acquired: true, swell: 0.25)
    let mid = channel.load()
    #expect(abs(mid.dwell - 0.5) < 1e-4)
    #expect(abs(mid.swell - 0.25) < 1e-4)
    #expect(mid.acquired)

    // 0 and 1 are the values the shader branches on, and both must survive exactly.
    channel.store(dwell: 0, acquired: false, swell: 1)
    #expect(channel.load() == SelectionState(dwell: 0, acquired: false, swell: 1))

    // Out of range clamps; non-finite resolves to 0, NOT to 1. A garbage value must draw a resting
    // cursor and an unacquired target rather than a completed selection, since both are read as
    // evidence that an acquisition happened.
    channel.store(dwell: 2.0, acquired: false, swell: -1.0)
    #expect(channel.load() == SelectionState(dwell: 1, acquired: false, swell: 0))
    channel.store(dwell: .nan, acquired: false, swell: .infinity)
    #expect(channel.load() == .idle)
  }

  @Test("a pipeline that never reaches its target reports no dwell and no selections")
  func dwellStaysZeroOffTarget() throws {
    let source = try RecordedSpikeSource(export: Self.loadFixture(), stride: 1)
    let pipeline = ReplayPipeline(source: source, seed: 0xC0FFEE)

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

@Suite("Trial re-anchoring")
@MainActor
struct ReanchorTests {
  static func loadFixture() throws -> ReplayExport {
    try ReplayExport(sidecarURL: RecordedSpikeSourceTests.fixtureSidecar)
  }

  @Test("reanchor moves the cursor and the filter agrees with the integrator")
  func reanchorMovesTheCursor() throws {
    let pipeline = try ReplayPipeline(
      source: RecordedSpikeSource(export: Self.loadFixture(), stride: 1),
      seed: 0xC0FFEE
    )
    for _ in 0 ..< 20 {
      pipeline.tick()
    }

    pipeline.reanchor(to: SIMD2<Float>(0.25, 0.75))
    // The next tick integrates FROM the re-anchored position, so it lands within one tick's travel
    // of it rather than back where the free-running cursor had drifted to.
    let after = pipeline.tick()
    #expect(abs(after.position.x - 0.25) < 0.2)
    #expect(abs(after.position.y - 0.75) < 0.2)
  }

  @Test("reanchor clamps to the grid and refuses a non-finite position")
  func reanchorClampsAndRefuses() throws {
    let pipeline = try ReplayPipeline(
      source: RecordedSpikeSource(export: Self.loadFixture(), stride: 1),
      seed: 0xC0FFEE
    )
    pipeline.reanchor(to: SIMD2<Float>(5.0, -3.0))
    var state = pipeline.tick()
    #expect(state.position.x >= 0 && state.position.x <= 1)
    #expect(state.position.y >= 0 && state.position.y <= 1)

    // A non-finite anchor must be REFUSED outright, not clamped to a bound: clamping would silently
    // park the cursor in a corner and call it a re-anchor.
    pipeline.reanchor(to: SIMD2<Float>(0.4, 0.6))
    pipeline.reanchor(to: SIMD2<Float>(.nan, 0.6))
    state = pipeline.tick()
    #expect(state.position.x.isFinite && state.position.y.isFinite)
    #expect(abs(state.position.x - 0.4) < 0.2, "the NaN anchor left the 0.4 anchor in place")
  }

  @Test("reanchor clears any dwell in progress")
  func reanchorClearsDwell() throws {
    let pipeline = try ReplayPipeline(
      source: RecordedSpikeSource(export: Self.loadFixture(), stride: 1),
      seed: 0xC0FFEE
    )
    for _ in 0 ..< 10 {
      pipeline.tick()
    }
    // A hold cannot survive being teleported: the dwell must be CONTINUOUS on one target.
    pipeline.reanchor(to: SIMD2<Float>(0.5, 0.5))
    #expect(pipeline.dwellProgress == 0)
  }
}

@Suite("Selection commit: one per trial, the counter and the latch")
@MainActor
struct SelectionCommitTests {
  private func freshPipeline() throws -> ReplayPipeline {
    let source = try RecordedSpikeSource(export: ReplayCadenceTests.loadFixture(), stride: 1)
    return ReplayPipeline(source: source, seed: 0xC0FFEE)
  }

  /// Run `ticks` ticks with the target re-pointed at the cursor each time, so the continuous-hold
  /// condition holds throughout. This exercises the READOUT, not a decoding result: it asserts that
  /// a satisfied dwell moves the tally a viewer reads off the screen.
  @discardableResult
  private func holdOnTarget(_ pipeline: ReplayPipeline, ticks: Int) -> SIMD2<Float> {
    var position = pipeline.tick().position
    for _ in 0 ..< ticks {
      pipeline.setTarget(position)
      position = pipeline.tick().position
    }
    return position
  }

  @Test("a dwell short of the threshold does not commit")
  func shortHoldDoesNotCommit() throws {
    let pipeline = try freshPipeline()
    // 0.30 s at 20 ms is 15 ticks; 14 is one short, and the threshold must be a threshold.
    holdOnTarget(pipeline, ticks: 14)
    #expect(pipeline.selectionCount == 0)
    #expect(!pipeline.acquired)
    #expect(pipeline.selectionSwell == 0)
    #expect(pipeline.dwellProgress > 0, "a partial hold shows partial progress")
  }

  @Test("a satisfied dwell commits once, latches acquired and lights the swell")
  func dwellCommitsOnce() throws {
    let pipeline = try freshPipeline()
    holdOnTarget(pipeline, ticks: 15)
    #expect(pipeline.selectionCount == 1, "15 continuous on-target ticks is exactly one commit")
    #expect(pipeline.acquired, "the commit latches the target green for the rest of the trial")
    #expect(pipeline.selectionSwell == 1, "a commit lights the swell fully")
    #expect(pipeline.dwellProgress == 0, "the counter restarts after committing")
  }

  @Test("one acquisition per trial: parking on the target never banks a second")
  func oneAcquisitionPerTrial() throws {
    let pipeline = try freshPipeline()
    // Six times the 15-tick requirement, parked on the same target the whole time. This used to
    // bank a fresh selection every 15 ticks, so a single 1.3 s trial could contribute four counts
    // for one square and the tally's numerator could pass its denominator.
    holdOnTarget(pipeline, ticks: 90)
    #expect(pipeline.selectionCount == 1, "a square cannot be selected twice in one trial")
    #expect(pipeline.acquired)
    #expect(pipeline.dwellProgress == 0, "no partial hold accumulates after the trial is acquired")
  }

  @Test("the next trial re-arms the dwell, so a second trial can be acquired")
  func nextTrialReArms() throws {
    let pipeline = try freshPipeline()
    holdOnTarget(pipeline, ticks: 15)
    #expect(pipeline.selectionCount == 1)
    pipeline.beginTrial()
    #expect(!pipeline.acquired, "a new trial releases the latch")
    holdOnTarget(pipeline, ticks: 15)
    #expect(pipeline.selectionCount == 2, "the second trial commits on its own 15-tick hold")
  }

  @Test("the swell decays to zero while the acquired latch holds")
  func swellDecaysButGreenHolds() throws {
    let pipeline = try freshPipeline()
    holdOnTarget(pipeline, ticks: 15)
    #expect(pipeline.selectionSwell == 1)

    // Break the hold and watch the swell fall. The latch must NOT fall with it: the square stays
    // green until the next trial, which is the only unambiguous "that one counted" on screen.
    let committed = pipeline.selectionCount
    pipeline.setTarget(SIMD2<Float>(0.99, 0.01))
    var previous = pipeline.selectionSwell
    for _ in 0 ..< 10 {
      pipeline.tick()
      #expect(pipeline.selectionSwell < previous, "swell did not fall: \(pipeline.selectionSwell)")
      previous = pipeline.selectionSwell
    }
    #expect(pipeline.selectionCount == committed, "no second commit inside the trial")
    #expect(pipeline.acquired, "the target stays green for the rest of the trial")
    #expect(previous < 1, "the swell is still at full size")
  }

  @Test("a re-anchor releases the latch so green cannot bleed into the next trial")
  func reanchorClearsAcquired() throws {
    let pipeline = try freshPipeline()
    holdOnTarget(pipeline, ticks: 15)
    #expect(pipeline.acquired)
    pipeline.reanchor(to: SIMD2<Float>(0.5, 0.5))
    #expect(!pipeline.acquired)
    #expect(pipeline.selectionSwell == 0)
    #expect(pipeline.dwellProgress == 0)
  }

  @Test("a target that is not on screen is not scored")
  func hiddenTargetIsNotScored() throws {
    let pipeline = try freshPipeline()
    holdOnTarget(pipeline, ticks: 14)
    #expect(pipeline.dwellProgress > 0)
    // The task can put a target outside the pre-registered workspace box, and the GUI draws nothing
    // for it. A hold must not keep banking against a square the viewer cannot see.
    pipeline.clearTarget()
    #expect(pipeline.dwellProgress == 0, "clearing the target drops the partial hold")
    let target = pipeline.target
    for _ in 0 ..< 60 {
      pipeline.tick()
    }
    #expect(pipeline.selectionCount == 0, "no acquisition while no target is on screen")
    #expect(pipeline.target == target, "the steering target is left alone; only scoring stops")
  }
}
