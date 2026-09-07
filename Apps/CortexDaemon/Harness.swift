// Harness.swift — the PARENT orchestrator of the D-07 two-process proof (Plan 02-04 Task 3). Lives in
// the Apps/CortexDaemon target because it drives `Producer` (also in this target) and posix_spawns
// the daemon binary itself as the consumer child. The CONSUMER half (HarnessConsumer) lives in
// CortexIPCSession so the always-on in-process correctness test can reuse it without the Apps target.
//
// FLOW (CF#3 rendezvous → key-over-channel → fd-over-channel → encrypted ring frames → ack-bounce):
//   1. Rendezvous.parentPrepare(&attr): allocate the bootstrap port, arm the spawnattr so the child
//      gets the injected send right at TASK_BOOTSTRAP_PORT.
//   2. posix_spawn THIS binary with arg "consume" (the child runs HarnessConsumer.runChild).
//   3. Rendezvous.parentAwaitReply: receive the child's reply-port send right (`dest`).
//   4. Producer().handoff(to: dest): send the session key over the channel (CF#1 fallback) then the
//      shm fd via FDChannel (SC#2). Producer().produce(frameCount:): encrypt+write frames, ring the
//      doorbell, busy-poll the D-02 ack-bounce per frame (cross-process lock-step).
//   5. waitpid the child; return its exit status (0 == it verified decoded==sent for every frame).
//
// This binary's two-process flow is the LOCAL / Plan-02-05 proof; CI's always-on correctness gate is
// the in-process HarnessE2ETests (no spawn). Foundation allowed (Apps target).
import CortexCore
import CortexIPCSession
import CortexIPCTransport
import Foundation

/// Errors specific to the parent orchestration (spawn / reap). Rendezvous + producer failures
/// propagate from their own typed-throws layers.
public enum HarnessError: Error {
  case spawnFailed(Int32)
  case waitFailed(Int32)
}

/// The parent orchestrator of the two-process proof harness.
public enum Harness {
  /// Run the full two-process round trip: prepare the rendezvous, posix_spawn this binary as the
  /// consumer child, hand off the key + fd, produce `frameCount` frames with the ack-bounce, and reap
  /// the child. Returns the child's exit status (0 == decoded == sent for every frame + all acked).
  public static func runParent(frameCount: Int) throws -> Int32 {
    let selfPath = CommandLine.arguments[0]

    // posix_spawnattr_t is an opaque pointer typedef → imported as Optional; init via the C call,
    // then bridge through a non-optional for parentPrepare and copy the mutation back before spawn.
    var attrOpt: posix_spawnattr_t?
    posix_spawnattr_init(&attrOpt)
    defer { posix_spawnattr_destroy(&attrOpt) }

    // 1. Arm the spawnattr with the injected rendezvous send right; hold the bootstrap receive right.
    guard var attr = attrOpt else { throw HarnessError.spawnFailed(-1) }
    let bootstrapRecv = try Rendezvous.parentPrepare(&attr)
    attrOpt = attr // carry the injected special-port mutation back to the optional the spawn uses

    // 2. posix_spawn this binary with "consume". argv must be NULL-terminated C strings.
    var pid: pid_t = 0
    let spawnRC: Int32 = selfPath.withCString { pathPtr -> Int32 in
      let consumeArg = strdup("consume")
      defer { free(consumeArg) }
      var argv: [UnsafeMutablePointer<CChar>?] = [strdup(pathPtr), consumeArg, nil]
      defer { free(argv[0]) }
      return posix_spawn(&pid, pathPtr, nil, &attrOpt, &argv, environ)
    }
    if spawnRC != 0 {
      throw HarnessError.spawnFailed(spawnRC)
    }

    // 3. Receive the child's reply-port send right (`dest` for FDChannel.send / SessionKeyChannel.send).
    let dest = try Rendezvous.parentAwaitReply(bootstrapRecv)

    // 4. Hand off (key over channel, then fd) and produce frames with the D-02 ack-bounce.
    let producer = try Producer()
    try producer.handoff(to: dest)
    let acked = try producer.produce(frameCount: frameCount)
    NSLog("Cortex harness parent: produced+acked %d/%d frames", acked, frameCount)

    // 5. Reap the child; return its exit status.
    var status: Int32 = 0
    while true {
      let w = waitpid(pid, &status, 0)
      if w == pid {
        break
      }
      if w < 0, errno == EINTR {
        continue
      }
      throw HarnessError.waitFailed(errno)
    }
    // Extract the child's exit code from the wait status (WEXITSTATUS).
    return (status & 0x7F) == 0 ? ((status >> 8) & 0xFF) : status
  }
}
