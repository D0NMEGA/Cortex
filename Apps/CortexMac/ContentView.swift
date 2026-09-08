import CortexBCIHID
import CortexCore
import CortexDemo
import CortexRender
import SwiftUI

// Phase 8 (SYS-06/PERF-04, D-09/D-10): the CortexMac v0 replay-loop GUI demo. This REPLACES the Phase-6
// oscillator-velocity drive with the REAL synthetic-spike → NDT1 → ReFIT-Kalman → CursorIntegrator →
// 30×30 webgrid replay loop (`CortexDemo.ReplayPipeline`), so the decoder + Kalman are GENUINELY in
// the live demo loop (D-10), not bypassed. The Phase-6 render path is UNCHANGED: the same
// `WebgridView(ring:)` + `MacDisplayLinkAdapter` (NSView.displayLink) consume the same `VelocityRing`
// at 120Hz (RENDER-08); only the PRODUCER changed (the decoder loop, not the oscillator). This is the
// D-09 runnable v0 artifact — free-team GUI-launchable with MTL_HUD_ENABLED=1 (the iPad build is the
// same code, gated). It VISIBLY surfaces (1) the SYS-03/04 instrumented BCI-HID round-trip log line and
// (2) the latest SOFTWARE-TIMED glass-to-glass sample WITH the verbatim methodology label (D-07) — so
// the demo shows the replay loop AND the honest latency framing, never an over-claimed number.
struct ContentView: View {
  /// The producer→renderer SPSC seam (D-03), once per arm. Each view's display-link callback is the
  /// single consumer of its own ring; each driver's MainActor timer is the single producer.
  ///
  /// TWO arms run side by side on the SAME session and the SAME decoded spikes, because the
  /// difference between them is the whole point. `blind` is what the decoder does; `refit` is what
  /// target knowledge does. Showing only the second is how a target-determined result gets mistaken
  /// for a decoding result (10-PREREGISTRATION section 7).
  @State private var blind = ReplayDriver(rotationEnabled: false)
  @State private var refit = ReplayDriver(rotationEnabled: true)

  var body: some View {
    VStack(spacing: 0) {
      // A real gutter, not a hairline. Each pane letterboxes and rules its OWN lattice, so butted
      // together with a 1 pt gap the two boards read as a single grid with one doubled line at the
      // join -- measured: the left board's last rule and the right board's first sat 50 px apart
      // against a uniform 98 px pitch.
      HStack(spacing: 10) {
        arm(
          driver: blind,
          title: "kalman_only - heading from the decode",
          caption: "Heading is the DECODE's own; no target steering, and nothing repositions the "
            + "cursor. Open-loop integration error accumulates without bound, and this is what that "
            + "looks like. Published: 0 of 1025."
        )
        arm(
          driver: refit,
          // NOT "refit". ReFIT retrains decoder parameters against target-informed intention; this
          // applies an intent ROTATION at inference and trains nothing. Calling the arm refit
          // credits the run with a method it does not implement.
          title: "target-assisted - heading supplied",
          caption: "IntentRotation replaces the decoded heading with the direction to the KNOWN "
            + "target, keeping only decoded SPEED, which is why this one does not drift. NOT a "
            + "decoding result. Published: 70 of 1025."
        )
      }

      // What the cursor IS, in one line. It free-runs: nothing repositions it between trials, so
      // what is on screen is the decode's own integrated velocity for as long as the replay runs.
      // That is the honest thing to show and it is also unflattering, which is the point -- the
      // decode-only pane drifts to an edge and stays there, and the caption says so rather than the
      // demo quietly correcting it.
      Text("The cursor FREE-RUNS: decoded velocity integrated open-loop, never repositioned. A "
        + "replay cannot close the loop -- the animal was watching its own hand, not this cursor. "
        + "Each trial is clicked when the recorded task moved its target on: the TASK supplies the "
        + "click's timing, the DECODE supplies the cursor's position.")
        .font(.system(size: 9, design: .monospaced))
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black)
        .foregroundStyle(.orange)

      // The honest instrumentation strip (D-07/D-09): source label, the SYS-03/04 round-trip line and
      // the latest software-timed glass-to-glass sample WITH the methodology label (no over-claim).
      VStack(alignment: .leading, spacing: 4) {
        // D-16: name the spike source ON SCREEN. A demo that silently ran synthetic while being
        // recorded as real-data evidence is the Pattern-2 trap in capture form.
        Text(blind.sourceLabel)
          .font(.system(.caption, design: .monospaced))
        Text(blind.decodeLine)
          .font(.system(.caption, design: .monospaced))
        Text(blind.roundTripLine)
          .font(.system(.caption, design: .monospaced))
        Text(blind.latencyLine)
          .font(.system(.caption, design: .monospaced))
        Text(GlassToGlassTimer.methodologyLabel)
          .font(.system(size: 9, design: .monospaced))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
      .background(.black)
      .foregroundStyle(.white)
    }
    .onAppear { blind.start()
      refit.start()
    }
    .onDisappear { blind.stop()
      refit.stop()
    }
  }

  /// A live acquisition tally for one arm.
  ///
  /// LIVE, and labelled so, because it counts only the trials that have replayed since launch. The
  /// published 0-of-1025 and 70-of-1025 in the arm captions come from the full free-running scored
  /// replay and are a different measurement; a viewer who conflates them would read a two-minute
  /// capture as the session result.
  private func scoreBadge(driver: ReplayDriver) -> some View {
    VStack(alignment: .trailing, spacing: 1) {
      // Green while the last click was a hit, white again once its marker has faded, so the tally
      // reads as "that one counted" at the moment it counts.
      Text("\(driver.selectionCount) / \(driver.trialCount)")
        .font(.system(size: 15, design: .monospaced).bold())
        .foregroundStyle(driver.lastClickHit ? .green : .white)
      Text("clicked on target / trials, this run")
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(.secondary)
      // A zero tally alone cannot say whether the cursor was landing just outside the cell or
      // nowhere near it. This says which, and it is the number to read before concluding anything
      // from a zero.
      Text(driver.missLabel)
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(.secondary)
      Text(driver.radiusLabel)
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 5))
    .padding(8)
  }

  /// One arm's render surface with the label that says what it is and what it is not.
  private func arm(driver: ReplayDriver, title: String, caption: String) -> some View {
    VStack(spacing: 0) {
      // The Phase-6 120Hz webgrid render surface — UNCHANGED (RENDER-08), now driven by the real loop.
      WebgridView(
        ring: driver.ring,
        targets: driver.targets,
        selection: driver.selection,
        cursorPositions: driver.cursorPositions,
        lattice: driver.lattice,
        targetHalfExtent: driver.scoringHalfExtent,
        board: driver.board
      )
      .frame(minWidth: 360, minHeight: 360)
      .overlay(alignment: .topTrailing) { scoreBadge(driver: driver) }
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(.caption, design: .monospaced).bold())
        Text(caption)
          .font(.system(size: 9, design: .monospaced))
          .foregroundStyle(.secondary)
          // Bounded rather than fixed-size, for the same reason as the re-anchoring banner: a
          // fixed-size Text proposed a near-zero width mid-resize demands an unbounded height.
          .lineLimit(3)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(6)
      .background(.black)
      .foregroundStyle(.white)
    }
  }
}
