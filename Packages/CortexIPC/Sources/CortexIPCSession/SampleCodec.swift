import CortexCoreC
import FlatBuffers

// SampleCodec — IPC-04. Build/read the FlatBuffers `Sample { ts_ns; channel_data:[ubyte]; seq; }`
// wire frame (Cortex.IPC.Sample, vendored gen in generated/sample_generated.swift, flatc 25.12.19
// matching the FlatBuffers runtime, CF#7).
//
// channel_data is raw IEEE-754 half (f16) bytes (D-10). The `[ubyte]` typing hides a half-pair
// invariant: the vector length MUST equal CORTEX_CHANNEL_COUNT * 2. We assert it on BOTH encode
// and decode and expose the channel payload as a zero-copy `Float16` view via the generated
// `withUnsafePointerToChannelData` slice hook + `withMemoryRebound(to: Float16.self, ...)` — no
// per-element conversion (D-10; hardware f16 on Apple Silicon, preserved end-to-end into the ANE).
//
// Decode uses `getCheckedRoot` (the FlatBuffers verifier) so a truncated/garbage buffer is rejected
// fail-closed (Discretion D-58: malformed input throws; the caller drops the frame / tears down)
// rather than producing an out-of-bounds read.
//
// CortexIPCSession is Foundation-allowed by design (D-04/D-06); not policed by the hot-path gate.
// The codec types are `nonisolated`: they are stateless pure value transforms with no shared mutable
// state, so they must be callable from ANY context — the MainActor-isolated daemon setup, AND the
// Foundation-free Transport consumer (Plan 02-04) that opens/decodes frames off the main actor. The
// CortexIPCSession target sets `.defaultIsolation(MainActor.self)`; `nonisolated` opts these out.
import Foundation

/// Number of f16 channels per frame, as a Swift Int (mirrors the C compile-time `CORTEX_CHANNEL_COUNT`
/// + its `_Static_assert` in cortex_shm.h, D-11). The wire `channel_data` byte length is `channelCount * 2`.
///
/// `nonisolated` opts this immutable `Int` (trivially Sendable, derived from a compile-time C macro)
/// out of the target's `.defaultIsolation(MainActor.self)` so the nonisolated codec — and the Plan
/// 02-04 off-main-actor consumer — can read it; there is no mutable state to race on.
public nonisolated let cortexChannelCount: Int = .init(CORTEX_CHANNEL_COUNT)

/// Wire byte length of `channel_data`: one IEEE-754 half (2 bytes) per channel (D-10 half-pair invariant).
public nonisolated let cortexChannelDataByteCount: Int = cortexChannelCount * 2

public enum SampleCodecError: Error, Equatable, Sendable {
  /// `channelData` length (in *elements* for encode, *bytes* for decode) did not match the
  /// CORTEX_CHANNEL_COUNT half-pair invariant (D-10).
  case badChannelCount(Int)
  /// The buffer failed the FlatBuffers verifier (`getCheckedRoot`) — truncated/garbage (fail-closed).
  case malformedBuffer
}

/// A decoded `Sample`. Holds the backing `ByteBuffer` so the zero-copy `Float16` view stays valid.
public nonisolated struct DecodedSample {
  /// mach_absolute_time-derived nanoseconds (D-12).
  public let tsNs: UInt64
  /// Ring/doorbell sequence number; also the AES-GCM nonce counter (D-12/D-16).
  public let seq: UInt64

  // The verified root + its buffer. Kept alive so `withChannelF16` can rebind the vector in place.
  private let sample: Cortex_IPC_Sample
  private var buffer: ByteBuffer

  fileprivate init(tsNs: UInt64, seq: UInt64, sample: Cortex_IPC_Sample, buffer: ByteBuffer) {
    self.tsNs = tsNs
    self.seq = seq
    self.sample = sample
    self.buffer = buffer
  }

  /// Zero-copy access to `channel_data` as `Float16` (D-10): the generated slice hook hands us the
  /// raw `[ubyte]` region, which we rebind to `Float16` with `withMemoryRebound` — no element-wise
  /// loop, no allocation. The pointer is valid only for the duration of `body`.
  ///
  /// Precondition (already enforced at decode time): the byte region is exactly
  /// `cortexChannelDataByteCount` long, so the `Float16` view has exactly `cortexChannelCount` elements.
  public func withChannelF16<T>(_ body: (UnsafeBufferPointer<Float16>) throws -> T) rethrows -> T {
    let result: T? = try sample.withUnsafePointerToChannelData { raw, count in
      // `count` is the element count of a [ubyte] vector == byte count. Invariant re-checked at decode.
      precondition(count == cortexChannelDataByteCount,
                   "channel_data byte count \(count) != \(cortexChannelDataByteCount) (CORTEX_CHANNEL_COUNT * 2)")
      return try raw.withMemoryRebound(to: Float16.self) { f16 in
        precondition(f16.count == cortexChannelCount,
                     "rebound Float16 view count \(f16.count) != \(cortexChannelCount)")
        return try body(f16)
      }
    }
    // The slice hook only returns nil when the field is absent; decode() guarantees presence.
    guard let result else {
      preconditionFailure("channel_data field unexpectedly absent after decode-time validation")
    }
    return result
  }
}

public nonisolated enum SampleCodec {
  /// Build a `Sample` FlatBuffer from `channelF16` (exactly `cortexChannelCount` half-floats, D-10),
  /// `tsNs`, and `seq`. The Float16 buffer is reinterpreted as raw bytes (`[ubyte]`) — the encode copy
  /// into the builder is ~200-400 ns/frame and is OFF the measured doorbell hot path (D-06).
  /// Throws `badChannelCount` if `channelF16.count != cortexChannelCount`.
  public static func encode(tsNs: UInt64, seq: UInt64, channelF16: UnsafeBufferPointer<Float16>) throws -> [UInt8] {
    guard channelF16.count == cortexChannelCount else {
      throw SampleCodecError.badChannelCount(channelF16.count)
    }
    var builder = FlatBufferBuilder(initialSize: 256)
    // Reinterpret the f16 elements as raw bytes; createVector copies them into the builder.
    let vectorOffset: Offset = channelF16.withMemoryRebound(to: UInt8.self) { rawBytes -> Offset in
      precondition(rawBytes.count == cortexChannelDataByteCount,
                   "f16->u8 rebind produced \(rawBytes.count) bytes, expected \(cortexChannelDataByteCount)")
      return builder.createVector(Array(rawBytes))
    }
    let root = Cortex_IPC_Sample.createSample(
      &builder,
      tsNs: tsNs,
      channelDataVectorOffset: vectorOffset,
      seq: seq
    )
    builder.finish(offset: root)
    return builder.sizedByteArray
  }

  /// Convenience: build from a `[Float16]` array (validates count, then forwards to the buffer overload).
  public static func encode(tsNs: UInt64, seq: UInt64, channels: [Float16]) throws -> [UInt8] {
    guard channels.count == cortexChannelCount else {
      throw SampleCodecError.badChannelCount(channels.count)
    }
    return try channels.withUnsafeBufferPointer { try encode(tsNs: tsNs, seq: seq, channelF16: $0) }
  }

  /// Read a `Sample` from wire bytes. Uses `getCheckedRoot` (FlatBuffers verifier) → throws
  /// `malformedBuffer` on a truncated/garbage buffer (fail-closed, D-58). Then asserts the
  /// `channel_data` byte length == `cortexChannelDataByteCount` (D-10) → throws `badChannelCount`.
  public static func decode(_ bytes: [UInt8]) throws -> DecodedSample {
    var byteBuffer = ByteBuffer(bytes: bytes)
    let sample: Cortex_IPC_Sample
    do {
      sample = try getCheckedRoot(byteBuffer: &byteBuffer)
    } catch {
      throw SampleCodecError.malformedBuffer
    }
    // Re-fetch the verified buffer for the decoded sample's lifetime.
    let channelByteCount = sample.channelData.count
    guard channelByteCount == cortexChannelDataByteCount else {
      throw SampleCodecError.badChannelCount(channelByteCount)
    }
    return DecodedSample(tsNs: sample.tsNs, seq: sample.seq, sample: sample, buffer: byteBuffer)
  }
}
