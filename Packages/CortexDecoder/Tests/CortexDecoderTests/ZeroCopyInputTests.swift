// DEC-09 — zero-copy spike input: pointer-identity + shared-memory round-trip.
//
// Proves the spike `MLMultiArray` is constructed OVER the shared IOSurface (no host copy):
//   1. writing through the MTLBuffer.contents() pointer is visible at the CVPixelBuffer base
//      address (one shared allocation);
//   2. MLMultiArray(pixelBuffer:).dataPointer == the surface/pixel-buffer base address
//      (the array points AT the surface, not a copy) — the DEC-09 assertion;
//   3. a known fp16 pattern written via the MTLBuffer reads back through the MLMultiArray,
//      accounting for CVPixelBufferGetBytesPerRow row padding (Risk #3).
//
// Guarded on `MTLCreateSystemDefaultDevice()`: CI macos-15 runners have a Metal device, but the
// suite skips cleanly (returns) if one is absent rather than crashing.
import CoreVideo
import Metal
import Testing

@testable import CortexDecoder

@Suite("DEC-09: zero-copy spike input over a shared IOSurface")
@MainActor
struct ZeroCopyInputTests {
  /// Channels per the Plan-01 contract; a small seqLen keeps the surface tiny.
  private static let channels = 96
  private static let seqLen = 8

  /// Builds a SpikeInputBuffer on the default device, or `nil` if no Metal device exists.
  private func makeBuffer() throws -> SpikeInputBuffer? {
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    return try SpikeInputBuffer(device: device, seqLen: Self.seqLen, channels: Self.channels)
  }

  @Test("MTLBuffer and CVPixelBuffer share one allocation (write via Metal, read via CV base)")
  func sharedAllocationIsVisibleAcrossBackings() throws {
    guard let buf = try makeBuffer() else { return }  // no Metal device — skip cleanly

    // Write a sentinel directly through the MTLBuffer.contents() pointer at (channel 0, bin 0).
    let metalPtr = buf.metalBuffer.contents()
    metalPtr.assumingMemoryBound(to: Float16.self).pointee = Float16(3.5)

    // The same byte must be visible at the CVPixelBuffer base address (shared memory).
    CVPixelBufferLockBaseAddress(buf.pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buf.pixelBuffer, .readOnly) }
    let cvBase = try #require(CVPixelBufferGetBaseAddress(buf.pixelBuffer))
    let seen = cvBase.assumingMemoryBound(to: Float16.self).pointee
    #expect(seen == Float16(3.5))

    // And the MTLBuffer.contents() pointer IS the surface base address (one allocation).
    #expect(metalPtr == buf.baseAddress)
  }

  @Test("MLMultiArray(pixelBuffer:).dataPointer == surface base address (no host copy)")
  func multiArrayPointsAtSharedSurface() throws {
    guard let buf = try makeBuffer() else { return }  // no Metal device — skip cleanly

    let array = try buf.makeMultiArray()

    // DEC-09: the array's data pointer is the shared surface base address, NOT a copied buffer.
    #expect(array.dataPointer == buf.baseAddress)
    // It is also the CVPixelBuffer base address (the surface IS the pixel buffer's storage).
    CVPixelBufferLockBaseAddress(buf.pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buf.pixelBuffer, .readOnly) }
    let cvBase = try #require(CVPixelBufferGetBaseAddress(buf.pixelBuffer))
    #expect(array.dataPointer == cvBase)

    // fp16 dtype is inferred from OneComponent16Half.
    #expect(array.dataType == .float16)
  }

  @Test("round-trip a known fp16 pattern: write via MTLBuffer, read back via MLMultiArray")
  func roundTripPatternThroughMultiArray() throws {
    guard let buf = try makeBuffer() else { return }  // no Metal device — skip cleanly

    // Write a distinct value to a diagonal of (channel, bin) cells through the typed write helper
    // (which respects bytesPerRow padding, Risk #3).
    let probes: [(ch: Int, bin: Int, val: Float16)] = [
      (0, 0, 1.0), (1, 2, 2.5), (5, 7, -3.25), (Self.channels - 1, Self.seqLen - 1, 7.5),
    ]
    for p in probes { try buf.write(p.val, channel: p.ch, bin: p.bin) }

    // Read back through the MLMultiArray using its own strides (it shares the surface, so the
    // padded row stride is reflected in array.strides — element [ch, bin] resolves correctly).
    let array = try buf.makeMultiArray()
    let base = array.dataPointer.assumingMemoryBound(to: Float16.self)
    let rowStride = array.strides[0].intValue  // elements per row (accounts for bytesPerRow padding)
    let colStride = array.strides[1].intValue
    for p in probes {
      let element = base[p.ch * rowStride + p.bin * colStride]
      #expect(element == p.val, "mismatch at (\(p.ch), \(p.bin))")
    }
  }

  @Test("bytesPerRow is at least the unpadded fp16 row width (Risk #3 surfaced)")
  func bytesPerRowAccountsForPadding() throws {
    guard let buf = try makeBuffer() else { return }  // no Metal device — skip cleanly
    #expect(buf.bytesPerRow >= Self.seqLen * MemoryLayout<Float16>.stride)
  }

  @Test("rank-4 model-input view: (1,C,1,S) shape, same surface pointer (no host copy)")
  func modelInputMultiArrayIsRank4AndZeroCopy() throws {
    guard let buf = try makeBuffer() else { return }  // no Metal device — skip cleanly

    let array = try buf.makeModelInputMultiArray()

    // The model's `spikes` input is rank-4 BC1S `(1, channels, 1, seqLen)` (Plan-01/04 contract).
    #expect(array.shape.map(\.intValue) == [1, Self.channels, 1, Self.seqLen])
    #expect(array.dataType == .float16)
    // STILL zero-copy: the rank-4 view points AT the shared surface base, not a copy (DEC-09).
    #expect(array.dataPointer == buf.baseAddress)
  }

  @Test("rank-4 view round-trips a known fp16 pattern via its (1,C,1,S) strides")
  func modelInputMultiArrayRoundTripsPattern() throws {
    guard let buf = try makeBuffer() else { return }  // no Metal device — skip cleanly

    let probes: [(ch: Int, bin: Int, val: Float16)] = [
      (0, 0, 1.0), (3, 1, 4.5), (Self.channels - 1, Self.seqLen - 1, -2.5),
    ]
    for p in probes { try buf.write(p.val, channel: p.ch, bin: p.bin) }

    // Read back through the rank-4 view's own strides: index [0, ch, 0, bin] resolves via
    // strides[channel] (padded row) + strides[time] (contiguous). Proves the rank-4 view addresses
    // the same surface bytes the write helper wrote (the real inference-path read).
    let array = try buf.makeModelInputMultiArray()
    let base = array.dataPointer.assumingMemoryBound(to: Float16.self)
    let channelStride = array.strides[1].intValue
    let timeStride = array.strides[3].intValue
    for p in probes {
      let element = base[p.ch * channelStride + p.bin * timeStride]
      #expect(element == p.val, "mismatch at (\(p.ch), \(p.bin))")
    }
  }

  @Test("out-of-range write fails closed (no force-unwrap crash)")
  func writeOutOfRangeThrows() throws {
    guard let buf = try makeBuffer() else { return }  // no Metal device — skip cleanly
    #expect(throws: ZeroCopyInputError.self) {
      try buf.write(1.0, channel: Self.channels, bin: 0)
    }
  }
}
