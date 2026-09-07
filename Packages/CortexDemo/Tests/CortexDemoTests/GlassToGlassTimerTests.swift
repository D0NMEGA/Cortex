@testable import CortexDemo

// GlassToGlassTimerTests — Phase 8 (PERF-04, D-07): the software-timed glass-to-glass timer unit tests.
//
// The 4 behaviors (08-03-PLAN Task 2):
//   1. sample() = (presentTimestampSeconds → ns) − intentEmissionNs, non-negative; a present time
//      before intent emission clamps to 0 (never negative).
//   2. the methodology label contains the verbatim D-07 phrases (embedded so it cannot be dropped).
//   3. a histogram of N synthetic (intent, present) pairs computes p50/p99 via LatencyHistogram (reuse).
//   4. the timer takes a PRESENT timestamp documented as targetPresentationTimestamp (NOT
//      targetTimestamp) — asserted structurally (the source documents the semantics; the grep gate +
//      this test pin it).
//
// Pure value-type math — no display link needed (mirrors LatencyHistogramTests' model-free posture).
import Foundation
import Testing

@Suite("PERF-04 / D-07: software-timed glass-to-glass timer (targetPresentationTimestamp)")
struct GlassToGlassTimerTests {
  // MARK: Test 1 — sample() converts + subtracts + clamps non-negative.

  @Test
  func `1: sample() = present(ns) - intentEmission(ns), non-negative, clamps to 0 if present < intent`() {
    // present = 0.025 s = 25_000_000 ns; intent = 5_000_000 ns ⇒ 20_000_000 ns software-timed latency.
    let latency = GlassToGlassTimer.sample(intentEmissionNs: 5_000_000, presentTimestampSeconds: 0.025)
    #expect(latency == 20_000_000, "sample() = present(ns) - intentEmission(ns)")

    // A present time BEFORE intent emission (clock skew) clamps to 0 — never negative / never UInt64-wrapped.
    let clamped = GlassToGlassTimer.sample(intentEmissionNs: 30_000_000, presentTimestampSeconds: 0.020)
    #expect(clamped == 0, "a present time before intent emission clamps to 0 (never negative)")

    // A non-finite / non-positive present time is defensively 0 (no bogus huge value).
    #expect(GlassToGlassTimer.sample(intentEmissionNs: 1000, presentTimestampSeconds: 0) == 0)
    #expect(GlassToGlassTimer.sample(intentEmissionNs: 1000, presentTimestampSeconds: -1) == 0)
    #expect(GlassToGlassTimer.sample(intentEmissionNs: 1000, presentTimestampSeconds: .nan) == 0)

    // A realistic case: present = 17.6ms (0.0176 s), intent = 1ms ⇒ 16.6ms software-timed latency.
    let realistic = GlassToGlassTimer.sample(intentEmissionNs: 1_000_000, presentTimestampSeconds: 0.0176)
    #expect(realistic == 16_600_000, "17.6ms present - 1ms intent = 16.6ms software-timed latency")
  }

  // MARK: Test 2 — the verbatim D-07 honesty label is embedded.

  @Test
  func `2: methodologyLabel contains the verbatim D-07 honesty phrases (cannot be dropped)`() {
    let label = GlassToGlassTimer.methodologyLabel
    // The three load-bearing phrases the D-07 honesty discipline requires (gate-checkable).
    // readme-policy.sh:136 requires this prefix byte-identical.
    #expect(
      label.hasPrefix("software-timed pipeline latency"),
      "label must start with the readme-policy.sh:136 required prefix"
    )
    #expect(label.contains("excludes the compositor"), "label discloses the compositor scanout is excluded")
    #expect(label.contains("photodiode"), "label names the photodiode rig that would measure the delta")
    #expect(
      label.contains("retired to Future work"),
      "label records that the photodiode rig is retired (LAT-01..LAT-08)"
    )
    #expect(!label.contains("Phases 9-10"), "retired phase reference must not appear in the label (RD-09 sweep)")
    // The full verbatim string (the exact D-07 label — no paraphrase drift).
    #expect(
      label == "software-timed pipeline latency - excludes the compositor's 1-3 frames of scanout; "
        +
        "measuring that delta needs a photodiode rig, which is retired to Future work (LAT-01..LAT-08) and was never built",
      "the methodology label is the verbatim D-07 string"
    )
  }

  // MARK: Test 3 — a histogram of synthetic (intent, present) pairs computes p50/p99 via LatencyHistogram.

  @Test
  func `3: histogram of N synthetic samples computes p50/p99 via LatencyHistogram (reuse)`() {
    // 100 synthetic software-timed samples: intent fixed, present sweeps so latency = 10..<110 ms.
    var samples = [UInt64]()
    for index in 0 ..< 100 {
      let intentNs: UInt64 = 1_000_000
      // present in seconds so that latency = (10 + index) ms.
      let presentSeconds = Double(intentNs) / 1_000_000_000 + Double(10 + index) / 1000.0
      samples.append(GlassToGlassTimer.sample(intentEmissionNs: intentNs, presentTimestampSeconds: presentSeconds))
    }
    let histogram = GlassToGlassTimer.histogram(samplesNs: samples, deviceAnnotation: "unit-test")
    #expect(histogram.count == 100, "all samples recorded")
    // Nearest-rank: p50 ≈ the 50th value (latency ~59ms), p99 ≈ the 99th value (~108ms). Bound-check.
    #expect(histogram.p50 >= 55_000_000 && histogram.p50 <= 65_000_000, "p50 is mid-range (~59ms)")
    #expect(histogram.p99 >= 105_000_000 && histogram.p99 <= 110_000_000, "p99 is near the top (~108ms)")
    #expect(histogram.deviceAnnotation == "unit-test", "the device annotation is carried through")
  }

  // MARK: Test 4 — the timer takes a present timestamp documented as targetPresentationTimestamp.

  @Test
  func `4: the present-time input is targetPresentationTimestamp (NOT targetTimestamp) — structural`() throws {
    // The API surface takes a present timestamp in seconds (a CFTimeInterval) — the
    // targetPresentationTimestamp semantics. We assert structurally that the SOURCE documents this as
    // targetPresentationTimestamp and does NOT bind targetTimestamp as the present clock (D-07 /
    // 08-RESEARCH §0.3). This mirrors the hid-surface-policy / DEC-12 source-scan idiom.
    let testFileURL = URL(fileURLWithPath: #filePath)
    let sourceURL = testFileURL
      .deletingLastPathComponent() // CortexDemoTests/
      .deletingLastPathComponent() // Tests/
      .deletingLastPathComponent() // CortexDemo/ (package root)
      .appendingPathComponent("Sources/CortexDemo/GlassToGlassTimer.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(
      source.contains("targetPresentationTimestamp"),
      "GlassToGlassTimer documents the present-time input as targetPresentationTimestamp (D-07)"
    )
    // The render DEADLINE field must NOT be bound as the present clock. The source may NAME
    // targetTimestamp only to forbid it (assembled here from fragments so this test's own source is not
    // a false match for the gate that scans GlassToGlassTimer.swift).
    let forbiddenAssignment = "= update." + "targetTimestamp"
    #expect(
      !source.contains(forbiddenAssignment),
      "targetTimestamp (the render deadline) is NOT bound as the present clock (D-07 / §0.3)"
    )

    // And functionally: sample() honors whatever present-seconds it is given (the present timestamp),
    // computing present-minus-intent — the targetPresentationTimestamp semantics.
    let latency = GlassToGlassTimer.sample(intentEmissionNs: 2_000_000, presentTimestampSeconds: 0.012)
    #expect(latency == 10_000_000, "sample() subtracts intent from the supplied present timestamp")
  }
}
