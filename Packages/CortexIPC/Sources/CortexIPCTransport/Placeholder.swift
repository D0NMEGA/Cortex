/// CortexIPCTransport — Foundation-free hot path (shm ring + kqueue/recvmsg doorbell + mach_msg
/// FD passing). Implemented in Plan 02-02. This placeholder exists only so the target compiles
/// after the Plan 02-01 split. This directory is Foundation-free and is policed by
/// Tools/scripts/hotpath-policy.sh — keep the five forbidden hot-path tokens out of it
/// (no dispatch async, no lazy stored properties, no pthread locks, no Foundation/ObjectiveC
/// imports). Use Darwin/POSIX + Swift concurrency primitives only.
public enum CortexIPCTransport {}
