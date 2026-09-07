@testable import CortexIPCTransport

// CortexIPCTransportTests — placeholder so the test target declared in Package.swift has a
// source directory after the Plan 02-01 split. Real ring / doorbell / mach_msg FD-passing
// tests (RingTests, DoorbellTests, FdPassTests) land in Plan 02-02.
import Testing

@Test("CortexIPCTransport target links")
func transportTargetLinks() {
  // The split target exists and is importable. Plan 02-02 replaces this with real tests.
  _ = CortexIPCTransport.self
}
