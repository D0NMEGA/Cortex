import SwiftUI
import CortexCore

struct ContentView: View {
  var body: some View {
    VStack(spacing: 16) {
      Text("Cortex.app -- Phase 1 / 10")
        .font(.title)
      Text("Foundation & 2026 Toolchain")
        .font(.headline)
      Text("App Group: \(CortexCore.AppGroup.identifier)")
        .font(.footnote)
        .monospaced()
      Text("SHM region: \(Cortex.shmName)")
        .font(.footnote)
        .monospaced()
    }
    .padding()
  }
}
