# Phase 10 - Main-thread research inputs

**Gathered:** 2026-09-05
**Method:** main-thread pass (multi-source scrapers + PubMed E-utilities + Parallel web search).
Recorded here because browser/MCP-backed research cannot run inside a Donny subagent; the
phase researcher folds these findings in rather than re-deriving them.

**Status of these findings:** external-source claims with URLs/DOIs captured. Grade B (secondary
sources) except where a primary DOI is given. The researcher and planner must treat the two
"action required" items below as findings to act on, not as settled repo facts.

---

## Finding 1 (ACTION REQUIRED, RD-07 / RD-09): the `8.5` Neuralink reference is stale

The repo pins **Neuralink P1 (Noland Arbaugh) verified peak = 8.5 BPS**, sourced as "PRIME study
blog, May 2024" (`docs/cortex-spec.md:54`, `:172`; `README.md:124`). It is load-bearing: RD-07
requires "the honest remaining gap to ... Neuralink P1's 8.5 BPS", `readme-policy.sh:148` requires
the literal token `8.5`, and `WebgridBPSTests.swift` and ADR-0002 repeat it.

Public sources disagree with 8.5 as a current figure:

| Figure | Context | Source |
|---|---|---|
| 8 BPS | Neuralink's own May 2024 post, first clinical trial participant | https://x.com/neuralink/status/1790454869381231020 |
| ~8 BPS | May 2024 blog graph of Noland's max daily performance | Neuralink PRIME blog, via ElonX |
| 4.61 BPS | Noland's first record, March 2024 all-hands | ElonX (Bliss Chapman presentation) |
| 9.51 BPS | Day 133 post-surgery, ~15% of electrodes active | ElonX secondary source only - **see correction below** |
| **"over 10 BPS"** | **What neuralink.com/webgrid states today, verified live 2026-09-05** | https://neuralink.com/webgrid |
| 17.1 BPS | Best in-house score, 35x35 grid, held by Bliss Chapman | ElonX |

Secondary summary: https://www.elonx.net/how-does-neuralink-measure-the-performance-of-its-interface

> **CORRECTION (2026-09-05, after the phase researcher's independent check).** An earlier draft of
> this file stated that neuralink.com/webgrid says 9.51 BPS. It does not. That figure came from a
> cached search index and the ElonX secondary source. Fetched live via browser-harness on
> 2026-09-05, the page reads verbatim: *"Our clinical trial participants have achieved over 10 BPS
> controlling a computer with their brain."* Plural participants, no exact figure, no named
> individual. **Do not re-point the repo's reference at 9.51** - it is not sourceable to Neuralink.

**Second live-page finding, RD-09-relevant.** The same page now defines the score as derived from
"net correct targets selected per minute (NTPM), grid size, **and the number of click types**" -
a three-factor formula, and its default grid selector reads 35x35. The repo pins the two-factor
form `max(0, log2(N)*(Sc-Si)/t)` in `bps-policy.sh` and the README. Comparing a two-factor BPS
against a current Neuralink figure computed with a click-type term is not like-for-like. This is
the same category of defect RD-09 exists to sweep, and it is independent of which reference figure
is chosen.

**Why this matters for this phase specifically.** Phase 10 is the credibility artifact for review by
Bliss Chapman and Nir Even-Chen. Chapman is the person who presented Noland's records and who holds
the 17.1 BPS in-house score - the one reviewer most certain to notice a stale or unsourced Neuralink
figure. A number the repo cannot source is the same class of defect as a synthetic number presented
as real, which is the entire point of RD-09.

**This is a planner decision, not a discretionary detail.** Options, in preference order:
1. Keep `8.5` but make its as-of date and source explicit everywhere it appears, and state the
   current public wording ("over 10 BPS", as of 2026-09-05) beside it. Cheapest, and
   `readme-policy.sh`'s `8.5` token survives. Note the phase researcher found `cortex-spec.md`
   self-contradicts here - `:54` and `:172` say 8.5 verified, `:313` says 8 verified, same source.
2. Re-point the reference to the sourceable May-2024 figure of 8 BPS with the Neuralink post as the
   citation, and cite "over 10 BPS" as the current state. Requires touching the policy gate's
   required token, ADR-0002, `WebgridBPSTests.swift`, and the spec.
3. Report the gap to a sourced range with both endpoints dated.

Option 2 is the only one that leaves every published figure traceable to a primary Neuralink
source. **No option should adopt 9.51** (see correction above).

Whichever is chosen, the phase must not leave an unsourced bare `8.5` standing, and the choice
belongs in the RD-09 sweep, not left to an executor.

## Finding 2 (ACTION REQUIRED, RD-07 / D-04): gain and smoothing confound the ablation

According to PubMed, Willett et al. 2017, "A Comparison of Intention Estimation Methods for Decoder
Calibration in Intracortical Brain-Computer Interfaces," *IEEE Trans Biomed Eng* 65(9):2066-2078
([DOI](https://doi.org/10.1109/TBME.2017.2783358), PMID 29989927, PMC6043406). Authors include
Willett, Pandarinath, Henderson, Shenoy, Jarosiewicz, Hochberg - i.e. the BrainGate2 group whose
4.16 figure this repo benchmarks against.

Findings that bear directly on D-04 and the RD-07 ablation, from the abstract:

- Using BrainGate2 pilot clinical trial data, they compared intention-estimation methods including
  **ReFIT**, an optimal feedback control model, a piecewise-linear feedback control model, and
  simpler heuristics, against a steady-state velocity Kalman filter.
- **Dimensionality-reduction properties were largely unaffected** by which intention estimator was
  used: decoded velocity vectors differed by <5% in angular error and in speed-vs-target-distance.
- **Smoothing and output gain were greatly affected: >50% difference in average values.**
- Their stated conclusion: once gain and smoothing differences are accounted for, current intention
  estimation methods yield **nearly equivalent decoders**, and a position error vector
  (target position minus cursor position) performs comparably to more elaborate models. They
  explicitly warn that "simple differences in gain and smoothing properties have a large effect on
  online performance and **can confound decoder comparisons**."

**Consequences for this phase:**

- D-04's shuffled/time-reversed-target arm is necessary but **not sufficient**. A raw-vs-ReFIT BPS
  delta on real data can be produced by a gain or smoothing difference alone, with no intent
  information involved. The ablation needs gain and smoothing either held fixed across arms or
  reported per arm, otherwise the uplift number is not attributable and the D-04 control cannot do
  the job the CONTEXT.md assigns it.
- It is prior-art support for D-01: a position-error vector toward the real `target_pos` is the
  literature-standard intent estimate, and it performs comparably to more elaborate models. D-01's
  choice is the conservative, cited one.
- It supplies the honest framing if the real-data uplift comes out near zero: near-equivalence
  across intention estimators is the published expectation from the BrainGate2 group, not a defect
  in this implementation. That directly serves the roadmap's "if ReFIT's uplift does not survive
  contact with real spikes, that is the finding."

## Finding 3 (context, RD-09): a causal claim in the spec spans two different systems

`docs/cortex-spec.md:46` states that ReFIT "is what gets BrainGate from 4.16 -> 8.5 BPS in humans",
and `.planning/PROJECT.md:171` and `ROADMAP.md:139` repeat the 4.16 -> 8.5 framing. The 4.16 figure
is BrainGate (Pandarinath et al. 2017, eLife 18554, https://elifesciences.org/articles/18554); the
8.5 figure is Neuralink's N1 in a different participant, with different electrode counts, a
different array, and a different decoder generation. Attributing the difference between them to
ReFIT is a cross-system causal claim the cited sources do not support.

RD-09 sweeps "every synthetic-derived number presented as a real-data result." This is an adjacent
defect in the same family - an unsupported causal claim joining two independently sourced numbers -
and it sits in the spec, the roadmap, and PROJECT.md. Worth folding into the same sweep; flagged
here rather than silently fixed because it changes the project's stated rationale for Phase 7.

## Finding 4 (background): offline-vs-closed-loop is a known, citable gap

The open-loop-replay disclosure D-03 mandates has established literature backing, useful for the
D-11 decomposition when hits are few or zero. Candidate sources surfaced but **not yet verified**
against their primary text - the researcher should confirm before any is cited in a repo artifact:

- "Intention Estimation in Brain Machine Interfaces" - https://pmc.ncbi.nlm.nih.gov/articles/PMC4105020/
- "A recurrent neural network for closed-loop intracortical brain-machine interface decoders" -
  https://pmc.ncbi.nlm.nih.gov/articles/PMC3638090/
- "Principled BCI Decoder Design and Parameter Selection Using a Feedback Control Model" -
  https://www.nature.com/articles/s41598-019-44166-7
- "Neuroprosthetic Decoder Training as Imitation Learning" -
  https://journals.plos.org/ploscompbiol/article?id=10.1371%2Fjournal.pcbi.1004948

The relevant well-established point is that offline decode accuracy is a poor predictor of
closed-loop control quality, because closed-loop control lets the subject correct errors that an
open-loop replay cannot. That asymmetry is the honest explanation for a low real-data BPS in an
open-loop replay, and it is the substance D-11 needs.

## Benchmark provenance confirmed

- **BrainGate 4.16 BPS**: Pandarinath et al. 2017, "High performance communication by people with
  paralysis using an intracortical brain-computer interface," eLife -
  https://elifesciences.org/articles/18554. ~~Consistent with `README.md:123`.~~ **NOT consistent -
  corrected 2026-09-05.** The paper reports 4.16 +/- 0.39 bps for T5 on the **dense 9x9 grid**; the
  6x6 figures are T6 2.2, T5 3.7, T7 1.4. `README.md:123` and ~17 other locations label it 6x6,
  including the Swift symbol `brainGate6x6BPS` and the serialized field `brain_gate_6x6_bps`.

- ~~**Webgrid BPS formula**: `BPS = log2(grid_size) * (net correct targets) / time`, matching the
  `max(0, log2(N)*(Sc-Si)/t)` form already pinned in `bps-policy.sh`. Neuralink's public
  description agrees.~~
  **WRONG ON BOTH HALVES - corrected 2026-09-05 after the Codex audit. This entry contradicted the
  three-factor finding recorded earlier in this same file; that earlier finding is the correct one.**
  1. **Against eLife:** the paper's achieved bitrate uses `log2(N - 1)`, not `log2(N)`. Matching the
     `(correct - incorrect)` numerator does not make the formulas identical.
  2. **Against Neuralink:** the live page describes a **three-factor** score - NTPM, grid size, and
     the number of click types - not the two-factor form pinned in `bps-policy.sh`.
  3. **Against the repo's own harness:** `CortexReFITBench/main.swift:283-285` makes incorrect
     selections structurally zero, so `Si` is always 0 and the metric cannot express the
     accuracy-speed tradeoff a human point-and-click bitrate measures.

  Consequence: the repo's BPS is **not like-for-like with either reference**, independent of which
  reference figure is chosen. RD-09 must disclose this rather than present the numbers as
  comparable. This is a disclosure obligation, not necessarily a formula change - changing
  `bps-policy.sh`'s pinned formula would break the Phase-7 byte-identity fixture (D-09).

## Sources not reachable this pass

Reddit (no OAuth credential configured; fail-soft by design) and X were not scraped. europepmc
timed out at 20s; arXiv, OpenAlex, and Semantic Scholar returned nothing for these queries, which
is expected - this is clinical neuroscience literature indexed in PubMed, not preprint-server
material. PubMed was queried directly instead and is the stronger source here.

---

*Attribution: article metadata in Findings 2 and 4 retrieved from PubMed.*
