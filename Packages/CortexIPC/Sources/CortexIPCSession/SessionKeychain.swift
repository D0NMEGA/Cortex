// SessionKeychain — IPC-06 / SC#3. Round-trips the random 256-bit session secret (D-14) through the
// macOS DATA-PROTECTION Keychain.
//
// PRODUCTION attributes (Backend.dataProtection, the DEFAULT — never weakened):
//   • kSecUseDataProtectionKeychain = kCFBooleanTrue!  — CF#8: MUST be kCFBooleanTrue, NEVER Swift
//     `true` (Swift `true` bridges to a number here and yields errSecParam -50). The data-protection
//     keychain is mandatory because the legacy file keychain does not honor the accessibility class below.
//   • kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly  — IPC-06: not readable
//     before first unlock, never leaves the device, excluded from backups (threat T-02-03-03).
//
// CF#1 VERDICT = FAIL → FALLBACK (02-SPIKES.md, recorded on real M4/Xcode 26.3): a bare `type: tool`
// under the free/personal team Y4A54395NZ cannot carry a team-prefixed `keychain-access-groups`
// entitlement (AMFI SIGKILL at exec when entitled; errSecMissingEntitlement -34018 when not). So this
// layer uses the application's DEFAULT access group — kSecAttrAccessGroup is OMITTED — which needs no
// provisioning profile and literally satisfies SC#3's "the key round-tripping Keychain" + IPC-06.
//
// CF#1 COROLLARY (proven during Plan 02-03, /tmp/kc-probe): the DATA-PROTECTION keychain itself is
// unreachable from any binary on this machine without a paid-team provisioning profile — unentitled →
// errSecMissingEntitlement (-34018); entitled with application-identifier OR keychain-access-groups →
// AMFI SIGKILL (exit 137), the same kill mode as the CF#1 access-group spike. The unentitled
// swift-test host therefore CANNOT exercise the data-protection keychain. The legacy (file) keychain,
// by contrast, round-trips unentitled (verified). To keep the production data-protection requirement
// AND have a runnable unit test, `Backend` parameterizes the query: production = `.dataProtection`
// (unchanged), KeychainTests inject `.legacyFile` to exercise the round-trip/not-found/idempotent
// LOGIC on the unentitled host. The data-protection item SHAPE was already built+signed+run on real M4
// by the CF#1 spike; the full data-protection round-trip is exercised under enrollment in Phase 8.
//
// D-14/D-15 RECONCILIATION: the "secret stored in Keychain + HKDF per-direction subkeys" half of D-15
// is honored now (SessionKeychain + SessionCrypto); the "share via a shared Keychain ACCESS GROUP"
// half is DEFERRED to Phase 8 (enrollment, paid team prefix). In Phase 2 the peer receives the secret
// over the secure mach_msg channel (Plan 02-04), NOT via a shared access group. `deferredAccessGroup`
// below is the single named constant Phase 8 flips on under the enrolled team prefix.
//
// Security discipline (T-02-03-04, carried from the CF#1 spike): errors carry OSStatus only — never
// the key bytes. CortexIPCSession is Foundation-allowed (D-04/D-06); not policed by the hot-path gate.
import Foundation
import Security
import CryptoKit

public nonisolated enum SessionKeychain {

  /// Keychain account under which the 256-bit session secret is stored.
  public static let account = "cortex.session.secret"

  /// Generic-password service scoping the item.
  public static let service = "com.donovansantine.cortex.session"

  /// DEFERRED (Phase 8): the team-prefixed Keychain access group for true CROSS-PROCESS sharing.
  ///
  /// Currently UNUSED — `baseQuery()` deliberately omits `kSecAttrAccessGroup` per the CF#1 = FAIL
  /// verdict (02-SPIKES.md): a bare tool under a free team cannot back a team-prefixed
  /// `keychain-access-groups` entitlement (AMFI SIGKILL / errSecMissingEntitlement -34018). When paid
  /// Apple Developer Program enrollment lands (Phase 8), reconcile the team prefix (free team
  /// Y4A54395NZ → the enrolled team's prefix) and set this on the query to share the secret via the
  /// access group instead of over the mach_msg channel (Plan 02-04). Until then the peer receives the
  /// key over the secure mach_msg channel — this constant must NOT be added to `baseQuery()` in Phase 2.
  public static let deferredAccessGroup = "Y4A54395NZ.group.com.donovansantine.cortex.shared"

  /// Which keychain the query targets. Production is `.dataProtection` (IPC-06); `.legacyFile` exists
  /// ONLY so the unit test can round-trip on the unentitled swift-test host (see the CF#1 corollary
  /// in the file header). `.legacyFile` does NOT honor `AfterFirstUnlockThisDeviceOnly` and must never
  /// be used in production.
  public enum Backend: Sendable {
    /// PRODUCTION (IPC-06): data-protection keychain, kCFBooleanTrue, AfterFirstUnlockThisDeviceOnly.
    case dataProtection
    /// TEST-ONLY: legacy file keychain (works unentitled). No data-protection accessibility class.
    case legacyFile
  }

  /// Errors surface OSStatus only — never key material (threat T-02-03-04).
  public enum KeychainError: Error, Equatable, Sendable {
    case add(OSStatus)
    case copy(OSStatus)
    case delete(OSStatus)
    /// The stored item was present but not the expected secret bytes.
    case unexpectedData
  }

  /// The shared item attributes. `.dataProtection` (default/production) sets kSecUseDataProtectionKeychain
  /// = kCFBooleanTrue! (CF#8) + kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly (IPC-06), and OMITS
  /// kSecAttrAccessGroup (default access group, CF#1 fallback).
  static func baseQuery(backend: Backend) -> [String: Any] {
    var q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    switch backend {
    case .dataProtection:
      // CF#8: kCFBooleanTrue, NOT Swift `true` (which yields errSecParam -50 here).
      q[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue!
      q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    case .legacyFile:
      // Test-only: the legacy file keychain round-trips on the unentitled host. No data-protection
      // flag and no AfterFirstUnlockThisDeviceOnly class (the legacy keychain ignores it).
      break
    }
    return q
  }

  /// Store `secret` (delete-then-add for idempotency). The secret bytes are written as
  /// `kSecValueData`; nothing is logged. Defaults to the production data-protection keychain (IPC-06).
  public static func store(secret: SymmetricKey, backend: Backend = .dataProtection) throws {
    let data = secret.withUnsafeBytes { Data($0) }
    var query = baseQuery(backend: backend)
    // Idempotent: remove any prior item first (ignore not-found).
    let deleteStatus = SecItemDelete(query as CFDictionary)
    guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
      throw KeychainError.delete(deleteStatus)
    }
    query[kSecValueData as String] = data
    let addStatus = SecItemAdd(query as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw KeychainError.add(addStatus)
    }
  }

  /// Load the session secret. Throws `copy(errSecItemNotFound)` (fail-closed) when absent.
  public static func load(backend: Backend = .dataProtection) throws -> SymmetricKey {
    var query = baseQuery(backend: backend)
    query[kSecReturnData as String] = kCFBooleanTrue!
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &out)
    guard status == errSecSuccess else {
      throw KeychainError.copy(status)
    }
    guard let data = out as? Data else {
      throw KeychainError.unexpectedData
    }
    return SymmetricKey(data: data)
  }

  /// Delete the session secret. `errSecItemNotFound` is treated as success (idempotent).
  public static func delete(backend: Backend = .dataProtection) throws {
    let status = SecItemDelete(baseQuery(backend: backend) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.delete(status)
    }
  }
}
