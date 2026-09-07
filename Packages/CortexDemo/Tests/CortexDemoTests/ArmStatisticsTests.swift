// ArmStatisticsTests - Phase 10 (RD-07, Plan 10-05): the per-arm gain and smoothing statistics that
// make the Willett confound MEASURABLE rather than assumed away.
//
// Every case here is a closed-form check on a hand-computable input, so a wrong divisor or a missing
// guard fails rather than merely looking plausible. The degenerate cases are the point: a non-finite
// statistic propagating into a committed JSON is the failure mode these functions exist to prevent
// (T-10-05-05), and an empty or zero-denominator arm is exactly what a floored real-data run
// produces.
@testable import CortexDemo
import simd
import Testing

@Suite("RD-07: ArmStatistics - realized gain and realized smoothing")
struct ArmStatisticsTests {
  /// Absolute tolerance for the Double comparisons. The arithmetic is a handful of adds and one
  /// divide, so 1e-12 is far above the float64 rounding floor and far below any real difference.
  private static let tol = 1e-12

  // MARK: - realizedGain

  @Test
  func `realizedGain of a sequence against itself is exactly 1`() {
    let v: [SIMD2<Float>] = [
      SIMD2<Float>(0.3, 0.4), // |v| = 0.5
      SIMD2<Float>(-1.0, 0.0),
      SIMD2<Float>(0.0, 2.5)
    ]
    #expect(abs(ArmStatistics.realizedGain(inputs: v, outputs: v) - 1.0) < Self.tol)
  }

  @Test
  func `realizedGain of outputs scaled by 2 is exactly 2`() {
    let inputs: [SIMD2<Float>] = [
      SIMD2<Float>(0.3, 0.4),
      SIMD2<Float>(-1.0, 0.0),
      SIMD2<Float>(0.0, 2.5)
    ]
    let outputs = inputs.map { $0 * 2 }
    #expect(abs(ArmStatistics.realizedGain(inputs: inputs, outputs: outputs) - 2.0) < 1e-6)
  }

  @Test
  func `realizedGain returns 0 for an all-zero input rather than NaN or infinity`() {
    let zeros = [SIMD2<Float>](repeating: SIMD2<Float>(0, 0), count: 4)
    let outputs: [SIMD2<Float>] = [
      SIMD2<Float>(1, 0), SIMD2<Float>(0, 1), SIMD2<Float>(1, 1), SIMD2<Float>(2, 2)
    ]
    let gain = ArmStatistics.realizedGain(inputs: zeros, outputs: outputs)
    #expect(gain == 0)
    #expect(gain.isFinite)
  }

  @Test
  func `realizedGain returns 0 for empty inputs without crashing`() {
    let empty = [SIMD2<Float>]()
    let gain = ArmStatistics.realizedGain(inputs: empty, outputs: empty)
    #expect(gain == 0)
    #expect(gain.isFinite)
  }

  @Test
  func `realizedGain stays finite when one sample is the zero vector`() {
    let inputs: [SIMD2<Float>] = [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0, 3)]
    let outputs: [SIMD2<Float>] = [SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(0, 1.5)]
    let gain = ArmStatistics.realizedGain(inputs: inputs, outputs: outputs)
    #expect(gain.isFinite)
    // mean(|out|) = (0 + 0.5 + 1.5)/3, mean(|in|) = (0 + 1 + 3)/3 => exactly 0.5.
    #expect(abs(gain - 0.5) < 1e-6)
  }

  // MARK: - realizedSmoothing

  @Test
  func `realizedSmoothing of a constant speed series is 0, not NaN`() {
    let constant = [SIMD2<Float>](repeating: SIMD2<Float>(0.6, 0.8), count: 16) // |v| = 1 every tick
    let smoothing = ArmStatistics.realizedSmoothing(outputs: constant)
    #expect(smoothing == 0)
    #expect(smoothing.isFinite)
  }

  @Test
  func `realizedSmoothing of an alternating speed series is about -1`() {
    // Speeds alternate 1, 2, 1, 2, ... so consecutive samples sit on opposite sides of the mean.
    var series = [SIMD2<Float>]()
    for i in 0 ..< 64 {
      series.append(SIMD2<Float>(i.isMultiple(of: 2) ? 1.0 : 2.0, 0))
    }
    let smoothing = ArmStatistics.realizedSmoothing(outputs: series)
    #expect(smoothing < -0.95, "alternating speeds should give a lag-1 autocorrelation near -1; got \(smoothing)")
    #expect(smoothing >= -1.0000001)
  }

  @Test
  func `realizedSmoothing of a slowly varying series is close to +1`() {
    // A slow ramp: consecutive speeds are almost equal, so the lag-1 autocorrelation is near +1.
    var series = [SIMD2<Float>]()
    for i in 0 ..< 128 {
      series.append(SIMD2<Float>(Float(i) * 0.01, 0))
    }
    let smoothing = ArmStatistics.realizedSmoothing(outputs: series)
    #expect(smoothing > 0.95, "a slow ramp should give a lag-1 autocorrelation near +1; got \(smoothing)")
    #expect(smoothing <= 1.0000001)
  }

  @Test
  func `realizedSmoothing returns 0 for an empty series without crashing`() {
    let smoothing = ArmStatistics.realizedSmoothing(outputs: [])
    #expect(smoothing == 0)
    #expect(smoothing.isFinite)
  }

  @Test
  func `realizedSmoothing returns 0 for a single sample (no lag-1 pair exists)`() {
    let smoothing = ArmStatistics.realizedSmoothing(outputs: [SIMD2<Float>(1, 1)])
    #expect(smoothing == 0)
    #expect(smoothing.isFinite)
  }

  @Test
  func `realizedSmoothing stays finite and bounded on a series containing a zero vector`() {
    let series: [SIMD2<Float>] = [
      SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0, 0), SIMD2<Float>(0, 2), SIMD2<Float>(0, 0)
    ]
    let smoothing = ArmStatistics.realizedSmoothing(outputs: series)
    #expect(smoothing.isFinite)
    #expect(smoothing >= -1.0000001 && smoothing <= 1.0000001)
  }

  // MARK: - The published-artifact guarantee

  @Test
  func `both statistics are finite for every degenerate shape a floored arm can produce`() {
    let shapes: [[SIMD2<Float>]] = [
      [],
      [SIMD2<Float>(0, 0)],
      [SIMD2<Float>(0, 0), SIMD2<Float>(0, 0)],
      [SIMD2<Float>(0, 0), SIMD2<Float>(0, 0), SIMD2<Float>(0, 0)],
      [SIMD2<Float>(1e-30, 0), SIMD2<Float>(0, 1e-30)]
    ]
    for shape in shapes {
      let gain = ArmStatistics.realizedGain(inputs: shape, outputs: shape)
      let smoothing = ArmStatistics.realizedSmoothing(outputs: shape)
      #expect(gain.isFinite, "gain was not finite for a \(shape.count)-sample degenerate arm")
      #expect(smoothing.isFinite, "smoothing was not finite for a \(shape.count)-sample degenerate arm")
    }
  }
}
