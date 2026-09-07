// RecordedSpikeSourceTests - Phase 10 (RD-08, Plan 10-04): the injected spike-window seam and the
// end of the silent synthetic fallback.
//
// RESEARCH Pattern 2 is the defect under test. `ReplayPipeline` sizes its `SpikeInputBuffer` from
// the spike source's `numBins`; `SyntheticSpikeSource`'s default is 8 while the shipped real model's
// `spikes` input is `(1, 96, 1, 32)`. `decodeWithModel` used to swallow the resulting error into the
// synthetic fallback, producing a running loop whose numbers were synthetic under a real-data label.
// These cases pin the three things that make that impossible to repeat:
//
//   1. `RecordedSpikeSource` reports the model's 32-bin window length, not the synthetic default.
//   2. The pipeline COUNTS model-backed ticks, so a fallback run is visible rather than assumed.
//   3. A decode that cannot be wired RECORDS why, naming both shapes, instead of discarding the reason.
//
// Everything here runs against the committed 256-bin Python-written fixture, so the suite is green on
// a clean clone with no dataset, no `Decoder/exports/` and no model.
import CortexCore
@testable import CortexDemo
import Foundation
import simd
import Testing

@Suite("RD-08 / Pattern 2: the SpikeWindowSource seam and the model-in-loop counters")
@MainActor
struct RecordedSpikeSourceTests {
  static let testSeed: UInt64 = 0xC0FFEE

  /// The committed synthetic fixture, resolved from this file's own path:
  /// `<repo>/Packages/CortexDemo/Tests/CortexDemoTests/RecordedSpikeSourceTests.swift`.
  static var fixtureSidecar: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // CortexDemoTests
      .deletingLastPathComponent() // Tests
      .deletingLastPathComponent() // CortexDemo (package root)
      .deletingLastPathComponent() // Packages
      .deletingLastPathComponent() // repo root
      .appendingPathComponent("Decoder/tests/fixtures/tiny_replay.json")
  }

  static func loadFixture() throws -> ReplayExport {
    try ReplayExport(sidecarURL: fixtureSidecar)
  }

  // MARK: Test 1 - the recorded source reports the MODEL's window length

  @Test("Test 1: RecordedSpikeSource reports numBins 32, channels 96, windowCount 8 on the fixture")
  func recordedSourceShape() throws {
    let export = try Self.loadFixture()
    let source = RecordedSpikeSource(export: export)

    #expect(RecordedSpikeSource.modelSeqLen == 32, "the shipped ndt1_real_vel_sweep_fp16 input is (1, 96, 1, 32)")
    #expect(source.numBins == 32, "the recorded source defaults to the MODEL's window length, not the synthetic 8")
    #expect(source.channels == 96)
    #expect(source.windowCount == 8, "256 fixture bins / 32 = 8 whole windows")
    #expect(source.window(0).count == 32 * 96)
  }

  // MARK: Test 2 - the window is exactly the export's bins, in bin-major order

  @Test("Test 2: window(i) is the export's bins [i*32 ..< (i+1)*32] in bin-major order")
  func windowMatchesTheExport() throws {
    let export = try Self.loadFixture()
    let source = RecordedSpikeSource(export: export)

    for index in 0 ..< source.windowCount {
      let expected = try export.window(endingAt: (index + 1) * 32 - 1, length: 32)
      #expect(source.window(index) == expected, "window \(index) is the export's own bins, unmodified")
    }
    // Distinct windows are distinct bins of a real (here synthetic-fixture) recording, not a repeat.
    #expect(source.window(0) != source.window(7))
  }

  // MARK: Test 3 - past the last whole window it clamps rather than reading out of range

  @Test("Test 3: window(_:) past windowCount - 1 clamps to the last whole window")
  func windowClampsAtTheBoundary() throws {
    let export = try Self.loadFixture()
    let source = RecordedSpikeSource(export: export)
    let last = source.window(source.windowCount - 1)

    #expect(source.window(source.windowCount) == last, "one past the end returns the last whole window")
    #expect(source.window(999) == last, "far past the end returns the last whole window")
    #expect(source.window(-1) == source.window(0), "a negative index clamps to the first window")
    // The clamp never degrades to an all-zero window: that would be silent data loss.
    #expect(last.contains { $0 != 0 }, "the clamped window carries real bins, not zeros")
  }

  // MARK: Test 4 - target and true velocity use the LAST bin of the window

  @Test("Test 4: target(forWindow:) and trueVelocity(forWindow:) take the window's LAST bin")
  func lastBinConvention() throws {
    let export = try Self.loadFixture()
    let source = RecordedSpikeSource(export: export)

    for index in 0 ..< source.windowCount {
      let lastBin = (index + 1) * 32 - 1
      #expect(try source.target(forWindow: index) == (export.target(at: lastBin)))
      #expect(try source.trueVelocity(forWindow: index) == (export.velocity(at: lastBin)))
    }
    // The convention matters: `apply_lag` already aligns row i's kinematics to the window ENDING at
    // bin i, so the rotation target and the decoded window describe the same instant.
    #expect(source.target(forWindow: 0) == SIMD2<Double>(-15.0, 0.0))
    #expect(source.target(forWindow: 7) == SIMD2<Double>(15.0, 15.0))
  }

  // MARK: Test 5 - the synthetic source is byte-identical after the conformance

  @Test("Test 5: SyntheticSpikeSource conforms to SpikeWindowSource with no behavior change")
  func syntheticSourceUnchanged() {
    let source: any SpikeWindowSource = SyntheticSpikeSource(seed: Self.testSeed)
    #expect(source.numBins == 8, "the v0 default window length is unchanged (and IS the Pattern-2 trap)")
    #expect(source.channels == 96)

    // Three values pinned from the closed-form drift, so a change to the v0 stream fails HERE rather
    // than silently moving the Phase-8 comparison's baseline.
    let window = source.window(0)
    #expect(window.count == 8 * 96)
    #expect(window[0] == Float16(0.6797))
    #expect(window[1] == Float16(3.83))
    #expect(window[3 * 96 + 7] == Float16(3.535))
  }

  // MARK: Test 6 - the pipeline derives its buffer length from the injected source

  @Test("Test 6: ReplayPipeline.sourceSeqLen follows the injected source, 32 recorded vs 8 synthetic")
  func pipelineSeqLenFollowsTheSource() throws {
    let export = try Self.loadFixture()
    let recorded = ReplayPipeline(source: RecordedSpikeSource(export: export), seed: Self.testSeed)
    #expect(recorded.sourceSeqLen == 32, "a recorded source sizes the SpikeInputBuffer at the model's 32 bins")

    let synthetic = ReplayPipeline(seed: Self.testSeed)
    #expect(synthetic.sourceSeqLen == 8, "the default convenience init still builds the v0 8-bin source")
  }

  // MARK: Test 7 - every tick is counted, and a fallback run is visible

  @Test("Test 7: modelBackedTicks / totalTicks / allTicksModelBacked count every tick")
  func modelBackedCountersAreExact() throws {
    let export = try Self.loadFixture()
    let pipeline = ReplayPipeline(source: RecordedSpikeSource(export: export), seed: Self.testSeed)

    #expect(pipeline.totalTicks == 0)
    #expect(!pipeline.allTicksModelBacked, "a run with no ticks is NOT model-backed")

    for _ in 0 ..< 12 {
      _ = pipeline.tick()
    }

    #expect(pipeline.totalTicks == 12, "every tick is counted")
    #expect(pipeline.modelBackedTicks == 0, "with no model present every tick used the synthetic fallback")
    #expect(!pipeline.allTicksModelBacked, "so the run must NOT claim to be model-backed")
    #expect(!pipeline.isModelBacked)
  }

  // MARK: Test 8 - a decode that cannot be wired records WHY

  @Test("Test 8: lastDecodeFailure is nil until a decode fails, then names both shapes")
  func lastDecodeFailureIsRecorded() throws {
    let export = try Self.loadFixture()
    let clean = ReplayPipeline(source: RecordedSpikeSource(export: export), seed: Self.testSeed)
    for _ in 0 ..< 4 {
      _ = clean.tick()
    }
    #expect(clean.lastDecodeFailure == nil, "no decode was attempted, so there is nothing to report")

    // A model URL that cannot load forces the failure path WITHOUT needing the gitignored .mlpackage,
    // so this control runs on a clean clone. The old code discarded this reason entirely.
    let absent = FileManager.default.temporaryDirectory
      .appendingPathComponent("cortex-no-such-model-\(UUID().uuidString).mlpackage")
    let broken = ReplayPipeline(
      source: RecordedSpikeSource(export: export),
      seed: Self.testSeed,
      modelURL: absent
    )
    #expect(!broken.isModelBacked, "an unloadable model still degrades to the synthetic fallback")
    let reason = try #require(broken.lastDecodeFailure, "the reason must be recoverable, not discarded")
    #expect(reason.contains("32"), "the recorded reason names the source's window length")
    #expect(reason.contains("96"), "the recorded reason names the channel count")

    for _ in 0 ..< 4 {
      _ = broken.tick()
    }
    #expect(broken.totalTicks == 4)
    #expect(broken.modelBackedTicks == 0)
    #expect(!broken.allTicksModelBacked)
  }

  // MARK: Test 9 - the Pattern-2 trap itself, driven against the real model

  @Test("Test 9: the seqLen mismatch that used to pass silently is now visible on every tick")
  func theSeqLenTrapIsVisible() throws {
    // The .mlpackage is gitignored; SKIP cleanly when absent (the ReplayPipelineTests Test 2
    // idiom) so this suite stays green on a clean clone. With a real model present this is the direct
    // control for RESEARCH Pattern 2: the SAME export, the SAME model, ONE variable changed - the
    // source's window length - and the two runs must be distinguishable from the outside.
    guard let modelURL = ReplayPipeline.modelURLFromEnvironment() else { return }
    let export = try Self.loadFixture()

    // 32 bins: the shape the shipped model's (1, 96, 1, 32) spikes input wants.
    let correct = ReplayPipeline(
      source: RecordedSpikeSource(export: export),
      seed: Self.testSeed,
      modelURL: modelURL
    )
    #expect(correct.sourceSeqLen == 32)
    for _ in 0 ..< 6 {
      _ = correct.tick()
    }
    #expect(correct.allTicksModelBacked, "at the model's own window length every tick runs NDT1")
    #expect(correct.lastDecodeFailure == nil)

    // 8 bins: SyntheticSpikeSource's default, and the exact mismatch that used to disappear into the
    // synthetic fallback while the loop kept running and its numbers stopped being real.
    let mismatched = ReplayPipeline(
      source: RecordedSpikeSource(export: export, numBins: 8),
      seed: Self.testSeed,
      modelURL: modelURL
    )
    #expect(mismatched.sourceSeqLen == 8)
    for _ in 0 ..< 6 {
      _ = mismatched.tick()
    }
    #expect(mismatched.modelBackedTicks == 0, "the model rejects the 8-bin buffer on every tick")
    #expect(!mismatched.allTicksModelBacked, "so the run must NOT be publishable as a real-data number")
    let reason = try #require(mismatched.lastDecodeFailure, "and the mismatch must be legible, not silent")
    #expect(reason.contains("seqLen 8"), "the reason names the buffer's actual window length")
    #expect(reason.contains("numBins 8"), "and the source's")
  }
}
