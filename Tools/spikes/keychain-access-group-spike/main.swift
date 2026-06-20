// CF#1 spike — cross-process Keychain access-group round-trip on the data-protection keychain.
//
// Purpose (Phase 2, Plan 02-01, Task 2): determine on REAL M4 + Xcode 26.3 hardware whether a
// bare Mach-O `tool` (CortexDaemon is `type: tool`) can write a 32-byte session secret to the
// data-protection keychain under a team-prefixed `keychain-access-groups` access group, and
// whether a SECOND process can read the identical bytes back. This is the SC#3 / IPC-06 risk
// flagged in 02-RESEARCH.md Critical Finding #1: a bare tool has no bundle/provisioning profile,
// so a team-prefixed access group may be rejected at runtime with errSecMissingEntitlement
// (-34018) under free/local signing.
//
// Usage:
//   cortex-kc-spike write   — process A: SecItemDelete (clear) -> SecItemAdd (store 32 bytes)
//   cortex-kc-spike read    — process B: SecItemCopyMatching   -> compare to the known pattern
//
// SECURITY (threat T-02-01-04): this tool prints OSStatus codes and a byte-MATCH boolean ONLY.
// It NEVER prints the secret bytes. The 32-byte payload is a fixed, non-secret test pattern so
// the read side can verify an exact match without the writer persisting anything out-of-band.
//
// CF#8 (02-RESEARCH.md Finding #8): kSecUseDataProtectionKeychain MUST be kCFBooleanTrue, NOT
// Swift `true` (Swift `true` bridges to a value that yields errSecParam -50).

import Darwin
import Security

// Team prefix of the ACTUAL local signing identity:
//   "Apple Development: don.mega11@icloud.com (Y4A54395NZ)"  -> TEAM PREFIX Y4A54395NZ.
// The plan/project memory assumed Team 57YW6M29S7, but the binary is signed under Y4A54395NZ,
// so the runtime kSecAttrAccessGroup must use Y4A54395NZ. (spike.entitlements declares the group
// via $(AppIdentifierPrefix), which codesign expands to this same literal team prefix.) Using the
// wrong prefix would fail spuriously and make the CF#1 verdict meaningless.
let teamPrefix = "Y4A54395NZ."
let accessGroup = teamPrefix + "group.com.donovansantine.cortex.shared"
let account = "cortex.session.secret"

// Fixed, NON-SECRET 32-byte test pattern (0x00..0x1F). A real session key is a random
// SymmetricKey(size: .bits256) — here we use a deterministic pattern so the read side can
// verify an exact byte match without printing key material.
let pattern: [UInt8] = Array(0..<32)

// Base query shared by all operations — EXACTLY the Phase-2 production item shape.
func baseQuery() -> [CFString: Any] {
  [
    kSecClass: kSecClassGenericPassword,
    // CF#8: kCFBooleanTrue (a CFBoolean), never Swift `true`.
    kSecUseDataProtectionKeychain: kCFBooleanTrue as Any,
    kSecAttrAccount: account,
    kSecAttrAccessGroup: accessGroup,
  ]
}

func name(for status: OSStatus) -> String {
  switch status {
  case errSecSuccess: return "errSecSuccess"
  case errSecItemNotFound: return "errSecItemNotFound"
  case errSecDuplicateItem: return "errSecDuplicateItem"
  case errSecParam: return "errSecParam"
  case errSecMissingEntitlement: return "errSecMissingEntitlement"
  case errSecInteractionNotAllowed: return "errSecInteractionNotAllowed"
  case errSecNotAvailable: return "errSecNotAvailable"
  default: return "OSStatus"
  }
}

func log(_ label: String, _ status: OSStatus) {
  print("\(label): \(status) (\(name(for: status)))")
}

func doWrite() -> Int32 {
  // Clear any prior item (idempotent): expect errSecSuccess or errSecItemNotFound.
  let delStatus = SecItemDelete(baseQuery() as CFDictionary)
  log("SecItemDelete", delStatus)

  var addQuery = baseQuery()
  addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  addQuery[kSecValueData] = Data(pattern)
  let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
  log("SecItemAdd", addStatus)

  return addStatus == errSecSuccess ? 0 : 1
}

func doRead() -> Int32 {
  var query = baseQuery()
  query[kSecReturnData] = kCFBooleanTrue as Any
  query[kSecMatchLimit] = kSecMatchLimitOne

  var item: CFTypeRef?
  let status = SecItemCopyMatching(query as CFDictionary, &item)
  log("SecItemCopyMatching", status)

  guard status == errSecSuccess, let data = item as? Data else {
    print("byte_match: false (no data returned)")
    return 1
  }
  let bytes = [UInt8](data)
  let match = bytes == pattern
  // Never print the bytes — only length + match boolean.
  print("returned_length: \(bytes.count)")
  print("byte_match: \(match)")
  return match ? 0 : 1
}

// Foundation-free Data construction helper note: `Data` here comes via the Security/CoreFoundation
// bridge in the Swift overlay; this is a throwaway spike under Tools/spikes (never shipped, never
// policed by hotpath-policy.sh), so the Foundation bridge is acceptable.
import Foundation

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let rc: Int32
switch mode {
case "write": rc = doWrite()
case "read": rc = doRead()
default:
  FileHandle.standardError.write(Data("usage: cortex-kc-spike <write|read>\n".utf8))
  rc = 2
}
exit(rc)
