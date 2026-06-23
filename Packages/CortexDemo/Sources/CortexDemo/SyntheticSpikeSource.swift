// SyntheticSpikeSource — Phase 8 (SYS-06, D-10): the deterministic synthetic Indy/Loco spike stream
// that feeds the closed loop, standing in for the gitignored Indy `.mat` replay.
//
// 08-CONTEXT D-10 / 08-RESEARCH §0.3: the v0 closed loop is driven by synthetic Indy/Loco spike replay
// through NDT1 so the CoreML decoder is GENUINELY in the loop. This source emits the `(numBins, 96)`
// fp16 spike windows the NDT1 `spikes` input consumes (the Phase-4 dataset shape: 96 channels, 20ms
// bins — DEC-02), modeling the post-IPC frame the daemon producer would replay into the decoder.
//
// ## Determinism contract (D-13, mirrors CortexReFITBench + ScanInfoRoundTrip)
// CLOSED-FORM, seed/index-driven — NO RNG, NO wall-clock. The spike counts are a pure function of
// (seed, bin index, channel), so two runs on the same seed produce byte-identical windows and the whole
// demo is reproducible. The window models a smoothly-varying population response (a slow sinusoidal
// drift per channel, phase-offset across channels) — enough structure that the decoder/Kalman path has
// a non-trivial signal, with NO hidden entropy. This is a synthetic stand-in; a real-data Indy `.mat`
// loader is a documented follow-on (same posture as CortexReFITBench's synthetic seed-locked replay).
//
// Foundation-free (`import simd` only): a pure value source, no I/O, no clock — it never touches the
// hot path, but staying lean mirrors the seam types' posture.
import simd

/// A deterministic source of `(numBins, 96)` fp16 spike windows for the v0 closed loop (D-10).
///
/// `nonisolated` + `Sendable`: a pure value type holding only its immutable shape + seed. It can be
/// produced/read from any context (the pipeline drives it on the main actor alongside the UI; the bench
/// drives it inline) under the package's `.defaultIsolation(MainActor.self)` posture.
public nonisolated struct SyntheticSpikeSource: Sendable {
  /// Number of recording channels per window — the NDT1 `(1, channels, 1, S)` contract (96 — DEC-02).
  public let channels: Int
  /// Number of 20ms time bins in one decode window (the NDT1 sequence length S).
  public let numBins: Int
  /// The deterministic seed — distinct seeds give distinct (but each individually reproducible) streams.
  public let seed: UInt64

  /// - Parameters:
  ///   - channels: recording channels (default 96 — the Phase-4 Indy/Loco channel count, DEC-02).
  ///   - numBins: 20ms bins per window (default 8 — a short NDT1 window; matches the decoder bench seqLen).
  ///   - seed: the determinism seed.
  public init(channels: Int = 96, numBins: Int = 8, seed: UInt64) {
    precondition(channels > 0 && numBins > 0, "SyntheticSpikeSource requires positive dimensions")
    self.channels = channels
    self.numBins = numBins
    self.seed = seed
  }

  /// The fp16 spike window for the `windowIndex`-th decode tick: a `(numBins, 96)` row-major array
  /// (bin-major: `window[bin * channels + channel]`). Closed-form in `(seed, windowIndex, bin, channel)`
  /// — NO RNG, NO clock — so identical inputs yield identical bytes (D-13).
  ///
  /// Each channel carries a slow sinusoidal firing-rate drift (rate in spikes/bin), phase-offset across
  /// channels and advanced by the window+bin index, quantized to a non-negative fp16 count. The result
  /// is a smoothly time-varying population pattern — structure for the decoder path, fully deterministic.
  public func window(_ windowIndex: Int) -> [Float16] {
    var out = [Float16](repeating: 0, count: numBins * channels)
    for bin in 0 ..< numBins {
      // Global bin index across the whole stream (so successive windows continue the drift, not reset).
      let t = Float(windowIndex * numBins + bin)
      for channel in 0 ..< channels {
        // Per-channel phase + frequency from a closed-form mix of (seed, channel) — deterministic, no RNG.
        let phase = Self.channelPhase(seed: seed, channel: channel)
        let freq = 0.08 + 0.04 * Self.unitHash(seed, UInt64(channel) &* 2_654_435_761 &+ 1)
        // Firing rate in [0, ~4] spikes/bin: a rectified slow sinusoid (smooth, non-negative).
        let rate = 2.0 * (1.0 + sinf(freq * t + phase))
        out[bin * channels + channel] = Float16(rate)
      }
    }
    return out
  }

  /// A per-channel phase offset in [0, 2π) from a closed-form hash of (seed, channel).
  private static func channelPhase(seed: UInt64, channel: Int) -> Float {
    Float(unitHash(seed, UInt64(channel) &* 0x9E37_79B9 &+ 0xABCD)) * (2.0 * Float.pi)
  }

  /// A small deterministic hash of (seed, index) → [0,1) — the same SplitMix64-finalizer idiom as
  /// CortexReFITBench's `unitHash` (a pure function; identical output for identical inputs, no RNG).
  static func unitHash(_ seed: UInt64, _ index: UInt64) -> Float {
    var z = (seed &+ 0x9E37_79B9_7F4A_7C15) ^ (index &* 0x9E37_79B9_7F4A_7C15)
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z = z ^ (z >> 31)
    // Top 24 bits → [0,1) Float (uint → unit-float construction; fp16-safe magnitude).
    return Float(z >> 40) * (1.0 / 16_777_216.0) // 2^-24
  }
}
