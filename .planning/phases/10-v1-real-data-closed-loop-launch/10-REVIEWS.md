# Phase 10 - Cross-AI Review

**Reviewed:** 2026-09-05
**Reviewer:** OpenAI Codex CLI 0.153.4, model `gpt-6-astra`, reasoning effort high, read-only sandbox
**Scope reviewed:** `10-RESEARCH.md`, `10-RESEARCH-INPUTS.md`, `10-CONTEXT.md`, `10-VALIDATION.md`,
`ROADMAP.md` (Phase 10), `REQUIREMENTS.md` (RD-07..RD-10). `*-PLAN.md` files were explicitly
out of scope - the planner was mid-run.

## Verdict: NO-GO

Issued against the foundation artifacts, before the 17 plans existed. The items below are the
replan input.

---

## Part 1 - Audit of the research's own six corrections

`10-RESEARCH.md` asserted six "verified corrections" to CONTEXT.md's premises. Independently
re-derived:

| # | Claim | Status | Evidence |
|---|---|---|---|
| 1 | `fit_kalman_gain.py` always defaults | **VERIFIED** | Both branches return `default_noise(seed)` at `:177`, `:189` |
| 2 | No demo IPC; latency bench never ran the model | **VERIFIED** | No `CortexIPC` dep, no GUI consumer; `CortexDemoBench/main.swift:90` omits model URL; `:112-115` computes presentation time |
| 3 | CI never executed | **PARTIAL** -> upgraded to **VERIFIED**, see below | Codex could not reach the GitHub API and correctly refused to certify it |
| 4 | Geometry ceiling is 43/1,025 | **PARTIAL** | Arithmetic reproduced exactly (4.195%); the *framing* is wrong, see D-1 below |
| 5 | BrainGate 4.16 is 9x9 not 6x6 | **VERIFIED** | eLife 18554: T5 9x9 = 4.16 +/- 0.39; 6x6 = T6 2.2 / T5 3.7 / T7 1.4 |
| 6 | The `8.5` figure is unsourced and self-contradicted | **PARTIAL** | Spec contradiction at `:54`/`:172` vs `:313` confirmed; live page rendering not certifiable by Codex |

**Claim 3 resolved by the orchestrator after the audit** (Codex was right to refuse):
`gh api repos/D0NMEGA/Cortex/actions/runs` returns `total_count: 0`, and `gh repo view` returns
`defaultBranchRef: ""` - the remote exists but holds **no commits**. "Never pushed, zero CI runs"
is now established against hosted state, not inferred from a missing local remote-tracking ref.
**New fact neither prior agent surfaced: the repo is `isPrivate: true`.** D-18's push therefore
runs CI for the first time but does **not** make the repository public. Visibility is a separate,
unmade decision.

---

## Part 2 - Defects to fix in the replan

### D-1 BLOCKER: the proposed D-13 `24.7` gate is demonstrably bypassable

`10-RESEARCH.md`'s proposed context-sensitive check was executed against test strings. Result:

```
FAIL  Glass-to-glass latency 24.7 +/- 1.3 ms -- RETIRED SPEC TARGET, never measured (Future work).
FAIL  The 24.7 ms figure is a RETIRED SPEC TARGET; no photodiode rig was ever built.
PASS  We measured 24.7 ms on the iPad Pro M4, beating the retired spec target.
PASS  | latency | 24.7 ms | measured | retired spec target |
PASS  Our achieved latency is 24.7 ms; retired spec target.
```

It **rejects the honest sentences and passes the dishonest ones** - the precise inversion of
ROADMAP SC#4, which is the reason this gate exists. Three root causes:
1. The helper is case-sensitive on lowercase `retired spec target`; the intended passing examples
   are uppercase.
2. The achievement regex only inspects text **after** the number and stops at table pipes.
3. It never verifies that the occurrence sits under a Future-work / retired heading, which is
   D-13's actual requirement.

**Replan requirement:** the gate design must be validated against an adversarial corpus that
includes at minimum the five strings above, with the expected verdict inverted from what the
current design produces. The `--self-test` must contain both directions as named cases.

### D-2 HIGH: control-count arithmetic is wrong (9 -> 12, not 14)

The rewrite removes two existing controls (`photodiode`, flat `24.7`) and adds five. 9 - 2 + 5 =
**12** non-baseline cases, and one of the five additions is a positive control, not a negative one.
`10-VALIDATION.md` asserted `>= 14`. **Fixed in the artifact 2026-09-05**; the plan must inherit 12.

### D-3 HIGH: the required full suite violates D-09

`10-VALIDATION.md`'s full-suite command included `Decoder/tests/test_heldout_cobps.py`, which
loads real sessions (`:98-103`), trains (`:124-126`), and asserts `heldout_co_bps > CO_BPS_MARGIN`
(`:176`). A negative real-data result would redden a required gate - the exact "red build is
pressure to tune" failure D-09 forbids. On an empty dataset it silently falls back to synthetic
training (`:104`), so a green result says nothing about the real replay either.
**Fixed in the artifact 2026-09-05** by deselecting it from the gate; it remains an
evidence-producing run.

Related, and **not yet fixed**: `10-RESEARCH.md:1119` claims the Phase-8 smoke "asserts only that
the bench runs." That is **false** - `CortexDemoBench/main.swift:144,188-197` gates p99 against
25 ms and `ci.yml:428-429` invokes it. Keeping that synthetic gate is fine; inheriting it onto a
real-data measurement is a D-09 violation. The plan must not wire the real-data bench through it.

### D-4 HIGH: the BrainGate comparison is not like-for-like, on three independent grounds

1. **Formula:** eLife 18554 uses `log2(N - 1)`; the repo uses `log2(N)`. Matching the
   `(correct - incorrect)` numerator does not make them the same metric.
2. **Grid:** 4.16 is a 9x9 dense-grid figure (Correction 5), mislabeled 6x6 in ~18 locations.
3. **Task:** `CortexReFITBench/main.swift:283-285` makes incorrect selections **structurally
   zero**, so `Si` is always 0 and the metric cannot express the speed-accuracy tradeoff a human
   point-and-click bitrate measures.

Additionally the live Neuralink page now describes a **three-factor** score (NTPM, grid size, and
number of click types) against the repo's two-factor form.

**Replan requirement:** RD-09 must disclose the non-comparability. Changing `bps-policy.sh`'s
pinned formula is *not* the fix - that would break the Phase-7 byte-identity fixture D-09 protects.
This is a disclosure obligation.

### D-5 HIGH: N=900 headline needs relabeling, not just a companion number

`10-RESEARCH.md:481-491` correctly finds the task presented **64** distinct targets (6.0 bits)
while `WebgridBPS` normalizes by `log2(900) = 9.81`. Open-question 2 was resolved as "headline
N=900 for continuity, state N=64 beside it." Codex's objection stands: the N=900 figure must be
labeled a **counterfactual grid score**, not the information rate of the recorded 64-target task.
Keep the resolution; tighten the label.

### D-6 HIGH: the geometry ceiling is not "the maximum any decoder can achieve"

The 43/1,025 arithmetic reproduces exactly. The *claim* that it is a ceiling for any decoder is
false - it is the hit rate obtained by replaying the recorded cursor through one specific dwell
rule and radius. A decoder producing different trajectories can exceed it. **Replan requirement:**
publish it as "recorded-cursor replay under the stated dwell/radius", never as a theoretical
maximum. It remains genuinely useful as a pre-registered reference point.

### D-7 HIGH: VALIDATION.md maps all five criteria but under-verifies several

| SC | Gap |
|---|---|
| SC#1 | A provenance-header string is not evidence of numerical fitting. No Schur-stability check on the **regenerated** constants - `KalmanConstantsTests` has no eigenvalue test, and `Decoder/tests/test_kalman_gain.py:57-62` checks a representative noise pair, not the shipped output. Also `KalmanConstantsTests.swift:74-76` requires **diagonal R**, while `10-RESEARCH.md:249` proposes a general empirical 2x2 covariance - "existing invariants unchanged" is wrong |
| SC#2 | No frame-cadence assertion, no renderer/HID delivery accounting. Seam B's automated definition stops at decode/window delivery. GUI capture instructions do not name the acceptance observations |
| SC#3 | A four-token sweep cannot establish the universal claim that no synthetic number is presented as real |
| SC#4 | See D-1 |
| SC#5 | Checking ADR headings and the index link does not establish that the required retirement *rationale* is present |

Also: the Seam B smoke exits 0 when the export is absent, and CI never has the export - so it is
**vacuous in CI** unless explicitly wired to the synthetic fixture. VALIDATION requests the fixture
but does not require the smoke to consume it.

### D-8 HIGH: the hit criterion still conflicts with the negative-result policy

RD-08 and ROADMAP SC#2 require a *demonstrated hit*. D-11 explicitly accepts zero hits as a
publishable result. Nothing defines how zero satisfies or amends the requirement. This is an
outcome threshold even when assessed manually. **Resolve the contract before measurement** - do
not redefine success after seeing the number.

Also stale: `ROADMAP.md:204` still says "the 3-way ablation" while D-04 locks a fourth arm. Left
unedited deliberately - amending a success criterion is the user's call, not the orchestrator's.

### D-9 MEDIUM: Willett 2017 is overextended

The paper compares **decoder calibration methods**. It does not predict that this repo's *runtime*
target-directed rotation should show near-zero benefit over unassisted decoding. `IntentRotation.swift:75-85`
explicitly replaces direction with the known target direction, so a shuffled-target control
failing does **not** convert the unshuffled arm into an independent neural-decoding result. Keep
the gain/smoothing confound point, which is supported; drop the stronger inference.

Codex independently confirmed the cross-system causal claim at `docs/cortex-spec.md:46`
(attributing 4.16 -> 8.5 to ReFIT across two different systems) and agrees it belongs in the sweep.

### D-10 HIGH: keeping `8.5` does not supply its provenance

D-17 acknowledges 8.5 lacks primary provenance while requiring it to be "dated and sourced
everywhere". An access date does not authenticate the figure. Codex's position: it may remain as
an explicitly **unsupported historical repo reference**, but not as a "verified" Neuralink
measurement retained to preserve a required gate token.

**User decision 2026-09-05: D-17 stands as written.** Recorded as a dissent, not a change. The
plan should, at minimum, avoid the word "verified" next to 8.5.

---

## Part 3 - The 4.16 mislabel locations (from the Codex sweep)

`README.md:111,123` · `docs/cortex-spec.md:53` · `docs/adr/0002-*.md:81` ·
`Tools/scripts/bps-policy.sh:20` · `WebgridBPS.swift:10,42-45` ·
`CortexReFITBench/main.swift:396,522,565` · `WebgridBPSTests.swift:21-22,98` ·
`.planning/PROJECT.md:107` · `.planning/REQUIREMENTS.md:124` · `.planning/ROADMAP.md:160` ·
`07-CONTEXT.md:181` · `08-CONTEXT.md:39` · `08-RESEARCH.md:139,146` · `08-05-SUMMARY.md:73` ·
`08-SECURITY.md:81` · `08-VERIFICATION.md:221` · `08-bps-evidence.md:16,33,122,126,196,236-237` ·
`webgrid_bps.json:2`

Symbol: `brainGate6x6BPS`. Serialized field: `brain_gate_6x6_bps`. Historical phase artifacts get
supersession banners, never retroactive edits (repo convention).

---

## Part 4 - What Codex could not check

- GitHub Actions history and hosted enforcement (API unreachable from its sandbox) - **since
  resolved by the orchestrator**, see Part 1
- Live rendering of neuralink.com/webgrid (no browser tool available to it) - **since resolved by
  the orchestrator via browser-harness**: the page reads "Our clinical trial participants have
  achieved over 10 BPS"
- Exhaustive proof that no primary source for 8.5 exists (not provable in principle)
- Test suites, clean-checkout runs, the lint count, GUI playback, model-backed latency, hardware
  gates - all require writes, builds or hardware. Codex inspected contracts and ran read-only
  computations; it did not claim any suite passed.

## Part 5 - Orchestrator note on what the planner independently found

The planner ran concurrently and, without seeing this review, independently reached the same
conclusion on the RD-07/D-09 conflict, resolving it structurally (a frozen `phase7BaselineK`
routed through `--smoke` so a real re-fit can never redden the byte-identity fixture). It also
**measured** the lint debt rather than trusting D-18's estimate: **526** SwiftLint violations, not
~535, plus **71 of 101 files** failing `swiftformat --lint`, which D-18 did not mention at all. It
further found that 350 of the 526 are `identifier_name` and that many are `Codable` field names
serving as JSON keys in `refit_bps.json` and `webgrid_bps.json` - renaming them would silently
break two byte-identity gates. That finding is corroborating, not superseded, and should survive
the replan.
