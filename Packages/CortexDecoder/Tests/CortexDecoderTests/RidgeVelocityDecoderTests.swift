// RidgeVelocityDecoderTests — parity with the Python fit, and refusal of a malformed blob.
//
// The risk this suite exists for is not a crash. A ridge decode that reads its weights in the wrong
// order, or off by one field, still returns two plausible-looking numbers and drives a cursor that
// looks like it is working. Nothing downstream would notice. So the load path and the feature order
// are pinned against a value computed by the exporter itself.
@testable import CortexDecoder
import Foundation
import simd
import Testing

@Suite("RidgeVelocityDecoder: parity with the exported fit")
@MainActor
struct RidgeVelocityDecoderTests {
  /// The exporter's `self_check`, recomputed here from the same rule. Committed in
  /// `ridge_velocity_k32.json`; if these drift apart, one of the two changed and the decoder the app
  /// runs is no longer the decoder that was measured.
  static let expectedVx: Float = 1.7763086314945753
  static let expectedVy: Float = 2.200316870271224

  @Test("the shipped blob loads with the fit's shape")
  func loadsShippedWeights() throws {
    let decoder = try RidgeVelocityDecoder()
    #expect(decoder.historyBins == 32, "the like-for-like history: the encoder's whole 32-bin window")
    #expect(decoder.channels == 96)
    #expect(decoder.featureCount == 3072)
  }

  @Test("decoding the exporter's probe window reproduces its numbers")
  func matchesThePythonSelfCheck() throws {
    let decoder = try RidgeVelocityDecoder()
    // The exporter's rule, verbatim: feature i = ((i % 7) - 3) / 4, bin-major over the whole window.
    // Not uniform within a bin, and spanning both signs, so a transposed or shifted read of the
    // weights lands on a different answer instead of coincidentally agreeing.
    let probe = (0 ..< decoder.featureCount).map { Float16((Float($0 % 7) - 3.0) / 4.0) }
    let out = try #require(decoder.decode(window: probe))
    // Tolerance is set by the blob's float32 storage and the Float16 window, not by the fit.
    #expect(abs(out.x - Self.expectedVx) < 2e-3, "vx \(out.x) vs Python \(Self.expectedVx)")
    #expect(abs(out.y - Self.expectedVy) < 2e-3, "vy \(out.y) vs Python \(Self.expectedVy)")
  }

  @Test("a wrong-length window is refused rather than decoded from a prefix")
  func refusesAWrongLengthWindow() throws {
    let decoder = try RidgeVelocityDecoder()
    #expect(decoder.decode(window: [Float16](repeating: 0, count: 3071)) == nil)
    #expect(decoder.decode(window: [Float16](repeating: 0, count: 3073)) == nil)
    #expect(decoder.decode(window: []) == nil)
  }

  @Test("an all-zero window returns the fit's bias")
  func zeroWindowReturnsBias() throws {
    let decoder = try RidgeVelocityDecoder()
    let out = try #require(decoder.decode(window: [Float16](repeating: 0, count: decoder.featureCount)))
    // The ridge is centered, so the bias is the pooled train-mean velocity. It must be a small
    // number of cm/s, not a decoded-looking value: a nonzero here would mean the header offset is
    // wrong and the "bias" is actually a weight.
    #expect(abs(out.x) < 5.0 && abs(out.y) < 5.0, "bias \(out) is not a plausible mean velocity")
  }

  @Test("a truncated or mislabelled blob is refused, never partially read")
  func refusesMalformedBlobs() {
    func blob(_ floats: [Float]) -> Data {
      floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
    #expect(throws: RidgeDecoderError.self) { try RidgeVelocityDecoder(bytes: blob([1, 32, 96])) }
    // Right header, body one float short.
    let short = [Float(1), 2, 2, 0] + [Float](repeating: 0.5, count: 2 * 2 * 2 - 1) + [0, 0]
    #expect(throws: RidgeDecoderError.self) { try RidgeVelocityDecoder(bytes: blob(short)) }
    // A future schema must be refused, not read as if it were this one.
    let future = [Float(2), 2, 2, 0] + [Float](repeating: 0.5, count: 2 * 2 * 2) + [0, 0]
    #expect(throws: RidgeDecoderError.self) { try RidgeVelocityDecoder(bytes: blob(future)) }
    // An implausible shape (zero channels) must not divide the body into nothing and pass.
    let degenerate = [Float(1), 32, 0, 0] + [Float](repeating: 0, count: 2)
    #expect(throws: RidgeDecoderError.self) { try RidgeVelocityDecoder(bytes: blob(degenerate)) }
  }
}
