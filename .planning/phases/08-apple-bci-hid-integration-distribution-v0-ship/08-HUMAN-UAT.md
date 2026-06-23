---
status: partial
phase: 08-apple-bci-hid-integration-distribution-v0-ship
source: [08-VALIDATION.md "Manual-Only Verifications", 08-RESEARCH.md §Validation Architecture, 08-CONTEXT.md D-01/D-06/D-08]
gates: 3
started: 2026-06-23T00:00:00Z
updated: 2026-06-23T06:00:00Z
---

> ## ⚠️ CRITICAL — ALL THREE GATES ARE NEVER AUTO-APPROVED (D-01 / D-06 / D-08, T-08-07-01)
>
> **These three gates are load-bearing project credibility. PRESENT each checkpoint to the user; do
> NOT auto-approve any of them** — even when `auto_advance=true`. Auto-approving fabricates the
> project's defining claims: a TestFlight submission that never happened (DIST-01/02/03), an iPad-M4
> glass-to-glass latency number that was never measured (PERF-04), or an on-device HID registration
> that never occurred (SYS-01/02). Honesty is the product; the audience is Bliss Chapman /
> Nir Even-Chen. (The `.agent` MEMORY rules "Device checkpoints: never auto-approve",
> "gsd-device-checkpoints-never-auto-approve", and "gsd-validation-md-stale-seed" all apply — a
> fabricated gate forges a load-bearing credibility claim. This is the explicit T-08-07-01 threat.)
>
> **v0 is FULLY RUNNABLE + CREDIBLE TODAY on the free Personal team (Plans 01-06).** The complete,
> structurally-verified pipeline is built and CI-green: the BCI HID surface + declared-and-gated
> entitlement (01), the closed-loop round trip (02), the synthetic-spike → NDT1 → ReFIT → 120Hz
> webgrid demo + the software-timed glass-to-glass bench (03), the `notarytool`+`match`+TestFlight
> lanes & scripts (04), the Webgrid BPS metric (05), and the credibility README (06). Each gate below
> only flips its requirement's **live half** from **ready → done**; none of them blocks v0. The
> always-available corroborating tier (M5 Pro software-timed glass-to-glass p99 ≈ 8.3 ms; the
> structural CI gates `hid-surface-policy.sh` / `notarize-policy.sh` / `match-policy.sh`) stands on
> its own and is never substituted for the gated canonical number.
>
> **Disposition rule (per gate):** each gate is either **DEFERRED** (its prerequisite is not
> available — record the paused state, do NOT mark its live half done, do NOT run a live lane or
> fabricate a number) **OR** **VERIFIED** (you executed the documented flip procedure on real
> hardware/enrollment and captured the real evidence into the evidence slot). There is no third
> option. NONE is auto-approved.

## Current Test

**All 3 gates DEFERRED — human disposition 2026-06-23** (prerequisites not available this session: no paid
Apple Developer Program enrollment + ASC `.p8` for Gate 1, no provisioned iPad Pro M4 for Gate 2, no managed
`hid.virtual.device` entitlement + Accessibility grant for Gate 3). Paused state recorded; none auto-approved;
no live lane run, no canonical number or HID registration fabricated. v0 ships fully runnable today on the
free Personal team — each gate flips ready → done by its procedure below the day its prerequisite lands.

All three gates drive an **already-built artifact** committed in Plans 01-06 — each is the live/paid/device
complement of a structurally-verified, CI-green piece, tied to the same code so the runbook cannot drift.
The day the prerequisite lands, the gate flips ready → done by the documented procedure below with **no
further code change**.

---

## Gate 1 — Live TestFlight submission (DIST-01 / DIST-02 / DIST-03)

**Status:** READY, GATED. The full distribution pipeline is real code and CI-green (Plan 04): the
`fastlane beta` lanes (mac + ios) wire `app_store_connect_api_key` + `match(type: "appstore", readonly:
is_ci)` + `build_app` + `Tools/scripts/notarize.sh` (`xcrun notarytool submit` → `xcrun stapler staple`/
`validate` → `spctl --assess`, **zero** deprecated-uploader refs) + `upload_to_testflight` (100 internal /
10,000 external testers, 90-day build expiry documented). The `notarize-policy.sh` + `match-policy.sh`
structural gates bite on every regression. **Blocking prerequisite:** a paid **Apple Developer Program
enrollment** + the **App Store Connect `.p8` API key** + the populated private `cortex-fastlane-certs`
repo + the `MATCH_PASSWORD` passphrase. The lanes/script fail LOUDLY (`UI.user_error!` / `exit 1`) when the
`ASC_*`/`MATCH_PASSWORD` ENV vars are unset, so a clean clone / CI run cannot half-submit (T-08-04-05).

**⛔ NEVER AUTO-APPROVE.** Recording a `notarytool` submission / a TestFlight build that never happened
forges DIST-01/02/03 (T-08-07-01). Do NOT run the live lane unless enrollment + the `.p8` are genuinely in
hand, and do NOT mark DIST-03's live half done without the captured evidence below.

### Flip procedure (ready → done)

Prerequisite: Apple Developer Program enrollment is active; the ASC `.p8` key has been downloaded; the
private `cortex-fastlane-certs` repo is populated (`fastlane match init` / first `match` run minted the
appstore certs).

1. Export the live-submission creds (ENV only — never commit them; `fastlane/asc_api_key.json` + `*.p8`
   are gitignored, T-08-07-03):
   ```bash
   export ASC_KEY_ID=…            # the 10+ alphanumeric Key ID
   export ASC_ISSUER_ID=…         # the Issuer UUID
   export ASC_KEY_PATH=/path/AuthKey_<KEYID>.p8
   export MATCH_PASSWORD=…        # the match repo passphrase
   export ASC_TEAM_ID=…           # paid team id (Appfile identity)
   export ASC_APPLE_ID=…          # Apple ID (Appfile identity)
   export ASC_ITC_TEAM_ID=…       # App Store Connect team id (Appfile identity)
   ```
2. Run the real lane (this is the line that flips DIST from gated to live — no code change):
   ```bash
   bundle exec fastlane beta            # platform :mac (CortexMac.app) — or `fastlane ios beta` for CortexiOS
   ```
   The lane runs `match(appstore)` → `build_app(scheme: "CortexMac")` → `notarize.sh` (`notarytool submit
   --wait` then `stapler staple`) → `upload_to_testflight`.
3. Confirm, in order:
   - `xcrun notarytool submit … --wait` prints **status: Accepted** (capture the **submission id**).
   - `xcrun stapler validate Cortex.app` prints **The validation succeeded** and `spctl --assess -vv
     --type exec` is accepted by Gatekeeper.
   - the build appears in **App Store Connect → TestFlight** and is **visible to an internal tester**.

**Expected outcome:** `notarytool` returns **Accepted**, the ticket staples + validates + passes
Gatekeeper, and the TestFlight build is processed and available to an internal tester — DIST-01 (notarize),
DIST-02 (match appstore signing), DIST-03 (TestFlight distribution) live half **done**.

### Evidence slot (capture into this section if VERIFIED — do NOT capture the `.p8`/passphrase, T-08-07-03)

- notarytool **submission id** + the `notarytool log` JSON excerpt (status `Accepted`): `__________`
- `stapler validate` + `spctl --assess` output: `__________`
- **TestFlight build screenshot** (App Store Connect → TestFlight, build visible to an internal tester),
  committed into this phase dir (e.g. `testflight-build.png`): `__________`
- (do NOT paste `ASC_KEY_*` / `MATCH_PASSWORD` / the `.p8` — only the submission id + the screenshot)

**why_human:** A live `notarytool submit` + `fastlane match` + TestFlight upload requires a **paid Apple
Developer Program enrollment** + a real ASC `.p8` key + the private certs repo — none of which a CI runner
or the free Personal team can hold. This is the wire-and-gate keystone (D-01): the pipeline is real and
structurally CI-gated now; only the live network call to Apple is the human gate. Never auto-approve (the
always-on proxy is the Plan-04 `notarize-policy.sh` + `match-policy.sh` structural tier).

**Disposition:** **DEFERRED** (human disposition 2026-06-23) — prerequisite not available this session (see
**Status** above for this gate's specific blocker: paid enrollment + ASC `.p8` / a provisioned iPad Pro M4 /
the managed `hid.virtual.device` entitlement + Accessibility grant). Paused state recorded; the requirement's
**live half stays not-done**; no live lane run, no number/registration fabricated. Flip via this gate's
procedure above when its prerequisite lands. _Not auto-approved._

---

## Gate 2 — iPad Pro M4 canonical software-timed glass-to-glass latency capture (PERF-04, D-08)

**Status:** READY, GATED — **M5 Pro is the corroborating-canonical number that stands today.** The
software-timed glass-to-glass measurement is real code and CI-green (Plan 03): `GlassToGlassTimer.sample(…)`
ends the measurement at the CAMetalDisplayLink **`update.targetPresentationTimestamp`** (the on-glass
present time — NOT `targetTimestamp`, the render deadline), carrying the verbatim
`GlassToGlassTimer.methodologyLabel`. The headless `CortexDemoBench` drives the real `ClosedLoopPipeline`
for n ≥ 10,000 ticks and asserts **p99 < 25 ms** — measured on **M5 Pro corroborating: p50 ≈ 4.23 ms,
p99 ≈ 8.32 ms** (`Packages/CortexDemo/.bench/glass_to_glass.json`, device annotation
`M5-Pro-software-timed-corroborating`). **Blocking prerequisite:** a **provisioned iPad Pro M4** (the free
Personal team cannot provision an iPad headless; the M5 Pro number is the corroborating proxy that
completes PERF-04's available tier — D-08).

**⛔ NEVER AUTO-APPROVE.** This is a load-bearing canonical credibility number. Do NOT fabricate an iPad-M4
number or assume it from the M5 Pro run — if the iPad-M4 capture is taken, record it as **observed** on the
device (T-08-07-01/02). The M5-Pro corroborating number is never substituted for the canonical iPad-M4 one.

### Flip procedure (ready → done)

Prerequisite: a provisioned iPad Pro M4 (iPadOS 26) is paired + trusted in Xcode 26.3 (Window → Devices and
Simulators).

1. In **Xcode 26.3**, build to the **connected iPad Pro M4** via the GUI (the free team signs GUI-only — see
   the project memory "Build Cortex with real Xcode 26.3"; select the iPad as the run destination on the
   `CortexiOS` scheme).
2. Capture the software-timed glass-to-glass number on-device — the SAME `GlassToGlassTimer` the bench uses,
   driven by the REAL `update.targetPresentationTimestamp` from the live `CAMetalDisplayLink`:
   - **(a) in-app capture (canonical):** run the `CortexiOS` `ClosedLoopPipeline` GUI on the iPad; the live
     display-link path feeds `update.targetPresentationTimestamp` into `GlassToGlassTimer.sample(…)`; record
     the p50/p99 histogram over n ≥ 10,000 ticks with `deviceAnnotation = "iPad-Pro-M4-software-timed-canonical"`.
   - **(b) headless corroboration:** `swift run --package-path Packages/CortexDemo CortexDemoBench --full`
     for the device-independent software-pipeline budget (already green on M5 Pro; the on-device present
     timestamp in (a) is the canonical surface).
3. Confirm **p99 < 25 ms** and that the printed/JSON output carries the verbatim methodology label
   (`software-timed pipeline latency — excludes the compositor's 1-3 frames of scanout, which is exactly the
   delta the v1 photodiode rig (Phases 9-10) quantifies`).

**Expected outcome:** on iPad Pro M4, software-timed glass-to-glass **p99 < 25 ms** against the real
`targetPresentationTimestamp`, annotated `iPad-Pro-M4-software-timed-canonical`, with the verbatim
methodology label travelling with the number — PERF-04 canonical (software-timed) half **done**. (The final
glass-to-glass figure remains the v1 **photodiode** claim of Phases 9-10; this is the software tier that
sets it up — no compositor-offset fudge, D-07.)

### Evidence slot (capture into this section if VERIFIED)

- the p50/p99 software-timed **histogram** (or `glass_to_glass_ipad.json`), annotated **iPad Pro M4 /
  iPadOS 26**, committed into this phase dir: `__________`
- the verbatim methodology label present in the captured output: `__________`
- (optional) a device-annotated screenshot of the in-app latency readout: `__________`

**why_human:** The on-device capture against the real `CAMetalDisplayLink` present timestamp needs **real
iPad Pro M4 hardware** + GUI provisioning — it cannot run on a headless CI runner (no display link, no GPU,
no paired device). This follows the D-08 / D-18 "measure on the available device (M5 Pro corroborating),
gate the canonical claim on the target device (iPad M4)" precedent already applied in Phase 3 SC#1
(`03-HUMAN-UAT.md`), Phase 5 SC#1/DEC-08 (`05-HUMAN-UAT.md`), and Phase 6 SC#2/SC#4 (`06-HUMAN-UAT.md`).
Never auto-approve.

**Disposition:** **DEFERRED** (human disposition 2026-06-23) — prerequisite not available this session (see
**Status** above for this gate's specific blocker: paid enrollment + ASC `.p8` / a provisioned iPad Pro M4 /
the managed `hid.virtual.device` entitlement + Accessibility grant). Paused state recorded; the requirement's
**live half stays not-done**; no live lane run, no number/registration fabricated. Flip via this gate's
procedure above when its prerequisite lands. _Not auto-approved._

---

## Gate 3 — On-device HID registration as a Switch Control HID provider (SYS-01 / SYS-02, D-06)

**Status:** READY, GATED — entitlement **declared-but-inert**, the structural CI gate stands today. The BCI
HID surface is real code and CI-green (Plan 01): the 5 ported Apple report structs + the verbatim
`BCIHIDDescriptor.bytes` report descriptor, the `com.apple.developer.hid.virtual.device` +
`keychain-access-groups` entitlements declared-but-inert across all 3 targets, and the live
`IOHIDUserDevice`/`HIDVirtualDevice` instantiation isolated behind `VirtualDeviceGate`'s **`#if
CORTEX_HID_LIVE`** compile gate (the default free-team build links **no** live HID symbol — AMFI-safe). The
`hid-surface-policy.sh` gate proves the live symbol stays scoped to the gated file. **Blocking
prerequisite:** the **`com.apple.developer.hid.virtual.device` entitlement activation** on a **managed
provisioning profile** (= paid enrollment) + the system **Accessibility-permission grant** + a provisioned
device session. (The live IOKit `IOHIDUserDevice` symbols additionally need the Plan-07 C-interop bridging
module, or migration to CoreHID `HIDVirtualDevice` — the default build links none of it.)

**⛔ NEVER AUTO-APPROVE.** Recording an on-device Switch Control HID registration that never occurred forges
SYS-01/02 (T-08-07-01). Do NOT mark the live half done without the captured Switch Control provider listing
+ a cursor-moves recording. The structural CI gate (`hid-surface-policy.sh`) is the always-on proxy and
stands on its own.

### Flip procedure (ready → done)

Prerequisite: paid enrollment with a managed provisioning profile that can carry
`com.apple.developer.hid.virtual.device`; a provisioned device (Mac or iPad) session; the Plan-07 C-interop
bridge (or CoreHID `HIDVirtualDevice`) wired so the gated symbols resolve.

1. **Activate the entitlement:** enable `com.apple.developer.hid.virtual.device` on the managed provisioning
   profile (the declared-but-inert key in `Apps/Cortex{Mac,iOS,Daemon}/Cortex.entitlements` becomes live
   under the managed profile).
2. **Build with the live flag:** compile with **`-D CORTEX_HID_LIVE`** so `VirtualDeviceGate`'s live path is
   linked (default builds keep it OFF). Build via Xcode 26.3 GUI on the provisioned device.
3. **Grant Accessibility:** on first run, grant Cortex the system **Accessibility** permission when prompted
   (System Settings → Privacy & Security → Accessibility).
4. **Instantiate the virtual device:** call `VirtualDeviceGate.createVirtualDevice(descriptor:
   BCIHIDDescriptor.bytes)` (`IOHIDUserDeviceCreate` with the ported descriptor) and send a Pointer (RID-3)
   report via `VirtualDeviceGate.sendPointer(_:)` (`IOHIDUserDeviceHandleReportWithTimeStamp`, timestamped
   `mach_absolute_time()` — the same clock as PERF-04).
5. **Confirm registration:** Cortex appears as a **BCI HID provider** under **Switch Control /
   AssistiveTouch**, and a sent Pointer report **moves the cursor** under Switch Control.

**Expected outcome:** the virtual device instantiates from the ported descriptor, Cortex is listed as a
Switch Control / AssistiveTouch HID provider, and a BCI Pointer report drives the system cursor — SYS-01/02
live half **done**.

### Evidence slot (capture into this section if VERIFIED)

- a screenshot of the **Switch Control / AssistiveTouch provider listing** showing Cortex registered as a
  BCI HID provider, committed into this phase dir (e.g. `switch-control-provider.png`): `__________`
- a **screen recording** of the cursor moving under Switch Control driven by a Cortex Pointer report (e.g.
  `hid-cursor-moves.mov`): `__________`
- the device + OS the registration ran on (e.g. iPad Pro M4 / iPadOS 26, or Mac / macOS 26): `__________`

**why_human:** Creating a virtual HID device requires the `com.apple.developer.hid.virtual.device`
entitlement on a **managed provisioning profile** (paid enrollment) + a system Accessibility grant + a
provisioned device session — none of which a CI runner or the free Personal team can hold (the entitled
binary is AMFI-SIGKILLed without the managed profile; the structural gate is the always-on proxy). This is
the D-06 wire-and-gate disposition. Never auto-approve.

**Disposition:** **DEFERRED** (human disposition 2026-06-23) — prerequisite not available this session (see
**Status** above for this gate's specific blocker: paid enrollment + ASC `.p8` / a provisioned iPad Pro M4 /
the managed `hid.virtual.device` entitlement + Accessibility grant). Paused state recorded; the requirement's
**live half stays not-done**; no live lane run, no number/registration fabricated. Flip via this gate's
procedure above when its prerequisite lands. _Not auto-approved._

---

## Summary

total: 3
verified: 0
deferred: 3
pending: 0
auto_approved: 0

**Status:** All three gates **DEFERRED** by human disposition (2026-06-23) — prerequisites not available; none auto-approved (the documented v0 wire-and-gate terminal state). Each remains **READY, GATED**.
Each drives an already-built, CI-green artifact (Plans 01-06) and flips its requirement's **live half**
ready → done by the documented procedure the day its prerequisite (paid enrollment + ASC `.p8` / a
provisioned iPad Pro M4 / the managed `hid.virtual.device` entitlement + Accessibility grant) lands. **v0 is
fully runnable + credible TODAY on the free Personal team** — the corroborating tier (M5 Pro software-timed
glass-to-glass p99 ≈ 8.3 ms; the structural CI gates) stands on its own and is never substituted for a
gated canonical number. Fabricating any gate forges a load-bearing credibility claim (T-08-07-01) — the
project's instrumentation-honesty thesis (Bliss Chapman / Nir Even-Chen the audience).

## Gaps

- The three live halves (live TestFlight submission, the iPad-Pro-M4 canonical software-timed latency
  capture, and the on-device Switch Control HID registration) are account/hardware-gated and deferred to
  this never-auto-approve checkpoint. They are **NOT coverage gaps** — each is the live/paid/device
  complement of a structurally-verified, CI-green piece (per 08-VALIDATION.md "Manual-Only Verifications"
  and 08-RESEARCH §Validation Architecture).
- When a prerequisite lands, run that gate's flip procedure above, capture the real evidence into its
  evidence slot, commit the artifacts into this phase dir, and present the checkpoint to the user for
  sign-off — **never auto-approve.**
