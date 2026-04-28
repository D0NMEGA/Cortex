// Reserved for Phase 2 — POSIX shm + kqueue + recvmsg + AES-GCM transport.
// See REQUIREMENTS.md IPC-01 through IPC-07 and the hot-path policy script
// at Tools/scripts/hotpath-policy.sh which polices this directory.

// Marker so the file has at least one declaration (SwiftPM linter quirk avoidance).
public enum CortexIPC {
  public static let phase: Int = 1
}
