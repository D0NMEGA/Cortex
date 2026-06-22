import Metal
import QuartzCore

// MetalLayerConfig — the low-latency compute-to-drawable CAMetalLayer configuration shared by both
// display-link adapters (Plan 03: the iOS CAMetalDisplayLink path and the macOS CADisplayLink path).
//
// This is the GPU-pipeline configuration the entire phase depends on. The values are load-bearing
// for the sub-25ms glass-to-glass budget (PERF-04) — see the heavy annotation on
// maximumDrawableCount below.

/// Applies the low-latency, compute-writable `CAMetalLayer` configuration both adapters reuse.
public enum MetalLayerConfig {
  /// Configures `layer` for the lowest-latency compute-kernel-to-drawable path (RENDER-04/06/07).
  ///
  /// - Parameters:
  ///   - layer: the `CAMetalLayer` backing the render surface.
  ///   - device: the Metal device that owns the drawable pool.
  public static func configure(_ layer: CAMetalLayer, device: MTLDevice) {
    layer.device = device
    layer.pixelFormat = .bgra8Unorm

    // REQUIRED so the `webgrid` compute kernel can WRITE the drawable texture (RENDER-04). With the
    // default `framebufferOnly = true`, the drawable texture is `.renderTarget`-only and a compute
    // `access::write` to it is illegal. The kernel is the SOLE writer and is extent-bounded by its
    // pixel-bounds guard (threat T-06-01-02), so disabling this CoreAnimation optimization is safe.
    layer.framebufferOnly = false

    // ─────────────────────────────────────────────────────────────────────────────────────────
    // INTENTIONAL low-latency config. `maximumDrawableCount = 2` (not 3) pairs with
    // `dispatch_semaphore(value: 1)` in Plan 03 for exactly ONE in-flight frame. Apple's
    // "Synchronizing CPU and GPU Work" sample uses 3 for THROUGHPUT (maximizes CPU(n+1)/GPU(n)
    // overlap); Cortex deliberately trades throughput for the LOWEST glass-to-glass latency
    // (PERF-04). Do NOT raise this to 3 — a third in-flight frame adds ~8.3ms (one 120Hz frame
    // interval) of latency to the budget. Valid values are only 2 or 3; 2 is the low-latency choice
    // and aligns with `CAMetalDisplayLink.preferredFrameLatency = 1.0` (Plan 03).
    // ─────────────────────────────────────────────────────────────────────────────────────────
    layer.maximumDrawableCount = 2

    // Async, lowest-latency present. `presentsWithTransaction = true` forces the timed/synchronized
    // present form (waitUntilScheduled + drawable.present()), which ASSERTS under CAMetalDisplayLink
    // and adds a CPU stall — keep it false for the beam-raced async present (RESEARCH Decision 4).
    layer.presentsWithTransaction = false
  }
}
