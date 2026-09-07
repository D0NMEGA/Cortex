import CortexRender
import SwiftUI

/// Phase 6 (RENDER-01/02/07): the iPad ProMotion render surface. The Phase-1 placeholder text is
/// replaced by the live 30×30 webgrid driven via CAMetalDisplayLink at 120Hz (iOSDisplayLinkAdapter),
/// full-bleed so the grid fills the panel. A deterministic LissajousProducer (D-05) pushes synthetic
/// cursor velocity into the shared VelocityRing the display-link callback pops — so the cursor moves
/// at launch with no real decoder yet (the Phase-5 decoder / Phase-7 Kalman become the producer later
/// behind the unchanged D-03 seam).
struct ContentView: View {
  /// The producer→renderer SPSC seam (D-03). The view's display-link callback is the single
  /// consumer; `WebgridDriver` below is the single producer — SPSC discipline upheld.
  @State private var driver = WebgridDriver()

  var body: some View {
    WebgridView(ring: driver.ring)
      .ignoresSafeArea() // full-bleed: the grid fills the entire ProMotion panel
      .onAppear { driver.start() }
      .onDisappear { driver.stop() }
  }
}

/// Owns the SINGLE synthetic producer thread that fills the `VelocityRing` from a deterministic
/// `LissajousProducer` (D-05) at the DEC-10 ~50Hz (20ms) cadence. One producer thread keeps the SPSC
/// invariant crisp; this is the synthetic drive, NOT the Phase-3 acquisition hot path, so a plain
/// `Thread` + sleep is appropriate here (no QoS/pthread ceremony needed).
@MainActor
final class WebgridDriver {
  /// 4096-slot ring (power-of-two; ample for a 50Hz producer vs a 120Hz consumer). `init?` only
  /// fails for a non-power-of-two/zero capacity, so this force-unwrap is total.
  let ring = VelocityRing(capacity: 4096)!
  private let producer = LissajousProducer()
  private var thread: Thread?

  func start() {
    guard thread == nil else { return }
    let ring = ring
    let producer = producer
    let t = Thread {
      // Deterministic time base: t advances by the fixed 20ms step each push (not a wall clock), so
      // the synthetic path is bit-reproducible for the SC#4 soak (D-05). seq is monotonic.
      let stepSeconds = 0.020
      var seq: UInt64 = 0
      var simTime = 0.0
      while !Thread.current.isCancelled {
        let (vx, vy) = producer.velocity(at: simTime)
        _ = ring.push(CursorVelocity(ts_ns: UInt64(seq) &* 20_000_000, seq: seq, vx: vx, vy: vy))
        seq &+= 1
        simTime += stepSeconds
        Thread.sleep(forTimeInterval: stepSeconds)
      }
    }
    t.name = "app.cortex.render.lissajous-producer"
    t.start()
    thread = t
  }

  func stop() {
    thread?.cancel()
    thread = nil
  }
}
