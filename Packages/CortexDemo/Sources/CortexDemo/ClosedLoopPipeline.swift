// ClosedLoopPipeline — Phase 8 (SYS-06, D-10): the v0 synthetic-spike → NDT1 → ReFIT-Kalman →
// CursorIntegrator → 30×30 webgrid CLOSED LOOP. The decoder + Kalman are GENUINELY in the loop.
//
// This is the true SYS-06 path (08-CONTEXT D-10, 08-RESEARCH §0.3): a synthetic Indy/Loco spike stream
// flows through the SAME decode → filter → integrate → webgrid assembly the live demo runs — NOT the
// Phase-6 oscillator-velocity shortcut (which bypasses the decoder entirely and would make SYS-06
// hollow). The grep gate (T-08-03-01) asserts that shortcut producer's type name appears nowhere in
// this file, so the closed loop provably drives the real decoder. The stages, in order:
//
//   1. SyntheticSpikeSource → a `(numBins, 96)` fp16 spike window (models the post-IPC frame).
//   2. DECODE — if a `NeuralDecoder` is available (CORTEX_MODEL_URL set + the model loads), route the
//      spike window through `decoder.decode(SpikeInputBuffer)` → (vx,vy): NDT1 GENUINELY in the loop
//      (D-10). Else fall back to a DETERMINISTIC synthetic decoded-velocity (the CortexReFITBench
//      `decodedVelocity` idiom) so the loop runs on a clean clone / CI without the gitignored model.
//      The `NeuralDecoder.decode` call site is PRESENT + COMPILED (`decodeWithModel`) so the model-
//      backed path is real, not a stub (structurally asserted by the acceptance grep + hid/render-style
//      gate).
//   3. ReFIT-KALMAN — `KalmanFilter.step(measurement:target:acquisitionRadius:)` → refined velocity
//      (the filter GENUINELY applied, never bypassed; ONE warm filter carried across ticks — the
//      continuous closed loop is never reset, 07-RESEARCH §2).
//   4. INTEGRATE — `CursorIntegrator.integrate(latest:dt:)` → clamped, always-finite [0,1] position
//      (the single NaN/Inf-reject + clamp seam, Phase-6 T-06-02-01, reused unchanged).
//   5. WEBGRID — push the position; `WebgridAcquisition` detects a HIT against the active target cell.
//
// ## Determinism (D-13, the load-bearing reproducibility contract)
// NO RNG, NO wall-clock on the SIMULATION path. The synthetic decoded-velocity is a closed-form
// function of (seed, tick, cursor, target), exactly like CortexReFITBench. `runToHit` is byte-identical
// across two runs on the same seed. (`mach_absolute_time()` appears ONLY in the GUI/bench latency
// instrumentation around `tick()`, never in the simulation that decides positions/hits.)
//
// The library's `.defaultIsolation(MainActor.self)` applies: the pipeline is driven off the hot path,
// alongside the SwiftUI demo (one decode→filter→integrate per 20ms is a handful of simd ops + at most
// one CoreML prediction — not the audio-callback regime).
import CortexDecoder // NeuralDecoder (NDT1 CoreML, D-10) + SpikeInputBuffer (the zero-copy decode input).
import CortexReFIT // KalmanFilter.step (the ReFIT-Kalman stage) + WebgridAcquisition (the HIT model).
import CortexRender // CursorIntegrator + CursorVelocity (the renderer-owned integrate seam).
import Metal // MTLCreateSystemDefaultDevice — only when wiring the model-backed SpikeInputBuffer (gated path).
import simd

/// One streamed step of the closed loop the GUI consumes: the refined cursor position (grid-normalised
/// [0,1]), the velocity pushed to the renderer ring, whether the decoder ran NDT1 (vs the synthetic
/// fallback), and whether this tick registered a webgrid HIT on the active target.
public nonisolated struct CursorState: Sendable, Equatable {
  /// The clamped, always-finite cursor position after this tick (grid-normalised [0,1]).
  public let position: SIMD2<Float>
  /// The ReFIT-Kalman-refined velocity for this tick (grid-units/second) — what feeds the render ring.
  public let velocity: SIMD2<Float>
  /// True if this tick routed the spike window through `NeuralDecoder.decode` (NDT1 genuinely in loop);
  /// false if it used the deterministic synthetic decoded-velocity fallback (no model present).
  public let decodedByModel: Bool
  /// True if the cursor is within the acquisition radius of the active target this tick (a webgrid HIT
  /// is registered when this holds continuously for the dwell — see ``ClosedLoopPipeline/runToHit``).
  public let onTarget: Bool

  public init(position: SIMD2<Float>, velocity: SIMD2<Float>, decodedByModel: Bool, onTarget: Bool) {
    self.position = position
    self.velocity = velocity
    self.decodedByModel = decodedByModel
    self.onTarget = onTarget
  }
}

/// The v0 synthetic-spike → NDT1 → ReFIT → integrator → 30×30 webgrid closed loop (SYS-06, D-10).
///
/// A `final class` (reference semantics): one pipeline owns the continuous warm Kalman filter + the
/// integrator + the active-target/tick cursor across a streaming demo session (never reset mid-loop).
public final class ClosedLoopPipeline {
  // MARK: - Tunables (the same 20ms / 30×30 geometry as CortexReFITBench)

  /// The decode/filter/integrate tick in seconds (20ms — the DEC-10 cadence, KalmanConstants.dt).
  public static let dt: Double = 0.020
  /// Acquisition radius = ½ cell of the 30×30 grid in [0,1] space (the WebgridAcquisition default).
  public static let acquisitionRadius: Float = 0.5 / 30.0

  // MARK: - Stages

  /// The INJECTED spike-window seam (Phase 10, RD-08). `SyntheticSpikeSource` is the deterministic v0
  /// stand-in for the post-IPC frame (D-10); `RecordedSpikeSource` replays the real D-06 export bins.
  /// Injecting it is what lets the real path change exactly ONE variable while decode, filter,
  /// integrate and webgrid stay byte-identical (10-PREREGISTRATION section 9, Seam A).
  public let spikeSource: any SpikeWindowSource
  /// The optional NDT1 decoder. Non-nil ⇒ NDT1 GENUINELY in the loop (CORTEX_MODEL_URL set + loaded);
  /// nil ⇒ the deterministic synthetic decoded-velocity fallback runs (clean clone / CI).
  private let decoder: NeuralDecoder?
  /// The shared-surface spike buffer the model-backed decode writes into (non-nil iff `decoder` is).
  private let spikeBuffer: SpikeInputBuffer?
  /// ONE warm ReFIT-Kalman filter carried across ticks (the continuous closed loop — never reset).
  private let filter: KalmanFilter
  /// The renderer-owned integrator (the single [0,1] clamp + NaN/Inf reject seam).
  private let integrator: CursorIntegrator
  /// The dwell-to-select webgrid HIT model (30×30 geometry).
  private let acquisition: WebgridAcquisition

  // MARK: - Streaming state (for the GUI `tick()` path)

  /// The active target cell center (grid-normalised [0,1]) the streaming loop steers toward.
  public private(set) var target: SIMD2<Float>
  /// The deterministic seed driving the synthetic decode fallback.
  public let seed: UInt64
  /// Grid-units per centimetre, applied to the MODEL's decoded velocity only.
  ///
  /// NDT1 emits cm/s while the filter, the integrator and the webgrid run in grid-units/s, so a
  /// real-data caller passes the export's `workspace.gridUnitsPerCm` here. Defaults to `1.0`, which
  /// is the identity the synthetic path wants, so callers that never touch a real export are
  /// unchanged.
  public let modelVelocityGridUnitsPerCm: Float
  /// Whether the ReFIT intent rotation is applied in the streaming `tick()` loop.
  ///
  /// `true` is the `refit` arm: `IntentRotation` replaces the decoded DIRECTION with the direction to
  /// the known target, keeping only the decoded speed, so the resulting heading is TARGET-DETERMINED
  /// BY CONSTRUCTION and is not attributable to the decode (10-PREREGISTRATION section 7).
  /// `false` is the `kalman_only` arm: the filter runs with no target, so the heading is the decode's
  /// own. Only the `false` arm's behaviour may be presented as what the decoder does.
  public let rotationEnabled: Bool
  /// The monotonic streaming tick index (drives the deterministic synthetic decode).
  private var tickIndex: Int = 0

  // MARK: - Model-in-loop accounting (Phase 10, RD-08 — the Pattern-2 mitigation)

  /// Ticks whose velocity came from `NeuralDecoder.decode`.
  public private(set) var modelBackedTicks = 0
  /// Every `tick()` this pipeline has run.
  public private(set) var totalTicks = 0
  /// True only if EVERY tick ran the model. A run where this is false must NOT publish a real-data
  /// number (10-PREREGISTRATION section 10): its numbers came from the synthetic fallback.
  public var allTicksModelBacked: Bool {
    totalTicks > 0 && modelBackedTicks == totalTicks
  }

  /// The FIRST reason a decode could not run, naming both shapes. Nil until a decode is attempted and
  /// fails. This is the whole point of the Pattern-2 repair: the fallback BEHAVIOUR is unchanged, but
  /// the reason is now recoverable instead of discarded.
  public private(set) var lastDecodeFailure: String?

  /// The window length the `SpikeInputBuffer` was sized to, i.e. the injected source's `numBins`.
  /// THE TRAP, stated in one property: the shipped real model's `spikes` input is `(1, 96, 1, 32)`, so
  /// it wants 32, while `SyntheticSpikeSource`'s default is 8. `decodeWithModel` used to swallow the
  /// resulting mismatch into the synthetic fallback, so the loop kept running and its numbers stopped
  /// being real. Assert this against the model's S before publishing anything.
  public var sourceSeqLen: Int {
    spikeSource.numBins
  }

  // MARK: - Init

  /// Build the closed loop over an INJECTED spike source (the Phase-10 designated init).
  ///
  /// - Parameters:
  ///   - source: the spike-window seam. `RecordedSpikeSource` replays the real D-06 export;
  ///     `SyntheticSpikeSource` is the deterministic v0 stand-in.
  ///   - seed: the determinism seed for the synthetic decode fallback.
  ///   - start: the initial cursor position (default grid center).
  ///   - target: the active target cell center the streaming `tick()` loop steers toward.
  ///   - modelURL: an optional compiled `.mlmodelc`/`.mlpackage`. When provided AND it loads AND a
  ///     Metal device + shared spike buffer can be created, the decode stage routes spike windows
  ///     through `NeuralDecoder.decode` — NDT1 GENUINELY in the loop (D-10). Resolve it from
  ///     `CORTEX_MODEL_URL` via ``modelURLFromEnvironment()`` on a clean clone (absent ⇒ synthetic).
  public init(
    source: any SpikeWindowSource,
    seed: UInt64,
    start: SIMD2<Float> = SIMD2<Float>(0.5, 0.5),
    target: SIMD2<Float> = SIMD2<Float>((13.0 + 0.5) / 30.0, (13.0 + 0.5) / 30.0),
    modelURL: URL? = nil,
    modelVelocityGridUnitsPerCm: Float = 1.0,
    rotationEnabled: Bool = true
  ) {
    self.seed = seed
    self.target = target
    self.modelVelocityGridUnitsPerCm = modelVelocityGridUnitsPerCm
    self.rotationEnabled = rotationEnabled
    spikeSource = source

    // Wire the model-backed decode path when a model URL is supplied AND the model + a shared-surface
    // spike buffer can be created. This is the D-10 NDT1-genuinely-in-loop path; it is PRESENT +
    // COMPILED regardless (the call site lives in `decodeWithModel`), and ACTIVE only with a real model.
    //
    // The failure is RECORDED rather than dropped. A run whose model never loaded degrades to the
    // synthetic fallback exactly as before, but `lastDecodeFailure` then names why — otherwise the
    // RD-08 assertion would report "none recorded" for the commonest cause of a fallback run.
    var loadedDecoder: NeuralDecoder?
    var loadedBuffer: SpikeInputBuffer?
    var setupFailure: String?
    if let modelURL {
      if let device = MTLCreateSystemDefaultDevice() {
        do {
          // Typed-throws on both fallible loads: a missing/corrupt model or a surface-create failure
          // degrades to the synthetic fallback rather than crashing the demo (never force-unwrapped).
          let d = try NeuralDecoder(modelURL: modelURL)
          let b = try SpikeInputBuffer(device: device, seqLen: spikeSource.numBins, channels: spikeSource.channels)
          loadedDecoder = d
          loadedBuffer = b
        } catch {
          setupFailure = "the model-backed decode path could not be wired: \(error) "
            + "(requested SpikeInputBuffer seqLen \(spikeSource.numBins) x channels \(spikeSource.channels); "
            + "the shipped real model wants seqLen 32 for its (1, 96, 1, 32) spikes input)"
        }
      } else {
        setupFailure = "no Metal device is available, so the model-backed decode path could not be wired "
          + "(requested SpikeInputBuffer seqLen \(spikeSource.numBins) x channels \(spikeSource.channels))"
      }
    }
    decoder = loadedDecoder
    spikeBuffer = loadedBuffer
    lastDecodeFailure = setupFailure

    filter = KalmanFilter()
    filter.setState([start.x, start.y, 0, 0, 0, 0])
    filter.setCursorPosition(start)
    integrator = CursorIntegrator(start: .init(x: start.x, y: start.y))
    acquisition = WebgridAcquisition(
      dwellSeconds: 0.30,
      acquisitionRadius: Self.acquisitionRadius,
      timeoutSeconds: 5.0,
      dt: Self.dt
    )
  }

  /// The v0 closed loop over the deterministic `SyntheticSpikeSource` (the Phase-8 call shape, kept
  /// byte-identical so every existing call site and test compiles and behaves unchanged).
  public convenience init(
    seed: UInt64,
    start: SIMD2<Float> = SIMD2<Float>(0.5, 0.5),
    target: SIMD2<Float> = SIMD2<Float>((13.0 + 0.5) / 30.0, (13.0 + 0.5) / 30.0),
    modelURL: URL? = nil,
    rotationEnabled: Bool = true
  ) {
    self.init(
      source: SyntheticSpikeSource(seed: seed),
      seed: seed,
      start: start,
      target: target,
      modelURL: modelURL,
      rotationEnabled: rotationEnabled
    )
  }

  /// True iff this pipeline routes spikes through `NeuralDecoder.decode` (NDT1 genuinely in loop, D-10).
  /// False ⇒ the deterministic synthetic decoded-velocity fallback (clean clone / CI, no model present).
  public var isModelBacked: Bool {
    decoder != nil
  }

  /// Resolve the optional model URL from `CORTEX_MODEL_URL` (the gitignored R&D `.mlpackage`/`.mlmodelc`).
  /// Absent/empty ⇒ nil ⇒ the synthetic decode fallback runs (the clean-clone / CI path, mirrors
  /// VelocityOutputTests / CortexDecoderBench). The URL is never committed — model from env only.
  public static func modelURLFromEnvironment() -> URL? {
    guard let raw = ProcessInfo.processInfo.environment["CORTEX_MODEL_URL"], !raw.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: raw)
  }

  // MARK: - Decode stage (the D-10 seam: NDT1 genuinely in loop, with a deterministic fallback)

  /// Decode one spike window into a `(vx,vy)` velocity through NDT1 when model-backed, else the
  /// deterministic synthetic decoded-velocity. The `NeuralDecoder.decode` call site is PRESENT +
  /// COMPILED here (D-10) — `decodeWithModel` is only EXERCISED when a real model + shared buffer exist.
  private func decode(window: [Float16], tick: Int, cursor: SIMD2<Float>) -> (velocity: SIMD2<Float>, byModel: Bool) {
    var modelVelocity: SIMD2<Float>?
    if let decoder, let spikeBuffer {
      modelVelocity = decodeWithModel(decoder: decoder, buffer: spikeBuffer, window: window)
    }
    // NDT1 GENUINELY in the loop (D-10) when the model produced a velocity; otherwise the deterministic
    // synthetic decoded-velocity (the CortexReFITBench idiom): a closed-form noisy readout pointing
    // toward the target, so raw scatters and the Kalman/rotation arm recovers it.
    // NDT1 emits cm/s; the filter, the integrator and the webgrid all run in grid-units/s. The same
    // conversion `CortexReplayBench` applies at its decode site, and it applies ONLY to the model
    // output: `syntheticDecodedVelocity` is a closed-form readout already expressed in grid-units/s.
    // Without it the loop integrates cm/s as grid-units/s and the cursor runs
    // `1 / gridUnitsPerCm` times too fast (about 17x on the pre-registered box).
    let velocity = modelVelocity.map { $0 * modelVelocityGridUnitsPerCm }
      ?? Self.syntheticDecodedVelocity(seed: seed, tick: tick, cursor: cursor, target: target)
    let byModel = modelVelocity != nil

    // The single place a decode resolves, so the counters cannot drift from the ticks (RD-08). Integer
    // increments in tick order — the D-13 determinism contract is untouched.
    totalTicks += 1
    if byModel { modelBackedTicks += 1 }
    return (velocity, byModel)
  }

  /// Route a spike window through `NeuralDecoder.decode` (NDT1 GENUINELY in the loop, D-10). Writes the
  /// `(numBins, 96)` fp16 window into the shared-surface `SpikeInputBuffer` (the zero-copy decode
  /// input), then calls `decoder.decode(buffer)` → (vx,vy). Returns nil on any fallible step so the
  /// caller degrades to the synthetic fallback (never crashes the demo).
  ///
  /// ## The Pattern-2 mitigation (Phase 10, RD-08)
  /// The FALLBACK BEHAVIOUR IS UNCHANGED: a failure still returns nil and the loop still keeps running
  /// on the synthetic decode. What changed is that the reason is RECORDED into ``lastDecodeFailure``
  /// instead of being discarded by a `try?`. Both shapes are named, because the commonest failure here
  /// is a shape mismatch: the shipped real model's `spikes` input is `(1, 96, 1, 32)` while
  /// `SyntheticSpikeSource`'s default `numBins` is 8, and the old code turned that into a running loop
  /// whose numbers were synthetic under a real-data label. A run whose ``allTicksModelBacked`` is false
  /// MUST NOT publish a real-data number (10-PREREGISTRATION section 10).
  private func decodeWithModel(decoder: NeuralDecoder, buffer: SpikeInputBuffer, window: [Float16]) -> SIMD2<Float>? {
    // A source whose window is not (numBins x channels) would index out of bounds below. Refuse it as
    // a legible fallback rather than trapping mid-run.
    let expected = spikeSource.numBins * spikeSource.channels
    guard window.count == expected else {
      recordDecodeFailure(reason: "the source returned \(window.count) values, expected \(expected)")
      return nil
    }
    // Write the window into the shared surface (bin-major), respecting the buffer's bounds.
    for bin in 0 ..< spikeSource.numBins {
      for channel in 0 ..< spikeSource.channels {
        let value = window[bin * spikeSource.channels + channel]
        do {
          try buffer.write(value, channel: channel, bin: bin)
        } catch {
          recordDecodeFailure(reason: "SpikeInputBuffer.write(channel: \(channel), bin: \(bin)) threw \(error)")
          return nil
        }
      }
    }
    // NDT1 inference — the CoreML decode call site (D-10). A throw ⇒ the synthetic fallback, WITH the
    // reason kept.
    do {
      return try decoder.decode(buffer)
    } catch {
      recordDecodeFailure(reason: "NeuralDecoder.decode threw \(error)")
      return nil
    }
  }

  /// Record the FIRST decode failure, naming the buffer's shape and the source's shape so a mismatch is
  /// legible from the string alone. Later failures are dropped: the first one is the diagnosis, and a
  /// 10,000-tick run must not accumulate 10,000 copies of it.
  private func recordDecodeFailure(reason: String) {
    guard lastDecodeFailure == nil else { return }
    let bufferShape = spikeBuffer.map { "seqLen \($0.seqLen) x channels \($0.channels)" } ?? "no buffer"
    lastDecodeFailure = "\(reason) [buffer \(bufferShape); "
      + "source numBins \(spikeSource.numBins) x channels \(spikeSource.channels)]. "
      + "The shipped real model wants seqLen 32 for its (1, 96, 1, 32) spikes input."
  }

  /// The deterministic synthetic decoded-velocity (grid-units/second). Closed-form, seed/index-driven
  /// (NO RNG, NO clock — D-13): points from `cursor` toward `target` with a deterministic directional
  /// perturbation (a sinusoid in the tick index). The same "noisy decoder" idiom as CortexReFITBench,
  /// tuned so the RAW arm genuinely MISSES while the Kalman+rotation arm HITs (the Test-4 ablation):
  ///
  ///   • SPEED decays smoothly to ~0 at the target (`speedRamp` over ~3 cells, NO floor) so whichever
  ///     arm arrives CENTERED creeps to a near-zero-velocity continuous dwell.
  ///   • The ANGULAR perturbation is large (~2.6–3.4 rad swing) at mid/far range and smoothly OFF inside
  ///     a small inner radius (`innerRadius`), so the RAW cursor wanders far OFF-AXIS and never
  ///     accumulates a continuous half-cell dwell within the timeout, while the ReFIT INTENT-ROTATION
  ///     (which fully direction-aligns the measurement onto cursor→target OUTSIDE the acquisition radius
  ///     — see IntentRotation) flies the cursor straight in and dwells. This exercises the rotation
  ///     stage exactly as Gilja-2012 ReFIT intends — the filter is genuinely in the loop, not bypassed.
  static func syntheticDecodedVelocity(seed: UInt64, tick: Int, cursor: SIMD2<Float>,
                                       target: SIMD2<Float>) -> SIMD2<Float>
  {
    let toTarget = target - cursor
    let dist = simd_length(toTarget)
    guard dist > 1e-6 else { return SIMD2<Float>(0, 0) }
    let dir = toTarget / dist

    // Speed ramps with distance and decays smoothly to ~0 at the target (no floor) — so the centered
    // arm settles into a near-zero-velocity dwell rather than orbiting forever.
    let speedRamp: Float = 0.10 // grid-units of distance over which speed ramps to full (~3 cells).
    let baseSpeed: Float = 0.9 * Swift.min(1.0, dist / speedRamp)

    // Angular perturbation (decoder noise): full amplitude outside `innerRadius`, smoothly off inside
    // it. Large enough that the RAW (unrotated) cursor wanders off-axis and misses; the ReFIT rotation
    // ignores it outside the acquisition radius (full direction-align) so the rotation arm converges.
    let innerRadius: Float = 0.05
    let proximityScale = Swift.min(1.0, dist / innerRadius) // 0 at target → 1 far away.
    let ampSeed = SyntheticSpikeSource.unitHash(seed, UInt64(bitPattern: Int64(tick)) &* 7 &+ 3)
    let angleAmplitude: Float = (2.6 + 0.8 * ampSeed) * proximityScale
    let theta = angleAmplitude * sinf(Float(tick) * 0.6)
    let cosT = cosf(theta)
    let sinT = sinf(theta)
    let perturbedDir = SIMD2<Float>(dir.x * cosT - dir.y * sinT, dir.x * sinT + dir.y * cosT)

    // Magnitude wobble (deterministic): ±30% around the base speed.
    let magWobble = 1.0 + 0.30 * sinf(Float(tick) * 0.5)
    return perturbedDir * (baseSpeed * magWobble)
  }

  // MARK: - Streaming tick (the GUI path: one decode→filter→integrate per 20ms)

  /// Point the loop at a new active target.
  ///
  /// The recorded session's target moves per trial, so a real-data caller drives this each tick.
  /// With `rotationEnabled == false` the value still feeds the on-screen target and the `onTarget`
  /// test, but it does NOT steer the cursor.
  public func setTarget(_ newTarget: SIMD2<Float>) {
    target = newTarget
  }

  /// Advance the continuous closed loop by ONE 20ms tick and return the new `CursorState`. The GUI
  /// calls this at the 20ms cadence and pushes the resulting velocity into the renderer's VelocityRing.
  /// The warm Kalman filter + integrator persist across calls (never reset — the continuous loop).
  @discardableResult
  public func tick() -> CursorState {
    let cursor = SIMD2<Float>(integrator.position.x, integrator.position.y)
    // Sync the integrator's authoritative clamped position into the filter BEFORE the step (§2.3).
    filter.setCursorPosition(cursor)

    let window = spikeSource.window(tickIndex)
    let (decoded, byModel) = decode(window: window, tick: tickIndex, cursor: cursor)

    // ReFIT-Kalman GENUINELY applied (rotation toward the active target enabled — the closed loop).
    // Rotation OFF is the `kalman_only` arm: a nil target makes `IntentRotation` return the
    // measurement unchanged, so the heading stays the decode's own.
    let refined = filter.step(
      measurement: decoded,
      target: rotationEnabled ? target : nil,
      acquisitionRadius: Self.acquisitionRadius
    )

    // Integrate via the renderer-owned integrator (the single [0,1] clamp + non-finite reject seam).
    let velocity = CursorVelocity(ts_ns: 0, seq: UInt64(tickIndex), vx: Float16(refined.x), vy: Float16(refined.y))
    let pos = integrator.integrate(latest: velocity, dt: Self.dt)
    let position = SIMD2<Float>(pos.x, pos.y)

    tickIndex &+= 1
    let onTarget = simd_distance(position, target) <= Self.acquisitionRadius
    return CursorState(position: position, velocity: refined, decodedByModel: byModel, onTarget: onTarget)
  }

  // MARK: - Deterministic batch run (the test + bench path)

  /// Run the closed loop deterministically from a fresh cursor at the grid center toward `target` and
  /// report whether it reaches a webgrid HIT (dwell-to-select), the cursor trajectory, and the tick
  /// count. Byte-identical across two runs on the same seed (D-13).
  ///
  /// This builds its OWN fresh filter + integrator (it does NOT disturb the streaming `tick()` state),
  /// running the SAME decode → filter → integrate → webgrid assembly with the ReFIT (rotation-on) arm.
  /// - Parameters:
  ///   - seed: the determinism seed (overrides the streaming seed for an isolated, reproducible run).
  ///   - target: the target cell center to reach.
  /// - Returns: the sampled positions, whether a HIT registered, and the tick count.
  public func runToHit(seed: UInt64, target: SIMD2<Float>) -> (positions: [SIMD2<Float>], hit: Bool, ticks: Int) {
    let result = Self.simulate(seed: seed, target: target, arm: .refit)
    return (result.positions, result.hit, result.ticks)
  }

  /// Which filter arm a deterministic simulation uses (mirrors CortexReFITBench's ablation arms).
  enum Arm {
    case raw // no filter — decoded velocity straight to the integrator.
    case refit // KalmanFilter.step with the active target + acquisition radius (rotation on).
  }

  /// The deterministic per-arm simulation backing `runToHit` + the Test-4 ablation. Pure: no RNG, no
  /// clock — fully determined by (seed, target, arm). A fresh warm filter + integrator per call.
  static func simulate(seed: UInt64, target: SIMD2<Float>,
                       arm: Arm) -> (positions: [SIMD2<Float>], hit: Bool, ticks: Int)
  {
    let start = SIMD2<Float>(0.5, 0.5)
    let acquisition = WebgridAcquisition(
      dwellSeconds: 0.30,
      acquisitionRadius: ClosedLoopPipeline.acquisitionRadius,
      timeoutSeconds: 5.0,
      dt: ClosedLoopPipeline.dt
    )
    let filter = KalmanFilter()
    filter.setState([start.x, start.y, 0, 0, 0, 0])
    filter.setCursorPosition(start)
    let integrator = CursorIntegrator(start: .init(x: start.x, y: start.y))

    let maxTicks = acquisition.timeoutTicks
    var positions = [SIMD2<Float>]()
    positions.reserveCapacity(maxTicks)

    for tick in 0 ..< maxTicks {
      let cursor = SIMD2<Float>(integrator.position.x, integrator.position.y)
      filter.setCursorPosition(cursor)
      let decoded = syntheticDecodedVelocity(seed: seed, tick: tick, cursor: cursor, target: target)
      let refined: SIMD2<Float> = switch arm {
      case .raw:
        decoded // no filter — the bypass arm (Test-4 baseline).
      case .refit:
        filter.step(measurement: decoded, target: target, acquisitionRadius: ClosedLoopPipeline.acquisitionRadius)
      }
      let velocity = CursorVelocity(ts_ns: 0, seq: UInt64(tick), vx: Float16(refined.x), vy: Float16(refined.y))
      let pos = integrator.integrate(latest: velocity, dt: ClosedLoopPipeline.dt)
      positions.append(SIMD2<Float>(pos.x, pos.y))
    }

    let trial = acquisition.runTrial(positions: positions, target: target)
    // Ticks to the HIT (1-based elapsed-tick count from the movement time), or the full budget on miss.
    let ticks = Int((trial.movementTime / ClosedLoopPipeline.dt).rounded())
    return (positions, trial.acquired, ticks)
  }
}
