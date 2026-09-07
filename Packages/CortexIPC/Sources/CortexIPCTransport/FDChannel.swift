import CortexCoreC

// FDChannel — Foundation-free Swift wrapper over the CortexCoreC mach_msg + fileport FD-passing
// shim (Plan 02-02 Task 3, IPC-03). It moves the shm region fd cross-process via a COMPLEX mach_msg
// carrying ONE MACH_MSG_PORT_DESCRIPTOR (fileport) — the mandated Mach primitive, with no socket
// control-message rights-transfer path anywhere (the no-rights-transfer invariant, SC#2).
//
// Rendezvous (obtaining the `dest`/`rcv` mach_port_t) is NOT FDChannel's job: per the CF#3 verdict
// (02-SPIKES.md) the harness injects the rendezvous send right at spawn via
// posix_spawnattr_setspecialport_np (Plan 02-04 wires that). FDChannel only does the message dance.
//
// CF#5: pass ONLY the shm region fd to send(shmFD:) — never a kqueue/socket fd (fileport_makeport
// errors on those).
//
// Foundation-free: `import Darwin` + `import CortexCoreC` only.
import Darwin

/// Errors from the FD-passing message dance (Swift 6 typed throws). `code` carries the raw shim
/// return: for send, a positive mach_msg_return_t or a negative -errno (fileport failure); for
/// receive, a negative -(mach_msg_return_t) or -errno.
public enum FDChannelError: Error, Equatable {
  case send(Int32)
  case recv(Int32)
}

/// Stateless façade over `cortex_fdmsg_send` / `cortex_fdmsg_recv`. The shm fd rides as a fileport
/// in one port descriptor alongside the inline ring geometry, so the receiver can validate the
/// geometry (T-02-02-02) before mapping.
public enum FDChannel {
  /// Producer side: send `shmFD` (wrapped as a fileport) + the ring geometry to `dest` (a send
  /// right from the rendezvous harness). Throws `.send(code)` on failure.
  public static func send(shmFD: Int32,
                          geometry: ShmRingLayout,
                          to dest: mach_port_t) throws(FDChannelError)
  {
    // shm_name is implicit here (the production ring uses CORTEX_SHM_NAME). The geometry the
    // receiver needs to map is ring_bytes/slot_stride/slot_depth.
    let rc = CORTEX_SHM_NAME.withCString { namePtr in
      cortex_fdmsg_send(dest,
                        shmFD,
                        UInt64(geometry.ringBytes),
                        UInt64(geometry.slotStride),
                        UInt32(geometry.depth),
                        namePtr)
    }
    if rc != 0 { throw .send(rc) }
  }

  /// Consumer side: receive on `rcv` (a receive right); reconstruct the shm fd (CLOEXEC already
  /// set) and the ring geometry. Returns the fd plus a `ShmRingLayout` rebuilt from the received
  /// stride/depth. Throws `.recv(code)` on a Mach/fileport failure.
  ///
  /// The returned geometry is validated against the compile-time CORTEX_CHANNEL_COUNT expectation
  /// (defense-in-depth, T-02-02-02): a sender that lies about the stride/depth is rejected rather
  /// than used to map an attacker-chosen region.
  public static func receive(on rcv: mach_port_t) throws(FDChannelError) -> (fd: Int32, geometry: ShmRingLayout) {
    var ringBytes: UInt64 = 0
    var slotStride: UInt64 = 0
    var slotDepth: UInt32 = 0
    var nameBuf = [CChar](repeating: 0, count: 32)

    let fd = nameBuf.withUnsafeMutableBufferPointer { namePtr in
      cortex_fdmsg_recv(rcv, &ringBytes, &slotStride, &slotDepth, namePtr.baseAddress!)
    }
    if fd < 0 { throw .recv(fd) }

    // Rebuild + validate the geometry against the compile-time expectation. The consumer trusts
    // its OWN CORTEX_CHANNEL_COUNT-derived layout; a mismatching sender is rejected (the fd is
    // closed so we don't leak it).
    let expected = ShmRingLayout()
    let received = ShmRingLayout(channelCount: Int(CORTEX_CHANNEL_COUNT), depth: Int(slotDepth))
    if Int(slotStride) != expected.slotStride
      || Int(ringBytes) != received.ringBytes
      || received.slotStride != expected.slotStride
    {
      close(fd)
      throw .recv(-1)
    }
    return (fd, received)
  }
}
