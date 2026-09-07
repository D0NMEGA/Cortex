// Doorbell — Foundation-free socketpair + kqueue EVFILT_READ control-plane wake (Plan 02-02 Task 2,
// IPC-02). This is the IDLE/ARMING path, NOT the measured hot path: per Critical Finding #2 the
// sub-µs SC#1 number comes from busy-polling the ShmRing seq, while this doorbell lets the consumer
// SLEEP when no frames are flowing and wakes it with a tiny notification. It satisfies IPC-02's
// literal "kqueue+recvmsg socket pair" wording (D-01: the control plane carries only ~8 bytes).
//
// The notification is a single 8-byte UInt64 seq in NATIVE byte order (producer and consumer are
// the same host/arch — daemon and app on one M4 — so no endian conversion is needed; documented
// here so a future remote transport knows to add it). The frame itself NEVER travels here.
//
// recvmsg(2) is used (IPC-02's literal wording) with a single iovec and NO control buffer
// (msg_control = nil, msg_controllen = 0): there is deliberately no BSD socket control-message
// FD-passing path on this socket (the no-rights-transfer invariant, SC#2). FD passing is
// FDChannel's job via mach_msg + a port descriptor — see FDChannel.swift / cortex_fdmsg.c.
//
// CF#5 reminder: NEVER pass these socket fds (or the kqueue fd) via fileport_makeport — only the
// shm region fd is fileport-sendable; fileport_makeport errors on a socket/kqueue fd.
//
// Foundation-free: `import Darwin` only. NO mutex locks, NO cooperative-dispatch hops.
import Darwin

/// A connected pair of AF_UNIX stream fds. The producer writes the notification on `producerFD`;
/// the consumer arms its kqueue on `consumerFD` and reads the notification there.
public struct DoorbellPair: Sendable {
  public let producerFD: Int32
  public let consumerFD: Int32
}

/// The result of waiting on the doorbell.
public enum WakeResult: Sendable, Equatable {
  case woke(seq: UInt64) // a notification arrived; payload is the producer's seq
  case timeout // the wait deadline elapsed with no notification
  case peerClosed // the producer end closed (EV_EOF / recv returned 0) — fail-closed signal
}

/// Errors from doorbell setup (Swift 6 typed throws).
public enum DoorbellError: Error, Equatable {
  case socketpair(Int32) // socketpair() failed; payload = errno
  case sockopt(Int32) // fcntl/setsockopt hardening failed; payload = errno
  case kqueue(Int32) // kqueue() failed; payload = errno
  case kevent(Int32) // kevent() registration failed; payload = errno
}

/// The socketpair+kqueue doorbell. Owns the two socket fds and (after `arm`) a kqueue fd; `close`
/// releases them all. Construction/teardown is NOT on the hot path; `ring`/`wait` are the per-wake
/// operations (a single send / a single kevent + recvmsg).
public final class Doorbell {
  /// Producer end — the daemon writes the seq notification here.
  public private(set) var producerFD: Int32
  /// Consumer end — the app arms its kqueue on this fd and reads the notification.
  public private(set) var consumerFD: Int32
  /// kqueue fd (allocated by `arm`); -1 until armed.
  private var kq: Int32 = -1

  // MARK: - Construction

  /// Create a hardened socketpair: AF_UNIX/SOCK_STREAM, FD_CLOEXEC + SO_NOSIGPIPE on both ends.
  public init() throws(DoorbellError) {
    var fds: [Int32] = [-1, -1]
    let rc = socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
    if rc != 0 {
      throw .socketpair(errno)
    }

    producerFD = fds[0]
    consumerFD = fds[1]

    do {
      try Doorbell.harden(fds[0])
      try Doorbell.harden(fds[1])
    } catch {
      Darwin.close(fds[0])
      Darwin.close(fds[1])
      throw error
    }
  }

  /// Set FD_CLOEXEC (don't leak the doorbell across exec — only the shm fd crosses, via fileport)
  /// and SO_NOSIGPIPE (a dead peer must not kill the process; writes return EPIPE instead).
  private static func harden(_ fd: Int32) throws(DoorbellError) {
    let flags = fcntl(fd, F_GETFD)
    if flags < 0 {
      throw .sockopt(errno)
    }
    if fcntl(fd, F_SETFD, flags | FD_CLOEXEC) < 0 {
      throw .sockopt(errno)
    }

    var one: Int32 = 1
    if setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size)) != 0 {
      throw .sockopt(errno)
    }
  }

  deinit { close() }

  /// Release all fds (idempotent).
  public func close() {
    if kq >= 0 {
      Darwin.close(kq)
      kq = -1
    }
    closeProducer()
    closeConsumer()
  }

  /// Close only the producer end (used by tests to simulate a dead peer; idempotent).
  public func closeProducer() {
    if producerFD >= 0 {
      Darwin.close(producerFD)
      producerFD = -1
    }
  }

  /// Close only the consumer end (idempotent).
  public func closeConsumer() {
    if consumerFD >= 0 {
      Darwin.close(consumerFD)
      consumerFD = -1
    }
  }

  // MARK: - Producer

  /// Ring the doorbell: write the 8-byte seq notification (native order) on the producer end.
  /// Returns the send() result (>=0 bytes sent, or -1 with errno set — e.g. EPIPE on a dead peer,
  /// which thanks to SO_NOSIGPIPE does NOT signal the process). Tiny notification only (D-01).
  @discardableResult
  public func ring(seq: UInt64) -> Int {
    var s = seq
    return withUnsafeBytes(of: &s) { raw in
      send(producerFD, raw.baseAddress, raw.count, 0)
    }
  }

  // MARK: - Consumer

  /// Arm a kqueue with EVFILT_READ on the consumer fd (EV_ADD|EV_ENABLE). Stores the kq fd for
  /// subsequent `wait` calls.
  public func arm() throws(DoorbellError) {
    let q = kqueue()
    if q < 0 {
      throw .kqueue(errno)
    }

    var ev = kevent()
    ev.ident = UInt(UInt32(bitPattern: consumerFD))
    ev.filter = Int16(EVFILT_READ)
    ev.flags = UInt16(EV_ADD | EV_ENABLE)
    ev.fflags = 0
    ev.data = 0
    ev.udata = nil

    let rc = withUnsafePointer(to: &ev) { evp in
      kevent(q, evp, 1, nil, 0, nil)
    }
    if rc < 0 {
      let e = errno
      Darwin.close(q)
      throw .kevent(e)
    }
    kq = q
  }

  /// Block until a notification arrives, the deadline elapses, or the peer closes. On a read-ready
  /// wake, recvmsg the 8-byte seq (single iovec, NO control buffer — no rights transfer) and return it.
  /// `timeoutNanos == nil` blocks indefinitely.
  public func wait(timeoutNanos: UInt64?) -> WakeResult {
    precondition(kq >= 0, "Doorbell.wait called before arm()")

    var out = kevent()
    let n: Int32
    if let t = timeoutNanos {
      var ts = timespec(tv_sec: Int(t / 1_000_000_000),
                        tv_nsec: Int(t % 1_000_000_000))
      n = kevent(kq, nil, 0, &out, 1, &ts)
    } else {
      n = kevent(kq, nil, 0, &out, 1, nil)
    }

    if n < 0 {
      return .timeout
    } // interrupted/failed — treat as a non-wake (caller may retry)
    if n == 0 {
      return .timeout
    } // deadline elapsed, no event

    // EV_EOF means the producer end closed (fail-closed signal, T-02-02-05 path).
    if (out.flags & UInt16(EV_EOF)) != 0, out.data == 0 {
      return .peerClosed
    }

    // Read exactly the 8-byte seq via recvmsg with a single iovec and no control message.
    var seq: UInt64 = 0
    let got: Int = withUnsafeMutableBytes(of: &seq) { raw -> Int in
      var iov = iovec(iov_base: raw.baseAddress, iov_len: raw.count)
      return withUnsafeMutablePointer(to: &iov) { iovp -> Int in
        var msg = msghdr()
        msg.msg_name = nil
        msg.msg_namelen = 0
        msg.msg_iov = iovp
        msg.msg_iovlen = 1
        msg.msg_control = nil // explicitly NO control buffer => no rights-transfer path here (SC#2)
        msg.msg_controllen = 0
        msg.msg_flags = 0
        return recvmsg(consumerFD, &msg, 0)
      }
    }

    if got == 0 {
      return .peerClosed
    } // orderly shutdown
    if got < 0 {
      return .timeout
    } // EAGAIN/EINTR on a spurious wake — treat as non-wake
    return .woke(seq: seq)
  }
}
