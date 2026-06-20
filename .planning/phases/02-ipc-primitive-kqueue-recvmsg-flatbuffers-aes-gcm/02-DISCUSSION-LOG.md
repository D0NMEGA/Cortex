# Phase 2: IPC Primitive — kqueue+recvmsg + FlatBuffers + AES-GCM - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-19
**Phase:** 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm
**Areas discussed:** Transport split, Module layout vs hot-path Foundation ban, Daemon↔app rendezvous & Phase 2 scope, FlatBuffers schema shape & codegen, AES-GCM key & nonce lifecycle, Measurement artifact spec

Mode: discuss (advisor mode OFF — no USER-PROFILE.md). User selected all 4 initial gray areas, then opted into both additional areas offered.

---

## Transport split (shm vs socket)

### Topology
| Option | Description | Selected |
|--------|-------------|----------|
| shm ring = data, socket = doorbell | Encrypted frame in shm ring slot; socket carries only a 4–8 byte index/seq; consumer wakes on EVFILT_READ, reads frame zero-copy; crypto off the doorbell path | ✓ |
| Frame travels through recvmsg | Full encrypted frame as the recvmsg payload; shm barely used | |
| Hybrid (small inline, large via shm) | Threshold-based two-path | |

### SC#1 round-trip definition
| Option | Description | Selected |
|--------|-------------|----------|
| Frame delivery: write→doorbell→read | Producer write+ring → consumer wake → reads frame; reported as round-trip via ack bounce (producer→consumer→ack) | ✓ |
| Doorbell ping-pong floor | Empty notification bounced both ways; excludes shm read/decrypt | |
| One-way × 2 | Measure one-way, double it | |

**User's choice:** shm ring = data plane + socket = doorbell; round-trip = frame delivery via ack bounce.
**Notes:** Matches SC#1's "shm + socket pair" wording; keeps AES-GCM off the measured sub-µs path.

---

## Module layout vs hot-path Foundation ban

### Module structure
| Option | Description | Selected |
|--------|-------------|----------|
| Split: Transport (no-FDN) + Session (FDN) | CortexIPCTransport Foundation-free + policed; CortexIPCSession holds CryptoKit/Keychain/FlatBuffers; re-scope hotpath-policy DIRS to Transport | ✓ |
| Crypto/codec in CortexCore | Keep CortexIPC pure, put crypto/codec in the already-Foundation CortexCore | |
| Relax gate for all of CortexIPC | Drop the ban wholesale | |

### Crypto path
| Option | Description | Selected |
|--------|-------------|----------|
| CryptoKit+Data in Session now; profile Phase 3 | AES-GCM via CryptoKit (locked) in the Foundation-allowed layer; Phase 3 swaps to Foundation-free if profiling demands | ✓ |
| Commit to Foundation-free AES-GCM now | CommonCrypto/swift-crypto from day one | |

**User's choice:** Two-module split + re-scope the gate; CryptoKit now, revisit in Phase 3.
**Notes:** The hotpath-policy.sh comment explicitly anticipates narrowing DIRS to a subdir.

---

## Daemon↔app rendezvous & Phase 2 scope

### Phase 2 scope
| Option | Description | Selected |
|--------|-------------|----------|
| Two-process proof harness | CortexDaemon producer + new consumer exe / XCTest posix_spawn; proves SC#1–4 on the primitive | ✓ |
| Real CortexMac app ↔ CortexDaemon | Genuine app-to-daemon path now | |
| Both: harness for SC#1, thin app smoke | Harness carries the measured claim + minimal app smoke | |

### mach port rendezvous
| Option | Description | Selected |
|--------|-------------|----------|
| Harness: runtime bootstrap name | Parent publishes port under a runtime service name; child bootstrap_look_up → raw mach_msg FD pass | ✓ |
| launchd MachServices plist | Production-shaped plist + check_in/look_up | |
| XPC carries the port, raw mach_msg for the FD | XPC only for the initial port, raw mach_msg for the FD | |

### Production daemon packaging (deferred by PROJECT.md)
| Option | Description | Selected |
|--------|-------------|----------|
| Name SMAppService daemon now, wire in Phase 8 | Decide the form = SMAppService; defer install/signing to Phase 8 | ✓ |
| Classic LaunchDaemon plist + MachServices | Traditional launchd form | |
| XPCService bundle | XPCService-managed lifecycle | |
| Keep deferring to Phase 8 | No decision now | |

**User's choice:** Harness; runtime bootstrap name → raw mach_msg; SMAppService named now, wired Phase 8.
**Notes:** Resolves the PROJECT.md "CortexDaemon final form is a Phase 2 decision" open item.

---

## FlatBuffers schema shape & codegen

### f16 wire representation
| Option | Description | Selected |
|--------|-------------|----------|
| [ubyte] of raw IEEE-754 half bytes | Rebind to Swift Float16; maximally zero-copy, smallest | ✓ |
| [uint16] of f16 bit-patterns | More self-documenting; still reinterpreted | |
| [float] f32 on the wire | Doubles bandwidth; contradicts spec/ANE | |

### Channel count
| Option | Description | Selected |
|--------|-------------|----------|
| Fixed compile-time channel count | CORTEX_CHANNEL_COUNT + _Static_assert; constant frame size → fixed-stride ring; value confirmed Phase 4 | ✓ |
| Variable channel count per frame | Pure FlatBuffers vector semantics | |

### Codegen
| Option | Description | Selected |
|--------|-------------|----------|
| Vendor generated Swift + CI drift check | Commit flatc output; local regen script; optional CI flatc+git diff; .fbs at Packages/CortexIPC/Schemas/sample.fbs | ✓ |
| SwiftPM build-tool plugin runs flatc | flatc as a hard build/CI dependency | |

**User's choice:** [ubyte] raw f16 + fixed compile-time channel count + vendored flatc with CI drift check.
**Notes:** Mechanism fixed now; concrete channel value pinned against Zenodo 3854034 in Phase 4.

---

## AES-GCM key & nonce lifecycle

### Key origin / "session"
| Option | Description | Selected |
|--------|-------------|----------|
| Random per-launch secret → HKDF-expand | Session = daemon lifetime; random 256-bit secret in Keychain; HKDF-expand to subkeys | ✓ |
| Long-term Keychain root + per-session salt | Persistent root + exchanged salt | |
| Single static key in Keychain | No per-session derivation | |

### Key sharing / directionality
| Option | Description | Selected |
|--------|-------------|----------|
| Shared Keychain access group + 2 HKDF subkeys | daemon→app and app→ack subkeys via distinct info labels | ✓ |
| Shared access group + single key both directions | One key, partitioned nonce space | |

### Nonce strategy
| Option | Description | Selected |
|--------|-------------|----------|
| Monotonic counter (reuse doorbell seq), rekey on exhaustion | 96-bit deterministic IV (epoch/dir prefix ‖ counter); reuse ring seq; NIST SP 800-38D | ✓ |
| Random 96-bit nonce per frame | RNG per frame; birthday bound ~2^32/key | |

**User's choice:** Random per-launch secret + 2 directional HKDF subkeys + monotonic-counter nonce reusing the ring seq.
**Notes:** Nonce uniqueness guaranteed per (key, direction); fresh key per launch resets the space.

---

## Measurement artifact spec

### Rigor
| Option | Description | Selected |
|--------|-------------|----------|
| n≥100k, p50/p99/σ, warm-up discarded, histogram + raw committed | Tight p99 tail; methodology note; mirrors sc2-evidence.md | ✓ |
| n=10k, p50/p99/σ, histogram | Matches photodiode signature n | |
| Simple median over a short run | No warm-up / artifact | |

### Where measured / CI relationship
| Option | Description | Selected |
|--------|-------------|----------|
| Manual M4 benchmark + committed evidence; CI = correctness smoke only | Timing on M4 hardware; CI on macos-15 (M1) gates correctness only | ✓ |
| CI measures timing too | Rejected — M1 runner ≠ M4 claim | |

**User's choice:** n≥100k with warm-up discard + committed histogram/raw; timing measured on M4, CI = correctness only.
**Notes:** Exactly mirrors Phase 1's correctness-in-CI / perf-on-hardware split.

---

## Implementer's Discretion

Ring depth; doorbell payload encoding; kqueue setup specifics; HKDF salt/info label strings; Keychain item naming; consumer-harness form (exe vs XCTest posix_spawn); histogram bucketing; fail-closed error/teardown semantics; concrete mach service name; per-target Swift isolation settings for the Transport hot path.

## Deferred Ideas

Foundation-free AES-GCM on the pthread hot path (Phase 3); SMAppService install/signing wiring (Phase 8); app-UI + decoder frame wiring (Phases 3–7); Rust SPSC ring + cbindgen bridge consuming the shm ring (Phase 3).
