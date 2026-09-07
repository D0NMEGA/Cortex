// LatencyHistogram — the DEC-11 latency summary value type.
//
// A PURE, Sendable value type with NO CoreML / Metal dependency, so its percentile math is unit-
// tested deterministically with no model (05-RESEARCH Decision 5: p50/p99 over the 10k-pass
// sample array; commit the `latency_histogram.{json}` artifact). The CortexDecoderBench executable
// fills it from the per-call nanoseconds it measures in-process and tags it with the device the
// ops actually ran on (`deviceAnnotation`: "NeuralEngine" / "CPU" / "mixed" / "unknown-mac").
//
// The venue split lives in that annotation: a Mac measurement may CPU-place the 1.29M-param model
// (the scale trap, 05-RESEARCH Risk #1), so the annotation is what makes a Mac number CORROBORATING
// rather than the canonical iPad-M4 ANE claim. The type itself never gates on <2ms — it only
// records and encodes.
//
// Percentile convention: NEAREST-RANK. rank = ceil(p * n), clamped to [1, n]; value = sorted[rank-1].
// `p` is clamped to [0, 1] (so 0.0 -> min, 1.0 -> max). An empty sample set returns nil from the
// throwing-free optional accessors and 0 from the non-optional conveniences — never a crash
// (threat T-05-04-03: no force-unwrap / no precondition trap on empty input).
//
// Imports Foundation only (for JSONEncoder); it deliberately does NOT pull in the Core ML module,
// which keeps the type model-free and unit-testable with no compiled model present.
import Foundation

/// A latency distribution over per-call nanoseconds: stores the sorted samples, exposes p50/p99
/// (nearest-rank), and JSON-encodes a compact summary tagged with the device the ops ran on.
///
/// `nonisolated` value type: the CortexDecoder library sets `.defaultIsolation(MainActor.self)`,
/// but this is pure data + pure math with no main-actor state, so it is explicitly isolation-free
/// to cross isolation boundaries freely (the bench builds it, tests read it synchronously, and a
/// future hot-path caller can use it without an actor hop). `Sendable`; no global mutable state.
public nonisolated struct LatencyHistogram: Codable, Sendable {
  /// The per-call latency samples in nanoseconds, kept SORTED ascending (sorted at init).
  public let samplesNs: [UInt64]

  /// The device the ops actually ran on, summarized from the compute plan by the bench:
  /// `"NeuralEngine"` / `"CPU"` / `"mixed"` / `"unknown-mac"`. This is WHY a Mac number is
  /// corroborating, not the canonical iPad-M4 ANE claim (05-RESEARCH Decision 5 / Risk #1).
  public let deviceAnnotation: String

  /// Creates a histogram from raw (possibly unsorted) ns samples; sorts them ascending once.
  public init(samplesNs: [UInt64], deviceAnnotation: String) {
    self.samplesNs = samplesNs.sorted()
    self.deviceAnnotation = deviceAnnotation
  }

  /// Number of samples.
  public var count: Int {
    samplesNs.count
  }

  /// Whether the histogram holds no samples. Present so callers can say `isEmpty` rather than
  /// `count == 0`, which is what SwiftLint's `empty_count` rule asks for at the call site.
  public var isEmpty: Bool {
    samplesNs.isEmpty
  }

  // MARK: - Optional (empty-safe) accessors

  /// The minimum sample, or nil if empty.
  public var minOrNil: UInt64? {
    samplesNs.first
  }

  /// The maximum sample, or nil if empty.
  public var maxOrNil: UInt64? {
    samplesNs.last
  }

  /// The nearest-rank percentile for `p` in [0, 1], or nil if the sample set is empty.
  ///
  /// `p` is clamped to [0, 1]. rank = ceil(p * n) clamped to [1, n]; returns `sorted[rank - 1]`,
  /// so `p == 0` yields the min and `p == 1` yields the max.
  public func percentileOrNil(_ p: Double) -> UInt64? {
    guard !samplesNs.isEmpty else { return nil }
    let clamped = Swift.min(1.0, Swift.max(0.0, p))
    let n = samplesNs.count
    // ceil(clamped * n), then clamp the 1-based rank into [1, n].
    let rank = Int((clamped * Double(n)).rounded(.up))
    let index = Swift.min(n - 1, Swift.max(0, rank - 1))
    return samplesNs[index]
  }

  // MARK: - Non-optional conveniences (0 sentinel on empty, never crash)

  /// The minimum sample, or 0 if empty.
  public var min: UInt64 {
    minOrNil ?? 0
  }

  /// The maximum sample, or 0 if empty.
  public var max: UInt64 {
    maxOrNil ?? 0
  }

  /// The nearest-rank percentile for `p` in [0, 1], or 0 if empty. See ``percentileOrNil(_:)``.
  public func percentile(_ p: Double) -> UInt64 {
    percentileOrNil(p) ?? 0
  }

  /// The median (50th percentile), or 0 if empty.
  public var p50: UInt64 {
    percentile(0.5)
  }

  /// The 99th percentile, or 0 if empty.
  public var p99: UInt64 {
    percentile(0.99)
  }

  // MARK: - JSON summary

  /// The compact, committed-evidence shape: `{count, p50_ns, p99_ns, min_ns, max_ns, deviceAnnotation}`.
  /// Snake-case ns fields match the latency_histogram.json artifact the evidence doc transcribes.
  public struct Summary: Codable, Sendable {
    public let count: Int
    public let p50_ns: UInt64
    public let p99_ns: UInt64
    public let min_ns: UInt64
    public let max_ns: UInt64
    public let deviceAnnotation: String
  }

  /// The summary snapshot (percentiles computed once).
  public var summary: Summary {
    Summary(
      count: count,
      p50_ns: p50,
      p99_ns: p99,
      min_ns: min,
      max_ns: max,
      deviceAnnotation: deviceAnnotation
    )
  }

  /// Encodes the ``summary`` to pretty-printed JSON — the committed `latency_histogram.json` body.
  public func encodedJSON() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(summary)
  }
}
