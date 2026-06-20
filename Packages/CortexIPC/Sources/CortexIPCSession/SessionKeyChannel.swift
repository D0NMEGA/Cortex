// SessionKeyChannel.swift — CF#1-FALLBACK key delivery over the secure mach_msg channel (Plan 02-04).
//
// CF#1 = FAIL (02-SPIKES.md / 02-03-SUMMARY): cross-process Keychain access-group sharing is
// un-backable under the free team (AMFI SIGKILL / errSecMissingEntitlement). So the consumer does
// NOT load the secret from a shared Keychain group. Instead the producer delivers the 32-byte
// session secret to the consumer OVER THE SAME rendezvous channel that carries the shm fd — as a
// SECOND mach_msg sent BEFORE the fd message (the directive's documented choice: "send it as a
// second mach_msg before the first frame"). The producer still STORES the secret single-process in
// the data-protection Keychain (SC#3, SessionKeychain.store); only the cross-process DELIVERY is
// over the channel. Access-group sharing returns in Phase 8 (enrollment), removing this path.
//
// SECURITY (threat T-02-04-03, ASVS V6.2): the mach_msg channel is a kernel-mediated capability only
// the parent and the spawned child hold (the rendezvous send right). The secret never touches disk
// in transit and is never logged (T-02-04-06). This is a bounded, inline, fixed-size payload — no
// port descriptor, no fd, no SCM_RIGHTS. The bytes carry no length field on the wire; both sides
// agree on the fixed 32-byte (256-bit, D-14) secret size at compile time.
//
// Foundation-allowed (CortexIPCSession, D-04/D-06). `nonisolated` so the off-main-actor consumer can
// call it. Uses raw mach_msg directly (the same primitive cortex_fdmsg.c uses) — kept in Swift here
// because it carries only inline bytes (no fileport), so no C shim is needed.
import Foundation
import CryptoKit
import Darwin
import CortexCoreC

/// Errors from the inline-secret mach_msg transfer (Swift 6 typed throws).
public nonisolated enum SessionKeyChannelError: Error, Equatable, Sendable {
  /// `mach_msg(MACH_SEND_MSG)` returned a nonzero mach_msg_return_t.
  case send(Int32)
  /// `mach_msg(MACH_RCV_MSG)` returned a nonzero mach_msg_return_t.
  case receive(Int32)
  /// The received secret was not the expected fixed size.
  case unexpectedLength(Int)
}

/// Delivers the 256-bit session secret over the rendezvous mach_msg channel (CF#1 fallback). Stateless.
public nonisolated enum SessionKeyChannel {

  /// The fixed wire size of the session secret: 256 bits = 32 bytes (D-14). Both sides agree at
  /// compile time; the message carries no length field.
  public static let secretByteCount = 32

  /// A small marker id distinguishing the key handshake from the fd message ('CKEY').
  static let messageID: mach_msg_id_t = 0x434B4559

  /// An inline-bytes message: a header + a fixed 32-byte secret region. NOT complex (no descriptors).
  private struct KeyMsg {
    var header = mach_msg_header_t()
    var secret = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                  UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                  UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                  UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))
  }

  /// Receive buffer = the message plus its trailer.
  private struct KeyRcv {
    var msg = KeyMsg()
    var trailer = mach_msg_trailer_t()
  }

  /// Producer side: send `secret` to `dest` (the rendezvous send right) as an inline mach_msg.
  /// Sent BEFORE the fd message so the consumer has the key before any frame arrives.
  public static func send(secret: SymmetricKey, to dest: mach_port_t) throws(SessionKeyChannelError) {
    let bytes = secret.withUnsafeBytes { Array($0) }
    // D-14 fixes the secret at 256 bits; guard defensively (a non-32-byte key is a programming error).
    guard bytes.count == secretByteCount else {
      // Reuse unexpectedLength to surface the misuse without logging the bytes.
      throw .unexpectedLength(bytes.count)
    }

    var msg = KeyMsg()
    // MACH_MSGH_BITS(remote, local) = (remote) | ((local) << 8); here local = 0 (no reply port).
    // COPY_SEND on the remote port: we copy the rendezvous send right handed to us. NOT complex
    // (inline bytes only, no descriptors) — so no MACH_MSGH_BITS_COMPLEX.
    msg.header.msgh_bits = mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND)
    msg.header.msgh_remote_port = dest
    msg.header.msgh_local_port = mach_port_t(MACH_PORT_NULL)
    msg.header.msgh_size = mach_msg_size_t(MemoryLayout<KeyMsg>.size)
    msg.header.msgh_id = messageID

    // Copy the 32 secret bytes into the fixed inline region.
    withUnsafeMutableBytes(of: &msg.secret) { dst in
      bytes.withUnsafeBytes { src in
        dst.copyMemory(from: src)
      }
    }

    let kr = withUnsafeMutablePointer(to: &msg.header) { hdr in
      mach_msg(hdr,
               MACH_SEND_MSG,
               mach_msg_size_t(MemoryLayout<KeyMsg>.size),
               0,
               mach_port_t(MACH_PORT_NULL),
               MACH_MSG_TIMEOUT_NONE,
               mach_port_t(MACH_PORT_NULL))
    }
    if kr != MACH_MSG_SUCCESS {
      throw .send(kr)
    }
  }

  /// Consumer side: receive the 32-byte secret on `rcv` (the rendezvous receive right). Returns the
  /// reconstructed `SymmetricKey`. Throws on a Mach failure or an unexpected size.
  public static func receive(on rcv: mach_port_t) throws(SessionKeyChannelError) -> SymmetricKey {
    var buf = KeyRcv()
    let kr = withUnsafeMutablePointer(to: &buf.msg.header) { hdr in
      mach_msg(hdr,
               MACH_RCV_MSG,
               0,
               mach_msg_size_t(MemoryLayout<KeyRcv>.size),
               rcv,
               MACH_MSG_TIMEOUT_NONE,
               mach_port_t(MACH_PORT_NULL))
    }
    if kr != MACH_MSG_SUCCESS {
      throw .receive(kr)
    }

    let bytes: [UInt8] = withUnsafeBytes(of: buf.msg.secret) { Array($0) }
    guard bytes.count == secretByteCount else {
      throw .unexpectedLength(bytes.count)
    }
    return SymmetricKey(data: bytes)
  }
}
