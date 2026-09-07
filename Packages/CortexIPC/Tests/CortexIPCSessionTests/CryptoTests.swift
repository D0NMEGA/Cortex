@testable import CortexIPCSession
import CryptoKit
import Foundation

// CryptoTests — IPC-05. Proves the AES-GCM + HKDF per-direction-subkey + deterministic-seq-nonce
// construction (D-15/D-16): round-trip, fail-closed tamper rejection, the nonce-uniqueness invariant
// (the HIGH-severity T-02-03-01 GCM-nonce-reuse defense), cross-direction (key,nonce) isolation, and
// nonce-from-seq reconstruction (the nonce is never transmitted).
import Testing

@Suite("SessionCrypto (IPC-05)")
struct CryptoTests {
  private static func makeKeys() -> SessionKeys {
    SessionKeys(secret: SessionKeys.generateSecret())
  }

  private static let plaintext: [UInt8] = Array("the quick brown fox — 0.5ms neural block".utf8)

  @Test
  func `seal then open with the same (subkey, seq) returns the identical plaintext`() throws {
    let keys = Self.makeKeys()
    let seq: UInt64 = 42
    let (ct, tag) = try SessionCrypto.seal(Self.plaintext, keys: keys, direction: .daemonToApp, seq: seq)
    let opened = try SessionCrypto.open(ciphertext: ct, tag: tag, keys: keys, direction: .daemonToApp, seq: seq)
    #expect(opened == Self.plaintext)
    // Ciphertext must NOT equal plaintext (it is actually encrypted).
    #expect(ct != Self.plaintext)
  }

  @Test
  func `flipping one ciphertext byte OR one tag byte makes open() throw (fail-closed integrity)`() throws {
    let keys = Self.makeKeys()
    let seq: UInt64 = 7
    let (ct, tag) = try SessionCrypto.seal(Self.plaintext, keys: keys, direction: .daemonToApp, seq: seq)

    // Flip one ciphertext byte.
    var badCt = ct
    badCt[0] ^= 0xFF
    #expect(throws: (any Error).self) {
      _ = try SessionCrypto.open(ciphertext: badCt, tag: tag, keys: keys, direction: .daemonToApp, seq: seq)
    }

    // Flip one tag byte.
    var badTag = tag
    badTag[badTag.count - 1] ^= 0x01
    #expect(throws: (any Error).self) {
      _ = try SessionCrypto.open(ciphertext: ct, tag: badTag, keys: keys, direction: .daemonToApp, seq: seq)
    }

    // Opening at the WRONG seq (wrong nonce) also fails — the nonce is authenticated.
    #expect(throws: (any Error).self) {
      _ = try SessionCrypto.open(ciphertext: ct, tag: tag, keys: keys, direction: .daemonToApp, seq: seq + 1)
    }
  }

  @Test
  func `nonce(direction, seq) is prefix||bigEndian(seq), exactly 12 bytes, and unique across seq`() throws {
    let direction = Direction.daemonToApp
    let prefix = direction.noncePrefix

    // Probe a spread of seq values incl. boundaries.
    let seqs: [UInt64] = [0, 1, 2, 255, 256, 65535, 65536, 0xFFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF]
    var seen = Set<[UInt8]>()
    for s in seqs {
      let n = try SessionCrypto.nonce(direction: direction, seq: s)
      let bytes = Array(n)
      // Exactly 12 bytes.
      #expect(bytes.count == 12)
      // prefix(4) || bigEndian(seq)(8).
      #expect(Array(bytes.prefix(4)) == prefix)
      #expect(Array(bytes.suffix(8)) == SessionCrypto.seqBigEndianBytes(s))
      // Distinct seq → distinct nonce.
      #expect(!seen.contains(bytes))
      seen.insert(bytes)
    }
    #expect(seen.count == seqs.count)
  }

  @Test
  func `the two directions never collide on (key, nonce): a frame sealed for A does not open with B`() throws {
    let keys = Self.makeKeys()
    let seq: UInt64 = 99

    // Same seq, different direction → different subkey AND different nonce prefix.
    #expect(Direction.daemonToApp.noncePrefix != Direction.appToAck.noncePrefix)
    let nA = try SessionCrypto.nonce(direction: .daemonToApp, seq: seq)
    let nB = try SessionCrypto.nonce(direction: .appToAck, seq: seq)
    #expect(Array(nA) != Array(nB)) // prefixes differ → nonces differ at the same seq

    // Seal for daemonToApp; opening with appToAck's key+nonce must fail closed.
    let (ct, tag) = try SessionCrypto.seal(Self.plaintext, keys: keys, direction: .daemonToApp, seq: seq)
    #expect(throws: (any Error).self) {
      _ = try SessionCrypto.open(ciphertext: ct, tag: tag, keys: keys, direction: .appToAck, seq: seq)
    }
    // And the correct direction still opens it.
    let opened = try SessionCrypto.open(ciphertext: ct, tag: tag, keys: keys, direction: .daemonToApp, seq: seq)
    #expect(opened == Self.plaintext)
  }

  @Test
  func `the nonce is reconstructable from seq alone — open succeeds without it being transmitted`() throws {
    let keys = Self.makeKeys()
    let seq: UInt64 = 0x0102_0304_0506_0708

    // Producer seals and transmits ONLY ciphertext + tag (no nonce).
    let (ct, tag) = try SessionCrypto.seal(Self.plaintext, keys: keys, direction: .daemonToApp, seq: seq)

    // Consumer rebuilds the nonce purely from the agreed (direction, seq) and opens.
    let opened = try SessionCrypto.open(ciphertext: ct, tag: tag, keys: keys, direction: .daemonToApp, seq: seq)
    #expect(opened == Self.plaintext)

    // Sanity: the rebuilt nonce equals the one used to seal (deterministic IV).
    let rebuilt = try SessionCrypto.nonce(direction: .daemonToApp, seq: seq)
    #expect(Array(rebuilt) == Direction.daemonToApp.noncePrefix + SessionCrypto.seqBigEndianBytes(seq))
  }

  @Test
  func `distinct secrets derive distinct subkeys (fresh-key-per-launch resets the nonce space, D-14)`() throws {
    let seq: UInt64 = 1
    let keys1 = SessionKeys(secret: SessionKeys.generateSecret())
    let keys2 = SessionKeys(secret: SessionKeys.generateSecret())

    // A frame sealed under launch-1's key must not open under launch-2's key at the same (dir, seq).
    let (ct, tag) = try SessionCrypto.seal(Self.plaintext, keys: keys1, direction: .daemonToApp, seq: seq)
    #expect(throws: (any Error).self) {
      _ = try SessionCrypto.open(ciphertext: ct, tag: tag, keys: keys2, direction: .daemonToApp, seq: seq)
    }
  }
}
