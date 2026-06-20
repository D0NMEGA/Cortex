---
phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm
verified: 2026-06-20T03:35:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
deferred:
  - truth: "Session key round-trips Keychain and is shared cross-process via access group"
    addressed_in: "Phase 8"
    evidence: "Phase 8 goal: 'Apple BCI HID Integration, Distribution & v0 Ship' — D-14/D-15 cross-process Keychain access-group sharing explicitly deferred to Phase 8 (enrollment); single-process round-trip + key-over-mach_msg satisfies SC#3/IPC-06 in Phase 2 (CF#1 FALLBACK, 02-SPIKES.md)"
  - truth: "xcodebuild of CortexDaemon Xcode target succeeds (Option A benchmark path)"
    addressed_in: "Phase 3"
    evidence: "Known follow-up: 'Float16 is unavailable in macOS' in generated Xcode project — deployment/arch config issue, NOT a code defect. SwiftPM builds clean; CI uses swift build/test. sc1-evidence.md §Anomalies #2 documents this and flags it for Phase 3 resolution."
---

# Phase 2: IPC Primitive Verification Report

**Phase Goal:** A sample frame leaves the acquisition daemon and arrives in the app process in sub-µs, encrypted, with the FD passed via `mach_msg` — the "thinnest viable" transport that the decoder will later sit on top of.
**Verified:** 2026-06-20T03:35:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A POSIX shm ring with names ≤31 bytes moves frames between processes (IPC-01) | ✓ VERIFIED | `ShmRing.swift` uses `cortex_shm_open` + `mmap(MAP_SHARED)`; `cortex_shm.h` has `_Static_assert(sizeof(CORTEX_SHM_NAME) <= 32, ...)`; `CORTEX_SHM_NAME = "/cortex.samples"` (15 bytes); RingTests 5/5 pass |
| 2 | kqueue + recvmsg socket pair is the idle/control-plane wake (IPC-02) | ✓ VERIFIED | `Doorbell.swift`: `socketpair(AF_UNIX, SOCK_STREAM)` + `kqueue` EVFILT_READ + `recvmsg` with single iovec, no control buffer; DoorbellTests 2/2 pass; FD_CLOEXEC + SO_NOSIGPIPE hardened |
| 3 | Cross-process FD passing uses mach_msg + MACH_MSG_PORT_DESCRIPTOR, zero SCM_RIGHTS (IPC-03/SC#2) | ✓ VERIFIED | `cortex_fdmsg.c`: `fileport_makeport` / `fileport_makefd` + COMPLEX mach_msg + `MACH_MSG_PORT_DESCRIPTOR`; SC#2 grep clean (exit 1 = no matches); CI gate wired; CF#3 rendezvous via `posix_spawnattr_setspecialport_np` 3/3 deterministic |
| 4 | FlatBuffers Sample { ts_ns, channel_data:[ubyte], seq } codec serializes/deserializes f16 frames (IPC-04) | ✓ VERIFIED | `sample.fbs` schema present; `sample_generated.swift` vendored (flatc 25.12.19 == runtime); `SampleCodec.swift`: zero-copy Float16 rebind, `channel_data.count == CORTEX_CHANNEL_COUNT*2` invariant on encode AND decode, `getCheckedRoot` verifier; SampleCodecTests 5/5 pass |
| 5 | AES-GCM encryption via CryptoKit with HKDF-derived per-session per-direction keys (IPC-05) | ✓ VERIFIED | `SessionCrypto.swift`: `AES.GCM.seal/open`, `HKDF<SHA256>.expand` with distinct info labels per direction, 96-bit deterministic nonce = 4-byte prefix \|\| 8-byte big-endian seq, fail-closed; CryptoTests 6/6 pass including nonce-uniqueness and cross-direction isolation |
| 6 | Session key stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (IPC-06/SC#3) | ✓ VERIFIED | `SessionKeychain.swift`: `kSecUseDataProtectionKeychain = kCFBooleanTrue!` (CF#8) + `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; CF#1 fallback = single-process round-trip + key delivered over mach_msg channel; KeychainTests 5/5 pass; production query confirmed data-protection attributes |
| 7 | Round-trip latency sub-µs at p99 on M4-class hardware, with two-process correctness proven (IPC-07/SC#1) | ✓ VERIFIED | `sc1-evidence.md`: p50=167ns, **p99=208ns**, σ=89.7ns over n=199,000 QoS-pinned frames on M5 Pro (≥ M4 baseline), Xcode 26.3; 4.8× margin under 1000ns bar; sc1-histogram.txt + 199k-sample CSV committed; `testInProcessRoundTrip` 256 frames decoded==sent+all-acked; `testForwardOnlyAntiReplay` passes |

**Score:** 7/7 truths verified

---

### Deferred Items

Items not yet fully met but explicitly addressed in later milestone phases (do not count against score).

| # | Item | Addressed In | Evidence |
|---|------|-------------|---------|
| 1 | Cross-process Keychain access-group sharing (D-14/D-15 full contract) | Phase 8 | Phase 8 goal covers enrollment; CF#1 = FAIL under free team (02-SPIKES.md); single-process + key-over-mach_msg satisfies SC#3/IPC-06 now |
| 2 | `xcodebuild` CortexDaemon Xcode target (Option A benchmark path) | Phase 3 | `Float16 is unavailable in macOS` is a project-config issue, not a code defect; `swift build`/`swift test` both clean; sc1-evidence.md §Anomalies #2 |

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|---------|--------|---------|
| `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h` | `_Static_assert` on `CORTEX_SHM_NAME` (≤32 bytes) and `CORTEX_CHANNEL_COUNT` bounds | ✓ VERIFIED | Two `_Static_assert` present; `CORTEX_CHANNEL_COUNT=96`; `CORTEX_SHM_NAME="/cortex.samples"` |
| `Packages/CortexIPC/Sources/CortexIPCTransport/ShmRing.swift` | Foundation-free shm ring with acquire/release busy-poll | ✓ VERIFIED | `cortex_shm_open` + `mmap(MAP_SHARED)`, `Synchronization.Atomic<UInt64>` over mmap'd region, `write`/`pollLatest`/`pollAck`; no `import Foundation` |
| `Packages/CortexIPC/Sources/CortexIPCTransport/Doorbell.swift` | socketpair + kqueue EVFILT_READ + recvmsg, no control buffer | ✓ VERIFIED | `socketpair(AF_UNIX, SOCK_STREAM)`, `kqueue`, `recvmsg` with single iovec; no SCM_RIGHTS/cmsg path |
| `Packages/CortexCore/Sources/CortexCoreC/cortex_fdmsg.c` | `fileport_makeport`/`fileport_makefd` + MACH_MSG_PORT_DESCRIPTOR, no SCM_RIGHTS | ✓ VERIFIED | Lines 25–104: fileport path confirmed; SCM_RIGHTS grep returns nothing |
| `Packages/CortexCore/Sources/CortexCoreC/cortex_rendezvous.c` | `posix_spawnattr_setspecialport_np` + `task_get_special_port` @ TASK_BOOTSTRAP_PORT | ✓ VERIFIED | Lines 66–133 confirmed; no `bootstrap_register`; no launchd plist |
| `Packages/CortexIPC/Schemas/sample.fbs` | `table Sample { ts_ns:ulong; channel_data:[ubyte]; seq:ulong }` | ✓ VERIFIED | Exact schema present; `root_type Sample` |
| `Packages/CortexIPC/Sources/CortexIPCSession/generated/sample_generated.swift` | Vendored flatc 25.12.19 Swift; `nonisolated` injected | ✓ VERIFIED | File exists; generator == runtime (CF#7); `nonisolated` injection via `gen-flatbuffers.sh` |
| `Packages/CortexIPC/Sources/CortexIPCSession/SampleCodec.swift` | Float16 zero-copy rebind, channel_data length invariant, getCheckedRoot | ✓ VERIFIED | Zero-copy `withMemoryRebound`, `CORTEX_CHANNEL_COUNT*2` assert on both encode and decode, `getCheckedRoot` verifier |
| `Packages/CortexIPC/Sources/CortexIPCSession/SessionCrypto.swift` | AES.GCM + HKDF<SHA256> per-direction + 96-bit deterministic nonce, fail-closed | ✓ VERIFIED | `HKDF<SHA256>.expand` with distinct info labels, `4-byte prefix \|\| 8-byte bigEndian(seq)`, plain `try` (no swallow) |
| `Packages/CortexIPC/Sources/CortexIPCSession/SessionKeychain.swift` | data-protection Keychain, kCFBooleanTrue, AfterFirstUnlock, Backend seam | ✓ VERIFIED | `kSecUseDataProtectionKeychain = kCFBooleanTrue!`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `.legacyFile` test seam |
| `Packages/CortexIPC/Sources/CortexIPCSession/HarnessConsumer.swift` | fail-closed AES-GCM open, forward-only anti-replay, ack-bounce | ✓ VERIFIED | `consumeOne`/`consumeLoop`; lastSeen watermark anti-replay; ack-bounce; `[len\|\|ct\|\|tag]` slot layout |
| `Apps/CortexDaemon/Producer.swift` | encrypt FlatBuffers Samples, write ring, ring doorbell, poll ack | ✓ VERIFIED | Generates 256-bit secret, `SessionKeychain.store`, `SampleCodec.encode`, `SessionCrypto.seal`, `ring.write`, doorbell, bounded ack-poll |
| `Apps/CortexDaemon/Benchmark.swift` | shm busy-poll + ack-bounce, QOS_CLASS_USER_INTERACTIVE pthreads, n≥100k, p50/p99/σ, no crypto/doorbell on timed path | ✓ VERIFIED | `pthread_create`, `QOS_CLASS_USER_INTERACTIVE`, `ring.write`/`pollAck`; grep confirms no `kevent`/`recvmsg`/`Doorbell`/`AES.GCM` |
| `.planning/.../sc1-evidence.md` | p50/p99/σ on M4-class, n≥100k, D-18 statement, honest disclosure | ✓ VERIFIED | p50=167ns, p99=208ns, σ=89.7ns, n=199,000; M5 Pro ≥ M4 disclosed; D-18 statement present |
| `sc1-histogram.txt` + `sc1-histogram.csv` | Committed artifacts, CSV has n=199k lines | ✓ VERIFIED | CSV: 199,001 lines (header + 199,000 samples); histogram header matches evidence |
| `Packages/CortexIPC/Tests/CortexIPCSessionTests/HarnessE2ETests.swift` | testInProcessRoundTrip (always-on), testForwardOnlyAntiReplay, testTwoProcessSpawnRoundTrip (XCTSkip) | ✓ VERIFIED | All three tests confirmed; no timing assertions |
| `.github/workflows/ci.yml` | CortexIPC test step, no-SCM_RIGHTS grep, no timing assertion | ✓ VERIFIED | Both gates present; no p99/latency vocabulary in file |
| `Tools/scripts/hotpath-policy.sh` | Polices CortexIPCTransport only (CF#4); exits 0 | ✓ VERIFIED | `DIRS_ARRAY=("Packages/CortexIPC/Sources/CortexIPCTransport")`; exits 0 on current codebase |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ShmRing.swift` | `cortex_shm_open` (CortexCoreC) | `import CortexCoreC`; direct C call | ✓ WIRED | `cortex_shm_open(name, oflag, 0o600)` at line 134; `mmap(MAP_SHARED)` at line 145 |
| `FDChannel.swift` | `cortex_fdmsg.c` | `cortex_fdmsg_send`/`cortex_fdmsg_recv` calls | ✓ WIRED | FDChannel imports CortexCoreC and calls both C functions |
| `cortex_rendezvous.c` | `posix_spawnattr_setspecialport_np` | Darwin API call at line 69 | ✓ WIRED | `posix_spawnattr_setspecialport_np(attr, boot, TASK_BOOTSTRAP_PORT)` confirmed |
| `Producer.swift` → `ShmRing` | Key stored via `SessionKeychain.store`, ring write via `ring.write` | Direct calls in `produce()` | ✓ WIRED | Confirmed in Producer.swift; key stored before any frame production (SC#3) |
| `HarnessConsumer.swift` → `ShmRing` | `adoptingFD` init from received fd | `ShmRing(adoptingFD:)` at consumer startup | ✓ WIRED | Consumer maps the SAME shm from the fd passed via FDChannel |
| `HarnessE2ETests` → `HarnessConsumer` | In-process round-trip uses `consumeOne` | Direct import + call in test | ✓ WIRED | `testInProcessRoundTrip` calls `consumeOne` 256 times; decodes+verifies+acks each |
| ci.yml → `swift test --package-path Packages/CortexIPC` | CortexIPC correctness gate step | Step at line 106 | ✓ WIRED | Step present with correct `--package-path`; comment confirms D-18 |
| ci.yml → no-SCM_RIGHTS grep | SC#2 structural gate over both source trees | Step at line 129 | ✓ WIRED | Covers `Packages/CortexIPC/Sources` AND `Packages/CortexCore/Sources/CortexCoreC` |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|-------------|--------|-------------------|--------|
| `HarnessConsumer.consumeOne` | `decoded` (DecodedSample) | `ShmRing.pollLatest` → `SessionCrypto.open` → `SampleCodec.decode` | Yes — ring poll acquires real ring bytes written by Producer | ✓ FLOWING |
| `testInProcessRoundTrip` | `verified` count (256 frames) | Inline producer-path: `SampleCodec.encode` → `SessionCrypto.seal` → `ring.write` | Yes — 256 real encrypted frames written and decoded | ✓ FLOWING |
| `Benchmark.runRoundTrip` | `samples[i]` (UInt64 ns) | `mach_absolute_time()` delta around `ring.write` + `pollAck` | Yes — 199,000 real nanosecond measurements; CSV committed | ✓ FLOWING |
| `sc1-histogram.csv` | 199,000 raw samples | `Benchmark.writeHistogram` from measured run | Yes — 199,001 lines verified by `wc -l` | ✓ FLOWING |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `swift build --package-path Packages/CortexCore` exits 0 | `swift build --package-path Packages/CortexCore` | "Build complete! (0.09s)" | ✓ PASS |
| `swift build --package-path Packages/CortexIPC` exits 0 | `swift build --package-path Packages/CortexIPC` | "Build complete! (0.12s)" | ✓ PASS |
| CortexCore 3 tests pass | `swift test --package-path Packages/CortexCore` | "3 tests … passed after 0.001 seconds" | ✓ PASS |
| CortexIPC 26 Swift Testing tests pass | `swift test --package-path Packages/CortexIPC` | "26 tests in 5 suites passed after 0.038 seconds" | ✓ PASS |
| HarnessE2ETests: in-process round-trip + anti-replay pass, two-process XCTSkips | `swift test --package-path Packages/CortexIPC` (XCTest) | testInProcessRoundTrip PASS, testForwardOnlyAntiReplay PASS, testTwoProcessSpawnRoundTrip SKIP (expected) | ✓ PASS |
| SC#2: no SCM_RIGHTS/cmsg in source trees | `grep -rnE 'SCM_RIGHTS\|cmsg\(' Packages/CortexIPC/Sources Packages/CortexCore/Sources/CortexCoreC Apps/CortexDaemon` | exit 1 (grep found nothing — this is the correct result) | ✓ PASS |
| Hot-path gate exits 0, scoped to CortexIPCTransport | `./Tools/scripts/hotpath-policy.sh` | "OK: hot-path policy clean across 1 dir(s)"; exit 0 | ✓ PASS |
| SC#4: _Static_assert on CORTEX_CHANNEL_COUNT and CORTEX_SHM_NAME | `grep -n '_Static_assert' cortex_shm.h` | Two `_Static_assert` confirmed (shm name length + channel count bounds) | ✓ PASS |
| No timing assertion in ci.yml (D-18) | `grep -iE 'assert.*(p99\|latency\|sub-.?s\|nanos)' ci.yml` | exit 1 (no matches — correct) | ✓ PASS |
| No Foundation import in CortexIPCTransport | `grep -rn 'import Foundation' Packages/CortexIPC/Sources/CortexIPCTransport/` | exit 1 (no matches — correct) | ✓ PASS |
| No ShmCheck references in daemon | `grep -n 'ShmCheck' Apps/CortexDaemon/main.swift Apps/CortexDaemon/Producer.swift` | exit 1 (no matches — correct) | ✓ PASS |
| Benchmark timed path has no kevent/Doorbell/AES.GCM | `grep -n 'kevent\|recvmsg\|Doorbell\|AES\.GCM' Apps/CortexDaemon/Benchmark.swift` | exit 0, zero matches (only comments describing their absence) | ✓ PASS |
| sc1-histogram.csv has 199,000 raw samples | `wc -l sc1-histogram.csv` | 199,001 lines (header + 199,000 samples) | ✓ PASS |

---

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|---------|
| IPC-01 | POSIX `shm_open` inside App Group container, names ≤31 bytes | ✓ SATISFIED | `ShmRing.swift` + `cortex_shm.h` _Static_assert; CORTEX_SHM_NAME = "/cortex.samples" (15 bytes); RingTests pass |
| IPC-02 | Raw kqueue + recvmsg socket pair primitive | ✓ SATISFIED | `Doorbell.swift`; DoorbellTests 2/2 pass; IPC-02 wording matched literally |
| IPC-03 | Cross-process FD passing via mach_msg + MACH_MSG_PORT_DESCRIPTOR using fileport_makeport | ✓ SATISFIED | `cortex_fdmsg.c` + `FDChannel.swift`; CF#3 rendezvous `posix_spawnattr_setspecialport_np`; SCM_RIGHTS grep clean |
| IPC-04 | FlatBuffers `Sample { ts_ns: u64, channel_data: [f16] }` schema | ✓ SATISFIED | `sample.fbs` + `SampleCodec.swift`; 5/5 SampleCodecTests |
| IPC-05 | AES-GCM via CryptoKit with HKDF-derived per-session keys | ✓ SATISFIED | `SessionCrypto.swift`; HKDF<SHA256> confirmed; 6/6 CryptoTests including nonce isolation |
| IPC-06 | Session keys stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | ✓ SATISFIED | `SessionKeychain.swift` production query confirmed; CF#1 fallback documented; 5/5 KeychainTests |
| IPC-07 | Measured round-trip latency sub-µs | ✓ SATISFIED | sc1-evidence.md: p99=208ns on M5 Pro ≥ M4; HarnessE2ETests correctness gate passes; 199k samples committed |

---

### Success Criteria Verification

| SC | Description | Status | Evidence |
|----|-------------|--------|---------|
| SC#1 | Round-trip latency sub-µs at p99 on M4, n≥100k | ✓ MET | p99=208ns, n=199,000, M5 Pro ≥ M4 baseline; 4.8× margin; committed histogram + 199k CSV |
| SC#2 | Cross-process FD handoff via mach_msg + MACH_MSG_PORT_DESCRIPTOR, no SCM_RIGHTS in code | ✓ MET | grep returns nothing across all three source trees; CI gate wired; fileport path confirmed in C |
| SC#3 | AES-GCM encrypted frames decrypt cleanly; key round-trips Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | ✓ MET | 256 frames decoded==sent in testInProcessRoundTrip; SessionKeychain production query verified; CF#1 fallback: single-process + key-over-mach_msg |
| SC#4 | shm name ≤31 bytes; unit-test/build fails if constant changed | ✓ MET | Two _Static_assert in cortex_shm.h: name ≤32 (incl NUL), CORTEX_CHANNEL_COUNT bounds; structural guarantee — precompile fails, no runtime needed |

---

### Anti-Patterns Found

| File | Pattern | Severity | Assessment |
|------|---------|----------|-----------|
| `Packages/CortexIPC/Sources/CortexIPCTransport/Placeholder.swift` | `public enum CortexIPCTransport {}` stub | ℹ️ Info | NOT a blocker — this is a linker sentinel, not a data-rendering stub. All real Transport code is in `ShmRing.swift`, `Doorbell.swift`, `FDChannel.swift` in the same directory. The file documents itself as a build placeholder. |

No blockers. No warnings. The linker sentinel is intentional and correctly documented.

---

### Human Verification Required

None. All observable truths are verifiable programmatically:

- SC#1 timing is backed by committed hardware-gated evidence (sc1-evidence.md + 199k CSV) with a reproducible runbook; the number does not require re-measurement to accept the phase.
- The two-process daemon binary path (XCTSkip in `swift test`) is expected behavior per D-18 — the correctness gate is the always-on in-process round-trip, which passed. The actual two-process spawn was verified 3/3 locally during execution (02-04-SUMMARY.md §Accomplishments).
- The `xcodebuild` CortexDaemon Xcode project config issue (`Float16 unavailable`) is a known follow-up (deferred above), not a blocker for this phase: CI uses `swift build`/`swift test` which both pass.

---

## Gaps Summary

No gaps found. All 7 IPC requirements satisfy their must-haves. All 4 Phase-2 Success Criteria are met. All builds pass, all tests pass (26 Swift Testing + HarnessE2ETests in-process + anti-replay), SC#2 grep is clean, hot-path gate exits 0, SC#4 _Static_assert is structural and compile-time enforced, SC#1 is hardware-gated committed evidence at p99=208ns (4.8× margin).

The two deferred items (cross-process Keychain access-group sharing → Phase 8; `xcodebuild` Xcode project config → Phase 3) are explicitly anticipated in the plan documents and do not affect any Phase 2 requirement or success criterion.

---

_Verified: 2026-06-20T03:35:00Z_
_Verifier: gsd-verifier_
