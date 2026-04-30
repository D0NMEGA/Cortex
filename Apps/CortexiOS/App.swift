// CortexiOS -- iPadOS 26 application target.
// Phase 1 ships an empty shell. Phase 2 will wire IPC; Phase 6 will wire the renderer.

import SwiftUI
import CortexCore  // Re-exports CortexCoreC; Cortex.shmName is reachable.

@main
struct CortexiOSApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
