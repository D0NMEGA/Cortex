@testable import CortexDecoder

// DEC-11 (histogram math) — pure percentile / p50 / p99 / JSON round-trip tests.
//
// These tests need NO model and NO CoreML: `LatencyHistogram` is a pure Sendable value type, so
// the percentile math is deterministic and always runs green in a clean clone / CI. The actual
// 10k-pass timing lives in the `CortexDecoderBench` EXECUTABLE (run manually + on the iPad), NOT
// in this `swift test` suite — CI must not carry a flaky latency gate (D-18 / 05-RESEARCH
// Decision 5). Only the math below is unit-tested.
//
// Percentile convention (documented): NEAREST-RANK — rank = ceil(p * n), clamped to [1, n],
// value = sorted[rank - 1]. For the known array 1...100 (n = 100):
//   • p50 -> ceil(50) = 50 -> sorted[49] = 50
//   • p99 -> ceil(99) = 99 -> sorted[98] = 99
//   • p0  -> clamp rank to 1 -> sorted[0]  = 1   (min)
//   • p1.0 -> ceil(100) = 100 -> sorted[99] = 100 (max)
import Foundation
import Testing

@Suite("DEC-11: LatencyHistogram pure percentile math (no model)")
struct LatencyHistogramTests {
  /// The canonical known distribution: 1...100 ns. Hand-computable percentiles.
  private static let oneToHundred: [UInt64] = Array(1 ... 100)

  @Test
  func `percentile(0.5) is the median (nearest-rank: 50) on 1...100`() {
    let hist = LatencyHistogram(samplesNs: Self.oneToHundred, deviceAnnotation: "test")
    #expect(hist.percentile(0.5) == 50)
    #expect(hist.p50 == 50)
  }

  @Test
  func `percentile(0.99) is the 99th (nearest-rank: 99) on 1...100`() {
    let hist = LatencyHistogram(samplesNs: Self.oneToHundred, deviceAnnotation: "test")
    #expect(hist.percentile(0.99) == 99)
    #expect(hist.p99 == 99)
  }

  @Test
  func `percentile clamps p to [0, 1]: 0.0 -> min, 1.0 -> max, out-of-range clamps`() {
    let hist = LatencyHistogram(samplesNs: Self.oneToHundred, deviceAnnotation: "test")
    #expect(hist.percentile(0.0) == 1) // min
    #expect(hist.percentile(1.0) == 100) // max
    #expect(hist.min == 1)
    #expect(hist.max == 100)
    // Out-of-range probabilities clamp rather than crash or return garbage.
    #expect(hist.percentile(-0.5) == 1)
    #expect(hist.percentile(1.5) == 100)
  }

  @Test
  func `an unsorted input is sorted internally before percentile`() {
    let hist = LatencyHistogram(samplesNs: [100, 1, 50, 2, 99], deviceAnnotation: "test")
    #expect(hist.min == 1)
    #expect(hist.max == 100)
    #expect(hist.count == 5)
    // nearest-rank p50 over n=5: ceil(0.5*5)=3 -> sorted[2] = 50
    #expect(hist.percentile(0.5) == 50)
  }

  @Test
  func `an empty sample set returns nil percentiles (explicit, not a crash)`() {
    let hist = LatencyHistogram(samplesNs: [], deviceAnnotation: "empty")
    #expect(hist.count == 0)
    #expect(hist.percentileOrNil(0.5) == nil)
    #expect(hist.percentileOrNil(0.99) == nil)
    #expect(hist.minOrNil == nil)
    #expect(hist.maxOrNil == nil)
    // The non-optional convenience accessors return 0 (a safe sentinel) on empty, never crash.
    #expect(hist.percentile(0.5) == 0)
    #expect(hist.p99 == 0)
  }

  @Test
  func `JSON encode round-trips count, p50, p99, min, max, and deviceAnnotation`() throws {
    let hist = LatencyHistogram(samplesNs: Self.oneToHundred, deviceAnnotation: "NeuralEngine")
    let data = try hist.encodedJSON()
    let decoded = try JSONDecoder().decode(LatencyHistogram.Summary.self, from: data)
    #expect(decoded.count == 100)
    #expect(decoded.p50_ns == 50)
    #expect(decoded.p99_ns == 99)
    #expect(decoded.min_ns == 1)
    #expect(decoded.max_ns == 100)
    #expect(decoded.deviceAnnotation == "NeuralEngine")
  }

  @Test
  func `the histogram value type is Sendable and survives a Codable round-trip itself`() throws {
    let hist = LatencyHistogram(samplesNs: [10, 20, 30], deviceAnnotation: "CPU")
    let data = try JSONEncoder().encode(hist)
    let decoded = try JSONDecoder().decode(LatencyHistogram.self, from: data)
    #expect(decoded.count == 3)
    #expect(decoded.deviceAnnotation == "CPU")
    #expect(decoded.percentile(0.5) == 20)
  }
}
