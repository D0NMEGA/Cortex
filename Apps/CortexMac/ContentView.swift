import CortexBCIHID
import CortexCore
import CortexDemo
import CortexRender
import SwiftUI

// Phase 8 (SYS-06/PERF-04, D-09/D-10): the CortexMac v0 closed-loop GUI demo. This REPLACES the Phase-6
// oscillator-velocity drive with the REAL synthetic-spike → NDT1 → ReFIT-Kalman → CursorIntegrator →
// 30×30 webgrid closed loop (`CortexDemo.ClosedLoopPipeline`), so the decoder + Kalman are GENUINELY in
// the live demo loop (D-10), not bypassed. The Phase-6 render path is UNCHANGED: the same
// `WebgridView(ring:)` + `MacDisplayLinkAdapter` (NSView.displayLink) consume the same `VelocityRing`
// at 120Hz (RENDER-08); only the PRODUCER changed (the decoder loop, not the oscillator). This is the
// D-09 runnable v0 artifact — free-team GUI-launchable with MTL_HUD_ENABLED=1 (the iPad build is the
// same code, gated). It VISIBLY surfaces (1) the SYS-03/04 instrumented BCI-HID round-trip log line and
// (2) the latest SOFTWARE-TIMED glass-to-glass sample WITH the verbatim methodology label (D-07) — so
// the demo shows the closed loop AND the honest latency framing, never an over-claimed number.
struct ContentView: View {
  /// The producer→renderer SPSC seam (D-03), once per arm. Each view's display-link callback is the
  /// single consumer of its own ring; each driver's MainActor timer is the single producer.
  ///
  /// TWO arms run side by side on the SAME session and the SAME decoded spikes, because the
  /// difference between them is the whole point. `blind` is what the decoder does; `refit` is what
  /// target knowledge does. Showing only the second is how a target-determined result gets mistaken
  /// for a decoding result (10-PREREGISTRATION section 7).
  @State private var blind = ClosedLoopDriver(rotationEnabled: false)
  @State private var refit = ClosedLoopDriver(rotationEnabled: true)

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 1) {
        arm(
          driver: blind,
          title: "kalman_only - target-blind",
          caption: "Heading is the DECODE's own. This is what the decoder does. Published: 0 of 1025 hits."
        )
        arm(
          driver: refit,
          title: "refit - target-determined",
          caption: "IntentRotation replaces the decoded heading with the direction to the KNOWN target, "
            + "keeping only decoded speed. NOT a decoding result. Published: 70 of 1025 hits."
        )
      }

      // The honest instrumentation strip (D-07/D-09): source label, the SYS-03/04 round-trip line and
      // the latest software-timed glass-to-glass sample WITH the methodology label (no over-claim).
      VStack(alignment: .leading, spacing: 4) {
        // D-16: name the spike source ON SCREEN. A demo that silently ran synthetic while being
        // recorded as real-data evidence is the Pattern-2 trap in capture form.
        Text(blind.sourceLabel)
          .font(.system(.caption, design: .monospaced))
        Text(blind.roundTripLine)
          .font(.system(.caption, design: .monospaced))
        Text(blind.latencyLine)
          .font(.system(.caption, design: .monospaced))
        Text(GlassToGlassTimer.methodologyLabel)
          .font(.system(size: 9, design: .monospaced))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
      .background(.black)
      .foregroundStyle(.white)
    }
    .onAppear { blind.start(); refit.start() }
    .onDisappear { blind.stop(); refit.stop() }
  }

  /// One arm's render surface with the label that says what it is and what it is not.
  private func arm(driver: ClosedLoopDriver, title: String, caption: String) -> some View {
    VStack(spacing: 0) {
      // The Phase-6 120Hz webgrid render surface — UNCHANGED (RENDER-08), now driven by the real loop.
      WebgridView(ring: driver.ring, targets: driver.targets)
        .frame(minWidth: 360, minHeight: 360)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(.caption, design: .monospaced).bold())
        Text(caption)
          .font(.system(size: 9, design: .monospaced))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(6)
      .background(.black)
      .foregroundStyle(.white)
    }
  }
}

/// Drives the REAL closed loop (D-09/D-10) on the MAIN ACTOR via a 20ms repeating timer: each tick runs
/// `ClosedLoopPipeline.tick()` (synthetic-spike → NDT1 → ReFIT → integrate) and pushes the decoded+
/// Kalman-refined velocity into the `VelocityRing` the 120Hz display-link callback pops.
///
/// The pipeline + the SYS-03/04 round-trip harness are `@MainActor`-isolated (the CortexDemo package
/// default — the demo loop is a handful of simd ops + at most one CoreML prediction per 20ms, NOT the
/// audio-callback hot path), so the PRODUCER runs on the main actor — a timer, not a background thread
/// (the Phase-3 acquisition pthread is a separate concern). The single CONSUMER is the renderer's
/// display-link callback popping the ring (SPSC discipline intact: one producer = this timer, one
/// consumer = the display link). `@Observable` so the SwiftUI overlay tracks the live round-trip +
/// latency lines.
@MainActor
@Observable
final class ClosedLoopDriver {
  /// 4096-slot ring (power-of-two; ample for a 50Hz producer vs a 120Hz consumer). `init?` only fails
  /// for a non-power-of-two/zero capacity, so this force-unwrap is total.
  let ring = VelocityRing(capacity: 4096)!

  /// The latest SYS-03/04 instrumented round-trip log line (surfaced live in the overlay).
  private(set) var roundTripLine = "round-trip log empty (no cycles recorded)"
  /// The latest software-timed glass-to-glass sample line (surfaced live, WITH the honest framing).
  private(set) var latencyLine = "software-timed glass-to-glass: warming up…"

  /// The real closed loop (D-10): spike window → NDT1 (or synthetic fallback) → ReFIT → integrate.
  /// Seeded deterministically so the demo trajectory is reproducible; the model-backed NDT1 path
  /// activates when CORTEX_MODEL_URL points at a built .mlpackage, else the synthetic decode runs.
  private let pipeline: ClosedLoopPipeline
  /// Which spike source is actually driving the loop, surfaced in the overlay (D-16).
  private(set) var sourceLabel: String
  /// The active task target, published to the renderer once per tick (latest-value, lock-free).
  let targets = TargetChannel()
  /// The recorded source, kept so the per-trial target can be read alongside each decoded tick.
  /// `nil` on the synthetic path, where the task has no recorded target to show.
  private let recordedSource: RecordedSpikeSource?
  /// The pre-registered workspace square, used to map a target in mm onto a grid cell.
  private let boxOriginMm: SIMD2<Double>
  private let boxSideMm: Double

  /// Whether this driver runs the ReFIT rotation (the target-determined arm) or not.
  let rotationEnabled: Bool

  init(rotationEnabled: Bool) {
    self.rotationEnabled = rotationEnabled
    // D-16: resolve the recorded export the same way `CortexDemoBench --real` does, so the GUI and
    // the bench cannot disagree about what "real" means. BOTH inputs are required: a recorded export
    // with no model would decode synthetically over real spikes and still look real on screen.
    let modelURL = ClosedLoopPipeline.modelURLFromEnvironment()
    let exportURL = ReplayExport.sidecarURLFromEnvironment()

    if let exportURL, let modelURL {
      do {
        let export = try ReplayExport(sidecarURL: exportURL)
        let source = RecordedSpikeSource(export: export)
        // NDT1 emits cm/s; the filter, integrator and webgrid run in grid-units/s. Without this the
        // demo cursor runs about 17x too fast on the pre-registered box.
        pipeline = ClosedLoopPipeline(
          source: source,
          seed: 0xC0FFEE,
          modelURL: modelURL,
          modelVelocityGridUnitsPerCm: Float(export.sidecar.workspace.gridUnitsPerCm),
          rotationEnabled: rotationEnabled
        )
        sourceLabel = "spike source: real: \(export.sidecar.sessionId)"
        recordedSource = source
        // The pre-registered `cursor_bbox_square`: the square of side `sideMm` centred on the
        // cursor bounding box's centre (10-PREREGISTRATION section 3, as amended).
        let workspace = export.sidecar.workspace
        boxSideMm = workspace.sideMm
        boxOriginMm = SIMD2<Double>(
          workspace.centreXMm - workspace.sideMm / 2.0,
          workspace.centreYMm - workspace.sideMm / 2.0
        )
        return
      } catch {
        // A REFUSED export is reported, never silently downgraded to synthetic while the recording
        // rolls. The loop still runs so the window is not blank, but the label says what happened.
        pipeline = ClosedLoopPipeline(seed: 0xC0FFEE, modelURL: modelURL, rotationEnabled: rotationEnabled)
        sourceLabel = "spike source: synthetic (the export at \(exportURL.lastPathComponent) was refused: \(error))"
        recordedSource = nil
        boxOriginMm = .zero
        boxSideMm = 1
        return
      }
    }

    pipeline = ClosedLoopPipeline(seed: 0xC0FFEE, modelURL: modelURL, rotationEnabled: rotationEnabled)
    var missing = [String]()
    if exportURL == nil { missing.append("CORTEX_REPLAY_EXPORT") }
    if modelURL == nil { missing.append("CORTEX_MODEL_URL") }
    sourceLabel = "spike source: synthetic (unset: \(missing.joined(separator: ", ")))"
    recordedSource = nil
    boxOriginMm = .zero
    boxSideMm = 1
  }
  /// The SYS-03/04 in-app host harness: one Scan-Info round trip per tick, instrumented log surfaced.
  private let roundTrip = ScanInfoRoundTrip()
  /// The 120Hz present boundary (the beam-raced present) the software-timed sample snaps to.
  private static let framePeriodNs: UInt64 = 8_333_333

  private var timer: Timer?
  private var seq: UInt64 = 0

  func start() {
    guard timer == nil else { return }
    // The 20ms decode cadence on the main actor (the producer). `.common` so it keeps firing during
    // window interaction. The display-link consumer pops the ring on its own callback at 120Hz.
    let timer = Timer(timeInterval: ClosedLoopPipeline.dt, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.step() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  /// Map the recorded target (mm) for `windowIndex` onto a grid cell and publish it to the renderer.
  ///
  /// Uses the SAME `cursor_bbox_square` normalisation the phase pre-registered, so the square the
  /// viewer sees is the square the hit criterion is scored in. A target outside the box, or a
  /// synthetic run with no recorded task, publishes nothing rather than a clamped cell that would
  /// misrepresent where the animal was reaching.
  private func publishTarget(forWindow windowIndex: Int) {
    guard let recordedSource, windowIndex >= 0, boxSideMm > 0 else {
      targets.clear()
      return
    }
    let targetMm = recordedSource.target(forWindow: windowIndex)
    let normalised = (targetMm - boxOriginMm) / boxSideMm
    guard normalised.x >= 0, normalised.x < 1, normalised.y >= 0, normalised.y < 1 else {
      targets.clear()
      return
    }
    let grid = Double(ClosedLoopDriver.gridSide)
    targets.store(column: Int(normalised.x * grid), row: Int(normalised.y * grid))
    // Steer the loop at the SAME target the square draws. Without this the ReFIT arm rotates toward
    // the stale init-time centre cell while the viewer sees a square somewhere else entirely.
    pipeline.setTarget(SIMD2<Float>(Float(normalised.x), Float(normalised.y)))
  }

  /// The 30x30 webgrid substrate (D-01), matching `WebgridParams.grid30x30`.
  private static let gridSide = 30

  /// One 20ms producer tick: decode → filter → integrate, push the velocity, drive the round trip,
  /// and refresh the overlay's software-timed glass-to-glass line.
  private func step() {
    // Intent emission clock (the same mach clock as the BCI HID report timestamp, §1.3).
    let intentEmissionNs = Time.machAbsoluteNanoseconds()

    // ONE real decode → filter → integrate tick (decoder + Kalman GENUINELY in the loop, D-10).
    let state = pipeline.tick()

    // Publish the RECORDED task target for the window that tick just consumed, so the red selection
    // square tracks the animal's actual per-trial target rather than a decoration. `tick()` reads
    // window `tickIndex` then increments, so the window just consumed is `totalTicks - 1`.
    publishTarget(forWindow: pipeline.totalTicks - 1)

    // Push the decoded+Kalman-refined velocity into the SAME ring the 120Hz renderer consumes.
    _ = ring.push(CursorVelocity(
      ts_ns: intentEmissionNs,
      seq: seq,
      vx: Float16(state.velocity.x),
      vy: Float16(state.velocity.y)
    ))

    // Drive one SYS-03/04 BCI-HID Scan-Info round trip (instrumented log — the SC#2 evidence).
    let scanInfo = BCIOutputScanInfoReport(
      selectedItem: UInt8(seq & 0x07),
      numberOfItems: 9,
      seed: UInt8(seq & 0xFF),
      itemControlType: 0,
      uiScanningLatencyInt: 0,
      uiScanningLatencyFrac: 0
    )
    _ = roundTrip.respond(to: scanInfo)
    roundTripLine = roundTrip.log.formattedLastLine()

    // Software-timed glass-to-glass sample (D-07): present = next 120Hz boundary after the tick.
    let afterTickNs = Time.machAbsoluteNanoseconds()
    let framesElapsed = afterTickNs / Self.framePeriodNs
    let presentNs = (framesElapsed + 1) * Self.framePeriodNs
    let latencyNs = GlassToGlassTimer.sample(
      intentEmissionNs: intentEmissionNs,
      presentTimestampSeconds: Double(presentNs) / 1_000_000_000
    )
    let latMs = Double(latencyNs) / 1_000_000
    latencyLine = "software-timed glass-to-glass: \(String(format: "%.2f", latMs)) ms (M5-Pro corroborating)"

    seq &+= 1
  }
}
