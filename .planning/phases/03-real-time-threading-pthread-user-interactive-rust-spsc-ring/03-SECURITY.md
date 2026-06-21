---
phase: 03
slug: real-time-threading-pthread-user-interactive-rust-spsc-ring
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-20
---

# Phase 03 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Threat definitions are the source of truth from the four PLAN `<threat_model>` blocks
> (03-01..04). Mitigation evidence (`file:line`) verified in-code by `gsd-security-auditor`
> on 2026-06-20 (verdict: SECURED, 18/18 closed). ASVS L1, block-on: high.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Swift → Rust (C ABI) | `import CortexRingFFI` (the `CortexRing` wrapper, the `CortexRingHotPath` worker, and the `cortex_ping` smoke) calls `extern "C"` functions; Swift passes raw pointers (`*mut CortexSpsc`, `*const/*mut CortexFrame`) the Rust side treats as untrusted | opaque ring handle, `CortexFrame` POD by pointer, `usize` capacity, `u32` scalar, `bool` returns |
| Producer thread ↔ Consumer thread (SPSC) | Two threads share the ring via atomics; correctness rests on the single-producer/single-consumer contract and Release/Acquire ordering | `CortexFrame` slots; 128-byte-padded head/tail atomic indices |
| Rust panic → C frame | A Rust panic unwinding across an `extern "C"` boundary is undefined behavior | (control flow; no data) |
| Swift caller → pthread worker | A POD `AcqThreadArg` (raw handles + Ints) crosses the `@convention(c)` boundary; no Swift class crosses as a tracked value | unretained ring handle, frame count |
| build-rust.sh → xcframework | Build script produces the binary artifact the SwiftPM `.binaryTarget` links unsigned | per-target `.a` static libs + committed C header + modulemap |
| Hot-path source tree → CI policy gate | `hotpath-policy.sh` is the enforced contract that no cooperative-runtime / lock / Foundation token enters the policed dirs (`.swift`/`.c`/`.rs`) | (source text) |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation (evidence) | Status |
|-----------|----------|-----------|-------------|------------------------|--------|
| T-03-01-01 | Tampering | `rust/src/frame.rs` | mitigate | `const _: () = assert!(size_of::<CortexFrame>() == 16 + CORTEX_CHANNEL_COUNT*2)` — `frame.rs:37` (negative control proven, E0080) | closed |
| T-03-01-02 | Denial of Service (panic-across-FFI = UB) | `rust/src/ffi.rs` | mitigate | `catch_unwind` on all 5 `extern "C"` bodies — `ffi.rs:67,77,106,130,162`; `#![deny(improper_ctypes_definitions)]` — `lib.rs:11` | closed |
| T-03-01-03 | Tampering | `rust/include/cortex_ring.h` | mitigate | Vendored header + CI `git diff --exit-code …cortex_ring.h` drift gate — `ci.yml:177` | closed |
| T-03-01-04 | Spoofing/Tampering | `CortexRingFFI.xcframework` (unsigned binary artifact) | accept | Built in-CI/locally from in-repo Rust source by `build-rust.sh`, gitignored, no third-party binary trust — see Accepted Risks Log | closed |
| T-03-01-05 | Information Disclosure | `cortex_ping` / build logs | accept | `cortex_ping` is pure arithmetic (`x ^ 0x5A5A5A5A`, no secret); `build-rust.sh` logs only target triples + tool versions — see Accepted Risks Log | closed |
| T-03-02-01 | Tampering (use-after-free) | `rust/src/ffi.rs` `cortex_spsc_destroy` | mitigate | Null guard + `Box::from_raw` reconstructs and drops exactly once — `ffi.rs:161-173` | closed |
| T-03-02-02 | Tampering (double-free / uninit-leak) | `rust/src/spsc.rs` `Drop` | mitigate | `Drop for Spsc<T>` drains only initialized `[head, tail)` slots via `assume_init_drop` — `spsc.rs:96-116` | closed |
| T-03-02-03 | Information Disclosure / OOB (null/bad ptr deref) | `rust/src/ffi.rs` push/pop | mitigate | `if r.is_null() \|\| f.is_null() { return false }` before any deref — `ffi.rs:108,132`; slot index always `& mask` | closed |
| T-03-02-04 | Tampering (integer overflow / bad capacity) | `rust/src/ffi.rs` `cortex_spsc_create` | mitigate | `if !capacity.is_power_of_two() { return null_mut() }` — `ffi.rs:81` | closed |
| T-03-02-05 | Denial of Service (panic-across-FFI = UB) | `rust/src/ffi.rs` all exports | mitigate | `catch_unwind` retained on every real body + `#![deny(improper_ctypes_definitions)]` (`lib.rs:11`) | closed |
| T-03-02-06 | Tampering (data race / wrong ordering) | `rust/src/spsc.rs` | mitigate | Release store `spsc.rs:164`, Acquire loads `141,192`; no SeqCst (grep empty); `#[repr(align(128))]` + align assert `spsc.rs:37,42`; loom test `tests/loom_spsc.rs` + CI `--cfg loom` `ci.yml:168` | closed |
| T-03-03-01 | Tampering (ARC/region-analysis crash or retain) | `Acquisition.swift` | mitigate | POD `AcqThreadArg` (raw handles + Int only) + non-optional `@convention(c)` + `.assumingMemoryBound` — `Acquisition.swift:48-60,98` | closed |
| T-03-03-02 | Elevation of Privilege (coop-runtime / Foundation creep) | `Acquisition.swift` + `hotpath-policy.sh` | mitigate | `import Darwin` only — `Acquisition.swift:40`; extended gate `DIRS_ARRAY` + `RUST_FORBIDDEN` + 3-language self-test — `hotpath-policy.sh:66,69-72,82` | closed |
| T-03-03-03 | Repudiation (silent SC#1 regression between manual M4 captures) | `instruments-evidence.md` + `hotpath-policy.sh` | mitigate | System-Trace runbook + `swift_task_*`/libdispatch pass criterion + D-18 manual-gate rationale; always-on gate is the CI proxy — `ci.yml:200` | closed |
| T-03-03-04 | Denial of Service (use-after-free of unretained ring handle) | `Acquisition.swift` | mitigate | `pthread_join(worker, nil)` blocks until the worker exits before the function returns — `Acquisition.swift:209` | closed |
| T-03-04-01 | Tampering (double-free / leak of the ring handle) | `Ring.swift` | mitigate | Failable `init?` returns nil on null create; `deinit` → `cortex_spsc_destroy` exactly once; no public manual destroy — `Ring.swift:37-49` | closed |
| T-03-04-02 | Tampering (Swift/Rust layout drift on CortexFrame) | `Ring.swift` | mitigate | `@_exported import CortexRingFFI` — `Ring.swift:5`; no `struct CortexFrame` mirror in Swift (grep empty); C type consumed directly via modulemap + cbindgen drift gate (T-03-01-03) | closed |
| T-03-04-03 | Information Disclosure (uninitialized pop output read) | `Ring.swift` `pop()` | mitigate | `var out = CortexFrame()` zero-inits before `&out`; returns `nil` when `cortex_spsc_pop` is false — `Ring.swift:71-73` | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-03-01 | T-03-01-04 | The `CortexRingFFI.xcframework` is built locally/in-CI from in-repo Rust source by `build-rust.sh` (not a downloaded prebuilt binary), is gitignored (never a committed opaque blob), and is consumed only within the same build — no third-party binary trust. Justified by the AGENTS.md constraints: in-process, on-device, single-user, no network fetch of the artifact. **Revisit at Phase 8 (signing) if a prebuilt xcframework is ever distributed.** | Phase 03 engineer | 2026-06-20 |
| AR-03-02 | T-03-01-05 | `cortex_ping` is a pure arithmetic smoke (`x ^ 0x5A5A5A5A`) carrying no secret; `build-rust.sh` logs only target triples + tool versions (mirrors `gen-flatbuffers.sh`). No PII/keys on this path — N/A by construction. | Phase 03 engineer | 2026-06-20 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-20 | 18 | 18 | 0 | gsd-security-auditor (sonnet), verdict SECURED |

**Verification scope (read-only, no implementation files modified):**
`rust/src/{frame,ffi,spsc,lib}.rs`, `rust/include/cortex_ring.h`, `rust/Cargo.toml`, `Sources/CortexRingHotPath/Acquisition.swift`, `Sources/CortexRing/Ring.swift`, `Tools/scripts/hotpath-policy.sh`, `.github/workflows/ci.yml`, `instruments-evidence.md`. No unregistered threat flags — all four SUMMARY threat surfaces map to registered IDs.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log (AR-03-01, AR-03-02)
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-20
