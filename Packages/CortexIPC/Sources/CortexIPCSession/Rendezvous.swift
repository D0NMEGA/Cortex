// Rendezvous.swift — thin Swift wrapper over the CortexCoreC CF#3 rendezvous helper (Plan 02-04
// Task 1, IPC-03). CortexIPCSession is Foundation-allowed orchestration (D-04/D-06), NOT the policed
// hot-path transport dir, so this file may use Foundation/CryptoKit-adjacent APIs freely.
//
// MECHANISM & DIRECTIONALITY (the proven spike + a one-message reply-port flip — see
// cortex_rendezvous.h and 02-SPIKES.md §CF#3 PASS):
//   • The parent (producer/daemon) injects a SEND right into the posix_spawn'd child at
//     TASK_BOOTSTRAP_PORT via posix_spawnattr_setspecialport_np — the mechanism the spike proved
//     3/3 on this M4. posix_spawnattr_setspecialport_np transfers exactly a SEND right (a direct
//     receive-right injection fails with MACH_RCV_INVALID_NAME, verified), so the spike direction
//     (child=send / parent=receive on the bootstrap port) is fixed.
//   • Because FDChannel.send(to:) needs a SEND right and FDChannel.receive(on:) needs a RECEIVE
//     right, and the shm fd must flow producer(parent) -> consumer(child), the child advertises its
//     OWN reply port: childAcquire() sends the parent one bootstrap handshake carrying the reply
//     port's send right, and RETURNS the reply RECEIVE right for FDChannel.receive. The parent's
//     parentAwaitReply() returns the matching SEND right for FDChannel.send(to:).
//
// FINAL DIRECTIONALITY for Tasks 2/3:
//   PRODUCER (parent): parentPrepare(&attr) -> bootstrapRecv ; posix_spawn ; let dest =
//     parentAwaitReply(bootstrapRecv) ; FDChannel.send(shmFD:geometry:to: dest).
//   CONSUMER (child):  let rcv = childAcquire() ; FDChannel.receive(on: rcv).
//
// Marked `nonisolated` so the off-main-actor consumer (the Foundation-free transport regime) can
// call it without a MainActor hop (CortexIPCSession sets .defaultIsolation(MainActor.self)).
import CortexCoreC

/// Errors mapping the C helper's `kern_return_t`/rc failures (Swift 6 typed throws). The payload is
/// the raw return code so a caller can log/inspect the exact Mach failure.
public nonisolated enum RendezvousError: Error, Equatable, Sendable {
  /// `cortex_rendezvous_parent_prepare` failed (allocate / insert-right / spawnattr injection).
  case parentPrepare(Int32)
  /// `cortex_rendezvous_parent_await_reply` failed (receive of the child's bootstrap handshake).
  case parentAwaitReply(Int32)
  /// `cortex_rendezvous_child_acquire` failed (special-port read / reply-port alloc / handshake send).
  case child(Int32)
}

/// The CF#3 rendezvous: hands a Mach send/receive right pair between a parent and its posix_spawn'd
/// child with no launchd plist and no socket control-message path. Stateless façade over the C shim.
public nonisolated enum Rendezvous {
  /// Default bound (ms) the parent waits for the child's bootstrap handshake before failing rather
  /// than blocking forever (T-02-04-05 — a dead/never-spawned child must not wedge the parent).
  public static let defaultReplyTimeoutMs: UInt32 = 10000

  /// Parent step 1 (before `posix_spawn`): arm `attr` so the child gets the rendezvous SEND right at
  /// `TASK_BOOTSTRAP_PORT`, and return the bootstrap RECEIVE right the parent holds. Pass the spawn
  /// the same `attr`, then call `parentAwaitReply(_:)` with the returned right.
  public static func parentPrepare(_ attr: inout posix_spawnattr_t) throws(RendezvousError) -> mach_port_t {
    var out = mach_port_t(MACH_PORT_NULL)
    // The C param `posix_spawnattr_t *attr` imports as `UnsafeMutablePointer<posix_spawnattr_t?>`
    // (posix_spawnattr_t is an opaque pointer typedef → Optional on import). Bridge `inout attr`
    // through an Optional local, then copy any mutation back so the caller's attr reflects the
    // injected special port before it posix_spawns with the same attr.
    var optAttr: posix_spawnattr_t? = attr
    let kr = cortex_rendezvous_parent_prepare(&optAttr, &out)
    if let mutated = optAttr { attr = mutated }
    if kr != KERN_SUCCESS {
      throw .parentPrepare(kr)
    }
    return out
  }

  /// Parent step 2 (after `posix_spawn`): block (bounded by `timeoutMs`; 0 == forever) until the
  /// child sends its bootstrap handshake, then return the child's reply SEND right — the `dest` for
  /// `FDChannel.send(shmFD:geometry:to:)`. Consumes (deallocates) `bootstrapRecv`.
  public static func parentAwaitReply(_ bootstrapRecv: mach_port_t,
                                      timeoutMs: UInt32 = Rendezvous.defaultReplyTimeoutMs)
    throws(RendezvousError) -> mach_port_t
  {
    var out = mach_port_t(MACH_PORT_NULL)
    let kr = cortex_rendezvous_parent_await_reply(bootstrapRecv, timeoutMs, &out)
    if kr != KERN_SUCCESS {
      throw .parentAwaitReply(kr)
    }
    return out
  }

  /// Child side: read the injected bootstrap SEND right, advertise a reply port to the parent, and
  /// return the reply RECEIVE right — the `rcv` for `FDChannel.receive(on:)`.
  public static func childAcquire() throws(RendezvousError) -> mach_port_t {
    var out = mach_port_t(MACH_PORT_NULL)
    let kr = cortex_rendezvous_child_acquire(&out)
    if kr != KERN_SUCCESS {
      throw .child(kr)
    }
    return out
  }
}
