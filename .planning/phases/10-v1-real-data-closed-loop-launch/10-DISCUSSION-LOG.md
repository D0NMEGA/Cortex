# Phase 10: v1 Real-Data Closed Loop & Launch - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 10-CONTEXT.md - this log preserves the alternatives considered.

**Date:** 2026-09-05
**Phase:** 10-v1-real-data-closed-loop-launch
**Mode:** discuss (interactive), advisor mode off (no USER-PROFILE.md)
**Areas discussed:** Real-session replay contract, Spike path into Swift, Ablation and BPS
reporting bar, README republish and v1 boundary

---

## Assumptions surfaced before the gray-area menu

Five areas were presented for correction: technical approach, implementation order, scope
boundaries, risk areas, dependencies. The user replied "Good" with no corrections, so all five
stand as stated and shaped the gray areas below. The assumption flagged as most uncertain was the
source of the ReFIT intent-rotation target on an open-loop recording; it became the first
question of the first area.

---

## Real-session replay contract

### Q1. Where should ReFIT's intent-rotation target come from on real data?

| Option | Description | Selected |
|--------|-------------|----------|
| Real `target_pos` | `data.py` reads the session's target array; rotation points at the target the animal actually reached for | yes |
| Drop the rotation arm | Report raw vs Kalman-only; declare rotation unmeasurable on an open-loop recording | |
| Both, clearly labeled | Real-target arm as the claim, synthetic-target arm as a bridge to Phase 7 | |

**User's choice:** Real `target_pos`.
**Notes:** Recommended option. Costs a third behavior array in the loader contract, extending
Phase 9's D-05.

### Q2. What is the 30x30 webgrid on the real-data path?

| Option | Description | Selected |
|--------|-------------|----------|
| Re-grid the real workspace | Map `finger_pos` workspace onto the grid, snap real `target_pos` to cells | yes |
| Keep the synthetic target sequence | Real velocity, synthetic targets; comparable but close to a coin flip | |
| Real grid, synthetic kept as regression | Real grid is the claim, synthetic retained untouched as fixture | |

**User's choice:** Re-grid the real workspace.
**Notes:** The third option's regression-fixture provision was folded into the decision anyway,
since `bps-policy.sh` and `check_refit_uplift.py` need their synthetic fixture untouched.

### Q3. How should the phase name what the loop actually is?

| Option | Description | Selected |
|--------|-------------|----------|
| Software path closed, subject open-loop | Disclosure carried in evidence, README, and metrics JSON | yes |
| Rename it replay throughout | Drop "closed loop" from the phase vocabulary entirely | |

**User's choice:** Software path closed, subject open-loop.

### Q4. Should the ablation include a shuffled-target control arm?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add the control | Rotation re-run against a shuffled or time-reversed target track | yes |
| No, the three arms are enough | State the confound in prose rather than measuring it | |

**User's choice:** Yes, add the control.

---

## Spike path into Swift

### Q1. How deep into the stack should the real spike stream go?

| Option | Description | Selected |
|--------|-------------|----------|
| Full chain via the daemon | Daemon reads exported bins; IPC, decoder, ReFIT, renderer, HID unchanged | yes |
| In-process pipeline only | Swap the source stage inside ClosedLoopPipeline, skip daemon and IPC | |
| In-process numbers, full chain demo | Two paths, two things to label | |

**User's choice:** Full chain via the daemon.
**Notes:** Chosen because it keeps RD-08's re-derived glass-to-glass p99 like-for-like with the
Phase-8 number, which included the IPC leg.

### Q2. What does the Python side export?

| Option | Description | Selected |
|--------|-------------|----------|
| Bins, velocity, targets in binary plus JSON sidecar | Sidecar records session id, sha256, bin count, lag, grid mapping | yes |
| Raw spike timestamps, binned in Swift | Duplicates tested `ndt1` binning; drift risk | |
| You decide | Leave format entirely to the planner | |

**User's choice:** Bins, velocity, targets in binary plus JSON sidecar.

### Q3. Does the exported real data enter git?

| Option | Description | Selected |
|--------|-------------|----------|
| Gitignored, materialized by script | Keeps the D-21 tier split; no redistribution question | yes |
| Gitignored export plus a tiny committed fixture | CI coverage of the real path; needs a CC-BY note | |
| Commit the full session excerpt | Strongest reproducibility; megabytes and a licensing footnote | |

**User's choice:** Gitignored, materialized by script.
**Notes:** Accepts that CI cannot exercise the real path, which the existing tier split already
assumes.

### Q4. Which session gets replayed?

| Option | Description | Selected |
|--------|-------------|----------|
| `indy_20160630_01` | The NLB'21 mc_rtt benchmark session, named in Phase 9 D-06 | yes |
| All four, reported per session | Most complete; four times the replay compute | |
| The best held-out R2 session | Selection on the outcome | |

**User's choice:** `indy_20160630_01`.

---

## Ablation and BPS reporting bar

### Q1. What happens to `check_refit_uplift.py`'s refit >= raw invariant on real data?

| Option | Description | Selected |
|--------|-------------|----------|
| Guard stays synthetic, real gets no pass bar | Real artifact gated on provenance and schema only | yes |
| Re-point the guard at real data | Converts a negative finding into a red build | |
| Guard both, real one advisory | Non-blocking real check alongside the blocking synthetic one | |

**User's choice:** Guard stays synthetic, real gets no pass bar.
**Notes:** The structural form of Phase 9's D-25 and Phase 8's D-12.

### Q2. Which rate metric leads on the real-data ablation?

| Option | Description | Selected |
|--------|-------------|----------|
| Both, with the comparability disclosure | Fitts TP for arm continuity, Webgrid BPS for the 4.16 and 8.5 gap | yes |
| Webgrid BPS only | Maps to the references RD-07 names; loses Phase-7 continuity | |
| Fitts throughput only | Matches the Phase-7 arms; the required gap is then cross-metric | |

**User's choice:** Both, with the comparability disclosure.

### Q3. If the real replay registers zero webgrid hits, what does the phase publish?

| Option | Description | Selected |
|--------|-------------|----------|
| Publish zero plus a decomposition | Report the zero, decompose why, add a hit-independent proxy | yes |
| Relax dwell and timeout until hits occur, disclosed | Tuning an acceptance parameter until the result appears | |
| Treat zero hits as a blocker | Contradicts D-25; unbounded decoder work inside a launch phase | |

**User's choice:** Publish zero plus a decomposition.

### Q4. What happens to the README's 1.953 BPS headline?

| Option | Description | Selected |
|--------|-------------|----------|
| Real number leads, 1.953 stays labeled synthetic | Preserves the visible before-and-after | yes |
| Retire 1.953 from the README | Cleaner headline; loses the honesty narrative | |

**User's choice:** Real number leads, 1.953 stays labeled synthetic.

---

## README republish and v1 boundary

### Q1. How should the rewritten gate treat the 24.7 figure?

| Option | Description | Selected |
|--------|-------------|----------|
| Context-sensitive, retired-target only | Permitted under a Future work heading; forbidden as measured or achieved | yes |
| Forbid 24.7 in the README entirely | Trivial to gate; README cannot state what it is retiring | |
| Require an adjacent retired marker | Weaker: distant tokens still pass | |

**User's choice:** Context-sensitive, retired-target only.
**Notes:** This is the literal reading of RD-10. The self-test must prove both directions bite.

### Q2. What real-data disclosure joins the required set?

| Option | Description | Selected |
|--------|-------------|----------|
| Provenance triple | Session id, real checkpoint sha256, open-loop-replay disclosure phrase | yes |
| A single real-data phrase | Simpler; a README could satisfy it while dropping the specifics | |
| You decide | Leave the token list to the planner | |

**User's choice:** Provenance triple.

### Q3. Can v1 be declared with the device gates still deferred?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, deferred and disclosed | Listed in the honest-gates table as v1's boundary, never as done | yes |
| No, v1 waits on the iPad-M4 gates | Blocks the milestone on absent hardware | |
| Close what an M2 can close, relabel the rest | Risks an M2 number drifting into a canonical M4 slot | |

**User's choice:** Yes, deferred and disclosed.

### Q4. Are a demo capture and the first PR inside this phase?

| Option | Description | Selected |
|--------|-------------|----------|
| Demo capture yes, ship no | Recorded M5 Pro run evidences RD-08; PR arms SwiftLint strict separately | yes |
| Both in scope | Adds a large unrelated lint cleanup to a credibility phase | |
| Neither, evidence only | RD-08's "demonstrated" then rests on numbers alone | |

**User's choice:** Demo capture yes, ship no.

---

## Implementer's Discretion

Recorded in 10-CONTEXT.md. Nine items, covering the export layout and sidecar schema, the daemon's
export-path selection and clean-clone behavior, replay pacing, whether AES-GCM stays on the real
path, the regular expressions implementing the context-sensitive 24.7 check and the wording of the
provenance disclosure phrases, the evidence artifact set, the retirement ADR's number and scope,
plan and wave decomposition, and whether the control arm shuffles, time-reverses, or both.

## Deferred Ideas

Five, recorded in 10-CONTEXT.md: NDT2 session conditioning, a live-human two-stage ReFIT retrain,
the photodiode rig itself (already preserved in ROADMAP Future work), the repo-wide SwiftLint
strict sweep and first pull request, and closing the deferred iPad Pro M4 device gates.

No scope creep was raised during the discussion; every option presented stayed inside RD-07..RD-10.
