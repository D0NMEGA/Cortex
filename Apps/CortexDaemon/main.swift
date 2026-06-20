// CortexDaemon — Phase-2 producer entry point (Plan 02-04 Task 2). Replaces the Phase-1 shm-open
// verification stub (that Phase-1 helper type was deleted in Plan 02-02). The daemon is BOTH the
// producer (parent) AND, when posix_spawn'd with the "consume" arg by the harness, the consumer
// (child) — the same binary plays both roles in the D-07 two-process proof.
//
// HARNESS FORM (documented in 02-04-SUMMARY): a self-spawning argv-dispatched daemon.
//   • no arg / "produce" → parent: prepare the CF#3 rendezvous, posix_spawn this binary with
//     "consume", hand off the key (over the channel) + the shm fd, produce frames, await the
//     ack-bounce, reap the child (Harness.runParent, Plan 02-04 Task 3).
//   • "consume" → child: acquire the rendezvous reply right, receive the key + fd, map the ring,
//     busy-poll, open + decode + verify each frame, ack-bounce (HarnessConsumer.runChild, Task 3).
//
// The always-on CI correctness gate is the IN-PROCESS HarnessE2ETests (no spawn) — this binary's
// two-process flow is the local/Plan-02-05 proof. Diagnostics use NSLog and never log key bytes
// (T-02-04-06). The full daemon xcodebuild (this file + Producer.swift) is Plan 02-05's CI job; the
// SwiftPM package build does not compile this Xcode target.

import Foundation
import CortexCore
import CortexIPCTransport
import CortexIPCSession

let mode = CommandLine.arguments.dropFirst().first ?? "produce"
NSLog("Cortex daemon (Phase 2). mode=%@. App Group: %@.", mode, CortexCore.AppGroup.identifier)

do {
  switch mode {
  case "bench":
    // SC#1 benchmark mode (Plan 02-05): run the shm-polled round-trip benchmark (CF#2) and write the
    // histogram + raw-sample CSV. This is an IN-PROCESS two-pthread measurement (no posix_spawn needed
    // — the timed path is the ring busy-poll + ack-bounce, NOT the rendezvous/doorbell). Optional args:
    //   bench [frames] [warmup] [histogram-output-path]
    // Defaults: 200k frames, 1k warm-up, ./sc1-histogram.txt (+ sc1-histogram.csv alongside). The
    // numbers are meaningful ONLY on M4 (D-18); CI may smoke this for completion but never asserts it.
    let args = Array(CommandLine.arguments.dropFirst())
    let frames = (args.count > 1 ? Int(args[1]) : nil) ?? 200_000
    let warmup = (args.count > 2 ? Int(args[2]) : nil) ?? 1_000
    let outPath = args.count > 3 ? args[3] : "sc1-histogram.txt"
    NSLog("Cortex daemon bench: frames=%d warmup=%d out=%@", frames, warmup, outPath)
    let result = Benchmark.runRoundTrip(frames: frames, warmup: warmup)
    Benchmark.printResult(result)
    Benchmark.writeHistogram(result, to: outPath)
    exit(0)
  case "consume":
    // Child path: acquire the rendezvous right, receive key + fd, run the consumer loop, ack-bounce.
    let result = try HarnessConsumer.runChild(frameCount: 1000)
    NSLog("Cortex daemon consumer done: verified=%d acked=%@",
          result.framesVerified, result.allAcked ? "true" : "false")
    exit(result.allAcked && result.framesVerified == result.framesSent ? 0 : 1)
  default:
    // Parent path: prepare rendezvous, posix_spawn self with "consume", hand off, produce, reap child.
    let status = try Harness.runParent(frameCount: 1000)
    NSLog("Cortex daemon producer done: child exit status=%d", status)
    exit(status)
  }
} catch {
  NSLog("Cortex daemon (mode=%@) failed: %@", mode, String(describing: error))
  exit(70) // EX_SOFTWARE
}
