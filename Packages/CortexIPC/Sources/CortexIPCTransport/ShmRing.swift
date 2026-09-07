import CortexCoreC

// ShmRing — Foundation-free fixed-stride POSIX shm ring (Plan 02-02 Task 1, IPC-01).
//
// This is the DATA PLANE (D-01): the producer writes an encrypted frame into a fixed-stride slot
// and bumps a sequence counter; the consumer busy-polls that counter and reads the slot zero-copy.
// Per Critical Finding #2 the busy-poll read here — NOT the kqueue doorbell — is the sub-µs path
// the SC#1 benchmark (Plan 02-05) measures. The kqueue/recvmsg doorbell (Doorbell.swift) is the
// idle/arming wake; the ack-bounce return path (D-02) is also shm-polled (ackSeq below).
//
// Foundation-free: `import Darwin` + `import CortexCoreC` only (policed by hotpath-policy.sh).
// Memory ordering: Swift 6.2 `Synchronization.Atomic<UInt64>` is laid over the mapped region
// (verified layout: size 8, alignment 8 == a bare UInt64). The producer does
//   memcpy(slot) ; producerSeq.store(seq, .releasing)
// and the consumer does
//   let s = producerSeq.load(.acquiring) ; memcpy(out, slot)
// so a consumer that observes seq S is guaranteed to see the complete slot for S (no torn read,
// T-02-02-01). Atomics over MAP_SHARED memory provide this ordering across processes too.
//
// NO mutex locks, NO cooperative-dispatch hops — both are hot-path-gate-forbidden and would
// defeat the busy-poll model (a lock is unbounded; the whole point is a lock-free SPSC counter).
import Darwin
import Synchronization

/// Compile-from-constant geometry of the ring. Every field derives from `CORTEX_CHANNEL_COUNT`
/// (the f16 channel count) so the slot stride is a constant (D-03) and the layout is identical
/// in every process that maps the region.
public struct ShmRingLayout: Sendable, Equatable {
  /// Cache-line size used to pad the header counters apart (avoids producer/consumer false sharing).
  public static let cacheLine = 64

  /// Bytes per slot: a per-slot seq tag (8) + the ENCRYPTED FlatBuffers frame (the f16 payload
  /// CHANNEL_COUNT*2 PLUS FlatBuffers framing headroom) + the GCM tag (16), rounded up to a 16-byte
  /// boundary. Plan 02-03 writes ciphertext+tag into this reserved space; Plan 02-04 verified the
  /// encrypted wire frame is the framed Sample (not the bare f16 payload), so the framing headroom is
  /// required (see `flatBuffersFramingHeadroom`).
  public let slotStride: Int

  /// FlatBuffers framing headroom (bytes) reserved in the slot beyond the raw `CHANNEL_COUNT*2` f16
  /// payload. The encrypted wire frame is the FlatBuffers-encoded `Sample` (root offset + vtable +
  /// table + vector length prefix + alignment), measured at +24 bytes over the bare payload for
  /// CHANNEL_COUNT=96; 64 gives generous slack for vtable/alignment variance across flatc versions.
  /// Plan 02-04 Rule-1 fix: the original Plan 02-02 stride reserved only the bare payload, so the
  /// encrypted framed Sample (216 B + 16 B tag = 232 B) overflowed the 224 B slot and `write` silently
  /// truncated the ciphertext — breaking AES-GCM open() on the consumer. Reserving the framing makes
  /// the encrypted frame fit (slotStride becomes 288 for CHANNEL_COUNT=96).
  public static let flatBuffersFramingHeadroom = 64
  /// Number of slots — a power of two so `seq % depth` is a mask (D-03, implementer's discretion).
  public let depth: Int
  /// Header region holding `producerSeq` (offset 0) and `ackSeq` (offset cacheLine), each on its
  /// own cache line. Sized to two cache lines = 128 bytes.
  public let headerBytes: Int
  /// Total mapped size: header + depth*stride.
  public let ringBytes: Int

  /// Byte offset of the producer sequence counter within the mapped region.
  public let producerSeqOffset: Int
  /// Byte offset of the ack sequence counter (D-02 ack-bounce) within the mapped region.
  public let ackSeqOffset: Int

  /// Default depth (D-03): 1024 slots. At a 224-byte stride that is ~224 KiB — comfortably small,
  /// power-of-two, and far deeper than the consumer's polling latency needs.
  public static let defaultDepth = 1024

  public init(channelCount: Int = Int(CORTEX_CHANNEL_COUNT), depth: Int = ShmRingLayout.defaultDepth) {
    precondition(depth > 0 && (depth & (depth - 1)) == 0, "ring depth must be a power of two")
    precondition(channelCount > 0, "channel count must be positive")

    let perSlotSeq = 8 // a copy of the frame's seq tag living inside the slot
    let payload = channelCount * 2 // raw f16 bytes (D-10)
    let framing = ShmRingLayout.flatBuffersFramingHeadroom // FlatBuffers Sample encoding overhead
    let gcmTag = 16 // AES-GCM tag reserved for Plan 02-03 (D-03)
    let raw = perSlotSeq + payload + framing + gcmTag
    slotStride = (raw + 15) & ~15 // round up to 16

    self.depth = depth

    let cl = ShmRingLayout.cacheLine
    producerSeqOffset = 0
    ackSeqOffset = cl
    headerBytes = 2 * cl // two cache-line-isolated counters

    ringBytes = headerBytes + slotStride * depth
  }
}

/// Errors mapping the three failure points of opening/mapping the ring (Swift 6 typed throws).
public enum ShmRingError: Error, Equatable {
  case open(Int32) // cortex_shm_open failed; payload = errno
  case truncate(Int32) // ftruncate failed; payload = errno
  case map(Int32) // mmap returned MAP_FAILED; payload = errno
  case sizeMismatch(expected: Int, actual: Int) // an adopted fd was too small to hold the ring
}

/// A mapped fixed-stride shm ring. Owns the fd (when it opened one) and the mapping; `deinit`
/// munmaps and closes. The per-frame `write`/`pollLatest` are the hot path (no allocation, no
/// locks); object construction/teardown is NOT on the hot path so a class with a deinit is fine.
public final class ShmRing {
  public let layout: ShmRingLayout

  /// Base of the mapped region.
  private let base: UnsafeMutableRawPointer
  /// fd owned by this instance (-1 if the caller adopted a borrowed fd; we still own the mapping).
  private let ownedFD: Int32

  /// Atomic view of the producer sequence counter, laid directly over the mapped header.
  private var producerSeq: UnsafeMutablePointer<Atomic<UInt64>> {
    base.advanced(by: layout.producerSeqOffset).assumingMemoryBound(to: Atomic<UInt64>.self)
  }

  /// Atomic view of the ack sequence counter (D-02).
  private var ackSeq: UnsafeMutablePointer<Atomic<UInt64>> {
    base.advanced(by: layout.ackSeqOffset).assumingMemoryBound(to: Atomic<UInt64>.self)
  }

  /// Pointer to the first byte of slot `index` within the mapped region.
  private func slotBase(_ index: Int) -> UnsafeMutableRawPointer {
    base.advanced(by: layout.headerBytes + index * layout.slotStride)
  }

  // MARK: - Construction

  /// Open/map the production ring at `CORTEX_SHM_NAME` (the global shm name; the App Group is the
  /// authorization boundary per Q4). `create` decides O_CREAT and whether to ftruncate.
  public convenience init(create: Bool, layout: ShmRingLayout = ShmRingLayout()) throws(ShmRingError) {
    try self.init(name: CORTEX_SHM_NAME, create: create, layout: layout)
  }

  /// Open/map a ring at an explicit name. Used by tests (unique name per test for isolation) and
  /// by callers that want a non-default name. Mirrors the ShmCheck.swift open/ftruncate/mmap
  /// reference sequence with the sentinel logic dropped.
  public init(name: String, create: Bool, layout: ShmRingLayout = ShmRingLayout()) throws(ShmRingError) {
    self.layout = layout

    let oflag: Int32 = create ? (O_CREAT | O_RDWR) : O_RDWR
    let fd = cortex_shm_open(name, oflag, 0o600)
    if fd < 0 { throw .open(errno) }

    if create {
      if ftruncate(fd, off_t(layout.ringBytes)) != 0 {
        let e = errno
        close(fd)
        throw .truncate(e)
      }
    }

    let mapped = mmap(nil, layout.ringBytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
    if mapped == MAP_FAILED || mapped == nil {
      let e = errno
      close(fd)
      throw .map(e)
    }
    base = mapped!
    ownedFD = fd
  }

  /// Map a ring from a file descriptor received over the FDChannel (consumer side, IPC-03). The fd
  /// is already open for the shared region; we mmap it directly and DO NOT close it on deinit
  /// (the caller owns the adopted fd's lifetime — typically it is closed after mapping, but we keep
  /// ownership explicit). We validate the region is at least `ringBytes` (T-02-02-02 geometry check).
  public init(adoptingFD fd: Int32, layout: ShmRingLayout = ShmRingLayout()) throws(ShmRingError) {
    self.layout = layout

    var st = stat()
    if fstat(fd, &st) == 0 {
      let actual = Int(st.st_size)
      if actual < layout.ringBytes {
        throw .sizeMismatch(expected: layout.ringBytes, actual: actual)
      }
    }

    let mapped = mmap(nil, layout.ringBytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
    if mapped == MAP_FAILED || mapped == nil {
      throw .map(errno)
    }
    base = mapped!
    ownedFD = -1 // borrowed: do not close the adopted fd in deinit
  }

  deinit {
    _ = munmap(base, layout.ringBytes)
    if ownedFD >= 0 { close(ownedFD) }
  }

  // MARK: - Slot arithmetic (constant-time)

  /// Slot index for a sequence number: `seq % depth` via a mask (depth is a power of two).
  @inlinable
  public func slotIndex(forSeq seq: UInt64) -> Int {
    Int(seq & UInt64(layout.depth - 1))
  }

  // MARK: - FD accessor (producer hand-off)

  /// Read-only access to the owned shm file descriptor, for `FDChannel.send(shmFD:)` (Plan 02-04
  /// producer hand-off). Returns the real fd on a ring created via `init(create:)`/`init(name:create:)`;
  /// returns -1 on a consumer ring (`init(adoptingFD:)` borrows the fd and does not own one to send).
  /// Only the producer (which created the region) sends — closing the 02-02->02-04 cross-plan handoff
  /// item (the fd was intentionally `private let ownedFD`). Read-only: does not transfer ownership.
  public var fd: Int32 {
    ownedFD
  }

  // MARK: - Producer (data plane)

  /// Write a frame into the next slot and publish it. Copies up to `slotStride` bytes (clamped),
  /// then RELEASE-stores the bumped producer seq so a consumer that acquire-loads the seq sees the
  /// fully-written slot. Returns the new seq. Hot path: one bounded memcpy + one atomic store.
  @discardableResult
  public func write(slotBytes: UnsafeRawBufferPointer) -> UInt64 {
    let prev = producerSeq.pointee.load(ordering: .relaxed) // single-producer: relaxed read of own counter
    let seq = prev &+ 1
    let idx = slotIndex(forSeq: seq)
    let dst = slotBase(idx)

    let n = min(slotBytes.count, layout.slotStride)
    if let src = slotBytes.baseAddress, n > 0 {
      memcpy(dst, src, n)
    }
    // Publish AFTER the payload is in place (T-02-02-01 ordering contract).
    producerSeq.pointee.store(seq, ordering: .releasing)
    return seq
  }

  // MARK: - Consumer (busy-poll — the CF#2 measured path)

  /// Busy-poll read: ACQUIRE-load the producer seq; if it advanced past `lastSeen`, copy the latest
  /// slot into `out` and return the seq, else return nil. The acquire load orders the subsequent
  /// slot read after the producer's release store, so the slot is fully visible (no torn read).
  /// This is the sub-µs path SC#1 measures (Critical Finding #2) — no syscall, no context switch.
  public func pollLatest(into out: UnsafeMutableRawBufferPointer, lastSeen: UInt64) -> UInt64? {
    let s = producerSeq.pointee.load(ordering: .acquiring)
    if s == lastSeen { return nil }
    let idx = slotIndex(forSeq: s)
    let src = slotBase(idx)
    let n = min(out.count, layout.slotStride)
    if let dstBase = out.baseAddress, n > 0 {
      memcpy(dstBase, src, n)
    }
    return s
  }

  /// Read-only acquire-load of the current producer seq (e.g. to size a spin loop). No slot read.
  public func loadProducerSeq() -> UInt64 {
    producerSeq.pointee.load(ordering: .acquiring)
  }

  // MARK: - Ack-bounce (D-02 return path, also shm-polled)

  /// Consumer side: RELEASE-store the ack seq after consuming a frame so the producer can measure
  /// a true round-trip (producer → consumer → ack) per D-02.
  public func ack(seq: UInt64) {
    ackSeq.pointee.store(seq, ordering: .releasing)
  }

  /// Producer side: ACQUIRE-load the ack seq; return it if it advanced past `lastSeen`, else nil.
  public func pollAck(lastSeen: UInt64) -> UInt64? {
    let s = ackSeq.pointee.load(ordering: .acquiring)
    return s == lastSeen ? nil : s
  }
}
