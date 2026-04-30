// ShmCheck -- utility for Phase 1 SC#2 manual verification (Plan 01-07 runbook).
// Calls shm_open("/cortex.samples", O_CREAT | O_RDWR, 0600) and returns the result.
// Both CortexMac and CortexDaemon call this on launch / button-press to demonstrate
// cross-process shm_open works inside the App Group container.
//
// Phase 2 will replace this with the real IPC primitive (kqueue + recvmsg). This file
// exists ONLY for Phase 1 SC#2 evidence capture and is removed when Phase 2 lands.

import Foundation
@_exported import CortexCoreC

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
  public let timestamp: UInt64

  public var description: String {
    let fdStr = fileDescriptor >= 0 ? String(fileDescriptor) : "FAILED (errno=\(errnoValue))"
    return """
    --- ShmCheckResult ---
      process:    \(processName) (pid \(pid))
      container:  \(containerURL?.path ?? "(nil -- App Group not authorized in this context)")
      shm name:   \(shmName)
      open flags: 0x\(String(openFlags, radix: 16)) (\(decodeFlags(openFlags)))
      open mode:  0o\(String(openMode, radix: 8))
      fd:         \(fdStr)
      inode:      \(inode)
      mach ts ns: \(timestamp)
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
  /// Run the SC#2 verification call: shm_open(CORTEX_SHM_NAME, O_CREAT|O_RDWR, 0600).
  /// Returns a result struct suitable for printing into the evidence file.
  public static func openSharedRegion(processLabel: String? = nil) -> ShmCheckResult {
    let name = String(cString: CORTEX_SHM_NAME)
    let flags: Int32 = O_CREAT | O_RDWR
    let mode: mode_t = 0o600
    let fd = shm_open(name, flags, mode)
    let err = errno

    var inode: UInt64 = 0
    if fd >= 0 {
      var st = stat()
      if fstat(fd, &st) == 0 {
        inode = UInt64(st.st_ino)
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
      timestamp: Time.machAbsoluteNanoseconds()
    )
  }

  /// Cleanup: shm_unlink the region (call only when finished verifying -- releases the kernel mapping).
  /// Phase 1 runbook does NOT call this so the shm region persists across the two processes.
  public static func unlinkSharedRegion() -> Bool {
    let name = String(cString: CORTEX_SHM_NAME)
    return shm_unlink(name) == 0
  }
}
