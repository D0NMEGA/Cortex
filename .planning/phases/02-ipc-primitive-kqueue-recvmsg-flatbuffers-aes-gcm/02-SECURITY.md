---
phase: 2
slug: ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-20
---

# Phase 2 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Daemon process → App process | posix_spawn'd child receives shm fd + session secret via mach_msg rendezvous (CF#3 path); kernel-mediated capability, no socket control-message path | 32-byte AES-256 session secret (inline mach_msg); shm fd (fileport in port descriptor) |
| Producer shm ring → Consumer shm ring | MAP_SHARED POSIX shm region; fixed-stride slots carry AES-GCM ciphertext+tag only; producer seq counter published with release ordering, consumer polled with acquire ordering | Encrypted FlatBuffers Sample frames (ciphertext + 16-byte GCM tag per slot) |
| CortexIPCTransport (hot path) → CortexIPCSession (orchestration) | Swift package boundary; hot-path target is Foundation-free (policed by hotpath-policy.sh); session target uses CryptoKit/Keychain | Decrypted [UInt8] plaintext handed off after AES-GCM open() |
| App process → macOS Keychain | Single-process data-protection Keychain item (kSecUseDataProtectionKeychain = kCFBooleanTrue, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly); cross-process access-group sharing deferred to Phase 8 | 256-bit session secret (stored by daemon; CF#1=FAIL → not shared via Keychain in Phase 2) |
| Mach bootstrap port (TASK_BOOTSTRAP_PORT) | posix_spawnattr_setspecialport_np injects send right into child at spawn; the bootstrap port carries only the rendezvous handshake, never frame data | Mach port right (send right → child); reply port send right (child → parent) |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-02-01-01 | Tampering | cortex_shm.h | mitigate | `_Static_assert(CORTEX_CHANNEL_COUNT > 0 && (CORTEX_CHANNEL_COUNT * 2) <= 65536)` at cortex_shm.h:44-48 — compile-time channel-count bounds enforcement | closed |
| T-02-01-02 | Elevation of Privilege | spike.entitlements | mitigate | Exact group `Y4A54395NZ.group.com.donovansantine.cortex.shared` in keychain-access-groups; no wildcard prefix — spike.entitlements:7 | closed |
| T-02-01-03 | Spoofing | cortex_rendezvous.c / rendezvous-spike/main.c | mitigate | `posix_spawnattr_setspecialport_np(attr, <send right>, TASK_BOOTSTRAP_PORT)` at cortex_rendezvous.c:69 and rendezvous-spike/main.c:94 — CF#3 ADOPT-WITH-RATIONALE | closed |
| T-02-01-04 | Information Disclosure | keychain-access-group-spike/main.swift | mitigate | Spike prints `returned_length` and `byte_match` boolean only — never actual secret bytes; main.swift:97-100 | closed |
| T-02-01-05 | Repudiation | hotpath-policy.sh | mitigate | `DIRS_ARRAY=("Packages/CortexIPC/Sources/CortexIPCTransport")` — CF#4 re-scope to Foundation-free hot-path target only; self-test override documented; hotpath-policy.sh:46 | closed |
| T-02-02-01 | Tampering | ShmRing.swift | mitigate | `producerSeq.store(seq, ordering: .releasing)` at ShmRing.swift:217; `producerSeq.load(ordering: .acquiring)` at ShmRing.swift:228; RingTests.orderingContract() proves end-to-end invariant | closed |
| T-02-02-02 | Spoofing | FDChannel.swift | mitigate | Geometry validation: `slotStride` / `ringBytes` mismatch closes received fd and throws at FDChannel.swift:70-74 | closed |
| T-02-02-03 | Denial of Service | cortex_fdmsg.c | mitigate | `strncpy(msg.shm_name, shm_name, sizeof(msg.shm_name) - 1)` + explicit NUL terminator at cortex_fdmsg.c:54-55; `shm_name[32]` fixed buffer in cortex_fdmsg.h | closed |
| T-02-02-04 | Information Disclosure | cortex_fdmsg.c | mitigate | Only `shm_fd` passed to `fileport_makeport`; no kqueue/socket fd sent; CF#5 invariant documented in cortex_fdmsg.h:7 | closed |
| T-02-02-05 | Denial of Service | Doorbell.swift | mitigate | `SO_NOSIGPIPE` set on both socket fds at Doorbell.swift:83 (via `harden`); DoorbellTests.noSigpipeOnClosedPeer() proves process survives dead peer | closed |
| T-02-02-06 | Elevation of Privilege | ShmRing.swift / Doorbell.swift / FDChannel.swift | mitigate | All three files import only `Darwin` (+`CortexCoreC` where needed), no `import Foundation`; hotpath-policy.sh polices the CortexIPCTransport target | closed |
| T-02-03-01 | Tampering | SessionCrypto.swift / CryptoTests.swift | mitigate | **HIGH** — 4-byte direction prefix ‖ 8-byte BE seq nonce at SessionCrypto.swift:110-115; HKDF<SHA256> per-direction subkeys at :83-88; fresh 256-bit secret per launch at :72. CryptoTests.nonceUniquenessAcrossSeq() probes 9 seq values (incl. boundaries 0, UInt64.max) and asserts `seen.count == seqs.count`; CryptoTests.crossDirectionIsolation() asserts distinct prefixes + nonces + cross-direction open failure. NIST SP 800-38D §8.2.1 deterministic-IV construction | closed |
| T-02-03-02 | Tampering | SessionCrypto.swift | mitigate | `SessionCrypto.open()` propagates CryptoKit error directly — no `try?` swallow; comment "Fail-closed (D-58)" at :21; CryptoTests.tamperFailsClosed() proves ciphertext-bit-flip AND tag-bit-flip AND wrong-seq all throw | closed |
| T-02-03-03 | Information Disclosure | SessionKeychain.swift | mitigate | `kSecUseDataProtectionKeychain = kCFBooleanTrue!` (CF#8) at :91; `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` at :92; KeychainTests.productionQueryHasDataProtectionAttributes() asserts both attributes | closed |
| T-02-03-04 | Information Disclosure | SessionKeychain.swift / SessionCrypto.swift | mitigate | `KeychainError` cases carry `OSStatus` only; `SessionCryptoError` carries byte-count Int only — no key bytes in any error; comment "Errors surface OSStatus only — never key material" at SessionKeychain.swift:70 | closed |
| T-02-03-05 | Denial of Service | SampleCodec.swift / SampleCodecTests.swift | mitigate | `getCheckedRoot` called at SampleCodec.swift:128; `channelByteCount == cortexChannelDataByteCount` guard at :133-135; SampleCodecTests.decodeRejectsGarbage() and .decodeRejectsWrongByteLength() prove both paths | closed |
| T-02-03-06 | Elevation of Privilege | SessionKeychain.swift | mitigate | `kSecAttrAccessGroup` deliberately omitted from `baseQuery()` in Phase 2 (CF#1 fallback); `deferredAccessGroup` constant is never passed to baseQuery; KeychainTests line 95 asserts `q[kSecAttrAccessGroup as String] == nil` | closed |
| T-02-04-01 | Spoofing | cortex_rendezvous.c / Rendezvous.swift | mitigate | `posix_spawnattr_setspecialport_np` at cortex_rendezvous.c:69; `task_get_special_port(…, TASK_BOOTSTRAP_PORT, …)` at :133; Rendezvous.swift wraps both parent and child sides with typed throws | closed |
| T-02-04-02 | Tampering | FDChannel.swift | mitigate | Same geometry check as T-02-02-02 — receiver validates received stride/ringBytes against compile-time CORTEX_CHANNEL_COUNT expectation at FDChannel.swift:70-74 | closed |
| T-02-04-03 | Information Disclosure | SessionKeyChannel.swift | accept | CF#1=FAIL: cross-process Keychain access-group sharing un-backable under free team Y4A54395NZ. Secret delivered over kernel-mediated mach_msg channel (rendezvous send right); never touches disk; never logged. Phase 8 removes this path via paid-team enrollment. See Accepted Risks Log. | closed |
| T-02-04-04 | Tampering | HarnessConsumer.swift / HarnessE2ETests.swift | mitigate | `s > lastSeen` strict-greater check at HarnessConsumer.swift:103 — stale/equal seq never decoded/acked; testForwardOnlyAntiReplay() in HarnessE2ETests proves spinBudget exhaustion on replay attempt | closed |
| T-02-04-05 | Denial of Service | Rendezvous.swift / HarnessConsumer.swift | mitigate | `defaultReplyTimeoutMs: UInt32 = 10_000` bounds parent await at Rendezvous.swift:44; `spinBudget: Int = 50_000_000` bounds consumer ack poll at HarnessConsumer.swift:96 | closed |
| T-02-04-06 | Information Disclosure | HarnessConsumer.swift / SessionKeyChannel.swift | mitigate | No `print` statements on any secret path in HarnessConsumer.swift; SessionKeyChannel.send() throws `unexpectedLength(bytes.count)` (count only, no bytes) at :70; key bytes zeroed via SymmetricKey lifecycle | closed |
| T-02-05-01 | Spoofing | Benchmark.swift / ci.yml | mitigate | Benchmark uses only ShmRing shm busy-poll — no kevent/recvmsg/Doorbell API (confirmed in 02-05-SUMMARY); ci.yml "Run CortexIPC tests" step is `swift test` only with no timing-gate grep | closed |
| T-02-05-02 | Tampering | ci.yml | mitigate | ci.yml line 129: `grep -rnE 'SCM_RIGHTS\|cmsg\('` over `Packages/CortexIPC/Sources` + `Packages/CortexCore/Sources/CortexCoreC` — build fails if socket FD-passing path reintroduced (SC#2 defense-in-depth) | closed |
| T-02-05-03 | Repudiation | sc1-evidence.md / sc1-histogram.csv / sc1-histogram.txt | mitigate | sc1-evidence.md + sc1-histogram.txt + sc1-histogram.csv committed to the phase directory — hardware-measured p99=208ns on M5 Pro (n=199,000); evidence immutable in git | closed |
| T-02-05-04 | Information Disclosure | ci.yml / CryptoTests.swift | accept | CI runner (macos-15/M1) cannot exercise the data-protection Keychain (CF#1 corollary); tests use legacyFile backend seam. Ephemeral per-test keys; CI prints test names and OK/FAIL only. Production data-protection path exercised on real M4 hardware. Phase 8 resolves via enrollment. See Accepted Risks Log. | closed |
| T-02-05-05 | Tampering | ci.yml | mitigate | "Run CortexIPC tests" step is `swift test --package-path Packages/CortexIPC` only — no timing assertion, no latency grep; D-18 explicitly prohibits CI timing assertions (confirmed at ci.yml:103-105 comment) | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-02-01 | T-02-04-03 | Cross-process Keychain access-group sharing (kSecAttrAccessGroup with team prefix) is un-backable under free Apple Developer team Y4A54395NZ — AMFI delivers SIGKILL (exit 137) when the entitlement is present on a bare `type: tool` binary; errSecMissingEntitlement (-34018) when absent. CF#1=FAIL verdict documented in 02-SPIKES.md. Fallback: the 256-bit session secret is delivered over the existing kernel-mediated mach_msg rendezvous channel (the same channel that carries the shm fd). The channel is a kernel capability: only the posix_spawn parent and the spawned child hold the paired send/receive rights. Secret never touches disk in transit and is never logged. ASVS V6.2: the control is bounded and inline. Removal path: Phase 8 enrollment with a paid Apple Developer Program account supplies a team-prefixed provisioning profile and allows kSecAttrAccessGroup; SessionKeychain.deferredAccessGroup holds the constant to flip. | gsd-secure-phase (2026-06-20) | 2026-06-20 |
| AR-02-02 | T-02-05-04 | The macOS data-protection Keychain (kSecUseDataProtectionKeychain) is unreachable from the unentitled swift-test runner — unentitled produces errSecMissingEntitlement (-34018); entitling the test host under the free team triggers AMFI SIGKILL (CF#1 corollary, proven in Plan 02-03 /tmp/kc-probe). CI therefore exercises Keychain round-trip/not-found/idempotent LOGIC via the legacyFile backend seam injected in KeychainTests. The production data-protection item shape (kCFBooleanTrue + AfterFirstUnlockThisDeviceOnly) was built, signed, and run on real M4 hardware by the CF#1 spike; KeychainTests.productionQueryHasDataProtectionAttributes() structurally asserts both production attributes. Ephemeral per-test keys are deleted in setUp/defer. CI output is test names and pass/fail only — no key material printed. Full data-protection round-trip exercised under Phase 8 enrollment. | gsd-secure-phase (2026-06-20) | 2026-06-20 |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-20 | 28 | 28 | 0 | gsd-secure-phase (sonnet-4-6) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-20
