// CortexMac -- native AppKit macOS 26 Tahoe application target.
// This target uses the native AppKit runtime, not the iOS-bridged runtime.
// Phase 6 RENDER-08 requires NSScreen.displayLink which the iOS-bridged path
// cannot surface cleanly. The NSApplicationDelegateAdaptor below anchors the
// SwiftUI App lifecycle to AppKit so the runtime stays native.
//
// project.yml sets SUPPORTS_MACCATALYST: NO on the build settings as defense-in-depth.

import SwiftUI
import AppKit
import CortexCore

@main
struct CortexMacApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Phase 1 placeholder. Phase 2 will spawn the daemon and open the shm region here.
    NSLog("Cortex.app (Mac) launched. App Group: \(CortexCore.AppGroup.identifier)")
  }
}
