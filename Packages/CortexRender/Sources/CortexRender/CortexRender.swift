// CortexRender — the Phase 6 CAMetalDisplayLink 120Hz beam-raced renderer with the 30x30 webgrid
// compute shader. The real API is `WebgridFrameEncoder` (the shared compute core),
// `MetalLayerConfig` (the low-latency CAMetalLayer config), and `WebgridParams` (the shared
// Swift<->Metal uniforms). See REQUIREMENTS.md RENDER-01 through RENDER-09.

/// Version marker for the CortexRender subsystem.
public enum CortexRender {
  /// The phase that owns this subsystem.
  public static let phase: Int = 6
}
