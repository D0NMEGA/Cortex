---
phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm
plan: 03
subsystem: api
tags: [flatbuffers, cryptokit, aes-gcm, hkdf, keychain, security-framework, float16, nist-sp-800-38d]

# Dependency graph
requires:
  - phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm (Plan 02-01)
    provides: "CortexIPCSession Foundation-allowed target; FlatBuffers runtime pinned (resolved 25.12.19, Package.resolved); CORTEX_CHANNEL_COUNT (=96) + _Static_assert in cortex_shm.h; CF#1 = FAIL verdict (single-process Keychain + key-over-mach_msg fallback)"
provides:
  - "FlatBuffers Sample { ts_ns; channel_data:[ubyte]; seq } schema + vendored flatc-25.12.19 Swift (CF#7 version-matched) + SampleCodec with zero-copy [ubyte]<->Float16 rebind and the channel_data.count == CORTEX_CHANNEL_COUNT*2 invariant on encode AND decode (IPC-04)"
  - "SessionCrypto: AES-GCM seal/open, HKDF<SHA256> two per-direction subkeys (daemon->app / app->ack), 96-bit deterministic nonce = 4-byte prefix || 8-byte big-endian seq reusing the ring seq, fail-closed open() (IPC-05, D-14/D-15/D-16)"
  - "SessionKeychain: data-protection Keychain round-trip (kCFBooleanTrue, AfterFirstUnlockThisDeviceOnly), CF#1 fallback (no access group), Backend test-seam (.dataProtection production / .legacyFile test) (IPC-06)"
  - "Tools/scripts/gen-flatbuffers.sh — vendored codegen with a nonisolated post-process; flatc 25.12.19 installed to ~/.local/bin"
affects: [phase-02-plan-04-harness-rendezvous, phase-03-pthread-hotpath, phase-04-decoder-f16-layout, phase-08-distribution-enrollment]

# Tech tracking
tech-stack:
  added:
    - "flatc 25.12.19 (FlatBuffers schema compiler, installed ~/.local/bin) — matches the SwiftPM runtime exactly (CF#7)"
    - "CryptoKit AES.GCM + HKDF<SHA256> + SymmetricKey (NIST SP 800-38D deterministic-IV construction)"
    - "Security framework SecItemAdd/CopyMatching/Delete on the data-protection keychain (production)"
  patterns:
    - "Vendored flatc codegen + scripted nonisolated post-process: gen script injects `nonisolated` on the generated table struct so the codec is callable off the MainActor-isolated target default (regen stays reproducible without hand-editing generated code)"
    - "nonisolated value-transform layer inside a MainActor-default target: stateless codec/crypto/keychain marked `nonisolated` so the Foundation-free Transport consumer (Plan 02-04) can call them off the main actor"
    - "NIST SP 800-38D deterministic-IV: per-direction HKDF subkey + per-direction 4-byte nonce prefix + monotonic seq counter + fresh-secret-per-launch → no (key,nonce) reuse, no per-frame RNG"
    - "Keychain Backend test-seam: production .dataProtection (IPC-06 attributes) + test-only .legacyFile so an unentitled swift-test host can exercise the round-trip logic"

key-files:
  created:
    - "Packages/CortexIPC/Schemas/sample.fbs"
    - "Packages/CortexIPC/Sources/CortexIPCSession/generated/sample_generated.swift"
    - "Packages/CortexIPC/Sources/CortexIPCSession/SampleCodec.swift"
    - "Packages/CortexIPC/Sources/CortexIPCSession/SessionCrypto.swift"
    - "Packages/CortexIPC/Sources/CortexIPCSession/SessionKeychain.swift"
    - "Packages/CortexIPC/Tests/CortexIPCSessionTests/SampleCodecTests.swift"
    - "Packages/CortexIPC/Tests/CortexIPCSessionTests/CryptoTests.swift"
    - "Packages/CortexIPC/Tests/CortexIPCSessionTests/KeychainTests.swift"
    - "Tools/scripts/gen-flatbuffers.sh"
  modified:
    - "Packages/CortexIPC/Sources/CortexIPCSession/Placeholder.swift (removed — replaced by real Session sources)"
    - "Packages/CortexIPC/Tests/CortexIPCSessionTests/Placeholder.swift (removed — replaced by real test suites)"

key-decisions:
  - "flatc 25.12.19 prebuilt macOS binary obtained from the v25.12.19 GitHub release, verified `flatc --version` == 25.12.19 == the FlatBuffers SwiftPM runtime (Package.resolved). CF#7 satisfied: generator and runtime match exactly. flatc was RUN locally (not hand-matched); the generated Swift is committed verbatim apart from a scripted `nonisolated` injection on the struct decl."
  - "HKDF info labels: 'cortex.daemon->app.v1' / 'cortex.app->ack.v1' (D-15). Nonce prefixes: daemon->app = [0xC0,0x01,0x00,0x01], app->ack = [0xC0,0x01,0x00,0x02] (D-16). Both the subkey AND the prefix differ per direction → no cross-direction (key,nonce) collision is structurally possible."
  - "CF#1 branch taken = FALLBACK (single-process + key-over-mach_msg). SessionKeychain OMITS kSecAttrAccessGroup (default access group); `deferredAccessGroup` = 'Y4A54395NZ.group.com.donovansantine.cortex.shared' is the single named constant Phase 8 flips on under an enrolled team prefix. D-14/D-15 reconciliation: secret-in-Keychain + HKDF per-direction subkeys honored now; share-via-access-group deferred to Phase 8."
  - "CF#1 corollary discovered this plan: the data-protection keychain is unreachable from any binary on this machine without a paid-team provisioning profile (unentitled → -34018; entitled → AMFI SIGKILL 137). A Backend enum keeps production = .dataProtection (IPC-06 unchanged) while KeychainTests inject .legacyFile to run the round-trip on the unentitled swift-test host."
  - "open()/decode() are fail-closed (D-58): CryptoKit's authentication error and getCheckedRoot's verifier rejection propagate; no try? swallow. Caller drops the frame / tears down."

patterns-established:
  - "Vendored codegen + reproducible scripted post-process — the model for any future flatc/protoc-style generated artifact under a MainActor-default target."
  - "Deterministic-IV AEAD with the ring seq as the GCM counter — the crypto contract Plan 02-04's producer/consumer ack-bounce implements."

requirements-completed: [IPC-04, IPC-05, IPC-06]

# Metrics
duration: 11min
completed: 2026-06-20
---

# Phase 2 Plan 03: CortexIPCSession — FlatBuffers Codec + AES-GCM/HKDF + Keychain Summary

**FlatBuffers Sample codec with zero-copy [ubyte]<->Float16 rebind (flatc 25.12.19 == runtime, CF#7), AES-GCM + HKDF per-direction subkeys + NIST SP 800-38D deterministic seq-nonce (fail-closed), and a data-protection Keychain round-trip on the CF#1 single-process fallback.**

## Performance

- **Duration:** ~11 min
- **Started:** 2026-06-20T07:04Z
- **Completed:** 2026-06-20T07:15Z
- **Tasks:** 3 / 3 (all autonomous; no checkpoint returned)
- **Files created/modified:** 9 created, 2 removed (the Plan 02-01 Session placeholders)

## Accomplishments

- **IPC-04 (Task 1):** `sample.fbs` (`table Sample { ts_ns:ulong; channel_data:[ubyte]; seq:ulong } root_type Sample`) compiled by `flatc 25.12.19` to vendored Swift, committed in-repo (D-13). `SampleCodec` builds/reads the frame, rebinds `channel_data` `[ubyte]`↔`Float16` **zero-copy** via the generated `withUnsafePointerToChannelData` slice hook + `withMemoryRebound` (no element loop, D-10), enforces `channel_data.count == CORTEX_CHANNEL_COUNT * 2` on **both** encode and decode, and uses `getCheckedRoot` (FlatBuffers verifier) so garbage/truncated buffers are rejected fail-closed (D-58). 5 @Test pass.
- **IPC-05 (Task 2):** `SessionCrypto` generates a random 256-bit secret (`SymmetricKey(size: .bits256)`, D-14), HKDF-expands it into two per-direction subkeys (D-15), and seals/opens with AES-GCM using a 96-bit deterministic nonce = 4-byte per-direction prefix ‖ 8-byte big-endian `seq` reusing the ring counter (D-16, NIST SP 800-38D §8.2.1). `open()` is fail-closed. 6 @Test pass, including the **nonce-uniqueness-across-seq** and **cross-direction (key,nonce) isolation** cases that defend the one HIGH-severity Phase-2 threat (T-02-03-01, GCM nonce reuse).
- **IPC-06 (Task 3):** `SessionKeychain` round-trips the secret through the **data-protection** Keychain — `kSecUseDataProtectionKeychain = kCFBooleanTrue!` (CF#8, never Swift `true`) + `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Took the **CF#1 FALLBACK**: no `kSecAttrAccessGroup` (default access group, single-process). 5 @Test pass.
- **Full suite green:** `swift build` + `swift test --package-path Packages/CortexIPC` = 3 suites / 16 @Test, 0 failures. Hot-path gate still clean (Session is Foundation-allowed, not policed, CF#4).

## CF#7 — flatc / runtime version match

- **FlatBuffers Swift runtime:** `25.12.19` (Package.resolved, pinned in Plan 02-01).
- **flatc generator:** `25.12.19` — the prebuilt `Mac.flatc.binary.zip` from the GitHub `v25.12.19` release, verified `flatc --version` == `25.12.19`, installed to `~/.local/bin/flatc`.
- **Match:** generator == runtime → **CF#7 satisfied**. flatc was **run locally** (not hand-matched). The committed `sample_generated.swift` is flatc's verbatim output plus one scripted transform: `gen-flatbuffers.sh` injects `nonisolated` on `public struct Cortex_IPC_Sample` (see Deviation 2). Regen is reproducible and idempotent.

## HKDF / nonce scheme (D-15 / D-16) + deterministic-IV rationale

- **Per-direction subkeys (D-15):** `HKDF<SHA256>.expand(pseudoRandomKey: secret, info: Data("cortex.daemon->app.v1".utf8), outputByteCount: 32)` and the same with `"cortex.app->ack.v1"`. The secret is a uniformly-random 256-bit PRK, so HKDF-Expand alone (no extract/salt) is the correct RFC 5869 step.
- **Deterministic 96-bit nonce (D-16):** `noncePrefix(4) ‖ seq.bigEndian(8)` = exactly 12 bytes (the size `AES.GCM.Nonce` requires). Prefixes: `[0xC0,0x01,0x00,0x01]` (daemon→app), `[0xC0,0x01,0x00,0x02]` (app→ack). The `seq` is the monotonic ring/doorbell counter (D-12) — **no per-frame RNG**.
- **Rationale (NIST SP 800-38D §8.2.1):** uniqueness of `(key, nonce)` rests on (a) a distinct subkey per direction, (b) a distinct 4-byte prefix per direction, and (c) the injective monotonic 8-byte counter within a direction. A fresh random secret per daemon launch (D-14) resets the entire space on restart/exhaustion, so the counter cannot wrap into a reused pair within one session. `CryptoTests` asserts distinct-seq→distinct-nonce, the 12-byte prefix‖bigEndian(seq) layout, cross-direction nonce divergence, that a frame sealed for one direction fails to open with the other's key, and that distinct secrets isolate keyspaces.

## CF#1 branch + D-14/D-15 reconciliation (for Plan 02-04)

- **Branch taken: FALLBACK** (CF#1 = FAIL, 02-SPIKES.md). `SessionKeychain.baseQuery(.dataProtection)` **omits** `kSecAttrAccessGroup` → the app's default access group (single-process round-trip), which needs no provisioning profile and satisfies SC#3 + IPC-06.
- **Deferred access-group constant:** `SessionKeychain.deferredAccessGroup = "Y4A54395NZ.group.com.donovansantine.cortex.shared"` — currently UNUSED (not added to the query), doc-commented for Phase 8 to flip on under the enrolled team prefix (free team `Y4A54395NZ` → enrolled prefix).
- **Reconciliation:** the "secret in Keychain + HKDF per-direction subkeys" half of D-14/D-15 is **honored now**; the "share via shared Keychain access group" half is **deferred to Phase 8**. In Phase 2 the peer receives the secret over the secure `mach_msg` channel (Plan 02-04), NOT via a shared access group.

## Fail-closed semantics (D-58)

- `SessionCrypto.open()` uses plain `try` on `AES.GCM.open` — any ciphertext/tag/nonce tamper makes CryptoKit throw `CryptoKitError`; it propagates (no `try?`). `CryptoTests` proves a flipped ciphertext byte, a flipped tag byte, AND opening at the wrong `seq` all throw.
- `SampleCodec.decode()` uses `getCheckedRoot` (FlatBuffers verifier) → `SampleCodecError.malformedBuffer` on a truncated/garbage buffer, and `badChannelCount` when `channel_data` byte length ≠ `CORTEX_CHANNEL_COUNT*2`, before the zero-copy rebind (so the Float16 view never indexes past the vector).
- Caller contract: drop the frame / tear the session down (Plan 02-04 wires this on the consumer).

## Task Commits

Each task committed atomically (`--no-verify`, isolated worktree executor running concurrently with Plan 02-02):

1. **Task 1: FlatBuffers Sample schema + vendored codec (IPC-04)** — `f3ccf41` (feat)
2. **Task 2: SessionCrypto — AES-GCM + HKDF subkeys + deterministic nonce (IPC-05)** — `0f6ab55` (feat)
3. **Task 3: SessionKeychain — data-protection round-trip, CF#1 fallback (IPC-06)** — `3662456` (feat)

**Plan metadata:** committed with this SUMMARY (docs).

_Note: the orchestrator owns STATE.md / ROADMAP.md / REQUIREMENTS.md writes after the wave completes — this plan did not touch them._

## Files Created/Modified

- `Packages/CortexIPC/Schemas/sample.fbs` — the `Sample` wire schema (IPC-04, D-12)
- `Packages/CortexIPC/Sources/CortexIPCSession/generated/sample_generated.swift` — vendored flatc-25.12.19 Swift (`Cortex_IPC_Sample`), `nonisolated`-injected
- `Packages/CortexIPC/Sources/CortexIPCSession/SampleCodec.swift` — encode/decode, zero-copy Float16 rebind, length invariant, getCheckedRoot
- `Packages/CortexIPC/Sources/CortexIPCSession/SessionCrypto.swift` — AES-GCM + HKDF per-direction subkeys + deterministic seq-nonce, fail-closed
- `Packages/CortexIPC/Sources/CortexIPCSession/SessionKeychain.swift` — data-protection Keychain round-trip, CF#1 fallback, Backend test-seam
- `Packages/CortexIPC/Tests/CortexIPCSessionTests/{SampleCodecTests,CryptoTests,KeychainTests}.swift` — 5 / 6 / 5 @Test
- `Tools/scripts/gen-flatbuffers.sh` — vendored codegen + nonisolated post-process (D-13)
- Removed `Packages/CortexIPC/Sources/CortexIPCSession/Placeholder.swift` and `Tests/CortexIPCSessionTests/Placeholder.swift` (Plan 02-01 stubs, now superseded)

## Decisions Made

- **flatc obtained as a verified 25.12.19 prebuilt** (not built from source, not brew — brew would likely mismatch). Installed system-wide per standing authority; `gen-flatbuffers.sh` guards on `command -v flatc` so CI without flatc still builds against the committed Swift (D-13 bundled-tools ethos).
- **Codec/crypto/keychain are `nonisolated`.** The `CortexIPCSession` target sets `.defaultIsolation(MainActor.self)` (Plan 02-01, set when the target was empty). These are stateless pure value transforms and are explicitly consumed by the **Foundation-free Transport consumer off the main actor** (Plan 02-04 cross-plan note). Marking them `nonisolated` is the correct contract; Package.swift was deliberately NOT edited (out of scope for the wave — the per-declaration `nonisolated` achieves the same without racing on the manifest).
- **`HKDF<SHA256>.expand`** chosen over `deriveKey` to match the plan's exact interface contract and the acceptance grep (`HKDF<SHA256>`); both are RFC-5869-correct for a high-entropy PRK.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] flatc not installed → obtained + installed flatc 25.12.19 (CF#7)**
- **Found during:** Task 1 (codegen step)
- **Issue:** `flatc` was absent; the vendored generated Swift (D-13) cannot be produced, and CF#7 requires the generator to equal the runtime (25.12.19).
- **Fix:** Downloaded the prebuilt `Mac.flatc.binary.zip` from the GitHub `v25.12.19` release, verified `flatc --version` == `25.12.19`, installed to `~/.local/bin/flatc`, ran `gen-flatbuffers.sh`. Generator == runtime.
- **Files modified:** `Packages/CortexIPC/Sources/CortexIPCSession/generated/sample_generated.swift` (generated)
- **Verification:** `flatc --version` == 25.12.19; SampleCodec compiles + 5 @Test pass against the real runtime.
- **Committed in:** `f3ccf41` (Task 1)

**2. [Rule 3 - Blocking] MainActor-default target made the codec + generated code unusable off the main actor → `nonisolated` (incl. a scripted gen post-process)**
- **Found during:** Task 1 (first build)
- **Issue:** `CortexIPCSession` sets `.defaultIsolation(MainActor.self)`, so the generated `Cortex_IPC_Sample` accessors, the codec statics, and the two top-level count constants became MainActor-isolated — uncallable from the nonisolated codec and from the Plan 02-04 off-main-actor consumer (`error: main actor-isolated ... can not be referenced from a nonisolated context`).
- **Fix:** Marked `SampleCodec`/`DecodedSample`/`SessionCrypto`/`SessionKeychain` + their error/Direction/Keys types `nonisolated`, and the two count constants `nonisolated let`. For the **generated** file (must not hand-edit), added a deterministic, idempotent `sed` step to `gen-flatbuffers.sh` that injects `nonisolated` on the `public struct Cortex_IPC_*` decl — keeping regen reproducible (committed file == flatc output + this one scripted transform). Package.swift was NOT edited (out of scope for the wave).
- **Files modified:** all four Session sources; `Tools/scripts/gen-flatbuffers.sh`; `generated/sample_generated.swift`
- **Verification:** clean build (no isolation errors, no warnings); 16 @Test pass; gate clean.
- **Committed in:** `f3ccf41` (Task 1)

**3. [Rule 3 - Blocking] Data-protection keychain unreachable from the unentitled swift-test host → Backend test-seam (production stays data-protection)**
- **Found during:** Task 3 (running KeychainTests)
- **Issue:** Tests against the data-protection keychain returned `errSecMissingEntitlement (-34018)`. A focused probe (`/tmp/kc-probe`, mirroring the CF#1 spike method) proved this is the **CF#1 mechanism extended to the default access group**: unentitled → -34018; ad-hoc-signed with `application-identifier` OR `keychain-access-groups` → **AMFI SIGKILL (exit 137)** under the free team. So the data-protection keychain cannot be exercised by any binary here without a paid-team provisioning profile. The legacy (file) keychain, however, round-trips unentitled (verified: add=0, copy=0, MATCH=true).
- **Fix:** Added a `SessionKeychain.Backend` enum. Production APIs default to `.dataProtection` (all IPC-06 attributes UNCHANGED — `kCFBooleanTrue`, `AfterFirstUnlockThisDeviceOnly`, no access group). `KeychainTests` inject `.legacyFile` to exercise the round-trip/not-found/idempotent **logic** on the unentitled host, PLUS a test that asserts `baseQuery(.dataProtection)` carries the data-protection attributes (CFBoolean true + AfterFirstUnlock + no access group). The directive's mandate ("the data-protection flag is the IPC-06 requirement — keep it") is honored: production is unchanged; only the test path is adapted. The full data-protection round-trip's item SHAPE was already built+signed+run on real M4 by the CF#1 spike, and its complete round-trip is exercised under enrollment in Phase 8.
- **Files modified:** `Packages/CortexIPC/Sources/CortexIPCSession/SessionKeychain.swift`, `Packages/CortexIPC/Tests/CortexIPCSessionTests/KeychainTests.swift`
- **Verification:** 5 @Test pass; the CF#8 negative grep (`! grep -qE 'kSecUseDataProtectionKeychain[^!]*:\s*true'`) passes; the production-query test confirms the data-protection attributes are wired.
- **Committed in:** `3662456` (Task 3)

---

**Total deviations:** 3 auto-fixed (all Rule 3 - blocking).
**Impact on plan:** All three were necessary to make the plan's own acceptance criteria pass on this machine. No scope creep, no architectural change to the production crypto/codec/Keychain contract: the schema, the zero-copy rebind, the HKDF/nonce construction, and the data-protection production query are exactly as the plan specified. Deviation 3 is the directive-anticipated test-host adaptation (a test seam, not a production weakening) and is itself an extension of the existing CF#1 verdict.

## Threat Flags

None — no security surface beyond the plan's `<threat_model>` was introduced. The CF#1 corollary (data-protection keychain needs enrollment) tightens, not broadens, the existing T-02-03-06 disposition (single-process default access group is strictly narrower than a shared group).

## Issues Encountered

- **flatc binary quarantine:** the downloaded flatc carried the macOS quarantine xattr; cleared with `xattr -dr com.apple.quarantine`. No impact.
- **`nonisolated(unsafe)` warning:** the first attempt at the count constants used `nonisolated(unsafe)`, which the compiler flagged as unnecessary for a Sendable `Int`; switched to plain `nonisolated let` (warning-clean).

## User Setup Required

None for this plan's deliverables. Note for the maintainer: `flatc 25.12.19` is now at `~/.local/bin/flatc` (on PATH). To regenerate the schema later, ensure that flatc version is present (it must match the FlatBuffers SwiftPM runtime per CF#7) and run `Tools/scripts/gen-flatbuffers.sh`. The full data-protection-keychain round-trip + cross-process access-group sharing require paid Apple Developer Program enrollment (Phase 8).

## Next Phase Readiness

**Plan 02-04 (harness) is unblocked.** The Session layer it composes is complete and tested:
- **Producer path:** `SampleCodec.encode(...)` a `Sample` → `SessionCrypto.seal(plaintext, keys:, direction: .daemonToApp, seq:)` → write `ciphertext + tag` into a ring slot (the nonce is reconstructable from `seq`, not transmitted).
- **Consumer path:** read the slot → `SessionCrypto.open(ciphertext:, tag:, keys:, direction: .daemonToApp, seq:)` (rebuild the nonce from `seq`) → `SampleCodec.decode(...)`. The ack-bounce uses `.appToAck`.
- **Key delivery (CF#1 fallback):** the consumer receives the 256-bit secret **over the secure `mach_msg` channel** (Plan 02-02 / the CF#3 special-port rendezvous), NOT via a shared Keychain access group. Each process then calls `SessionKeys(secret:)` to derive its per-direction subkeys. (`SessionKeychain` stores/loads the secret single-process; cross-process sharing via access group is Phase 8.)
- All Session symbols are `nonisolated` → callable from the Foundation-free Transport consumer off the main actor.

**Blockers:** None. **Concurrency note:** ran file-disjoint from the Plan 02-02 executor (Transport dir) as designed.

## Self-Check: PASSED

(populated by the self-check step below)

---
*Phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm*
*Plan: 03 (CortexIPCSession — codec + crypto + Keychain — Wave 2)*
*Completed: 2026-06-20*
