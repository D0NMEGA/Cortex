// MacDisplayLinkAdapter — the macOS display-link plumbing (RENDER-08/02/07).
//
// This is the OTHER HALF of the two-adapters-over-one-encoder architecture (RESEARCH TL;DR #1). The
// macOS-native (non-Catalyst) path uses `NSView.displayLink(target:selector:)` (macOS 14+), which
// returns a Core Animation display-link timer synced to the view's screen. Unlike the iOS
// `CAMetalDisplayLink` path there is NO vended drawable — the selector MANUALLY calls
// `metalLayer.nextDrawable()` (which may return nil under contention → skip the frame). Everything
// after drawable acquisition (pop → integrate → encode → present) MIRRORS the iOS adapter and reuses
// the SAME shared `WebgridFrameEncoder` (Plan 01) + the SAME `FrameSynchronizer` value:1 gate.
//
// ## Why this uses the per-screen display-link timer BY DESIGN (RENDER-08, not a regression)
// `NSView.displayLink(target:selector:)` is the SANCTIONED macOS Metal path per RENDER-08 and the
// cortex-spec: on native AppKit it is preferred over `CAMetalDisplayLink` (which wants an
// AppKit-thread tick) and over the legacy `CVDisplayLink` (rejected as legacy). `NSView.displayLink`
// also tracks screen moves automatically (AppKit docs), so it is robust to window-screen changes at
// zero extra cost. This is DISTINCT from the iOS Metal path's prohibition: the Plan-04 grep-gate
// scopes the "no legacy display-link for Metal" rule to the iOS adapter only; the macOS adapter's
// use of `NSView.displayLink` is the explicitly-sanctioned RENDER-08 mechanism.
//
// ## Wait/signal balance — deadlock-safety (threat T-06-03-01)
// With `value: 1` an unbalanced wait deadlocks the render loop forever. The invariant is "every
// `waitForNextFrame()` is balanced by exactly one signal." This adapter `wait`s at the top of the
// tick; on the `nextDrawable() == nil` SKIP path it calls `synchronizer.signal()` directly to
// balance (no command buffer is encoded that frame); on the normal path
// `synchronizer.signalOnComplete(cb)` balances it on GPU completion. With ≤0.4ms GPU there is
// enormous headroom under the 8.33ms 120Hz interval, so nil is rare — but the balance is structural,
// not luck.
//
// ## Drawable-retention stutter (threat T-06-03-02)
// The ENTIRE tick body is wrapped in an explicit `autoreleasepool` so each frame's
// `nextDrawable()`-vended drawable is released promptly rather than retained across frames — the
// classic CAMetalLayer/nextDrawable fullscreen stutter cause (RESEARCH Risk #6). Grep-asserted.
//
// No stdout console call on the render path — os.Logger only.

#if os(macOS)

  import AppKit
  import Metal
  import os
  import QuartzCore

  /// Drives the shared `WebgridFrameEncoder` from an `NSView.displayLink` Core Animation timer at a
  /// locked 120Hz with one frame in flight (RENDER-08/02/07).
  @MainActor
  public final class MacDisplayLinkAdapter: NSObject {
    private let layer: CAMetalLayer
    private let encoder: WebgridFrameEncoder
    private let queue: MTLCommandQueue
    private let synchronizer: FrameSynchronizer
    private let integrator: CursorIntegrator
    private let ring: VelocityRing
    /// The active task target, latest-value (see `TargetChannel`). `nil` when the host sets none.
    private let targets: TargetChannel?
    /// The dwell-to-select progress channel, read once per frame alongside the target.
    private let dwell: DwellChannel?
    /// Re-anchor events for the renderer's own integrator (see `AnchorChannel`).
    private let anchors: AnchorChannel?
    /// The last anchor generation applied, so each one moves the cursor exactly once.
    private var lastAnchor: UInt32 = 0
    private let log = Logger(subsystem: "app.cortex.render", category: "MacDisplayLinkAdapter")

    /// The display link returned by `NSView.displayLink`. `CADisplayLink` is the macOS 14+ AppKit
    /// timer type here — the RENDER-08-sanctioned macOS Metal path (NOT the rejected iOS-Metal usage).
    private var link: CADisplayLink?

    /// Previous tick's timestamp, for the integrator dt. `nil` until the first tick.
    private var lastTimestamp: CFTimeInterval?

    /// - Parameters:
    ///   - layer: the `MetalLayerConfig.configure`-d `CAMetalLayer` backing the render surface.
    ///   - device: the Metal device (also owns the command queue).
    ///   - ring: the SPSC velocity ring this adapter pops on the tick thread (consumer end).
    ///   - start: the integrator's initial cursor position (defaults to grid centre).
    ///   - targets: the active-target channel the renderer reads once per frame; `nil` draws no target.
    ///   - dwell: the dwell-to-select progress channel; `nil` draws the cursor at its resting size.
    ///   - anchors: cursor re-anchor events; `nil` leaves the cursor free-running.
    /// - Throws: `WebgridFrameEncoderError` if the `webgrid` pipeline / command queue cannot be built.
    public init(
      layer: CAMetalLayer,
      device: MTLDevice,
      ring: VelocityRing,
      start: CursorPosition = .init(x: 0.5, y: 0.5),
      targets: TargetChannel? = nil,
      dwell: DwellChannel? = nil,
      anchors: AnchorChannel? = nil
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
      self.dwell = dwell
      self.anchors = anchors
      super.init()
    }

    /// Create and start the display link off `view` at a locked 120Hz, one frame in flight.
    ///
    /// - Parameter view: the `NSView` hosting the `CAMetalLayer`. `NSView.displayLink` ties the timer
    ///   to the view's screen and tracks screen moves automatically (RESEARCH Decision 2).
    public func start(in view: NSView) {
      let link = view.displayLink(target: self, selector: #selector(tick(_:)))
      // RENDER-02: locked 120Hz. The M5 Pro MacBook Pro built-in panel is ProMotion 120Hz — the
      // CONTEXT D-11 corroborating-canonical surface for SC#2/SC#4.
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
      link.add(to: .main, forMode: .common)
      self.link = link
    }

    /// Stop and tear down the display link (e.g. on view teardown).
    public func stop() {
      link?.invalidate()
      link = nil
    }

    /// The per-tick render selector. Fires on the main run-loop thread. The whole body is wrapped in
    /// an `autoreleasepool` (drawable-retention stutter mitigation, T-06-03-02). No await, no
    /// allocation beyond the command buffer, no lock except the lock-free ring pop + the value:1 gate.
    @objc private func tick(_ link: CADisplayLink) {
      autoreleasepool {
        // 1. value:1 wait at the top — block until the previous frame's GPU work completed (RENDER-07).
        synchronizer.waitForNextFrame()

        // 2. Integrator dt from the tick timestamp delta. The link exposes the current `timestamp` and
        //    the predicted `targetTimestamp`; use the delta vs the previous tick (zero-order hold
        //    decouples the 120Hz render from the ~50Hz velocity cadence). First tick: dt = 0 (hold).
        let now = link.timestamp
        let dt: Double = if let last = lastTimestamp {
          now - last
        } else {
          0
        }
        lastTimestamp = now

        // 3. MANUAL drawable acquisition (RESEARCH #1) — may be nil under contention. On the SKIP path
        //    we MUST balance the value:1 wait we just took, or the semaphore deadlocks (T-06-03-01).
        guard let drawable = layer.nextDrawable() else {
          synchronizer.signal() // balance the wait — every wait gets exactly one signal
          return
        }

        // 4. Pop the latest velocity (nil → integrator holds, D-04); drain to the most recent frame.
        var latest = ring.pop()
        while let next = ring.pop() {
          latest = next
        }

        // 5. Integrate under a zero-order hold on velocity → clamped, finite position.
        //    The hold is what makes the 120Hz render faithful to the ~50Hz producer: treating an
        //    empty ring as zero velocity integrates motion on only 50 of every 120 frames and
        //    shrinks every trajectory to ~42% of its length.
        // A pending re-anchor moves the cursor before this frame integrates, so the
        // frame renders from the anchor rather than one tick past it.
        if let anchor = anchors?.take(after: lastAnchor) {
          integrator.reset(to: CursorPosition(x: anchor.x, y: anchor.y))
          lastAnchor = anchor.generation
        }
        let pos = integrator.integrateHoldingVelocity(latest: latest, dt: dt)

        // 6. Build the 30×30 uniforms with the integrated cursor + the drawable extent (D-01).
        // The target is a LATEST-VALUE read, one atomic load per frame - never a queue drain.
        let target = targets?.load()
        let params = WebgridParams.grid30x30(
          cursorX: pos.x,
          cursorY: pos.y,
          viewportWidth: UInt32(drawable.texture.width),
          viewportHeight: UInt32(drawable.texture.height),
          targetColumn: target?.column ?? WebgridParams.noTarget,
          targetRow: target?.row ?? WebgridParams.noTarget,
          dwellProgress: dwell?.load() ?? 0
        )

        // 7. Encode one compute pass into the manually-acquired drawable.
        guard let cb = queue.makeCommandBuffer() else {
          log.error("makeCommandBuffer returned nil; skipping frame")
          synchronizer.signal() // balance the wait on this skip path too (T-06-03-01)
          return
        }
        encoder.encode(into: drawable, commandBuffer: cb, params: params)

        // 8. Signal the gate on GPU completion, then PLAIN present (timed present variants assert under
        //    a Metal display link — RESEARCH #5) and commit.
        synchronizer.signalOnComplete(cb)
        cb.present(drawable)
        cb.commit()
      }
    }
  }

#endif
