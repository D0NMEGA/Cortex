# Capture-only signing override

## What this file is

`CortexMac.capture.entitlements` is the committed `Apps/CortexMac/Cortex.entitlements` with exactly
one key removed: `com.apple.developer.hid.virtual.device`. Nothing else differs. It exists so the
CortexMac GUI can be built and launched on this machine for a screen capture.

## Why it is needed

`com.apple.developer.hid.virtual.device` is an Apple-managed capability. A free Personal team cannot
provision it, so signing fails before the app ever launches:

```
Personal development teams ... do not support the HID Virtual Device capability
```

The only local signing identity is the free Personal team `57YW6M29S7`, so without this override
there is no way to run the app here at all.

## How it is used

Pass it on the `xcodebuild` command line. It is never referenced by `project.yml` and never becomes
the default for any target:

```bash
xcodebuild -project Cortex.xcodeproj -scheme CortexMac -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_ENTITLEMENTS=Tools/capture/CortexMac.capture.entitlements \
  -allowProvisioningUpdates build
```

To run from the Xcode GUI instead, set the same `CODE_SIGN_ENTITLEMENTS` value in the build settings
for that run, or Xcode hits the identical provisioning error.

## This is not the shipping configuration

`Apps/CortexMac/Cortex.entitlements`, `Apps/CortexiOS/Cortex.entitlements` and
`Apps/CortexDaemon/Cortex.entitlements` are deliberately NOT modified, and neither is `project.yml`.
Two reasons:

1. `Tools/scripts/hid-surface-policy.sh:168-170` requires the HID key in all three committed
   entitlements files. Removing it there would fail the gate, which is the gate working correctly.
2. XcodeGen regenerates the project from `project.yml`, so a hand edit to a generated file would be
   silently reverted on the next `xcodegen generate`.

## What omitting the key does not change

Nothing that runs. The live HID path is `#if CORTEX_HID_LIVE`-gated, and the entitlement is inert
under free-team signing regardless: an entitled binary signed by a free team is AMFI-SIGKILLed. A
recording made with this override therefore shows the same runtime behaviour the shipping
configuration would show on this hardware.

That disclosure belongs in any evidence artifact that cites a capture made this way. See the
`What the capture build is not` section of
`.planning/phases/10-v1-real-data-closed-loop-launch/10-demo-capture-evidence.md`.
