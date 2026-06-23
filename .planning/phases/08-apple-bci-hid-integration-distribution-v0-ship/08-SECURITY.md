---
phase: 8
slug: apple-bci-hid-integration-distribution-v0-ship
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-23
---

# Phase 8 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Covers Plans 08-01 through 08-07 (37 threats across 7 plan files).
> Dispositions and STRIDE categories are authoritative from each PLAN `<threat_model>`; evidence is from the gsd-security-auditor verification run (2026-06-23).

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Free-team binary / AMFI | CortexMac/CortexiOS/CortexDaemon signed under free Personal team (57YW6M29S7); the `com.apple.developer.hid.virtual.device` entitlement is declared but AMFI will SIGKILL any activation attempt without a managed provisioning profile | Entitlement key only — live IOHIDUserDevice symbols are absent from the default binary (compile-time `#if CORTEX_HID_LIVE` gate) |
| HID report wire (host ↔ virtual device) | BCI HID Usage Page 0x60 report structs (RID 1-4) encoding cursor intent, button state, scan selection, and scan feedback as fixed-size byte frames | Neural cursor intent (synthetic); no real neural data crosses this boundary in v0 |
| Scan-Info closed loop (host harness ↔ ScanInfoRoundTrip) | ScanInfoRoundTrip.respond(to:) consumes a BCIOutputScanInfoReport (numberOfItems, seed) and emits BCIInputItemSelection + BCIInputPointerReport — the intent path is a pure function of the input | Synthetic BCI input: itemIndex, Int8 pointer deltas |
| Software-timed glass-to-glass measurement | GlassToGlassTimer.sample(_:presentTimestampSeconds:) consumes mach_absolute_time at intent-emission and CAMetalDisplayLink targetPresentationTimestamp at present; logs ns deltas | Software pipeline latency only; no real electrode data |
| Distribution / App Store Connect | fastlane lanes and notarize.sh pipe the built .app to Apple's notary service and TestFlight; all credentials flow via ENV-only | ASC .p8 key, MATCH_PASSWORD, team IDs — never committed; lanes fail loudly when ENV vars unset |
| README / public artifact | README.md is the credibility artifact reviewed by Bliss Chapman / Nir Even-Chen; it must not leak credentials or fabricate gated numbers | Latency claims (software-timed only), BPS numbers (synthetic replay only), gate disclosures |

---

## Threat Register

### Plan 08-01 — BCI HID Surface

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-08-01-01 | Tampering | BCIHIDReports.swift | mitigate | Exact byte-size assertions: RID1=3, RID2=5, RID3=4, RID4-in=2, RID4-out=7 bytes; decode(encode(x))==x for all 5 structs; signed Int8 pointer extreme round-trip; wrong-length decode returns nil. Evidence: `BCIHIDReportTests.swift` — 7 `@Test` behaviors confirmed; BCIHIDDescriptor.swift line 8: `usagePage: [UInt8] = [0x05, 0x60]` present | closed |
| T-08-01-02 | Elevation / DoS | VirtualDeviceGate.swift | mitigate | `#if CORTEX_HID_LIVE` file-scope gate; live `IOHIDUserDeviceHandleReportWithTimeStamp` symbol appears only inside the gated block (lines 21-62). Evidence: `VirtualDeviceGate.swift` line 1 `#if CORTEX_HID_LIVE`; `hid-surface-policy.sh` exit=0 on real tree; `hid-surface-policy.sh --self-test` exit=0 (7/7 controls pass incl. "gated live symbol is ALLOWED" scoping control) | closed |
| T-08-01-03 | Spoofing / Repudiation | Cortex.entitlements (×3) | mitigate | `com.apple.developer.hid.virtual.device` declared with `<true/>` in all 3 targets; comment on line 9 of each file: "declared but INERT under free Personal-team signing … activation needs a managed provisioning profile". Evidence: `Apps/CortexDaemon/Cortex.entitlements`, `Apps/CortexMac/Cortex.entitlements`, `Apps/CortexiOS/Cortex.entitlements` — confirmed by inspection | closed |
| T-08-01-04 | Tampering | hid-surface-policy.sh | mitigate | Structural CI grep gate asserts descriptor Usage-Page bytes, all 5 report-struct names, entitlement key in all 3 targets, `#if CORTEX_HID_LIVE`; forbids ungated live HID symbol and app-sandbox; --self-test self-weakening detection. Evidence: `hid-surface-policy.sh` exit=0; `--self-test` exit=0 (PASS: strip descriptor → exit 1; strip BCIOutputScanInfoReport → exit 1; strip HID entitlement → exit 1; strip #if gate → exit 1; inject ungated symbol → exit 1; gated symbol allowed → exit 0; inject app-sandbox → exit 1) | closed |
| T-08-01-05 | Information Disclosure | HID surface (no PII/secrets/network) | accept | See Accepted Risks Log — AR-08-01-05 | closed |

### Plan 08-02 — Scan-Info Round-Trip Closed Loop

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-08-02-01 | Tampering / DoS | ScanInfoRoundTrip.swift | mitigate | `guard count > 0 else { return (0, SIMD3<Int8>(0, 0, 0)) }` clamp for degenerate numberOfItems=0. Evidence: `ScanInfoRoundTrip.swift` confirmed; `ScanInfoRoundTripTests.swift` Test 5 (`respondHandlesZeroItemsSafely`) asserts itemIndex==0, pointer.position==(0,0,0), log.entries.count==1 on numberOfItems=0 | closed |
| T-08-02-02 | Spoofing / Repudiation | RoundTripLog.swift | mitigate | `func record(_ entry: RoundTripEntry)` appends exactly one entry per `respond(to:)` call; comment: "Called exactly once per `respond(to:)` (threat T-08-02-02)". Evidence: `RoundTripLog.swift` line 71; `ScanInfoRoundTripTests.swift` Test 3 (`respondAppendsOneLogEntryPerCycle`) asserts count progresses 0→1→2 across two calls | closed |
| T-08-02-03 | Tampering | ScanInfoRoundTrip.swift | mitigate | Intent computation is a pure function of Scan-Info input — `splitMix64` pure integer hash (SteeleVigna, no entropy source); `machAbsoluteNanoseconds()` confined to log-only path; no `Date()`, `random`, or `arc4random` in intent path. Evidence: `ScanInfoRoundTrip.swift` comment "NOT an entropy-backed generator"; `ScanInfoRoundTripTests.swift` Test 4 (`respondIsDeterministic`) asserts byte-identical intent across two independent instances with same input | closed |
| T-08-02-04 | Information Disclosure | Scan-Info loop (synthetic UI state) | accept | See Accepted Risks Log — AR-08-02-04 | closed |

### Plan 08-03 — Closed-Loop Pipeline and Glass-to-Glass Timer

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-08-03-01 | Spoofing / Repudiation | ClosedLoopPipeline.swift | mitigate | `NeuralDecoder.decode(buffer)` call site present in `decodeWithModel` function; comment explicitly forbids the "oscillator-velocity shortcut (which bypasses the decoder entirely)"; no "LissajousProducer" text in file; `filter.step(measurement: decoded, ...)` and `integrator.integrate(latest: velocity, dt: Self.dt)` both present confirming Kalman and CursorIntegrator are genuinely in the loop. Evidence: `ClosedLoopPipeline.swift` confirmed by inspection | closed |
| T-08-03-02 | Tampering | GlassToGlassTimer.swift | mitigate | `presentTimestampSeconds` parameter doc states this MUST be `CAMetalDisplayLink update.targetPresentationTimestamp` and explicitly forbids `update.targetTimestamp` (the render DEADLINE). Evidence: `GlassToGlassTimer.swift` lines 37-39; no binding of `targetTimestamp` as the present clock in the file | closed |
| T-08-03-03 | Repudiation | GlassToGlassTimer.swift | mitigate | `public static let methodologyLabel = "software-timed pipeline latency — excludes the compositor's 1-3 frames of scanout, which is exactly the delta the v1 photodiode rig (Phases 9-10) quantifies"` (lines 37-39). Evidence: verbatim label confirmed; README Latency section quotes it exactly; bench stdout carries it | closed |
| T-08-03-04 | Spoofing | M5-Pro corroborating number vs iPad-M4 canonical capture | mitigate | The latency histogram is device-annotated "M5-Pro-corroborating"; the headless CortexDemoBench prints the iPad-M4-canonical-capture-is-HUMAN-UAT note; the canonical iPad-Pro-M4 capture is the Plan 07 never-auto-approve gate (D-08). The M5-Pro number is never presented as the iPad-M4 canonical figure. Evidence: `readme-policy.sh` exit=0 confirms the device-disclosure phrases (software-timed + iPad-M4 deferral present); `08-HUMAN-UAT.md` Gate 2 holds the canonical capture as never-auto-approve | closed |
| T-08-03-05 | Tampering / DoS | CursorIntegrator.swift | mitigate | `guard vx.isFinite, vy.isFinite else { return position }` rejects non-finite velocity; `clampFinite(_:)` returns `lowerBound` (0.0) for non-finite input and `min(max(v, 0.0), 1.0)` for finite — explicit NaN guard plus [0,1] clamp (reused unchanged from Phase-6 T-06-02-01). Evidence: `CursorIntegrator.swift` confirmed by inspection | closed |
| T-08-03-06 | Information Disclosure | Synthetic Indy replay / gitignored .mlpackage | accept | See Accepted Risks Log — AR-08-03-06 | closed |

### Plan 08-04 — Distribution Pipeline

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-08-04-01 | Information Disclosure | .gitignore / Appfile | mitigate | `.gitignore` lines 47-60: `*.p8`, `*.p12`, `*.cer`, `*.certSigningRequest`, `*.mobileprovision`, `*.provisionprofile`, `fastlane/asc_api_key.json` all gitignored; `!fastlane/asc_api_key.json.example` exception keeps the placeholder committable. `Appfile` reads `apple_id`, `team_id`, `itc_team_id` from `ENV["ASC_APPLE_ID"]` etc — no literal email/team-id. Evidence: `.gitignore` confirmed; `fastlane/Appfile` lines 12-15 confirmed | closed |
| T-08-04-02 | Information Disclosure | fastlane/Matchfile | mitigate | `git_url(ENV["MATCH_GIT_URL"] || "https://github.com/…")` — https only, no `file://`, no `git@`. Evidence: `match-policy.sh` exit=0; `--self-test` exit=0 (8/8 controls pass: local-disk URL injection → exit 1; appstore→development downgrade → exit 1; drop https git_url → exit 1; drop git_url entirely → exit 1; inject literal MATCH_PASSWORD= in Matchfile → exit 1; inject literal MATCH_PASSWORD= in Fastfile → exit 1; inject ENV-default password literal → exit 1; inject ssh git_url → exit 1) | closed |
| T-08-04-03 | Spoofing / Tampering | fastlane/Matchfile + Fastfile | mitigate | MATCH_PASSWORD read from ENV by `match` itself — never declared in Matchfile or Fastfile; Fastfile `require_dist_env` function calls `UI.user_error!` when `MATCH_PASSWORD` is unset. Evidence: `match-policy.sh` exit=0; `--self-test` exit=0 confirming literal-password injection controls bite | closed |
| T-08-04-04 | Tampering | notarize.sh / Fastfile | mitigate | `xcrun notarytool submit` + `xcrun stapler staple` present in `notarize.sh`; zero `altool` references anywhere (runtime-assembled `FORBIDDEN_UPLOADER="$(printf 'al%s' 'tool')"` in gate). Evidence: `notarize-policy.sh` exit=0; `--self-test` exit=0 (4/4 controls pass: strip notarytool submit → exit 1; strip stapler staple → exit 1; inject altool into notarize.sh → exit 1; inject altool into Fastfile → exit 1) | closed |
| T-08-04-05 | Repudiation / Spoofing | ci.yml | mitigate | CI runs `ruby -c fastlane/Fastfile && ruby -c fastlane/Matchfile && ruby -c fastlane/Appfile` (parse-only); no live `fastlane beta` / `match` / `notarytool` lane executed in CI; bundler smoke is `continue-on-error: true`. Evidence: `ci.yml` lines 508-521 (parse step), lines 526-539 (bundler `continue-on-error: true`); no `fastlane beta` invocation in ci.yml | closed |
| T-08-04-06 | Elevation | App Store provisioning-profile entitlement | accept | See Accepted Risks Log — AR-08-04-06 | closed |

### Plan 08-05 — Webgrid BPS Metric

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-08-05-01 | Tampering | WebgridBPS.swift | mitigate | `return Swift.max(0, targetBits(n: n) * net / seconds)` at line 87 — mandatory clamp; `WebgridBPSTests.swift` Test 2 (`clampBitesOnNetNegative`) asserts `bitsPerSecond(n:900, correct:5, incorrect:20, seconds:30) == 0.0` and confirms the unclamped value would be negative. Evidence: `WebgridBPS.swift` line 87 confirmed; `bps-policy.sh` exit=0; `--self-test` exit=0 (strip Swift.max(0, → exit 1; strip formula line → exit 1) | closed |
| T-08-05-02 | Spoofing / Repudiation | webgrid_bps.json (bench output) | mitigate | `"caveat": "synthetic Indy replay, NOT a live-human two-stage ReFIT retrain; reference peak 8.5 BPS; honest measured number, NOT tuned toward 4.16 — D-12"` present in `webgrid_bps.json`; bench is seed/index-driven with no clock/RNG (deterministic, cannot be silently re-rolled). Evidence: `.planning/phases/08-.../webgrid_bps.json` confirmed; `08-bps-evidence.md` section "NOT engineered toward ≥ 4.16" confirmed | closed |
| T-08-05-03 | Tampering | webgrid_bps.json / CortexReFITBench | mitigate | `bps-policy.sh` determinism leg: runs `CortexReFITBench --smoke` twice and diffs `webgrid_bps.json` byte-for-byte across both runs AND against the committed copy. Evidence: `bps-policy.sh` exit=0 — "webgrid_bps.json byte-identical across two runs AND == the committed copy" | closed |
| T-08-05-04 | Repudiation | WebgridBPS.swift | mitigate | Header comment in `WebgridBPSTests.swift` and `WebgridBPS.swift`: "DISTINCT from `FittsThroughput`"; `referencePeakBPS = 8.5`, `brainGate6x6BPS = 4.16` are named constants (not unnamed magic numbers). Evidence: `WebgridBPS.swift` confirmed; `WebgridBPSTests.swift` Test 5 asserts `referencePeakBPS == 8.5` and `brainGate6x6BPS == 4.16` | closed |
| T-08-05-05 | Tampering | Packages/CortexReFIT/.bench/webgrid_bps.json | mitigate | `bps-policy.sh` determinism gate confirms the `.bench/` copy produced by the bench equals the committed `.planning/.../webgrid_bps.json` copy byte-for-byte; the Phase-7 refit_bps.json write is kept byte-for-byte unchanged. Evidence: `bps-policy.sh` exit=0 as above; `.bench/webgrid_bps.json` contents confirmed: `"refit_webgrid_bps": 1.953047883714651`, `"formula": "B = max(0, log2(N)*(Sc-Si)/t)"`, `"n_targets": 900` | closed |
| T-08-05-06 | Information Disclosure | Algorithmic BPS over public synthetic data | accept | See Accepted Risks Log — AR-08-05-06 | closed |
| T-08-05-07 | Spoofing / Repudiation | webgrid_bps.json / 08-bps-evidence.md | mitigate | `"incorrect_model": "none — single-target dwell-to-select; Si structurally 0; BPS is upper-bound"` present in `webgrid_bps.json`; `08-bps-evidence.md` contains mandatory Si=0 disclosure section titled "MANDATORY Si (incorrect) disclosure" — the silent bare `incorrect: 0` over-claim is forbidden. Evidence: `webgrid_bps.json` confirmed; `08-bps-evidence.md` confirmed | closed |

### Plan 08-06 — Credibility-Grade README

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-08-06-01 | Spoofing / Repudiation | README.md | mitigate | README contains: rejected-alternatives table (MLX, _ANEClient, CocoaPods, altool); dual latency claim with verbatim `software-timed pipeline latency` phrase; v1 photodiode SPEC TARGET `24.7 ± 1.3 ms` framed as spec target pending capture; all 6 gate disclosures (free/Personal-team, ANE-eligible vs placed, iPad-M4, BCI-HID entitlement, software vs photodiode, synthetic vs live-human BPS). Evidence: `readme-policy.sh` exit=0 (13/13 required checks pass) | closed |
| T-08-06-02 | Information Disclosure | README.md | mitigate | No PEM private-key header, no inline `MATCH_PASSWORD =`, no email/PII, no ASC issuer UUID in README. Evidence: `readme-policy.sh` exit=0 (4/4 forbidden checks pass); `--self-test` exit=0 (inject PEM key → exit 1; inject email → exit 1; inject inline MATCH_PASSWORD → exit 1; inject issuer UUID → exit 1) | closed |
| T-08-06-03 | Tampering | readme-policy.sh | mitigate | `readme-policy.sh --self-test` exit=0: 9/9 controls pass (5 disclosure-strip + 4 secret-injection); a silently weakened gate fails CI loudly. Evidence: `--self-test` output confirmed above | closed |
| T-08-06-04 | Repudiation | README.md content | mitigate | README confirmed present at project root with 233 lines including Webgrid BPS `max(0` formula token, `8.5` leaderboard gap, `synthetic` BPS caveat, and `Personal team`/`free-team` signing disclosure; cites the committed evidence artifacts (08-bps-evidence.md, webgrid_bps.json) by name. Evidence: `readme-policy.sh` exit=0; README lines 1-233 read in full | closed |
| T-08-06-05 | (n/a) | README (static docs, no runtime surface) | accept | See Accepted Risks Log — AR-08-06-05 | closed |

### Plan 08-07 — HUMAN-UAT Never-Auto-Approve Gates

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-08-07-01 | Spoofing / Repudiation | 08-HUMAN-UAT.md | mitigate | `08-HUMAN-UAT.md` exists and contains "CRITICAL — ALL THREE GATES ARE NEVER AUTO-APPROVED" header; each gate carries "NEVER AUTO-APPROVE" sub-heading; `auto_approved: 0` in summary block. Evidence: `08-HUMAN-UAT.md` lines 10-19 (critical block), lines 65/139/203 (per-gate "NEVER AUTO-APPROVE"), lines 255-260 (summary: `verified: 0`, `deferred: 3`, `auto_approved: 0`) | closed |
| T-08-07-02 | Repudiation | 08-HUMAN-UAT.md Gate 2 | mitigate | Gate 2 runbook: `targetPresentationTimestamp` is the specified measurement endpoint; `targetTimestamp` explicitly forbidden in the flip procedure; `deviceAnnotation = "iPad-Pro-M4-software-timed-canonical"` required; verbatim methodology label required in captured output; each gate has an evidence slot that "verified" requires be filled. Evidence: `08-HUMAN-UAT.md` lines 123-184 confirmed | closed |
| T-08-07-03 | Information Disclosure | 08-HUMAN-UAT.md Gate 1 evidence slot | mitigate | Evidence slot for Gate 1 explicitly states "do NOT capture the `.p8`/passphrase" and "do NOT paste `ASC_KEY_*` / `MATCH_PASSWORD` / the `.p8`" — creds via ENV only; the slot captures the notarytool submission id + TestFlight screenshot, not the key. Evidence: `08-HUMAN-UAT.md` lines 101-107 confirmed | closed |
| T-08-07-04 | Tampering | 08-VALIDATION.md | mitigate | `08-VALIDATION.md` present; the 3 live gates stay Manual-Only; Per-Task Verification Map covers all 15 task IDs (8-01-01 through 8-07-01) each with an `<automated>` command; Wave 0 checklist shows all 5 policy scripts and all 4 test suites checked `[x]`; deferred gates record a paused state and do not mark the live half done. Evidence: `08-VALIDATION.md` lines 43-80 confirmed | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-08-01-05 | T-08-01-05 | The BCI HID surface port carries no PII, no secrets, and no network I/O — only pure Swift value types, public HID descriptor bytes, and declared (INERT) entitlement keys. The only sensitive material in the project (ASC API keys, signing certs) lives in the Plan 08-04 distribution surface, not here. Accepted as a no-sensitive-data surface. | gsd-security-auditor | 2026-06-23 |
| AR-08-02-04 | T-08-02-04 | The Scan-Info round-trip closed loop runs entirely in-process over public BCI HID protocol report shapes using synthetic UI state — no PII, no secrets, no network. There is no sensitive data surface to disclose. (Byte-exact compliance against Apple's private HID stack is separately gated by the Plan 07 Gate 3 managed-entitlement HUMAN-UAT — a verification gate, not a disclosure risk.) Accepted as a no-sensitive-data surface. | gsd-security-auditor | 2026-06-23 |
| AR-08-03-06 | T-08-03-06 | The closed-loop pipeline runs an on-device synthetic Indy replay through the decoder — no PII, no secrets, no network, no real electrode data. The `.mlpackage` model is local gitignored R&D and the model URL is read from ENV, never committed. No sensitive data surface. (The separate compositor-scanout exclusion is a disclosed methodology limitation carried by T-08-03-03's verbatim `methodologyLabel`, not an accepted risk.) Accepted as a no-sensitive-data surface. | gsd-security-auditor | 2026-06-23 |
| AR-08-04-06 | T-08-04-06 | The App Store distribution path uses `match(appstore)` with Apple-managed provisioning profiles; the entitlement surface is exactly Plan 08-01's declared-and-gated set, so no over-broad entitlement is hand-authored. Provisioning-profile generation is the gated live run (Plan 07 Gate 1 HUMAN-UAT), reviewed by a human and never auto-approved. The full pipeline (Fastfile `beta` lanes, `notarize.sh` notarytool submit, `match(appstore)`) is real, CI-parsed, and structurally gated. Accepted as transferred to Apple-managed profile generation under human gate. | gsd-security-auditor | 2026-06-23 |
| AR-08-05-06 | T-08-05-06 | The Webgrid BPS is a device-independent algorithmic metric computed over public synthetic Indy data — no PII, no secrets, no network, no sensitive surface. (The synthetic-vs-live-human provenance and the 6.55 BPS gap to the 8.5 verified peak are separately disclosed and gate-enforced under the mitigated threats T-08-05-02 / T-08-05-07, not accepted here.) Accepted as a no-sensitive-data surface. | gsd-security-auditor | 2026-06-23 |
| AR-08-06-05 | T-08-06-05 | The README is static documentation with no network and no runtime surface; the only residual risk is content accuracy or a credential leak, both covered by the mitigated threats T-08-06-01 through T-08-06-04 and the `readme-policy.sh` gate (which enforces every gate-disclosure phrase and forbids secret leaks). The 3 Plan 07 Manual-Only live halves remain disclosed as "READY, GATED" — not done, not fabricated. Accepted as a static-docs no-runtime-surface item. | gsd-security-auditor | 2026-06-23 |

*Accepted risks do not resurface in future audit runs.*

---

## Unregistered Threat Flags

The following items were flagged in SUMMARY.md sections during Phase 08 execution. Each maps to an existing registered threat — none are unregistered.

| Flag Source | SUMMARY Reference | Maps To | Disposition |
|-------------|-------------------|---------|-------------|
| Executor reworded "LissajousProducer" comment to "oscillator-velocity shortcut" to avoid tripping the forbidden grep | 08-03-SUMMARY.md | T-08-03-01 | Informational — comment wording is audit-irrelevant; the grep-forbidden literal (`LissajousProducer`) is confirmed absent from `ClosedLoopPipeline.swift` and the decoder is genuinely in the loop |
| Executor reworded `targetTimestamp` reference in `GlassToGlassTimer.swift` | 08-03-SUMMARY.md | T-08-03-02 | Informational — the mitigation is confirmed present (targetPresentationTimestamp used; targetTimestamp explicitly forbidden in parameter doc) |
| match-policy.sh self-test had a non-biting MATCH_PASSWORD negative control; fixed so the control injects the forbidden bare inline-passphrase assignment form (an `ENV[…]`-less literal assignment) | 08-04-SUMMARY.md | T-08-04-03 | Informational — fixed before phase complete; `--self-test` confirmed exit=0 with all 8 controls biting at audit time |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-23 | 37 | 37 | 0 | gsd-security-auditor (+ orchestrator reconciliation to PLAN dispositions/categories) |

Disposition split (authoritative from PLANs): 31 mitigate (all closed) + 6 accept (all documented in the Accepted Risks Log) = 37.

### Policy Script Execution Evidence

All five structural CI gate scripts were run against the real project tree and their self-tests were run to confirm negative controls bite. All exits are 0.

| Script | Real Tree Exit | --self-test Exit | Controls Verified |
|--------|---------------|-----------------|-------------------|
| `Tools/scripts/hid-surface-policy.sh` | 0 | 0 | 7/7 (strip descriptor → 1; strip BCIOutputScanInfoReport → 1; strip HID entitlement → 1; strip #if gate → 1; inject ungated symbol → 1; gated symbol allowed → 0; inject app-sandbox → 1) |
| `Tools/scripts/match-policy.sh` | 0 | 0 | 8/8 (inject local-disk URL → 1; appstore→development → 1; drop https git_url → 1; drop git_url entirely → 1; inject literal MATCH_PASSWORD= (Matchfile) → 1; inject literal MATCH_PASSWORD= (Fastfile) → 1; inject ENV-default password literal → 1; inject ssh git_url → 1) |
| `Tools/scripts/notarize-policy.sh` | 0 | 0 | 4/4 (strip notarytool submit → 1; strip stapler staple → 1; inject altool into notarize.sh → 1; inject altool into Fastfile → 1) |
| `Tools/scripts/bps-policy.sh` | 0 | 0 | 2/2 + determinism (strip Swift.max(0, → 1; strip formula line → 1; webgrid_bps.json byte-identical across two runs AND == committed copy) |
| `Tools/scripts/readme-policy.sh` | 0 | 0 | 9/9 (strip photodiode → 1; strip software-timed phrase → 1; strip 24.7 → 1; strip synthetic BPS caveat → 1; strip 8.5 gap → 1; inject PEM key → 1; inject email/PII → 1; inject inline MATCH_PASSWORD → 1; inject issuer UUID → 1) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer) — 31 mitigate, 6 accept, authoritative from the PLAN threat models
- [x] Accepted risks documented in Accepted Risks Log (6 entries: AR-08-01-05, AR-08-02-04, AR-08-03-06, AR-08-04-06, AR-08-05-06, AR-08-06-05)
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-23
