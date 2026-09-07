// iOSDisplayLinkAdapter — the iOS/iPadOS display-link plumbing (RENDER-01/02/07).
//
// This is HALF of the single biggest architectural fact of Phase 6 (RESEARCH TL;DR #1): iOS and
// macOS drive the SAME shared `WebgridFrameEncoder` (Plan 01) over `CursorIntegrator` + `VelocityRing`
// (Plan 02) through TWO different display-link mechanisms. iOS uses `CAMetalDisplayLink` (iOS 17+),
// whose delegate is HANDED a ready drawable via `update.drawable` — there is NO `nextDrawable()` on
// this path. macOS (the peer adapter) uses the AppKit `NSView.displayLink` timer with a manual
// `nextDrawable()`. Only drawable-acquisition + pacing differ; the encode core is shared.
//
// ## CRITICAL: the iOS Metal path stays on CAMetalDisplayLink ONLY (RENDER-01)
// This file MUST NOT reference the legacy per-screen display-link timer class on the iOS Metal path.
// `CAMetalDisplayLink` is the sanctioned iOS Metal path (it bundles drawable acquisition + encode
// deadline + on-glass timestamp into one callback for beam-raced 120Hz); regressing to the legacy
// timer here is exactly the REQUIREMENTS Out-of-Scope "legacy display-link for Metal" rejection. The
// Plan-04 grep-gate asserts the legacy class name never appears on this path.
//
// ## Threading (Swift 6.2 `.defaultIsolation(MainActor.self)`)
// The adapter is `@MainActor`: it is created + `start()`ed from the SwiftUI `UIViewRepresentable` on
// the main actor, and the link is added to the main run loop, so the delegate callback fires on the
// main thread. The callback path itself touches only `Sendable` collaborators (the encoder,
// synchronizer, integrator, ring) — no actor hop inside the callback (an await there would add
// latency). This is a DISPLAY regime (Metal encode is allowed), distinct from the Phase-3
// acquisition hot path; the only callback-thread work that must stay lock-free is `ring.pop()`,
// which is (Plan 02 SPSC). The render path logs via os.Logger only — never the stdout console call.

#if os(iOS)

  import Metal
  import os
  import QuartzCore

  /// Drives the shared `WebgridFrameEncoder` from a `CAMetalDisplayLink` at a locked 120Hz with one
  /// frame in flight (RENDER-01/02/07).
  @MainActor
  public final class iOSDisplayLinkAdapter: NSObject, @preconcurrency CAMetalDisplayLinkDelegate {
    private let layer: CAMetalLayer
    private let encoder: WebgridFrameEncoder
    private let queue: MTLCommandQueue
    private let synchronizer: FrameSynchronizer
    private let integrator: CursorIntegrator
    private let ring: VelocityRing
    /// The active task target, latest-value (see `TargetChannel`). `nil` when the host sets none.
    private let targets: TargetChannel?
    /// Dwell progress and selection flash, read once per frame alongside the target.
    private let selection: SelectionChannel?
    /// Re-anchor events for the renderer's own integrator (see `CursorPositionChannel`).
    private let cursorPositions: CursorPositionChannel?
    /// The last anchor generation applied, so each one moves the cursor exactly once.
    private var lastCursorGeneration: UInt32 = 0
    private let log = Logger(subsystem: "app.cortex.render", category: "iOSDisplayLinkAdapter")

    /// The display link. `CAMetalDisplayLink` is iOS 17+; the package targets iOS 26, so it is always
    /// available. Retained for the adapter's lifetime; invalidated in `stop()`.
    private var link: CAMetalDisplayLink?

    /// Previous frame's estimated on-glass time, for the integrator dt. `nil` until the first frame
    /// (the first dt is skipped — there is no prior timestamp to delta against).
    private var lastPresentationTimestamp: CFTimeInterval?

    /// - Parameters:
    ///   - layer: the `MetalLayerConfig.configure`-d `CAMetalLayer` backing the render surface.
    ///   - device: the Metal device (also owns the command queue).
    ///   - ring: the SPSC velocity ring this adapter pops on the callback thread (consumer end).
    ///   - start: the integrator's initial cursor position (defaults to grid centre).
    ///   - targets: the active-target channel the renderer reads once per frame; `nil` draws no target.
    ///   - selection: dwell + flash state; `nil` draws a resting cursor and an unflashed target.
    ///   - cursorPositions: the producer's authoritative position; `nil` free-runs the render integrator.
    /// - Throws: `WebgridFrameEncoderError` if the `webgrid` pipeline cannot be built, or an error if
    ///   the command queue cannot be created.
    public init(
      layer: CAMetalLayer,
      device: MTLDevice,
      ring: VelocityRing,
      start: CursorPosition = .init(x: 0.5, y: 0.5),
      targets: TargetChannel? = nil,
      selection: SelectionChannel? = nil,
      cursorPositions: CursorPositionChannel? = nil
    ) throws {
      self.layer = layer
      encoder = try WebgridFrameEncoder(device: device)
      guard let q = device.makeCommandQueue() else {
        throw WebgridFrameEncoderError.functionMissing("MTLCommandQueue")
      }
      queue = q
      synchronizer = FrameSynchronizer()
      integrator = CursorIntegrator(start: start)
      self.ring = ring
      self.targets = targets
      self.selection = selection
      self.cursorPositions = cursorPositions
      super.init()
    }

    /// Create and start the `CAMetalDisplayLink` at a locked 120Hz, one frame in flight.
    public func start() {
      let link = CAMetalDisplayLink(metalLayer: layer)
      // RENDER-02: locked 120Hz on ProMotion (system may still drop under thermal/Low-Power — handled
      // gracefully by the dt-driven integrator). Pairs with Info.plist
      // CADisableMinimumFrameDurationOnPhone=YES, which unlocks above-default rates on the panel.
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
      // Only 1.0 or 2.0 are accepted (RESEARCH #2). 1.0 = lowest latency (~single frame in flight),
      // consistent with the value:1 synchronizer + maximumDrawableCount=2.
      link.preferredFrameLatency = 1.0
      link.delegate = self
      // Fire on the main run loop in .common mode (sample convention) so the callback is not stalled
      // by UI tracking run-loop modes.
      link.add(to: .main, forMode: .common)
      self.link = link
    }

    /// Stop and tear down the display link (e.g. on view teardown).
    public func stop() {
      link?.invalidate()
      link = nil
    }

    // MARK: CAMetalDisplayLinkDelegate

    /// Called by the link once per refresh with a READY drawable (`update.drawable`) — no
    /// `nextDrawable()` on iOS (RESEARCH #1). Runs on the main run-loop thread.
    ///
    /// The conformance is `@preconcurrency` and this method inherits the class's `@MainActor`
    /// isolation, which is what the link actually delivers: it was added to the `.main` run loop in
    /// `start()`, so every callback arrives on the main thread. `@preconcurrency` inserts the runtime
    /// check that asserts it rather than trusting a comment.
    ///
    /// The earlier shape -- `nonisolated` plus `MainActor.assumeIsolated { self.render(update:) }` --
    /// does not compile under Swift 6 in this module. `CortexRender` sets
    /// `.defaultIsolation(MainActor.self)`, so `render` is main-actor isolated, and
    /// `CAMetalDisplayLink.Update` is not `Sendable`; passing it into the closure is a
    /// "sending 'update' risks causing data races" error. It went unnoticed until 2026-09-07 because
    /// the iOS target had never been compiled anywhere: `swift build` only builds the macOS slice,
    /// where this file is `#if os(iOS)`-excluded, and CI had never reached the CortexiOS step.
    public func metalDisplayLink(
      _: CAMetalDisplayLink,
      needsUpdate update: CAMetalDisplayLink.Update
    ) {
      render(update: update)
    }

    /// The per-frame encode body. Main-actor isolated (assumed from the run-loop thread). No await, no
    /// allocation beyond the command buffer, no lock except the lock-free ring pop + the value:1 gate.
    private func render(update: CAMetalDisplayLink.Update) {
      // 1. value:1 wait at the top — block until the previous frame's GPU work completed (RENDER-07).
      synchronizer.waitForNextFrame()

      // 2. Integrator dt from the estimated on-glass time delta (zero-order hold decouples the 120Hz
      //    render from the ~50Hz velocity cadence — RESEARCH Decision 5). First frame: no prior
      //    timestamp, so dt = 0 (cursor holds for one frame).
      let now = update.targetPresentationTimestamp
      let dt: Double = if let last = lastPresentationTimestamp {
        now - last
      } else {
        0
      }
      lastPresentationTimestamp = now

      // 3. Pop the latest velocity (nil → integrator holds, D-04). Drain to the most recent frame so a
      //    120Hz consumer never lags a slower producer.
      var latest = ring.pop()
      while let next = ring.pop() {
        latest = next
      }

      // 4. Integrate under a zero-order hold on velocity → clamped, finite position.
      //    Re-seat on the producer's authoritative position first. The producer advances a fixed
      //    20 ms per tick while this loop advances real frame time, so without this the drawn
      //    cursor and the cursor the dwell criterion scores drift apart, and a viewer sees a
      //    closed ring over a target that never registers.
      if let authoritative = cursorPositions?.take(after: lastCursorGeneration) {
        integrator.resync(to: CursorPosition(x: authoritative.x, y: authoritative.y))
        lastCursorGeneration = authoritative.generation
      }
      let pos = integrator.integrateHoldingVelocity(latest: latest, dt: dt)

      // 5. Build the 30×30 uniforms with the integrated cursor + the drawable extent (D-01).
      let drawable = update.drawable
      // The target is a LATEST-VALUE read, one atomic load per frame - never a queue drain.
      let target = targets?.load()
      let sel = selection?.load() ?? .idle
      let params = WebgridParams.grid30x30(
        cursorX: pos.x,
        cursorY: pos.y,
        viewportWidth: UInt32(drawable.texture.width),
        viewportHeight: UInt32(drawable.texture.height),
        target: target,
        dwellProgress: sel.dwell,
        targetFlash: sel.flash
      )

      // 6. Encode one compute pass into the vended drawable.
      guard let cb = queue.makeCommandBuffer() else {
        // Could not make a command buffer this frame — balance the value:1 wait or deadlock, then skip.
        log.error("makeCommandBuffer returned nil; skipping frame")
        synchronizer.signal()
        return
      }
      encoder.encode(into: drawable, commandBuffer: cb, params: params)

      // 7. Signal the gate on GPU completion (releases the next frame).
      synchronizer.signalOnComplete(cb)

      // 8. PLAIN present — the timed/timestamp-targeting present variants ASSERT under
      //    CAMetalDisplayLink (RESEARCH #5), so use the unparameterized form only. Then commit.
      cb.present(drawable)
      cb.commit()
    }
  }

#endif
