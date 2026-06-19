// ShmCheck -- utility for Phase 1 SC#2 manual verification (Plan 01-07 runbook).
// Opens the App-Group-scoped POSIX shared-memory region "/cortex.samples" and proves
// cross-process sharing between CortexMac (app) and CortexDaemon (executable).
//
// PROOF MECHANISM: the plan originally specified "fstat returns the same inode in both
// processes." On Darwin, POSIX shm objects are kernel objects (not filesystem-backed), so
// fstat returns st_ino = 0 -- a degenerate match that proves nothing. Instead we prove
// sharing the robust way: ftruncate + mmap the region, READ the 8-byte sentinel left by a
// prior process, then WRITE our own (magic << 32 | pid). When CortexMac reads back the
// daemon's PID from the shared mapping, cross-process shared memory is irrefutably proven.
//
// Phase 2 will replace this with the real IPC primitive (kqueue + recvmsg). This file
// exists ONLY for Phase 1 SC#2 evidence capture and is removed when Phase 2 lands.

import Foundation
@_exported import CortexCoreC

/// Magic in the high 32 bits of the sentinel so a zero-filled / foreign region is
/// distinguishable from a genuine Cortex writer.
private let cortexShmMagic: UInt32 = 0xC0DE_2026
/// One page is plenty for an 8-byte sentinel; matches the granularity the kernel maps.
private let cortexShmRegionBytes = 4096

public struct ShmCheckResult: CustomStringConvertible {
  public let processName: String
  public let pid: Int32
  public let containerURL: URL?
  public let shmName: String
  public let openFlags: Int32
  public let openMode: mode_t
  public let fileDescriptor: Int32
  public let errnoValue: Int32
  public let inode: UInt64
  public let regionSize: Int
  public let mmapSucceeded: Bool
  public let sentinelRead: UInt64
  public let sentinelWritten: UInt64
  public let timestamp: UInt64

  /// PID encoded in `sentinelRead` if it carries the Cortex magic, else nil (zero/foreign region).
  public var peerPidFromShared: Int32? {
    guard UInt32(truncatingIfNeeded: sentinelRead >> 32) == cortexShmMagic else { return nil }
    return Int32(truncatingIfNeeded: sentinelRead)
  }

  public var description: String {
    let fdStr = fileDescriptor >= 0 ? String(fileDescriptor) : "FAILED (errno=\(errnoValue))"
    let peerStr: String
    if let peer = peerPidFromShared {
      peerStr = "pid \(peer) (another process wrote this — SHARED MEMORY CONFIRMED)"
    } else if sentinelRead == 0 {
      peerStr = "0x0 (region was empty — this process is the first writer)"
    } else {
      peerStr = String(format: "0x%016llX (no Cortex magic)", sentinelRead)
    }
    return """
    --- ShmCheckResult ---
      process:     \(processName) (pid \(pid))
      container:   \(containerURL?.path ?? "(nil -- App Group not authorized in this context)")
      shm name:    \(shmName)
      open flags:  0x\(String(openFlags, radix: 16)) (\(decodeFlags(openFlags)))
      open mode:   0o\(String(openMode, radix: 8))
      fd:          \(fdStr)
      inode:       \(inode) (Darwin POSIX shm: always 0 -- see sentinel for the real proof)
      region size: \(regionSize) bytes (ftruncate'd, shared metadata)
      mmap:        \(mmapSucceeded ? "OK (MAP_SHARED)" : "FAILED")
      read  shm:   \(String(format: "0x%016llX", sentinelRead)) -> \(peerStr)
      wrote shm:   \(String(format: "0x%016llX", sentinelWritten)) (magic 0x\(String(cortexShmMagic, radix: 16)) | this pid \(pid))
      mach ts ns:  \(timestamp)
    -----------------------
    """
  }

  private func decodeFlags(_ flags: Int32) -> String {
    var parts: [String] = []
    if flags & O_CREAT != 0 { parts.append("O_CREAT") }
    if flags & O_RDWR != 0 { parts.append("O_RDWR") }
    if flags & O_RDONLY != 0 || flags == 0 { parts.append("O_RDONLY") }
    if flags & O_WRONLY != 0 { parts.append("O_WRONLY") }
    if flags & O_EXCL != 0 { parts.append("O_EXCL") }
    return parts.isEmpty ? "(none)" : parts.joined(separator: "|")
  }
}

public enum ShmCheck {
  /// Run the SC#2 verification: shm_open(CORTEX_SHM_NAME, O_CREAT|O_RDWR, 0600), ftruncate to a
  /// page, mmap MAP_SHARED, read the prior sentinel, write our own. Returns a printable result.
  public static func openSharedRegion(processLabel: String? = nil) -> ShmCheckResult {
    let name = CORTEX_SHM_NAME // imported from C as a Swift String constant
    let flags: Int32 = O_CREAT | O_RDWR
    let mode: mode_t = 0o600
    // cortex_shm_open is the non-variadic C shim for shm_open (Swift can't call C variadics).
    let fd = cortex_shm_open(name, flags, mode)
    let err = errno

    var inode: UInt64 = 0
    var regionSize = 0
    var mmapSucceeded = false
    var sentinelRead: UInt64 = 0
    var sentinelWritten: UInt64 = 0

    if fd >= 0 {
      var st = stat()
      if fstat(fd, &st) == 0 {
        inode = UInt64(st.st_ino)
        // Size the region if it is smaller than one page (idempotent across runs).
        if st.st_size < off_t(cortexShmRegionBytes) {
          _ = ftruncate(fd, off_t(cortexShmRegionBytes))
          _ = fstat(fd, &st)
        }
        regionSize = Int(st.st_size)
      }

      let mapped = mmap(nil, cortexShmRegionBytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
      if mapped != MAP_FAILED, let base = mapped {
        mmapSucceeded = true
        // Read whatever a prior process left (0 if first / zero-filled).
        sentinelRead = base.loadUnaligned(fromByteOffset: 0, as: UInt64.self)
        // Write our own sentinel: high 32 = magic, low 32 = our pid.
        sentinelWritten = (UInt64(cortexShmMagic) << 32) | UInt64(UInt32(bitPattern: getpid()))
        base.storeBytes(of: sentinelWritten, toByteOffset: 0, as: UInt64.self)
        _ = msync(base, cortexShmRegionBytes, MS_SYNC)
        _ = munmap(base, cortexShmRegionBytes)
      }
    }

    let pn = processLabel ?? ProcessInfo.processInfo.processName

    return ShmCheckResult(
      processName: pn,
      pid: getpid(),
      containerURL: AppGroup.containerURL(),
      shmName: name,
      openFlags: flags,
      openMode: mode,
      fileDescriptor: fd,
      errnoValue: err,
      inode: inode,
      regionSize: regionSize,
      mmapSucceeded: mmapSucceeded,
      sentinelRead: sentinelRead,
      sentinelWritten: sentinelWritten,
      timestamp: Time.machAbsoluteNanoseconds()
    )
  }

  /// Cleanup: shm_unlink the region (releases the kernel object). Call to reset between
  /// independent evidence runs; the runbook itself relies on the region persisting so the
  /// daemon's write is visible to the app.
  @discardableResult
  public static func unlinkSharedRegion() -> Bool {
    shm_unlink(CORTEX_SHM_NAME) == 0
  }
}
