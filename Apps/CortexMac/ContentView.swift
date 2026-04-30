import SwiftUI
import CortexCore

struct ContentView: View {
  @State private var shmCheckResult: ShmCheckResult?

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
      Divider()
      Button("Run Phase 1 SC#2 ShmCheck") {
        let r = ShmCheck.openSharedRegion(processLabel: "CortexMac.app")
        shmCheckResult = r
        // Also log to NSLog so Console.app captures it for evidence.
        NSLog("[Cortex SC#2] %@", String(describing: r))
      }
      if let r = shmCheckResult {
        ScrollView {
          Text(r.description)
            .font(.system(.footnote, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
        }
        .frame(maxHeight: 220)
      }
    }
    .padding(40)
    .frame(minWidth: 560, minHeight: 480)
  }
}
