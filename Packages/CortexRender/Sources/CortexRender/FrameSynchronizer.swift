// FrameSynchronizer — the ONE-frame-in-flight gate shared by BOTH display-link adapters (Plan 03:
// the iOS CAMetalDisplayLink path and the macOS NSView.displayLink/CADisplayLink path).
//
// ─────────────────────────────────────────────────────────────────────────────────────────────
// INTENTIONAL `value: 1` = ONE frame in flight = LOWEST latency (RENDER-07, PERF-04).
//
// Apple's "Synchronizing CPU and GPU Work" sample uses `value: 3` for THROUGHPUT — a triple-buffer
// that maximizes the CPU(n+1)/GPU(n) overlap. Cortex DELIBERATELY trades that overlap away for the
// minimum glass-to-glass latency the spec's sub-25ms claim depends on: with `value: 1` the CPU
// blocks on the previous frame's GPU completion before encoding the next, so there is never more
// than one frame between intent and photons.
//
// This pairs with `MetalLayerConfig.maximumDrawableCount = 2` and the iOS link's
// `preferredFrameLatency = 1.0`. DO NOT raise this to 3 — a third in-flight frame silently adds
// ~8.3ms (one 120Hz frame interval) to the glass-to-glass budget and breaks PERF-04. At the ≤0.4ms
// GPU target there is enormous headroom under the 8.33ms frame interval, so `value: 1` never
// throttles the 120Hz cadence (SC#4 soak validates this).
//
// The structural grep-gate (Plan 04) asserts `value: 1` here and FAILS the build if it changes —
// defense-in-depth: this annotation for the human reader, the gate for the regression.
// ─────────────────────────────────────────────────────────────────────────────────────────────
//
// ## Wait/signal balance (deadlock-safety, threat T-06-03-01)
// The contract is "every `waitForNextFrame()` is balanced by exactly one `signal`." With `value: 1`
// an unbalanced wait DEADLOCKS the render loop permanently (the link can never acquire the
// semaphore again). The iOS adapter always reaches `signalOnComplete` (the vended drawable is never
// nil). The macOS adapter MUST signal on its `nextDrawable() == nil` skip path too — see
// `MacDisplayLinkAdapter` — which is why this type also exposes a direct `signal()` for the
// drawable-acquisition-failed branch.

import Metal
import os

/// A `dispatch_semaphore(value: 1)` wrapper enforcing exactly ONE in-flight frame (RENDER-07).
///
/// `Sendable` (`@unchecked`) because the single instance is shared between the display-link callback
/// thread (which `wait`s) and the Metal completion-handler thread (which `signal`s) — that
/// cross-thread sharing is the entire purpose of the gate. `DispatchSemaphore` is itself a
/// thread-safe primitive, so the conformance is sound; there is no unsynchronized mutable state.
public final class FrameSynchronizer: @unchecked Sendable {
  /// value: 1 — see the file header. ONE frame in flight, lowest latency. Do NOT change to 3.
  private let semaphore = DispatchSemaphore(value: 1)

  public init() {}

  /// Block until the previous frame's GPU work has completed (or immediately, on the first frame).
  /// Call at the TOP of the display-link callback, before acquiring a drawable / encoding.
  public func waitForNextFrame() {
    semaphore.wait()
  }

  /// Signal completion when the command buffer's GPU work finishes — releases the gate for the next
  /// frame. Registers `addCompletedHandler` so the signal fires on GPU completion, NOT at commit
  /// time (which would defeat the one-in-flight guarantee).
  ///
  /// - Parameter cb: the command buffer whose completion releases the semaphore.
  public func signalOnComplete(_ cb: MTLCommandBuffer) {
    cb.addCompletedHandler { [semaphore] _ in
      semaphore.signal()
    }
  }

  /// Release the gate directly, WITHOUT a command buffer. ONLY for the macOS `nextDrawable() == nil`
  /// skip path: that branch has already `wait`ed but will encode no command buffer this frame, so it
  /// must balance the wait here or the `value: 1` semaphore deadlocks (threat T-06-03-01). Every
  /// `waitForNextFrame()` is balanced by exactly one signal — via `signalOnComplete` on the normal
  /// path, or via this on the skip path.
  public func signal() {
    semaphore.signal()
  }
}
