// GlassToGlassTimer — Phase 8 (PERF-04, D-07): the SOFTWARE-TIMED glass-to-glass latency measurement.
//
// THE load-bearing credibility piece. 08-RESEARCH §0.3/§5 (the API correction the spec §3 got
// imprecise): the software-timed glass-to-glass latency ends at the CAMetalDisplayLink
// `Update.targetPresentationTimestamp` — "the time the system estimates until display of the next
// frame", i.e. the on-glass present time. The render-DEADLINE field (`Update`'s deadline timestamp,
// which the §0.3 correction warns against) must NOT end the measurement — it would inflate/deflate the
// number (threat T-08-03-02). The grep gate forbids binding that deadline field as the present clock.
//
//   software-timed pipeline latency = targetPresentationTimestamp(ns) − intentEmission(ns)
//
// where `intentEmission` is the decoder's `mach_absolute_time()` at intent emission (the SAME clock as
// the BCI HID report timestamp — §1.3 / CortexCore.Time.machAbsoluteNanoseconds()).
//
// ## Honesty discipline (D-07 — no compositor-offset fudge, threat T-08-03-03)
// This is the SOFTWARE number that SETS UP the v1 photodiode claim; it is NOT the final glass-to-glass
// figure. The verbatim methodology label is EMBEDDED in the type (`methodologyLabel`) so it is gate-
// checkable and CANNOT be dropped — it must travel with every reported number. The label states the
// software measurement excludes the compositor's 1-3 frames of scanout, which is exactly the delta the
// v1 photodiode rig (Phases 9-10) quantifies. The canonical iPad-M4 capture is the Plan 07 never-auto-
// approve HUMAN-UAT gate (D-08); the M5-Pro headless number is CORROBORATING (threat T-08-03-04).
//
// Foundation-only (for the LatencyHistogram helper) — no Metal/CoreML dependency, so the conversion +
// percentile math are unit-testable with no display link (mirrors LatencyHistogram's model-free posture).
import CortexDecoder // LatencyHistogram — the p50/p99/max value type reused for the bench (no new math).
import Foundation

/// The software-timed glass-to-glass latency measurement (PERF-04, D-07). A pure `Sendable` value type:
/// the `sample` conversion + the histogram helper are deterministic and model-free (unit-testable with
/// no display link). `nonisolated` so it crosses isolation boundaries freely (the bench + the GUI both
/// use it without an actor hop) under the package's `.defaultIsolation(MainActor.self)`.
public nonisolated enum GlassToGlassTimer {
  /// The VERBATIM D-07 honesty label — embedded so it is gate-checkable and cannot be dropped (threat
  /// T-08-03-03). It must accompany every reported software-timed number (printed by the bench, written
  /// to the JSON, surfaced in the GUI). It states the software measurement excludes the compositor's
  /// scanout, which is precisely the delta the v1 photodiode rig quantifies (NO compositor-offset fudge).
  public static let methodologyLabel =
    "software-timed pipeline latency — excludes the compositor's 1-3 frames of scanout, " +
    "which is exactly the delta the v1 photodiode rig (Phases 9-10) quantifies"

  /// Nanoseconds per second (the `CFTimeInterval`-seconds → ns conversion factor).
  private static let nanosecondsPerSecond: Double = 1_000_000_000

  /// Compute one software-timed glass-to-glass sample in nanoseconds:
  /// `presentTimestampSeconds` (converted to ns) − `intentEmissionNs`, clamped to ≥ 0 (never negative).
  ///
  /// - Parameters:
  ///   - intentEmissionNs: the decoder's intent-emission time in ns (`mach_absolute_time()` widened via
  ///     `mach_timebase_info` — CortexCore.Time.machAbsoluteNanoseconds() — the SAME clock as the BCI
  ///     HID report timestamp, §1.3).
  ///   - presentTimestampSeconds: the on-glass present time in seconds. This MUST be the
  ///     CAMetalDisplayLink `update.targetPresentationTimestamp` (a `CFTimeInterval` in seconds — the
  ///     time the system estimates until display of the next frame), **NOT** `update.targetTimestamp`
  ///     (the render DEADLINE). Using the deadline would mis-state the latency (D-07 / 08-RESEARCH §0.3).
  /// - Returns: the non-negative software-timed latency in ns. A present time before intent emission
  ///   clamps to 0 (the measurement is never negative — defensive against clock skew at startup).
  public static func sample(intentEmissionNs: UInt64, presentTimestampSeconds: Double) -> UInt64 {
    // Convert the present timestamp (CFTimeInterval seconds) to ns. A non-finite/negative present time
    // clamps to 0 so the subtraction below can never produce a bogus huge value.
    guard presentTimestampSeconds.isFinite, presentTimestampSeconds > 0 else { return 0 }
    let presentNs = presentTimestampSeconds * nanosecondsPerSecond
    let intentNs = Double(intentEmissionNs)
    let deltaNs = presentNs - intentNs
    // Clamp to ≥ 0: a present time before intent emission (clock skew) yields 0, never a negative or
    // wrapped-UInt64 latency (threat: a negative delta would underflow UInt64 to ~1.8e19 ns).
    guard deltaNs > 0 else { return 0 }
    return UInt64(deltaNs.rounded())
  }

  /// Build a device-annotated ``LatencyHistogram`` from software-timed ns samples (reuses the
  /// CortexDecoder histogram math — p50/p99/max nearest-rank — rather than duplicating it). The
  /// `deviceAnnotation` is WHY a number is M5-Pro CORROBORATING vs the canonical iPad-M4 claim (D-08).
  ///
  /// - Parameters:
  ///   - samplesNs: the per-tick software-timed latency samples in ns.
  ///   - deviceAnnotation: the device the measurement ran on (e.g. "M5-Pro-software-timed-corroborating").
  public static func histogram(samplesNs: [UInt64], deviceAnnotation: String) -> LatencyHistogram {
    LatencyHistogram(samplesNs: samplesNs, deviceAnnotation: deviceAnnotation)
  }
}
