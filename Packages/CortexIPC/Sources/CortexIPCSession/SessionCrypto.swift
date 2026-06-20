// SessionCrypto — IPC-05. AES-GCM (CryptoKit, FEAT_AES on Apple Silicon) with HKDF-derived
// per-direction subkeys and a 96-bit DETERMINISTIC nonce that reuses the ring `seq` as its counter.
//
// Key & nonce lifecycle (D-14/D-15/D-16):
//   • D-14  random 256-bit secret per daemon launch: SymmetricKey(size: .bits256).
//   • D-15  HKDF<SHA256>.expand the secret into TWO per-direction subkeys with distinct `info`
//           labels (daemon->app, app->ack) — each direction gets its own key domain.
//   • D-16  96-bit nonce = 4-byte per-direction/epoch PREFIX || 8-byte BIG-ENDIAN seq. The seq is the
//           monotonic ring/doorbell counter (D-12) — NO per-frame RNG. This is the NIST SP 800-38D
//           §8.2.1 deterministic-IV construction. The nonce is reconstructable from seq, so it is
//           NOT transmitted.
//
// Nonce-uniqueness invariant (the one HIGH-severity Phase-2 threat, T-02-03-01 — GCM nonce reuse is
// catastrophic): within a direction, distinct seq → distinct nonce (the 8-byte counter is injective
// over UInt64). Across directions, the (key, nonce) pair can never collide because BOTH the subkey
// (distinct HKDF info) AND the 4-byte prefix differ. A fresh random secret per launch (D-14) resets
// the entire (key, nonce) space on restart/exhaustion, so the monotonic counter cannot wrap into a
// reused pair within a session. CryptoTests proves both halves of this invariant.
//
// Fail-closed (Discretion D-58): open() lets CryptoKit's error propagate on ANY tamper — no `try?`
// swallow. The caller drops the frame / tears the session down.
//
// CortexIPCSession is Foundation-allowed (D-04/D-06); not policed by the hot-path gate. Types are
// `nonisolated` so the Plan 02-04 consumer can seal/open off the main actor.
import Foundation
import CryptoKit

/// The two encrypted directions of the Phase-2 ack-bounce (D-02/D-15). Each carries its own HKDF
/// `info` label (→ distinct subkey) and a distinct 4-byte nonce prefix (→ distinct nonce domain),
/// which together guarantee no cross-direction (key, nonce) collision.
public nonisolated enum Direction: Sendable, CaseIterable {
  /// Producer → consumer (the forward frame path).
  case daemonToApp
  /// Consumer → producer (the ack-bounce return path).
  case appToAck

  /// HKDF `info` label — domain separation between the two per-direction subkeys (D-15).
  public var infoLabel: String {
    switch self {
    case .daemonToApp: return "cortex.daemon->app.v1"
    case .appToAck: return "cortex.app->ack.v1"
    }
  }

  /// 4-byte epoch/direction nonce prefix (D-16). Distinct per direction so the high 4 bytes of the
  /// 12-byte nonce already separate the two directions' nonce spaces even before the subkey differs.
  /// `0xC0 0x01` = "cortex IPC" epoch tag; the last byte distinguishes the direction (0x01 / 0x02).
  public var noncePrefix: [UInt8] {
    switch self {
    case .daemonToApp: return [0xC0, 0x01, 0x00, 0x01]
    case .appToAck: return [0xC0, 0x01, 0x00, 0x02]
    }
  }
}

/// Errors raised by the deterministic-nonce construction (distinct from CryptoKit's own
/// authentication errors, which propagate unchanged from seal/open — fail-closed, D-58).
public nonisolated enum SessionCryptoError: Error, Equatable, Sendable {
  /// A constructed nonce was not exactly 12 bytes (should be impossible: 4-byte prefix + 8-byte seq).
  case invalidNonceLength(Int)
}

/// The per-session key material: the random 256-bit secret (D-14) HKDF-expanded into the two
/// per-direction subkeys (D-15). Construct once after the secret is delivered (the secret arrives over
/// the secure mach_msg channel in Plan 02-04, per the CF#1 fallback — NOT a shared Keychain group).
public nonisolated struct SessionKeys: Sendable {
  private let daemonToAppKey: SymmetricKey
  private let appToAckKey: SymmetricKey

  /// Generate a fresh random 256-bit session secret (D-14). One per daemon launch.
  public static func generateSecret() -> SymmetricKey {
    SymmetricKey(size: .bits256)
  }

  /// Derive both per-direction subkeys from `secret` via HKDF<SHA256>.expand with distinct `info`
  /// labels (D-15). The secret is already high-entropy (256 random bits), so HKDF-Expand alone is the
  /// correct RFC 5869 step (no salt/extract needed for a uniformly random PRK).
  public init(secret: SymmetricKey) {
    self.daemonToAppKey = SessionKeys.deriveSubkey(secret: secret, direction: .daemonToApp)
    self.appToAckKey = SessionKeys.deriveSubkey(secret: secret, direction: .appToAck)
  }

  private static func deriveSubkey(secret: SymmetricKey, direction: Direction) -> SymmetricKey {
    HKDF<SHA256>.expand(
      pseudoRandomKey: secret,
      info: Data(direction.infoLabel.utf8),
      outputByteCount: 32
    )
  }

  /// The AES-256 subkey for `direction`.
  public func subkey(for direction: Direction) -> SymmetricKey {
    switch direction {
    case .daemonToApp: return daemonToAppKey
    case .appToAck: return appToAckKey
    }
  }
}

public nonisolated enum SessionCrypto {

  /// Encode `seq` as 8 big-endian bytes (the nonce counter, D-16).
  public static func seqBigEndianBytes(_ seq: UInt64) -> [UInt8] {
    withUnsafeBytes(of: seq.bigEndian) { Array($0) }
  }

  /// Build the 96-bit deterministic nonce for `(direction, seq)` (D-16): 4-byte prefix || 8-byte
  /// big-endian seq = exactly 12 bytes (the size `AES.GCM.Nonce` requires). NO per-frame RNG.
  public static func nonce(direction: Direction, seq: UInt64) throws -> AES.GCM.Nonce {
    var bytes = direction.noncePrefix
    bytes.append(contentsOf: seqBigEndianBytes(seq))
    guard bytes.count == 12 else {
      throw SessionCryptoError.invalidNonceLength(bytes.count)
    }
    return try AES.GCM.Nonce(data: Data(bytes))
  }

  /// Seal `plaintext` for `direction` at sequence `seq`. Returns the ciphertext + 16-byte tag; the
  /// nonce is reconstructable from `seq` and is NOT returned/transmitted (D-16).
  public static func seal(
    _ plaintext: [UInt8],
    keys: SessionKeys,
    direction: Direction,
    seq: UInt64
  ) throws -> (ciphertext: [UInt8], tag: [UInt8]) {
    let box = try AES.GCM.seal(
      Data(plaintext),
      using: keys.subkey(for: direction),
      nonce: nonce(direction: direction, seq: seq)
    )
    return (Array(box.ciphertext), Array(box.tag))
  }

  /// Open `ciphertext`+`tag` for `direction` at sequence `seq`, rebuilding the nonce from `seq`. Lets
  /// CryptoKit's error propagate on ANY tamper (fail-closed, D-58) — caller drops the frame / tears down.
  public static func open(
    ciphertext: [UInt8],
    tag: [UInt8],
    keys: SessionKeys,
    direction: Direction,
    seq: UInt64
  ) throws -> [UInt8] {
    let box = try AES.GCM.SealedBox(
      nonce: nonce(direction: direction, seq: seq),
      ciphertext: Data(ciphertext),
      tag: Data(tag)
    )
    let opened = try AES.GCM.open(box, using: keys.subkey(for: direction))
    return Array(opened)
  }
}
