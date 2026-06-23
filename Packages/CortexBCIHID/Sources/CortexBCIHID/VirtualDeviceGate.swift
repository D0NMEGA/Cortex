#if CORTEX_HID_LIVE
  // Imports for the live path ONLY (file-scope, gated). These compile in solely under -D CORTEX_HID_LIVE
  // so the default free-team build links no live HID symbol (T-08-01-02 / AMFI-safe). `IOKit` provides
  // the IOHIDUserDevice C API; `Foundation` provides `Data`; `Darwin` provides `mach_absolute_time()`.
  import Darwin
  import Foundation
  import IOKit
#endif

/// The live virtual-HID-device seam. Inert by default; the live instantiation members exist only when
/// the binary is built with the `CORTEX_HID_LIVE` compile flag (opt-in, never in a default config).
public enum VirtualDeviceGate {
  /// Errors surfaced by the gated seam (used by the inert stubs and, when live, the real path).
  public enum GateError: Error, Sendable, Equatable {
    /// The live HID path is not compiled in (default free-team build) — `CORTEX_HID_LIVE` is OFF.
    case notEnabled
    /// Creating the virtual device failed (live path only) — carries the IOReturn-style code.
    case deviceCreationFailed(Int32)
  }

  #if CORTEX_HID_LIVE
    // ─────────────────────────────────────────────────────────────────────────────────────────────
    // LIVE PATH — compiled ONLY under -D CORTEX_HID_LIVE (the Plan 07 gated device session). This is
    // the ONLY place the live IOHIDUserDevice symbol may appear; hid-surface-policy.sh proves no other
    // CortexBCIHID source references it. Requires the com.apple.developer.hid.virtual.device entitlement
    // (managed provisioning profile) + a system Accessibility-permission grant.
    //
    // The code below is the documented Apple C API verbatim (developer.apple.com BCI HID reference).
    // `IOHIDUserDevice` / `IOHIDUserDeviceCreate` / `IOHIDUserDeviceHandleReportWithTimeStamp` are NOT
    // surfaced by the public Swift IOKit overlay (no `IOHIDUserDevice.h` in the SDK module map —
    // RESEARCH §9 [verify]), so activating CORTEX_HID_LIVE additionally requires the Plan-07 C-interop
    // bridging module (or the modern CoreHID `HIDVirtualDevice`); the default free-team build is OFF and
    // links none of this. This is the Plan 01-02 "scaffold-now, device-session-deferred" pattern.

    /// True when the live HID path is compiled in.
    public static let isLive = true

    /// Create the virtual HID device from the BCI descriptor bytes. The created device is registered
    /// with the host's Switch Control / AssistiveTouch as a BCI HID provider.
    public static func createVirtualDevice(descriptor: [UInt8]) throws -> IOHIDUserDevice {
      let properties: [String: Any] = [
        kIOHIDReportDescriptorKey as String: Data(descriptor)
      ]
      guard let device = IOHIDUserDeviceCreate(kCFAllocatorDefault, properties as CFDictionary) else {
        throw GateError.deviceCreationFailed(-1)
      }
      return device
    }

    /// Send a BCI input report (e.g. a Pointer RID-3 cursor delta) to the host. The timestamp is
    /// `mach_absolute_time()` — the same clock as the PERF-04 glass-to-glass instrumentation.
    public static func sendReport(_ device: IOHIDUserDevice, report: [UInt8], timestamp: UInt64) {
      var bytes = report
      IOHIDUserDeviceHandleReportWithTimeStamp(device, timestamp, &bytes, bytes.count)
    }

    /// Send a Pointer report at the current `mach_absolute_time()`.
    public static func sendPointer(_ device: IOHIDUserDevice, _ pointer: BCIInputPointerReport) {
      sendReport(device, report: pointer.encode(), timestamp: mach_absolute_time())
    }

  #else
    // ─────────────────────────────────────────────────────────────────────────────────────────────
    // INERT DEFAULT PATH — the free-team demo build. No live HID symbol is linked; every entry point
    // throws `.notEnabled`, so callers compile and run but cannot instantiate a real device.

    /// False — the live HID path is NOT compiled into this (default) build.
    public static let isLive = false

    /// Inert: the live device-creation path is gated out. Throws `.notEnabled`.
    public static func createVirtualDevice(descriptor _: [UInt8]) throws -> Never {
      throw GateError.notEnabled
    }

    /// Inert: report sending is gated out. Throws `.notEnabled`.
    public static func sendReport(report _: [UInt8], timestamp _: UInt64) throws {
      throw GateError.notEnabled
    }

    /// Inert: pointer sending is gated out. Throws `.notEnabled`.
    public static func sendPointer(_: BCIInputPointerReport) throws {
      throw GateError.notEnabled
    }
  #endif
}
