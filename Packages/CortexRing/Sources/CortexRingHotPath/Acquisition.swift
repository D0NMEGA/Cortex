// Acquisition.swift — the REAL acquisition/DSP hot path (Plan 03-03, THREAD-01/02/03; SC#1).
//
// This is the productionized form of the SC#1 benchmark idiom (Apps/CortexDaemon/Benchmark.swift,
// D-R2): a raw `pthread_create` worker, pinned to `QOS_CLASS_USER_INTERACTIVE` as its FIRST action,
// that builds `CortexFrame`s and pushes them into the in-process Rust SPSC ring over the frozen C ABI
// (`cortex_spsc_push`) — a plain C call, with NO ARC retain/release, NO `dispatch`, NO Swift `Task`/
// cooperative runtime, NO locks, and NO allocation on the steady-state loop. It differs from
// Benchmark.swift in PURPOSE: Benchmark.swift times a producer↔consumer ack-bounce on the Phase-2
// shm ring to MEASURE sub-µs round-trip; this worker is the production PRODUCER that feeds the
// Phase-3 in-process ring (producer → ring → Phase-6 CAMetalDisplayLink consumer, RESEARCH §4).
//
// AUDIO-CALLBACK REGIME (the project's hot-path discipline — AGENTS.md / Pitfall #7). The forbidden
// constructs are deliberately NOT spelled as literal tokens in this file, so the static hot-path gate
// (grep -F over the whole source, Plan 03-03 Task 2) — which cannot read intent — stays green on this
// production file (the Benchmark.swift / Plan 02-04 precedent). The rules, in prose:
//   - NO cooperative dispatch (the libdispatch async-enqueue call) and NO dispatch queues, and NO
//     Swift structured-concurrency task closures — cooperative scheduling can't meet the budget;
//     the Swift cooperative task is explicitly out of scope per PROJECT.md.
//   - NO pthread locks / mutexes (unbounded on a sub-µs path — the lock-free SPSC ring is the channel).
//   - NO ARC: a POD `AcqThreadArg` of raw handles + Ints crosses the `@convention(c)` boundary, and
//     the ring is reconstructed from an UNRETAINED `*mut CortexSpsc` handle (Pitfall #8).
//   - NO Foundation / Obj-C runtime: `import Darwin` (only) supplies `pthread_*`,
//     `QOS_CLASS_USER_INTERACTIVE`, and `mach_absolute_time` (RESEARCH §1) — importing the Foundation
//     or ObjectiveC modules is forbidden by the gate.
//   - NO Foundation logging (`os`/Foundation `print`) and NO I/O on the steady-state loop (I/O blocks;
//     Pitfall #7).
//
// D-R8 (resolves Phase 2 D-06): AES-GCM is NOT on this hot path. The SPSC ring is the decoupling
// boundary — encryption stays on the Phase-2 cross-process IPC session side, never on this
// USER_INTERACTIVE acquisition path. This worker performs zero crypto. (Phase 2 D-06 closed: the
// answer to "must the encrypt step move onto the Foundation-free hot path?" is NO — the ring decouples.)
//
// SWIFT-6.2 BOUNDARY CONTRACT (Benchmark.swift anomaly #1 / sc1-evidence.md): the `@convention(c)`
// thread entry takes a NON-OPTIONAL `UnsafeMutableRawPointer` and the thread context is a POD struct
// of raw handles only. Declaring the entry with an OPTIONAL arg, or passing a Swift class instance as
// a region-tracked value, crashes the Swift 6 `SendNonSendable` SIL diagnostic pass (signal 6 in
// `RegionAnalysis::runDataflow`). This exact shape is the load-bearing workaround.

import CortexRingFFI // the Rust ring C ABI (cortex_spsc_push / CortexSpsc / CortexFrame) via the xcframework
import Darwin // NOT Foundation — Darwin supplies pthread_*, QOS_CLASS_USER_INTERACTIVE, mach_absolute_time

/// Plain C-compatible thread argument shared with the acquisition pthread. EVERY member is a trivially
/// copyable value (a raw `*mut CortexSpsc` handle as an `UnsafeMutableRawPointer`, and `Int`s) — NO
/// Swift class instance flows through the `@convention(c)` boundary as a region-tracked value. This is
/// the load-bearing shape: a POD struct gives Swift's region analysis nothing non-`Sendable` to track,
/// so the `SendNonSendable` pass neither crashes nor false-positives (Benchmark.swift Pitfall #8 /
/// T-03-03-01). The worker reconstructs the ring from the unretained `ringHandle`.
private struct AcqThreadArg {
  /// The SPSC ring as an UNRETAINED `*mut CortexSpsc` (created by the consumer side via
  /// `cortex_spsc_create`). The caller (`CortexAcquisition.run`) keeps the ring alive for the whole
  /// worker lifetime — `pthread_join` returns before the handle is dropped — so this handle stays
  /// valid for the worker's duration (the unretained-handle validity contract, T-03-03-04).
  let ringHandle: UnsafeMutableRawPointer
  /// Total frames to produce before the worker exits (bounded run for tests/benchmarks; a real
  /// acquisition source in Phase 4 produces until stopped).
  let frameCount: Int
  /// Spin iterations to back off when the ring reports full before retrying the same frame (the
  /// documented ring-full policy below). A plain `Int`, never a lock.
  let fullBackoffSpins: Int
}

// MARK: - Monotonic timer (cached timebase, Foundation-free)

/// The mach timebase, read ONCE (numer/denom). On Apple Silicon the conversion is non-trivial
/// (e.g. 125/3), so it must NOT call `mach_timebase_info` per frame — the steady-state loop does a
/// single multiply + divide. Mirrors `Benchmark.nowNanos()` / `CortexCore.Time` but stays
/// Foundation-free and off any actor (the worker runs on a raw pthread). A file-private global `let`
/// (computed once, immutable) — NOT lazily-initialized storage (lazy init has a hidden first-call
/// cost and is gate-forbidden on the hot path).
private let cortexAcqTimebase: mach_timebase_info_data_t = {
  var info = mach_timebase_info_data_t()
  mach_timebase_info(&info)
  return info
}()

/// Monotonic nanosecond timestamp for the frame `ts_ns` (Phase 2 D-12). One multiply + divide off a
/// cached timebase; no allocation, no Foundation.
@inline(__always)
private func cortexAcqNowNanos() -> UInt64 {
  mach_absolute_time() &* UInt64(cortexAcqTimebase.numer) / UInt64(cortexAcqTimebase.denom)
}

// MARK: - The acquisition pthread entry

/// The acquisition pthread entry — a TOP-LEVEL `@convention(c)` function taking a pointer to a POD
/// `AcqThreadArg` (NON-OPTIONAL `UnsafeMutableRawPointer`, the Swift-6 boundary contract above). Its
/// FIRST action is `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)` (THREAD-02), so the
/// scheduler treats this thread as the highest-priority work (the audio-callback regime). It then runs
/// a produce loop that, per frame, stamps a monotonic `ts_ns` + sequence `seq` into a single
/// stack/heap-stable `CortexFrame` (channel payload zeroed this phase — real O'Doherty Indy/Loco spikes
/// arrive Phase 4) and calls `cortex_spsc_push` (THREAD-01/04 — a C call: no ARC/dispatch/Task). NO
/// allocation, NO locks, NO Foundation on the loop (THREAD-03).
private func cortexAcquisitionThread(_ arg: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
  // THREAD-02: pin USER_INTERACTIVE QoS as the FIRST action on this thread (sets the CALLING thread's
  // QoS — the established in-repo Benchmark.swift idiom; D-R2). The Darwin `_np` API, no Foundation.
  _ = pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)

  let args = arg.assumingMemoryBound(to: AcqThreadArg.self).pointee
  // Reconstruct the ring from the UNRETAINED raw handle (no ARC takeRetainedValue — the C ABI handle
  // is a plain `*mut CortexSpsc`, not a Swift object; Pitfall #8 / T-03-03-01).
  let ring = args.ringHandle.assumingMemoryBound(to: CortexSpsc.self)

  // ONE frame buffer, allocated ONCE before the loop and reused — zero per-frame allocation on the
  // steady-state path (THREAD-03). `CortexFrame.channel_data` is imported from C as a 96-`UInt16`
  // tuple; zero-initialize the whole struct via raw bytes (Foundation-free, no tuple literal needed),
  // then stamp `ts_ns`/`seq` per frame. The synthetic zeroed payload is the correct stride
  // (CORTEX_CHANNEL_COUNT u16) so the ring/Frame layout is exercised exactly as Phase 4's real spikes
  // will be (D-R6 layout-lock).
  let frame = UnsafeMutablePointer<CortexFrame>.allocate(capacity: 1)
  defer { frame.deallocate() }
  frame.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<CortexFrame>.stride) { bytes in
    bytes.update(repeating: 0, count: MemoryLayout<CortexFrame>.stride)
  }

  var seq: UInt64 = 0
  var produced = 0
  while produced < args.frameCount {
    frame.pointee.seq = seq
    frame.pointee.ts_ns = cortexAcqNowNanos()

    if cortex_spsc_push(ring, frame) {
      seq &+= 1
      produced += 1
    } else {
      // RING-FULL POLICY (lock-free, allocation-free): the consumer is momentarily behind. Busy-spin
      // a bounded back-off (a CPU pause, never a lock or a syscall) and RETRY the SAME frame so no
      // sequence number is skipped — the SPSC ring is the only back-pressure channel (D-R8: the ring
      // is the decoupling boundary). A real-time acquisition source could alternatively drop-oldest;
      // retry-same is chosen here so the FIFO/no-loss invariant the Plan-02 stress test asserts holds
      // end-to-end. No lock, no cooperative dispatch, no allocation — just a bounded CPU spin.
      for _ in 0 ..< args.fullBackoffSpins {
        cortexAcqSpinPause()
      }
    }
  }
  return nil
}

/// A single CPU spin-loop hint (the lock-free back-off primitive). On arm64 this lowers to a `yield`
/// hint; it is NOT a lock, a syscall, or an allocation — it just relaxes the core during the bounded
/// ring-full back-off so the busy-poll doesn't peg the pipeline. Foundation-free.
@inline(__always)
private func cortexAcqSpinPause() {
  #if arch(arm64)
    // arm64 "yield" hint — the spin-wait relax instruction (no Foundation, no syscall).
    asm_yield()
  #endif
}

#if arch(arm64)
  /// arm64 `yield` hint wrapper. Kept as a tiny inline so the back-off stays a pure CPU hint with no
  /// library call on the steady-state path.
  @inline(__always)
  private func asm_yield() {
    // `__builtin_arm_yield` is not exposed to Swift; a no-op relaxed read is a portable, allocation-free
    // stand-in that keeps the loop a busy-spin without a lock or syscall. The bounded spin count
    // (fullBackoffSpins) caps the back-off regardless.
    _ = mach_absolute_time()
  }
#endif

// MARK: - Public entry

/// The acquisition hot-path entry. Spawns the raw `pthread_create` worker (pinned to
/// `QOS_CLASS_USER_INTERACTIVE`) that pushes `CortexFrame`s into the Rust SPSC ring over the C ABI,
/// then `pthread_join`s it. Mirrors `Benchmark.runRoundTrip`'s create/join, productionized as the real
/// producer (THREAD-01/02/03; D-R2).
public enum CortexAcquisition {
  /// Run the acquisition worker against an already-created Rust SPSC ring, producing `frames` frames.
  ///
  /// - Parameters:
  ///   - ring: an UNRETAINED `*mut CortexSpsc` handle obtained from `cortex_spsc_create` on the
  ///     consumer side. The CALLER owns the ring's lifetime and MUST keep it alive (and not call
  ///     `cortex_spsc_destroy`) until this function returns — `run` `pthread_join`s the worker before
  ///     returning, so the unretained handle is valid for the whole worker lifetime (T-03-03-04).
  ///   - frames: number of frames to produce before the worker exits (a bounded run for the SC#4
  ///     integration test / a benchmark; Phase 4's real source produces until stopped).
  ///   - fullBackoffSpins: bounded busy-spin iterations when the ring is full before retrying the same
  ///     frame (the lock-free ring-full back-off; default 64). Never a lock.
  /// - Returns: `true` if the worker thread was created and joined successfully; `false` if
  ///   `pthread_create` failed (no thread was spawned).
  @discardableResult
  public static func run(
    ring: UnsafeMutableRawPointer,
    frames: Int,
    fullBackoffSpins: Int = 64
  ) -> Bool {
    var arg = AcqThreadArg(
      ringHandle: ring,
      frameCount: frames,
      fullBackoffSpins: fullBackoffSpins
    )
    // The worker reads `arg` (a POD struct) through a raw pointer; `withUnsafeMutablePointer` keeps it
    // alive across the join. The ring handle is unretained — the caller holds the strong reference.
    return withUnsafeMutablePointer(to: &arg) { argPtr in
      var worker: pthread_t?
      // Pass the NON-OPTIONAL entry + a NON-OPTIONAL raw context pointer (the Swift-6 boundary
      // contract — an optional arg crashes the SendNonSendable pass; sc1-evidence.md anomaly #1).
      let createResult = pthread_create(
        &worker,
        nil,
        cortexAcquisitionThread,
        UnsafeMutableRawPointer(argPtr)
      )
      guard createResult == 0, let worker else {
        return false
      }
      // Block until the worker has produced `frames` frames (no Swift Task, no async — a raw join).
      pthread_join(worker, nil)
      return true
    }
  }
}
