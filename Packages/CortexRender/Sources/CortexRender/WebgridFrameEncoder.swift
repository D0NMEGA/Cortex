import Metal
import QuartzCore
import os

// WebgridFrameEncoder — the platform-agnostic core that encodes ONE compute pass writing the 30x30
// webgrid + cursor into a supplied CAMetalDrawable (RENDER-04). Both display-link adapters (Plan 03:
// iOS CAMetalDisplayLink + macOS CADisplayLink) call `encode(into:commandBuffer:params:)` over this
// single core — only drawable acquisition and frame pacing differ between them (RESEARCH Decision
// 1/2). This type knows NOTHING about display links, semaphores, or `present` — the caller owns the
// `dispatch_semaphore(value: 1)` wait/signal and the present, so the value:1 pacing lives in one
// place (Plan 03).

/// Errors thrown while building the `webgrid` compute pipeline.
public enum WebgridFrameEncoderError: Error, Sendable {
  /// The module's `default.metallib` (compiled from `Webgrid.metal`) could not be loaded.
  case defaultLibraryMissing
  /// The `webgrid` kernel function was not found in the default library.
  case functionMissing(String)
}

/// Encodes the 30x30 webgrid + bright-disc cursor into a drawable in a single Metal compute pass.
public final class WebgridFrameEncoder {
  /// The compiled compute pipeline over the `webgrid` kernel. `MTLComputePipelineState` is immutable
  /// and `Sendable`; stored once at init, never mutated (no captured mutable state — strict
  /// concurrency clean).
  private let pipelineState: MTLComputePipelineState
  private let log = Logger(subsystem: "app.cortex.render", category: "WebgridFrameEncoder")

  /// Builds the compute pipeline from the `webgrid` kernel in this module's `default.metallib`.
  ///
  /// - Parameter device: the Metal device used to compile the pipeline.
  /// - Throws: `WebgridFrameEncoderError` if the default library or the `webgrid` function is
  ///   missing, or the underlying Metal error if pipeline creation fails.
  public init(device: MTLDevice) throws {
    // `Webgrid.metal` is declared a `.process` resource (Package.swift), so the Apple build system
    // compiles it into this module's resource bundle as `default.metallib`. Load it via `.module`.
    guard let library = try? device.makeDefaultLibrary(bundle: .module) else {
      throw WebgridFrameEncoderError.defaultLibraryMissing
    }
    guard let function = library.makeFunction(name: "webgrid") else {
      throw WebgridFrameEncoderError.functionMissing("webgrid")
    }
    pipelineState = try device.makeComputePipelineState(function: function)
  }

  /// Encodes one compute pass writing the webgrid + cursor into `drawable.texture`.
  ///
  /// The caller owns lifecycle: it MUST wait on its `dispatch_semaphore(value: 1)` before calling
  /// this, and signal it (in `commandBuffer.addCompletedHandler`) + `present`/`commit` the buffer
  /// AFTER (Plan 03). This method only encodes; it does not commit, present, or signal.
  ///
  /// - Parameters:
  ///   - drawable: the `CAMetalDrawable` whose texture receives the frame (its layer must be
  ///     configured via `MetalLayerConfig.configure` so the texture is compute-writable).
  ///   - commandBuffer: the command buffer to encode into (caller commits/presents it).
  ///   - params: the uniforms (grid dims, cell geometry, cursor pos/radius); uploaded zero-copy.
  public func encode(
    into drawable: CAMetalDrawable,
    commandBuffer: MTLCommandBuffer,
    params: WebgridParams
  ) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
      // A nil compute encoder means the command buffer is unusable (e.g. already committed). Skip
      // this frame rather than crash the render loop; the caller still presents the (untouched)
      // drawable. Logged via os.Logger (never print on the encode path).
      log.error("makeComputeCommandEncoder returned nil; skipping frame")
      return
    }
    encoder.setComputePipelineState(pipelineState)
    encoder.setTexture(drawable.texture, index: 0)

    // RENDER-06 zero-copy: setBytes is the small-constant upload path — no MTLBuffer, hence no
    // staging buffer and no CPU-managed storage mode (the unified-memory fast path for a ~40-byte
    // uniforms struct). If an MTLBuffer were ever used here it would have to be
    // options:.storageModeShared. `WebgridParams` is a trivial value type, so its raw `.stride`
    // bytes are exactly what the Metal-side `WebgridParams` expects.
    var uniforms = params
    encoder.setBytes(&uniforms, length: MemoryLayout<WebgridParams>.stride, index: 0)

    // 2D threadgroup sized from the pipeline's execution width: a row of `threadExecutionWidth`
    // (one SIMD-group wide) by as many rows as fit under `maxTotalThreadsPerThreadgroup`. The kernel
    // bounds-checks each thread, so `dispatchThreads` (non-uniform threadgroups) sized to the exact
    // drawable extent is safe and writes every pixel once.
    let width = pipelineState.threadExecutionWidth
    let height = max(1, pipelineState.maxTotalThreadsPerThreadgroup / width)
    let threadsPerThreadgroup = MTLSize(width: width, height: height, depth: 1)
    let threads = MTLSize(
      width: drawable.texture.width, height: drawable.texture.height, depth: 1)
    encoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerThreadgroup)
    encoder.endEncoding()
  }
}
