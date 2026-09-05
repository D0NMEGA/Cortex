// ArmStatistics - Phase 10 (RD-07, Plan 10-05): per-arm realized gain and realized smoothing.
//
// A stateless value namespace in the style of `WebgridBPS`: every function is a closed-form
// transform of its inputs, deterministic, no I/O, no state. It exists so the four-arm real-data
// ablation can report the two quantities that decide whether an arm-to-arm delta is attributable at
// all, rather than assuming they are equal across arms.
//
// ## Every return is guarded
// A zero denominator returns 0 and every value is checked with `.isFinite` before it leaves the
// function. This is not defensive decoration: these numbers are written straight into a committed
// artifact, and a floored real-data arm (zero hits, a vanishingly small decoded speed, a constant
// output series with zero variance) produces exactly the degenerate shapes that would otherwise emit
// a NaN into published evidence. `ArmStatisticsTests` drives each of those shapes.
import simd

/// Per-arm gain and smoothing, so the RD-07 ablation MEASURES the Willett confound rather than
/// assuming it away. Willett et al. 2017, IEEE TBME 65(9):2066-2078,
/// DOI 10.1109/TBME.2017.2783358: using BrainGate2 pilot clinical trial data, decoded velocity
/// vectors differed by under 5 percent in angular error across intention-estimation methods, while
/// SMOOTHING and OUTPUT GAIN differed by over 50 percent, and the authors warn that "simple
/// differences in gain and smoothing properties have a large effect on online performance and can
/// confound decoder comparisons". A raw-versus-ReFIT delta produced by a gain difference alone
/// carries no intent information, so every arm reports both quantities beside its rate.
///
/// SCOPE (review D-9): that paper compares decoder CALIBRATION methods. `IntentRotation` is a
/// RUNTIME transform on an already-fit decoder's output, so the citation supports the confound
/// warning above and NOTHING about what benefit a runtime rotation should show. Do not extend it.
public nonisolated enum ArmStatistics {
  /// Realized output gain: `mean(|v_out|) / mean(|v_in|)` over an arm's ticks
  /// (10-PREREGISTRATION section 8).
  ///
  /// This is the ratio of mean SPEEDS, not the mean of per-tick ratios. A per-tick ratio would be
  /// undefined on every tick the decoder emitted a vanishingly small velocity, which on a
  /// shrinkage-heavy real decode is a large fraction of them, and averaging those would be dominated
  /// by the ticks where the denominator is smallest.
  ///
  /// - Parameters:
  ///   - inputs: the arm's INPUT velocities, i.e. the decoded sequence every arm shares.
  ///   - outputs: the arm's OUTPUT velocities after its filter stage. Only the first
  ///     `min(inputs.count, outputs.count)` samples are used, so a length mismatch cannot pair
  ///     unrelated ticks.
  /// - Returns: the gain, or 0 when there are no samples or the mean input speed is 0. Always
  ///   finite.
  public static func realizedGain(inputs: [SIMD2<Float>], outputs: [SIMD2<Float>]) -> Double {
    let count = Swift.min(inputs.count, outputs.count)
    guard count > 0 else { return 0 }

    var inputSum = 0.0
    var outputSum = 0.0
    for i in 0 ..< count {
      inputSum += speed(inputs[i])
      outputSum += speed(outputs[i])
    }
    guard inputSum > 0 else { return 0 }

    let gain = outputSum / inputSum
    return gain.isFinite ? gain : 0
  }

  /// Realized smoothing: the lag-1 autocorrelation of the output SPEED series
  /// (10-PREREGISTRATION section 8).
  ///
  /// `sum((s[t] - mean) * (s[t+1] - mean)) / sum((s[t] - mean)^2)` over the whole series. A heavily
  /// smoothed output moves slowly, so consecutive speeds sit on the same side of the mean and the
  /// value approaches +1; an unsmoothed jittery output alternates and drives it toward -1.
  ///
  /// A CONSTANT series has zero variance, so the autocorrelation is undefined. It returns 0 rather
  /// than a NaN. That is a defined convention, not a measurement: a series with no variation carries
  /// no information about how smooth it is, and 0 is the neutral value between the two extremes.
  ///
  /// - Parameter outputs: the arm's output velocities, in tick order.
  /// - Returns: the lag-1 autocorrelation in `[-1, 1]`, or 0 for a series with fewer than 2 samples
  ///   or zero variance. Always finite.
  public static func realizedSmoothing(outputs: [SIMD2<Float>]) -> Double {
    guard outputs.count >= 2 else { return 0 }

    let speeds = outputs.map(speed)
    let mean = speeds.reduce(0, +) / Double(speeds.count)

    var covariance = 0.0
    var variance = 0.0
    for t in 0 ..< speeds.count {
      let centered = speeds[t] - mean
      variance += centered * centered
      if t + 1 < speeds.count {
        covariance += centered * (speeds[t + 1] - mean)
      }
    }
    guard variance > 0 else { return 0 }

    let autocorrelation = covariance / variance
    return autocorrelation.isFinite ? autocorrelation : 0
  }

  /// The speed of one velocity sample, widened to `Double` and forced finite.
  ///
  /// `CursorIntegrator` already rejects a non-finite velocity before it can move the cursor, so a
  /// non-finite sample should never reach here. Mapping it to 0 anyway means one bad sample can
  /// never poison a whole arm's published statistic through the sums above.
  private static func speed(_ v: SIMD2<Float>) -> Double {
    let s = Double(simd_length(v))
    return s.isFinite ? s : 0
  }
}
