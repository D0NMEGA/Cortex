# ADR 0002 -- v0 Ship, BCI HID Integration, and the Wire-and-Gate Doctrine

**Status:** Accepted
**Date:** 2026-06-23
**Deciders:** @donovansantine
**Superseded in part by:** [ADR-0003](0003-photodiode-retirement-and-real-data-v1.md), 2026-08-28

> Two premises below are retired. First, the BPS figures this ADR records -- ReFIT 1.953 Webgrid BPS
> and the 0.374 Fitts throughput -- were measured on a synthetic seed-locked Poisson replay, which
> this ADR states plainly and which remains true of them; Phases 9 and 10 replaced them with results
> measured on real Indy M1 spikes, so they are superseded as the project's reported numbers rather
> than corrected as records. Second, the rejected-alternatives table below calls the
> photodiode-instrumented number "the v1 claim"; on 2026-08-28 that path was retired to Future work
> (LAT-01 through LAT-08) and v1 was re-pointed at real-neural-data decoding.
>
> The original text is left verbatim: an ADR records what was decided and on what basis at the time,
> so a superseded premise gets a forward pointer, never an edit. Per `docs/adr/README.md`
> "Numbering", a superseded ADR states the supersession in its Status area. The supersession is
> PARTIAL: the wire-and-gate doctrine, the HID surface decisions and the distribution pipeline below
> are unaffected and remain Accepted.

## Context

Phase 8 is the v0 convergence milestone: it wires all seven prior phases into one running
closed-loop artifact (synthetic Indy/Loco spike → `kqueue`/shm IPC → NDT1 CoreML decoder →
ReFIT-Kalman → 120Hz 30×30 webgrid), registers Cortex against Apple's May 2025 BCI HID
surface, builds the full `notarytool` + `fastlane match` → TestFlight distribution pipeline,
and publishes the software-timed glass-to-glass claim plus the credibility-grade README
(DIST-04).

Two hard realities shape every Phase-8 decision:

1. **Solo dev, free Personal team, no paid Apple Developer Program enrollment.** Per ADR-0001
   section 5, enrollment was deferred to Phase 8. The free team signs the Mac GUI but cannot
   provision an iPad headless, cannot back a managed `com.apple.developer.hid.virtual.device`
   entitlement, and cannot notarize or upload to TestFlight.
2. **The audience is Bliss Chapman / Nir Even-Chen, and the product is instrumentation
   honesty.** The project's thesis — "only people who have actually instrumented glass-to-glass
   have shipped fast code" — means an over-claimed number is worse than a gated one. Presenting
   the software-timed latency as the final glass-to-glass figure, the synthetic BPS as a
   live-human result, or a declared entitlement as a granted one would each forge the
   credibility the project exists to establish.

This ADR records how v0 ships **honestly** under those constraints. It follows the ADR-0001
format precedent (sequential numbering, no decimals; supersession via a new ADR).

## Decision

Phase 8 commits to the following five decisions. Each lists the `08-CONTEXT.md` decision IDs
(D-XX) it implements and references the phase plans that realize it.

### 1. The wire-and-gate doctrine — build the whole pipeline, gate the live/paid step (D-01)

Every account-, entitlement-, or hardware-gated success criterion ships as **complete,
structurally-verified code** plus a **never-auto-approved HUMAN-UAT checkpoint** for the live
step. The complete `notarytool submit` + `xcrun stapler staple` + `fastlane match(type: "appstore")`
+ `upload_to_testflight` pipeline is built as real Fastfile lanes + `notarize.sh` this phase
(honoring the ADR-0001 / Plan 01-04 swap targets: Matchfile `file:///` → private GitHub remote
+ `MATCH_PASSWORD` from ENV, uncommented Appfile identity, real lanes). The **live submission is
gated** behind a never-auto-approved checkpoint because paid enrollment is not active.

This is the keystone decision: v0 ships the closed-loop demo + the software-timed claim + the
README **now**; enrollment only flips DIST-01/02/03 from "ready" to "done". Plans 08-04 (lanes +
`notarize.sh`), 08-04 gates (`notarize-policy.sh`, `match-policy.sh`).

### 2. The BCI HID surface is declared and gated, never claimed as granted (D-04)

The mirror-able public surface is **Apple's own BCI HID report descriptor**, not a
"Synchron-published entitlement list". Phase 8 **ports the five Apple BCI HID report structs +
the descriptor byte array into Swift** (buildable now, free team, unit-tested encode/decode) and
**declares-and-gates the `com.apple.developer.hid.virtual.device` entitlement** (declared in all
three targets, inert under free signing). The live `IOHIDUserDevice`/`HIDVirtualDevice`
instantiation as a Switch Control provider sits behind a `#if CORTEX_HID_LIVE` compile gate so
the free-team demo binary stays AMFI-safe, and on-device registration is a never-auto-approved
HUMAN-UAT checkpoint. SYS-01/05 are satisfied as "registered against the available HID surface,
entitlement declared-and-gated" — the same eligible-vs-placed honesty framing as the ANE work.
Plans 08-01 (port + `hid-surface-policy.sh`), 08-02 (Scan-Info round trip, SYS-03/04).

### 3. Software-timed glass-to-glass is the v0 claim; photodiode is the v1 target (D-07)

The v0 software-timed glass-to-glass number ends the measurement at the `CAMetalDisplayLink`
**`targetPresentationTimestamp`** (the on-glass present time — NOT `targetTimestamp`, the render
deadline), measured from the decoder's intent-emission `mach_absolute_time()`. It is labeled
**verbatim**: "software-timed pipeline latency — excludes the compositor's 1-3 frames of scanout,
which is exactly the delta the v1 photodiode rig (Phases 9-10) quantifies." This label is
embedded in `GlassToGlassTimer.methodologyLabel` so it travels with every reported number and is
gate-checkable. The canonical 24.7 ± 1.3 ms photodiode-instrumented number is the **v1 target**,
not claimed as measured today. The canonical device is M5 Pro ProMotion (corroborating); the
iPad-Pro-M4 capture is HUMAN-UAT (D-08). No estimated-compositor-offset fudge. Plan 08-03
(`CortexDemo`, `GlassToGlassTimer`, `CortexDemoBench`; p99 ≈ 8.3 ms M5 corroborating).

### 4. The leaderboard metric is the Webgrid information-rate BPS, not the Fitts throughput (D-11)

The standard Neuralink / Bliss-Chapman Webgrid information-rate bitrate
`B = max(0, log2(N) * (Sc - Si) / t)` (N = 900 for the 30×30 grid incl. the delete/cancel key,
`log2(N)`-normalized so it is comparable to BrainGate's T5 dense 9x9 4.16) is the leaderboard-comparable
metric. The mandatory `max(0, ...)` clamp is unit-tested to bite. The Phase-7 S&M-2004 Fitts
throughput is **retained as a secondary cross-check** (PERF-03), emitted side by side. This
closes the Phase-7 D-13 deferral, which explicitly postponed the 4.16/8.5 comparison precisely
because the Fitts throughput is not the Webgrid bitrate. Measured in the deterministic headless
`CortexReFITBench` (byte-identical, CI-guarded, device-independent — no hardware gate). Plan 08-05
(`WebgridBPS.swift`, `bps-policy.sh`, `webgrid_bps.json`).

### 5. The BPS is reported honestly on synthetic replay, never tuned toward a pass bar (D-12)

The measured number is recorded as **whatever it honestly is** — ReFIT **1.953 Webgrid BPS** on
synthetic Indy replay — with the explicit gap to the peak (6.55 BPS short of 8.5; below the 4.16
reference) stated as the point, not hidden. It is framed as a **synthetic seed-locked replay**
(NOT a live-human two-stage ReFIT retrain) and was **NOT engineered toward ≥4.16** as a pass bar,
which would game the metric. `Si` is structurally 0 (single-target dwell-to-select harness),
disclosed as an `incorrect_model` so the BPS reads as an honest upper-bound, not a silent
"measured zero errors". Plan 08-05 (`08-bps-evidence.md`).

## Consequences

### Positive

- **v0 is fully runnable and credible today** without paid enrollment: the CortexMac GUI runs
  the real closed loop, the headless benches reproduce the latency + BPS numbers, and every CI
  structural gate is green.
- **The README is a credibility artifact, not marketing.** Every number carries its device and
  its gate; the dual latency claim and the six honest-gate disclosures are exactly the
  instrumentation honesty the audience values.
- **Enrollment is a clean flip, not a rebuild.** The notarization/match/TestFlight lanes, the
  `keychain-access-groups` and `virtual.device` entitlement surfaces, and the SMAppService
  register/install path are all wired; paid enrollment activates them.
- **Regressions fail loudly.** `readme-policy.sh`, `hid-surface-policy.sh`, `notarize-policy.sh`,
  `match-policy.sh`, and `bps-policy.sh` each ship a negative-control `--self-test` that runs in
  CI, so a silently-weakened gate stops biting and trips the self-test.

### Negative

- **Three load-bearing claims remain gated** until enrollment + hardware: the live TestFlight
  submission, the iPad-Pro-M4 canonical latency capture, and on-device Switch Control HID
  registration. These are HUMAN-UAT checkpoints, never auto-approved — fabricating them would
  forge the credibility numbers.
- **The headline BPS (1.953) is below the 4.16 reference.** This is honest and expected on
  synthetic replay through a noisy synthetic decoder; the live-human retrain is the path to 8.5,
  out of scope for v0.
- **Runtime ANE placement is CPU at this scale.** The 1.29M-param model is ANE-eligible but
  CPU-scheduled — the documented CoreML scale trap, reported rather than hidden.

### Cross-phase commitments propagated

- **Honesty is the product.** Every future claim (the v1 photodiode capture, any live-human BPS)
  discloses its gate. The v1 milestone's whole purpose is to convert the software-timed number to
  the photodiode-instrumented one and quantify the disclosed compositor delta.
- **Wire-and-gate, not stub-and-claim.** Gated capabilities ship as complete code + a HUMAN-UAT
  checkpoint, never as an over-claimed result.
- **Structural CI gates beat prose.** A disclosure that matters is asserted by a grep gate with a
  biting self-test, extending the ADR-0001 "compile-time guarantees beat runtime ones" discipline
  to the documentation surface.

## Alternatives considered (rejected)

| Alternative | Why rejected |
|-------------|--------------|
| **Pay for Apple Developer Program enrollment mid-sprint to ship a "fully live" v0** | Adds cost + ~24-48h review delay and does not change what v0 demonstrates; the wire-and-gate doctrine ships a credible v0 now and flips the gate when enrollment lands (D-01). |
| **Report the software-timed latency as the glass-to-glass claim** | Over-claim: software timestamps cannot see the compositor's 1-3 frames of scanout. The photodiode-instrumented number is the v1 claim; conflating them forges the project's defining number (D-07). |
| **Add an estimated compositor offset to the software-timed number** | A fudge that fabricates precision the instrument does not have. The honest path states the software number with its exclusion label and lets the v1 photodiode rig measure the delta (D-07). |
| **Tune the BPS harness toward ≥4.16 to claim "matched BrainGate"** | Games the metric and violates the instrumentation-honesty ethos. The number is reported as 1.953 with the 6.55 gap to 8.5 stated plainly (D-12). |
| **Use the S&M-2004 Fitts throughput as the leaderboard number** | The Fitts throughput (0.374) is a different metric from the Webgrid bitrate; comparing it to 4.16/8.5 would be a category error. The Webgrid information-rate BPS is the leaderboard metric, Fitts the cross-check (D-11, closes P7 D-13). |
| **Claim the BCI HID entitlement as integrated / granted** | The `com.apple.developer.hid.virtual.device` entitlement is Apple-managed / partner-gated and not grantable to a solo dev in-sprint. The public report descriptor + structs are ported and the entitlement is declared-and-gated; over-claiming a grant is forbidden (D-04). |
| **Instantiate `IOHIDUserDevice` in the shipping demo binary** | Creating the virtual device needs the managed entitlement (paid provisioning); an entitled binary under free signing is AMFI-SIGKILLed. The live path sits behind a `#if CORTEX_HID_LIVE` compile gate; the demo binary links no live HID symbol (D-04). |
| **Drive the v0 demo with the Phase-6 Lissajous velocity shortcut** | Would make SYS-06 a hollow claim — the decoder would not be in the loop. The v0 loop runs the real synthetic-spike → NDT1 → ReFIT → webgrid assembly (D-10). |

## References

- `docs/adr/0001-foundation-and-2026-toolchain.md` (the format precedent; section 5 deferred
  enrollment to Phase 8)
- `docs/cortex-spec.md` section 5 (BCI HID protocol), section 6 (build/CI/distribution checklist),
  section 7 (software-timed v0 vs photodiode v1), section 8 (BPS leaderboard), section 11 (rejected
  alternatives → DIST-04)
- `.planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/08-CONTEXT.md` D-01 through
  D-13 (decisions implemented by this ADR)
- `.planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/08-RESEARCH.md` (the
  primary-source refinements: Apple BCI HID report descriptor, `targetPresentationTimestamp`, the
  `max(0, ...)` Webgrid formula)
- `.planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/08-bps-evidence.md` +
  `webgrid_bps.json` (the honest 1.953 BPS evidence)
- Plan summaries 08-01 (HID surface), 08-02 (Scan-Info round trip), 08-03 (closed-loop demo +
  software-timed glass-to-glass), 08-04 (distribution pipeline), 08-05 (Webgrid BPS)
- Apple — BCI HID reference; `com.apple.developer.hid.virtual.device` entitlement;
  `CAMetalDisplayLink.Update.targetPresentationTimestamp`; `SMAppService` (08-RESEARCH Sources)

## Amendment (2026-09-07, Phase 10 / RD-09)

Two factual corrections applied to this ADR. The decisions it records are unchanged.

**1. BrainGate reference condition (Task 2, Plan 10-11).** The cited figure 4.16 BPS was labeled
as a "6x6" result throughout this document and its source files. Verified against Pandarinath et
al. 2017 (eLife 18554) 2026-09-07: 4.16 +/- 0.39 bps is the participant **T5 on the DENSE 9x9
grid**, not a 6x6 condition. The same paper's T5 6x6 figure is 3.7 +/- 0.4 bps. Inline references
corrected to "T5 dense 9x9". The `brainGate6x6BPS` Swift constant was renamed `brainGateDenseGridBPS`;
`brainGate6x6T5BPS = 3.7` was added. The `brain_gate_6x6_bps` artifact key was renamed
`brain_gate_dense_9x9_bps`; `brain_gate_6x6_t5_bps: 3.7` was added. No measured values changed.

**2. GlassToGlassTimer.methodologyLabel (Task 1, Plan 10-11).** The verbatim label quoted in
section 3 of this ADR was the correct label at the time of writing. Plan 10-11 (commit cfab16d)
subsequently changed the label: the trailing clause "which is exactly the delta the v1 photodiode
rig (Phases 9-10) quantifies" was replaced with "measuring that delta needs a photodiode rig, which
is retired to Future work (LAT-01..LAT-08) and was never built". The em dash was changed to an ASCII
hyphen. The historical quote in section 3 is preserved as written; this amendment records the change.
