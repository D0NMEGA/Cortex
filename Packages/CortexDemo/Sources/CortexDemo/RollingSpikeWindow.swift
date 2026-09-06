// RollingSpikeWindow - Phase 10 (RD-08, Plan 10-06): the missing piece of the D-05 chain.
//
// ## Why it exists
// 10-RESEARCH Pitfall 9. `SampleCodec.encode(tsNs:seq:channels:)` takes `[Float16]` of exactly
// `cortexChannelCount` (96) elements, so ONE IPC frame carries ONE 20 ms bin across 96 channels. The
// shipped `ndt1_real_vel_sweep_fp16` input is `(1, 96, 1, 32)`. Nothing in the repo bridged that
// gap: the 32-bin window has to be assembled on the CONSUMER side, one frame at a time, and no
// component did that. This is that component, and it is the Seam B boundary's missing piece
// (10-PREREGISTRATION section 9: daemon reads the export, AES-GCM seal, shm ring, consumer decrypt,
// rolling 32-bin window, `SpikeInputBuffer`, decode).
//
// ## Deliberately NOT on the hot path
// This runs once per 20 ms in the consumer, after the decrypt and before the decode, so a small copy
// per completed window is fine and a lock-free ring is not needed. It is not policed by
// `Tools/scripts/hotpath-policy.sh` and must not be moved into a policed target: the audio-callback
// discipline (`Packages/CortexIPC/Sources/CortexIPCTransport`,
// `Packages/CortexRing/Sources/CortexRingHotPath`, `Packages/CortexReFIT/Sources/CortexReFIT`)
// applies to the transport this sits behind, not to the accumulation itself. The backing store is
// one flat `[Float16]` written in place; only `window()` and `fill(_:)` copy.
//
// ## The two silent failures this refuses
// Both would produce a window that decodes cleanly and is wrong, with nothing erroring:
//
//   1. REVERSED ORDER. `window()` and `fill(_:)` both emit bin 0 as the OLDEST bin. A time-reversed
//      window is a perfectly well-formed `(1, 96, 1, 32)` tensor, so the model would accept it and
//      every downstream number would be wrong. `RollingSpikeWindowTests` pins the ordering on both
//      paths with distinguishable bins.
//   2. A WINDOW STRADDLING A GAP. A skipped sequence number means the 32 bins in hand are not 32
//      CONTIGUOUS bins of the recorded session. Decoding them would be a fabrication, so a gap
//      RESETS the fill rather than inserting zeros or stitching across the hole.
import CortexDecoder

/// What the accumulator did with one pushed frame. Every refusal is named, so a consumer can report
/// WHICH invariant bit rather than discovering a frame count that silently does not add up.
public nonisolated enum RollingPushResult: Sendable, Equatable {
  /// The frame was the expected successor and was accumulated.
  case accepted
  /// The frame's `seq` was already seen (a replay or a stale re-read). Not accumulated.
  case duplicate(seq: UInt64)
  /// A sequence number was skipped. Not accumulated, and the fill is RESET (see `push`).
  case gap(expected: UInt64, got: UInt64)
  /// The frame did not carry exactly `channels` values. Not accumulated; nothing is mutated.
  case badChannelCount(found: Int, expected: Int)
}

/// One bin in, a contiguous `length`-bin window out.
///
/// `nonisolated` (the `CursorIntegrator` idiom) because it runs in the IPC consumer, which is off the
/// main actor by construction - `HarnessConsumer` is `nonisolated` for exactly that reason - while
/// this package's default isolation is `MainActor`. It is a reference type with mutable state and is
/// deliberately NOT `Sendable`: one consumer thread owns one accumulator.
public final nonisolated class RollingSpikeWindow {
  /// Recording channels per bin - the NDT1 `(1, channels, 1, S)` contract (96, DEC-02), and exactly
  /// what `SampleCodec.encode` requires per frame.
  public let channels: Int
  /// Bins per decode window - the model's S. 32 for the shipped real model
  /// (`RecordedSpikeSource.modelSeqLen`), locked by 10-PREREGISTRATION section 2.
  public let length: Int

  /// How many CONTIGUOUS bins are currently accumulated, capped at `length`.
  public private(set) var count: Int = 0
  /// Frames accumulated over the accumulator's lifetime.
  public private(set) var acceptedFrames: Int = 0
  /// Frames REFUSED over the accumulator's lifetime: duplicates, gaps and malformed channel counts.
  /// Reported by the Seam B smoke so a lossy run is visible rather than assumed away.
  public private(set) var droppedFrames: Int = 0

  /// `true` once `length` contiguous bins are in hand, which is the only state `window()` and
  /// `fill(_:)` will produce from.
  public var isFull: Bool {
    count >= length
  }

  /// The flat bin-major backing store, `length * channels` values. `head` is the index of the NEXT
  /// bin slot to write, so the ring wraps in place and only the accessors copy.
  private var storage: [Float16]
  private var head: Int = 0
  /// The last `seq` this accumulator anchored on, or nil before the first push. A gap re-anchors it
  /// on the seq that arrived, so a SECOND gap is still detected instead of being absorbed as a fresh
  /// start.
  private var lastSeq: UInt64?

  public init(channels: Int = 96, length: Int = 32) {
    precondition(channels > 0 && length > 0, "RollingSpikeWindow requires positive dimensions")
    self.channels = channels
    self.length = length
    storage = [Float16](repeating: 0, count: length * channels)
  }

  /// Push one decoded IPC frame: `seq` is the ring sequence the slot was published under, `values` is
  /// that frame's 96 channel counts.
  ///
  /// Ordering rules, in the order they are applied:
  ///
  ///   - a `values.count` other than `channels` is `.badChannelCount` and mutates NOTHING, not even
  ///     the sequence anchor, so the same seq can be re-delivered correctly;
  ///   - a `seq` less than or equal to the anchor is `.duplicate` (forward-only, mirroring
  ///     `HarnessConsumer`'s anti-replay check) and is not accumulated;
  ///   - a `seq` that skips one or more numbers is `.gap`, is NOT accumulated, RESETS `count` to 0,
  ///     and re-anchors on the seq that arrived. The reset is the point: 32 bins spanning a hole are
  ///     not 32 contiguous bins of the recorded session, and decoding them would be a fabrication.
  ///     Inserting zeros would be worse, because a zeroed bin is a real, decodable value the session
  ///     never produced;
  ///   - the first push of an empty accumulator accepts any `seq`, because there is nothing to be
  ///     the successor of yet.
  ///
  /// Every refusal increments `droppedFrames`.
  @discardableResult
  public func push(seq: UInt64, channels values: [Float16]) -> RollingPushResult {
    guard values.count == channels else {
      droppedFrames += 1
      return .badChannelCount(found: values.count, expected: channels)
    }

    if let previous = lastSeq {
      if seq <= previous {
        droppedFrames += 1
        return .duplicate(seq: seq)
      }
      let expected = previous &+ 1
      if seq != expected {
        droppedFrames += 1
        count = 0
        head = 0
        lastSeq = seq
        return .gap(expected: expected, got: seq)
      }
    }

    let base = head * channels
    for channel in 0 ..< channels {
      storage[base + channel] = values[channel]
    }
    head = (head + 1) % length
    if count < length {
      count += 1
    }
    lastSeq = seq
    acceptedFrames += 1
    return .accepted
  }

  /// The accumulated window in BIN-MAJOR order with the OLDEST bin FIRST:
  /// `window()[binOffset * channels + channel]`, byte-for-byte the layout
  /// `SyntheticSpikeSource.window` and `ReplayExport.window(endingAt:length:)` emit, so this
  /// accumulator is interchangeable with them at the decode boundary.
  ///
  /// Returns an EMPTY array when the accumulator is not full. A partial window is never zero-padded
  /// into a full one; `isFull` is what tells a caller whether there is anything to decode.
  public func window() -> [Float16] {
    guard isFull else { return [] }
    var out = [Float16](repeating: 0, count: length * channels)
    // `head` is the next slot to write, so it is also the OLDEST bin once the ring is full. Rotate
    // from there so the returned layout is unambiguous regardless of where the ring happens to sit.
    for row in 0 ..< length {
      let source = ((head + row) % length) * channels
      let destination = row * channels
      for channel in 0 ..< channels {
        out[destination + channel] = storage[source + channel]
      }
    }
    return out
  }

  /// Write the accumulated window straight into a zero-copy decode buffer, bin 0 being the OLDEST
  /// bin - the SAME convention `window()` uses, and the one the model's time axis expects. Getting
  /// this backwards would feed the decoder a time-reversed window that errors nowhere.
  ///
  /// Refuses a partial window rather than writing one: an accumulator holding `count < length` bins
  /// has no value for bins `count ..< length`, so filling would either leave stale bytes from the
  /// previous window or write zeros the session never produced. The refusal reuses
  /// `ZeroCopyInputError.indexOutOfRange` ("a row/column index was out of the configured bounds")
  /// with `column: count`, the first bin that does not yet exist, so the typed-throws signature
  /// stays the buffer's own error domain.
  ///
  /// `@MainActor` while the rest of this type is not, and the split is the real isolation boundary
  /// rather than a convenience: `SpikeInputBuffer` is MainActor-isolated (CortexDecoder carries
  /// `.defaultIsolation(MainActor.self)`), so the shared-IOSurface write has to happen there, while
  /// `push` and `window()` stay nonisolated so a consumer thread can accumulate frames off the main
  /// actor as `HarnessConsumer` does. Only the handoff crosses.
  @MainActor
  public func fill(_ buffer: SpikeInputBuffer) throws(ZeroCopyInputError) {
    guard isFull else {
      throw .indexOutOfRange(row: 0, column: count)
    }
    for bin in 0 ..< length {
      let source = ((head + bin) % length) * channels
      for channel in 0 ..< channels {
        try buffer.write(storage[source + channel], channel: channel, bin: bin)
      }
    }
  }
}
