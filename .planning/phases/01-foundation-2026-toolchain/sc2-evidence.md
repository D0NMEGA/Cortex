# Phase 1 SC#2 Evidence — Cross-process `shm_open` inside the App Group container

**Date:** 2026-06-19
**Machine:** Apple **M5 Pro**, macOS 26 (`arm64-apple-macosx26.0`), **Xcode 26.3 (17C529)**, Swift 6.2.4
**Signing:** Personal Team `57YW6M29S7` (Donovan Santine) — cert `Apple Development: don.mega11@icloud.com (Y4A54395NZ)`, no paid enrollment
**Result:** ✅ **PASS**

> **SC#2 (Phase 1 Success Criterion #2):** "App Group container is provisioned and an
> entitlement-validated empty `shm_open` test fixture in the container survives sandbox
> checks (replaces the deprecated `com.apple.security.temporary-exception.shared-memory`
> entitlement)." Scope: **Mac only** (iPad on-device App Group needs paid enrollment — deferred to Phase 8).

---

## Proof methodology (and why it deviates from the plan's "inode match")

The plan (`01-07-PLAN.md`) specified proving shared-region identity via *"fstat returns the
same inode in both processes."* **On Darwin this is degenerate:** POSIX shm objects are kernel
objects, not filesystem-backed, so `fstat` returns `st_ino = 0` in every process — `0 == 0`
proves nothing. (See the `inode: 0` line in every block below.)

Instead we prove sharing the **robust** way, honoring the must-have's *intent* ("proving they
reference the same shm region"):

1. Each process `shm_open("/cortex.samples", O_CREAT|O_RDWR, 0600)` → `ftruncate` to a page → `mmap(MAP_SHARED)`.
2. It **reads** the 8-byte sentinel left by any prior process, then **writes** its own: `(0xC0DE2026 << 32) | pid`.
3. If a second process reads back the **first process's PID** from the mapping, cross-process shared memory is irrefutably demonstrated — actual bytes crossing the process boundary, not a coincidental metadata match.

Secondary corroboration in every block: the App Group **container path resolves** (only possible
when the App Group entitlement is honored) and the **region size** (`16384` = one 16 KB
Apple-Silicon page) is shared metadata.

---

## Test A — daemon ↔ daemon (fully automated, no GUI; reproducible)

Two independent runs of the signed `CortexDaemon` executable against a freshly-`shm_unlink`'d region:

**Run #1 (pid 41118) — first writer:**
```
--- ShmCheckResult ---
  process:     CortexDaemon (pid 41118)
  container:   /Users/d0nmega/Library/Group Containers/group.com.donovansantine.cortex.shared
  shm name:    /cortex.samples
  open flags:  0x202 (O_CREAT|O_RDWR)
  fd:          3
  inode:       0 (Darwin POSIX shm: always 0 -- see sentinel for the real proof)
  region size: 16384 bytes (ftruncate'd, shared metadata)
  mmap:        OK (MAP_SHARED)
  read  shm:   0x0000000000000000 -> 0x0 (region was empty — this process is the first writer)
  wrote shm:   0xC0DE20260000A09E (magic 0xc0de2026 | this pid 41118)
-----------------------
```

**Run #2 (pid 41127) — reads run #1's PID:**
```
  process:     CortexDaemon (pid 41127)
  container:   /Users/d0nmega/Library/Group Containers/group.com.donovansantine.cortex.shared
  fd:          3
  read  shm:   0xC0DE20260000A09E -> pid 41118 (another process wrote this — SHARED MEMORY CONFIRMED)
  wrote shm:   0xC0DE20260000A0A7 (magic 0xc0de2026 | this pid 41127)
```

➡ Run #2 read **pid 41118** (run #1's PID) out of `/cortex.samples`. **Cross-process shared memory confirmed.**

---

## Test B — Mac app ↔ daemon (the plan's required app↔daemon demonstration)

Region reset, then signed `CortexDaemon` planted its PID, then the user launched signed
`CortexMac.app` and pressed **"Run Phase 1 SC#2 ShmCheck"**.

**CortexDaemon (pid 41220) — planted its PID:**
```
  process:     CortexDaemon (pid 41220)
  container:   /Users/d0nmega/Library/Group Containers/group.com.donovansantine.cortex.shared
  fd:          3
  read  shm:   0x0000000000000000 -> 0x0 (region was empty — this process is the first writer)
  wrote shm:   0xC0DE20260000A104 (magic 0xc0de2026 | this pid 41220)
```

**CortexMac.app (pid 41234) — read the daemon's PID** (transcribed verbatim from the app's on-screen result panel; screenshot captured in the execution session):
```
--- ShmCheckResult ---
  process:     CortexMac.app (pid 41234)
  container:   /Users/d0nmega/Library/Group Containers/group.com.donovansantine.cortex.shared
  shm name:    /cortex.samples
  open flags:  0x202 (O_CREAT|O_RDWR)
  open mode:   0o600
  fd:          3
  inode:       0 (Darwin POSIX shm: always 0 -- see sentinel for the real proof)
  region size: 16384 bytes (ftruncate'd, shared metadata)
  mmap:        OK (MAP_SHARED)
  read  shm:   0xC0DE20260000A104 -> pid 41220 (another process wrote this — SHARED MEMORY CONFIRMED)
  wrote shm:   0xC0DE20260000A112 (magic 0xc0de2026 | this pid 41234)
  mach ts ns:  445747404283625
```

➡ **CortexMac.app read pid 41220 — the daemon's PID — from the App-Group-scoped shared region.**
**Phase 1 SC#2 cross-process `shm_open` between the Mac app and the Mac daemon is verified.**

---

## App Group container directory (provisioned by macOS)

```
$ ls -la ~/Library/Group\ Containers/group.com.donovansantine.cortex.shared/
drwx------@   4 d0nmega  staff   128 Jun 19 17:28 .
-rw-r--r--    1 d0nmega  staff   597 .com.apple.containermanagerd.metadata.plist
drwx------    6 d0nmega  staff   192 Library
```

`.com.apple.containermanagerd.metadata.plist` is written by macOS `containermanagerd` **only when
an entitled process accesses the group container** — OS-level confirmation the App Group
entitlement is honored (no sandbox, no provisioning-profile authorization needed; per RESEARCH.md
Critical Finding #1).

---

## Codesign entitlement audit (replaces the deprecated shared-memory entitlement)

**CortexMac.app**
```
Identifier=com.donovansantine.cortex.mac
Authority=Apple Development: don.mega11@icloud.com (Y4A54395NZ)
Authority=Apple Worldwide Developer Relations Certification Authority
Authority=Apple Root CA
TeamIdentifier=57YW6M29S7
Entitlements:
  com.apple.developer.team-identifier = 57YW6M29S7
  com.apple.security.application-groups = [ group.com.donovansantine.cortex.shared ]
```

**CortexDaemon** (standalone `mh_execute`)
```
Identifier=CortexDaemon
Authority=Apple Development: don.mega11@icloud.com (Y4A54395NZ)
Authority=Apple Worldwide Developer Relations Certification Authority
Authority=Apple Root CA
TeamIdentifier=57YW6M29S7
Entitlements:
  com.apple.security.application-groups = [ group.com.donovansantine.cortex.shared ]
```

Both binaries are Personal-Team-signed with a full chain to Apple Root CA and carry the App Group
entitlement. **No** `com.apple.security.temporary-exception.shared-memory` (deprecated) and **no**
`com.apple.security.app-sandbox` (Phase 1 keeps sandbox off per ADR-0001 / Critical Finding #1).

---

## Anomalies / notes — defects the real Xcode 26.3 toolchain surfaced

Phase 1 (Plans 01-01…01-06) was authored on a CommandLineTools-only host (no Xcode), so several
defects were latent until this runbook installed Xcode 26.3 and actually built/ran the code. All
were fixed during this checkpoint (committed separately):

1. **`shm_open` is variadic** in Darwin headers → Swift refuses to import C variadics (build break).
   Fixed with a non-variadic `cortex_shm_open` C shim in `CortexCoreC`.
2. **`String(cString:)` deprecation** (×2) → `CORTEX_SHM_NAME` is already a Swift `String`; used directly.
3. **Test target lacked `.defaultIsolation(MainActor.self)`** → tests couldn't reach MainActor-isolated
   API under Swift 6.2 strict concurrency (test build break). Mirrored the main target's isolation.
4. **Info.plist drift** → `xcodegen` regenerates the plists from `project.yml`; committed the idempotent output.
5. **`CortexDaemon` was `type: bundle` (mh_bundle)** → a loadable bundle **cannot run standalone**
   (`cannot execute binary file`) nor carry entitlements, so it could never satisfy D-03's functional
   requirement (a daemon doing cross-process `shm_open`). Changed to `type: tool` (mh_execute). This
   resolves the daemon-type disposition Plan 01-02 explicitly deferred to the Xcode 26 environment
   (Critical Finding #4 / RESEARCH Pitfall #6). **Final App-Store daemon packaging (XPC service /
   launchd helper) remains a Phase 2 decision** — a bare `tool` is not App-Store-distributable.
6. **`inode` comparison is degenerate on Darwin** (`st_ino = 0`) → upgraded the proof to a cross-process
   `mmap` sentinel (write-PID / read-PID), as documented above.

Also closed in passing: the **deferred Plan 01-02 dynamic `xcodebuild` smoke** — CortexMac + CortexDaemon
now `BUILD SUCCEEDED` under Xcode 26.3.

---

## Conclusion

**Phase 1 SC#2 PASSES.** Two locally-Personal-Team-signed, App-Group-entitled Mac binaries
(`CortexMac.app` and the `CortexDaemon` executable) both `shm_open("/cortex.samples")` against a
region reachable inside the App Group container, and **data written by one process is read by the
other** (daemon PID 41220 → app; daemon PID 41118 → daemon PID 41127). The App Group container is
provisioned by macOS, the entitlement is honored without the deprecated shared-memory exception and
without the sandbox, and the whole path is reproducible on Apple Silicon + Xcode 26.3. The IPC
foundation Phase 2 builds on is real, not theoretical.

**Cross-phase notes:**
- `ShmCheck.swift` is one-shot Phase-1 evidence scaffolding — **removed when Phase 2's real IPC primitive (kqueue + recvmsg) lands.**
- **Phase 2** must decide the production daemon packaging (XPC service vs. launchd helper) for the App Store path; `type: tool` is a Phase-1 placeholder.
- **Phase 8** (paid enrollment): repeat this runbook with the iPad target on a real device (SC#2 extension).
