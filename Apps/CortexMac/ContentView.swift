import CortexBCIHID
import CortexCore
import CortexDemo
import CortexRender
import SwiftUI

// Phase 8 (SYS-06/PERF-04, D-09/D-10): the CortexMac v0 replay-loop GUI demo. This REPLACES the Phase-6
// oscillator-velocity drive with the REAL synthetic-spike → NDT1 → ReFIT-Kalman → CursorIntegrator →
// 30×30 webgrid replay loop (`CortexDemo.ReplayPipeline`), so the decoder + Kalman are GENUINELY in
// the live demo loop (D-10), not bypassed. The Phase-6 render path is UNCHANGED: the same
// `WebgridView(ring:)` + `MacDisplayLinkAdapter` (NSView.displayLink) consume the same `VelocityRing`
// at 120Hz (RENDER-08); only the PRODUCER changed (the decoder loop, not the oscillator). This is the
// D-09 runnable v0 artifact — free-team GUI-launchable with MTL_HUD_ENABLED=1 (the iPad build is the
// same code, gated). It VISIBLY surfaces (1) the SYS-03/04 instrumented BCI-HID round-trip log line and
// (2) the latest SOFTWARE-TIMED glass-to-glass sample WITH the verbatim methodology label (D-07) — so
// the demo shows the replay loop AND the honest latency framing, never an over-claimed number.
struct ContentView: View {
  /// The producer→renderer SPSC seam (D-03), once per arm. Each view's display-link callback is the
  /// single consumer of its own ring; each driver's MainActor timer is the single producer.
  ///
  /// TWO arms run side by side on the SAME session and the SAME decoded spikes, because the
  /// difference between them is the whole point. `blind` is what the decoder does; `refit` is what
  /// target knowledge does. Showing only the second is how a target-determined result gets mistaken
  /// for a decoding result (10-PREREGISTRATION section 7).
  @State private var blind = ReplayDriver(rotationEnabled: false)
  @State private var refit = ReplayDriver(rotationEnabled: true)

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 1) {
        arm(
          driver: blind,
          title: "kalman_only - heading from the decode",
          caption: "Heading is the DECODE's own; no target steering. The start of each trial is still "
            + "task-derived (see the re-anchor note), so this is not target-free. Published: 0 of 1025."
        )
        arm(
          driver: refit,
          // NOT "refit". ReFIT retrains decoder parameters against target-informed intention; this
          // applies an intent ROTATION at inference and trains nothing. Calling the arm refit
          // credits the run with a method it does not implement.
          title: "target-assisted - heading supplied",
          caption: "IntentRotation replaces the decoded heading with the direction to the KNOWN "
            + "target, keeping only decoded speed. NOT a decoding result. Published: 70 of 1025."
        )
      }

      // The re-anchoring disclosure. It sits ABOVE the arm captions and outside either pane because
      // it qualifies BOTH tracks, and because a viewer who reads nothing else must not walk away
      // believing this is a free-running decoded cursor. The published hit counts in the captions
      // above come from the free-running scored replay, NOT from what is on screen here.
      // `lineLimit`, NOT `fixedSize(vertical:)`: a fixed-size Text can be proposed a near-zero width
      // mid-resize, wrap to one character per line and demand an enormous height. That is not
      // hypothetical here -- it drove the window to 1120x5139 pt the first time the capture script
      // resized it, and the recording framed empty space. A line limit bounds the height whatever
      // width is proposed.
      Text("Cursor RE-ANCHORED to the previous target at each trial start; motion within a trial "
        + "is decoded. Open-loop integration drifts ~26 cells of a 30-cell grid in 30 s and a "
        + "replay cannot correct it. Hit counts below are from the free-running scored replay.")
        .font(.system(size: 9, design: .monospaced))
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black)
        .foregroundStyle(.orange)

      // The honest instrumentation strip (D-07/D-09): source label, the SYS-03/04 round-trip line and
      // the latest software-timed glass-to-glass sample WITH the methodology label (no over-claim).
      VStack(alignment: .leading, spacing: 4) {
        // D-16: name the spike source ON SCREEN. A demo that silently ran synthetic while being
        // recorded as real-data evidence is the Pattern-2 trap in capture form.
        Text(blind.sourceLabel)
          .font(.system(.caption, design: .monospaced))
        Text(blind.decodeLine)
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
    .onAppear { blind.start()
      refit.start()
    }
    .onDisappear { blind.stop()
      refit.stop()
    }
  }

  /// One arm's render surface with the label that says what it is and what it is not.
  private func arm(driver: ReplayDriver, title: String, caption: String) -> some View {
    VStack(spacing: 0) {
      // The Phase-6 120Hz webgrid render surface — UNCHANGED (RENDER-08), now driven by the real loop.
      WebgridView(
        ring: driver.ring,
        targets: driver.targets,
        dwell: driver.dwell,
        anchors: driver.anchors
      )
      .frame(minWidth: 360, minHeight: 360)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(.caption, design: .monospaced).bold())
        Text(caption)
          .font(.system(size: 9, design: .monospaced))
          .foregroundStyle(.secondary)
          // Bounded rather than fixed-size, for the same reason as the re-anchoring banner: a
          // fixed-size Text proposed a near-zero width mid-resize demands an unbounded height.
          .lineLimit(3)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(6)
      .background(.black)
      .foregroundStyle(.white)
    }
  }
}

/// Drives the REAL replay loop (D-09/D-10) on the MAIN ACTOR via a 20ms repeating timer: each tick runs
/// `ReplayPipeline.tick()` (synthetic-spike → NDT1 → ReFIT → integrate) and pushes the decoded+
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
final class ReplayDriver {
  /// 4096-slot ring (power-of-two; ample for a 50Hz producer vs a 120Hz consumer). `init?` only
  /// fails for a non-power-of-two/zero capacity, so 4096 can never fail; the trap is unreachable and
  /// says why, rather than being a bare `!`.
  let ring: VelocityRing = {
    guard let ring = VelocityRing(capacity: 4096) else {
      preconditionFailure("VelocityRing(capacity:) only returns nil for a zero or non-power-of-two "
        + "capacity; 4096 is neither")
    }
    return ring
  }()

  /// The latest SYS-03/04 instrumented round-trip log line (surfaced live in the overlay).
  private(set) var roundTripLine = "round-trip log empty (no cycles recorded)"
  /// The latest software-timed glass-to-glass sample line (surfaced live, WITH the honest framing).
  private(set) var latencyLine = "software-timed glass-to-glass: warming up…"
  /// Live decode provenance: how many ticks NDT1 actually decoded, out of every tick run.
  ///
  /// `sourceLabel` names the SPIKE source and nothing else. A viewer reading "real:
  /// indy_20160630_01" beside a moving cursor cannot tell whether NDT1 produced that motion or the
  /// synthetic fallback did, and the two look identical on screen. The pipeline already counts this
  /// (`modelBackedTicks` / `totalTicks`) and records why a decode failed; it was simply never shown.
  private(set) var decodeLine = "decode: warming up…"

  /// The real replay loop (D-10): spike window → NDT1 (or synthetic fallback) → ReFIT → integrate.
  /// Seeded deterministically so the demo trajectory is reproducible; the model-backed NDT1 path
  /// activates when CORTEX_MODEL_URL points at a built .mlpackage, else the synthetic decode runs.
  private let pipeline: ReplayPipeline
  /// Which spike source is actually driving the loop, surfaced in the overlay (D-16).
  private(set) var sourceLabel: String
  /// The active task target, published to the renderer once per tick (latest-value, lock-free).
  let targets = TargetChannel()
  /// Dwell-to-select progress, published to the renderer once per tick (latest-value, lock-free).
  let dwell = DwellChannel()
  /// Cursor re-anchor events. The RENDERER owns the integrator that draws the cursor, so a
  /// re-anchor has to be published to it as well as applied to the pipeline's own integrator.
  let anchors = AnchorChannel()
  /// The recorded source, kept so the per-trial target can be read alongside each decoded tick.
  /// `nil` on the synthetic path, where the task has no recorded target to show.
  private let recordedSource: RecordedSpikeSource?
  /// The pre-registered workspace square, used to map a target in mm onto a grid cell.
  private let boxOriginMm: SIMD2<Double>
  private let boxSideMm: Double
  /// The normalised target published on the previous tick, or `nil` before the first one.
  ///
  /// A CHANGE in this value is the trial boundary, and its OLD value is where the subject's hand was
  /// when the new target appeared -- which is what the cursor re-anchors onto. The task structure is
  /// what makes that sound: a trial ends by acquiring its target, so the hand is at the target it
  /// just left. Measured on this session, at the 1024 target changes the recorded hand sits a median
  /// 5.19 mm from the target it just left (77% within half the 15 mm task pitch) against 61.45 mm
  /// from the one that just appeared.
  private var previousTarget: SIMD2<Float>?

  /// Whether this driver runs the ReFIT rotation (the target-determined arm) or not.
  let rotationEnabled: Bool

  init(rotationEnabled: Bool) {
    self.rotationEnabled = rotationEnabled
    // D-16: resolve the recorded export the same way `CortexDemoBench --real` does, so the GUI and
    // the bench cannot disagree about what "real" means. BOTH inputs are required: a recorded export
    // with no model would decode synthetically over real spikes and still look real on screen.
    let modelURL = ReplayPipeline.modelURLFromEnvironment()
    let exportURL = ReplayExport.sidecarURLFromEnvironment()

    if let exportURL, let modelURL {
      do {
        let export = try ReplayExport(sidecarURL: exportURL)
        // `stride: 1` replays in REAL TIME: one 20 ms tick advances the session by one 20 ms bin,
        // decoding the trailing 32-bin window ending there -- the cadence `CortexReplayBench` scores
        // with. The default stride is the window length, which advances 640 ms of recorded time per
        // tick; that made the demo integrate `velocity * 0.020` across 0.640 s of real motion (the
        // cursor crept around its start point at 1/32 speed) while the per-trial target advanced 32x
        // too fast (the task square changed every ~2 frames and read as random strobing).
        let source = RecordedSpikeSource(export: export, stride: 1)
        // NDT1 emits cm/s; the filter, integrator and webgrid run in grid-units/s. Without this the
        // demo cursor runs about 17x too fast on the pre-registered box.
        pipeline = ReplayPipeline(
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
        pipeline = ReplayPipeline(seed: 0xC0FFEE, modelURL: modelURL, rotationEnabled: rotationEnabled)
        sourceLabel = "spike source: synthetic (the export at \(exportURL.lastPathComponent) was refused: \(error))"
        recordedSource = nil
        boxOriginMm = .zero
        boxSideMm = 1
        return
      }
    }

    pipeline = ReplayPipeline(seed: 0xC0FFEE, modelURL: modelURL, rotationEnabled: rotationEnabled)
    var missing = [String]()
    if exportURL == nil {
      missing.append("CORTEX_REPLAY_EXPORT")
    }
    if modelURL == nil {
      missing.append("CORTEX_MODEL_URL")
    }
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
    let timer = Timer(timeInterval: ReplayPipeline.dt, repeats: true) { [weak self] _ in
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
      previousTarget = nil
      return
    }
    let targetMm = recordedSource.target(forWindow: windowIndex)
    let normalised = (targetMm - boxOriginMm) / boxSideMm
    guard normalised.x >= 0, normalised.x < 1, normalised.y >= 0, normalised.y < 1 else {
      // No target on screen means no trial, so there is nothing to re-anchor onto when one returns.
      targets.clear()
      previousTarget = nil
      return
    }
    let grid = Double(ReplayDriver.gridSide)
    targets.store(column: Int(normalised.x * grid), row: Int(normalised.y * grid))
    let current = SIMD2<Float>(Float(normalised.x), Float(normalised.y))

    // A new target is a new trial. Re-anchor the cursor onto the target just left before steering at
    // the new one, so what the viewer sees is the decode's within-trial behaviour rather than 24
    // minutes of accumulated open-loop integration error. See `ReplayPipeline.reanchor(to:)` for
    // why a replay cannot close that loop on its own, and the on-screen caption that says so.
    if let previous = previousTarget, previous != current {
      pipeline.reanchor(to: previous)
      anchors.store(x: previous.x, y: previous.y)
    }
    previousTarget = current

    // Steer the loop at the SAME target the square draws. Without this the ReFIT arm rotates toward
    // the stale init-time centre cell while the viewer sees a square somewhere else entirely.
    pipeline.setTarget(current)
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

    // Publish the dwell the cursor has accumulated on that target, so the ring contracts as a
    // selection is committed. Same 0.30 s continuous-hold criterion the run is scored with.
    dwell.store(pipeline.dwellProgress)

    // Push the decoded+Kalman-refined velocity into the SAME ring the 120Hz renderer consumes.
    _ = ring.push(CursorVelocity(
      tsNs: intentEmissionNs,
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

    // Decode provenance, refreshed live. A shortfall names itself rather than being inferred from a
    // cursor that looks plausible either way.
    let backed = pipeline.modelBackedTicks
    let total = pipeline.totalTicks
    if total > 0, backed == total {
      decodeLine = "decode: NDT1 CoreML on \(backed)/\(total) ticks (model in loop)"
    } else if let reason = pipeline.lastDecodeFailure {
      decodeLine = "decode: NDT1 on \(backed)/\(total) ticks - SYNTHETIC FALLBACK: \(reason)"
    } else {
      decodeLine = "decode: NDT1 on \(backed)/\(total) ticks"
    }

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
