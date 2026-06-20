---
phase: 2
slug: ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-20
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Derived from `02-RESEARCH.md` § Validation Architecture. **CI gates CORRECTNESS only; the SC#1 sub-µs timing claim is hardware-gated M4 evidence (D-18), never asserted in CI.**

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (Swift 6.2 default) for unit/codec/crypto/ring; XCTest host for the two-process `posix_spawn` harness (if chosen over a standalone exe) |
| **Config file** | none — in-language; `swift test` per package |
| **Quick run command** | `swift build --package-path Packages/CortexIPC && swift test --package-path Packages/CortexIPC` |
| **Full suite command** | `xcodebuild test -workspace Cortex.xcworkspace -scheme CortexMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` + `./Tools/scripts/hotpath-policy.sh` |
| **Estimated runtime** | ~60 s quick; ~5–10 min full (warm cache) |

---

## Sampling Rate

- **After every task commit:** Run `swift build --package-path Packages/CortexIPC && swift test --package-path Packages/CortexIPC` + `./Tools/scripts/hotpath-policy.sh`
- **After every plan wave:** Run the full `ci.yml` correctness harness on `macos-15`
- **Before `/gsd-verify-work`:** Full suite green + `sc1-evidence.md` (M4) + FD-pass + Keychain round-trip evidence committed
- **Max feedback latency:** 60 seconds (per-task)

---

## Per-Task Verification Map

> Plan/wave/task IDs are filled by the planner. Each requirement maps to an automated correctness check; SC#1 timing is the sole manual (hardware-gated) item.

| Req | Wave | Secure Behavior | Test Type | Automated Command | File Exists |
|-----|------|-----------------|-----------|-------------------|-------------|
| IPC-01 | 1 | shm ring opens/maps in App Group, fixed stride | unit | `swift test --package-path Packages/CortexIPC --filter RingTests` | ❌ W0 |
| IPC-01 / SC#4 | 1 | `CORTEX_SHM_NAME` ≤31 B; `CORTEX_CHANNEL_COUNT` `_Static_assert` | compile-time | `swift build --package-path Packages/CortexCore` (fails to compile if violated) | ❌ W0 (header) |
| IPC-02 | 1 | socketpair+`kqueue` `EVFILT_READ` doorbell delivers notification | unit + harness | harness exits 0; `kevent` returns the armed event | ❌ W0 |
| IPC-03 / SC#2 | 2 | FD passed via `mach_msg`+`MACH_MSG_PORT_DESCRIPTOR`; received fd maps same shm; **no `SCM_RIGHTS` in code** | harness + static | harness reads producer sentinel through passed fd; `! grep -rnE 'SCM_RIGHTS\|cmsg\(' Packages/CortexIPC/Sources` | ❌ W0 |
| IPC-04 | 2 | `Sample` round-trips; `channel_data.count == CORTEX_CHANNEL_COUNT*2`; `Float16` zero-copy rebind | unit | `swift test --filter SampleCodecTests` | ❌ W0 |
| IPC-05 | 2 | AES-GCM seal/open w/ HKDF per-direction subkeys + 96-bit deterministic nonce; tamper → `open` throws | unit | `swift test --filter CryptoTests` | ❌ W0 |
| IPC-06 / SC#3 | 2 | key round-trips Keychain w/ `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (data-protection keychain; `kCFBooleanTrue`) | unit (+ CF#1 spike) | `swift test --filter KeychainTests` | ❌ W0 (gated by access-group spike) |
| IPC-07 / SC#1 | 3 | sub-µs round-trip (shm-polled `seq`, ack-bounce), p99 on M4 | **manual (hardware-gated)** | `sc1-evidence.md`: n≥100k, p50/p99/σ, ~1k warm-up discarded, QoS pinned | ❌ W0 |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Packages/CortexIPC/Package.swift` — split into `CortexIPCTransport` + `CortexIPCSession`; add `FlatBuffers` dep
- [ ] `Packages/CortexIPC/Tests/CortexIPCTransportTests/RingTests.swift` — shm ring open/map/stride
- [ ] `Packages/CortexIPC/Tests/CortexIPCSessionTests/{SampleCodecTests,CryptoTests,KeychainTests}.swift`
- [ ] two-process harness (standalone exe or XCTest host that `posix_spawn`s the child) covering IPC-02/03/07
- [ ] `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h` — add `CORTEX_CHANNEL_COUNT` `_Static_assert`
- [ ] `Tools/scripts/hotpath-policy.sh` — re-scope `DIRS_ARRAY` to `CortexIPCTransport` (CF#4)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Sub-µs round-trip @ p99 | IPC-07 / SC#1 | CI runner is M1; the claim is M4. CI can only attest correctness (D-18). | On M4 + Xcode 26.3: run the harness n≥100k frames, discard ~1k warm-up, pin `QOS_CLASS_USER_INTERACTIVE`, record p50/p99/σ + histogram + raw samples → `sc1-evidence.md` |
| Cross-process Keychain access-group sharing | IPC-06 / SC#3 | Bare-`tool` daemon entitlement backing is uncertain under free/local signing (CF#1). | CF#1 spike under Team 57YW6M29S7; if it fails, fall back to single-process round-trip + key delivery over the secure channel (defer access-group sharing to Phase 8) |

---

## Validation Sign-Off

- [ ] Every planner task has an `<automated>` verify OR a Wave 0 dependency (only SC#1 timing + CF#1 sharing are manual)
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60 s
- [ ] `nyquist_compliant: true` set in frontmatter (after planner fills task IDs)

**Approval:** pending
