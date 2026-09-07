@testable import CortexBCIHID

// DaemonRegistrationTests — Phase 8 (SYS-02, D-03): unit-test the SMAppService daemon-registration
// SCAFFOLD via the mockable status path. The live SMAppService install is paid-signing-gated (Plan 07
// HUMAN-UAT), so these tests exercise the protocol + status enum + MockDaemonService — not a real
// registration — exactly as the Validation Architecture (RESEARCH §Validation) routes SYS-02:
// **Automated** (code path) + **Manual-Only** (live registration).
import Testing

/// The DaemonRegistration types + VirtualDeviceGate are MainActor-isolated (the package default
/// .defaultIsolation(MainActor.self)); the suite adopts the same isolation to drive them synchronously
/// (mirrors the CortexReFIT KalmanConstantsTests precedent).
@Suite("DaemonRegistrationTests")
@MainActor
struct DaemonRegistrationTests {
  @Test("Mock reports its fixed status and register()/unregister() are callable")
  func mockStatusAndRegisterPath() throws {
    let mock = MockDaemonService(status: .requiresApproval)
    #expect(mock.status == .requiresApproval)
    #expect(mock.registerCallCount == 0)
    try mock.register()
    #expect(mock.registerCallCount == 1)
    try mock.unregister()
    #expect(mock.unregisterCallCount == 1)
  }

  @Test("DaemonService abstracts the status across all SMAppService.Status mirror cases")
  func statusEnumMirrorsSMAppService() {
    let cases: [DaemonRegistrationStatus] = [.notRegistered, .enabled, .requiresApproval, .notFound]
    for expected in cases {
      let service: any DaemonService = MockDaemonService(status: expected)
      #expect(service.status == expected)
    }
  }

  @Test("DaemonRegistration carries the bundled launch-daemon plist name")
  func registrationModelsPlistName() {
    let registration = DaemonRegistration(plistName: "com.donovansantine.cortex.daemon.plist")
    #expect(registration.plistName == "com.donovansantine.cortex.daemon.plist")
  }

  @Test("VirtualDeviceGate is inert by default (CORTEX_HID_LIVE OFF) — no live HID symbol linked")
  func virtualDeviceGateInertByDefault() {
    // The default free-team build must NOT compile in the live path (T-08-01-02 / AMFI-safe).
    #expect(VirtualDeviceGate.isLive == false)
  }
}
