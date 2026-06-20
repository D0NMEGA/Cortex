# Phase 2: IPC Primitive — kqueue+recvmsg + FlatBuffers + AES-GCM - Context

**Gathered:** 2026-06-19
**Status:** Ready for planning

<domain>
## Phase Boundary

A single FlatBuffers `Sample { ts_ns: u64, channel_data: [f16] }` frame leaves the acquisition daemon and arrives in the app process **sub-µs (p99, on M4), encrypted (AES-GCM), with the file descriptor passed via `mach_msg`** — the "thinnest viable" transport the decoder will later sit on top of. Delivers IPC-01 through IPC-07.

**In scope:** POSIX `shm` ring in the App Group container; `kqueue`+`recvmsg` socketpair doorbell; cross-process FD handoff via `mach_msg` + `MACH_MSG_PORT_DESCRIPTOR`; FlatBuffers `Sample` codec; AES-GCM session encryption with HKDF-derived per-session keys in Keychain; a two-process proof harness measuring the sub-µs round-trip on M4.

**Not in this phase:** the pthread `QOS_CLASS_USER_INTERACTIVE` hot path and Rust SPSC ring (Phase 3); any decoder/renderer code (Phases 4–6); wiring frames into the CortexMac/CortexiOS UI; real notarization/TestFlight and the SMAppService install/signing wiring (Phase 8).

</domain>

<decisions>
## Implementation Decisions

### Transport & latency model
- **D-01:** **shm ring = data plane; `kqueue`+`recvmsg` socketpair = control plane (doorbell).** The encrypted frame is written into a fixed-stride slot in a POSIX shm ring inside the App Group container. The socket carries **only a small fixed notification** (write index / sequence number, ~4–8 bytes). Consumer arms `kqueue` `EVFILT_READ` on the socket, wakes, reads the index, then reads the frame from the shm slot **zero-copy**. AES-GCM encrypt/decrypt is therefore **off** the measured doorbell round-trip. Satisfies SC#1's "over the POSIX shm + `kqueue`+`recvmsg` socket pair" wording (both used).
- **D-02:** **SC#1 "round-trip" = frame-delivery latency.** Measured as producer write+ring → consumer wake → consumer has the frame readable, reported as a true round-trip via an **ack bounce** (consumer rings the producer on receipt): `producer → consumer → ack`. This is the honest "sample available to the next pipeline stage" number, in the project's photodiode/Bliss-Chapman instrumentation spirit.
- **D-03:** shm ring slot **stride is constant** (fixed frame size — see D-11/D-12), so index→address is trivial arithmetic. Ring depth is implementer's discretion (small power-of-two).

### Module topology & hot-path discipline
- **D-04:** **Split `CortexIPC` into two source modules/targets:**
  - `Packages/CortexIPC/Sources/CortexIPCTransport` — **Foundation-free hot path**: shm ring, `kqueue`/`recvmsg` doorbell, `mach_msg` FD passing. The **only** directory the hot-path gate polices.
  - `Packages/CortexIPC/Sources/CortexIPCSession` — **Foundation-allowed**: CryptoKit AES-GCM codec, Keychain session-key management, FlatBuffers `Sample` codec, session setup/teardown. Depends on `CortexIPCTransport`.
  (Current `Package.swift` declares a single `CortexIPC` target — planner splits it into the two targets above and wires the product.)
- **D-05:** **Re-scope `Tools/scripts/hotpath-policy.sh` `DIRS_ARRAY`** from `Packages/CortexIPC/Sources` to **`Packages/CortexIPC/Sources/CortexIPCTransport` only** — the script's own comment anticipates exactly this ("extend `DIRS_ARRAY` to scope that subdir specifically"). The gate then polices the true hot path, not setup code. Forbidden tokens unchanged (`dispatch_async`, `lazy var`, `pthread_mutex`, `import Foundation`, `import ObjectiveC`).
- **D-06:** **Per-frame AES-GCM uses CryptoKit (`Data`-based, Foundation) in the Session layer in Phase 2** — AES-GCM-via-CryptoKit is the locked architectural choice. **Phase 3** (pthread `USER_INTERACTIVE`) profiles whether the encrypt step must move onto the Foundation-free hot path; if so, swap to a Foundation-free AES-GCM (CommonCrypto `CCCryptorGCM` or swift-crypto's lower layer). Captured as a Phase-3 follow-up, not a Phase-2 task.

### Rendezvous, process scope & daemon packaging
- **D-07:** **Phase 2 deliverable is a two-process PROOF HARNESS**, not full app integration. The existing `CortexDaemon` (standalone `type: tool`) is the **producer**; add a small **consumer** executable and/or an XCTest that `posix_spawn`s a child. The harness proves SC#1–4 on the primitive. Wiring frames into the app UI and the decoder is explicitly later-phase work.
- **D-08:** **mach port rendezvous (harness):** the parent allocates the Mach receive right and **publishes it under a runtime bootstrap service name**; the child does `bootstrap_look_up` to obtain the send right, then **raw `mach_msg` + `MACH_MSG_PORT_DESCRIPTOR`** (via `fileport_makeport`) passes the FD. **No `SCM_RIGHTS` anywhere** (SC#2). No launchd plist needed for the proof.
- **D-09:** **Production daemon packaging form is named now = SMAppService-registered daemon** (modern macOS 13+ replacement for `SMJobBless`/raw launchd plists; App-Store-compatible). Phase 2 shapes the rendezvous code to be compatible with this form, but the actual SMAppService **register/install + signing wiring is deferred to Phase 8** (per Phase 1 D-09 enrollment deferral). **Resolves the PROJECT.md open item** "CortexDaemon final App-Store form (XPC/launchd) is a Phase 2 decision."

### FlatBuffers schema & codegen
- **D-10:** **`channel_data` = FlatBuffers `[ubyte]` vector of raw IEEE-754 half (f16) bytes.** Producer/consumer rebind to Swift native `Float16` via `UnsafeBufferPointer` (no per-element conversion; hardware f16 on M-series; f16 preserved end-to-end into the ANE decoder). A `length == CORTEX_CHANNEL_COUNT * 2` assertion enforces the half-pair invariant the `[ubyte]` typing hides.
- **D-11:** **Fixed compile-time channel count.** Define `CORTEX_CHANNEL_COUNT` as a compile-time constant with a `_Static_assert` (mirroring `cortex_shm.h`), so frame size is constant → fixed-stride shm ring (D-03), and the FlatBuffers vector length is asserted `==` the constant. **The mechanism is fixed in Phase 2**; the actual value (~96 for O'Doherty Indy) is confirmed against the Zenodo 3854034 dataset in **Phase 4**.
- **D-12:** **Sample schema** (planner-refinable, but `ts_ns` + `channel_data` are mandated by IPC-04): `table Sample { ts_ns: ulong; channel_data: [ubyte]; seq: ulong; }`. `ts_ns` = `mach_absolute_time`-derived nanoseconds; `channel_data` = raw f16 bytes (D-10); `seq` = the doorbell/ring sequence number, **reused as the GCM nonce counter** (D-16). Frames represent uniform 0.5 ms blocks (IPC-04).
- **D-13:** **flatc codegen vendored.** Commit the `flatc`-generated Swift in-repo; regenerate via a local `Tools/` script; an **optional** CI step runs `flatc` + `git diff --exit-code` to catch schema drift **only when `flatc` is present** (keeps CI on bundled tools per Phase 1 ethos). `.fbs` at `Packages/CortexIPC/Schemas/sample.fbs`; generated Swift in `CortexIPCSession`. FlatBuffers Swift runtime added as a SwiftPM dependency (`google/flatbuffers`).

### AES-GCM key & nonce lifecycle
- **D-14:** **Session = one daemon-process lifetime.** On launch the daemon generates a **random 256-bit secret** (`SymmetricKey(size: .bits256)`); HKDF-Expand derives the working subkeys. The random secret is stored in **Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, IPC-06). Fresh key per launch → nonce space resets safely each session. Satisfies IPC-05 "HKDF-derived per-session keys."
- **D-15:** **Key shared via a shared Keychain access group** (same team + shared `keychain-access-group` entitlement) so the secret round-trips Keychain per SC#3. **HKDF-Expand into two subkeys** with distinct `info` labels — `daemon→app` and `app→ack` — so each direction has its own key + nonce domain (no cross-direction reuse). Pairs with the ack-bounce round-trip (D-02).
- **D-16:** **GCM nonce = 96-bit deterministic** = `(key-epoch/direction prefix || monotonic message counter)`, **reusing the shm doorbell sequence number (D-12 `seq`) as the counter** — free and elegant. Guaranteed unique per `(key, direction)` (NIST SP 800-38D deterministic-IV construction). On counter exhaustion or daemon restart, a fresh session key (D-14) resets the space. **No per-frame RNG on the hot path.**

### Measurement
- **D-17:** **SC#1 rigor:** n ≥ **100k** frames; report **p50 / p99 / σ** (SC#1 names p99); discard a **warm-up** prefix (~first 1k); pin QoS during the run; **commit the histogram + raw samples + a methodology note** (mirrors Phase 1 `sc2-evidence.md` and the photodiode n=10k discipline).
- **D-18:** **The sub-µs-on-M4 timing claim is measured on real M4 hardware** and captured as committed evidence (manual benchmark + runbook, like `sc2-evidence.md`). **CI on `macos-15` runs the harness for CORRECTNESS only** (round-trip succeeds, AES-GCM decrypts, FD passes, schema/`_Static_assert` hold) — **never the timing claim** (the runner is M1, the claim is M4). Mirrors Phase 1's split (CI gates correctness; M-series hardware gates the perf number).

### Cross-phase commitments honored
- **Compile-time guarantees beat runtime:** `CORTEX_CHANNEL_COUNT` `_Static_assert` (D-11); the existing `CORTEX_SHM_NAME` assert already makes **Phase 2 SC#4 structurally satisfied** before any test runs.
- **Audio-callback discipline:** `CortexIPCTransport` is Foundation-free and the sole policed directory (D-04, D-05).

### Implementer's Discretion
- Ring depth (small power-of-two); exact doorbell payload encoding (index vs `seq` vs 1-byte kick + seq in a shm header); `kqueue` setup specifics (`EVFILT_READ` on the socket vs `EVFILT_USER`); exact HKDF `salt`/`info` label strings and Keychain item naming; the consumer-harness form (standalone exe vs XCTest `posix_spawn`); benchmark histogram bucketing; fail-closed error/teardown semantics on decrypt failure / partial read / peer death; the concrete mach service name for the bootstrap rendezvous; the per-target Swift isolation settings (the Transport hot path should avoid `MainActor`/actor hops — confirm `.defaultIsolation` on that target).

### Folded Todos
None — `todo match-phase 2` returned zero matches.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project spec (the source of every locked choice)
- `docs/cortex-spec.md` §4.1 — Hot-path thread rules (audio-callback discipline driving D-04/D-05)
- `docs/cortex-spec.md` §4.3 — Cross-process IPC: shm + `kqueue`+`recvmsg`, `mach_msg`+`MACH_MSG_PORT_DESCRIPTOR` FD passing (no `SCM_RIGHTS`), Darwin `PSHMNAMLEN` 31-byte limit
- `docs/cortex-spec.md` §4.4 — Wire format: FlatBuffers, `Sample { ts_ns:u64, channel_data:[f16] }`, uniform 0.5 ms blocks, ~200–400 ns encode/decode caveat
- `docs/cortex-spec.md` §4.5 — Crypto: AES-GCM via CryptoKit (FEAT_AES), HKDF per-session key, Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- `docs/cortex-spec.md` §9 — macOS gotchas (PSHMNAMLEN, deprecated shared-memory entitlement → App Group)

### Phase requirements & goal-backward targets
- `.planning/REQUIREMENTS.md` IPC-01 … IPC-07 — the acceptance bar for this phase
- `.planning/ROADMAP.md` "Phase 2" — the four numbered Success Criteria (goal-backward verification target)
- `.planning/PROJECT.md` Key Decisions table — IPC rows (`kqueue`+`recvmsg`, `mach_msg` FD passing, AES-GCM, App Group) and the **CortexDaemon packaging note** (D-09 resolves it)

### Prior-phase context (locked, carry-forward)
- `.planning/phases/01-foundation-2026-toolchain/01-CONTEXT.md` — **D-07** (App Group `group.com.donovansantine.cortex.shared`), **D-08** (`CORTEX_SHM_NAME` + compile-time assert; Phase 2 SC#4 already satisfied), **Cross-Phase Commitments** (compile-time guarantees; audio-callback discipline)

### Existing code Phase 2 builds on / replaces
- `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h` — `CORTEX_SHM_NAME`, the `cortex_shm_open` non-variadic shim, the `_Static_assert` (SC#4)
- `Packages/CortexCore/Sources/CortexCore/ShmCheck.swift` — Phase 1 cross-process shm proof (mmap/`ftruncate`/`MAP_SHARED` reference pattern); **to be replaced** by the real `CortexIPCTransport` ring (the file says so)
- `Packages/CortexCore/Sources/CortexCore/AppGroup.swift` — `containerURL()` (ring + Keychain flow through the App Group)
- `Packages/CortexCore/Sources/CortexCore/Time.swift` — `machAbsoluteNanoseconds()` (used for `ts_ns` and SC#1 timing)
- `Apps/CortexDaemon/main.swift` — current placeholder = Phase 2 **producer** skeleton
- `Packages/CortexIPC/Package.swift` + `Sources/CortexIPC/CortexIPC.swift` — the empty module to split (D-04)
- `Tools/scripts/hotpath-policy.sh` — the gate to re-scope (D-05)

### External Apple/library docs (planner: pull current versions via Context7 / WebFetch when wiring tasks)
- `mach_msg` / `MACH_MSG_PORT_DESCRIPTOR` / `fileport_makeport` / `bootstrap_look_up` (Mach IPC + FD passing)
- `kqueue(2)` / `EVFILT_READ`, `recvmsg(2)`, `socketpair(2)`
- CryptoKit `AES.GCM`, `HKDF`, `SymmetricKey`; NIST SP 800-38D (GCM deterministic-IV construction)
- Security framework Keychain `SecItem*` + `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` + `keychain-access-group`
- `SMAppService` (macOS 13+ daemon registration) — D-09
- FlatBuffers Swift (`google/flatbuffers`) + `flatc` schema compiler

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`cortex_shm.h`** — `CORTEX_SHM_NAME` + `cortex_shm_open` shim are exactly what the Transport ring opens; its `_Static_assert` already satisfies SC#4. The header is the canonical home for the new `CORTEX_CHANNEL_COUNT` assert (D-11).
- **`ShmCheck.swift`** — the `shm_open` → `ftruncate` → `mmap(MAP_SHARED)` sequence is the reference for the ring's mapping code; the file is explicitly slated for replacement by Phase 2.
- **`AppGroup.swift` / `Time.swift`** — container URL + `mach_absolute_time` wrapper, consumed directly.
- **`CortexDaemon/main.swift`** — already opens the shared region and blocks; becomes the harness producer.

### Established Patterns
- **`hotpath-policy.sh`** forbidden-token gate (re-scope per D-05; it's a "trap pre-armed" from Phase 1).
- **Hardware-gated-claim evidence pattern** (`sc2-evidence.md` + manual runbook) → reuse for the SC#1 M4 timing evidence (D-18).
- **`_Static_assert` in a shared C header** as the compile-time-guarantee idiom → reuse for `CORTEX_CHANNEL_COUNT`.
- **CI = bundled-tools-only** (no `brew install`; `validate-privacy-manifest.sh` precedent) → keeps `flatc` vendored (D-13).
- **`.defaultIsolation(MainActor.self)`** is set on the Phase 1 packages — the Foundation-free Transport target must avoid `MainActor`/actor hops on the hot path; planner confirms isolation settings for `CortexIPCTransport`.

### Integration Points
- `CortexIPCTransport` consumes `CortexCoreC` (`cortex_shm.h`) for the ring; `CortexIPCSession` depends on `CortexIPCTransport`.
- Producer (daemon) + consumer (harness) both claim the App Group **and** a shared Keychain access group (D-15).
- **Phase 3** consumes the ring → Rust SPSC bridge; **Phases 4–5** decoder consumes the f16 `channel_data` layout (D-10/D-11); **Phase 8** wires the SMAppService daemon (D-09).

</code_context>

<specifics>
## Specific Ideas

- **Reuse the doorbell sequence number as the GCM nonce counter** (D-12 `seq` → D-16) — a deliberate unification the user endorsed: one monotonic counter serves both ring ordering and nonce uniqueness.
- **Per-direction HKDF subkeys** (D-15) are paired intentionally with the **ack-bounce round-trip** (D-02) so the return path has its own key+nonce domain.
- **The `CORTEX_CHANNEL_COUNT` compile-time assert** mirrors the `cortex_shm.h` precedent the user called load-bearing in Phase 1 ("compile-time guarantees beat runtime ones").
- **CI never measures the latency claim** — the M1 runner can only attest correctness; the sub-µs-on-M4 number is hardware-gated evidence, exactly as Phase 1 handled SC#2.

</specifics>

<deferred>
## Deferred Ideas

| Idea | Belongs in | Why deferred |
|------|------------|--------------|
| Move per-frame AES-GCM onto the Foundation-free pthread hot path (CommonCrypto / swift-crypto) | Phase 3 | Decide after profiling shows the encrypt step is on the `USER_INTERACTIVE` hot path (D-06) |
| SMAppService register/install + code-signing wiring for the production daemon | Phase 8 | Needs Apple Developer enrollment (Phase 1 D-09); D-09 only *names* the form now |
| Wiring frames into the CortexMac/CortexiOS UI and the decoder | Phases 3–7 | Phase 2 is the transport primitive only (D-07) |
| Rust SPSC ring + `cbindgen` bridge consuming the shm ring | Phase 3 | Sample-transport decoder→UI path is a separate phase |

### Reviewed Todos (not folded)
None — `todo match-phase 2` returned zero matches.

</deferred>

---

*Phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm*
*Context gathered: 2026-06-19*
