# Phase 8: Apple BCI HID Integration, Distribution & v0 Ship - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 08-CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-23
**Phase:** 08-apple-bci-hid-integration-distribution-v0-ship
**Areas discussed:** Distribution & enrollment; BCI HID entitlement honesty; v0 demo + software-timed claim; Webgrid BPS vs 4.16/8.5

---

## Distribution & enrollment

### Q1 — Apple Developer Program enrollment status
| Option | Description | Selected |
|--------|-------------|----------|
| Wire + gate (not enrolled) | Build the complete notarize/stapler/match/TestFlight pipeline as real code; gate the live Apple submission behind a never-auto-approved HUMAN-UAT checkpoint | ✓ |
| Execute for real (enrolled now) | Run real notarytool + match + TestFlight upload this phase (needs active enrollment + ASC .p8) | |
| Enroll mid-phase | Start wire-and-gate; flip to real submission if enrollment + .p8 land before phase close | |

**User's choice:** Wire + gate (not enrolled) → **D-01**

### Q2 — Cross-process keychain-access-groups (CF#1)
| Option | Description | Selected |
|--------|-------------|----------|
| Keep P2 fallback + gate entitlement | Single-process Keychain + key-over-mach_msg for demo; wire entitlement surface, gate activation on paid signing | ✓ |
| Activate real entitlement | Add team-prefixed entitlement, prove cross-process sharing for real (needs paid team) | |

**User's choice:** Keep P2 fallback + gate entitlement → **D-02**

### Q3 — Production daemon packaging (D-09 SMAppService)
| Option | Description | Selected |
|--------|-------------|----------|
| Keep standalone + script/gate install | Standalone type:tool producer for demo; script SMAppService install, gate signed helper on enrollment | ✓ |
| Wire SMAppService install now | Implement SMAppService register/install + signed helper this phase (needs paid signing) | |

**User's choice:** Keep standalone + script/gate install → **D-03**

---

## BCI HID entitlement honesty

### Q1 — Credible HID landing given the managed entitlement
| Option | Description | Selected |
|--------|-------------|----------|
| Public surface + declared mirror + gate | Build vs public Switch Control/Accessibility surface; mirror Synchron's declared entitlement/Info.plist keys; document BCI-HID managed entitlement as request-gated | ✓ |
| Assume entitlement grant | Implement against the real BCI HID protocol assuming Apple grants the managed entitlement | |
| Accessibility-only, no BCI-HID claim | Integrate purely as Switch Control/Accessibility input; don't declare the BCI-HID surface | |

**User's choice:** Public surface + declared mirror + gate → **D-04**

### Q2 — Bidirectional context-sharing demonstration surface (SYS-03/04)
| Option | Description | Selected |
|--------|-------------|----------|
| In-app host harness + instrumented log | App sends UI state into decode loop, applies returned intent, with an instrumented round-trip log | ✓ |
| Real external host via HID provider API | Separate host app over the actual AccessibilityHID provider IPC (needs granted entitlement) | |
| Synthetic/mocked round-trip | Simulate the host side; log without a real UI consumer | |

**User's choice:** In-app host harness + instrumented log → **D-05**

### Q3 — HID-provider registration verification
| Option | Description | Selected |
|--------|-------------|----------|
| Structural CI gate + Manual-UAT | CI grep-gates entitlement keys + Info.plist surface; on-device registration is never-auto-approved HUMAN-UAT | ✓ |
| Runtime registration assertion | Assert real on-device registration in an automated test (needs entitlement + device) | |

**User's choice:** Structural CI gate + Manual-UAT → **D-06**

---

## v0 demo + software-timed claim

### Q1 — Software-timed glass-to-glass boundary (PERF-04)
| Option | Description | Selected |
|--------|-------------|----------|
| intent_ts → present-callback ts | mach_absolute_time intent-emission → CAMetalDisplayLink present/targetPresentationTimestamp; labeled software-pipeline (excludes compositor, = v1 photodiode delta) | ✓ |
| intent_ts → drawable encoded/committed | Stop at GPU encode/commit (smaller, less defensible as 'glass') | |
| intent_ts → present + estimated compositor offset | Add a documented compositor estimate (risky — guessing the thing the rig measures) | |

**User's choice:** intent_ts → present-callback ts → **D-07**

### Q2 — Canonical measurement device
| Option | Description | Selected |
|--------|-------------|----------|
| M5 Pro corroborating + iPad-M4 deferred | M5 Pro ProMotion corroborating-canonical; iPad-M4 capture is never-auto-approved HUMAN-UAT (D-11/D-12 pattern) | ✓ |
| iPad-M4 canonical now | Require the iPad capture as the canonical v0 number this phase | |
| Mac-only, no iPad gate | Claim only the Mac number; drop the iPad canonical capture | |

**User's choice:** M5 Pro corroborating + iPad-M4 deferred → **D-08**

### Q3 — Runnable v0 demo artifact
| Option | Description | Selected |
|--------|-------------|----------|
| CortexMac full closed-loop GUI | CortexMac runs the full synthetic-spike → IPC → NDT1 → ReFIT → 120Hz webgrid + MTL_HUD, free-team GUI-launchable; iPad same code, gated | ✓ |
| Both Mac + iPad demo | Wire both as first-class demo targets this phase | |
| Headless integration harness only | Prove the pipeline headless; defer the visible app demo | |

**User's choice:** CortexMac full closed-loop GUI → **D-09**

### Q4 — Closed-loop drive (decoder in loop for SYS-06?)
| Option | Description | Selected |
|--------|-------------|----------|
| Synthetic Indy/Loco spikes → NDT1 | Real synthetic spike frames through IPC → NDT1 → ReFIT — decoder + Kalman genuinely in the live loop | ✓ |
| Lissajous velocity (skip decoder) | Reuse the Phase-6 deterministic velocity producer; decoder NOT exercised | |
| Decoder loop + Lissajous fallback toggle | Ship both with a runtime toggle, default to decoder loop | |

**User's choice:** Synthetic Indy/Loco spikes → NDT1 → **D-10**

---

## Webgrid BPS vs 4.16/8.5

### Q1 — Satisfy SC#5 leaderboard comparison (Fitts-TP ≠ BPS)
| Option | Description | Selected |
|--------|-------------|----------|
| Webgrid BPS primary + Fitts cross-check | Implement Neuralink Webgrid BPS = log2(N)×(correct−incorrect)/time on the 30×30 grid (synthetic replay); keep Fitts-TP as secondary cross-check | ✓ |
| Webgrid BPS only | Compute BPS, drop the Fitts-TP from v0 reporting | |
| Annotate Fitts-TP only (no new metric) | Map the existing Fitts-TP against 4.16/8.5 with caveats (the TP≠BPS mismatch D-13 warned about) | |

**User's choice:** Webgrid BPS primary + Fitts cross-check → **D-11**

### Q2 — Framing vs BrainGate 4.16 / P1 8.5
| Option | Description | Selected |
|--------|-------------|----------|
| Report measured + live-vs-synthetic caveat + gap | State the actual synthetic-replay BPS, framed as synthetic (not live-human retrain), with the documented gap to 8.5; no forced "matched 4.16" headline | ✓ |
| Engineer toward ≥4.16 as a pass bar | Tune the harness to clear 4.16 (risk: overfitting/gaming — against the ethos) | |
| Report BPS, defer comparison if not met | Measure/report, only claim the comparison if it lands | |

**User's choice:** Report measured + live-vs-synthetic caveat + gap → **D-12**

### Q3 — BPS measurement harness
| Option | Description | Selected |
|--------|-------------|----------|
| Deterministic headless harness (extend P7 bench) | Extend CortexReFITBench to emit Webgrid BPS; byte-identical, CI-guardable, device-independent (no hardware gate) | ✓ |
| Live demo-app measurement | Measure BPS from the running CortexMac demo loop (timing/nondeterminism) | |

**User's choice:** Deterministic headless harness (extend P7 bench) → **D-13**

---

## Implementer's Discretion

- **README credibility framing (DIST-04)** — user chose to fold it into implementer's discretion under the established honesty ethos rather than discuss it explicitly (architectural-commitments + rejected-alternatives tables + v0 claim wording; disclose every honest gate).
- CI grep-gate token lists / negative-control self-tests for the new HID + notarization gates.
- Fastfile lane structure, ASC API-key env plumbing (placeholder), HUMAN-UAT runbook format.
- In-app host-harness UI form + instrumented-log schema.
- Webgrid BPS harness selection/timing model details.

## Deferred Ideas

- Live Apple submission (notarytool/match/TestFlight) — gated, flips on enrollment + ASC .p8
- keychain-access-groups real activation — gated on paid signing
- SMAppService signed helper install — gated on enrollment
- iPad Pro M4 canonical latency + on-device Switch Control registration — HUMAN-UAT, never auto-approve
- Real BCI-HID managed entitlement grant — Apple/Synchron-gated, out of scope
- v1 photodiode-instrumented glass-to-glass claim, rig, launch video — Phases 9-10
