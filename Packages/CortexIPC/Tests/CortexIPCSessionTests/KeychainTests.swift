@testable import CortexIPCSession
import Foundation
import Security

// KeychainTests — IPC-06 / SC#3. SINGLE-process round-trip of the 256-bit session secret through the
// Keychain (CF#1 fallback: default access group, no team-prefixed kSecAttrAccessGroup). Proves SC#3's
// "the key round-tripping Keychain" round-trip/not-found/idempotent LOGIC, and asserts the PRODUCTION
// data-protection query carries the IPC-06 attributes (kCFBooleanTrue + AfterFirstUnlockThisDeviceOnly).
//
// CF#1 COROLLARY (proven in Plan 02-03, /tmp/kc-probe): the data-protection keychain is unreachable
// from the unentitled swift-test host — unentitled → errSecMissingEntitlement (-34018); entitled →
// AMFI SIGKILL (137) under the free team. So the round-trip tests run against `Backend.legacyFile`
// (which round-trips unentitled); production stays `.dataProtection`. The data-protection item shape
// was built+signed+run on real M4 by the CF#1 spike; its full round-trip is exercised under enrollment
// in Phase 8. The CROSS-process leg is delivered over mach_msg in Plan 02-04 (CF#1 = FAIL verdict).
//
// Security discipline (T-02-03-04): tests assert byte-equality locally and NEVER print the secret.
// Each test cleans up its Keychain item in `init`/`defer` for isolation (Swift Testing fresh-instance).
import Testing

@Suite("SessionKeychain (IPC-06 / SC#3)", .serialized)
struct KeychainTests {
  /// Round-trip logic is exercised against the legacy file keychain (works on the unentitled host).
  private static let testBackend: SessionKeychain.Backend = .legacyFile

  /// Fresh instance per test (Swift Testing). Ensure no stale item leaks in or out.
  init() {
    try? SessionKeychain.delete(backend: Self.testBackend)
  }

  private func cleanup() {
    try? SessionKeychain.delete(backend: Self.testBackend)
  }

  @Test("store then load returns the identical 32 secret bytes (SC#3 round-trip)")
  func roundTripByteEquality() throws {
    defer { cleanup() }
    let secret = SessionKeys.generateSecret()
    let original = secret.withUnsafeBytes { Array($0) }
    #expect(original.count == 32)

    try SessionKeychain.store(secret: secret, backend: Self.testBackend)
    let loaded = try SessionKeychain.load(backend: Self.testBackend)
    let loadedBytes = loaded.withUnsafeBytes { Array($0) }

    #expect(loadedBytes == original)
  }

  @Test("load after delete throws an errSecItemNotFound-derived error (fail-closed)")
  func notFoundAfterDelete() throws {
    defer { cleanup() }
    let secret = SessionKeys.generateSecret()
    try SessionKeychain.store(secret: secret, backend: Self.testBackend)
    try SessionKeychain.delete(backend: Self.testBackend)

    #expect(throws: SessionKeychain.KeychainError.copy(errSecItemNotFound)) {
      _ = try SessionKeychain.load(backend: Self.testBackend)
    }
  }

  @Test("storing twice (delete-then-add) succeeds without errSecDuplicateItem; second value wins")
  func idempotentReStore() throws {
    defer { cleanup() }
    let first = SessionKeys.generateSecret()
    let second = SessionKeys.generateSecret()
    let secondBytes = second.withUnsafeBytes { Array($0) }

    try SessionKeychain.store(secret: first, backend: Self.testBackend)
    // Must not throw errSecDuplicateItem — store() deletes any prior item first.
    try SessionKeychain.store(secret: second, backend: Self.testBackend)

    let loaded = try SessionKeychain.load(backend: Self.testBackend).withUnsafeBytes { Array($0) }
    #expect(loaded == secondBytes)
  }

  @Test("delete is idempotent — deleting a non-existent item does not throw")
  func deleteIsIdempotent() throws {
    defer { cleanup() }
    // No item stored. Both calls must succeed (errSecItemNotFound treated as success).
    try SessionKeychain.delete(backend: Self.testBackend)
    try SessionKeychain.delete(backend: Self.testBackend)
  }

  @Test("the PRODUCTION query is the data-protection keychain (kCFBooleanTrue + AfterFirstUnlock, IPC-06/CF#8)")
  func productionQueryHasDataProtectionAttributes() {
    let q = SessionKeychain.baseQuery(backend: .dataProtection)

    // kSecUseDataProtectionKeychain must be the CFBoolean true (CF#8), NOT a Swift Bool / NSNumber.
    let dp = q[kSecUseDataProtectionKeychain as String]
    #expect(dp != nil)
    #expect(CFGetTypeID(dp as CFTypeRef) == CFBooleanGetTypeID())
    #expect((dp as! CFBoolean) == kCFBooleanTrue)

    // Accessibility class is AfterFirstUnlockThisDeviceOnly (IPC-06).
    let accessible = q[kSecAttrAccessible as String]
    #expect((accessible as! CFString) == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)

    // CF#1 fallback: NO team-prefixed access group in the Phase-2 query (default access group).
    #expect(q[kSecAttrAccessGroup as String] == nil)
  }
}
