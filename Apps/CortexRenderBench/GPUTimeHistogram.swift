// GPUTimeHistogram — the RENDER-05 GPU-compute-time measurement core (SC#2 ≤0.4ms).
//
// Measures the REAL 30×30 webgrid compute pass (the same `WebgridFrameEncoder` + `webgrid` kernel
// the live adapters drive — RENDER-04/05, "measure the actual kernel, not a toy") over n ≥ 10k
// frames, reducing per-frame `commandBuffer.gpuEndTime - gpuStartTime` (CFTimeInterval seconds,
// public, valid after the buffer completes — 06-RESEARCH Decision 6) into a device-annotated
// p50/p95/p99 histogram. Mirrors the Phase-5 `CortexDecoderBench` discipline: a dedicated bench
// executable, warmup + N passes, p50/p99 histogram, committed device-annotated evidence — NOT a
// swift-test timing gate (a flaky latency assertion stays out of CI, D-18).
//
// ## Why an offscreen texture (and why it still measures the SAME kernel)
// A `CAMetalDrawable` requires a live `CAMetalLayer`/window, which a headless `type: tool` bench
// does not have. So the bench encodes the identical `webgrid` kernel into an OFFSCREEN
// `MTLTexture` sized to a representative drawable extent (default 2752×2064 — iPad-Pro-M4-13"-ish;
// configurable WxH). The texture is `.bgra8Unorm` with `.shaderWrite` usage — exactly the write
// scope `MetalLayerConfig` opens on the live drawable (`framebufferOnly = false` ⇒ the drawable
// texture gains `.shaderWrite`). The kernel's `out.write(color, gid)` path, the `setBytes` uniforms
// upload (RENDER-06 zero-copy), the bounds guard, and the `dispatchThreads`-to-extent sizing are
// byte-for-byte the live path. We reuse `WebgridFrameEncoder` UNCHANGED by handing it an
// `OffscreenDrawable` — a `CAMetalDrawable`-conforming wrapper over the offscreen texture whose
// `present()` is a no-op (the bench `commit()`s + `waitUntilCompleted`s instead of presenting).
// What this does NOT measure: the on-display present / refresh-rate path — that is the iPad-M4
// canonical capture (Plan 06, deferred) and the on-panel soak (FrameSoak mode b). The COMPUTE time
// — the SC#2 ≤0.4ms claim — is identical.
//
// ## Threading / allocation
// Single-threaded, allocation-light measure loop: one preallocated `[Double]` sample buffer, no
// per-frame `print()` (os.Logger only if ever needed; here the loop is print-free), the command
// buffer is the only per-frame allocation (unavoidable — it is what carries the GPU timestamps).

import CortexCore
import CortexRender
import Foundation
import Metal
import os
import QuartzCore

/// A `CAMetalDrawable`-conforming wrapper over an offscreen `MTLTexture`, so the bench can drive the
/// real `WebgridFrameEncoder` (which takes a `CAMetalDrawable`) with NO window. `present*` are
/// no-ops — the bench commits + `waitUntilCompleted`s to read the GPU timestamps, it never presents.
///
/// `CAMetalDrawable` refines `MTLDrawable`; both protocols' members are implemented over the wrapped
/// texture / a monotonic drawable id. `@unchecked Sendable` is sound: the only stored state is the
/// immutable texture and a constant id, and the bench uses one wrapper per device on a single thread.
///
/// Module-internal (not `private`) so both `GPUTimeHistogram` and `FrameSoak` reuse the SAME offscreen
/// drawable wrapper — they measure the identical encode path, just over a frame-count vs a duration.
final class OffscreenDrawable: NSObject, CAMetalDrawable, @unchecked Sendable {
  /// The offscreen render target the `webgrid` kernel writes (the drawable's texture).
  let texture: MTLTexture
  /// The `CAMetalLayer` a real drawable belongs to. A headless offscreen target has none.
  var layer: CAMetalLayer {
    _layer
  }

  private let _layer = CAMetalLayer()
  // MTLDrawable conformance.
  let drawableID: Int = 0
  let presentedTime: CFTimeInterval = 0

  init(texture: MTLTexture) {
    self.texture = texture
    super.init()
  }

  // The bench never presents — these satisfy the MTLDrawable protocol as no-ops so encoding the
  // identical kernel does not require a window. (The live adapters call `commandBuffer.present` /
  // `drawable.present()`; the bench substitutes `waitUntilCompleted`.)
  func present() {}
  func present(at _: CFTimeInterval) {}
  func present(afterMinimumDuration _: CFTimeInterval) {}
  func addPresentedHandler(_: @escaping MTLDrawablePresentedHandler) {}
}

/// Percentile summary (milliseconds) over the per-frame GPU-compute-time samples.
struct GPUTimeStats {
  let count: Int
  let p50Ms: Double
  let p95Ms: Double
  let p99Ms: Double
  let minMs: Double
  let maxMs: Double
  let meanMs: Double
}

/// One bench run: the device it ran on, the offscreen extent it ran at, and the percentile stats.
///
/// A named struct rather than a 4-member tuple return (SwiftLint `large_tuple` caps tuples at 2).
/// All four members are load-bearing at the call site -- `main.swift` prints `deviceName` and
/// `stats`, and passes `deviceName`/`width`/`height`/`stats` straight into `writeJSON`, which emits
/// the committed `gpu_time_hist.json`. Member names are unchanged from the tuple labels, so every
/// `.member` access at the call site is source-identical and no emitted key moves.
struct GPUTimeRun {
  let deviceName: String
  let width: Int
  let height: Int
  let stats: GPUTimeStats
}

/// Errors building / running the GPU-time bench.
enum GPUTimeBenchError: Error, CustomStringConvertible {
  case noDevice
  case noCommandQueue
  case noTexture
  case noCommandBuffer

  var description: String {
    switch self {
    case .noDevice: "no system-default MTLDevice (MTLCreateSystemDefaultDevice returned nil)"
    case .noCommandQueue: "device.makeCommandQueue() returned nil"
    case .noTexture: "device.makeTexture() returned nil for the offscreen target"
    case .noCommandBuffer: "queue.makeCommandBuffer() returned nil"
    }
  }
}

/// The GPU-compute-time histogram bench: warm up, then measure the real `webgrid` compute pass over
/// `frames` (≥10k) offscreen frames, reducing `gpuEndTime - gpuStartTime` to a p50/p95/p99 histogram.
enum GPUTimeHistogram {
  private static let log = Logger(subsystem: "app.cortex.renderbench", category: "GPUTimeHistogram")

  /// Build the offscreen render target matching the live drawable's storage/usage.
  ///
  /// `.bgra8Unorm` + `.shaderWrite` mirrors the `MetalLayerConfig` drawable exactly
  /// (`pixelFormat = .bgra8Unorm`, `framebufferOnly = false` ⇒ the drawable texture is
  /// compute-writable). `.storageModePrivate`: GPU-resident, the fastest write target on Apple
  /// Silicon (and the bench never reads the pixels back — it only times the compute).
  private static func makeOffscreenTexture(
    device: MTLDevice, width: Int, height: Int
  ) throws -> MTLTexture {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
    )
    desc.usage = [.shaderWrite, .shaderRead]
    desc.storageMode = .private
    guard let texture = device.makeTexture(descriptor: desc) else {
      throw GPUTimeBenchError.noTexture
    }
    return texture
  }

  /// Run the bench. Drives the cursor deterministically via `LissajousProducer` → `CursorIntegrator`
  /// → `WebgridParams.grid30x30` (so the measured workload is bit-identical run-to-run, D-05), and
  /// measures the SAME `WebgridFrameEncoder` compute pass per frame.
  ///
  /// - Parameters:
  ///   - frames: number of MEASURED frames (≥10_000 per RENDER-05). Defaults applied by `main`.
  ///   - warmup: discarded warmup frames (pipeline + clock warmup, Phase-5 precedent).
  ///   - width/height: the representative offscreen drawable extent.
  /// - Returns: a ``GPUTimeRun``: the device name, the texture extent, and the percentile stats.
  ///
  /// `@MainActor`: `WebgridFrameEncoder` is MainActor-isolated (CortexRender uses
  /// `.defaultIsolation(MainActor.self)`), so its `init` + `encode` must be called on the MainActor.
  /// The bench is single-threaded and runs entirely on the main thread, so this is free.
  @MainActor
  static func run(
    frames: Int, warmup: Int, width: Int, height: Int
  ) throws -> GPUTimeRun {
    guard let device = MTLCreateSystemDefaultDevice() else { throw GPUTimeBenchError.noDevice }
    guard let queue = device.makeCommandQueue() else { throw GPUTimeBenchError.noCommandQueue }

    // The REAL encoder + kernel under measurement (RENDER-04/05 — not a toy).
    let encoder = try WebgridFrameEncoder(device: device)
    let texture = try makeOffscreenTexture(device: device, width: width, height: height)
    let drawable = OffscreenDrawable(texture: texture)

    // Deterministic drive (D-05): closed-form Lissajous velocity → clamped position. The renderer's
    // own integrator, so the measured params match what the live path would produce.
    let producer = LissajousProducer()
    let integrator = CursorIntegrator()
    let dt = 1.0 / 120.0 // nominal 120Hz frame delta for the deterministic integration step.

    /// Encode + commit + wait one frame at simulated time `t`, returning the SAME `WebgridFrameEncoder`
    /// compute pass's GPU time in milliseconds (gpuEndTime - gpuStartTime, valid post-completion).
    func encodeAndTimeFrame(t: Double) throws -> Double {
      let (vx, vy) = producer.velocity(at: t)
      let v = CursorVelocity(tsNs: 0, seq: 0, vx: vx, vy: vy)
      let pos = integrator.integrate(latest: v, dt: dt)
      let params = WebgridParams.grid30x30(
        cursorX: pos.x, cursorY: pos.y,
        viewportWidth: UInt32(width), viewportHeight: UInt32(height)
      )

      guard let cb = queue.makeCommandBuffer() else { throw GPUTimeBenchError.noCommandBuffer }
      encoder.encode(into: drawable, commandBuffer: cb, params: params)
      cb.commit()
      cb.waitUntilCompleted() // gpuStartTime/gpuEndTime are valid only after completion (Decision 6).
      // CFTimeInterval seconds → milliseconds. `gpuEndTime - gpuStartTime` is the on-GPU execution
      // window of THIS command buffer (the webgrid compute pass) — the SC#2 ≤0.4ms quantity.
      return (cb.gpuEndTime - cb.gpuStartTime) * 1000.0
    }

    // Warmup: discard K frames (pipeline compile residency + GPU clock ramp — Phase-5 precedent).
    var warmT = 0.0
    for _ in 0 ..< max(0, warmup) {
      _ = try encodeAndTimeFrame(t: warmT)
      warmT += dt
    }

    // Measure loop: preallocated sample buffer, no per-frame allocation beyond the command buffer,
    // no per-frame print (allocation-light hot loop).
    var samples = [Double](repeating: 0, count: frames)
    var t = warmT
    for i in 0 ..< frames {
      samples[i] = try encodeAndTimeFrame(t: t)
      t += dt
    }

    let stats = percentiles(of: samples)
    return GPUTimeRun(deviceName: device.name, width: width, height: height, stats: stats)
  }

  /// Reduce the per-frame millisecond samples to p50/p95/p99 + min/max/mean. Sorts a copy and
  /// indexes by the nearest-rank percentile (`ceil(p·n)-1`, clamped) — the standard discrete
  /// percentile used in the Phase-5 latency histogram.
  static func percentiles(of samples: [Double]) -> GPUTimeStats {
    precondition(!samples.isEmpty, "percentiles requires ≥1 sample")
    let sorted = samples.sorted()
    let n = sorted.count

    func pct(_ p: Double) -> Double {
      // Nearest-rank: rank = ceil(p · n); index = rank-1, clamped into [0, n-1].
      let rank = Int((p * Double(n)).rounded(.up))
      let idx = min(max(rank - 1, 0), n - 1)
      return sorted[idx]
    }

    let sum = sorted.reduce(0, +)
    return GPUTimeStats(
      count: n,
      p50Ms: pct(0.50),
      p95Ms: pct(0.95),
      p99Ms: pct(0.99),
      minMs: sorted.first ?? 0,
      maxMs: sorted.last ?? 0,
      meanMs: sum / Double(n)
    )
  }

  /// Write `gpu_time_hist.json` (raw percentiles + n + device + texture extent) into `dir`. JSON is
  /// the load-bearing artifact; a histogram PNG is an optional nice-to-have (noted in the evidence
  /// doc) — the percentiles fully characterise the distribution against the ≤0.4ms bound.
  /// Takes the whole ``GPUTimeRun`` rather than its four members spread as arguments: the caller
  /// already holds one, this mirrors `FrameSoak.writeJSON(to:result:iso8601Date:)` in the sibling
  /// file, and it brings the signature from 6 parameters to 3. The emitted JSON is unchanged.
  static func writeJSON(to dir: URL, run: GPUTimeRun, iso8601Date: String) throws {
    let deviceName = run.deviceName
    let width = run.width
    let height = run.height
    let stats = run.stats
    // Hand-built JSON (key order stable, no Foundation date encoding surprise) — small, auditable.
    let json = """
    {
      "artifact": "gpu_time_hist",
      "requirement": "RENDER-05",
      "success_criterion": "SC#2",
      "bound_ms": 0.4,
      "device": "\(deviceName)",
      "device_tier": "M5 Pro ProMotion — corroborating-canonical (D-11)",
      "canonical_device_deferred": "iPad Pro M4 — 06-HUMAN-UAT.md (D-12, optional/future)",
      "measurement": "commandBuffer.gpuEndTime - gpuStartTime (CFTimeInterval, post-completion)",
      "kernel": "webgrid (real 30x30 / 900-cell compute pass via WebgridFrameEncoder)",
      "drive": "deterministic LissajousProducer (D-05) — reproducible",
      "texture_extent": { "width": \(width), "height": \(height), "pixelFormat": "bgra8Unorm" },
      "samples": \(stats.count),
      "gpu_time_ms": {
        "p50": \(fmt(stats.p50Ms)),
        "p95": \(fmt(stats.p95Ms)),
        "p99": \(fmt(stats.p99Ms)),
        "min": \(fmt(stats.minMs)),
        "max": \(fmt(stats.maxMs)),
        "mean": \(fmt(stats.meanMs))
      },
      "date": "\(iso8601Date)"
    }
    """
    let url = dir.appendingPathComponent("gpu_time_hist.json")
    try json.write(to: url, atomically: true, encoding: .utf8)
  }

  /// Fixed 4-decimal formatting for the JSON numerics (microsecond-grained, locale-independent).
  static func fmt(_ v: Double) -> String {
    String(format: "%.4f", v)
  }
}
