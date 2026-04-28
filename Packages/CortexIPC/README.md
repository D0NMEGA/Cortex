# CortexIPC

Reserved for Phase 2: sub-µs POSIX shm + kqueue + recvmsg + FlatBuffers + AES-GCM
sample-frame transport between the acquisition daemon and the app process.

Empty in Phase 1 — see `.planning/REQUIREMENTS.md` IPC-01 through IPC-07.

## Hot-path policy

Source files in this directory are policed by `Tools/scripts/hotpath-policy.sh`,
which fails the build if any forbidden token (`dispatch_async`, `lazy var`,
`pthread_mutex`, `import Foundation`, `import ObjectiveC`) appears.
The script is a no-op while this directory is empty; it bites the moment Phase 2 lands.
