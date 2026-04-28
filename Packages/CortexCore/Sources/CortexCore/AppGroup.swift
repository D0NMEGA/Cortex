// App Group container helpers. Identifier defined per D-07.
// On macOS, the container path is ~/Library/Group Containers/<identifier>/.
// On iOS Simulator, App Group is silently ignored (per RESEARCH.md Q4 / Critical Finding #1).

import Foundation

public enum AppGroup {
  /// App Group identifier shared by CortexiOS, CortexMac, and CortexDaemon.
  /// Source of truth: 01-CONTEXT.md D-07.
  public static let identifier: String = "group.com.donovansantine.cortex.shared"

  /// Returns the URL of the App Group container on macOS / iOS device,
  /// or nil on the iOS Simulator (where the entitlement is silently ignored).
  public static func containerURL() -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
  }
}
