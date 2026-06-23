// WebgridAcquisition — the dwell-to-select + per-trial-timeout acquisition model over the 30×30
// webgrid (REFIT-03, D-08). Pure deterministic value type, no I/O, no clock, no RNG.
//
// A TRIAL: a target cell center is active; the cursor (driven by the integrator in the harness) is
// sampled each tick. A HIT registers when the cursor stays within the acquisition radius of the
// target center for a CONTINUOUS dwell window; a TIMEOUT registers when the dwell is not satisfied
// within the per-trial timeout. The classic BrainGate/Webgrid dwell-to-select convention (D-08).
//
// ## Documented defaults (07-RESEARCH §4.4 — recorded in 07-bps-evidence.md)
// - dwell ≈ 300–500 ms (default 0.30 s) — the continuous hold that commits a selection.
// - acquisition radius = ½ cell of the 30×30 grid = `0.5 / 30` in `[0,1]` space (default).
// - per-trial timeout ≈ 5–10 s (default 5 s) — caps unreachable targets.
// All three are configurable parameters with these defaults.
//
// ## Determinism (07-RESEARCH §7 pitfall 8)
// `runTrial` is a pure function of `(positions, target)` and the stored parameters — it reads no
// clock and draws no randomness; movement time is `ticks · dt`, index-driven. Two runs over the same
// sampled-position sequence return identical results, so the BPS the harness builds on it is
// bit-reproducible.
//
// ## Hot-path note (off the policed path, kept Foundation-free anyway)
// Lives under the hotpath-policed `Packages/CortexReFIT/Sources/CortexReFIT` dir, so it stays
// `import simd` only (it is harness/measurement code, NOT the audio hot path, but Foundation-free
// keeps the policed dir clean — `simd_distance` is all it needs).
import simd

/// The dwell-to-select + per-trial-timeout acquisition model over the 30×30 webgrid geometry (D-08).
/// A `Sendable` value type holding only the immutable trial parameters.
public nonisolated struct WebgridAcquisition: Sendable {
  /// Continuous on-target hold required to register a selection (seconds). Default 0.30 s
  /// (07-RESEARCH §4.4: 300–500 ms).
  public let dwellSeconds: Double
  /// On-target acquisition radius in grid-normalised `[0,1]` space. Default `0.5 / 30` = half a cell
  /// pitch of the 30×30 grid (07-RESEARCH §4.4).
  public let acquisitionRadius: Float
  /// Per-trial timeout (seconds) — caps an unreachable target as a TIMEOUT. Default 5 s.
  public let timeoutSeconds: Double
  /// Tick period (seconds). Default 0.020 s (the 20 ms decode/filter tick, ``KalmanConstants/dt``).
  public let dt: Double

  /// - Parameters use the 07-RESEARCH §4.4 documented defaults.
  public init(
    dwellSeconds: Double = 0.30,
    acquisitionRadius: Float = 0.5 / 30.0,
    timeoutSeconds: Double = 5.0,
    dt: Double = 0.020
  ) {
    self.dwellSeconds = dwellSeconds
    self.acquisitionRadius = acquisitionRadius
    self.timeoutSeconds = timeoutSeconds
    self.dt = dt
  }

  /// The number of CONTINUOUS in-radius ticks that satisfy the dwell (ceil(dwell/dt), at least 1).
  public var dwellTicks: Int {
    Swift.max(1, Int((dwellSeconds / dt).rounded(.up)))
  }

  /// The maximum number of ticks before the trial times out (ceil(timeout/dt), at least 1).
  public var timeoutTicks: Int {
    Swift.max(1, Int((timeoutSeconds / dt).rounded(.up)))
  }

  /// The outcome of one acquisition trial.
  public struct TrialResult: Sendable, Equatable {
    /// True if the dwell was satisfied within the timeout (a HIT); false on TIMEOUT.
    public let acquired: Bool
    /// Movement time in seconds = (tick index at which the dwell completed) · dt. On a TIMEOUT this
    /// is the full elapsed trial time (timeout). Used as `MT` for an acquired trial.
    public let movementTime: Double
    /// The cursor position at the tick the dwell completed (the endpoint), or the last sampled
    /// position on a timeout. Feeds the endpoint-scatter `SDx`.
    public let endpoint: SIMD2<Float>

    public init(acquired: Bool, movementTime: Double, endpoint: SIMD2<Float>) {
      self.acquired = acquired
      self.movementTime = movementTime
      self.endpoint = endpoint
    }
  }

  /// Run one trial over a pre-sampled cursor-position sequence (one position per tick) against the
  /// active `target` cell center. Pure: the result is fully determined by the inputs + parameters.
  ///
  /// Dwell logic: a running counter increments while the cursor is within `acquisitionRadius` of the
  /// target and RESETS to zero on any tick the cursor leaves the radius (the dwell must be
  /// CONTINUOUS). When the counter reaches `dwellTicks`, the trial is acquired; movement time is the
  /// elapsed time to that tick. If the trial exhausts `positions` (or `timeoutTicks`) without
  /// satisfying the dwell, it is a TIMEOUT.
  ///
  /// - Parameters:
  ///   - positions: the cursor position sampled each tick (grid-normalised `[0,1]`).
  ///   - target: the active target cell center (grid-normalised `[0,1]`).
  /// - Returns: the ``TrialResult`` (acquired + movement time + endpoint).
  public func runTrial(positions: [SIMD2<Float>], target: SIMD2<Float>) -> TrialResult {
    let maxTicks = Swift.min(positions.count, timeoutTicks)
    var continuousInRadius = 0

    for tick in 0 ..< maxTicks {
      let p = positions[tick]
      if simd_distance(p, target) <= acquisitionRadius {
        continuousInRadius += 1
        if continuousInRadius >= dwellTicks {
          // Dwell satisfied at this tick (1-based elapsed-tick count = tick + 1).
          let movementTime = Double(tick + 1) * dt
          return TrialResult(acquired: true, movementTime: movementTime, endpoint: p)
        }
      } else {
        continuousInRadius = 0 // the dwell must be continuous — any exit resets it.
      }
    }

    // TIMEOUT: never satisfied the dwell within the budget.
    let lastIndex = Swift.max(0, maxTicks - 1)
    let endpoint = positions.isEmpty ? target : positions[Swift.min(lastIndex, positions.count - 1)]
    let elapsed = Double(maxTicks) * dt
    return TrialResult(acquired: false, movementTime: elapsed, endpoint: endpoint)
  }
}
