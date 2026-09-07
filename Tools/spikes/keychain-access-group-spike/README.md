# CF#1 Keychain access-group spike

Phase 2, Plan 02-01, Task 2. Determines whether a bare Mach-O `tool` can share a session secret
across processes via a team-prefixed `keychain-access-groups` access group on the data-protection
keychain. See `.planning/phases/02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm/02-SPIKES.md`
for the recorded verdict (CF#1 = FAIL → fallback).

## Run

```sh
xcrun --sdk macosx swiftc main.swift -o /tmp/cortex-kc-spike
codesign --force --sign <IDENTITY-SHA1> \
  --entitlements spike.entitlements \
  --identifier com.donovansantine.cortex.kcspike /tmp/cortex-kc-spike
/tmp/cortex-kc-spike write    # process A — SecItemDelete + SecItemAdd
/tmp/cortex-kc-spike read     # process B — SecItemCopyMatching + 32-byte match
```

## Notes

- **CF#8:** `kSecUseDataProtectionKeychain` must be `kCFBooleanTrue`, NOT Swift `true` (Swift `true`
  bridges to a value that yields `errSecParam -50`).
- **Team prefix:** `spike.entitlements` uses the LITERAL prefix `Y4A54395NZ.` because raw
  `codesign --entitlements` does NOT expand the Xcode build variable `$(AppIdentifierPrefix)` (that
  substitution only happens during an Xcode build). Under an Xcode build the equivalent declaration is
  the access group string prefixed with `$(AppIdentifierPrefix)`. The signing identity is
  `Apple Development: <apple-id redacted> (Y4A54395NZ)`, so the runtime `kSecAttrAccessGroup` in
  `main.swift` uses the same `Y4A54395NZ.` prefix.
- **Free team caveat:** `Y4A54395NZ` is very likely a FREE/personal Apple team. Free teams generally
  cannot authorize the App Groups / keychain-access-groups capabilities, so a binary bearing the
  entitlement is SIGKILLed at exec by AMFI (no provisioning profile to back it), and absent the
  entitlement `SecItemAdd` returns `errSecMissingEntitlement (-34018)`. Both are LEGITIMATE
  CF#1 = FAIL verdicts — exactly the risk this spike exists to resolve.
- **Security:** the spike prints OSStatus codes + a byte-MATCH boolean only — never the secret bytes
  (threat T-02-01-04). The 32-byte payload is a fixed non-secret test pattern (0x00..0x1F).
- Throwaway probe under `Tools/spikes/` — never shipped, never on the App Store path, not policed by
  `hotpath-policy.sh`.
