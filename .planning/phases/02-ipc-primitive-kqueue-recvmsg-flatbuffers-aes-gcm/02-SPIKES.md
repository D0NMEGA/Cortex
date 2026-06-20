# Phase 2 — Plan 02-01 Spike Outcomes (CF#1 Keychain + CF#3 Rendezvous)

**Run:** 2026-06-20 on the real M4 dev machine (NOT CI).
**Environment (verified live):**
- `xcode-select -p` = `/Applications/Xcode-26.3.0.app/Contents/Developer` (Xcode 26.3, NOT CommandLineTools)
- macOS 26.5 (Darwin 25, build 25F71); Swift 6.2.4; arch `arm64` (Apple Silicon M4)
- Signing identity: `Apple Development: don.mega11@icloud.com (Y4A54395NZ)` — SHA-1 `10382498625EDD5F29A1518B95A522B39AD047F3`

Both spikes were executed autonomously by the Plan 02-01 executor (the human-action precondition —
"a human at a signing-capable dev machine must build+sign+run the spike; CI cannot sign" — is
satisfied because the executor has Bash on a signing-capable Xcode-26.3 M4). The OSStatus / exit
codes below are REAL, captured from actual process runs.

> **TEAM-PREFIX DISCREPANCY (must-record):** The plan and project memory (`cortex-build-with-real-xcode`)
> assume **Team 57YW6M29S7**. The ACTUAL local signing identity is **Team Y4A54395NZ**
> (`don.mega11@icloud.com`), which is almost certainly a **FREE / personal** Apple team. All spike
> signing and the runtime `kSecAttrAccessGroup` use **Y4A54395NZ** so the CF#1 test is MEANINGFUL
> (a hardcoded 57YW6M29S7 prefix would fail spuriously since the binary is signed under Y4A54395NZ).
> When paid Apple Developer Program enrollment lands (Phase 8), reconcile the team prefix:
> swap Y4A54395NZ → the enrolled team's prefix in entitlements + any access-group strings.

---

## CF#1 Keychain access-group spike

**Goal:** Determine, on real M4 + Xcode 26.3 hardware, whether a bare Mach-O `tool` (CortexDaemon is
`type: tool`) can write a 32-byte session secret to the **data-protection keychain** under a
team-prefixed `keychain-access-groups` access group, and whether a SECOND process can read the
identical bytes back. This gates whether Plan 02-03 implements D-14/D-15 cross-process access-group
sharing as written, or falls back.

**Spike artifacts:**
- `Tools/spikes/keychain-access-group-spike/main.swift` — `write`/`read` modes; production item shape:
  `kSecClass=kSecClassGenericPassword`, `kSecUseDataProtectionKeychain=kCFBooleanTrue` (CF#8 — NOT
  Swift `true`), `kSecAttrAccount="cortex.session.secret"`,
  `kSecAttrAccessGroup="Y4A54395NZ.group.com.donovansantine.cortex.shared"`,
  `kSecAttrAccessible=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`;
  round-trip = `SecItemDelete` → `SecItemAdd` → `SecItemCopyMatching`. Prints OSStatus codes + a
  byte-MATCH boolean ONLY — never the secret bytes (threat T-02-01-04).
- `Tools/spikes/keychain-access-group-spike/spike.entitlements` — declares `keychain-access-groups`
  = `[Y4A54395NZ.group.com.donovansantine.cortex.shared]` + the App Group. (Literal team prefix
  because raw `codesign --entitlements` does NOT expand the Xcode build variable `$(AppIdentifierPrefix)`;
  under an Xcode build the equivalent is `<string>$(AppIdentifierPrefix)group.com.donovansantine.cortex.shared</string>`.)

**Build + sign recipe used:**
```
xcrun --sdk macosx swiftc Tools/spikes/keychain-access-group-spike/main.swift -o /tmp/cortex-kc-spike
codesign --force --sign 10382498625EDD5F29A1518B95A522B39AD047F3 \
  --entitlements Tools/spikes/keychain-access-group-spike/spike.entitlements \
  --identifier com.donovansantine.cortex.kcspike /tmp/cortex-kc-spike
```
- Compile: OK (arm64 Mach-O).
- Codesign: OK — embedded entitlements verified via `codesign -d --entitlements -`:
  both `keychain-access-groups` (Y4A54395NZ. prefix) and `com.apple.security.application-groups`
  present.

### Observed results (REAL)

| Run | Signing | Result | Interpretation |
|-----|---------|--------|----------------|
| **Entitled** | Apple Development (Y4A54395NZ) + `spike.entitlements` embedded | **SIGKILL at exec — exit 137 (128+9), no stdout** | AMFI refuses to LAUNCH a binary bearing a team-prefixed `keychain-access-groups` entitlement with **no provisioning profile to back it**. A bare `tool` (no bundle/profile) under a free/personal team cannot carry that entitlement. |
| Control A (ad-hoc `--sign -`, no entitlements) | ad-hoc, no entitlements | Runs; `SecItemDelete` = **-34018**, `SecItemAdd` = **-34018** | `errSecMissingEntitlement` — the access group `Y4A54395NZ.group…` is not authorized for this process. |
| Control B (real identity, no entitlements) | Apple Development (Y4A54395NZ), no entitlements | Runs; `SecItemDelete` = **-34018**, `SecItemAdd` = **-34018** | `errSecMissingEntitlement` — same. Proves the kill in the Entitled run is caused by the *entitlement* (AMFI), and that absent the entitlement the access group is rejected anyway. |

**Exact OSStatus observed:** `SecItemAdd` / `SecItemDelete` = **`errSecMissingEntitlement (-34018)`**
(in both control runs); the entitled binary never reached the `SecItem*` calls because AMFI
**SIGKILLed it at exec (exit 137)**.

### Verdict: **CF#1 = FAIL** → fall back (errSecMissingEntitlement / AMFI-kill, signing-blocked under a free team)

Cross-process Keychain access-group sharing does **NOT** work under the available free/personal team
(Y4A54395NZ) without a provisioning profile. Both failure modes are conclusive:
(1) the team-prefixed `keychain-access-groups` entitlement is **un-backable** by a bare tool under a
free team → AMFI SIGKILL; (2) without that entitlement the access group yields
`errSecMissingEntitlement (-34018)`. This is the exact, plan-anticipated outcome from
02-RESEARCH.md Critical Finding #1 — **NOT a blocker**, it is the risk this spike exists to resolve.

### Directive for Plan 02-03 (binding)

Plan 02-03 **MUST take the CF#1 fallback** (do NOT implement D-14/D-15 cross-process access-group
sharing in Phase 2):

1. **Prove SC#3 as a SINGLE-process Keychain round-trip.** One process writes the random 256-bit
   session secret to the **data-protection keychain** with
   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` + `kSecUseDataProtectionKeychain=kCFBooleanTrue`
   (CF#8) and reads it back — **using the application's DEFAULT access group** (i.e. do NOT set a
   team-prefixed `kSecAttrAccessGroup`; an app's default access group needs no provisioning profile).
   This literally satisfies SC#3's "the key round-tripping Keychain" and IPC-06's accessibility class.
2. **Deliver the key to the peer over the secure `mach_msg` channel** established in Plan 02-02
   (the same channel that passes the shm fd), NOT via a shared Keychain access group. HKDF-Expand
   into the per-direction subkeys (D-15) happens in each process after the secret is delivered.
3. **Defer cross-process access-group SHARING to Phase 8** (enrollment), reconciled with the
   paid-team prefix at that time. Flag this as a **D-14/D-15 reconciliation** in the Plan 02-03
   summary (the "share via shared Keychain access group" half of D-15 is deferred; the
   "secret stored in Keychain + HKDF per-direction subkeys" half is honored in Phase 2).
4. **KeychainTests** (02-RESEARCH.md test map) run the single-process round-trip; the cross-process
   access-group test is `@disabled`/deferred with a comment citing this CF#1 verdict.

Security note carried forward: the spike printed OSStatus + a byte-match boolean only — never key
material (threat T-02-01-04). Plan 02-03's KeychainTests must follow the same discipline.

---

## CF#3 Rendezvous spike

**Goal:** Prove a parent process can hand a Mach SEND right to a `posix_spawn`'d child and the child
can message the parent back — WITHOUT a launchd plist and WITHOUT the deprecated `bootstrap_register`
(which returns `BOOTSTRAP_NOT_PRIVILEGED (1100)` for ad-hoc names on modern macOS, per
02-RESEARCH.md Critical Finding #3). This picks the rendezvous mechanism Plan 02-04's harness uses
and reconciles it with locked decision D-08.

**Spike artifact:** `Tools/spikes/rendezvous-spike/main.c` (pure C, no signing needed). Attempts the
**non-deprecated** path FIRST per CF#3:
- Parent: `mach_port_allocate(MACH_PORT_RIGHT_RECEIVE)` → `mach_port_insert_right(MACH_MSG_TYPE_MAKE_SEND)`
  → `posix_spawnattr_setspecialport_np(&attr, sendRight, TASK_BOOTSTRAP_PORT)` → `posix_spawn` (self, arg `child`)
  → `mach_msg(MACH_RCV_MSG | MACH_RCV_TIMEOUT, 10s)`.
- Child: `task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &p)` → `mach_msg(MACH_SEND_MSG)`
  one word (`0xC0FFEE`) to `p`.

**Build + run recipe used:**
```
xcrun clang Tools/spikes/rendezvous-spike/main.c -o /tmp/cortex-rdv-spike
/tmp/cortex-rdv-spike          # parent posix_spawns itself with `child`
```
- Compile: OK (no warnings).

### Observed results (REAL)

```
parent: spawned child pid=70042; waiting for rendezvous word...
child: sent word 0xC0FFEE over TASK_BOOTSTRAP_PORT rendezvous
PASS: parent received word 0xC0FFEE from posix_spawn'd child over TASK_BOOTSTRAP_PORT
```
- Parent received the exact word `0xC0FFEE`; exit 0. **Deterministic across 3 consecutive runs** (3/3 PASS).

### Verdict: **CF#3 = PASS** via `posix_spawnattr_setspecialport_np`

The non-deprecated special-port injection works end-to-end on macOS 26.5 / Xcode 26.3 / M4 with **no
launchd plist** and **no `bootstrap_register`**. The mechanism proven is
`posix_spawnattr_setspecialport_np` (parent side) + `task_get_special_port` (child side), using
**special-port index `TASK_BOOTSTRAP_PORT` (= 4)** as the rendezvous channel.

### D-08 reconciliation: **ADOPT-WITH-RATIONALE**

D-08 literally names "parent publishes a receive right under a bootstrap service name; child
`bootstrap_look_up`s it." We **adopt `posix_spawnattr_setspecialport_np` instead**, because:
- D-08's named API (`bootstrap_register`) is `__OSX_AVAILABLE_BUT_DEPRECATED(10.4→10.5)` and returns
  `BOOTSTRAP_NOT_PRIVILEGED (1100)` for ad-hoc names on modern macOS; the non-deprecated
  `bootstrap_check_in` requires a launchd plist, which D-08 explicitly avoids ("No launchd plist
  needed for the proof").
- `posix_spawnattr_setspecialport_np` achieves **D-08's INTENT** exactly — "the parent hands the
  child the rendezvous right with no plist" — via a non-deprecated, verified-working path.
- This is a mechanism substitution that preserves the locked decision's goal; flagged here for the
  checker/user as an intentional, spike-validated deviation (not a silent change).

### Directive for Plan 02-04 (binding)

1. The harness driver injects the parent's rendezvous **SEND right** into the `posix_spawn`'d consumer
   via `posix_spawnattr_setspecialport_np(&attr, sendRight, TASK_BOOTSTRAP_PORT)`; the consumer reads
   it via `task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, …)`. **No `bootstrap_register`,
   no launchd plist** for the Phase-2 proof harness.
2. **Special-port index Plan 02-04 uses: `TASK_BOOTSTRAP_PORT` (= 4).** Do NOT clobber the other
   task special ports (1,2,3,5,6,9,10,11 = kernel/host/name/inspect/read/access/debug/resource).
3. **Caveat (carry into Plan 02-04):** injecting `TASK_BOOTSTRAP_PORT` means the child loses its real
   launchd bootstrap port. This is SAFE for the **Foundation-free `CortexIPCTransport` consumer**
   (D-04) which needs no CFRunLoop/launchd services. If Plan 02-04 instead chooses a
   Foundation/CoreFoundation consumer or an XCTest host that needs real bootstrap, fall back to the
   `bootstrap_register`/`bootstrap_look_up` path (accept the deprecation warning) and record the
   `BOOTSTRAP_*` return code — i.e. that fallback would be HONOR-WITH-SPIKE. The recommended path
   (and the one validated here) is the Foundation-free consumer + special-port injection.
4. Once the rendezvous right is in hand, the consumer proceeds to the Q1 `mach_msg` +
   `MACH_MSG_PORT_DESCRIPTOR` + `fileport_makeport` dance to receive the shm fd (Plan 02-02 / IPC-03).

Threat note (T-02-01-03): the special-port path injects the right directly at spawn — there is **no
global bootstrap name for a third process to squat**, which is strictly safer than the bootstrap
fallback's named-registration surface.
