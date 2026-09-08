// ReplayDriver — the 20 ms producer behind the CortexMac demo.
//
// Split out of `ContentView.swift`: the view is the layout and the labels, this is the loop that
// decodes, clicks, and publishes to the renderer.
import CortexBCIHID
import CortexCore
import CortexDemo
import CortexRender
import Foundation
import simd

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
  /// Dwell progress + acquisition state, published to the renderer once per tick (lock-free).
  let selection = SelectionChannel()
  /// The pipeline's authoritative cursor position, republished every tick.
  ///
  /// The RENDERER owns the integrator that draws the cursor; the PIPELINE owns the one the filter,
  /// the steering and the dwell criterion read. Publishing the pipeline's position every tick is
  /// what keeps them the same cursor -- without it they integrate different clocks and a viewer
  /// watches a ring close over a target that never registers.
  let cursorPositions = CursorPositionChannel()
  /// Selections committed since launch, mirrored off the pipeline so `@Observable` tracks it.
  ///
  /// `ReplayPipeline` is a plain class, so SwiftUI sees no change when its counter moves; reading it
  /// straight from the badge would render a tally frozen at zero.
  private(set) var selectionCount = 0
  /// Whether the last click landed on target. Drives the tally's colour, and clears with the marker.
  private(set) var lastClickHit = false
  /// Median cursor-to-target distance at a click, over the clicks so far.
  private(set) var missLabel = "median miss: no clicks yet"
  /// The finite board of whole cells the task presents, derived from its own target positions.
  let board: Board
  /// The ruled lattice the renderer draws.
  ///
  /// The TASK's target lattice when a real export is replaying, not the uniform 30x30 substrate.
  /// This session steps its targets 15 mm apart on a workspace 171.68 mm across, which is 2.62
  /// cells of a 30x30 grid: an irrational step, so on a 30x30 grid no target can ever sit on a cell.
  /// Drawing the task's own pitch is the only way the squares land on the lattice without moving
  /// them off the point the dwell criterion scores.
  let lattice: GridLattice
  /// The acquisition tolerance this run scores with, grid-normalised, and the same in millimetres.
  let scoringHalfExtent: Float
  let scoringHalfExtentMm: Double

  /// Names the rule in force, because the tally means nothing without it.
  ///
  /// The published 0-of-1025 and 70-of-1025 are scored at the 30x30 Webgrid half-cell, a 2.861 mm
  /// RADIUS on this session. That is a convention from a different task, and the animal's OWN
  /// recorded hand satisfies it on only 14.3% of trials, so a decoder scored against it is largely
  /// being told about the rule. This run scores the task's own cell instead: the cursor's centre
  /// inside a square of the task's 15 mm target pitch, which is what the viewer sees drawn.
  var radiusLabel: String {
    scoringHalfExtentMm > 0
      ? String(format: "cell %.2f mm = the task's target pitch", scoringHalfExtentMm * 2)
      : "cell = one 30x30 Webgrid cell"
  }

  /// The recorded source, kept so the per-trial target can be read alongside each decoded tick.
  /// `nil` on the synthetic path, where the task has no recorded target to show.
  private let recordedSource: RecordedSpikeSource?
  /// The pre-registered workspace square, used to map a target in mm onto a grid cell.
  private let boxOriginMm: SIMD2<Double>
  private let boxSideMm: Double
  /// Where the last click landed, published to the renderer while its green marker fades.
  private var hitMarker = SIMD2<Float>(0, 0)

  /// The normalised target published on the previous tick, or `nil` before the first one.
  ///
  /// A CHANGE in this value is the trial boundary, and its OLD value is where the subject's hand was
  /// when the new target appeared -- which is what the cursor re-anchors onto. The task structure is
  /// what makes that sound: a trial ends by acquiring its target, so the hand is at the target it
  /// just left. Measured on this session, at the 1024 target changes the recorded hand sits a median
  /// 5.19 mm from the target it just left (77% within half the 15 mm task pitch) against 61.45 mm
  /// from the one that just appeared.
  private var previousTarget: SIMD2<Float>?
  /// Trials STARTED since launch. The DENOMINATOR of the live counter, and not the session's 1,025
  /// -- a capture shows a couple of minutes of a 24-minute replay.
  ///
  /// Started, not completed: counting only target CHANGES skipped the first trial, so a run that
  /// acquired its opening target could report 1 of 0. The numerator is now bounded by the
  /// denominator by construction, because a trial is opened before it can be acquired and can only
  /// be acquired once.
  private(set) var trialCount = 0

  /// Whether this driver runs the ReFIT rotation (the target-determined arm) or not.
  let rotationEnabled: Bool

  init(rotationEnabled: Bool) {
    self.rotationEnabled = rotationEnabled
    let setup = Self.resolve(rotationEnabled: rotationEnabled)
    pipeline = setup.pipeline
    sourceLabel = setup.sourceLabel
    recordedSource = setup.recordedSource
    board = setup.geometry.board
    lattice = setup.geometry.lattice
    scoringHalfExtent = setup.geometry.scoringHalfExtent
    scoringHalfExtentMm = setup.geometry.scoringHalfExtentMm
    boxOriginMm = setup.geometry.originMm
    boxSideMm = setup.geometry.sideMm
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
      pipeline.clearTarget()
      previousTarget = nil
      return
    }
    let targetMm = recordedSource.target(forWindow: windowIndex)
    let normalised = (targetMm - boxOriginMm) / boxSideMm
    guard normalised.x >= 0, normalised.x < 1, normalised.y >= 0, normalised.y < 1 else {
      // No target on screen means no trial, so there is nothing to re-anchor onto when one returns.
      // Scoring stops with the drawing: a dwell banked against a target the viewer cannot see is a
      // hit they have no way to anticipate or check.
      targets.clear()
      pipeline.clearTarget()
      previousTarget = nil
      return
    }
    let current = SIMD2<Float>(Float(normalised.x), Float(normalised.y))
    // Publish the target WHERE IT IS, not the grid cell containing it. The dwell criterion tests
    // distance to this exact point; drawing the cell instead put the square a median 2.26 mm away
    // against a 2.86 mm radius, so a cursor centred in the square was scored as a miss.
    targets.store(x: current.x, y: current.y)

    // A new target is a new trial. Re-anchor the cursor onto the target just left before steering at
    // the new one, so what the viewer sees is the decode's within-trial behaviour rather than 24
    // minutes of accumulated open-loop integration error. See `ReplayPipeline.reanchor(to:)` for
    // why a replay cannot close that loop on its own, and the on-screen caption that says so.
    if let previous = previousTarget {
      if previous != current {
        // THE CLICK. The recorded task moved its target on, which is the moment the animal selected
        // it, so this is a real selection event in the data rather than a rule imposed on top of
        // it. Scored against the target that was on screen for the tick just finished, at wherever
        // the decode had put the cursor. Nothing repositions the cursor: it carries on from here.
        let hit = pipeline.registerClick()
        publishHitMarker(at: previous, hit: hit)
        pipeline.beginTrial()
        trialCount += 1
      }
    } else {
      // The first target of the run, or the first after one left the workspace box. Nothing to
      // click yet, but the trial still has to be OPENED so it enters the denominator.
      pipeline.beginTrial()
      trialCount += 1
    }
    previousTarget = current

    // Steer the loop at the SAME target the square draws. Without this the ReFIT arm rotates toward
    // the stale init-time centre cell while the viewer sees a square somewhere else entirely.
    pipeline.setTarget(current)
  }

  /// Remember where a click landed so the renderer can hold a green marker there while it fades.
  ///
  /// A MISS publishes nothing new: the marker's fade comes from the pipeline and stays 0, so the
  /// previous hit's position is simply never drawn again. Only hits are marked, which is what makes
  /// a green square on screen mean exactly one thing.
  private func publishHitMarker(at position: SIMD2<Float>, hit: Bool) {
    guard hit else { return }
    hitMarker = position
  }

  /// The median miss in millimetres, or why there is not one yet.
  private static func missLabel(_ median: Float?, sideMm: Double) -> String {
    guard let median, sideMm > 0 else { return "median miss: no clicks yet" }
    return String(format: "median miss %.1f mm at the click", Double(median) * sideMm)
  }

  /// Decode provenance, refreshed live. A shortfall names itself rather than being inferred from a
  /// cursor that looks plausible either way.
  private func decodeProvenance() -> String {
    let backed = pipeline.modelBackedTicks
    let total = pipeline.totalTicks
    let name = switch pipeline.decoderKind {
    case .ridge: "ridge (linear, 32 bins x 96 ch, held-out R2 0.4616)"
    case .ndt1: "NDT1 CoreML (held-out R2 0.4238)"
    }
    let counted = "decode: \(name) on \(backed)/\(total) ticks"
    guard total == 0 || backed != total, let reason = pipeline.lastDecodeFailure else {
      return counted
    }
    return "\(counted) - SYNTHETIC FALLBACK: \(reason)"
  }

  /// One 20ms producer tick: decode → filter → integrate, push the velocity, drive the round trip,
  /// and refresh the overlay's software-timed glass-to-glass line.
  private func step() {
    // Intent emission clock (the same mach clock as the BCI HID report timestamp, §1.3).
    let intentEmissionNs = Time.machAbsoluteNanoseconds()

    // Publish the RECORDED task target for the window this tick is ABOUT to consume, so the tick is
    // scored against its own trial's target. `tick()` reads window `tickIndex`, which is
    // `totalTicks` before the tick runs. Published FIRST, not after: a trial boundary has to
    // re-anchor the cursor BEFORE the first decoded tick of the new trial, and the last tick of the
    // old trial has to be scored against the target that was actually on screen for it.
    publishTarget(forWindow: pipeline.totalTicks)

    // ONE real decode → filter → integrate tick (decoder + Kalman GENUINELY in the loop, D-10).
    let state = pipeline.tick()

    // Publish the dwell the cursor has accumulated and whether this trial has been acquired, so the
    // ring contracts as a selection is committed and the target greens and STAYS green when it does.
    // Same 0.30 s continuous-hold criterion the run is scored with.
    let authoritative = pipeline.cursorPosition
    cursorPositions.store(x: authoritative.x, y: authoritative.y)

    selection.store(
      clickPulse: pipeline.clickPulse,
      hitX: hitMarker.x,
      hitY: hitMarker.y,
      hitFade: pipeline.selectionSwell
    )
    selectionCount = pipeline.selectionCount
    lastClickHit = pipeline.selectionSwell > 0
    missLabel = Self.missLabel(pipeline.medianMiss, sideMm: boxSideMm)

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

    decodeLine = decodeProvenance()

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

// MARK: - Resolving the run from the environment

///
/// Which spike source, which decoder and which task geometry this driver runs, all read from the
/// environment before any stored property exists. Setup, not the loop: it happens once at init and
/// nothing here runs per tick.
private extension ReplayDriver {
  /// Everything the driver needs, resolved from the environment before any property is stored.
  private struct Setup {
    let pipeline: ReplayPipeline
    let sourceLabel: String
    let recordedSource: RecordedSpikeSource?
    let geometry: Geometry
  }

  /// Resolve the spike source, the decoder and the task geometry from the environment.
  ///
  /// D-16: the recorded export is resolved the same way `CortexDemoBench --real` does, so the GUI
  /// and the bench cannot disagree about what "real" means.
  private static func resolve(rotationEnabled: Bool) -> Setup {
    let modelURL = ReplayPipeline.modelURLFromEnvironment()
    let exportURL = ReplayExport.sidecarURLFromEnvironment()
    // Defaults to the matched linear decoder, which reaches the higher held-out R2 on this data.
    // `CORTEX_DECODER=ndt1` runs the transformer instead; the decode line names whichever ran.
    let kind = ReplayPipeline.decoderFromEnvironment()

    // The linear decoder ships in the app bundle, so it needs no model file. NDT1 does, and running
    // the transformer arm without one would silently be the synthetic readout.
    guard let exportURL, kind == .ridge || modelURL != nil else {
      let pipeline = ReplayPipeline(
        seed: 0xC0FFEE, modelURL: modelURL, rotationEnabled: rotationEnabled, decoderKind: kind
      )
      return Setup(
        pipeline: pipeline,
        sourceLabel: missingInputsLabel(exportURL: exportURL, modelURL: modelURL, kind: kind),
        recordedSource: nil,
        geometry: syntheticGeometry
      )
    }

    do {
      let export = try ReplayExport(sidecarURL: exportURL)
      // `stride: 1` replays in REAL TIME: one 20 ms tick advances the session by one 20 ms bin,
      // decoding the trailing 32-bin window ending there -- the cadence `CortexReplayBench` scores
      // with. The default stride is the window length, which advances 640 ms of recorded time per
      // tick; that made the demo integrate `velocity * 0.020` across 0.640 s of real motion while
      // the per-trial target advanced 32x too fast and read as random strobing.
      let source = RecordedSpikeSource(export: export, stride: 1)
      let geometry = geometry(export: export, source: source)
      // Both decoders emit cm/s; the filter, integrator and webgrid run in grid-units/s. Without
      // this conversion the cursor runs about 17x too fast on the pre-registered box.
      let pipeline = ReplayPipeline(
        source: source,
        seed: 0xC0FFEE,
        modelURL: modelURL,
        modelVelocityGridUnitsPerCm: Float(export.sidecar.workspace.gridUnitsPerCm),
        rotationEnabled: rotationEnabled,
        decoderKind: kind,
        scoringHalfExtent: geometry.scoringHalfExtent
      )
      return Setup(
        pipeline: pipeline,
        sourceLabel: "spike source: real: \(export.sidecar.sessionId)",
        recordedSource: source,
        geometry: geometry
      )
    } catch {
      // A REFUSED export is reported, never silently downgraded to synthetic while the recording
      // rolls. The loop still runs so the window is not blank, but the label says what happened.
      let pipeline = ReplayPipeline(
        seed: 0xC0FFEE, modelURL: modelURL, rotationEnabled: rotationEnabled, decoderKind: kind
      )
      return Setup(
        pipeline: pipeline,
        sourceLabel: "spike source: synthetic (the export at \(exportURL.lastPathComponent) "
          + "was refused: \(error))",
        recordedSource: nil,
        geometry: syntheticGeometry
      )
    }
  }

  /// The 30x30 substrate's own geometry, for a run with no recorded task behind it.
  private static let syntheticGeometry = Geometry(
    originMm: .zero,
    sideMm: 1,
    lattice: .uniform30,
    board: .wholeGrid,
    scoringHalfExtent: ReplayPipeline.acquisitionRadius,
    scoringHalfExtentMm: 0
  )

  /// The workspace box, the ruled lattice and the finite board, all derived from the export.
  ///
  /// Computed HERE rather than on a later tick because the display-link adapter captures the
  /// lattice when the render view is created; one computed after that never reaches the renderer.
  private struct Geometry {
    let originMm: SIMD2<Double>
    let sideMm: Double
    let lattice: GridLattice
    /// The finite square of whole cells the task presents.
    let board: Board
    /// Half the task's own target pitch, grid-normalised: the tolerance the TASK defines.
    let scoringHalfExtent: Float
    /// The same radius in millimetres, for the on-screen label.
    let scoringHalfExtentMm: Double
  }

  private static func geometry(export: ReplayExport, source: RecordedSpikeSource) -> Geometry {
    // The pre-registered `cursor_bbox_square`: the square of side `sideMm` centred on the cursor
    // bounding box's centre (10-PREREGISTRATION section 3, as amended).
    let workspace = export.sidecar.workspace
    let origin = SIMD2<Double>(
      workspace.centreXMm - workspace.sideMm / 2.0,
      workspace.centreYMm - workspace.sideMm / 2.0
    )
    let lattice = taskLattice(
      pitchMm: export.sidecar.targetGrid.pitchMm,
      firstTargetMm: source.target(forWindow: 0),
      boxOriginMm: origin,
      boxSideMm: workspace.sideMm
    )
    // Half the task's own 15 mm target pitch, so the drawn square exactly fills its cell on the
    // lattice above: the cell IS the target, and the region scored is the region drawn. Falls back
    // to one 30x30 Webgrid cell if the sidecar has no usable pitch.
    let pitchMm = export.sidecar.targetGrid.pitchMm
    let usable = pitchMm > 0 && pitchMm < workspace.sideMm && workspace.sideMm > 0
    let halfMm = usable ? pitchMm / 2.0 : Double(ReplayPipeline.acquisitionRadius) * workspace.sideMm
    let extent = targetExtentMm(source: source, windows: source.windowCount)
    return Geometry(
      originMm: origin,
      sideMm: workspace.sideMm,
      lattice: lattice,
      board: taskBoard(extentMm: extent, pitchMm: pitchMm, boxOriginMm: origin, boxSideMm: workspace.sideMm),
      scoringHalfExtent: Float(halfMm / workspace.sideMm),
      scoringHalfExtentMm: halfMm
    )
  }

  /// The bounding box of every target the recorded session presents, in millimetres.
  ///
  /// Scanned rather than assumed. The board has to be the task's own, and the sidecar records only
  /// how many distinct targets there are and how far apart they step -- not where they sit. One
  /// pass over the export at launch is a few milliseconds and it is exact.
  private static func targetExtentMm(source: RecordedSpikeSource,
                                     windows: Int) -> (min: SIMD2<Double>, max: SIMD2<Double>)?
  {
    guard windows > 0 else { return nil }
    var lo = SIMD2<Double>(.infinity, .infinity)
    var hi = SIMD2<Double>(-.infinity, -.infinity)
    for window in 0 ..< windows {
      let t = source.target(forWindow: window)
      guard t.x.isFinite, t.y.isFinite else { continue }
      lo = SIMD2<Double>(Swift.min(lo.x, t.x), Swift.min(lo.y, t.y))
      hi = SIMD2<Double>(Swift.max(hi.x, t.x), Swift.max(hi.y, t.y))
    }
    guard lo.x.isFinite, hi.x.isFinite else { return nil }
    return (lo, hi)
  }

  /// The finite board: whole cells, centred on the targets, sized to contain every one of them.
  ///
  /// This session's 64 targets sit on 8 distinct x values and 8 distinct y values, 15 mm apart,
  /// spanning 105 mm = 7 pitches, so the board is 8 cells across -- which is also `log2 N = 6` bits
  /// per selection, the figure the sidecar records. Derived from the targets rather than assumed,
  /// so a different session draws its own board. Falls back to the whole normalised square when the
  /// export has no usable target extent, rather than inventing a board the task does not have.
  private static func taskBoard(
    extentMm: (min: SIMD2<Double>, max: SIMD2<Double>)?,
    pitchMm: Double,
    boxOriginMm: SIMD2<Double>,
    boxSideMm: Double
  ) -> Board {
    guard let extentMm, pitchMm > 0, boxSideMm > 0 else { return .wholeGrid }
    let spanX = (extentMm.max.x - extentMm.min.x) / pitchMm
    let spanY = (extentMm.max.y - extentMm.min.y) / pitchMm
    // Targets are cell CENTRES, so a span of n pitches needs n + 1 cells to contain them all.
    let cells = Int((Swift.max(spanX, spanY)).rounded()) + 1
    guard cells > 0, Double(cells) * pitchMm <= boxSideMm else { return .wholeGrid }
    let centreMm = (extentMm.min + extentMm.max) / 2
    let centre = (centreMm - boxOriginMm) / boxSideMm
    guard centre.x.isFinite, centre.y.isFinite else { return .wholeGrid }
    return .cells(
      cells,
      pitch: Float(pitchMm / boxSideMm),
      centre: SIMD2<Float>(Float(centre.x), Float(centre.y))
    )
  }

  /// The task's own target lattice, phased so every target falls at a cell centre.
  ///
  /// The 30x30 substrate cannot do this. This session steps its targets 15 mm apart on a workspace
  /// 171.68 mm across, which is 2.62 cells of a 30x30 grid, so no phase puts them all on cells --
  /// the squares can only look aligned by being DRAWN somewhere other than where they are scored,
  /// which is the defect this replaces. Falls back to the uniform substrate if the sidecar's pitch
  /// is not usable, rather than drawing a lattice the task does not have.
  private static func taskLattice(
    pitchMm: Double,
    firstTargetMm: SIMD2<Double>,
    boxOriginMm: SIMD2<Double>,
    boxSideMm: Double
  ) -> GridLattice {
    guard boxSideMm > 0, pitchMm > 0, pitchMm < boxSideMm else { return .uniform30 }
    let pitch = Float(pitchMm / boxSideMm)
    let normalised = (firstTargetMm - boxOriginMm) / boxSideMm
    let reference = SIMD2<Float>(Float(normalised.x), Float(normalised.y))
    guard reference.x.isFinite, reference.y.isFinite else { return .uniform30 }
    return .centred(on: reference, pitch: SIMD2<Float>(pitch, pitch))
  }

  /// Name the environment variables whose absence forced the synthetic readout.
  ///
  /// `CORTEX_MODEL_URL` is listed only for the NDT1 arm. The linear decoder ships in the app bundle,
  /// so demanding a model file for it would send a reader hunting for a checkpoint that this run
  /// never needed.
  private static func missingInputsLabel(
    exportURL: URL?,
    modelURL: URL?,
    kind: ReplayPipeline.Decoder
  ) -> String {
    var missing = [String]()
    if exportURL == nil {
      missing.append("CORTEX_REPLAY_EXPORT")
    }
    if kind == .ndt1, modelURL == nil {
      missing.append("CORTEX_MODEL_URL")
    }
    return "spike source: synthetic (unset: \(missing.joined(separator: ", ")))"
  }
}
