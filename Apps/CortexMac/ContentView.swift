import SwiftUI
import CortexCore

struct ContentView: View {
  var body: some View {
    VStack(spacing: 16) {
      Text("Cortex.app -- Phase 1 / 10")
        .font(.title)
      Text("Foundation & 2026 Toolchain (macOS native)")
        .font(.headline)
      Text("App Group: \(CortexCore.AppGroup.identifier)")
        .font(.footnote)
        .monospaced()
      Text("SHM region: \(Cortex.shmName)")
        .font(.footnote)
        .monospaced()
      if let url = CortexCore.AppGroup.containerURL() {
        Text("Container: \(url.path)")
          .font(.footnote)
          .monospaced()
          .foregroundStyle(.secondary)
      } else {
        Text("Container: not available (sandbox or simulator)")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .padding(40)
    .frame(minWidth: 560, minHeight: 480)
  }
}
