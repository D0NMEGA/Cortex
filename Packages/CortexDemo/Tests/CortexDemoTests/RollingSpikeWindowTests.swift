// RollingSpikeWindowTests - Phase 10 (RD-08, Plan 10-06): the one-bin-in, 32-bin-window-out
// accumulator that sits between the IPC consumer and `SpikeInputBuffer`.
//
// Every case here is dataset-free and model-free: the accumulator is pure arithmetic over
// `[Float16]`, so this suite is green on a clean clone with no export, no `.mlpackage` and no Metal
// device except where a case explicitly needs one (`fill`, which skips when no device exists).
//
// Two of these cases exist because getting them wrong would be SILENT. A time-reversed window
// decodes without erroring and every downstream number is then wrong; a window assembled across a
// sequence gap is a contiguous-looking 32 bins that the session never produced. Both are pinned with
// distinguishable bins (bin `i` filled with `Float16(i)`) so an ordering error shows up in the
// assertion message rather than as a plausible-looking number three stages later.
import CortexDecoder
@testable import CortexDemo
import Metal
import Testing

@Suite("RD-08 / Pitfall 9: the rolling 32-bin accumulator between the IPC frame and the decode window")
struct RollingSpikeWindowTests {
  /// A bin whose every channel carries `value`, so a window's bin ordering is readable from any
  /// single element of that bin.
  static func bin(_ value: Int, channels: Int = 96) -> [Float16] {
    [Float16](repeating: Float16(value), count: channels)
  }

  /// Push bins `0 ..< count` at seq `1 ... count`, the sequence numbering the producer uses
  /// (`ring.loadProducerSeq() &+ 1` starts at 1, never 0).
  @discardableResult
  static func pushRange(_ window: RollingSpikeWindow, _ count: Int, firstSeq: UInt64 = 1) -> [RollingPushResult] {
    (0 ..< count).map { index in
      window.push(seq: firstSeq &+ UInt64(index), channels: bin(index))
    }
  }

  // MARK: Test 1 - a fresh accumulator is empty

  @Test("Test 1: a fresh RollingSpikeWindow(channels: 96, length: 32) is empty and not full")
  func freshWindowIsEmpty() {
    let window = RollingSpikeWindow(channels: 96, length: 32)

    #expect(window.channels == 96)
    #expect(window.length == 32)
    // `count` is a bin fill level, not a collection size; there is no `isEmpty` to prefer.
    // swiftlint:disable:next empty_count
    #expect(window.count == 0)
    #expect(window.isFull == false)
    #expect(window.acceptedFrames == 0)
    #expect(window.droppedFrames == 0)
    #expect(window.window().isEmpty, "an unfilled accumulator returns no window rather than a zero-padded one")
  }

  // MARK: Test 2 - the 32nd bin is what makes it full

  @Test("Test 2: 31 bins leaves isFull false; the 32nd makes it true")
  func fillsOnTheThirtySecondBin() {
    let window = RollingSpikeWindow(channels: 96, length: 32)

    Self.pushRange(window, 31)
    #expect(window.count == 31)
    #expect(window.isFull == false, "31 of 32 bins is not a decodable window")

    #expect(window.push(seq: 32, channels: Self.bin(31)) == .accepted)
    #expect(window.count == 32)
    #expect(window.isFull, "the 32nd contiguous bin completes the window")
    #expect(window.acceptedFrames == 32)
  }

  // MARK: Test 3 - window() is bin-major with the OLDEST bin first

  @Test("Test 3: window() is bin-major with the OLDEST bin first")
  func windowIsOldestFirst() {
    let window = RollingSpikeWindow(channels: 96, length: 32)
    Self.pushRange(window, 32)

    let out = window.window()
    #expect(out.count == 32 * 96, "a full window is length * channels values")

    // The bin pushed 32 pushes ago carried Float16(0); the most recent carried Float16(31).
    #expect(out[0] == Float16(0), "window()[0 ..< 96] must be the OLDEST bin, not the newest")
    #expect(out[95] == Float16(0), "the whole oldest bin is contiguous at the front")
    #expect(out[31 * 96] == Float16(31), "the LAST bin-major row is the newest bin")

    for binIndex in 0 ..< 32 {
      let base = binIndex * 96
      #expect(
        out[base] == Float16(binIndex),
        "bin \(binIndex) should carry \(binIndex) but carried \(out[base]); the window is out of order"
      )
      #expect(out[base + 95] == Float16(binIndex))
    }
  }

  // MARK: Test 4 - a 33rd push shifts the window by exactly one bin

  @Test("Test 4: a 33rd push keeps isFull and shifts the window by exactly one bin (the wrap)")
  func thirtyThirdPushWrapsByOne() {
    let window = RollingSpikeWindow(channels: 96, length: 32)
    Self.pushRange(window, 32)
    let before = window.window()

    #expect(window.push(seq: 33, channels: Self.bin(32)) == .accepted)
    #expect(window.isFull)
    #expect(window.count == 32, "the accumulator never grows past length")

    let after = window.window()
    #expect(after[0] == Float16(1), "the new oldest bin is what used to be index 1")
    #expect(after[31 * 96] == Float16(32), "the newest bin is the one just pushed")

    // The shift is exactly one bin: rows 0..<31 after equal rows 1..<32 before.
    for binIndex in 0 ..< 31 {
      let afterBase = binIndex * 96
      let beforeBase = (binIndex + 1) * 96
      #expect(
        after[afterBase] == before[beforeBase],
        "row \(binIndex) after the wrap should equal row \(binIndex + 1) before it"
      )
    }
  }

  // MARK: Test 5 - a duplicate seq is refused and does not mutate the buffer

  @Test("Test 5: a repeated seq returns .duplicate and does not advance the accumulator")
  func duplicateSeqIsRefused() {
    let window = RollingSpikeWindow(channels: 96, length: 32)
    Self.pushRange(window, 4)
    #expect(window.count == 4)

    // seq 4 was the last accepted; replaying it must not be accumulated a second time.
    #expect(window.push(seq: 4, channels: Self.bin(99)) == .duplicate(seq: 4))
    #expect(window.count == 4, "a duplicate must not advance the fill")
    #expect(window.acceptedFrames == 4)
    #expect(window.droppedFrames == 1)

    // A strictly OLDER seq is the same refusal (forward-only, mirroring HarnessConsumer's anti-replay).
    #expect(window.push(seq: 2, channels: Self.bin(99)) == .duplicate(seq: 2))
    #expect(window.count == 4)
  }

  // MARK: Test 6 - a gap RESETS the accumulator instead of bridging it

  @Test("Test 6: a skipped seq returns .gap and RESETS count to 0 rather than inserting zeros")
  func gapResetsRatherThanBridging() {
    let window = RollingSpikeWindow(channels: 96, length: 32)
    Self.pushRange(window, 10)
    #expect(window.count == 10)

    // seq 11 is expected; 13 arrives.
    #expect(window.push(seq: 13, channels: Self.bin(12)) == .gap(expected: 11, got: 13))
    // `count` is a bin fill level, not a collection size; there is no `isEmpty` to prefer.
    // swiftlint:disable:next empty_count
    #expect(window.count == 0, "a window straddling a gap is not 32 contiguous bins, so the fill RESETS")
    #expect(window.isFull == false)
    #expect(window.droppedFrames == 1)
    #expect(window.acceptedFrames == 10, "the gapped frame is not counted as accepted")
    #expect(window.window().isEmpty, "a reset accumulator has no window to hand out")
  }

  // MARK: Test 7 - a gap does not silently insert zero bins

  @Test("Test 7: after a gap, 32 fresh contiguous bins are needed and none of them is a zero filler")
  func gapDoesNotInsertZeroBins() {
    let window = RollingSpikeWindow(channels: 96, length: 32)
    Self.pushRange(window, 10)
    #expect(window.push(seq: 13, channels: Self.bin(12)) == .gap(expected: 11, got: 13))

    // Resume from the gapped seq. 31 more bins must not be enough; the 32nd completes it.
    #expect(window.push(seq: 14, channels: Self.bin(100)) == .accepted)
    Self.pushRange(window, 30, firstSeq: 15)
    #expect(window.count == 31)
    #expect(window.isFull == false, "the pre-gap bins were discarded, so the fill restarts from zero")

    #expect(window.push(seq: 45, channels: Self.bin(131)) == .accepted)
    #expect(window.isFull)
    let out = window.window()
    #expect(out[0] == Float16(100), "the first post-gap bin is the oldest; no zero filler was inserted")
    #expect(out[31 * 96] == Float16(131))
  }

  // MARK: Test 8 - a wrong channel count is refused without mutating anything

  @Test("Test 8: push with a channel count other than 96 returns .badChannelCount and mutates nothing")
  func badChannelCountIsRefused() {
    let window = RollingSpikeWindow(channels: 96, length: 32)
    Self.pushRange(window, 5)
    let before = window.count

    #expect(
      window.push(seq: 6, channels: Self.bin(5, channels: 95)) == .badChannelCount(found: 95, expected: 96)
    )
    #expect(window.count == before, "a malformed frame must not advance the fill")
    #expect(window.acceptedFrames == 5)
    #expect(window.droppedFrames == 1)

    // The refusal did not consume the sequence number either: seq 6 is still the expected next one.
    #expect(window.push(seq: 6, channels: Self.bin(5)) == .accepted)
    #expect(window.count == before + 1)
  }

  // MARK: Test 9 - fill() writes bin 0 as the OLDEST bin

  @Test("Test 9: fill(_:) writes bin 0 as the OLDEST bin, matching window()'s ordering")
  @MainActor
  func fillWritesOldestAtBinZero() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      // No Metal device (a headless CI container). The ordering contract is still pinned by Test 3.
      return
    }
    let window = RollingSpikeWindow(channels: 96, length: 32)
    Self.pushRange(window, 32)

    let buffer = try SpikeInputBuffer(device: device, seqLen: 32, channels: 96)
    try window.fill(buffer)

    #expect(try buffer.read(channel: 0, bin: 0) == Float16(0), "bin 0 of the decode buffer is the OLDEST bin")
    #expect(try buffer.read(channel: 95, bin: 0) == Float16(0))
    #expect(try buffer.read(channel: 0, bin: 31) == Float16(31), "bin 31 is the NEWEST bin")
    for binIndex in 0 ..< 32 {
      #expect(
        try buffer.read(channel: 7, bin: binIndex) == Float16(binIndex),
        "SpikeInputBuffer bin \(binIndex) should carry \(binIndex); a reversed fill would decode a window that never happened"
      )
    }
  }

  // MARK: Test 10 - fill() on an unfilled accumulator refuses

  @Test("Test 10: fill(_:) on an accumulator that is not full throws rather than writing a partial window")
  @MainActor
  func fillRefusesAPartialWindow() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let window = RollingSpikeWindow(channels: 96, length: 32)
    Self.pushRange(window, 31)

    let buffer = try SpikeInputBuffer(device: device, seqLen: 32, channels: 96)
    #expect(throws: ZeroCopyInputError.self) {
      try window.fill(buffer)
    }
  }

  // MARK: Test 11 - the first accepted seq can be anything; only the SUCCESSOR is constrained

  @Test("Test 11: the first push accepts any seq, and a gap RE-ANCHORS rather than clearing the anchor")
  func firstPushAcceptsAnySeqAndAGapReAnchors() {
    let window = RollingSpikeWindow(channels: 96, length: 32)

    #expect(window.push(seq: 5000, channels: Self.bin(0)) == .accepted, "an empty accumulator has no expectation yet")
    #expect(window.count == 1)
    #expect(window.push(seq: 5001, channels: Self.bin(1)) == .accepted)
    #expect(window.push(seq: 5003, channels: Self.bin(2)) == .gap(expected: 5002, got: 5003))
    // `count` is a bin fill level, not a collection size; there is no `isEmpty` to prefer.
    // swiftlint:disable:next empty_count
    #expect(window.count == 0)

    // The gap RE-ANCHORS on the seq that arrived, so a SECOND gap is still detected rather than
    // being absorbed as a fresh start. This is why the reset clears the fill and not the anchor.
    #expect(window.push(seq: 5006, channels: Self.bin(3)) == .gap(expected: 5004, got: 5006))
    #expect(window.droppedFrames == 2)
    #expect(window.push(seq: 5007, channels: Self.bin(4)) == .accepted)
    #expect(window.count == 1)
  }
}
