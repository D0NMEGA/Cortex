// SampleCodecTests — IPC-04. Proves the FlatBuffers Sample codec round-trips bit-exact, exposes a
// zero-copy [ubyte]<->Float16 view (D-10), enforces the channel_data.count == CORTEX_CHANNEL_COUNT*2
// half-pair invariant on BOTH encode and decode, and rejects garbage buffers via getCheckedRoot.
import Testing
import FlatBuffers

@testable import CortexIPCSession

@Suite("SampleCodec (IPC-04)")
struct SampleCodecTests {

  /// Deterministic Float16 payload of exactly `cortexChannelCount` distinct values.
  private static func makeChannels() -> [Float16] {
    (0..<cortexChannelCount).map { Float16($0) - 32.0 }  // mix of negatives + positives
  }

  @Test("ts_ns, seq, and the Float16 channel array round-trip bit-exact")
  func roundTripBitExact() throws {
    let channels = Self.makeChannels()
    let tsNs: UInt64 = 1_234_567_890_123
    let seq: UInt64 = 0xDEAD_BEEF_0000_0042

    let bytes = try SampleCodec.encode(tsNs: tsNs, seq: seq, channels: channels)
    let decoded = try SampleCodec.decode(bytes)

    #expect(decoded.tsNs == tsNs)
    #expect(decoded.seq == seq)

    // Bit-exact comparison via the raw bit patterns (avoids NaN/-0.0 equality pitfalls).
    decoded.withChannelF16 { view in
      #expect(view.count == cortexChannelCount)
      for i in 0..<cortexChannelCount {
        #expect(view[i].bitPattern == channels[i].bitPattern)
      }
    }
  }

  @Test("decode exposes channel_data as a zero-copy Float16 view of count == CORTEX_CHANNEL_COUNT")
  func zeroCopyFloat16View() throws {
    let channels = Self.makeChannels()
    let bytes = try SampleCodec.encode(tsNs: 7, seq: 9, channels: channels)
    let decoded = try SampleCodec.decode(bytes)

    let count = decoded.withChannelF16 { view -> Int in
      // The view is backed directly by the ByteBuffer region (no per-element copy / loop in decode).
      #expect(view[0].bitPattern == channels[0].bitPattern)
      #expect(view[cortexChannelCount - 1].bitPattern == channels[cortexChannelCount - 1].bitPattern)
      return view.count
    }
    #expect(count == cortexChannelCount)
  }

  @Test("encode rejects channel_data whose element count != CORTEX_CHANNEL_COUNT (half-pair invariant, D-10)")
  func encodeRejectsWrongCount() throws {
    let tooFew = [Float16](repeating: 1.0, count: cortexChannelCount - 1)
    #expect(throws: SampleCodecError.badChannelCount(cortexChannelCount - 1)) {
      _ = try SampleCodec.encode(tsNs: 0, seq: 0, channels: tooFew)
    }
    let tooMany = [Float16](repeating: 1.0, count: cortexChannelCount + 5)
    #expect(throws: SampleCodecError.badChannelCount(cortexChannelCount + 5)) {
      _ = try SampleCodec.encode(tsNs: 0, seq: 0, channels: tooMany)
    }
  }

  @Test("decode rejects a Sample whose channel_data byte length != CORTEX_CHANNEL_COUNT*2 (fail-closed)")
  func decodeRejectsWrongByteLength() throws {
    // Hand-build a well-formed Sample with a too-short channel_data vector (verifier passes, but the
    // half-pair invariant must still reject it on decode).
    var builder = FlatBufferBuilder(initialSize: 64)
    let shortVec = builder.createVector([UInt8](repeating: 0, count: cortexChannelDataByteCount - 2))
    let root = Cortex_IPC_Sample.createSample(&builder, tsNs: 1, channelDataVectorOffset: shortVec, seq: 2)
    builder.finish(offset: root)
    let bytes = builder.sizedByteArray

    #expect(throws: SampleCodecError.badChannelCount(cortexChannelDataByteCount - 2)) {
      _ = try SampleCodec.decode(bytes)
    }
  }

  @Test("decode rejects a truncated/garbage buffer via the FlatBuffers verifier (getCheckedRoot)")
  func decodeRejectsGarbage() throws {
    // First build a valid frame, then truncate it so the verifier's offsets run past the end.
    let valid = try SampleCodec.encode(tsNs: 1, seq: 1, channels: Self.makeChannels())
    let truncated = Array(valid.prefix(valid.count / 2))
    #expect(throws: SampleCodecError.malformedBuffer) {
      _ = try SampleCodec.decode(truncated)
    }

    // Pure garbage bytes are also rejected (not a valid root offset / table).
    let garbage: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
    #expect(throws: SampleCodecError.malformedBuffer) {
      _ = try SampleCodec.decode(garbage)
    }
  }
}
