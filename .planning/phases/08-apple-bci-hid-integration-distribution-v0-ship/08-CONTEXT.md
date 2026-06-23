# Phase 8: Apple BCI HID Integration, Distribution & v0 Ship - Context

**Gathered:** 2026-06-23
**Status:** Ready for planning

<domain>
## Phase Boundary

The **v0 milestone** — the convergence phase. It wires all seven prior phases into one running closed-loop artifact (synthetic Indy/Loco spike → kqueue/shm IPC → NDT1 CoreML decoder → ReFIT-Kalman → 120Hz 30×30 webgrid), registers Cortex as a BCI **HID provider** against the available Switch Control / Accessibility surface, builds the full `notarytool` + `fastlane match` → TestFlight distribution pipeline, and publishes the **software-timed glass-to-glass claim** + credibility-grade README. Delivers SYS-01..06, DIST-01..04, PERF-01..04.

**In scope:** the first full end-to-end app assembly; the in-app bidirectional closed-loop round trip (host UI-state → intent → refinement) with an instrumented log; the HID-provider entitlement/Info.plist surface mirroring Synchron's public reference; the complete signing/notarization/TestFlight pipeline as real code + lanes + scripts; the software-timed `mach_absolute_time` glass-to-glass measurement; the Webgrid information-rate BPS metric vs the 4.16/8.5 leaderboard; the README architectural-commitments + rejected-alternatives tables and the v0 claim.

**Not in this phase (gated/deferred):** the live Apple submission to TestFlight and the paid-signing-dependent entitlement activations (gated on Apple Developer Program enrollment — never auto-approved); the iPad Pro M4 canonical latency capture + on-device Switch Control registration (HUMAN-UAT); the photodiode-instrumented v1 glass-to-glass claim, rig, and launch video (Phases 9-10).

**Scope anchor:** discussion clarifies HOW we ship v0 honestly given a solo-dev, free-team, no-paid-enrollment reality — it does not add capabilities beyond the fixed SYS/DIST/PERF requirement set.

</domain>

<decisions>
## Implementation Decisions

### Distribution & Apple Developer enrollment
- **D-01: Wire the full distribution pipeline as real code; gate the live Apple submission.** The complete `notarytool submit` + `xcrun stapler staple` + `fastlane match` + TestFlight-upload pipeline is built as real Fastfile lanes + scripts this phase (honoring the P1 D-10 swap targets: Matchfile `file:///` → private GitHub remote + `MATCH_PASSWORD`, uncomment Appfile identity fields, real lanes replacing the placeholders). The actual submission to Apple is **gated behind a never-auto-approved HUMAN-UAT checkpoint** because paid Apple Developer Program enrollment is **not active** (P1 D-09/D-12 deferred it here). v0 ships the closed-loop demo + software-timed claim + README **now**; TestFlight (DIST-03) flips from gated to live the day enrollment + the ASC `.p8` key land. DIST-01/DIST-02 are satisfied as built-and-structurally-verified pipeline; the live run is the gated checkpoint. **This is the keystone decision — it sets the wire-and-gate pattern for the whole phase.**
- **D-02: Keep the Phase-2 single-process Keychain fallback for the v0 demo; wire the `keychain-access-groups` entitlement surface but gate its activation on paid signing.** CF#1 (P2) established that an entitled binary is AMFI-SIGKILLed under free-team signing. The demo uses the proven single-process Keychain + key-over-`mach_msg` fallback; the real cross-process `keychain-access-groups` entitlement is declared in the entitlement surface but its activation/verification is a paid-signing HUMAN-UAT gate.
- **D-03: Keep the standalone `type:tool` daemon driving the demo; script the SMAppService register/install, gate the signed helper install.** D-09 (P2) named SMAppService as the App-Store production form. This phase keeps the standalone producer for the runnable v0 demo and writes/scripts the SMAppService register/install path, but the **signed privileged-helper install is gated on enrollment** (paid signing required for the helper).

### BCI HID integration — honest entitlement surface
- **D-04: Build against the public Switch Control / Accessibility (AccessibilityHID, WWDC '25) surface; mirror Synchron's publicly-declared entitlement + Info.plist keys; document the managed BCI-HID entitlement as request-gated.** The May-2025 BCI HID provider entitlement is Apple-managed (Synchron is the partner reference; the protocol surface is likely partner-gated/NDA'd) and is **not grantable to a solo dev in-sprint**. SYS-01 is satisfied as "Cortex registered against the available HID surface, with the BCI-HID entitlement surface declared and gated" — the same instrumentation-honesty framing as ANE-eligible-vs-placement (P5) and M5-corroborating-vs-iPad-canonical (P6/P7). SYS-05 = mirror the public Synchron entitlement/Info.plist surface. **Do not** claim a granted entitlement or assume Apple approval.
- **D-05: The bidirectional closed-loop round trip (SYS-03/04) is demonstrated by an in-app host harness with an instrumented log.** The CortexMac/iOS app itself (or an in-app host view) sends UI state (cursor position, target list) into the decode loop and applies the returned intent; an instrumented round-trip log satisfies SC#2's "instrumented log shows the round trip." No external-app or granted-entitlement dependency — it runs on the demo device today.
- **D-06: HID-provider registration is verified structurally in CI + a Manual-UAT checkpoint.** A structural CI grep gate verifies the entitlement keys + Info.plist surface (same idiom as the existing no-app-sandbox / no-`_ANEClient` / `hotpath-policy.sh` gates); actual on-device registration as a Switch Control provider is a **never-auto-approved HUMAN-UAT checkpoint**.

### v0 closed-loop demo & software-timed glass-to-glass claim
- **D-07: Software-timed glass-to-glass (PERF-04) = intent-emission `mach_absolute_time` → `CAMetalDisplayLink` present / `targetPresentationTimestamp`.** Explicitly labeled **"software-timed pipeline latency — excludes the compositor's 1-3 frames of scanout, which is exactly the delta the v1 photodiode rig (Phases 9-10) quantifies."** This is the honest software number that *sets up* the v1 claim; it is NOT presented as the final glass-to-glass figure. No estimated-compositor-offset fudge.
- **D-08: Canonical measurement = M5 Pro ProMotion (corroborating-canonical); iPad Pro M4 canonical capture is a never-auto-approved HUMAN-UAT checkpoint.** Consistent with D-11/D-12 across Phases 5/6/7. The software-timed v0 number is reported on M5 Pro with the iPad-M4 canonical capture deferred to HUMAN-UAT.
- **D-09: The runnable v0 demo artifact is the CortexMac full closed-loop GUI app.** It runs the full synthetic-spike → IPC → NDT1 (CoreML) → ReFIT → 120Hz webgrid loop with `MTL_HUD_ENABLED=1`, launchable via the Xcode GUI on the free Personal team (which signs Mac GUI apps). The iPad build is the **same code**, gated on provisioning. (Satisfies the portfolio working-demo requirement.)
- **D-10: The closed loop is driven by synthetic Indy/Loco spike replay through NDT1 — the decoder is genuinely in the loop (true SYS-06).** Synthetic spike frames (the Phase-4 Indy/Loco dataset) flow through IPC → NDT1 → ReFIT so the CoreML decoder + Kalman filter are actually exercised in the live demo — not the Phase-6 Lissajous velocity shortcut (which bypasses the decoder). SYS-06's "synthetic-spike → decoder → ReFIT-Kalman → cursor → webgrid hit" is met literally.

### Webgrid BPS & the BPS leaderboard (SC#5)
- **D-11: Compute the standard Neuralink / Bliss-Chapman Webgrid information-rate BPS on the 30×30 grid; keep the Phase-7 S&M-2004 Fitts-TP as a secondary cross-check.** Formula: `BPS = log2(N_targets) × (correct − incorrect) / time` (grid-size-normalized via `log2(N)`, so a 30×30 result is comparable to BrainGate's 6×6 4.16). This closes P7 **D-13**, which explicitly deferred the 4.16/8.5 comparison to Phase 8 precisely because the Fitts throughput (0.374) is NOT the Webgrid bitrate.
- **D-12: Report the measured synthetic-replay BPS with an explicit live-vs-synthetic caveat + the documented gap toward 8.5 — no metric-gaming.** State the actual number Cortex achieves on **synthetic** Indy replay, explicitly framed as synthetic-replay (NOT a live-human two-stage ReFIT retrain), with the honest gap to the P1 peak (8.5). Do **not** engineer/tune the harness toward ≥4.16 as a pass bar — that would game the metric and violate the project's instrumentation-honesty ethos. If the honest number differs from 4.16, report it honestly rather than forcing a "matched BrainGate" headline.
- **D-13: BPS is measured in a deterministic headless harness (extend the Phase-7 `CortexReFITBench` 3-way ablation).** Byte-identical across runs, CI-guardable, device-independent (BPS is an algorithmic metric, not a latency claim — no hardware gate needed). Mirrors REFIT-03.

### Implementer's Discretion
- **README credibility framing (DIST-04)** — folds into implementer's discretion under the established honesty ethos. The architectural-commitments table and rejected-alternatives table (MLX, Network.framework, Swift `Task`, ChaCha20-Poly1305, `_ANEClient`, CocoaPods, 6×6 webgrid, h=4 attention, `(B,S,C)` layout, `altool`) are largely locked by PROJECT.md; the planner assembles them and states the v0 software-timed claim **next to** the forthcoming v1 photodiode claim, disclosing every honest gate (free-team signing, ANE eligibility-vs-placement, iPad-M4 deferrals, BCI-HID entitlement gating, software-vs-photodiode timing boundary). Over-claiming would undermine the project's whole thesis.
- Exact CI grep-gate token lists and negative-control self-tests for the new HID/entitlement and notarization-pipeline gates (mirror the existing gate idioms).
- Fastfile lane structure/naming, ASC API-key env-var plumbing (placeholder until enrollment), and the exact HUMAN-UAT runbook format (reuse the `sc2-evidence.md` / `06-HUMAN-UAT.md` precedent).
- The in-app host-harness UI form and the instrumented-log schema for the bidirectional round trip.
- Webgrid BPS harness target/selection model details (acquisition rule, time window, correct/incorrect accounting) consistent with the Neuralink Webgrid definition.

### Folded Todos
None — `todo match-phase 8` returned zero matches.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project spec (source of the locked v0 scope)
- `docs/cortex-spec.md` §5 — System integration: May-2025 BCI HID protocol, Switch Control + Accessibility hook (AccessibilityHID WWDC '25), Synchron entitlement/Info.plist mirror, bidirectional context-sharing closed loop (D-04/D-05)
- `docs/cortex-spec.md` §6 — Build/CI/distribution checklist: `notarytool submit` + `xcrun stapler staple` (no `altool`), `PrivacyInfo.xcprivacy` CA92.1, TestFlight 100/10,000 + 90-day expiry, `fastlane match` + ASC `.p8` JWT, SwiftPM-only (D-01)
- `docs/cortex-spec.md` §7 — Software-timed v0 vs photodiode v1; "Apple's compositor adds 1-3 frames latency that software timestamps cannot see" (the D-07 boundary rationale)
- `docs/cortex-spec.md` §8 — BPS leaderboard: BrainGate 4.16, Indy/Loco 3.7-8.5, Neuralink P1 peak 8.5 verified; "match BrainGate (4.16) on synthetic Indy-spike replay in v0" (D-11/D-12)
- `docs/cortex-spec.md` §9 — macOS gotchas (deprecated entitlements, `_ANEClient`, CocoaPods — feed the rejected-alternatives table, DIST-04)
- `docs/cortex-spec.md` Finding 1 — BCI HID protocol source provenance (Synchron/Apple May 2025)

### Phase requirements & goal-backward targets
- `.planning/REQUIREMENTS.md` SYS-01..06, DIST-01..04, PERF-01..04 — the acceptance bar for this phase
- `.planning/ROADMAP.md` "Phase 8" — the five numbered Success Criteria (goal-backward verification target; SC#5 = BPS + <25ms software-timed budget)
- `.planning/PROJECT.md` Key Decisions table + Out of Scope — locked architectural commitments and the rejected-alternatives content for the README

### Prior-phase context (locked, carry-forward)
- `.planning/phases/01-foundation-2026-toolchain/01-CONTEXT.md` — **D-05/D-06** (bundle IDs), **D-07** (App Group `group.com.donovansantine.cortex.shared`), **D-09** (enrollment deferred to P8), **D-10** (fastlane swap targets), **D-11/D-12** (CI signing posture, ASC key deferred)
- `.planning/phases/02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm/02-CONTEXT.md` — **CF#1** (keychain-access-groups deferred to P8), **D-09** (SMAppService named as the App-Store daemon form, install deferred to P8)
- `.planning/phases/06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid/06-CONTEXT.md` — renderer seam the demo consumes (CursorVelocity fp16, VelocityRing, renderer-owned integrator, present path, `MTL_HUD` scheme env)
- `.planning/phases/07-refit-kalman-closed-loop-recalibration/07-CONTEXT.md` — **D-13** (4.16/8.5 comparison deferred to P8), `CortexReFITBench` deterministic 3-way ablation harness (extend for Webgrid BPS, D-13 here)

### Existing code Phase 8 builds on / swaps
- `fastlane/Fastfile` + `Matchfile` + `Appfile` — P1 placeholders; swap in real lanes + private match remote + identity (D-01)
- `Apps/CortexMac/Cortex.entitlements`, `Apps/CortexiOS/Cortex.entitlements`, `Apps/CortexDaemon/Cortex.entitlements` — HID/keychain-access-groups entitlement surface lands here (D-02/D-04)
- `Apps/CortexMac/Info.plist`, `Apps/CortexiOS/Info.plist` — HID/Accessibility Info.plist keys mirroring Synchron (D-04)
- `project.yml` — `DEVELOPMENT_TEAM: 57YW6M29S7` (free Personal team) across all targets; `CODE_SIGN_STYLE: Automatic`
- `Tools/scripts/hotpath-policy.sh` + `render-policy.sh` + `validate-privacy-manifest.sh` — the CI grep-gate idiom to mirror for the new HID/notarization structural gates (D-06)
- `Packages/CortexReFIT` + `CortexReFITBench` — extend for the Webgrid BPS metric (D-13)
- `Packages/CortexRender` (`WebgridFrameEncoder`, velocity ring, integrator) + `Packages/CortexDecoder` (NDT1 `.mlpackage`, `.cpuAndNeuralEngine` inference path) + `Packages/CortexIPC` — the halves the demo assembles (D-09/D-10)

### External Apple/library docs (planner: pull current versions via Context7 / WebFetch when wiring tasks)
- AccessibilityHID / Switch Control / Accessibility framework HID-provider APIs (WWDC '25)
- `notarytool`, `xcrun stapler staple`, App Store Connect API key (`.p8` JWT)
- `fastlane match` (App Store Connect API key auth), `gym`, `pilot`/`deliver`
- `SMAppService` register/install (macOS 13+ daemon registration)
- `CAMetalDisplayLink` `targetPresentationTimestamp` (the D-07 present timestamp)
- Neuralink Webgrid BPS definition / Bliss-Chapman Webgrid methodology (the D-11 information-rate formula)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **fastlane scaffolding** (`Fastfile`/`Matchfile`/`Appfile`) — P1 placeholders with the exact Phase-8 swap targets documented in `01-04-SUMMARY.md`; D-01 activates them.
- **Entitlements + Info.plist (×3 targets)** — the surface where the HID + keychain-access-groups declarations land (D-02/D-04).
- **CI grep-gate idiom** (`hotpath-policy.sh`, `render-policy.sh`, `validate-privacy-manifest.sh`, no-app-sandbox/no-`_ANEClient` checks) — the established "trap pre-armed, negative-control self-test" pattern to mirror for the new structural gates (D-06).
- **HUMAN-UAT evidence pattern** (`sc2-evidence.md`, `06-HUMAN-UAT.md`, `03-HUMAN-UAT.md`) — the never-auto-approve runbook+evidence form to reuse for the TestFlight submission, iPad-M4 latency, and Switch Control registration gates (D-01/D-06/D-08).
- **`CortexReFITBench`** deterministic 3-way ablation harness — extend to emit Webgrid BPS (D-13).
- **Phase 6 renderer seam + Phase 5 decoder path + Phase 2/3 IPC/ring** — the components the CortexMac demo assembles into the closed loop (D-09/D-10).

### Established Patterns
- **Eligible/measured-but-honestly-reported** (ANE eligibility vs CPU placement; M5-corroborating vs iPad-M4-canonical) — the exact framing reused for the BCI-HID entitlement (declared-but-gated, D-04) and the software-vs-photodiode timing boundary (D-07).
- **Hardware/account-gated canonical claim → never-auto-approved HUMAN-UAT** (D-11/D-12 across P5/6/7) — reused for TestFlight, iPad-M4 latency, on-device HID registration.
- **Compile-time / CI structural guarantee beats runtime assertion** — structural entitlement/Info.plist grep gates (D-06).
- **Free Personal team `57YW6M29S7` signs Mac GUI only** (CLI xcodebuild can't provision it) — the demo runs via Xcode GUI (D-09).

### Integration Points
- The CortexMac app is the assembly point: `CortexIPC` (transport) → `CortexDecoder` (NDT1) → `CortexReFIT` (Kalman) → `CortexRender` (webgrid), driven by the standalone `CortexDaemon` producer replaying synthetic Indy/Loco spikes (D-10).
- The in-app host harness taps the same loop for the bidirectional round-trip log (D-05).
- The notarization/match/TestFlight pipeline wraps the built `.app`/`.ipa` artifacts; the live submission is the gated boundary (D-01).

</code_context>

<specifics>
## Specific Ideas

- **The wire-and-gate doctrine is the spine of this phase:** every account/entitlement/hardware-gated success criterion ships as *complete, structurally-verified code* + a *never-auto-approved HUMAN-UAT checkpoint* for the live/paid step. v0 is fully runnable and credible today; enrollment only flips gates from "ready" to "done."
- **Honesty is the product.** The audience is Bliss Chapman / Nir Even-Chen; the project's thesis is instrumentation honesty ("only people who have actually instrumented glass-to-glass have shipped fast code"). Every claim discloses its gate: software-timed (not photodiode), synthetic-replay (not live-human), ANE-eligible (CPU-scheduled at scale), free-team-signed (not notarized-live), HID-surface-registered (BCI-HID entitlement request-gated).
- **The decoder must be genuinely in the v0 loop** (D-10) — using the Lissajous shortcut would make SYS-06 a hollow claim. The first real synthetic-spike → NDT1 → ReFIT → webgrid assembly is the heart of v0.
- **D-13 (P7) is closed here, correctly:** Webgrid information-rate BPS (`log2(N)×(correct−incorrect)/time`), not the Fitts throughput, is the leaderboard-comparable metric — and it's reported honestly on synthetic replay, not gamed toward 4.16.

</specifics>

<deferred>
## Deferred Ideas

| Idea | Belongs in | Why deferred |
|------|------------|--------------|
| Live Apple submission — real `notarytool submit` + `fastlane match` + TestFlight upload | Gated checkpoint within Phase 8 (flips when enrolled) | Needs paid Apple Developer Program enrollment + ASC `.p8` key (P1 D-09/D-12); pipeline is built now, submission is the HUMAN-UAT gate (D-01) |
| `keychain-access-groups` real cross-process activation | Gated within Phase 8 | Needs paid signing (CF#1, P2); surface wired, activation gated (D-02) |
| SMAppService signed privileged-helper install | Gated within Phase 8 | Needs paid signing for the helper (D-09 P2); register/install scripted, install gated (D-03) |
| iPad Pro M4 canonical software-timed latency capture | Phase 8 HUMAN-UAT (never auto-approve) | Free-team can't provision iPad headless; M5 Pro is corroborating-canonical (D-08) |
| On-device Switch Control HID registration | Phase 8 HUMAN-UAT (never auto-approve) | Requires a provisioned device session; CI verifies the surface structurally (D-06) |
| Real BCI-HID managed entitlement grant | Out of scope (Apple/Synchron-gated) | Partner-gated, not grantable to a solo dev in-sprint; surface mirrored + documented (D-04) |
| v1 photodiode-instrumented glass-to-glass claim, rig, launch video | Phases 9-10 | v0 ships software-timed; the photonic ground-truth delta is the v1 milestone |

### Reviewed Todos (not folded)
None — `todo match-phase 8` returned zero matches.

</deferred>

---

*Phase: 08-apple-bci-hid-integration-distribution-v0-ship*
*Context gathered: 2026-06-23*
