# ADR 0003 -- Retire the photodiode latency path; re-point v1 at real-data decoding

**Status:** Accepted
**Date:** 2026-09-05
**Deciders:** @d0nmega

## Context

Through Phase 8 the v1 milestone was a photodiode-instrumented latency measurement. Three facts,
each with its source, made that the wrong target for v1. They are the reasons for the decision
below, not background to it.

**1. The number was always a target, not a result.** The spec's canonical line was
"Glass-to-glass latency 24.7 +/- 1.3 ms (p50, sigma=0.8 ms, n=10k, photodiode-instrumented)", and
it is a retired spec target, never a measurement. Nothing in the repo ever measured it, because the
instrument that would have measured it was never built. `.planning/ROADMAP.md` carries this as a
standing honesty constraint in the "Future work (retired from v1)" section: "24.7 ms was always a
spec target, never a measurement. Nothing in v1 may present it as achieved." `.planning/REQUIREMENTS.md`
repeats it on the LAT block. This ADR does not soften that; it records why the path was retired and
what structurally enforces the constraint now.

**2. The rig is hardware-gated.** The measurement needs a BPW34 photodiode, an OPA381
transimpedance amplifier and a Saleae Logic Pro 8, roughly a $110 bill of materials excluding the
analyzer, aimed at the iPad Pro M4 pixel where the cursor lands, with the acquisition daemon
emitting a GPIO pulse at the intent-emission timestamp captured on the same timeline at 100 MS/s or
better. None of that hardware exists, and neither does the iPad Pro M4 the rig has to point at. That
device gap is not hypothetical: its absence had already forced three Phase-8 HUMAN-UAT deferrals on
2026-06-23 (canonical iPad-M4 latency, live TestFlight, on-device HID registration) and a fourth on
2026-09-02 in Phase 9 (canonical iPad-M4 decoder p99). A requirement gated on instrumentation that
does not exist cannot be scheduled honestly, and pretending otherwise is how a target quietly turns
into a claim.

**3. The photodiode gap was not the project's largest credibility hole.** The larger hole was that
every decoder number the repo published had been produced on a synthetic Poisson fallback.
`04-training-evidence.md` records it in those words: "No real `.mat` was present under
`Decoder/data/`". So co-bps 0.3804, the ReFIT 0.374-versus-0.161 Fitts ablation and the 1.953
Webgrid BPS were all synthetic-data numbers wearing real-sounding labels. A photodiode measures the
scanout delta of a pipeline; it says nothing about whether the decoder in that pipeline has ever
seen a spike from an animal. Buying a latency instrument while every decoder number was synthetic
would have been optimising the wrong claim, and saying so plainly is the decision's actual reason.

## Decision

Retire the photodiode latency path and re-point v1 at real-neural-data decoding.

1. **Move LAT-01, LAT-02, LAT-03, LAT-04, LAT-05, LAT-06, LAT-07 and LAT-08 to the ROADMAP's
   "Future work (retired from v1)" section, preserved verbatim and not deleted.** All eight
   identifiers are named here so a reader of this ADR alone can confirm nothing was dropped: the BOM
   order (LAT-01), the breadboard and TIA stage (LAT-02), the GPIO intent pulse (LAT-03), the Saleae
   dual-edge capture (LAT-04), the 10,000-trial capture script (LAT-05), the p50/sigma/n statistical
   reduction (LAT-06), the final defensible claim (LAT-07) and the launch video (LAT-08). They are
   deferred work, not abandoned work, and the ROADMAP section says so.

2. **Re-point the v1 milestone at real-neural-data decoding (RD-01 through RD-10).** v1 is now the
   O'Doherty/Makin Indy M1 dataset (Zenodo 3854034, checksum-pinned sessions) decoded end to end
   through the CoreML, ReFIT-Kalman, 120 Hz renderer and BCI HID path, with the result reported
   against the session it came from.

3. **Make the retired figure structurally uncitable as an achieved result.** Rewrite
   `Tools/scripts/readme-policy.sh` rather than delete it (RD-10). The flat `photodiode` and `24.7`
   required tokens leave the required-present set, and the figure becomes context-sensitive: it may
   appear only on a line that also carries a retirement marker, only under a Future-work or retired
   heading, and never framed as measured, achieved or instrumented. The gate's `--self-test` pins
   eight adversarial sentences with their verdicts fixed in advance, in both directions, and CI runs
   the self-test beside the gate, so a future weakening of the rules reddens the build instead of
   silently re-opening the hole.

## Consequences

### Positive

- Every published decoder number is now derived from real primate M1 spikes rather than a synthetic
  Poisson fallback. The largest credibility hole is closed, and the before-and-after synthetic
  figures are retained beside the real ones so the change is legible rather than quietly erased.
- The retired claim cannot silently return. The check that forbids it ships with a self-test that
  proves both directions bite: a retired-context occurrence passes and an achieved-context
  occurrence fails.
- The retired work is preserved. LAT-01 through LAT-08 remain the right way to earn a true
  glass-to-glass number, and a future v2 can pick them up unchanged.

### Negative

- **The project has no photon-level latency measurement.** The compositor's scanout delta remains
  unquantified, so the software-timed number is an explicit **lower bound** on true glass-to-glass
  latency and is labeled as such everywhere it appears. The verbatim methodology label travels with
  the number in `GlassToGlassTimer.methodologyLabel` so it cannot be dropped in transit.
- v1 ships with six device gates deferred (`10-HUMAN-UAT.md`): canonical iPad-M4 software-timed
  latency, live TestFlight submission, on-device HID registration, canonical iPad-M4 decoder p99,
  canonical iPad-M4 Seam A p99 on the real-data path, and the canonical iPad-M4 120 Hz webgrid
  demonstration. None is auto-approved and none is presented as done.
- The real-data result is a **single session**, `indy_20160630_01`, replayed open loop. It is one
  recorded session under one acceptance rule, not a population result.
- The encoder does not transfer across sessions. Phase 9's four leave-one-session-out folds were all
  negative against the held-out session's own mean, mean -0.3498, range -0.7805 to -0.1238. No
  cross-session claim is made or supported.

## Alternatives considered (rejected)

| Alternative | Why rejected |
|-------------|--------------|
| **Build the photodiode rig anyway and keep v1 as planned** | Gated on hardware the project does not have: the ~$110 BOM and, more importantly, the unprovisioned iPad Pro M4 that had already deferred four HUMAN-UAT gates. It would also have measured the wrong thing, because it does not touch the synthetic-data hole described in Context fact 3. |
| **Delete LAT-01 through LAT-08 outright** | The work is still the right way to earn a true glass-to-glass number. Deleting it would erase a correct plan rather than defer it, and it would make the retirement read as abandonment to a future contributor. They are preserved verbatim in the ROADMAP's Future work section instead. |
| **Keep claiming 24.7 ms as the v1 target with no structural guard** | A target printed next to measured numbers reads as a measurement, regardless of the surrounding prose. Documentation discipline is not a control. RD-10 makes the achieved framing a build failure, which is a control. |
| **Delete `readme-policy.sh`'s handling of the figure entirely, or ban the number outright** | RD-10 says rewrite, not delete. A flat ban would stop the README stating the target it is retiring, and that disclosure is itself the honest thing to publish. The gate now permits the figure in a retirement context and forbids it in an achievement context. |
| **A single pairing rule on the number** | Rejected with executed evidence, not on judgment. An external cross-AI review ran that one-and-a-half-rule design against test strings on 2026-09-05 (`10-REVIEWS.md` D-1, a BLOCKER) and it produced the exact inversion of the requirement: it rejected the two honest sentences and passed three dishonest ones, transcribed below. One rule is not enough. The gate now runs three independently-controlled rules and pins eight adversarial strings. |

The transcript that refuted the single-rule design. These are adversarial test strings quoted as
evidence, not claims about this project, and each one is now a named `--self-test` case with the
opposite verdict:

```
FAIL  Glass-to-glass latency 24.7 +/- 1.3 ms -- RETIRED SPEC TARGET, never measured (Future work).
FAIL  The 24.7 ms figure is a RETIRED SPEC TARGET; no photodiode rig was ever built.
PASS  We measured 24.7 ms on the iPad Pro M4, beating the retired spec target.
PASS  | latency | 24.7 ms | measured | retired spec target |
PASS  Our achieved latency is 24.7 ms; retired spec target.
```

Three root causes, each closed by its own rule and its own control: the marker comparison was
case-sensitive, so uppercase honest text failed rule A; the achievement scan looked only at text
after the number and stopped at a table pipe, so a verb before the number or in the next cell
escaped rule B; and no draft ever checked that the figure sits under a Future-work or retired
heading, which is the requirement's actual wording and is now rule C.

## References

- `docs/adr/0001-foundation-and-2026-toolchain.md` (the format precedent; its Context section still
  frames the photodiode figure as the defining project claim, which this ADR supersedes)
- `docs/adr/0002-v0-ship-and-bci-hid-integration.md` (the wire-and-gate doctrine this retirement
  applies to a hardware-gated requirement)
- `.planning/ROADMAP.md` "Future work (retired from v1)" (LAT-01 through LAT-08, preserved verbatim,
  and the standing honesty constraint)
- `.planning/REQUIREMENTS.md` "Latency Measurement Rig (LAT) -- RETIRED to Future work 2026-08-28"
- `.planning/PROJECT.md` (the 2026-08-28 re-point and its stated reason)
- `.planning/phases/04-ndt1-training-on-indy-loco-synthetic-replay/04-training-evidence.md` (the
  synthetic-Poisson-fallback record: "No real `.mat` was present under `Decoder/data/`")
- `.planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real-evidence.md` and
  `10-replay-evidence.md` (what replaced the retired claim)
- `.planning/phases/10-v1-real-data-closed-loop-launch/10-REVIEWS.md` D-1 (the executed refutation of
  the single-pairing-rule design)
- `.planning/phases/10-v1-real-data-closed-loop-launch/10-HUMAN-UAT.md` (the six deferred device
  gates)
- `Tools/scripts/readme-policy.sh` (the rewritten gate and its 12 controls plus the eight-case
  adversarial corpus)
