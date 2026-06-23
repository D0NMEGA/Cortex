# Phase 8: Apple BCI HID Integration, Distribution & v0 Ship — Research

**Researched:** 2026-06-23 (main-thread browser-harness + Context7 + Apple docs JSON API + local Xcode 26.3 toolchain)
**Method:** Per project policy, this is the **main-thread browser pass** (the GSD subagent researcher is HTTP-only; browser-harness errors out in a subagent). No `## Main-thread-gated research` items remain — all browser-gated lookups were completed here.
**Answers:** "What do I need to know to PLAN Phase 8 well?"
**Confidence grading:** A = primary source (Apple docs / installed toolchain / fastlane docs). B = reputable secondary. C = inference.

---

## 0. Executive summary — three research-driven refinements to the locked decisions

The `08-CONTEXT.md` decisions are sound, but primary-source research **sharpens three of them** (intent preserved, specifics corrected — the planner should build to the corrected specifics):

1. **SYS-01/05 (D-04): the mirror-able public surface is Apple's own BCI HID *report descriptor*, not a "Synchron-published entitlement list."** Apple publishes the full protocol at `developer.apple.com/documentation/accessibility/brain-computer-interface-hid-reference-for-connecting-to-apple-platforms` — public C structs, a HID report descriptor, and the `IOHIDUserDevice`/CoreHID `HIDVirtualDevice` API. Synchron's press releases carry **no entitlement strings**. So "mirror the public surface" = **port the Apple BCI HID report structs + descriptor into Swift** (buildable now, free team), and **declare-and-gate the `com.apple.developer.hid.virtual.device` entitlement** (the managed/gated part). This is *more* concrete and *more* honest than the CONTEXT phrasing. [A]

2. **SYS-03/04 (D-05): the closed-loop "bidirectional context" channel is literally the BCI HID *Scan Info output report* (Report ID 4, host→device).** It carries `selectedItem`, `numberOfItems`, `seed` (scan-cycle id), `itemControlType`, and a two-byte `uiScanningLatency` (int+frac). The in-app host harness should model the round trip as: host emits Scan-Info output → Cortex returns an Item-Selection input report (Report ID 4) / Pointer report (Report ID 3). The protocol *names* the round trip for us. [A]

3. **PERF-04 (D-07): use `CAMetalDisplayLink.Update.targetPresentationTimestamp`, NOT `targetTimestamp`.** The spec §3 line listing `targetTimestamp` is imprecise: `targetTimestamp` is the *render deadline*; `targetPresentationTimestamp` is "the time the system estimates until display of the next frame" — i.e. the on-glass present time the software-timed glass-to-glass claim must end at. [A]

Everything else (the wire-and-gate doctrine, decoder-genuinely-in-loop, BPS-not-Fitts, M5-corroborating/iPad-canonical, free-team-signs-GUI) is confirmed by research.

---

## 1. Apple BCI HID protocol — SYS-01, SYS-02, SYS-05  [A]

**Primary source:** `https://developer.apple.com/documentation/accessibility/brain-computer-interface-hid-reference-for-connecting-to-apple-platforms` (Apple Developer → Accessibility → Specifications → Human Interface Device (HID); sibling: "Braille HID reference" — same descriptor-family pattern).

It is a **HID report descriptor reference for BCI hardware firmware**, consumed by the host's **Switch Control / AssistiveTouch**. BCI is a first-class input category (announced May 2025; Synchron Stentrode is the first device — businesswire 2025-08-04). The device is created on the host via a **virtual HID device** (`IOHIDUserDevice` C API, or the modern Swift **CoreHID `HIDVirtualDevice`**).

### 1.1 The public report structures (port these verbatim into Swift) [A]
```c
// Usage Page 0x60 = "Brain Control Interface"; Usage 0x01 = BCI Application
typedef struct { UInt8 reportId; UInt8 signalQuality[2]; } BCIInputSignalReport;   // RID 1: [0]=buttonID, [1]=neural strength 0-255 (Usage 0x02)
typedef struct { UInt8 reportId; UInt8 buttons[4];       } BCIInputButtonReport;   // RID 2: 32 buttons (HID Button Usage Page)
typedef struct { UInt8 reportId; SInt8 position[3];      } BCIInputPointerReport;  // RID 3: x,y,z deltas -127..127 (Generic Desktop) — the cursor report
typedef struct { UInt8 reportId; UInt8 itemIndex;        } BCIInputItemSelection;  // RID 4 (input): focus item 0..255 (BCI Usage 0x04)
typedef struct { UInt8 reportId; UInt8 selectedItem; UInt8 numberOfItems; UInt8 seed;
                 UInt8 itemControlType; UInt8 uiScanningLatencyInt; UInt8 uiScanningLatencyFrac;
               } BCIOutputScanInfoReport;                                          // RID 4 (output): host→device scan feedback (THE closed-loop channel)
```
Descriptor header (first bytes, for the structural CI gate): `0x05, 0x60` (Usage Page = Brain Control Interface), `0x09, 0x01` (Usage = BCI Application), `0xA1, 0x01` (Collection Application), then `0x09, 0x02` / `0x85, 0x01` (Signal Quality / Report ID 1) …

### 1.2 The high-level button actions enum (RID 2 semantics) [A]
`Select, MoveToNextItem, MoveToPreviousItem, ToggleAssistiveTechnologyMenu, Activate, StartSequentialNavigation, StopSequentialNavigation, TriggerAutomation, ToggleAppSwitcher, Home, ToggleNotificationsView, Assistant, VolumeDown, VolumeUp, ToggleDictation, ToggleAccessibilityFeature, ToggleQuickSettingsView, Escape, ScrollUp, ScrollDown, ScrollLeft, ScrollRight`.

### 1.3 The API + the gate boundary [A]
- **Send input reports:** `IOHIDUserDeviceHandleReportWithTimeStamp(device, timestamp, report, size)` — **timestamp is `mach_absolute_time()`** (ties directly into PERF-04 instrumentation).
- **Receive output (scan-info) reports:** `IOHIDUserDeviceRegisterInputReportCallback(device, buffer, size, callback, context)`.
- **Entitlement (the gated key):** `com.apple.developer.hid.virtual.device` (Boolean) — `developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device`. Creating the virtual device requires it; a sandboxed app additionally triggers a **system Accessibility-permission prompt** (forum thread 737230). The entitlement needs a managed provisioning profile (paid enrollment) → this is exactly the **HUMAN-UAT gate** (D-04/D-06). Modern Swift path: CoreHID `HIDVirtualDevice` + `developer.apple.com/documentation/corehid/creatingvirtualdevices`.

**Wire-vs-gate split (concrete, for D-01/D-02/D-04/D-06):**
| Buildable NOW (free team, no enrollment) | Gated → HUMAN-UAT (entitlement + provisioned device) |
|---|---|
| Swift port of all 5 report structs + the descriptor byte array | Actual `IOHIDUserDevice`/`HIDVirtualDevice` instantiation |
| Report-encoding + scan-info-decoding logic (pure, unit-testable) | Live registration as a Switch Control HID provider |
| Declaring `com.apple.developer.hid.virtual.device` in entitlements (declared, inert under free signing) | Entitlement *activation* (needs managed profile) + Accessibility grant |
| Structural CI grep gate on descriptor tokens (`0x60`, report IDs, struct names) | On-device "cursor moves in Switch Control" demo |

> **Note on D-02 keychain-access-groups:** same gate idiom — declare the entitlement key, keep the Phase-2 single-process Keychain fallback (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) for the runnable demo; cross-process activation is the paid-signing gate (CF#1).

---

## 2. SMAppService daemon registration — supports SYS-02/SYS-06 (D-03)  [A]

`developer.apple.com/documentation/servicemanagement/smappservice` — class, **macOS 13.0+** (Mac Catalyst 16.0+). Members the planner needs:
- `SMAppService.daemon(plistName:)` → returns a service object for a launch daemon whose plist lives in the app bundle (`Contents/Library/LaunchDaemons/<name>.plist`); also `.agent(plistName:)`, `.loginItem(identifier:)`, `.mainApp`.
- `.register()` — "Registers the service so it can begin launching subject to user approval"; returns/raises per `SMAppService.Status` (`notRegistered`, `enabled`, `requiresApproval`, `notFound`).
- `.status`, `.unregister()`, `openSystemSettingsLoginItems()`.

D-03 is satisfied as: **keep the standalone `type:tool` CortexDaemon driving the demo**; write/script the `SMAppService.daemon(...).register()` path; the **signed privileged-helper install is the gate** (register() needs the helper signed + the LaunchDaemons plist bundled — paid signing). Build the register/status code + a script now; gate the actual install.

---

## 3. Distribution — DIST-01 (notarytool + stapler)  [A, authoritative from installed Xcode 26.3.0]

Verified against the **local toolchain**: `/Applications/Xcode-26.3.0.app/Contents/Developer/usr/bin/notarytool` (`xcrun notarytool submit --help`). `altool` is fully replaced. Canonical lane/CI invocation with the ASC API key (`.p8` JWT):

```bash
# Auth option A — inline ASC API key (CI-friendly; no Keychain dependency)
xcrun notarytool submit "Cortex.zip" \
  --key   "AuthKey_<KEYID>.p8" \   # -k  : filesystem path to the .p8 private key
  --key-id "<KEYID>" \             # -d  : 10+ alphanumeric Key ID
  --issuer "<ISSUER-UUID>" \       # -i  : Issuer UUID (required for Team keys; OMIT for Individual keys)
  --wait                           # block until Accepted/Invalid; pair with --timeout 30m
# Auth option B — stored profile: xcrun notarytool store-credentials "cortex-notary" --key ... --key-id ... --issuer ...
#                then: xcrun notarytool submit Cortex.zip --keychain-profile "cortex-notary" --wait
xcrun stapler staple "Cortex.app"          # staple the ticket to the .app/.pkg/.dmg
xcrun stapler validate "Cortex.app"        # verify
spctl --assess -vv --type exec "Cortex.app"  # Gatekeeper assessment
```
Other flags: `-f json|plist` (parseable output for CI), `--webhook`, `--s3-acceleration` (default on). **Gate:** the *live* submit needs paid enrollment + a real ASC key → wire the lane + a `notarize` script now, gate the run (D-01). Structural verification now = grep the Fastfile/scripts for `notarytool submit` + `stapler staple` and **zero** `altool` (mirrors `hotpath-policy.sh`).

---

## 4. Distribution — DIST-02 (fastlane match) + DIST-03 (TestFlight)  [A, fastlane docs via Context7 /fastlane/docs]

**ASC API key in fastlane** — two equivalent forms; prefer the JSON-file form in CI:
```ruby
# Form 1: action populates SharedValues::APP_STORE_CONNECT_API_KEY for all downstream actions (match/gym/pilot/deliver)
app_store_connect_api_key(key_id: "<KEYID>", issuer_id: "<ISSUER-UUID>", key_filepath: "AuthKey_<KEYID>.p8")
# Form 2 (recommended for CI): a JSON file consumed via api_key_path: by pilot/cert/sigh/deliver
pilot(api_key_path: "fastlane/asc_api_key.json")
```
**Match (appstore) — the P1→P8 swaps (per 01-04-SUMMARY.md / D-10):**
```ruby
# Matchfile
git_url("https://github.com/<you>/cortex-fastlane-certs.git")  # was file:///… ; PRIVATE repo + ENV["MATCH_PASSWORD"]
storage_mode("git"); type("appstore")                          # was "development"
app_identifier(["com.donovansantine.cortex.mac","com.donovansantine.cortex.ios"]); team_id("<TEAMID>")
# Fastfile (real lanes replacing the two placeholder lanes)
lane :beta do
  api_key = app_store_connect_api_key(key_id: ENV["ASC_KEY_ID"], issuer_id: ENV["ASC_ISSUER_ID"], key_filepath: ENV["ASC_KEY_PATH"])
  match(type: "appstore", readonly: is_ci, api_key: api_key)   # readonly in CI: never mints new certs
  build_app(scheme: "CortexMac")                               # = gym
  upload_to_testflight(api_key: api_key, skip_waiting_for_build_processing: true)  # = pilot
end
```
**TestFlight config (DIST-03)** [B — spec §6 + Apple docs]: 100 internal testers / 10,000 external testers; each build expires after **90 days**. `upload_to_testflight` supports `changelog:`, `groups:`, `distribute_external:`. **Gate:** real `match`/`build_app`/`upload_to_testflight` need enrollment + the ASC key + the private certs repo → wire the lanes now, gate execution (D-01). Structural now: grep Fastfile for `match(type: "appstore")`, `upload_to_testflight`, `app_store_connect_api_key`; grep Matchfile for no `file://` and no public-URL leak (mirror the P1 threat-model grep T-01-04-01).

---

## 5. Software-timed glass-to-glass — PERF-04 (D-07)  [A]

`CAMetalDisplayLink.Update` (the object delivered to `metalDisplayLink(_:needsUpdate:)`) exposes:
- **`targetPresentationTimestamp`** — "The time the system estimates until the display of the next frame." → **the on-glass present time. USE THIS** as the end of the software-timed measurement.
- `targetTimestamp` — "A deadline that indicates when your app needs to finish rendering to the drawable." → render deadline, **NOT** present time.
- `drawable` — the `CAMetalDrawable` to encode into.

Software-timed pipeline latency = `update.targetPresentationTimestamp − intentEmissionTime`, where `intentEmissionTime` is the decoder's `mach_absolute_time()` at intent emission (same clock as the BCI HID report timestamp, §1.3). **Label verbatim**: *"software-timed pipeline latency — excludes the compositor's 1-3 frames of scanout, which is exactly the delta the v1 photodiode rig (Phases 9-10) quantifies."* No estimated-offset fudge (D-07). Convert `mach_absolute_time()` ticks via `mach_timebase_info` (already wrapped in `CortexCore.Time.machAbsoluteNanoseconds()` per 01-03). **Canonical device = M5 Pro ProMotion** (corroborating); iPad-M4 capture = HUMAN-UAT (D-08).

---

## 6. Webgrid BPS metric — PERF-01, PERF-02, PERF-03 (D-11/D-12/D-13)  [A formula / B reference numbers]

**Authoritative formula** (ElonX.net "How does Neuralink measure performance", corroborated by spec §8 and the standard Wolpaw/Webgrid information-rate definition):
```
B = max(0, log2(N) × (Sc − Si) / t)
```
- `N` = number of selectable targets **including the delete/cancel key** (for a 30×30 webgrid, N = 900 ⇒ `log2(900) ≈ 9.81` bits/correct-selection — this `log2(N)` normalization is what makes a 30×30 result comparable to BrainGate's 6×6).
- `Sc` = correct selections, `Si` = incorrect selections, `t` = elapsed seconds.
- **The `max(0, …)` clamp is mandatory** (CONTEXT D-11 omits it) — never report negative bitrate.

**Leaderboard reference numbers** (report honestly, do NOT tune toward a pass-bar — D-12):
| Subject | Grid | BPS | Source |
|---|---|---|---|
| BrainGate (Pandarinath 2017) | 6×6 | **4.16** | spec §8 [B] |
| Neuralink P1 (Noland Arbaugh) "verified peak" used by project | 30×30 | **8.5** | PRIME blog, spec §8 [B] |
| Noland later peak (15% electrodes, day 133) | 30×30 | 9.51 | ElonX [B] — note exists; project locks 8.5 per spec |
| Bliss Chapman (ex-Neuralink) | 35×35 | 17.1 | ElonX / DJ Seo tweet [C] |

**PERF-03 reconciliation:** PERF-03's literal text says "mirror Soukoreff & MacKenzie 2004 ISO 9241-9 Fitts throughput." D-11 resolves this: the **leaderboard metric is the Webgrid BPS above**; the **S&M-2004 Fitts-TP is the *secondary cross-check*** already implemented in Phase 7 (`CortexReFITBench`, refit_bps 0.374). So Phase 8 PERF-03 = keep emitting the Fitts-TP cross-check *and* add the Webgrid BPS, reporting both. **Harness:** extend the deterministic headless `CortexReFITBench` 3-way ablation to emit Webgrid BPS — byte-identical across runs, CI-guardable, device-independent (algorithmic metric, no hardware gate — D-13, mirrors REFIT-03). Acquisition rule / time window / correct-vs-incorrect accounting per the Neuralink Webgrid definition (a "selection" = cursor dwell/click in the target cell; an incorrect = selection in a non-target cell).

---

## 7. README credibility — DIST-04 (implementer's discretion)  [A — from PROJECT.md/spec]

The architectural-commitments table + rejected-alternatives table are locked by PROJECT.md/spec §11. Rejected list to publish: **MLX** (unbounded P99, no ANE), **Network.framework** (50-200µs), **Swift `Task`** on hot path (unbounded latency), **ChaCha20-Poly1305** (slower than AES-GCM on FEAT_AES), **`_ANEClient`** (App Store rejection), **CocoaPods** (deprecated→SwiftPM), **hardware PTP** (no macOS NIC), **NDT2** (session-conditioning latency), **`(B,S,C)` layout** (not ANE-pinned→`(B,C,1,S)`), **h=4 attention** (actual NDT1 h=1-2), **`CADisplayLink` for Metal** (→`CAMetalDisplayLink`), **6×6 webgrid** (→30×30), **`altool`** (→notarytool). State the **v0 software-timed claim next to the forthcoming v1 photodiode claim**, disclosing every gate (free-team signing, ANE-eligible-vs-placed, iPad-M4 deferral, BCI-HID entitlement gating, software-vs-photodiode boundary, synthetic-vs-live-human BPS). Over-claiming undermines the thesis.

---

## 8. CI structural-gate tokens (D-06) — concrete grep targets for the new gates

Mirror the `hotpath-policy.sh` / `render-policy.sh` / `validate-privacy-manifest.sh` idiom (trap pre-armed + negative-control self-test):
- **HID surface gate:** assert presence of the descriptor Usage-Page byte pair (`0x05, 0x60`), the 5 report-struct names, `com.apple.developer.hid.virtual.device` in entitlements; assert the IOHIDUserDevice/HIDVirtualDevice instantiation is behind a gated/`#if` compile path so the free-team demo binary stays AMFI-safe.
- **Notarization gate:** assert `notarytool submit` + `stapler staple` present in lanes/scripts; assert **zero** `altool` occurrences.
- **Match gate:** assert `type("appstore")` + private `https://` git_url + no `file://` in Matchfile; assert `MATCH_PASSWORD` read from ENV (never literal).
- **BPS gate:** assert the `max(0, log2(N)*(Sc-Si)/t)` harness exists and is deterministic (run twice, `diff` byte-identical).

---

## Validation Architecture

Mapping each requirement / success criterion to its validation method and the "sampling rate" sufficient to catch regression (Nyquist framing). **Automated** items run in CI on every change; **Manual-Only** items are hardware/account-gated and routed to a never-auto-approved HUMAN-UAT checkpoint (they are *not* coverage gaps).

| Req / SC | What it asserts | Validation method | Class |
|---|---|---|---|
| SYS-01 | BCI HID report descriptor + 5 structs ported; `virtual.device` entitlement declared | Unit tests on report encode/decode + structural grep gate on descriptor tokens/struct names/entitlement key | **Automated** |
| SYS-02 | SMAppService register/status path + Switch-Control linkage scripted | Unit test of register/status code path (mocked); grep for `SMAppService.daemon`/`register()` | **Automated** (code) + **Manual-Only** (live registration) |
| SYS-03/04 | Bidirectional round trip: Scan-Info output → Item-Selection/Pointer input, instrumented log | In-app host-harness test driving the loop + asserting an instrumented round-trip log line | **Automated** |
| SYS-05 | Public BCI HID surface mirrored (descriptor + entitlement, not over-claimed) | Structural grep gate (Usage Page 0x60, report IDs, entitlement key); README honesty assertion | **Automated** |
| SYS-06 | synthetic-spike → IPC → NDT1(CoreML) → ReFIT → 120Hz webgrid hit, decoder genuinely in loop | Deterministic end-to-end harness asserting a webgrid hit AND that NDT1 inference ran (not the Lissajous shortcut) | **Automated** |
| DIST-01 | notarytool submit + stapler staple, no altool | Grep gate (present + zero altool) + negative-control self-test | **Automated** (structural) + **Manual-Only** (live submit) |
| DIST-02 | match(appstore) + ASC .p8 wired; no cert leak | Grep gate on Fastfile/Matchfile; `ruby -c` parse; MATCH_PASSWORD-from-ENV check | **Automated** (structural) + **Manual-Only** (live match) |
| DIST-03 | TestFlight 100/10k + 90-day documented | Doc/structural assertion (lane + runbook present) | **Automated** (structural) + **Manual-Only** (live upload) |
| DIST-04 | README commitments + rejected-alternatives tables + dual v0/v1 claim | Grep gate for required table rows + gate-disclosure phrases | **Automated** |
| PERF-01 | Webgrid BPS computed on synthetic Indy replay | Deterministic BPS harness, value emitted + range-checked (honest, not pinned to 4.16) | **Automated** |
| PERF-02 | Gap toward 8.5 BPS documented | README/doc assertion | **Automated** |
| PERF-03 | S&M-2004 Fitts-TP cross-check retained alongside BPS | Harness emits both metrics; byte-identical re-run | **Automated** |
| PERF-04 | P99 decoder+render+present < 25ms software-timed; targetPresentationTimestamp used | Software-timed bench (M5 Pro corroborating) asserting < 25ms p99; grep that `targetPresentationTimestamp` (not `targetTimestamp`) is the present clock | **Automated** (M5 corroborating) + **Manual-Only** (iPad-M4 canonical) |

**Manual-Only / HUMAN-UAT checkpoints (never auto-approve — fabricating these forges the credibility claim):**
1. Live `notarytool submit` + `fastlane match` + TestFlight upload (needs paid enrollment + ASC `.p8`).
2. iPad Pro M4 canonical software-timed latency capture (free team can't provision iPad headless).
3. On-device `IOHIDUserDevice` registration as a Switch Control HID provider + `virtual.device` entitlement activation + Accessibility grant.

---

## 9. Open questions for the planner (verify when wiring exact tasks)

- **[verify]** Exact full BCI HID descriptor byte array (Appendix has the complete listing) — fetch from the Apple BCI HID reference page when writing the descriptor-port task; only the header bytes are reproduced above.
- **[verify]** Whether macOS 26 lets a *non-driver* app create `HIDVirtualDevice`/`IOHIDUserDevice` with `com.apple.developer.hid.virtual.device` (forum says macOS 13 apps can; confirm for 26 — affects whether the gated path is app-level or needs a DriverKit dext). Does not block the buildable-now code.
- **[verify]** ASC API key JSON schema for `api_key_path` (key_id/issuer_id/key + `in_house`/`is_key_content_base64`) when authoring the placeholder JSON.
- **[confirm]** CortexReFITBench extension point for the Webgrid BPS emitter (Packages/CortexReFIT + CortexReFITBench) — read before writing the harness task.

---

## Sources (primary unless noted)

- Apple — BCI HID reference: `developer.apple.com/documentation/accessibility/brain-computer-interface-hid-reference-for-connecting-to-apple-platforms` [A]
- Apple — `com.apple.developer.hid.virtual.device` entitlement: `developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device` [A]
- Apple — CoreHID / `HIDVirtualDevice` / "Creating virtual devices": `developer.apple.com/documentation/corehid` , `…/corehid/creatingvirtualdevices` [A]
- Apple — `SMAppService`: `developer.apple.com/documentation/servicemanagement/smappservice` [A]
- Apple — `CAMetalDisplayLink.Update` (`targetPresentationTimestamp` vs `targetTimestamp`): `developer.apple.com/documentation/quartzcore/cametaldisplaylink/update` [A]
- Local toolchain — `xcrun notarytool submit --help` (Xcode 26.3.0) [A, authoritative]
- fastlane docs (Context7 `/fastlane/docs`) — `app_store_connect_api_key`, `match appstore`, `upload_to_testflight`, `api_key_path` [A]
- Webgrid BPS formula — elonx.net/how-does-neuralink-measure-the-performance-of-its-interface [B]; corroborated by `docs/cortex-spec.md` §8
- Synchron + Apple BCI HID announcement — businesswire.com/news/home/20250804537175 ; massdevice.com/synchron-bci-integration-apple-tech [B, provenance only — no entitlement strings]
