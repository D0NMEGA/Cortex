@testable import CortexIPCTransport
import Darwin

// DoorbellTests — proves the socketpair + kqueue EVFILT_READ doorbell (Plan 02-02 Task 2, IPC-02).
//
// The doorbell is the CONTROL PLANE / idle-arming wake (D-01, Critical Finding #2): it carries
// ONLY a tiny 8-byte seq notification, never the frame (the frame rides ShmRing). The consumer
// arms kqueue EVFILT_READ on its socket end, blocks in `wait`, wakes, and recvmsg's the 8 bytes.
//
// Coverage (the four behaviors mandated by the plan):
//   1. producer writes 8-byte seq -> consumer's kqueue wakes and recvmsg reads exactly those 8 bytes
//   2. nothing written -> kevent with a short timeout returns 0 events (no spurious wake)
//   3. both socket fds have FD_CLOEXEC set
//   4. writing to a closed peer does NOT raise SIGPIPE (SO_NOSIGPIPE) — returns EPIPE, process lives
import Testing

@Suite("Doorbell")
struct DoorbellTests {
  /// 1. Wake + read: ring(seq) on the producer end, the armed consumer wakes and reads the seq.
  @Test
  func `kqueue EVFILT_READ wakes and recvmsg reads the 8-byte seq`() throws {
    let door = try Doorbell()
    defer { door.close() }
    try door.arm()

    let sent: UInt64 = 0xDEAD_BEEF_0000_0042
    door.ring(seq: sent)

    let result = door.wait(timeoutNanos: 500_000_000) // 500 ms — generous for a same-host wake
    switch result {
    case let .woke(seq):
      #expect(seq == sent, "the woken consumer reads the exact seq the producer rang")
    case .timeout:
      Issue.record("doorbell timed out instead of waking on a written seq")
    case .peerClosed:
      Issue.record("doorbell reported peerClosed unexpectedly")
    }
  }

  /// 2. No spurious wake: with nothing written, a short-timeout wait returns .timeout (0 events).
  @Test
  func `no spurious wake: empty doorbell times out with zero events`() throws {
    let door = try Doorbell()
    defer { door.close() }
    try door.arm()

    let result = door.wait(timeoutNanos: 20_000_000) // 20 ms
    #expect(result == .timeout, "an empty doorbell must not wake (no spurious EVFILT_READ)")
  }

  /// 3. FD_CLOEXEC set on BOTH socket fds (fcntl F_GETFD & FD_CLOEXEC != 0).
  @Test
  func `both socket fds have FD_CLOEXEC set`() throws {
    let door = try Doorbell()
    defer { door.close() }

    let pf = fcntl(door.producerFD, F_GETFD)
    let cf = fcntl(door.consumerFD, F_GETFD)
    #expect(pf >= 0 && (pf & FD_CLOEXEC) != 0, "producer fd has FD_CLOEXEC")
    #expect(cf >= 0 && (cf & FD_CLOEXEC) != 0, "consumer fd has FD_CLOEXEC")
  }

  /// 4. SO_NOSIGPIPE: closing the consumer end then writing from the producer returns EPIPE
  ///    instead of delivering SIGPIPE (which would kill the test process). Reaching the #expect
  ///    at all proves the process survived.
  @Test
  func `SO_NOSIGPIPE: write to a closed peer returns EPIPE, process survives`() throws {
    let door = try Doorbell()
    // Close the consumer end so the producer's write hits a dead peer.
    door.closeConsumer()

    let rc = door.ring(seq: 1) // returns the send() result
    // With SO_NOSIGPIPE the process is NOT signaled; write returns -1 with errno EPIPE
    // (occasionally the first byte is buffered then EPIPE on a subsequent write; ring once more).
    if rc >= 0 {
      let rc2 = door.ring(seq: 2)
      #expect(rc2 < 0 && (errno == EPIPE || errno == ECONNRESET),
              "second write to a closed peer fails with EPIPE/ECONNRESET, not SIGPIPE")
    } else {
      #expect(errno == EPIPE || errno == ECONNRESET,
              "write to a closed peer fails with EPIPE/ECONNRESET, not SIGPIPE")
    }

    door.closeProducer()
  }
}
