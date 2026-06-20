// CortexIPCSessionTests — placeholder so the test target declared in Package.swift has a
// source directory after the Plan 02-01 split. Real codec / crypto / Keychain tests
// (SampleCodecTests, CryptoTests, KeychainTests) land in Plan 02-03.
import Testing

@testable import CortexIPCSession

@Test("CortexIPCSession target links")
func sessionTargetLinks() {
  // The split target exists and is importable. Plan 02-03 replaces this with real tests.
  _ = CortexIPCSession.self
}
