---
phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm
plan: 04
subsystem: infra
tags: [mach-rendezvous, posix-spawn, special-port, fileport, two-process-harness, aes-gcm, anti-replay, ack-bounce, foundation-free, hotpath-gate]

# Dependency graph
requires:
  - phase: 02-01
    provides: "CortexIPCTransport (Foundation-free) + CortexIPCSession split; CF#3 rendezvous verdict (PASS, posix_spawnattr_setspecialport_np @ TASK_BOOTSTRAP_PORT); CF#1 verdict (FAIL → key-over-channel fallback)"
  - phase: 02-02
    provides: "ShmRing (init create/adoptingFD, write/pollLatest/ack/pollAck), Doorbell, FDChannel (send/receive, mach_msg+fileport, geometry validation), cortex_fdmsg.c; flagged the private ownedFD handoff gap"
  - phase: 02-03
    provides: "SampleCodec (encode/decode, FlatBuffers Sample), SessionCrypto (AES-GCM + HKDF subkeys + seq-nonce, fail-closed), SessionKeychain (data-protection round-trip, CF#1 fallback, Backend test-seam), all nonisolated"
provides:
  - "cortex_rendezvous.h/.c (CortexCoreC): CF#3 Mach rendezvous via posix_spawnattr_setspecialport_np @ TASK_BOOTSTRAP_PORT (the proven spike mechanism) + a one-message reply-port flip so the shm fd flows producer(parent)→consumer(child); NO bootstrap_register, NO launchd plist, NO socket control-message rights path"
  - "Rendezvous.swift (CortexIPCSession, nonisolated): parentPrepare/parentAwaitReply/childAcquire wrappers with documented producer→consumer directionality + bounded reply timeout (T-02-04-05)"
  - "SessionKeyChannel.swift (CortexIPCSession, nonisolated): CF#1-fallback delivery of the 256-bit secret as an inline mach_msg over the rendezvous channel (no fileport, no fd, no control-message path) — sent BEFORE the fd message"
  - "Producer (Apps/CortexDaemon): generate+store key (SC#3), encrypt FlatBuffers Samples (seq-nonce), write [len||ct||tag] into ring slots, ring doorbell, busy-poll the D-02 ack-bounce (bounded)"
  - "HarnessConsumer (CortexIPCSession, nonisolated): receive key+fd, map ring, busy-poll, fail-closed AES-GCM open, decode + verify decoded==sent, forward-only lastSeen anti-replay (T-02-04-04), ack-bounce; runChild + reusable consumeOne/consumeLoop"
  - "Harness (Apps/CortexDaemon): runParent orchestrator — posix_spawn self consume via CF#3, hand off, produce, reap"
  - "main.swift rewritten as the Phase-2 producer entry point (argv produce/consume dispatch); ZERO references to the deleted Phase-1 shm-open helper type"
  - "HarnessE2ETests (XCTest): testInProcessRoundTrip (always-on CI correctness gate, decoded==sent + all acked), testForwardOnlyAntiReplay (T-02-04-04), testTwoProcessSpawnRoundTrip (XCTSkip-guarded); no timing assertions (D-18)"
  - "ShmRing.fd public read-only accessor (closes the 02-02→02-04 ownedFD handoff gap, gate-clean)"
  - "ShmRing slot stride now reserves FlatBuffers framing headroom (Rule-1 geometry fix): stride 224→288 so the encrypted framed Sample + GCM tag fits"
affects: [phase-02-plan-05-benchmark, phase-03-pthread-hotpath, phase-04-decoder, phase-08-distribution-enrollment]

# Tech tracking
tech-stack:
  added:
    - "posix_spawnattr_setspecialport_np + task_get_special_port (TASK_BOOTSTRAP_PORT=4) Mach rendezvous — the non-deprecated spawn-injection path (D-08 ADOPT-WITH-RATIONALE)"
    - "Reply-port handshake (one COMPLEX mach_msg carrying a MAKE_SEND port descriptor) to flip rendezvous directionality producer→consumer"
    - "Inline-bytes mach_msg (Swift, no C shim) for the 32-byte session-secret channel delivery (CF#1 fallback)"
  patterns:
    - "Empirical spike-mechanism verification before wiring: probed the naive receive-right injection (fails MACH_RCV_INVALID_NAME), the reply-port handshake (3/3 PASS), and the full package-C functions (3/3 PASS) before committing"
    - "Variable-length wire frame → explicit length prefix: FlatBuffers omits default/zero scalar fields, so the encoded Sample size varies (216 B zero vs 248 B non-zero); the slot carries [4B LE ct length][ct][16B tag] rather than a fixed split"
    - "Forward-only seq watermark as anti-replay: deterministic seq-nonce means a replayed older seq reproduces a used (key,nonce); the consumer only advances lastSeen and ignores non-increasing seq"
    - "Off-main-actor producer: replicate the tiny mach_absolute_time→ns conversion inline rather than call MainActor-isolated Time.machAbsoluteNanoseconds() from the nonisolated producer"
    - "Two-tier harness: always-on in-process correctness gate (no spawn flakiness) + XCTSkip-guarded two-process spawn proof (D-18: CI gates correctness; the timing claim is Plan 02-05)"

key-files:
  created:
    - "Packages/CortexCore/Sources/CortexCoreC/include/cortex_rendezvous.h"
    - "Packages/CortexCore/Sources/CortexCoreC/cortex_rendezvous.c"
    - "Packages/CortexIPC/Sources/CortexIPCSession/Rendezvous.swift"
    - "Packages/CortexIPC/Sources/CortexIPCSession/SessionKeyChannel.swift"
    - "Packages/CortexIPC/Sources/CortexIPCSession/HarnessConsumer.swift"
    - "Apps/CortexDaemon/Producer.swift"
    - "Apps/CortexDaemon/Harness.swift"
    - "Packages/CortexIPC/Tests/CortexIPCSessionTests/HarnessE2ETests.swift"
  modified:
    - "Apps/CortexDaemon/main.swift (rewritten: Phase-1 shm-open stub → Phase-2 producer entry point)"
    - "Packages/CortexIPC/Sources/CortexIPCTransport/ShmRing.swift (fd accessor + framing-headroom stride fix)"
    - "Packages/CortexIPC/Tests/CortexIPCTransportTests/RingTests.swift (constantStride updated for framing headroom)"
    - "project.yml (CortexDaemon now depends on CortexIPCTransport + CortexIPCSession)"

key-decisions:
  - "Harness form = SELF-SPAWNING ARGV-DISPATCHED DAEMON. main.swift dispatches produce (parent → Harness.runParent) vs consume (child → HarnessConsumer.runChild); the same binary is both producer and posix_spawn'd consumer. The always-on CI gate is the in-process HarnessE2ETests; the binary's two-process flow is the local/Plan-02-05 proof. Harness.runParent lives in the Apps target (it drives Producer, also in Apps); HarnessConsumer lives in CortexIPCSession so the in-process test reuses it without the Apps target."
  - "FINAL fd directionality: PARENT(producer) holds a SEND right, CHILD(consumer) holds a RECEIVE right, via a reply-port handshake. posix_spawnattr_setspecialport_np injects ONLY a SEND right into the child (a direct receive-right injection was empirically verified to fail with MACH_RCV_INVALID_NAME 0x10004002), so the spike's child=send/parent=receive bootstrap direction is fixed. The child therefore advertises its own reply port (one bootstrap mach_msg carrying the reply send right); the parent uses that reply SEND right as FDChannel.send's dest, the child receives on its reply RECEIVE right. Net: fd flows parent→child using only the proven injection primitive + the same mach_msg machinery FDChannel speaks."
  - "CF#1 key delivery = OVER THE CHANNEL (fallback). The consumer does NOT load the secret from a shared Keychain access group (un-backable under the free team). The producer sends the 32-byte secret as a SECOND inline mach_msg on the rendezvous port BEFORE the fd message (FIFO per port guarantees ordering); the consumer receives key then fd. The producer still stores the secret single-process in the Keychain (SC#3). Access-group sharing is deferred to Phase 8."
  - "Anti-replay = forward-only lastSeen watermark (T-02-04-04). The consumer accepts only strictly-increasing seq; a replayed/stale seq (which would reproduce a used (key,nonce)) is ignored, never decoded/acked. testForwardOnlyAntiReplay proves a re-poll at the current watermark stalls (no re-acceptance)."
  - "Slot wire layout = [4B little-endian ciphertext length][ciphertext][16B GCM tag]. A FlatBuffers Sample is VARIABLE-length (it omits default/zero scalar fields: 216 B for zero ts_ns/seq/payload vs 248 B for non-zero), so a fixed-length split is incorrect; the explicit length prefix is required."

patterns-established:
  - "CF#3 rendezvous + reply-port flip is the cross-process capability bootstrap for the whole IPC channel — reused by Plan 02-05's benchmark to spawn the consumer."
  - "The in-process consumeOne (decode + verify + anti-replay + ack) is the shared correctness kernel both the spawned child loop and the CI gate run."

requirements-completed: [IPC-02, IPC-03, IPC-07]

# Metrics
duration: 22min
completed: 2026-06-20
---

# Phase 2 Plan 04: Two-Process Proof Harness (CF#3 rendezvous + producer/consumer + HarnessE2ETests) Summary

**The IPC primitive becomes a working, verifiable transport: a CF#3 Mach rendezvous (posix_spawnattr_setspecialport_np + a reply-port flip) hands the shm fd parent→child, the rewritten daemon producer encrypts FlatBuffers Samples into the ring and the spawned consumer decrypts + verifies decoded==sent + ack-bounces — proven end-to-end 3/3 across real processes and gated in CI by an always-on in-process correctness test (D-18 correctness-only; the sub-µs M4 timing claim is Plan 02-05).**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-06-20T07:31Z
- **Completed:** 2026-06-20T07:54Z
- **Tasks:** 3 / 3 (fully autonomous; no checkpoint — all tasks type=auto on the signing-capable M4)
- **Files created/modified:** 12 (8 created, 4 modified)

## Accomplishments

- **Task 1 — CF#3 rendezvous (IPC-03):** `cortex_rendezvous.h/.c` (CortexCoreC) ports the proven spike mechanism — `posix_spawnattr_setspecialport_np(attr, <send right>, TASK_BOOTSTRAP_PORT)` (parent) + `task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &p)` (child), the non-deprecated path validated 3/3 in Plan 02-01. NO `bootstrap_register`, NO launchd plist, NO socket control-message rights path. `Rendezvous.swift` (nonisolated) wraps it with documented producer→consumer directionality. The shm fd flows parent→child via a one-message reply-port handshake (see Deviations / directionality below).
- **Task 2 — Producer + daemon rewrite (IPC-02/03/05, SC#3):** `Producer.swift` (Apps) generates the 256-bit secret (D-14), stores it single-process in the data-protection Keychain (SC#3), opens the ring (create), encrypts each FlatBuffers Sample with the seq-derived nonce (D-16), writes `[len||ct||tag]` into the next slot (release-store), rings the doorbell, and busy-polls the D-02 ack-bounce (bounded — T-02-04-05). `main.swift` is fully rewritten as the argv-dispatched producer entry point with ZERO references to the deleted Phase-1 shm-open helper type. The authorized `ShmRing.fd` accessor (Rule-2) closes the 02-02→02-04 handoff gap, gate-clean.
- **Task 3 — Consumer harness + HarnessE2ETests (IPC-07 correctness, SC#2/SC#3 runtime):** `HarnessConsumer.swift` (nonisolated) receives the key over the channel (CF#1 fallback) then the shm fd (SC#2), maps the ring via `adoptingFD`, busy-polls (the CF#2 path), opens each AES-GCM box fail-closed, decodes the Sample, verifies `decoded == sent` (seq + deterministic channel pattern), applies the forward-only anti-replay check (T-02-04-04), and ack-bounces (D-02). `HarnessE2ETests` (XCTest): `testInProcessRoundTrip` verifies 256 frames decoded==sent + all acked (the always-on CI gate), `testForwardOnlyAntiReplay` proves the watermark blocks replays, `testTwoProcessSpawnRoundTrip` is XCTSkip-guarded. No timing assertions (D-18).
- **End-to-end proof:** The REAL two-process flow was verified 3/3 deterministic via a temporary SwiftPM executable (built, run, reverted): parent prepares the rendezvous → posix_spawns the child → child acquires its reply right → parent receives the child's reply port → parent sends the key over the channel + the fd via FDChannel → parent produces 64 encrypted frames → child receives the key, maps the SAME shm from the passed fd, decrypts, **verifies 64/64 decoded==sent**, acks each → parent observes the ack-bounce → child exits 0.
- **Full suite green:** `swift test --package-path Packages/CortexIPC` = 5 Swift Testing suites (26 tests) + the XCTest HarnessE2ETests (3 tests, 1 XCTSkip) all pass. Hot-path gate exits 0; the SC#2 invariant (`SCM_RIGHTS|cmsg(`) is clean across CortexIPC/Sources + CortexCoreC + Apps.

## Harness form + final fd directionality

- **Harness form:** a self-spawning, argv-dispatched daemon. `main.swift` runs `produce` (parent) or `consume` (child). `Harness.runParent` (Apps target) orchestrates the parent (rendezvous → spawn → handoff → produce → reap); `HarnessConsumer.runChild` (CortexIPCSession) is the child. The in-process `HarnessE2ETests` is the always-on CI correctness gate (no spawn flakiness on the M1 runner); the binary's two-process flow is the local / Plan-02-05 proof.
- **fd directionality:** **parent(producer) = SEND right, child(consumer) = RECEIVE right.** `posix_spawnattr_setspecialport_np` injects exactly a SEND right into the child (the spike direction; a direct receive-right injection was empirically verified to fail with `MACH_RCV_INVALID_NAME 0x10004002`). To flow the fd parent→child (FDChannel.send needs a SEND dest, FDChannel.receive needs a RECEIVE rcv), the child advertises its OWN reply port via ONE bootstrap mach_msg carrying the reply port's send right in a `MACH_MSG_PORT_DESCRIPTOR`; the parent uses that reply SEND right as `FDChannel.send`'s `dest`, and the child receives on its reply RECEIVE right. This keeps the spike-proven injection primitive and reuses the exact mach_msg + port-descriptor machinery FDChannel already speaks.

## CF#1 key delivery + anti-replay

- **CF#1 branch = key-over-channel (fallback).** `SessionKeyChannel.send/receive` carry the 256-bit secret as a SECOND inline mach_msg on the rendezvous port, sent BEFORE the fd message (Mach FIFO-per-port guarantees the consumer receives key-then-fd). No fileport, no fd, no socket control-message path — a bounded 32-byte inline payload only. The producer still STORES the secret single-process in the data-protection Keychain (SC#3, `SessionKeychain.store`); cross-process DELIVERY is over the channel. Access-group sharing is deferred to Phase 8 (enrollment), at which point this path is removed (T-02-04-03 disposition).
- **Anti-replay = forward-only `lastSeen` (T-02-04-04).** The deterministic seq-nonce means a replayed older seq reproduces a used (key,nonce); AES-GCM authenticates every frame (open() throws on tamper), and the consumer additionally accepts only STRICTLY-increasing seq, ignoring (never decoding/acking) non-increasing seq. `testForwardOnlyAntiReplay` proves a re-poll at the current watermark stalls instead of re-accepting.

## In-process vs two-process test split (D-18 rationale)

- **`testInProcessRoundTrip` (always-on):** one process, lock-step — the producer-side logic is inline (SampleCodec → SessionCrypto.seal → packSlot → ShmRing.write) and `HarnessConsumer.consumeOne` maps the SAME ring, verifies decoded==sent for EVERY one of 256 frames, and acks each (asserted via `pollAck`). Unique shm name + `shm_unlink` teardown. This is the deterministic CI correctness gate — no spawn flakiness on the macos-15/M1 runner.
- **`testTwoProcessSpawnRoundTrip` (XCTSkip-guarded):** the real D-07 proof via `posix_spawn` + CF#3. The daemon/consumer binary is not resolvable from the swift-test bundle under `swift test`, so the test XCTSkips (CI stays green on the in-process gate). The Xcode-built daemon exercises the spawn path locally / in Plan 02-05.
- **D-18:** neither test contains a timing/latency assertion — CI gates CORRECTNESS only; the sub-µs M4 claim is owned by Plan 02-05.

## Confirmation: main.swift has zero ShmCheck references

`Apps/CortexDaemon/main.swift` was fully rewritten from the Phase-1 shm-open verification stub (which called the deleted `ShmCheck.openSharedRegion`) into the Phase-2 producer entry point. It contains ZERO references to that helper type (verified by grep) and dispatches `produce`/`consume`. The daemon is now the Phase-2 producer + posix_spawn'd consumer.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Plan gap, authorized] Added `ShmRing.fd` public read-only accessor**
- **Found during:** Task 2 (Producer needs the shm fd for FDChannel.send; `ownedFD` was `private let`)
- **Issue:** The 02-02-SUMMARY explicitly flagged this handoff gap; the plan AUTHORIZED a minimal gate-clean accessor.
- **Fix:** Added `public var fd: Int32 { ownedFD }` (returns the real fd for a created ring, -1 for an adopted/borrowed one). No `import Foundation`, no forbidden tokens.
- **Files modified:** `Packages/CortexIPC/Sources/CortexIPCTransport/ShmRing.swift`
- **Verification:** hot-path gate exits 0; RingTests 5/5 still pass.
- **Committed in:** `757d6c7` (Task 2)

**2. [Rule 1 - Bug] ShmRing slot stride omitted FlatBuffers framing → encrypted frame overflowed the slot**
- **Found during:** Task 3 (in-process test crashed: Array index out of range / GCM authenticationFailure)
- **Issue:** The Plan 02-02 stride reserved only the bare f16 payload: `roundUp16(8 + CHANNEL_COUNT*2 + 16) = 224`. But the encrypted WIRE frame is the FlatBuffers-encoded Sample (216 B for 96 channels) + 16 B tag = 232 B, which overflowed the 224 B slot; `ShmRing.write` clamps to slotStride, silently TRUNCATING the ciphertext so AES-GCM `open()` failed on the consumer.
- **Fix:** Added `ShmRingLayout.flatBuffersFramingHeadroom = 64` to the stride formula → stride 224→288 (holds 232 B with margin). Updated `RingTests.constantStride` to include the headroom. Gate-clean (no forbidden tokens). This is a correctness requirement for the plan's entire deliverable, scoped to the stride only.
- **Files modified:** `Packages/CortexIPC/Sources/CortexIPCTransport/ShmRing.swift`, `Packages/CortexIPC/Tests/CortexIPCTransportTests/RingTests.swift`
- **Verification:** hot-path gate 0; all RingTests + the in-process round trip pass; the two-process probe verified 64/64.
- **Committed in:** `7a91ab3` (Task 3)

**3. [Rule 1 - Bug] FlatBuffers Sample is variable-length → fixed-length slot split was wrong**
- **Found during:** Task 3 (in-process test: ciphertext length 248 ≠ probed 216)
- **Issue:** My first split used a constant `encodedFrameLength` probed from a zero-pattern encode (216 B). But FlatBuffers omits default/zero scalar fields, so a real frame with non-zero ts_ns/seq/payload encodes longer (248 B). A fixed-length split mis-bounds the ciphertext → GCM failure.
- **Fix:** Defined the slot payload as `[4B LE ciphertext length][ciphertext][16B tag]` (`HarnessConsumer.packSlot` / the length-prefix parse in `consumeOne`); the producer and the in-process test both use `packSlot`. Removed the obsolete constant.
- **Files modified:** `Packages/CortexIPC/Sources/CortexIPCSession/HarnessConsumer.swift`, `Apps/CortexDaemon/Producer.swift`, `Packages/CortexIPC/Tests/CortexIPCSessionTests/HarnessE2ETests.swift`
- **Verification:** in-process round trip verifies 256/256; two-process probe 64/64.
- **Committed in:** `7a91ab3` (Task 3)

**4. [Rule 3 - Blocking] CortexDaemon target lacked the CortexIPC dependency**
- **Found during:** Task 2 (Producer/main.swift import CortexIPCTransport + CortexIPCSession; the daemon target depended only on CortexCore)
- **Issue:** Without the dependency the Plan 02-05 daemon xcodebuild cannot compile the producer/harness.
- **Fix:** Added `CortexIPCTransport` + `CortexIPCSession` products to the CortexDaemon target in `project.yml` (the bare CortexIPC product was split in Plan 02-01, so both products are named). Validated with `xcodegen generate` (the .xcodeproj is gitignored, not committed).
- **Files modified:** `project.yml`
- **Verification:** `xcodegen generate` exits 0; daemon Apps sources type-check clean against the package modules under `-swift-version 6`.
- **Committed in:** `757d6c7` (Task 2)

**5. [Rule 1 - Bug] Producer called MainActor-isolated Time.machAbsoluteNanoseconds() from a nonisolated context**
- **Found during:** Task 3 (type-checking the Apps daemon sources)
- **Issue:** `Time.machAbsoluteNanoseconds()` is MainActor-isolated (CortexCore default isolation); `Producer.produce` is nonisolated (the producer runs off the main actor, mirroring the hot-path regime), so the call errored under Swift 6 strict concurrency.
- **Fix:** Replicated the identical `mach_absolute_time()`→ns conversion inline in `Producer.nowNanos()` (Darwin, nonisolated) — no MainActor hop, no change to CortexCore.
- **Files modified:** `Apps/CortexDaemon/Producer.swift`
- **Verification:** daemon sources type-check clean.
- **Committed in:** `7a91ab3` (Task 3)

**6. [Rule 1 - Literal-token-grep contradiction] Reworded comments embedding `SCM_RIGHTS` / `ShmCheck`**
- **Found during:** Task 2 (the `! grep ShmCheck` acceptance) and Task 3 (the SC#2 `! grep SCM_RIGHTS|cmsg(` invariant)
- **Issue:** Comments documenting "NO SCM_RIGHTS" / "replaces the ShmCheck stub" embed the literal tokens the grep gates flag, even though the code has neither (the exact Plan 02-02 precedent for Doorbell). The grep cannot read intent.
- **Fix:** Reworded the comments to describe the no-rights-transfer invariant / the Phase-1 shm-open helper without the literal tokens. The code genuinely uses mach_msg + fileport (no socket control message) and zero references to the deleted helper.
- **Files modified:** `Apps/CortexDaemon/main.swift`, `Apps/CortexDaemon/Producer.swift`, `Packages/CortexIPC/Sources/CortexIPCSession/HarnessConsumer.swift`, `Packages/CortexIPC/Sources/CortexIPCSession/SessionKeyChannel.swift`
- **Verification:** `! grep 'ShmCheck' main.swift` passes; `! grep -rE 'SCM_RIGHTS|cmsg(' Sources CortexCoreC Apps` clean.
- **Committed in:** `757d6c7` (Task 2) + `7a91ab3` (Task 3)

### Authorized scope additions (beyond the plan's declared files_modified)

- **`Packages/CortexIPC/Sources/CortexIPCSession/SessionKeyChannel.swift` (new):** the CF#1-fallback key-over-channel helper. The plan's binding directive explicitly authorized delivering the secret as "a second mach_msg before the first frame" — this is that mechanism, factored into a small focused file used by both the producer (send) and the consumer (receive).
- **`Apps/CortexDaemon/Harness.swift` (new):** the parent orchestrator (`runParent`). main.swift (Task 2) references it; it must live in the Apps target because it drives `Producer` (which CortexIPCSession cannot import). HarnessConsumer (consumer logic) stays in CortexIPCSession so the in-process test reuses it without the Apps target.
- **`project.yml`:** see Deviation 4.

---

**Total deviations:** 6 auto-fixed (2 geometry/encoding correctness bugs [Rule 1], 1 concurrency bug [Rule 1], 1 literal-token rewording [Rule 1], 1 plan-gap accessor [Rule 2, authorized], 1 blocking dependency [Rule 3]) + 2 authorized scope additions.
**Impact on plan:** The rendezvous mechanism, the producer/consumer wiring, the CF#1 key-over-channel fallback, the forward-only anti-replay, the in-process/two-process test split, and the zero-ShmCheck daemon rewrite are exactly as the plan specified. Deviations 2 and 3 are genuine cross-plan correctness bugs (the Plan 02-02 stride and a FlatBuffers variable-length assumption) that the harness — the plan's entire purpose — could not pass without; they are scoped narrowly and fully tested. The two-process D-07 proof was validated 3/3 on real hardware.

## Threat Flags

None — no security surface beyond the plan's `<threat_model>` was introduced. The key-over-channel path (SessionKeyChannel) is exactly the CF#1-fallback surface the threat register anticipated (T-02-04-03, disposition accept-mitigated, removed in Phase 8); the forward-only anti-replay implements the T-02-04-04 mitigation; the bounded ack-poll + waitpid implement T-02-04-05; no secrets are logged (T-02-04-06).

## Known Stubs

None. The two-process spawn test is XCTSkip-guarded (not a stub — the real path is exercised by the Xcode-built daemon / Plan 02-05, and was verified 3/3 here via a temporary SwiftPM probe). All production sources are complete.

## Cross-Plan Notes

**For Plan 02-05 (SC#1 benchmark + CI):**
- **The benchmark drives THIS producer/consumer on the shm-polled path (CF#2).** Plan 02-05 should reuse `Harness.runParent` / `HarnessConsumer` (or the same primitives) to spawn the consumer via the CF#3 rendezvous, then time the busy-poll `pollLatest` + ack-bounce (NOT a blocking kevent round-trip, NOT the rendezvous/handoff which is one-shot setup) at n≥100k on M4, recording `sc1-evidence.md`.
- **CI correctness gates (wire these):** (1) the in-process `HarnessE2ETests.testInProcessRoundTrip` (always-on, decoded==sent + acked); (2) the no-rights-transfer grep `! grep -rnE 'SCM_RIGHTS|cmsg\(' Packages/CortexIPC/Sources Packages/CortexCore/Sources/CortexCoreC` (SC#2); (3) the hot-path gate.
- **Daemon xcodebuild:** the CortexDaemon target now depends on both CortexIPC products and the Apps sources type-check under Swift 6; Plan 02-05's daemon scheme build will compile `main.swift`/`Producer.swift`/`Harness.swift`. The two-process `testTwoProcessSpawnRoundTrip` will RUN (not skip) when the daemon binary is resolvable next to the test bundle.
- **Slot layout for the benchmark:** the slot payload is `[4B LE ct length][ct][16B tag]`; the stride is now 288 (framing headroom added). A benchmark that writes raw bytes can use the full slotStride.

**For Plan 02-01 verdict reconciliation:** the CF#3 spike's child→parent direction was flipped to parent→child via a reply-port handshake (the spike's `setspecialport_np` injection is unchanged; only which side ends up with send vs receive differs). Documented in `cortex_rendezvous.h`/`.c` and `Rendezvous.swift`.

## Self-Check: PASSED

- All 8 created source/test files exist on disk (cortex_rendezvous.h/.c, Rendezvous.swift, SessionKeyChannel.swift, HarnessConsumer.swift, Producer.swift, Harness.swift, HarnessE2ETests.swift) + this SUMMARY — VERIFIED
- All 3 task commits exist (`5d55a35`, `757d6c7`, `7a91ab3`) — VERIFIED via `git log`
- Modified files reflect their changes: ShmRing.fd accessor present, main.swift has zero ShmCheck references, the framing-headroom stride fix is in place — VERIFIED
- Both packages build (CortexCore + CortexIPC exit 0); full CortexIPC test suite green (5 Swift Testing suites / 26 tests + XCTest HarnessE2ETests 3 tests / 1 XCTSkip / 0 failures); hot-path gate exits 0; SC#2 grep (`SCM_RIGHTS|cmsg(`) clean across CortexIPC/Sources + CortexCoreC + Apps — VERIFIED
- Daemon Apps sources type-check clean under `-swift-version 6` (Plan 02-05 xcodebuild readiness); the two-process flow verified 3/3 end-to-end via a temporary SwiftPM probe (reverted) — VERIFIED

---
*Phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm*
*Plan: 04 (Two-process proof harness — Wave 3)*
*Completed: 2026-06-20*
