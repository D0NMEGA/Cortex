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
