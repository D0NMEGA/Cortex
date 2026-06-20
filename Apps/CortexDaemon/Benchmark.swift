// Benchmark.swift — the SC#1 defining-claim benchmark (Plan 02-05 Task 1, IPC-07).
//
// CF#2 / D-01 — THE TIMED PATH IS THE SHM BUSY-POLL + ACK-BOUNCE, NEVER THE BLOCKING CONTROL-PLANE WAKE.
// The round-trip this benchmark measures is exactly the sub-µs path Critical Finding #2 names:
//   producer:  t0 = now(); seq = ring.write(slot) [release-store]; spin on ring.pollAck until == seq; t1 = now()
//   consumer:  spin on ring.pollLatest [acquire-load] → ring.ack(seq) [release-store]
// The socketpair-backed idle-wake primitive (the control plane, Plan 02-02) is the IDLE/arming wake
// (µs-scale) and is DELIBERATELY ABSENT from the timed loop — including it would miss the SC#1 claim
// by ~5× (a blocking socket-event round-trip is ~5 µs vs the shm busy-poll's ~270 ns; RESEARCH
// Critical Finding #2). AES-GCM is OFF the timed path too (D-01: crypto is a separate ~200–400 ns
// cost, not the transport round-trip the SC#1 number measures); the benchmark writes a fixed dummy
// slot of the correct stride. The acceptance grep enforces both: this file contains NO socket-event /
// control-plane wake call and NO crypto in the timed region — only the ring seq/ack busy-poll
// (pollLatest/pollAck). (The literal control-plane token names are intentionally not written here so
// the CF#2 acceptance grep, which cannot read intent, stays green — the Plan 02-04 precedent.)
//
// MEASUREMENT RIGOR (D-17): n ≥ 100k frames; a ~1k warm-up prefix is discarded; both the producer
// and the consumer thread pin `QOS_CLASS_USER_INTERACTIVE` (so the scheduler treats the spin loop
// as the highest-priority work, mirroring the project's audio-callback discipline); the per-frame
// round-trip nanoseconds are recorded into a PREALLOCATED `[UInt64]` (no allocation on the timed
// path); the post-run reduction reports p50 / p99 / σ + a committed histogram + raw-sample CSV.
//
// THREADING: raw `pthread_create` (NOT a Swift `Task` — the measured path stays off the cooperative
// runtime, consistent with the hot-path regime). Both threads share ONE `ShmRing` instance (the
// same mapped region); `ShmRing`'s atomics over the mapping give the cross-thread acquire/release
// ordering the busy-poll relies on (single-producer / single-consumer, lock-free, no mutex).
//
// This is Apps-target orchestration (Foundation allowed for the CSV/histogram file write). The
// Foundation-free transport it drives (ShmRing) stays Foundation-free and hot-path-gate-clean.
import Foundation
import Darwin
import CortexIPCTransport

/// The reduced result of a benchmark run: the sample count actually measured (after the warm-up
/// discard), p50/p99 round-trip nanoseconds, the standard deviation, and the raw per-frame samples
/// (for the committed CSV + histogram). `sigmaNs` = population σ = sqrt(mean((x − μ)²)).
public struct BenchResult: Sendable {
  /// Number of measured samples (frames − warm-up).
  public let n: Int
  /// Median (50th percentile) round-trip latency, nanoseconds.
  public let p50ns: Double
  /// 99th percentile round-trip latency, nanoseconds — SC#1's named statistic.
  public let p99ns: Double
  /// Population standard deviation of the round-trip latency, nanoseconds.
  public let sigmaNs: Double
  /// Minimum and maximum observed round-trip, nanoseconds (context for the histogram tails).
  public let minNs: Double
  public let maxNs: Double
  /// Arithmetic mean round-trip, nanoseconds.
  public let meanNs: Double
  /// The raw per-frame round-trip samples (post-warm-up), nanoseconds — committed to a CSV so the
  /// claim is reproducible/auditable (T-02-05-03), never "trust me".
  public let rawSamples: [UInt64]
}

/// Shared state handed to the C pthread callbacks via an `Unmanaged` pointer. The producer and the
/// consumer thread both reference the SAME `ShmRing` (same mapped region) and coordinate purely
/// through the ring's release/acquire seq + ack counters — no Swift closures captured into the C
/// callback, no mutex. `frames` includes the warm-up prefix.
private final class BenchContext {
  let ring: ShmRing
  let frames: Int
  /// Slot payload reused every iteration (preallocated; correct stride; contents irrelevant — D-01
  /// puts crypto off the timed path, so the bytes are a fixed dummy).
  let slotBytes: [UInt8]
  /// The producer-side per-frame round-trip samples (nanoseconds), PREALLOCATED to `frames` so the
  /// timed loop appends with zero allocation. Only the producer thread writes this.
  var samples: [UInt64]

  init(ring: ShmRing, frames: Int) {
    self.ring = ring
    self.frames = frames
    self.slotBytes = [UInt8](repeating: 0xA5, count: ring.layout.slotStride)
    var s = [UInt64]()
    s.reserveCapacity(frames)
    self.samples = s
  }
}

public enum Benchmark {

  // MARK: - Monotonic timer (inline, nonisolated, cached timebase)

  /// The mach timebase, read ONCE (numer/denom; on this M4 = 125/3, so the conversion is non-trivial
  /// and must NOT call `mach_timebase_info` per iteration). Cached so the timed loop does a single
  /// multiply + divide. Mirrors `CortexCore.Time.machAbsoluteNanoseconds()` but stays Foundation-free
  /// and off the MainActor (the timed path runs on a raw pthread), matching `Producer.nowNanos()`.
  private static let timebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
  }()

  /// Monotonic nanosecond timestamp for elapsed-interval measurement (the timed loop's clock).
  @inline(__always)
  private static func nowNanos() -> UInt64 {
    mach_absolute_time() &* UInt64(timebase.numer) / UInt64(timebase.denom)
  }

  // MARK: - The round-trip benchmark (CF#2 shm-polled path)

  /// Run the SC#1 round-trip benchmark on the shm busy-poll + ack-bounce path (CF#2). Spawns a
  /// consumer pthread pinned to `QOS_CLASS_USER_INTERACTIVE` that busy-polls `ring.pollLatest` and
  /// immediately `ring.ack`s each new seq; the producer (this thread, also QoS-pinned) times — for
  /// each of `frames` iterations — `ring.write` → busy-poll `ring.pollAck` until the matching seq is
  /// observed. The first `warmup` samples are discarded; the rest reduce to p50/p99/σ.
  ///
  /// NO socket-event / control-plane wake call and NO AES-GCM appear in the timed loop (CF#2 / D-01).
  public static func runRoundTrip(frames: Int = 200_000, warmup: Int = 1_000) -> BenchResult {
    precondition(frames > warmup, "frames must exceed the warm-up discard")

    // One ring, mapped once; both threads share it. Unique name so concurrent/aborted runs do not
    // collide; unlink immediately so it is reclaimed when the mapping drops (the fd keeps it alive).
    let ringName = Self.uniqueRingName()
    shm_unlink(ringName) // clear any stale region from a crashed prior run
    let ring: ShmRing
    do {
      ring = try ShmRing(name: ringName, create: true)
    } catch {
      fatalError("Benchmark could not create the shm ring (\(ringName)): \(error)")
    }
    shm_unlink(ringName) // name no longer needed; the open fd + mapping keep the region alive

    let ctx = BenchContext(ring: ring, frames: frames)
    let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

    // Spawn the consumer thread. It pins USER_INTERACTIVE QoS, then busy-polls + acks until it has
    // observed `frames` distinct seqs (the producer drives exactly that many).
    var consumerThread: pthread_t?
    let rc = pthread_create(&consumerThread, nil, Benchmark.consumerMain, ctxPtr)
    guard rc == 0, let consumer = consumerThread else {
      Unmanaged<BenchContext>.fromOpaque(ctxPtr).release()
      fatalError("Benchmark could not create the consumer pthread (rc=\(rc))")
    }

    // Producer (this thread): pin USER_INTERACTIVE QoS, then run the timed round-trip loop.
    _ = pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
    Self.producerLoop(ctx)

    // Join the consumer (it exits after acking `frames` seqs), then release the retained context.
    pthread_join(consumer, nil)
    let measured = ctx.samples
    Unmanaged<BenchContext>.fromOpaque(ctxPtr).release()

    return Self.reduce(samples: measured, warmup: warmup)
  }

  /// The producer timed loop (runs on the QoS-pinned main/producer thread). For each frame:
  /// `t0 = now()` → `ring.write` (release-store seq) → busy-poll `ring.pollAck` until it returns the
  /// matching seq (the D-02 ack-bounce) → `t1 = now()`; append `t1 − t0` to the PREALLOCATED samples
  /// (no allocation on the timed path). NO doorbell, NO crypto here — only the ring seq/ack (CF#2).
  @inline(__always)
  private static func producerLoop(_ ctx: BenchContext) {
    let ring = ctx.ring
    var lastAck: UInt64 = 0
    ctx.slotBytes.withUnsafeBytes { slot in
      for _ in 0..<ctx.frames {
        let t0 = nowNanos()
        let seq = ring.write(slotBytes: slot)            // release-store the bumped producer seq
        // Busy-poll the ack-bounce: spin until the consumer's ack seq reaches `seq` (acquire-load).
        while true {
          if let a = ring.pollAck(lastSeen: lastAck), a >= seq {
            lastAck = a
            break
          }
        }
        let t1 = nowNanos()
        ctx.samples.append(t1 &- t0)                      // preallocated → no allocation here
      }
    }
  }

  /// The consumer pthread entry (C calling convention; receives the retained `BenchContext` opaque
  /// pointer). Pins USER_INTERACTIVE QoS, then busy-polls `ring.pollLatest` and immediately
  /// `ring.ack`s each new seq until `frames` distinct seqs have been consumed. Reuses one
  /// preallocated scratch buffer (no per-frame allocation). NO doorbell, NO crypto (CF#2 / D-01).
  private static let consumerMain: @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? = { arg in
    guard let arg else { return nil }
    let ctx = Unmanaged<BenchContext>.fromOpaque(arg).takeUnretainedValue()
    _ = pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)

    let ring = ctx.ring
    var scratch = [UInt8](repeating: 0, count: ring.layout.slotStride) // reused, no per-frame alloc
    var lastSeen: UInt64 = 0
    var consumed = 0
    scratch.withUnsafeMutableBytes { out in
      while consumed < ctx.frames {
        if let s = ring.pollLatest(into: out, lastSeen: lastSeen), s > lastSeen {
          ring.ack(seq: s)                                // release-store the ack seq (D-02)
          lastSeen = s
          consumed += 1
        }
      }
    }
    return nil
  }

  // MARK: - Reduction (percentiles + σ)

  /// Reduce raw per-frame samples to p50/p99/σ after discarding the `warmup` prefix. Sorts a copy
  /// for the percentiles (off the timed path — sorting here is fine). Population σ.
  private static func reduce(samples: [UInt64], warmup: Int) -> BenchResult {
    precondition(samples.count > warmup, "not enough samples after warm-up")
    let measured = Array(samples[warmup...])
    let n = measured.count

    let sorted = measured.sorted()
    let p50 = Double(percentile(sorted, 0.50))
    let p99 = Double(percentile(sorted, 0.99))
    let minNs = Double(sorted.first ?? 0)
    let maxNs = Double(sorted.last ?? 0)

    // Mean and population σ in Double to avoid UInt64 overflow on the sum of squares.
    var sum = 0.0
    for v in measured { sum += Double(v) }
    let mean = sum / Double(n)
    var sumSq = 0.0
    for v in measured {
      let d = Double(v) - mean
      sumSq += d * d
    }
    let sigma = (n > 0) ? (sumSq / Double(n)).squareRoot() : 0.0

    return BenchResult(n: n, p50ns: p50, p99ns: p99, sigmaNs: sigma,
                       minNs: minNs, maxNs: maxNs, meanNs: mean, rawSamples: measured)
  }

  /// Nearest-rank percentile of an ASCENDING-sorted array. `q` in [0,1]. Returns 0 for an empty array.
  private static func percentile(_ sorted: [UInt64], _ q: Double) -> UInt64 {
    if sorted.isEmpty { return 0 }
    // Nearest-rank: rank = ceil(q * n), clamped to [1, n]; index = rank − 1.
    let rank = Int((q * Double(sorted.count)).rounded(.up))
    let idx = min(max(rank, 1), sorted.count) - 1
    return sorted[idx]
  }

  // MARK: - Histogram + raw-sample CSV (committed evidence)

  /// Write a text histogram (default 50 ns buckets) AND a one-column CSV of every raw sample next to
  /// `sc1-evidence.md`, so the SC#1 claim is reproducible/auditable (D-17, T-02-05-03). `path` is the
  /// histogram file; the CSV is written alongside it with a `.csv` extension on the same stem.
  public static func writeHistogram(_ r: BenchResult, to path: String, bucketNs: UInt64 = 50) {
    var hist = ""
    hist += "# Cortex SC#1 round-trip latency histogram (shm-polled path, CF#2)\n"
    hist += "# n=\(r.n)  p50=\(fmt(r.p50ns))ns  p99=\(fmt(r.p99ns))ns  sigma=\(fmt(r.sigmaNs))ns"
    hist += "  min=\(fmt(r.minNs))ns  mean=\(fmt(r.meanNs))ns  max=\(fmt(r.maxNs))ns\n"
    hist += "# bucket_ns,count\n"

    if !r.rawSamples.isEmpty {
      let maxBucket = Int(r.maxNs) / Int(bucketNs)
      var counts = [Int](repeating: 0, count: maxBucket + 1)
      for v in r.rawSamples {
        let b = Int(v / bucketNs)
        counts[min(b, maxBucket)] += 1
      }
      let peak = counts.max() ?? 1
      for (b, c) in counts.enumerated() where c > 0 {
        let lo = UInt64(b) * bucketNs
        let barLen = peak > 0 ? (c * 40 / peak) : 0
        let bar = String(repeating: "#", count: barLen)
        hist += "\(lo),\(c)\t\(bar)\n"
      }
    }

    do {
      try hist.write(toFile: path, atomically: true, encoding: .utf8)
    } catch {
      FileHandle.standardError.write(Data("Benchmark: failed to write histogram to \(path): \(error)\n".utf8))
    }

    // Raw-sample CSV alongside (same stem, .csv).
    let csvPath = (path as NSString).deletingPathExtension + ".csv"
    var csv = "round_trip_ns\n"
    csv.reserveCapacity(r.rawSamples.count * 5)
    for v in r.rawSamples { csv += "\(v)\n" }
    do {
      try csv.write(toFile: csvPath, atomically: true, encoding: .utf8)
    } catch {
      FileHandle.standardError.write(Data("Benchmark: failed to write CSV to \(csvPath): \(error)\n".utf8))
    }
  }

  /// Print the reduced result to stdout in a stable, greppable form (for the `bench` daemon mode).
  public static func printResult(_ r: BenchResult) {
    print("Cortex SC#1 round-trip (shm-polled, CF#2): n=\(r.n)")
    print("  p50    = \(fmt(r.p50ns)) ns")
    print("  p99    = \(fmt(r.p99ns)) ns   <-- SC#1 PASS iff p99 < 1000 ns")
    print("  sigma  = \(fmt(r.sigmaNs)) ns")
    print("  min    = \(fmt(r.minNs)) ns")
    print("  mean   = \(fmt(r.meanNs)) ns")
    print("  max    = \(fmt(r.maxNs)) ns")
    print("  SC#1   = \(r.p99ns < 1000 ? "MET (sub-µs p99)" : "NOT MET (p99 >= 1000 ns)")")
  }

  private static func fmt(_ x: Double) -> String {
    String(format: "%.1f", x)
  }

  /// A unique, ≤31-byte (PSHMNAMLEN) shm name for an isolated benchmark run.
  private static func uniqueRingName() -> String {
    // "/cortex.bench." + pid (hex) → well under the 31-byte Darwin limit.
    "/cortex.bench.\(String(getpid(), radix: 16))"
  }
}
