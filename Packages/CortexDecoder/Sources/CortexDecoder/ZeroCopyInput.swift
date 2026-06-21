// ZeroCopyInput — the DEC-09 zero-copy spike input path.
//
// 05-RESEARCH Decision 3: spikes enter Core ML with NO host copy via
//   MLMultiArray(pixelBuffer:shape:)   over an IOSurface-backed CVPixelBuffer
// whose pixel format is `kCVPixelFormatType_OneComponent16Half` (fp16). The SAME IOSurface
// also backs an `MTLBuffer` created with `storageModeShared` (`bytesNoCopy`), so the
// renderer/IPC side writes spikes into unified memory and Core ML / the ANE reads them
// over the shared surface — one allocation, zero host-side memcpy.
//
// Apple's `MLMultiArray(pixelBuffer:shape:)` "reduces inference latency by avoiding the
// buffer copy to and from some compute units"; it requires OneComponent16Half, yields a
// `.float16` array, and constrains `shape.last == pixelBuffer.width`, `product(rest) == height`
// (Context7 / developer.apple.com). The spike input is `(1, 96, 1, S)` fp16 per the Plan-01
// contract, so width = S (the time axis), height = 96 (channels), and the array shape is
// `[96, S]` (product of the leading dims == height == 96).
//
// Risk #3 (05-RESEARCH): `CVPixelBufferGetBytesPerRow` may exceed `width * 2` (row padding to
// a hardware alignment). All element writes go through `bytesPerRow`, never `width * 2`.
import CoreML
import CoreVideo
import IOSurface
import Metal

/// Errors raised while constructing the shared-surface spike buffer. Typed so every fallible
/// CoreVideo/Metal/IOSurface call fails closed with a clear cause — no force-unwrap on the
/// create paths (threat T-05-03-05).
public enum ZeroCopyInputError: Error, Sendable {
  /// `CVPixelBufferCreate` returned a non-success `CVReturn`.
  case pixelBufferCreateFailed(status: CVReturn)
  /// The created CVPixelBuffer had no backing IOSurface (IOSurface property not honored).
  case missingIOSurface
  /// `MTLDevice.makeBuffer(bytesNoCopy:…)` returned nil over the shared surface.
  case sharedBufferCreateFailed
  /// A row/column index was out of the configured `(channels, seqLen)` bounds.
  case indexOutOfRange(row: Int, column: Int)
  /// `MLMultiArray(pixelBuffer:shape:)` threw while wrapping the surface.
  case multiArrayCreateFailed(underlying: String)
}

/// One IOSurface shared between a `OneComponent16Half` `CVPixelBuffer` and a `storageModeShared`
/// `MTLBuffer`, yielding an `MLMultiArray` over the SAME surface with no host copy (DEC-09).
///
/// The buffer owns the surface for the lifetime of inference: the `MTLBuffer` is created with
/// `bytesNoCopy` over the surface base address, so this object MUST outlive any `MLMultiArray`
/// it produces (05-RESEARCH Decision 3 — "the MTLBuffer must outlive the MLMultiArray").
public final class SpikeInputBuffer {
  /// Number of recording channels (the CVPixelBuffer height). `(1, channels, 1, seqLen)` fp16.
  public let channels: Int
  /// Number of 20ms time bins in the window (the CVPixelBuffer width).
  public let seqLen: Int
  /// Bytes per row of the backing surface. May exceed `seqLen * 2` due to alignment padding
  /// (Risk #3); element writes use this stride, never `seqLen * 2`.
  public let bytesPerRow: Int

  /// The IOSurface-backed pixel buffer Core ML wraps zero-copy.
  public let pixelBuffer: CVPixelBuffer
  /// The IOSurface shared by `pixelBuffer` and `metalBuffer` (retained for the buffer's lifetime).
  public let surface: IOSurfaceRef
  /// The Metal buffer over the SAME surface (`storageModeShared`, `bytesNoCopy`) — the renderer/
  /// IPC write target. Retained so the surface stays alive while an `MLMultiArray` references it.
  public let metalBuffer: MTLBuffer

  /// Base address of the shared surface — the single physical home of the spike bytes. The
  /// `MLMultiArray.dataPointer`, `metalBuffer.contents()`, and `CVPixelBufferGetBaseAddress`
  /// all resolve to this address (the pointer-identity proof, DEC-09).
  public var baseAddress: UnsafeMutableRawPointer { IOSurfaceGetBaseAddress(surface) }

  /// Creates the shared surface + buffers.
  /// - Parameters:
  ///   - device: the Metal device (unified memory on Apple Silicon — one allocation is shared).
  ///   - seqLen: number of 20ms time bins (CVPixelBuffer width). Must be > 0.
  ///   - channels: recording channels (CVPixelBuffer height); defaults to the 96-channel contract.
  public init(device: MTLDevice, seqLen: Int, channels: Int = CortexDecoder.channelCount) throws(ZeroCopyInputError) {
    precondition(seqLen > 0 && channels > 0, "SpikeInputBuffer requires positive dimensions")
    self.seqLen = seqLen
    self.channels = channels

    // 1. IOSurface-backed CVPixelBuffer, fp16 single-component, width = S, height = channels.
    var pb: CVPixelBuffer?
    let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      seqLen,
      channels,
      kCVPixelFormatType_OneComponent16Half,
      attrs as CFDictionary,
      &pb
    )
    guard status == kCVReturnSuccess, let pixelBuffer = pb else {
      throw .pixelBufferCreateFailed(status: status)
    }
    self.pixelBuffer = pixelBuffer

    // 2. The backing IOSurface (retained for the buffer's lifetime).
    guard let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
      throw .missingIOSurface
    }
    self.surface = surfaceRef
    self.bytesPerRow = IOSurfaceGetBytesPerRow(surfaceRef)

    // 3. MTLBuffer over the SAME surface base address — storageModeShared, bytesNoCopy. On unified
    //    memory this shares ONE allocation with the CVPixelBuffer (no copy). The IOSurface base
    //    address is page-aligned and its allocation size is page-multiple, satisfying
    //    makeBuffer(bytesNoCopy:)'s alignment contract.
    let allocSize = IOSurfaceGetAllocSize(surfaceRef)
    let base = IOSurfaceGetBaseAddress(surfaceRef)
    guard let buffer = device.makeBuffer(
      bytesNoCopy: base,
      length: allocSize,
      options: .storageModeShared,
      deallocator: nil
    ) else {
      throw .sharedBufferCreateFailed
    }
    self.metalBuffer = buffer
  }

  /// Wraps the shared surface as an `MLMultiArray` with NO host copy — the documented
  /// IOSurface-backed initializer (05-RESEARCH Decision 3). Shape is `[channels, seqLen]`
  /// (`shape.last == pixelBuffer.width == seqLen`; `product(rest) == height == channels`); the
  /// data type is inferred `.float16` from the OneComponent16Half format.
  ///
  /// The returned array's `dataPointer` equals ``baseAddress`` — proven by the pointer-identity
  /// test (DEC-09). It is NOT constructed from a Swift `[Float]`/`[Float16]` value initializer.
  public func makeMultiArray() throws(ZeroCopyInputError) -> MLMultiArray {
    do {
      return try MLMultiArray(
        pixelBuffer: pixelBuffer,
        shape: [channels as NSNumber, seqLen as NSNumber]
      )
    } catch {
      throw .multiArrayCreateFailed(underlying: String(describing: error))
    }
  }

  /// Writes a single fp16 spike count into `(channel, bin)` through the shared `MTLBuffer`,
  /// respecting `bytesPerRow` row padding (Risk #3). Visible at the CVPixelBuffer base address
  /// and to the ANE — no copy.
  public func write(_ value: Float16, channel: Int, bin: Int) throws(ZeroCopyInputError) {
    guard channel >= 0, channel < channels, bin >= 0, bin < seqLen else {
      throw .indexOutOfRange(row: channel, column: bin)
    }
    let rowBase = baseAddress.advanced(by: channel * bytesPerRow)
    rowBase.advanced(by: bin * MemoryLayout<Float16>.stride)
      .assumingMemoryBound(to: Float16.self).pointee = value
  }

  /// Reads back the fp16 value at `(channel, bin)` from the shared surface (test/diagnostic
  /// helper), respecting `bytesPerRow`.
  public func read(channel: Int, bin: Int) throws(ZeroCopyInputError) -> Float16 {
    guard channel >= 0, channel < channels, bin >= 0, bin < seqLen else {
      throw .indexOutOfRange(row: channel, column: bin)
    }
    let rowBase = baseAddress.advanced(by: channel * bytesPerRow)
    return rowBase.advanced(by: bin * MemoryLayout<Float16>.stride)
      .assumingMemoryBound(to: Float16.self).pointee
  }
}
