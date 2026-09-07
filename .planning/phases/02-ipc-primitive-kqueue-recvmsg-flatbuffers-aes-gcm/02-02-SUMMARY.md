---
phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm
plan: 02
subsystem: infra
tags: [shm-ring, mmap, kqueue, recvmsg, socketpair, mach-ipc, fileport, mach-msg-port-descriptor, atomics, foundation-free, hotpath-gate]

# Dependency graph
requires:
  - phase: 02-01
    provides: "CortexIPCTransport (Foundation-free target, no MainActor isolation) + CortexIPCSession split; CORTEX_CHANNEL_COUNT (=96) compile-time constant + _Static_assert in cortex_shm.h; hot-path gate re-scoped to CortexIPCTransport; cortex_shm_open shim; CF#3 rendezvous verdict (PASS, posix_spawnattr_setspecialport_np @ TASK_BOOTSTRAP_PORT)"
  - phase: 01-foundation-2026-toolchain
    provides: "cortex_shm.h (CORTEX_SHM_NAME + cortex_shm_open), CortexCoreC C target with SwiftPM-auto-generated module map, AppGroup/Time helpers, App Group group.com.donovansantine.cortex.shared"
provides:
  - "ShmRing: Foundation-free fixed-stride POSIX shm ring (open/map via cortex_shm_open + mmap MAP_SHARED), slot stride 224 = roundUp16(8 + CORTEX_CHANNEL_COUNT*2 + 16), depth 1024 (power-of-two), cache-line-padded producerSeq/ackSeq header, acquire/release busy-poll read (the CF#2 measured path) + ack-bounce (D-02)"
  - "Doorbell: socketpair(AF_UNIX,SOCK_STREAM) + kqueue EVFILT_READ + recvmsg idle/arming wake carrying an 8-byte seq notification; FD_CLOEXEC + SO_NOSIGPIPE hardened; NO socket control-message rights path"
  - "cortex_fdmsg.h/.c (CortexCoreC): cross-process shm-fd handoff via a COMPLEX mach_msg with exactly one MACH_MSG_PORT_DESCRIPTOR from fileport_makeport / fileport_makefd — the mandated Mach primitive with ZERO SCM_RIGHTS (SC#2)"
  - "FDChannel: Foundation-free Swift wrapper over the shim; takes a mach_port_t from the harness rendezvous; validates received ring geometry against the compile-time CORTEX_CHANNEL_COUNT layout before mapping (T-02-02-02)"
  - "ShmCheck.swift removed (Phase-1-only placeholder); both CortexCore + CortexIPC build clean"
affects: [phase-02-plan-03-session-keychain-codec, phase-02-plan-04-harness-rendezvous, phase-02-plan-05-benchmark, phase-03-pthread-hotpath, phase-04-decoder]

# Tech tracking
tech-stack:
  added:
    - "Swift 6.2 Synchronization.Atomic<UInt64> laid over mmap'd MAP_SHARED memory (verified layout: size 8 / alignment 8 == a bare UInt64) for cross-process acquire/release seq counters"
    - "mach_msg + MACH_MSG_PORT_DESCRIPTOR + fileport_makeport/fileport_makefd FD passing (C shim in CortexCoreC)"
    - "kqueue/kevent EVFILT_READ + recvmsg over an AF_UNIX socketpair doorbell"
  patterns:
    - "Foundation-free hot path: import Darwin + import CortexCoreC only; Synchronization.Atomic over shared memory instead of pthread/dispatch (the model Phase 3's pthread USER_INTERACTIVE path follows)"
    - "Acquire/release ordering contract on a fixed-stride SPSC ring: producer memcpy(slot) THEN producerSeq.store(.releasing); consumer producerSeq.load(.acquiring) THEN memcpy(out) — observed seq implies a fully-written slot (no torn read)"
    - "C shim in CortexCoreC keeps a Mach/Darwin primitive callable from the Foundation-free target (extends the cortex_shm_open precedent)"
    - "Literal-token-grep avoidance in comments: describe forbidden tokens (mutex locks, the no-rights-transfer invariant) WITHOUT embedding their fixed strings so the hot-path gate (grep -F pthread_mutex) and the SC#2 grep (SCM_RIGHTS|cmsg) stay clean (Plan 02-01 precedent)"

key-files:
  created:
    - "Packages/CortexIPC/Sources/CortexIPCTransport/ShmRing.swift"
    - "Packages/CortexIPC/Sources/CortexIPCTransport/Doorbell.swift"
    - "Packages/CortexIPC/Sources/CortexIPCTransport/FDChannel.swift"
    - "Packages/CortexCore/Sources/CortexCoreC/include/cortex_fdmsg.h"
    - "Packages/CortexCore/Sources/CortexCoreC/cortex_fdmsg.c"
    - "Packages/CortexIPC/Tests/CortexIPCTransportTests/RingTests.swift"
    - "Packages/CortexIPC/Tests/CortexIPCTransportTests/DoorbellTests.swift"
  modified:
    - "Packages/CortexCore/Sources/CortexCore/ShmCheck.swift (REMOVED via git rm)"

key-decisions:
  - "Used Swift 6.2 Synchronization.Atomic<UInt64> directly over the mmap'd region (NOT the C-atomic fallback): a probe confirmed Atomic<UInt64> has size 8 / alignment 8 (identical to a bare UInt64) and works via assumingMemoryBound(to: Atomic<UInt64>.self) with .store(.releasing)/.load(.acquiring). This is the plan's PREFERRED path; the CortexCoreC atomic fallback was not needed."
  - "Ring geometry: slotStride = 224 = roundUp16(8 perSlotSeq + 96*2 payload + 16 GCM tag); depth = 1024 (power-of-two, mask-based wrap); headerBytes = 128 (producerSeq at offset 0, ackSeq at offset 64 — each on its own 64-byte cache line to kill producer/consumer false sharing); ringBytes = 229504."
  - "FD descriptor disposition = MACH_MSG_TYPE_MOVE_SEND (the fileport's send right is moved to the receiver); remote-port bits = MACH_MSG_TYPE_COPY_SEND (we copy the dest send right handed to us by the rendezvous). Send drops the fileport on Mach failure (no leak); recv deallocates the received port right after fileport_makefd."
  - "FDChannel.receive validates the received geometry (ring_bytes/slot_stride/slot_depth) against the consumer's OWN compile-time CORTEX_CHANNEL_COUNT layout before mapping and closes the fd on mismatch (T-02-02-02 defense-in-depth against a malicious fd/geometry from a holder of the rendezvous send right)."
  - "ShmRing.init(adoptingFD:) maps a borrowed fd (consumer side) and does NOT close it in deinit (explicit borrow); init(name:create:) / init(create:) own and close their fd. A test-only init(name:create:) overload gives each test a unique shm name (shm_unlink teardown) since the production ring opens the GLOBAL CORTEX_SHM_NAME."

patterns-established:
  - "SPSC shm ring acquire/release discipline — reused verbatim by Phase 3's Rust SPSC ring bridge."
  - "Doorbell is the idle/arming wake, NOT the measured path (CF#2): the sub-µs SC#1 number comes from ShmRing.pollLatest busy-poll. Plan 02-05's benchmark must measure the busy-poll + ack-bounce, never a blocking kevent round-trip."
  - "The two-grep comment discipline: a hot-path source may DOCUMENT that it avoids mutex locks / rights-transfer without tripping the grep -F gate or the SC#2 regex by never writing the literal forbidden token."

requirements-completed: [IPC-01, IPC-02, IPC-03]

# Metrics
duration: 38min
completed: 2026-06-20
---

# Phase 2 Plan 02: Foundation-free CortexIPCTransport hot path (shm ring + kqueue/recvmsg doorbell + mach_msg/fileport FD passing) Summary

**The Foundation-free transport primitive: a fixed-stride MAP_SHARED shm ring with an acquire/release busy-poll read (the CF#2 sub-µs path) + ack-bounce, a socketpair+kqueue EVFILT_READ doorbell for the idle wake, and a CortexCoreC mach_msg+fileport C shim that hands the shm fd across processes with ZERO SCM_RIGHTS (SC#2) — ShmCheck.swift retired.**

## Performance

- **Duration:** ~38 min
- **Started:** 2026-06-20T02:05Z
- **Completed:** 2026-06-20T02:43Z
- **Tasks:** 3 / 3 (fully autonomous; no checkpoint — all tasks type=auto on the signing-capable M4)
- **Files created/modified:** 8 (7 created, 1 removed)

## Accomplishments

- **ShmRing (IPC-01, CF#2):** Foundation-free fixed-stride POSIX shm ring opened/mapped via `cortex_shm_open` + `mmap(MAP_SHARED)`. Slot stride (224) is a constant derived from `CORTEX_CHANNEL_COUNT` (D-03); depth 1024 is a power-of-two so `seq % depth` is a mask. The header puts `producerSeq` and `ackSeq` on separate 64-byte cache lines (no false sharing). The **busy-poll read** (`pollLatest`: acquire-load seq → read slot) is the sub-µs path SC#1 measures; the **ack-bounce** (`ack`/`pollAck`, D-02) is also shm-polled. `Synchronization.Atomic<UInt64>` is laid directly over the mapped region (verified layout-compatible) with `.releasing`/`.acquiring` ordering — no C-atomic fallback needed, no pthread/dispatch.
- **Doorbell (IPC-02):** `socketpair(AF_UNIX, SOCK_STREAM)` + `kqueue` `EVFILT_READ` + `recvmsg` delivering an 8-byte `seq` notification (D-01 — never the frame). Both fds hardened with `FD_CLOEXEC` + `SO_NOSIGPIPE`. `wait` returns `.woke(seq:)` / `.timeout` / `.peerClosed` (EV_EOF fail-closed). This is the **idle/arming wake** (CF#2), explicitly not the measured path. The `recvmsg` uses a single iovec with **no control buffer** — there is no rights-transfer path on the socket (reinforces SC#2).
- **FD passing (IPC-03, SC#2):** `cortex_fdmsg.c` (CortexCoreC) sends/receives the shm fd inside a **COMPLEX `mach_msg`** carrying exactly one `MACH_MSG_PORT_DESCRIPTOR` built from `fileport_makeport`; the receiver reconstructs via `fileport_makefd`. The ring geometry rides inline so the receiver can validate before mapping. **No `SCM_RIGHTS`, no `cmsg`, no socket control message anywhere** — the defining SC#2 invariant. `FDChannel.swift` wraps it Foundation-free, takes a `mach_port_t` from the harness's CF#3 rendezvous, and validates the received geometry against the compile-time layout (T-02-02-02).
- **ShmCheck.swift removed:** the Phase-1-only cross-process-shm placeholder (its own header said Phase 2 retires it) is gone via `git rm`; its only remaining references are the Apps Xcode targets, rewired in Plan 02-04. `AppGroup.swift` + `Time.swift` untouched. Both `CortexCore` and `CortexIPC` build clean; the hot-path gate is green.

## Task Commits

Each task committed atomically (`--no-verify`, isolated worktree executor running concurrently with the Plan 02-03 executor):

1. **Task 1: Foundation-free shm ring + RingTests (5 @Test)** — `65484c8` (feat)
2. **Task 2: socketpair + kqueue EVFILT_READ doorbell + DoorbellTests (4 @Test)** — `b9b5697` (feat)
3. **Task 3: mach_msg+fileport FD-passing C shim + FDChannel; remove ShmCheck** — `d1612d9` (feat)

**Plan metadata:** committed with this SUMMARY (docs).

_Note: TDD tasks (1 and 2) were each written tests-RED-first then implementation-GREEN; since the implementation made the failing tests pass on first green and the only post-green edits were gate-satisfying comment rewords (refactor, tests stayed green), each task is a single atomic feat commit. The orchestrator owns STATE.md / ROADMAP.md after the wave — this plan did not touch them._

## Files Created/Modified

- `Packages/CortexIPC/Sources/CortexIPCTransport/ShmRing.swift` — fixed-stride shm ring; `ShmRingLayout` (compile-from-`CORTEX_CHANNEL_COUNT` geometry); `init(create:)` / `init(name:create:)` / `init(adoptingFD:)`; `write` (release-store), `pollLatest` (acquire-load busy-poll), `ack`/`pollAck` (D-02); typed `ShmRingError`. Foundation-free.
- `Packages/CortexIPC/Sources/CortexIPCTransport/Doorbell.swift` — `DoorbellPair`, `WakeResult`, `DoorbellError`; `ring(seq:)` (send 8 bytes), `arm()` (kqueue EVFILT_READ), `wait(timeoutNanos:)` (kevent + recvmsg, no control buffer); FD_CLOEXEC + SO_NOSIGPIPE hardening. Foundation-free.
- `Packages/CortexIPC/Sources/CortexIPCTransport/FDChannel.swift` — Foundation-free wrapper over the shim; `send(shmFD:geometry:to:)` / `receive(on:)` with geometry validation; `FDChannelError`.
- `Packages/CortexCore/Sources/CortexCoreC/include/cortex_fdmsg.h` — `cortex_fd_msg_t` (header + body + one port descriptor + inline geometry + bounded `shm_name[32]`); `cortex_fdmsg_send` / `cortex_fdmsg_recv` declarations.
- `Packages/CortexCore/Sources/CortexCoreC/cortex_fdmsg.c` — the mach_msg complex-message send/recv with fileport_makeport/makefd; MOVE_SEND descriptor; no-leak error paths; NO SCM_RIGHTS/cmsg.
- `Packages/CortexIPC/Tests/CortexIPCTransportTests/RingTests.swift` — 5 @Test (round-trip, wrap-around, constant stride, MAP_SHARED two-mapping visibility, ordering contract + ack-bounce); unique per-test shm name with `shm_unlink` teardown.
- `Packages/CortexIPC/Tests/CortexIPCTransportTests/DoorbellTests.swift` — 4 @Test (wake delivers 8-byte seq, no spurious wake, FD_CLOEXEC on both fds, SO_NOSIGPIPE returns EPIPE on dead peer).
- `Packages/CortexCore/Sources/CortexCore/ShmCheck.swift` — **REMOVED** (`git rm`; Phase-1-only placeholder).

## Decisions Made

- **`Synchronization.Atomic` over mmap'd memory (preferred path, no fallback).** A throwaway probe proved `Atomic<UInt64>` is layout-identical to `UInt64` (size 8 / align 8) and that placing one over raw/mmap'd memory via `assumingMemoryBound(to: Atomic<UInt64>.self)` with acquire/release ordering works. The plan allowed a CortexCoreC C-atomic fallback if `Synchronization` couldn't bind to mapped memory — it can, so the cleaner Swift path was used. Atomics over `MAP_SHARED` memory carry the same acquire/release ordering across processes.
- **Ring layout (implementer's discretion per D-03):** depth 1024, stride 224, 128-byte two-cache-line header. Documented in `ShmRingLayout` and asserted in `RingTests.constantStride`.
- **mach_msg dispositions:** MOVE_SEND for the fileport descriptor (transfer the fd capability), COPY_SEND for the remote port (we were handed a send right). Both error paths avoid leaking the fileport / received port right.
- **Geometry validation on receive (T-02-02-02):** the consumer trusts only its own `CORTEX_CHANNEL_COUNT`-derived layout and rejects a mismatching sender (closing the fd), so a holder of the rendezvous send right can't make the consumer map an attacker-chosen region.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Plan/gate literal-token contradiction] Reworded a ShmRing comment to not embed the literal `pthread_mutex`**
- **Found during:** Task 1 (acceptance / hot-path gate check)
- **Issue:** My explanatory comment said "NO pthread_mutex, NO dispatch …" to document why the ring is lock-free. The hot-path gate uses `grep -F pthread_mutex`, so that literal substring inside a comment tripped the gate (exit 1) — the comment defeated the very rule it documented. This is the exact Plan 02-01 precedent (its placeholder comment had the same problem with `import Foundation`).
- **Fix:** Reworded to "NO mutex locks, NO cooperative-dispatch hops …" — intent preserved, no forbidden literal. The acceptance criterion "contains NO pthread_mutex" is now satisfied honestly (the ring genuinely uses no mutex).
- **Files modified:** `Packages/CortexIPC/Sources/CortexIPCTransport/ShmRing.swift`
- **Verification:** `hotpath-policy.sh` exits 0; RingTests still 5/5 green.
- **Committed in:** `65484c8` (Task 1)

**2. [Rule 1 - SC#2-grep literal-token contradiction] Reworded three Doorbell comments to not embed `SCM_RIGHTS` / `cmsg`**
- **Found during:** Task 2 (SC#2 grep check)
- **Issue:** Doorbell.swift legitimately documents that it has NO control-message FD path (it's the no-rights-transfer reinforcement). The plan's Task 2 criterion (`! grep -nE 'SCM_RIGHTS|cmsg' Doorbell.swift`) and the defining SC#2 invariant (`! grep -rnE 'SCM_RIGHTS|cmsg\(' …`) both flag the literal tokens even inside "NO SCM_RIGHTS" comments — the grep can't read intent.
- **Fix:** Reworded the three comment lines to describe "the no-rights-transfer invariant (SC#2)" / "no BSD socket control-message FD-passing path" without writing the literal tokens. The actual code has no control buffer (`msg_control = nil`) — the invariant holds; only the prose changed.
- **Files modified:** `Packages/CortexIPC/Sources/CortexIPCTransport/Doorbell.swift`
- **Verification:** both SC#2 grep variants return nothing across CortexIPC/Sources + CortexCoreC; DoorbellTests still 4/4 green.
- **Committed in:** `b9b5697` (Task 2)

**3. [Rule 3 - Blocking] Cleared a stale CortexIPC build cache so the new CortexCoreC header resolved**
- **Found during:** Task 3 (CortexIPC build with FDChannel)
- **Issue:** After adding `cortex_fdmsg.h` to CortexCoreC's `include/` and building CortexCore (which succeeded), the first `swift build --package-path Packages/CortexIPC` reported `cannot find 'cortex_fdmsg_send' in scope` — CortexIPC's `.build` had cached the CortexCoreC clang module from before the header existed.
- **Fix:** `rm -rf Packages/CortexIPC/.build` then rebuilt; the SwiftPM-auto-generated module map re-scanned `include/` and exposed both `cortex_shm.h` and `cortex_fdmsg.h`. (`.build` is git-ignored; nothing committed for this.)
- **Files modified:** none (build artifact only)
- **Verification:** `swift build --package-path Packages/CortexIPC` exits 0; FDChannel resolves both shim functions; full Task 3 verify command prints OK.
- **Committed in:** n/a (no source change)

---

**Total deviations:** 3 auto-fixed (2 literal-token-grep contradictions [Rule 1], 1 blocking stale-cache [Rule 3]).
**Impact on plan:** All three were necessary to make the plan's own acceptance criteria / gate / builds pass; no scope creep, no architectural change. The ring layout, the busy-poll/ack-bounce model, the doorbell hardening, the mach_msg+fileport shim, and the ShmCheck removal are exactly as the plan specified. Notably, the `Synchronization.Atomic`-over-mmap path was the plan's PREFERRED option (the C-atomic fallback was authorized but unneeded) — not a deviation.

## Issues Encountered

- A unqualified `close(fds[i])` inside the Doorbell `init` catch block resolved to my own no-arg `close()` instance method instead of POSIX `close(Int32)` (compile error). Fixed by qualifying as `Darwin.close(...)`. Resolved within Task 2 before commit.
- The harness backgrounded several throwaway `swiftc` probe invocations and truncated their tail output; rather than fight it, I relied on `swift test` / `swift build` as the authoritative compile check (the probes had already confirmed the Darwin/mach symbol spellings with no `error:` output).

## Cross-Plan Notes

**For Plan 02-04 (harness / rendezvous) — the wiring contract:**
1. The harness obtains the rendezvous send right per the CF#3 verdict (02-SPIKES.md): parent injects a send right via `posix_spawnattr_setspecialport_np(&attr, sendRight, TASK_BOOTSTRAP_PORT=4)`; the Foundation-free child reads it via `task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &p)`.
2. **Producer (daemon):** create the ring with `ShmRing(create: true)`; call `FDChannel.send(shmFD: <ring fd>, geometry: <ShmRingLayout()>, to: <send right>)`. (ShmRing currently owns its fd privately; Plan 02-04 needs an accessor or a `dup`/`fileport` of it — expose `ownedFD` or add a `withFD` if required. Flagging: the fd is intentionally `private let` today.)
3. **Consumer (app):** `let (fd, geom) = try FDChannel.receive(on: <receive right>)`; then `ShmRing(adoptingFD: fd, layout: geom)`. The geometry is already validated against `CORTEX_CHANNEL_COUNT`.
4. **Steady state:** producer `ring.write(slotBytes:)` (returns seq) → `doorbell.ring(seq:)`; consumer `doorbell.wait(...)` to wake from idle, then `ring.pollLatest(into:lastSeen:)` busy-poll (the CF#2 measured path), then `ring.ack(seq:)`; producer `ring.pollAck(lastSeen:)` to close the D-02 round-trip. **SC#1 (Plan 02-05) must time the busy-poll + ack-bounce, NOT a blocking kevent round-trip.**

**For Plan 02-03 (Session layer):**
- The ring slot stride already reserves the 16-byte GCM tag region: `slotStride = roundUp16(8 perSlotSeq + CORTEX_CHANNEL_COUNT*2 payload + 16 tag) = 224`. The Session encrypts the FlatBuffers `Sample` frame and writes `ciphertext || tag` into the slot's payload+tag region; `ShmRing.write` copies up to `slotStride` bytes verbatim (it is payload-agnostic).
- Per the Plan 02-01 CF#1 verdict, the Session must use the single-process Keychain round-trip + deliver the session secret over the secure channel (defer access-group sharing to Phase 8). The transport channel built here (mach_msg) is the carrier for that key handoff if desired.

## Known Stubs

None introduced by this plan. The pre-existing `Packages/CortexIPC/Sources/CortexIPCTransport/Placeholder.swift` (an empty `enum CortexIPCTransport {}`) is the Plan 02-01-mandated scaffold; it is harmless (no data flow, no UI) and can be removed by a later plan once nothing imports the bare enum. All five production sources are complete, not stubs.

## Self-Check: PASSED

- All 7 created source/test files exist on disk (ShmRing, Doorbell, FDChannel, cortex_fdmsg.h, cortex_fdmsg.c, RingTests, DoorbellTests) + this SUMMARY — VERIFIED
- `ShmCheck.swift` is removed from disk and staged as a deletion — VERIFIED
- All 3 task commits exist (`65484c8`, `b9b5697`, `d1612d9`) — VERIFIED via `git log`
- Both packages build (CortexCore + CortexIPC exit 0); hot-path gate exits 0; SC#2 grep (`SCM_RIGHTS|cmsg(`) clean across CortexIPC/Sources + CortexCoreC — VERIFIED
- 11 Transport tests pass (5 RingTests + 4 DoorbellTests + 2 Plan-02-01 placeholders); 3 CortexCore tests still pass after ShmCheck removal — VERIFIED

## Next Phase Readiness

- **Plan 02-04 (harness) is unblocked:** the producer/consumer wiring contract is documented above; the only open item is exposing the ring fd for `FDChannel.send` (today `private let ownedFD`) — a one-line accessor in Plan 02-04.
- **Plan 02-03 (Session) is unblocked and file-disjoint** (it works in CortexIPCSession): the slot's reserved GCM-tag bytes and the payload-agnostic `write` are ready.
- **Blockers:** none. Both packages build clean, the hot-path gate is green, the SC#2 invariant is clean across CortexIPC/Sources + CortexCoreC, and 11 Transport tests pass.

---
*Phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm*
*Plan: 02 (Foundation-free CortexIPCTransport hot path — Wave 2)*
*Completed: 2026-06-20*
</content>
