// FrameSoak — the SC#4 "60s sustained-120Hz, no dropped frames" soak (RENDER-02 corroborating).
//
// Two modes, per 06-RESEARCH Decision 6:
//   (a) OFFSCREEN-THROUGHPUT soak (this file, CI-friendly subset): run the real
//       encode+commit+waitUntilCompleted loop for N wall-clock seconds, driven by the deterministic
//       `LissajousProducer` (D-05). Record EVERY per-frame interval, count frames, and flag+count any
//       interval > 8.33ms (the 120Hz frame budget). Report achieved frames vs the 120·N target and
//       the over-budget interval count. This PROVES the GPU workload sustains the per-frame budget
//       with enormous headroom — it does NOT prove on-display refresh (no window, no display link).
//   (b) ON-PANEL soak (the canonical SC#4 surface — documented, run live): the TRUE 120Hz-no-drop
//       proof runs the CortexMac app (Plan 03) on the M5 Pro ProMotion panel with the
//       MacDisplayLinkAdapter, counting `CADisplayLink` callbacks over 60s and logging any interval
//       > 8.33ms. That is the on-panel run captured in 06-render-evidence.md (and the iPad-M4
//       canonical capture is the deferred 06-HUMAN-UAT step, D-12). See `onPanelRunSteps` below for
//       the exact engineer steps.
//
// ## What mode (a) measures vs what it does NOT
// Mode (a) is the GPU-throughput floor: "can the M5 Pro encode+execute the real 900-cell webgrid
// compute pass faster than the 8.33ms budget, sustained, for 60s, with zero over-budget frames?"
// A PASS here means the renderer's compute work has the headroom SC#4 requires. The display-refresh
// guarantee (frames actually presented at 120Hz on the panel) is mode (b) — the on-panel run. The
// honest framing is preserved in the evidence doc: throughput-sustained (measured headless) +
// on-panel 120Hz (run live on the ProMotion panel) together corroborate SC#4; the iPad-M4 canonical
// capture is the deferred optional/future datapoint (D-11/D-12).
//
// ## Determinism (D-05 / threat T-06-05-03)
// The per-frame workload is driven ONLY by `LissajousProducer.velocity(at: t)` — closed-form, no
// RNG, no clock-derived workload. The ONLY time-based input is the 60s wall-clock duration bound
// (so the loop knows when to stop) and the recorded intervals (the thing being measured). The
// histogram of work per frame is therefore reproducible run-to-run.

import CortexRender
import Foundation
import Metal
import QuartzCore

/// The result of an offscreen-throughput soak (mode a).
struct FrameSoakResult {
  let mode: String
  let deviceName: String
  let durationSec: Double
  let frames: Int
  let achievedHz: Double
  let overBudgetCount: Int
  let maxIntervalMs: Double
  let meanIntervalMs: Double
  /// The 120Hz frame budget in milliseconds (8.33ms) — the over-budget threshold.
  let budgetMs: Double
  let width: Int
  let height: Int
}

/// The 30×30 webgrid offscreen-throughput soak. Reuses the SAME `WebgridFrameEncoder` + offscreen
/// drawable path as `GPUTimeHistogram`, but loops for a wall-clock DURATION instead of a fixed frame
/// count, recording every per-frame interval and flagging any > 8.33ms.
enum FrameSoak {
  /// The 120Hz frame budget: 1000 / 120 ≈ 8.333…ms. An interval longer than this is a "dropped
  /// frame" at 120Hz (SC#4). Literal `8.33` appears here and in the over-budget comparison.
  static let budgetMs = 1000.0 / 120.0 // ≈ 8.33ms — the 120Hz per-frame budget (SC#4)

  /// Run the offscreen-throughput soak for `seconds` wall-clock seconds.
  ///
  /// - Parameters:
  ///   - seconds: soak duration (SC#4 canonical = 60s; a smaller value is a CI-friendly smoke run).
  ///   - width/height: the offscreen drawable extent (same representative extent as the histogram).
  /// - Returns: the device-annotated soak result (frames, achieved Hz, over-budget interval count).
  ///
  /// `@MainActor`: drives the MainActor-isolated `WebgridFrameEncoder` (same reason as
  /// `GPUTimeHistogram.run`); single-threaded on the main thread, so the isolation is free.
  @MainActor
  // A headless bench driver: acquire device, build the encoder and offscreen target, run the timed
  // loop, reduce. The steps are sequential and each one's failure mode is local, so extracting them
  // would hand a reader four helpers to reassemble instead of one readable sequence.
  // swiftlint:disable:next function_body_length
  static func run(seconds: Double, width: Int, height: Int) throws -> FrameSoakResult {
    guard let device = MTLCreateSystemDefaultDevice() else { throw GPUTimeBenchError.noDevice }
    guard let queue = device.makeCommandQueue() else { throw GPUTimeBenchError.noCommandQueue }
    let encoder = try WebgridFrameEncoder(device: device)

    // Offscreen target identical to the histogram's (bgra8Unorm + shaderWrite — the live drawable's
    // write scope under framebufferOnly=false).
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
    )
    desc.usage = [.shaderWrite, .shaderRead]
    desc.storageMode = .private
    guard let texture = device.makeTexture(descriptor: desc) else {
      throw GPUTimeBenchError.noTexture
    }
    let drawable = OffscreenDrawable(texture: texture)

    let producer = LissajousProducer()
    let integrator = CursorIntegrator()
    let dt = 1.0 / 120.0

    // Pre-size the interval buffer to the expected frame count (≈ achievable Hz · seconds) so the
    // hot loop does not reallocate. We do not know the achievable rate a priori, so reserve generously
    // (assume up to ~5000 fps headless — far above 120) and append; `reserveCapacity` avoids growth.
    var intervalsMs = [Double]()
    intervalsMs.reserveCapacity(Int(seconds * 5000) + 1024)

    var frames = 0
    var overBudget = 0
    var maxIntervalMs = 0.0
    var sumIntervalMs = 0.0

    // Wall-clock bounds. `Time.machAbsoluteNanoseconds()` is the project monotonic clock (CortexCore);
    // here we only need a stop bound + per-frame deltas, so a single monotonic source is sufficient.
    let startNs = nowNs()
    let durationNs = UInt64(seconds * 1_000_000_000.0)
    var prevNs = startNs
    var simT = 0.0

    while nowNs() - startNs < durationNs {
      // Real webgrid compute pass for this frame (deterministic drive, D-05).
      let (vx, vy) = producer.velocity(at: simT)
      let v = CursorVelocity(tsNs: 0, seq: 0, vx: vx, vy: vy)
      let pos = integrator.integrate(latest: v, dt: dt)
      let params = WebgridParams.grid30x30(
        cursorX: pos.x, cursorY: pos.y,
        viewportWidth: UInt32(width), viewportHeight: UInt32(height)
      )

      guard let cb = queue.makeCommandBuffer() else { throw GPUTimeBenchError.noCommandBuffer }
      encoder.encode(into: drawable, commandBuffer: cb, params: params)
      cb.commit()
      cb.waitUntilCompleted()

      // Per-frame interval = wall-clock time between consecutive completed frames. An interval
      // > 8.33ms is an over-budget frame at 120Hz (SC#4).
      let tNs = nowNs()
      let intervalMs = Double(tNs - prevNs) / 1_000_000.0
      prevNs = tNs

      intervalsMs.append(intervalMs)
      if intervalMs > budgetMs { overBudget += 1 } // > 8.33ms → over the 120Hz budget
      if intervalMs > maxIntervalMs { maxIntervalMs = intervalMs }
      sumIntervalMs += intervalMs
      frames += 1
      simT += dt
    }

    let elapsedSec = Double(nowNs() - startNs) / 1_000_000_000.0
    let achievedHz = elapsedSec > 0 ? Double(frames) / elapsedSec : 0
    let meanIntervalMs = frames > 0 ? sumIntervalMs / Double(frames) : 0

    return FrameSoakResult(
      mode: "offscreen-throughput (CI-friendly subset; on-panel 120Hz is mode b — see evidence doc)",
      deviceName: device.name,
      durationSec: elapsedSec,
      frames: frames,
      achievedHz: achievedHz,
      overBudgetCount: overBudget,
      maxIntervalMs: maxIntervalMs,
      meanIntervalMs: meanIntervalMs,
      budgetMs: budgetMs,
      width: width,
      height: height
    )
  }

  /// Monotonic nanosecond clock (mirrors `CortexCore.Time.machAbsoluteNanoseconds`; inlined here to
  /// keep the soak loop free of a cross-module call, though either is allocation-free).
  private static func nowNs() -> UInt64 {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return mach_absolute_time() &* UInt64(info.numer) / UInt64(info.denom)
  }

  /// The exact engineer steps for the canonical on-panel SC#4 soak (mode b) — documented here and in
  /// 06-render-evidence.md so the live ProMotion run is reproducible (D-11 corroborating-canonical).
  static let onPanelRunSteps = """
  On-panel 120Hz soak (mode b — the canonical SC#4 surface, M5 Pro ProMotion, D-11):
    1. Build & run the CortexMac scheme on the M5 Pro MacBook Pro built-in ProMotion panel.
    2. The MacDisplayLinkAdapter (Plan 03) drives the webgrid at preferredFrameRateRange 120/120/120.
    3. MTL_HUD_ENABLED=1 (set in the CortexMac scheme, RENDER-09) shows live P95 frame time,
       drawable-wait, encoder-time — confirm P95 frame time ≈ 8.33ms and zero long frames for 60s.
    4. (optional) enable a callback counter in the adapter to count display-link ticks over 60s and
       log any interval > 8.33ms; screenshot the HUD as the artifact (lives beside this doc / Plan 06).
  The iPad-Pro-M4 canonical capture is the deferred optional/future datapoint (06-HUMAN-UAT.md, D-12).
  """

  /// Write `soak_log.json` (mode, duration, frames, achieved Hz, over-budget count, device) into `dir`.
  static func writeJSON(to dir: URL, result r: FrameSoakResult, iso8601Date: String) throws {
    let json = """
    {
      "artifact": "soak_log",
      "success_criterion": "SC#4",
      "requirement": "RENDER-02 (corroborating)",
      "mode": "\(r.mode)",
      "device": "\(r.deviceName)",
      "device_tier": "M5 Pro ProMotion — corroborating-canonical (D-11)",
      "canonical_device_deferred": "iPad Pro M4 — 06-HUMAN-UAT.md (D-12, optional/future)",
      "drive": "deterministic LissajousProducer (D-05) — reproducible",
      "budget_ms": \(String(format: "%.4f", r.budgetMs)),
      "duration_sec": \(String(format: "%.3f", r.durationSec)),
      "frames": \(r.frames),
      "achieved_hz": \(String(format: "%.2f", r.achievedHz)),
      "over_budget_intervals": \(r.overBudgetCount),
      "max_interval_ms": \(String(format: "%.4f", r.maxIntervalMs)),
      "mean_interval_ms": \(String(format: "%.4f", r.meanIntervalMs)),
      "texture_extent": { "width": \(r.width), "height": \(r.height) },
      "verdict": "\(r.overBudgetCount == 0 ? "PASS (zero over-budget intervals)" : "DROPS DETECTED")",
      "on_panel_canonical": "mode b — run the CortexMac scheme live on the M5 Pro ProMotion panel (see 06-render-evidence.md)",
      "date": "\(iso8601Date)"
    }
    """
    let url = dir.appendingPathComponent("soak_log.json")
    try json.write(to: url, atomically: true, encoding: .utf8)
  }
}

/// Bridges `main`'s `--soak` flag to the `FrameSoak` measurement + JSON write + console summary.
/// (A free function so `main.swift` stays a thin CLI; the measurement logic lives in `FrameSoak`.)
/// `@MainActor` because it calls the MainActor-isolated `FrameSoak.run`.
@MainActor
func runFrameSoak(args: BenchArgs, date: String) throws {
  print("")
  print(
    String(
      format:
      "CortexRenderBench — frame soak: %.0fs @ %dx%d offscreen (deterministic Lissajous, D-05)",
      args.soakSeconds, args.width, args.height
    )
  )
  let soak = try FrameSoak.run(seconds: args.soakSeconds, width: args.width, height: args.height)
  print("  device         : \(soak.deviceName)")
  print(
    String(
      format: "  duration       : %.3fs   frames=%d   achieved=%.1fHz   target=120Hz",
      soak.durationSec, soak.frames, soak.achievedHz
    )
  )
  print(
    String(
      format: "  over-budget    : %d intervals > 8.33ms   (max interval=%.3fms, mean=%.3fms)",
      soak.overBudgetCount, soak.maxIntervalMs, soak.meanIntervalMs
    )
  )
  let soakVerdict = soak.overBudgetCount == 0 ? "PASS (zero over-budget frames)" : "DROPS DETECTED"
  print("  SC#4 throughput: \(soakVerdict)")
  try FrameSoak.writeJSON(to: args.outDir, result: soak, iso8601Date: date)
  print("  wrote          : \(args.outDir.appendingPathComponent("soak_log.json").path)")
}
