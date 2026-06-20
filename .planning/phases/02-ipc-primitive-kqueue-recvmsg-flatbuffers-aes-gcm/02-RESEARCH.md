# Phase 2: IPC Primitive — kqueue+recvmsg + FlatBuffers + AES-GCM — Research

**Produced:** 2026-06-20
**Method:** Main-thread deep research pass (browser-harness + `gh` code search + live SDK header inspection + Context7). Per the project's GSD×browser-harness rule, the deep browser pass is the main thread's job — this file pre-stages research so `/gsd-plan-phase` skips the HTTP-only subagent. Sources are cited inline (verifiable, not "trust me").
**Toolchain caveat:** SDK headers below were read from the active toolchain at research time. The CLT SDK and the Xcode 26.3 SDK both ship the relevant headers (verified for `sys/fileport.h` in both CLT and `iPhoneOS26.3.sdk`). **Per memory note `cortex-build-with-real-xcode`, all Phase 2 build/verify steps run under real Xcode 26.3 (Team 57YW6M29S7), not CommandLineTools** — CLT hid 6 defects in Phase 1.

---

## User Constraints (from CONTEXT.md)

### Locked Decisions (D-01…D-18 — do not relitigate)
- **D-01/D-02/D-03:** shm ring = data plane (zero-copy, fixed stride); `kqueue`+`recvmsg` socketpair = control-plane doorbell carrying only a small fixed notification. SC#1 "round-trip" = frame-delivery latency measured via an **ack-bounce** (`producer → consumer → ack`). AES-GCM is **off** the measured doorbell path.
- **D-04/D-05:** Split `CortexIPC` into `CortexIPCTransport` (Foundation-free hot path; the *only* policed dir) + `CortexIPCSession` (Foundation-allowed: CryptoKit, Keychain, FlatBuffers codec). Re-scope `hotpath-policy.sh` `DIRS_ARRAY` to `Packages/CortexIPC/Sources/CortexIPCTransport` only.
- **D-06:** Per-frame AES-GCM uses CryptoKit (`Data`-based, Foundation) in the Session layer in Phase 2. Moving it onto the Foundation-free pthread path is a Phase-3 follow-up.
- **D-07/D-08/D-09:** Phase 2 = two-process **proof harness** (daemon = producer; small consumer exe and/or XCTest that `posix_spawn`s a child). FD handoff via `mach_msg` + `MACH_MSG_PORT_DESCRIPTOR` (via `fileport_makeport`), **no `SCM_RIGHTS`**. Production packaging form named now = **SMAppService** daemon; register/install + signing wiring deferred to Phase 8.
- **D-10/D-11/D-12/D-13:** `channel_data = [ubyte]` of raw f16 bytes, rebound to `Float16` zero-copy; `CORTEX_CHANNEL_COUNT` compile-time `_Static_assert`; `table Sample { ts_ns: ulong; channel_data: [ubyte]; seq: ulong; }`; flatc codegen vendored in-repo.
- **D-14/D-15/D-16:** Session = one daemon lifetime; random 256-bit secret → HKDF-Expand into per-direction subkeys; secret stored in Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); shared via Keychain access group; 96-bit deterministic GCM nonce = `(direction/epoch prefix || monotonic counter)` reusing `seq` as the counter.
- **D-17/D-18:** SC#1 rigor: n ≥ 100k, report p50/p99/σ, discard ~1k warm-up, pin QoS, commit histogram + raw samples + methodology. Real-M4 timing is hardware-gated evidence; CI (`macos-15`, M1) runs the harness for **correctness only**, never the timing claim.

### Implementer's Discretion (planner decides, research informs)
Ring depth (power-of-two); doorbell payload encoding; `kqueue` setup (`EVFILT_READ` on socket vs `EVFILT_USER`); HKDF `salt`/`info` labels + Keychain item naming; consumer-harness form (exe vs XCTest `posix_spawn`); histogram bucketing; fail-closed teardown semantics; concrete mach service name for rendezvous; per-target Swift isolation (Transport must avoid `MainActor`/actor hops).

### Cross-Phase Commitments honored
Compile-time guarantees beat runtime (`CORTEX_CHANNEL_COUNT` `_Static_assert`; existing `CORTEX_SHM_NAME` assert already makes **SC#4 structurally satisfied**). Audio-callback discipline (`CortexIPCTransport` Foundation-free, sole policed dir).

---

## Phase Requirements

| Req | Behavior | Primary SC |
|-----|----------|-----------|
| IPC-01 | POSIX `shm_open` in App Group container, name ≤31 bytes (`PSHMNAMLEN`) | SC#4 |
| IPC-02 | `kqueue`+`recvmsg` socketpair moves a frame daemon→app | SC#1 |
| IPC-03 | Cross-process FD passing via `mach_msg`+`MACH_MSG_PORT_DESCRIPTOR` (`fileport_makeport`) | SC#2 |
| IPC-04 | FlatBuffers `Sample { ts_ns:u64, channel_data:[f16] }` round-trips 0.5 ms blocks | SC#1/SC#3 |
| IPC-05 | AES-GCM via CryptoKit `AES.GCM`, HKDF-derived per-session keys | SC#3 |
| IPC-06 | Session keys in Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | SC#3 |
| IPC-07 | Measured round-trip latency sub-µs over local socket pair | SC#1 |

---

## Summary

Every named API is real, public, and App-Store-eligible. The genuinely hard parts and their resolutions:

1. **FD passing (IPC-03/SC#2)** is solid: `fileport_makeport`/`fileport_makefd` are public `__API_AVAILABLE(macos(10.7))` (NOT SPI, NOT deprecated), `fileport_t == mach_port_t` drops straight into a `MACH_MSG_PORT_DESCRIPTOR`. Battle-tested in Frida and HexFiend. **Gotcha: a kqueue/socket fd is NOT fileport-sendable — only the shm fd is.**
2. **The rendezvous named in D-08 is fragile.** `bootstrap_register` is **deprecated since 10.5** and returns `BOOTSTRAP_NOT_PRIVILEGED` for ad-hoc names on modern macOS; the non-deprecated `bootstrap_check_in` needs a launchd-declared service (which D-08 avoids). Robust non-deprecated alternative: **`posix_spawnattr_setspecialport_np`** — parent injects the rendezvous send right at spawn. See **Critical Finding #3**.
3. **SC#1 "sub-µs" is only real via shm busy-poll (~270 ns), NOT a blocking kqueue round-trip (~5 µs).** See **Critical Finding #2** — this is load-bearing for the project's defining latency claim.
4. **SC#3 is the riskiest criterion.** A **bare-`tool` daemon** + data-protection keychain + team-prefixed access group typically needs a provisioning profile to back the `keychain-access-groups` entitlement → high risk of `errSecMissingEntitlement (-34018)` under free/local signing. See **Critical Finding #1** (spike-first + fallback plan).

Recommended build order (waves) is in the Architectural Responsibility Map.

---

## Architectural Responsibility Map

| Component | Target | Foundation? | Responsibility |
|-----------|--------|-------------|----------------|
| shm ring (open/map/slot arithmetic) | `CortexIPCTransport` | ❌ | Fixed-stride ring in App Group container; consumes `cortex_shm.h` |
| `kqueue`+`recvmsg` doorbell | `CortexIPCTransport` | ❌ | Arm `EVFILT_READ`; tiny notification; idle wake |
| `mach_msg` + port-descriptor FD passing | `CortexIPCTransport` (+ thin C shim in `CortexCoreC`) | ❌ | `fileport_makeport`/`makefd`; complex-message send/recv |
| Spawn-time rendezvous | harness driver | n/a | `posix_spawnattr_setspecialport_np` (or bootstrap fallback) |
| FlatBuffers `Sample` codec | `CortexIPCSession` | ✅ | Build/read `Sample`; `[ubyte]`↔`Float16` rebind |
| AES-GCM + HKDF | `CortexIPCSession` | ✅ | CryptoKit `AES.GCM`, `HKDF<SHA256>`, deterministic nonce |
| Keychain session key | `CortexIPCSession` | ✅ | `SecItemAdd`/`CopyMatching`, data-protection keychain, access group |
| Producer | `Apps/CortexDaemon` (`type: tool`) | ✅ (setup) | Generate key, write frames, ring doorbell |
| Consumer + measurement | new harness exe and/or XCTest | ✅ (setup) | Receive FD, decrypt, ack-bounce, collect p50/p99/σ |

---

## Domain Research

### Q1: Cross-process FD passing — `fileport` + `MACH_MSG_PORT_DESCRIPTOR` (IPC-03 / SC#2)

**API surface (verified, SDK `sys/fileport.h`):**
```c
typedef __darwin_mach_port_t fileport_t;          // == mach_port_t
#define FILEPORT_NULL ((fileport_t)0)
__API_AVAILABLE(macos(10.7), ios(4.3)) int fileport_makeport(int fd, fileport_t *port);  // 0 ok / -1 errno
__API_AVAILABLE(macos(10.7), ios(4.3)) int fileport_makefd(fileport_t port);              // newfd / -1 errno
```
Public API, not deprecated, has section-2 man pages, ships in CLT and `iPhoneOS26.3.sdk`. Clang module `Darwin.sys.fileport` exists → callable from Swift (`import Darwin`); **if not surfaced, add a one-line C shim in `CortexCoreC`** mirroring the existing `cortex_shm_open` precedent.

**Semantics (from `man 2 fileport_makeport`):**
- Sender may `close()` the original fd immediately after `fileport_makeport`. Sharing semantics == `dup(2)` (shared open file description).
- The fd from `fileport_makefd` is created **with close-on-exec set**.
- ⚠️ **"Certain special types of open file descriptions, e.g. a kqueue, cannot be sent between processes; `fileport_makeport()` will return an error for those descriptors."** → Only the **shm fd** is fileport-eligible. Never attempt to pass the kqueue or socketpair fds via fileport. (This is fine — the design only needs to hand off the shm region's fd.)
- Apple NOTE *advises* XPC + `xpc_fd_create`/`xpc_fd_dup` instead. **We deliberately go lower-level** — IPC-03 mandates the raw `mach_msg`+fileport primitive (the "thinnest viable" transport). Document this as a conscious choice in the threat model / ADR.

**The complex-message form (mandated by IPC-03):** Frida ([frida-core `lib/pipe/pipe-darwin.c`](https://github.com/frida/frida-core/blob/main/lib/pipe/pipe-darwin.c)) puts the fileport in the message *header* port slot — simplest, but IPC-03 specifically requires `MACH_MSG_PORT_DESCRIPTOR` (the **complex** message body), which lets the shm fd ride alongside inline data (e.g., shm name, ring size, slot stride) in **one** message. Skeleton (put in the C shim, keeps Transport Swift Foundation-free):
```c
typedef struct {
  mach_msg_header_t          header;   // msgh_bits |= MACH_MSGH_BITS_COMPLEX
  mach_msg_body_t            body;     // msgh_descriptor_count = 1
  mach_msg_port_descriptor_t fd_port;  // .name=fileport, .disposition=MACH_MSG_TYPE_MOVE_SEND, .type=MACH_MSG_PORT_DESCRIPTOR
  uint64_t                   ring_bytes;   // inline payload (example)
  char                       shm_name[32]; // ≤31+NUL, mirrors PSHMNAMLEN
} cortex_fd_msg_t;
// receive buffer must also reserve mach_msg_trailer_t.
```
Send: `header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND,0) | MACH_MSGH_BITS_COMPLEX; header.msgh_remote_port = <dest send right>;` then `mach_msg(MACH_SEND_MSG)`. Receiver: `mach_msg(MACH_RCV_MSG)`, read `fd_port.name`, `int fd = fileport_makefd(name); mach_port_deallocate(mach_task_self(), name);`. References: Frida (above); [HexFiend `helper_subprocess`](https://github.com/HexFiend/HexFiend/tree/master/helper_subprocess) (a shipping macOS app passing FDs to a helper subprocess — our exact daemon↔app shape); [saelo/pwn2own2018 `libspc`](https://github.com/saelo/pwn2own2018) (fileport in an XPC dictionary).

### Q2: Parent→child Mach-port rendezvous (IPC-03 / D-08) — **deviation candidate, see CF#3**

D-08 names "parent publishes a receive right under a bootstrap service name; child `bootstrap_look_up`s it." **SDK reality (`servers/bootstrap.h`):**
- `bootstrap_register(bp, name_t, sp)` — `__OSX_AVAILABLE_BUT_DEPRECATED(10.4 → 10.5)`, `XPC_WARN_RESULT`. Returns `BOOTSTRAP_NOT_PRIVILEGED (1100)` for ad-hoc names on modern macOS (launchd no longer lets arbitrary processes register names). `BOOTSTRAP_MAX_NAME_LEN = 128` (no 31-byte limit — that's shm only).
- `bootstrap_check_in` / `bootstrap_look_up` — **not** deprecated, but `check_in` requires the service to be declared in a launchd plist (D-08 explicitly wants *no plist*).

**Robust non-deprecated alternative — `posix_spawnattr_setspecialport_np` (verified `spawn.h`, `__API_AVAILABLE(macos(10.5))`):**
```c
int posix_spawnattr_setspecialport_np(posix_spawnattr_t *attr, mach_port_t new_port, int which);
```
Parent: `mach_port_allocate(RECEIVE)` → rendezvous_rx; `mach_port_extract_right(..., MACH_MSG_TYPE_MAKE_SEND, ...)` → send; `posix_spawnattr_setspecialport_np(&attr, send, TASK_BOOTSTRAP_PORT)`; `posix_spawn`. Child: `task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &p)` (or read the global `bootstrap_port`) → uses `p` directly as the rendezvous channel, then the Q1 `mach_msg`+fileport dance proceeds. `which` indices (`mach/task_special_ports.h`): `TASK_BOOTSTRAP_PORT=4`, others (1,2,3,5,6,9,10,11) are kernel/host/name/inspect/read/access/debug/resource — **do not clobber**.
- **Caveat:** injecting `TASK_BOOTSTRAP_PORT` means the child loses real launchd bootstrap. **Safe for the Foundation-free Transport consumer** (D-04); a Foundation/CoreFoundation child may need real bootstrap for CFRunLoop. → If the consumer is the full app or an XCTest host, prefer keeping its real bootstrap and use the **bootstrap fallback** instead.
- **Recommendation:** primary = `posix_spawnattr_setspecialport_np` for a minimal Foundation-free consumer; fallback = `bootstrap_register`/`look_up` (accept deprecation warning) if the consumer needs real launchd. **Reconcile with locked D-08 in the plan** — either honor D-08 (bootstrap, document the deprecation/NOT_PRIVILEGED risk + a verified-working spike) or adopt setspecialport with this rationale and flag the deviation for the checker/user. Validate with a ≤30-line spike before committing the harness shape.

### Q3: `kqueue` + `recvmsg` + socketpair doorbell, and the sub-µs truth (IPC-02/IPC-07 / SC#1) — **see CF#2**

- `socketpair(AF_UNIX, SOCK_STREAM, 0, fds)` for the doorbell; set `FD_CLOEXEC` + `SO_NOSIGPIPE` (Frida pattern, Q1 link). Doorbell payload is tiny (write index / `seq`, 4–8 bytes) — D-01.
- Consumer arms `kqueue`/`kevent64` with `EVFILT_READ` on the socket fd (or `EVFILT_USER` for a pure in-process kick — Discretion). A `kevent` wake involves a scheduler context switch.
- **Latency reality (cited):** [Linux IPC Shootout, Jan 2026](https://victoranderssen.com/blog/linux-ipc-benchmark) — **shared-memory round-trip median ≈ 270 ns** at 32 B vs **AF_UNIX stream ≈ 5,910 ns / datagram ≈ 4,640 ns**. Linux numbers, but the architecture carries to Darwin/Apple Silicon (socket = syscall + context-switch bound; shm poll = cache-coherency bound). **A blocking kqueue/recvmsg cross-process round-trip is µs-scale at p99 — it cannot meet sub-µs.**
- **Therefore (load-bearing):** the measured SC#1 sub-µs number comes from **busy-polling the shm ring sequence number** (producer bumps `seq`; consumer spins reading `seq` from the mapped ring → reads the slot zero-copy). The D-02 **ack-bounce must also be shm-polled** (consumer bumps an ack `seq` the producer spins on). The `kqueue`+`recvmsg` socketpair satisfies SC#1's "over the POSIX shm + `kqueue`+`recvmsg` socket pair" wording and provides the **idle/arming** path (blocking wake when not spinning), but is **not** on the measured hot path. Pin `QOS_CLASS_USER_INTERACTIVE` during the run (D-17). Memory ordering: acquire/release on the `seq` load/store (mirrors the Phase 3 SPSC ring discipline).

### Q4: POSIX shm ring in App Group container (IPC-01 / SC#4)

- **SC#4 is already structurally satisfied** by the existing `_Static_assert(sizeof(CORTEX_SHM_NAME) <= 32, ...)` in `cortex_shm.h` — do not weaken it. Add the analogous `CORTEX_CHANNEL_COUNT` `_Static_assert` (D-11) in the same header.
- Reuse the `ShmCheck.swift` reference sequence: `cortex_shm_open(name, O_CREAT|O_RDWR, 0600)` → `ftruncate(fd, ring_bytes)` → `mmap(nil, ring_bytes, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0)`. `ShmCheck.swift` is **slated for replacement** by the real Transport ring (its own header says so).
- Fixed-stride ring: `slot_addr = base + (seq % depth) * stride`, `stride = sizeof(header) + CORTEX_CHANNEL_COUNT*2 + GCM_TAG(16) + ...` (constant → trivial arithmetic, D-03). Depth = small power-of-two (Discretion). Ring header (counters) lives in a cache-line-padded region to avoid false sharing with slots.
- App Group container path via existing `AppGroup.containerURL()`. Note: POSIX `shm_open` names are a **global namespace** (not under the container path) — the App Group is the *authorization* boundary (Phase 1 D-07/SC#2 proved cross-process shm works under the shared entitlement); keep the `/cortex.samples`-style name.

### Q5: FlatBuffers `Sample` codec, `[ubyte]`↔`Float16` zero-copy (IPC-04) — **see CF#7**

- Schema (`Packages/CortexIPC/Schemas/sample.fbs`, D-12): `table Sample { ts_ns:ulong; channel_data:[ubyte]; seq:ulong; } root_type Sample;`. `[ubyte]` is the right primitive for raw f16 bytes (Context7 `/google/flatbuffers`: `inventory:[ubyte];`).
- Codegen: `flatc --swift sample.fbs` → vendored Swift in `CortexIPCSession` (D-13). SwiftPM dep: `.package(url: "https://github.com/google/flatbuffers.git", from: "X.Y.Z")`, product `FlatBuffers` (FlatBuffers versions by date, e.g. 25.x). Read root via `getRoot`/`getCheckedRoot(byteBuffer:)`.
- **Zero-copy decode:** the generated `channel_data` accessor exposes the vector's bytes inside the `ByteBuffer`; obtain an `UnsafeRawBufferPointer`/`UnsafeBufferPointer<UInt8>` to the vector region and `withMemoryRebound`/`bindMemory(to: Float16.self)` — hardware f16, no per-element conversion (D-10). **Encode copies** into the builder (~200–400 ns/frame, the spec §4.4 caveat) — acceptable, it's off the doorbell hot path.
- **Enforce D-10 invariant:** assert `channel_data.count == CORTEX_CHANNEL_COUNT * 2` on both build and read (the `[ubyte]` typing hides the half-pair invariant).
- ⚠️ **CF#7 version match:** vendored generated Swift and the `FlatBuffers` runtime must be from the **same** FlatBuffers version, or you hit ABI/compile mismatches. Pin the SwiftPM version and the vendored `flatc` to the same release; the optional CI `flatc + git diff --exit-code` drift check (D-13) only runs when `flatc` is present.

### Q6: AES-GCM + HKDF + deterministic nonce (IPC-05 / D-16)

CryptoKit (`import CryptoKit`, Session layer, D-06). API is stable; confirm exact signatures via Context7/Apple docs at wiring (CONTEXT.md canonical_refs already directs this). Shape:
```swift
let secret = SymmetricKey(size: .bits256)                                   // D-14 random per launch
let k = HKDF<SHA256>.expand(pseudoRandomKey: secret, info: Data("cortex.daemon->app.v1".utf8), outputByteCount: 32)  // D-15 per-direction
// deterministic 96-bit nonce = 4-byte direction/epoch prefix || 8-byte big-endian seq  (D-16, NIST SP 800-38D §8.2.1 deterministic IV)
let nonce = try AES.GCM.Nonce(data: prefix4 + seq.bigEndianBytes)           // 12 bytes
let box = try AES.GCM.seal(plaintextFlatBuffer, using: SymmetricKey(data: k), nonce: nonce)
// transmit box.ciphertext + box.tag (nonce is reconstructable from seq → need not be sent)
let opened = try AES.GCM.open(AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag), using: SymmetricKey(data: k))
```
- **Nonce uniqueness:** `seq` (D-12) is the monotonic counter; per-direction `info` labels give each direction its own `(key, nonce)` domain (no cross-direction reuse). Fresh session key per launch (D-14) resets the space on restart/exhaustion. **No per-frame RNG on the hot path.** This is the NIST SP 800-38D deterministic-IV construction — correct and standard.
- FEAT_AES on Apple Silicon makes AES-GCM the right choice over ChaCha20-Poly1305 (spec §4.5).
- `AES.GCM.Nonce(data:)` **requires exactly 12 bytes** — assert length. `seal`/`open` are `throws`; fail-closed on `open` failure (drop frame / tear down, Discretion D-58).

### Q7: Keychain session key — data-protection keychain + access group (IPC-06 / SC#3) — **see CF#1, CF#8**

- IPC-06's `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` is a **data-protection-keychain** attribute → must set `kSecUseDataProtectionKeychain = kCFBooleanTrue` in every query ([Apple: kSecUseDataProtectionKeychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain) — "behaves like an iOS keychain item"). The **legacy file keychain does not honor that accessibility class**, so data-protection keychain is mandatory, not optional.
- ⚠️ **CF#8:** pass `kCFBooleanTrue`, **not** Swift `true`, for `kSecUseDataProtectionKeychain` — Swift `true` bridged here yields `errSecParam (-50)` ([SO 79801561, Oct 2025](https://stackoverflow.com/questions/79801561/macos-keychain-access-group-failing-with-ksecusedataprotectionkeychain)).
- Item shape: `kSecClass = kSecClassGenericPassword`, `kSecAttrAccount = "cortex.session.secret"`, `kSecAttrAccessGroup = "<TeamPrefix>.group.com.donovansantine.cortex.shared"` (or a dedicated keychain group), `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecValueData = <32-byte secret>`. Round-trip = `SecItemDelete` → `SecItemAdd` → `SecItemCopyMatching` (proves SC#3 "round-tripping Keychain").
- ⚠️ **CF#1 (the SC#3 risk):** sharing across processes via access group needs **both** binaries signed by the **same team** with the **same `keychain-access-groups` entitlement backed by a provisioning profile**. `CortexDaemon` is `type: tool` (bare Mach-O, `project.yml:106`) — [SO 62908049](https://stackoverflow.com/questions/62908049/can-we-add-keychain-access-group-entitlements-in-commandline-application-for-mac): a command-line tool has no bundle/provisioning profile, so a team-prefixed keychain access group may be rejected at runtime (`errSecMissingEntitlement -34018`). This mirrors Phase 1's enrollment-deferral risk (App Group worked unsandboxed; keychain access groups are stricter). **Mitigation plan in CF#1.**

### Q8: Module split + hot-path gate re-scope + Swift isolation (D-04/D-05) — **see CF#4**

- Split `Packages/CortexIPC/Package.swift`'s single `CortexIPC` target into `CortexIPCTransport` (depends on `CortexCoreC`) + `CortexIPCSession` (depends on `CortexIPCTransport`, adds `FlatBuffers`); wire the product. Transport target: **drop** `.defaultIsolation(MainActor.self)` (current manifest sets it) — the Foundation-free hot path must avoid `MainActor`/actor hops (Discretion); use `nonisolated`/`Sendable` value types. Session target may keep MainActor isolation.
- ⚠️ **CF#4:** the current `hotpath-policy.sh` `DIRS_ARRAY=("Packages/CortexIPC/Sources")` scans **all** of CortexIPC/Sources. `CortexIPCSession` legitimately `import Foundation` (CryptoKit/Keychain/FlatBuffers) → the gate would **false-positive and fail Phase 2's own CI**. D-05's re-scope to `Packages/CortexIPC/Sources/CortexIPCTransport` is **mandatory and load-bearing**, not cosmetic. The script's own comment anticipates this ("extend `DIRS_ARRAY` to scope that subdir specifically"). Keep the forbidden-token self-test (Plan 01-06 pattern).

### Q9: Measurement methodology + CI split (D-17/D-18)

- Mirror Phase 1's hardware-gated-claim evidence pattern (`sc2-evidence.md` + runbook). n ≥ 100k, discard ~1k warm-up, report **p50/p99/σ** (SC#1 names p99), pin `QOS_CLASS_USER_INTERACTIVE`, commit histogram + raw samples + methodology note → `sc1-evidence.md`. Timestamps via existing `Time.machAbsoluteNanoseconds()` (already privacy-manifested CA92.1).
- **CI on `macos-15` (M1) runs the harness for CORRECTNESS only** — round-trip succeeds, AES-GCM decrypts, FD passes, schema/`_Static_assert` hold, `seq`/nonce monotonic. **Never** assert the timing number in CI (runner is M1, claim is M4). The sub-µs-on-M4 number is committed hardware-gated evidence (manual benchmark under Xcode 26.3).

### Q10: SMAppService daemon form (D-09) — deferred to Phase 8

`SMAppService.daemon(plistName:)` (macOS 13+, App-Store-compatible replacement for `SMJobBless`/raw launchd plists). Phase 2 only **names** the form and shapes the rendezvous to be SMAppService-compatible; register/install + code-signing wiring is **Phase 8** (needs Apple Developer enrollment, Phase 1 D-09). Resolves the PROJECT.md open item "CortexDaemon final App-Store form is a Phase 2 decision." No Phase-2 task beyond the ADR/PROJECT.md note.

---

## Validation Architecture

> Per `.planning/config.json` `workflow.nyquist_validation: true`, this section is required (drives `02-VALIDATION.md`).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (Swift 6.2 default) for unit/codec/crypto; XCTest host for the `posix_spawn` two-process harness (if chosen over a standalone exe) |
| Quick run | `swift test --package-path Packages/CortexIPC` |
| Full suite | `xcodebuild test -workspace Cortex.xcworkspace -scheme CortexMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` (correctness) + manual `sc1-evidence` benchmark (M4 timing) |
| Hot-path gate | `Tools/scripts/hotpath-policy.sh` (re-scoped to `CortexIPCTransport`) |

### Phase Requirements → Test Map

| Req | Behavior | Test Type | Automated command (correctness) |
|-----|----------|-----------|---------------------------------|
| IPC-01 | shm ring opens/maps in App Group; fixed stride | unit + manual runbook | `swift test --filter RingTests` |
| IPC-01 / SC#4 | `CORTEX_SHM_NAME` ≤31 B; `CORTEX_CHANNEL_COUNT` assert | compile-time | `swift build --package-path Packages/CortexCore` fails if constant over-long / mismatched |
| IPC-02 | socketpair+kqueue doorbell delivers notification | unit + harness | harness exits 0; `kevent` returns the armed event |
| IPC-03 / SC#2 | FD passed via `mach_msg`+`MACH_MSG_PORT_DESCRIPTOR`; received fd maps same shm; **no `SCM_RIGHTS` in code** | harness + static grep | harness: receiver reads producer's sentinel through passed fd; `! grep -rn 'SCM_RIGHTS\|cmsg' Packages/CortexIPC/Sources` |
| IPC-04 | `Sample` round-trips; `channel_data.count == CHANNEL_COUNT*2`; `Float16` rebind | unit | `swift test --filter SampleCodecTests` |
| IPC-05 | AES-GCM seal/open with HKDF subkeys + deterministic nonce | unit | `swift test --filter CryptoTests` (incl. nonce-uniqueness + tamper-fails-open) |
| IPC-06 / SC#3 | key round-trips Keychain w/ correct accessibility | unit (+ spike, CF#1) | `swift test --filter KeychainTests`; **gated by CF#1 access-group spike** |
| IPC-07 / SC#1 | sub-µs round-trip (shm-polled) on M4 | manual benchmark | `sc1-evidence.md`: n≥100k, p50/p99/σ; **CI asserts correctness only** |

### Sampling Rate

- **Per task commit:** `swift build --package-path Packages/CortexIPC && swift test --package-path Packages/CortexIPC` + `hotpath-policy.sh` (≤60 s).
- **Per wave merge:** full `ci.yml` (correctness harness on `macos-15`).
- **Phase gate:** CI green + `sc1-evidence.md` (M4, sub-µs p99) + `sc2-evidence`-style FD-passing evidence + Keychain round-trip evidence committed.

### Wave 0 Gaps (artifacts that must exist)

- [ ] `Packages/CortexIPC/Package.swift` — split into `CortexIPCTransport` + `CortexIPCSession`, add `FlatBuffers` dep
- [ ] `Packages/CortexIPC/Sources/CortexIPCTransport/*` — shm ring, kqueue/recvmsg doorbell, mach FD passing (Foundation-free)
- [ ] `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h` — add `CORTEX_CHANNEL_COUNT` `_Static_assert`; (optional) mach-msg+fileport C shim
- [ ] `Packages/CortexIPC/Sources/CortexIPCSession/*` — FlatBuffers codec (vendored gen), AES-GCM/HKDF, Keychain
- [ ] `Packages/CortexIPC/Schemas/sample.fbs` + vendored generated Swift
- [ ] `Packages/CortexIPC/Tests/*` — Ring, SampleCodec, Crypto, Keychain tests
- [ ] `Apps/CortexDaemon/main.swift` — producer (replaces Phase 1 stub)
- [ ] new consumer harness exe (or XCTest host that `posix_spawn`s the child)
- [ ] `Tools/scripts/hotpath-policy.sh` — re-scope `DIRS_ARRAY` to `CortexIPCTransport`
- [ ] `Packages/CortexCore/Sources/CortexCore/ShmCheck.swift` — remove (replaced by real ring)
- [ ] `sc1-evidence.md` + raw samples + histogram; FD-pass + Keychain evidence
- [ ] entitlements: add `keychain-access-groups` to daemon + consumer (CF#1 spike first)
- [ ] CI: add CortexIPC build/test steps; FD-pass + no-`SCM_RIGHTS` grep; correctness-only harness

---

## Critical Findings (LOAD-BEARING)

### Finding #1 (LOAD-BEARING): Bare-`tool` daemon + data-protection-keychain access group is the top SC#3 risk
`CortexDaemon` is `type: tool` (bare Mach-O). Cross-process key sharing via a team-prefixed `keychain-access-groups` access group on the data-protection keychain typically needs a **provisioning profile** to back the entitlement; a bare tool has no bundle/profile → likely `errSecMissingEntitlement (-34018)` under free/local signing ([SO 62908049](https://stackoverflow.com/questions/62908049/can-we-add-keychain-access-group-entitlements-in-commandline-application-for-mac)).
**Mitigation (plan must include):**
1. **Spike first (≤1 task):** under real Xcode 26.3 + Team 57YW6M29S7, sign the daemon tool with `keychain-access-groups` (via `CODE_SIGN_ENTITLEMENTS`, which `codesign` embeds into the bare Mach-O signature) + the consumer, and verify `SecItemAdd`/`CopyMatching` cross-process succeeds. If green → proceed with D-14/D-15 as written.
2. **Fallback if it fails:** prove SC#3 as a **single-process Keychain round-trip** (one process writes the key to the data-protection keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and reads it back — literally satisfies SC#3's "the key round-tripping Keychain") and deliver the key to the peer **over the established secure `mach_msg` channel**, deferring cross-process access-group *sharing* to Phase 8 (enrollment). SC#3's wording requires the key to round-trip Keychain + frames to decrypt on the receiver — both met without enrollment-gated access-group sharing. Flag as a D-14/D-15 reconciliation for the checker/user.

### Finding #2 (LOAD-BEARING): SC#1 sub-µs requires shm busy-poll, NOT a blocking kqueue round-trip
Shared-memory round-trip ≈ 270 ns vs AF_UNIX socketpair ≈ 5 µs ([IPC Shootout, Jan 2026](https://victoranderssen.com/blog/linux-ipc-benchmark)). A blocking `kqueue`/`recvmsg` cross-process wake is context-switch-bound (µs-scale at p99) and **cannot** meet sub-µs. The measured SC#1 number must come from busy-polling the shm `seq`; the ack-bounce (D-02) must be shm-polled too. The socketpair+kqueue is the **idle/arming doorbell** and satisfies SC#1's "over the POSIX shm + `kqueue`+`recvmsg` socket pair" wording — it is not on the measured hot path. Build the harness measurement on the shm-polled path or it will miss the project's defining claim by ~5×.

### Finding #3 (LOAD-BEARING): D-08's `bootstrap_register` rendezvous is deprecated/fragile — prefer `posix_spawnattr_setspecialport_np`
`bootstrap_register` is `__OSX_AVAILABLE_BUT_DEPRECATED(10.4→10.5)` and returns `BOOTSTRAP_NOT_PRIVILEGED (1100)` for ad-hoc names on modern macOS; non-deprecated `bootstrap_check_in` needs a launchd plist (D-08 avoids plists). Use `posix_spawnattr_setspecialport_np(&attr, sendRight, TASK_BOOTSTRAP_PORT)` (parent injects the rendezvous send right at spawn; child reads via `task_get_special_port`). Caveat: only safe for a Foundation-free consumer (TASK_BOOTSTRAP_PORT injection drops real launchd bootstrap). Reconcile with locked D-08 in the plan (honor-with-spike OR adopt-with-rationale) and flag the deviation.

### Finding #4 (LOAD-BEARING): Hot-path gate re-scope (D-05) is mandatory or Phase 2 CI fails on itself
Current `hotpath-policy.sh` scans all of `Packages/CortexIPC/Sources`. `CortexIPCSession` legitimately `import Foundation` → the forbidden-token gate false-positives and fails Phase 2's own CI. Re-scoping `DIRS_ARRAY` to `Packages/CortexIPC/Sources/CortexIPCTransport` (D-05) is load-bearing, not cosmetic. Keep the synthetic-violation self-test.

### Finding #5: Only the shm fd is fileport-sendable
`man fileport_makeport`: a kqueue fd (and similar special fds) **cannot** be sent and returns an error. The design only needs to pass the **shm region fd** (valid) — never attempt to pass the kqueue or socketpair fds via fileport.

### Finding #6: Build/verify under real Xcode 26.3, not CLT
Per memory `cortex-build-with-real-xcode`: CommandLineTools hid 6 defects in Phase 1. All Phase 2 builds/tests/signing run under Xcode 26.3 (Team 57YW6M29S7). The `select-xcode`/`DEVELOPER_DIR` discipline from Phase 1 applies; CI already pins Xcode 26.3 via `setup-xcode@v1`.

### Finding #7: FlatBuffers flatc/runtime version must match
Vendored generated Swift (D-13) and the SwiftPM `FlatBuffers` runtime must be the same release, or ABI/compile mismatch. Pin both; the optional CI `flatc + git diff --exit-code` drift check runs only when `flatc` is present (bundled-tools ethos).

### Finding #8: `kSecUseDataProtectionKeychain` needs `kCFBooleanTrue`, not Swift `true`
Swift `true` here yields `errSecParam (-50)` ([SO 79801561, Oct 2025](https://stackoverflow.com/questions/79801561/macos-keychain-access-group-failing-with-ksecusedataprotectionkeychain)). Use `kCFBooleanTrue` in the query dict.

---

## Standard Stack

### Core (verified APIs)
- **FD passing:** `fileport_makeport`/`fileport_makefd` (`sys/fileport.h`, public, macOS 10.7+) + `mach_msg` complex message with `mach_msg_port_descriptor_t` (`mach/message.h`).
- **Rendezvous:** `posix_spawnattr_setspecialport_np` (`spawn.h`, macOS 10.5+) [recommended] / `bootstrap_register`+`bootstrap_look_up` (`servers/bootstrap.h`, deprecated) [fallback].
- **Doorbell:** `socketpair(AF_UNIX, SOCK_STREAM)` + `kqueue`/`kevent` `EVFILT_READ` + `recvmsg`.
- **shm:** `cortex_shm_open` shim → `ftruncate` → `mmap(MAP_SHARED)` (reuse `ShmCheck.swift` sequence).
- **Wire:** FlatBuffers Swift (`github.com/google/flatbuffers`, product `FlatBuffers`) + vendored `flatc` codegen.
- **Crypto:** CryptoKit `AES.GCM`, `HKDF<SHA256>`, `SymmetricKey` (NIST SP 800-38D deterministic IV).
- **Keychain:** Security framework `SecItemAdd`/`SecItemCopyMatching` + `kSecUseDataProtectionKeychain` + `kSecAttrAccessGroup` + `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

### Supporting
- Timestamps: existing `Time.machAbsoluteNanoseconds()`; App Group: existing `AppGroup.containerURL()`.
- Evidence: mirror `sc2-evidence.md` runbook pattern → `sc1-evidence.md`.

### Reference implementations
- [frida-core `lib/pipe/pipe-darwin.c`](https://github.com/frida/frida-core/blob/main/lib/pipe/pipe-darwin.c) — fileport + mach_msg send/recv.
- [HexFiend `helper_subprocess`](https://github.com/HexFiend/HexFiend/tree/master/helper_subprocess) — shipping macOS app passing FDs to a helper subprocess.
- `man 2 fileport_makeport` (semantics + kqueue-not-sendable caveat).

---

*Phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm*
*Research method: main-thread browser-harness + gh code search + live SDK inspection + Context7, 2026-06-20*
