# Phase 7: ReFIT-Kalman Closed-Loop Recalibration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-22
**Phase:** 07-refit-kalman-closed-loop-recalibration
**Mode:** discuss (interactive)
**Areas discussed:** Kalman core & substrate, Intent-rotation semantics, BPS measurement harness, Synthetic intent source, Structure & provenance

---

## Kalman core & substrate (REFIT-01)

### Q: 6-DOF Kalman state vector?
| Option | Description | Selected |
|--------|-------------|----------|
| `[px,py,vx,vy,ax,ay]` | Position + velocity + acceleration (constant-acceleration model); measurement = decoded (vx,vy) | ✓ |
| `[px,py,vx,vy,bx,by]` | Position + velocity + per-axis bias/offset (Gilja "constant term", doubled) | |
| Gilja `[px,py,vx,vy,1]` +pad | 5-state velocity-KF faithful to Gilja 2012, padded/relabeled to 6 | |

**User's choice:** `[px,py,vx,vy,ax,ay]` — simplest defensible 6-state; position present for the rotation step; output to seam stays a 2-vector velocity.

### Q: Kalman gain computation per tick?
| Option | Description | Selected |
|--------|-------------|----------|
| Steady-state constant gain | Precompute converged K offline; hot-path op = fixed simd mat-vecs | ✓ |
| Full covariance propagation | Propagate P + recompute K each tick (textbook) | |

**User's choice:** Steady-state constant gain — standard real-time iBCI trick, matches SC#3 + hot-path discipline.

### Q: Implementation substrate / language?
| Option | Description | Selected |
|--------|-------------|----------|
| Swift + simd | Fixed-size simd matrices, Foundation-free, hot-path-safe | ✓ |
| Swift + Accelerate | BLAS/LAPACK — overkill for a 6-state filter | |
| Rust + cbindgen producer | loom-checkable, but spec/REFIT-01 say Swift | |

**User's choice:** Swift + simd — matches REFIT-01 "Swift side" + spec §2.4 "pure linear algebra."

---

## Intent-rotation semantics (REFIT-02)

### Q: Which ReFIT formulation?
| Option | Description | Selected |
|--------|-------------|----------|
| Online per-tick rotation | Rotate decoded velocity toward target each 20ms; inference-time, no retrain | ✓ |
| Two-stage train-time refit | Open-loop block → rotate intended velocities → re-fit KF offline → run | |
| Both (refit + online assist) | Offline refit AND online rotation | |

**User's choice:** Online per-tick rotation — literal SC#1 reading; honestly a "ReFIT-inspired online assist," not Gilja's full retrain.

### Q: Where does the rotation act?
| Option | Description | Selected |
|--------|-------------|----------|
| Rotate the measurement | Rotate z toward target BEFORE the KF measurement update | ✓ |
| Rotate the output | Run KF on raw z, then rotate posterior output velocity | |

**User's choice:** Rotate the measurement — the actual ReFIT assumption applied at the observation, not a post-hoc nudge.

### Q: Rotation strength / gating policy?
| Option | Description | Selected |
|--------|-------------|----------|
| Full align, speed preserved, gated | Full direction onto cursor→target, keep speed; only when target active + outside acquisition radius | ✓ |
| Angle-limited / partial blend | Capped angle or fractional blend toward target | |

**User's choice:** Full align, speed preserved, gated — canonical Gilja behavior with sane gating so it doesn't snap on-target.

---

## BPS measurement harness (REFIT-03 / SC#2 / PERF-03)

### Q: Headless sim or renderer-in-the-loop?
| Option | Description | Selected |
|--------|-------------|----------|
| Headless deterministic sim | Pure-Swift bench: replay → filter → CursorIntegrator → webgrid acquisition → Fitts TP; no Metal | ✓ |
| Renderer-in-the-loop | Drive real Metal renderer + display link | |

**User's choice:** Headless deterministic sim — CI-stable, reproducible; live 120Hz demo is Phase 8 SYS-06.

### Q: Target-selection criterion?
| Option | Description | Selected |
|--------|-------------|----------|
| Dwell-to-select | Cursor stays in target cell for a dwell window + per-trial timeout | ✓ |
| Cell-crossing / first-entry | Acquired on first entry into the correct cell | |

**User's choice:** Dwell-to-select — classic BrainGate/Webgrid convention, deterministic.

### Q: Fitts throughput fidelity to Soukoreff & MacKenzie 2004?
| Option | Description | Selected |
|--------|-------------|----------|
| Full S&M 2004 (effective width) | TP = IDe/MT, IDe = log2(De/We+1), We = 4.133·SD, mean-of-means | ✓ |
| Nominal-width Fitts | ID = log2(D/W+1), nominal width, no scatter correction | |

**User's choice:** Full S&M 2004 (effective width) — exactly the cited method; the We correction makes the number defensible.

### Q: Uplift artifact + regression guard?
| Option | Description | Selected |
|--------|-------------|----------|
| Committed artifact + deterministic CI guard | 07-bps-evidence.md + JSON; CI asserts ReFIT_BPS ≥ raw_BPS on fixed seed | ✓ |
| Committed artifact only | Evidence doc + JSON, no CI threshold | |

**User's choice:** Committed artifact + deterministic CI guard — mirrors the co-bps>null gate; deterministic so non-flaky.

---

## Synthetic intent source (REFIT-03 / PERF-01)

### Q: How is the closed-loop task defined / decoder driven to targets?
| Option | Description | Selected |
|--------|-------------|----------|
| Indy's own reach targets | Use the dataset's actual reach targets; replay held-out neural data; webgrid is the display | ✓ |
| Synthetic forward-model intent→spikes | Generative model maps webgrid target → spikes → decoder | |

**User's choice:** Indy's own reach targets — most honest, no fabricated neural signal; matches REFIT-03 + the instrument-it-honestly ethos.

### Q: Depth of the raw-vs-filter comparison?
| Option | Description | Selected |
|--------|-------------|----------|
| 3-way ablation | raw NDT1 / Kalman-only / Kalman+rotation on identical seed | ✓ |
| 2-way (raw vs full ReFIT) | Just raw vs full ReFIT-Kalman delta | |

**User's choice:** 3-way ablation — isolates rotation vs smoothing; cheap given determinism; reviewer-grade transparency.

### Q: Frame absolute BPS vs leaderboard, or stay relative?
| Option | Description | Selected |
|--------|-------------|----------|
| Absolute + uplift, defer formal claim | List absolute BPS + delta; note formal PERF-01/02 claim is Phase 8 SC#5 | ✓ |
| Relative uplift only | Strictly raw-vs-ReFIT delta, no leaderboard mention | |

**User's choice:** Absolute + uplift, defer formal claim — captures the numbers without overclaiming on synthetic replay.

---

## Structure & provenance

### Q: Where does the Kalman code live?
| Option | Description | Selected |
|--------|-------------|----------|
| New CortexReFIT package | Focused Swift package, per-subsystem split, owns its hot-path gate | ✓ |
| Fold into CortexDecoder | Kalman next to NeuralDecoder | |
| Into CortexRender | Producer-side, next to the seam | |

**User's choice:** New CortexReFIT package — high cohesion; planner sorts shared-seam-type placement (CursorVelocity may move to CortexCore).

### Q: Where are the steady-state gain + Q/R determined?
| Option | Description | Selected |
|--------|-------------|----------|
| Fit offline in Decoder/, emit constants | Fit Q/R from Indy residuals, solve Riccati, emit committed Swift constants | ✓ |
| Solve Riccati in Swift at init | Hand-set Q/R, compute gain at filter init | |
| Hand-tuned gain constants | Heuristic Q/R, hardcoded gain | |

**User's choice:** Fit offline in Decoder/, emit constants — data-grounded, reproducible, hot path loads constants only.

## Implementer's Discretion

- Dwell-time, acquisition-radius, per-trial-timeout values for the webgrid task.
- Precise simd matrix/vector layout and predict+update inlining.
- Trial count `n` and the short-budget CI-smoke variant of the harness.
- Riccati-solve location in `Decoder/` and the emitted-constants file format.
- Filter position-state synchronization to the clamped cursor position each tick.

## Deferred Ideas

- Classic two-stage ReFIT retraining (more faithful to Gilja, heavier, couples into decoder training).
- Synthetic intent→spikes forward model (free-form webgrid, but BPS would partly measure the model).
- Rust + cbindgen producer (loom-checkable; spec says Swift for now).
- Live on-device 120 Hz closed-loop demo (SYS-06) and formal BrainGate/Neuralink leaderboard claim (PERF-01/02) — Phase 8.
- Angle-limited / partial-blend rotation (conservative knob, unused now).
