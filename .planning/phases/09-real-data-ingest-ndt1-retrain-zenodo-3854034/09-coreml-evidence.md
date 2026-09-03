# Phase 9 RD-05 / RD-06 evidence: the CoreML numbers, re-derived on the real-data checkpoints

**Date:** 2026-09-02
**Result:** every CoreML-side number in this repository has been re-measured on the real-data
checkpoints, and one of them did not survive the move. The 4-bit package is 3.4134x smaller and
the reconstruction model barely notices the quantization (Poisson-NLL delta 0.020352), but the
**shipped with-velocity model's held-out velocity R2 falls from +0.423870 to -1.786971 under the
same 4-bit palettization**. Separately, the real-data graph schedules **239** ops, not the 226
Phase 5 recorded, all of them ANE-eligible with zero CPU-only. Decoder p99 is 0.1411 ms on this
Mac with the ops measured as CPU-placed, which makes it corroborating rather than canonical.

RD-05 and RD-06 forbid inheriting a number from the synthetic run. Nothing here is inherited. The
Phase-4 and Phase-5 figures appear only as explicitly labeled baselines, so that the comparison is
visible rather than the inheritance being invisible.

---

## Summary of what changed against the synthetic run

| Quantity | Phase 4 / 5 (synthetic, randomly initialized) | Phase 9 (real data) | Reproduced? |
|---|---|---|---|
| Size ratio, fp16 over 4-bit | 3.471x | **3.4134x** | yes, to 1.7% |
| Poisson-NLL delta, reconstruction model | 0.009114 | **0.020352** | no, and it was not expected to |
| Held-out velocity R2, fp16 package | never measured on real kinematics | **+0.423870** | n/a |
| Held-out velocity R2, 4-bit package | never measured on real kinematics | **-1.786971** | n/a |
| Schedulable ops, ANE eligibility scan | 226, all eligible, 0 CPU-only | **239, all eligible, 0 CPU-only** | no |
| Decoder p99, this Mac, CPU-placed | 0.139333 ms | **0.141083 ms** | yes |

Two of these were predicted to reproduce and did. The size ratio should reproduce because the
architecture, the parameter count and which tensors clear the threshold are unchanged, and it does.
The loss delta should NOT reproduce, because k-means centroids are fit to the actual weight values,
and it does not. The two that were expected to reproduce and did not are the op count and the
velocity R2, and both are findings rather than noise.

---

## The control that makes every difference above attributable

The obvious objection to a table of "Phase 4 said X, Phase 9 says Y" is that something in the
toolchain, the config or this plan's own code changed and the weights are innocent. That objection
was tested rather than argued away. The two gitignored checkpoints were moved aside and the whole
pipeline re-run against the resulting random initialization:

| Quantity | Phase 4 / 5, synthetic | This plan, checkpoints hidden | This plan, real data |
|---|---|---|---|
| Size ratio | 3.471x | **3.471x** | 3.4134x |
| Poisson-NLL delta | 0.009114 | **0.009179** | 0.020352 |
| Schedulable ops | 226 | **226** | 239 |
| Provenance label recorded | n/a | `random init (no checkpoint at ...)` | `real-data checkpoint ...` |

With no checkpoints present this plan's code reproduces the Phase-4 size ratio to four significant
figures, the Phase-4 NLL delta to within 0.7%, and the Phase-5 op count exactly. So the conversion
config did not drift, the `tmp_path` compile fix did not perturb the scan, and adding scikit-learn
changed nothing for tensors that never took that branch. **Every difference reported in this
document is attributable to the weights.**

The same run confirms two operational properties Plan 09-09's CI job depends on: the five slow
tests pass on a checkout with no checkpoints, and `rederive_coreml.py` exits 1 rather than quietly
measuring random weights.

---

## Environment

| Field | Value |
|---|---|
| Machine | Apple M5 Pro (`arm64`) |
| OS | `macOS-26.5-arm64-arm-64bit` (macOS 26 Tahoe, build 25F71) |
| Python | 3.12.13 (uv-managed) |
| coremltools | **9.0** (pinned; a project convention, not a coincidence) |
| torch | 2.12.1 |
| numpy | 2.4.6 |
| scikit-learn | 1.9.0 (newly required; see "The scikit-learn requirement" below) |
| Toolchain (Swift leg) | Xcode 26.3 / Swift 6.2.4 (`swiftlang-6.2.4.1.4`, `clang-1700.6.4.2`) |
| Compute units (scan and bench) | `CPU_AND_NE` / `.cpuAndNeuralEngine`, the DEC-07 production set, not `.all` |

coremltools 9.0 logs "Torch version 2.12.1 has not been tested with coremltools" on every import.
Phase 5 shipped through this identical pairing and so does this plan; conversion, palettization and
prediction all succeeded. The advisory is informational. If `ct.convert` ever does regress, the
remedy is to pin torch, **not** to bump coremltools: 9.0 is a project convention (P9, T-09-08-08).

A second warning appears now that scikit-learn is installed: "scikit-learn version 1.9.0 is not
supported ... Disabling scikit-learn conversion API." That refers to `coremltools.converters.sklearn`,
which converts scikit-learn *models* into Core ML and which this project does not use. The
palettizer's own `from sklearn.cluster import KMeans` is unaffected, as the successful palettization
below demonstrates.

---

## Provenance

Every number below was measured with the real-data weights loaded, and the load returns a label
rather than a boolean so that the artifact records which weights produced it.

| Checkpoint | sha256 | Role |
|---|---|---|
| `Decoder/checkpoints/ndt1_real_pooled.pt` | `f95b257bf2479b49102a2d8afee3c46d9008c51ba754d42a60a26762b7d3af8e` | the reconstruction encoder (Plan 09-06) |
| `Decoder/checkpoints/ndt1_real_with_velocity.pt` | `9d542cb51d4af4811f324fbc6bda0b503da7b15aafc98b5e1340e1a7f49cce65` | the shipped model (Plan 09-07) |

The labels the slow tests emitted into their gitignored JSON records:

```
sc4_size.json    provenance = real-data checkpoint ndt1_real_pooled.pt sha256=f95b257bf247
sc4_delta.json   provenance = real-data checkpoint ndt1_real_pooled.pt sha256=f95b257bf247
runtime_plan.json provenance = real-data checkpoint ndt1_real_with_velocity.pt sha256=9d542cb51d4a
```

`load_real_weights_if_present` returns `"random init (no checkpoint at <path>)"` when the
gitignored checkpoints are absent, and that string deliberately does not contain the substring
`real-data`, because the callers gate on exactly that substring. `rederive_coreml.py` exits nonzero
rather than measure random weights.

**The apparatus was validated before the finding was read.** Scoring the fp16 package over the same
56,943 held-out rows returns pooled R2 **0.423870** (vx 0.344584, vy 0.531901) against Plan 09-07's
PyTorch float32 figure of 0.4238 (vx 0.3430, vy 0.5338). Agreement to four decimal places across a
different framework, a different precision and an independent reimplementation of the window
geometry, lag and null is what licenses reading the 4-bit number below as a result rather than as a
bug.

---

## Palettization (RD-05, D-16)

Both models converted with `ct.convert(convert_to="mlprogram", compute_precision=FLOAT16,
minimum_deployment_target=iOS18)` and palettized with `OpPalettizerConfig(mode="kmeans", nbits=4)`
at coremltools 9.0 defaults (`granularity=per_tensor`, `weight_threshold=2048`,
`num_kmeans_workers=1`).

| | Reconstruction model `NDT1ANE` | Shipped model `NDT1ANEWithVelocity` |
|---|---|---|
| fp16 package | 2,704,783 B | 2,708,540 B |
| 4-bit package | 792,409 B | 796,165 B |
| **Size ratio** | **3.4134x** | **3.4020x** |
| Model-appropriate delta | Poisson NLL **0.020352** | held-out R2 **-2.210841** |
| fp16 metric | NLL 0.836898 | R2 **+0.423870** |
| 4-bit metric | NLL 0.816546 | R2 **-1.786971** |

Phase-4 baseline, **synthetic**, measured on a randomly-initialized `NDT1ANE`: size ratio
**3.471x**, Poisson-NLL delta **0.009114** (`04-palettization-evidence.md`). Labeled synthetic here
and not carried forward into any Phase-9 claim.

The size ratio reproduces to within 1.7%, and the residual is explained rather than shrugged at:
the trained model palettizes **39** weight tensors where the untrained one palettizes 38, and its
fp16 package is 26,745 bytes larger, both for the reason given under "The scikit-learn requirement".
The NLL delta roughly doubled, which is the expected direction: k-means centroids are fit to the
actual weight values, so a delta measured on random weights predicts nothing about a delta measured
on trained ones. That is precisely why RD-05 forbids inheriting it.

### The velocity R2 did not survive 4-bit palettization

This is the plan's most consequential output and it is negative.

| Model | Held-out R2 over 56,943 rows, against the pooled TRAIN-split mean-velocity null |
|---|---|
| fp16 package | **+0.423870** (vx +0.344584, vy +0.531901) |
| 4-bit package | **-1.786971** (vx -0.460860, vy -3.593836) |
| Delta | **-2.210841** |

A negative R2 means the model predicts held-out velocity worse than a constant would. The 4-bit
shipped artifact does not decode cursor velocity.

The mechanism was measured, not inferred. On 384 held-out windows, the 4-bit encoder's last-bin
output differs from the float32 reference by mean absolute 0.19728 against the fp16 package's
0.04254, and critically that difference is a **systematic per-channel mean shift** of up to 1.21573
against a residual scatter of only 0.07793. Per-tensor 4-bit k-means gives one 16-entry lookup
table for an entire weight tensor, so its error biases rather than cancels across the sum. The
reconstruction objective barely registers this. The linear readout does: it was fit by ridge
regression on the un-palettized encoder's output, so a per-channel shift in that input maps
straight into a constant velocity error of **[-11.24, +12.92] cm/s** against a signal whose
per-axis standard deviation is only [2.87, 2.02] cm/s.

**Diagnostic, deliberately excluded from the number above.** To separate "quantization offsets the
velocity" from "quantization destroys it", the constant offset between the 4-bit and fp16
predictions was estimated on **train rows only** (4,096 per session, taken from the end of the train
block, reading no held-out bin) and subtracted from the held-out 4-bit predictions. That recovers
part of the loss and leaves R2 at **-0.770991**, still worse than the constant null. So the damage
is not a removable offset and re-centering is not a fix. This is reported as a diagnostic and is
not offered as a remedy; no readout was refit, because refitting after seeing a bad number is
tuning, and both models are settled for this plan.

What this does NOT say: it does not say 4-bit palettization is unusable for this architecture, and
it does not say the fp16 artifact is the answer. It says that the specific pairing shipped today, a
ridge readout fit on float32 encoder output and then deployed on a 4-bit encoder, does not work,
and that the choice of deployment artifact is now an open question rather than a settled one. The
untested candidates are refitting the readout on the palettized encoder's output and excluding the
encoder from palettization; both are Phase-10 work and neither was run here.

---

## The velocity head is not palettized

`weight_threshold=2048` is a coremltools `OpPalettizerConfig` default: any weight tensor with fewer
than 2,048 elements is skipped entirely. The velocity readout is a 1x1 `Conv2d(96 -> 2)`, that is
**2 x 96 = 192** elements, so it is **never quantized**. Measured census of the shipped model:

| Quantity | Value |
|---|---|
| Parameter tensors in the model | 103 |
| Tensors clearing the 2,048-element threshold | 39 |
| Tensors skipped, under threshold | 64 |
| `constexpr_lut_to_dense` ops in the saved 4-bit package | 39 |
| Smallest palettized tensor | 4,096 elements (the positional encoding) |
| Largest skipped tensor | 560 elements |
| Velocity readout weight | **192 elements, skipped** |

The census is taken from two independent directions that agree: the torch parameter list says 39
tensors are large enough to be eligible, and the saved package's MIL program contains exactly 39
lookup-table ops. There is a clean gap between 560 and 4,096, so nothing sits near the threshold
where a small change would move it.

The consequence, stated plainly because it is the difference between an honest delta and a
misleading one: **the shipped model's R2 delta is entirely encoder-attributable.** The readout that
maps encoder output to velocity is bit-identical between the fp16 and 4-bit packages. All 2.210841
of the R2 loss comes from quantizing the encoder underneath an unquantized head. `rederive_coreml.py`
raises rather than proceeds if the readout ever grows past the threshold, so this claim cannot
silently go stale.

---

## Determinism

Two questions, both answered by measurement.

**Palettization.** `palettize_4bit` was run twice on the same fp16 package. The two 4-bit packages
are byte-identical in size and produce **identical** Poisson-NLL deltas (0.020352 both times), so
the committed delta is reproducible rather than assumed to be. This matters more than it did in
Phase 4: coremltools uses its bundled `kmeans1d` only for tensors with at least 10,000 elements,
and this model's 4,096-element positional encoding therefore goes through scikit-learn's `KMeans`
instead, which is seeded (`random_state=0`, `n_init=1`) but is a different algorithm.

**The ANE scan, which had to be fixed before it could be trusted.** The Phase-9 deferred item
recorded `test_ane_compute_plan.py` as flaky: two consecutive runs each failed a different test and
a third passed 3/3 with no code change. The cause was found and is worse than flakiness.
`compile_model` moves its freshly compiled `.mlmodelc` to the destination with `shutil.move`, which
nests the new directory **inside** an existing destination rather than replacing it, and then
returns the unchanged destination anyway. `MLComputePlan.load_from_path` consequently reads the
first compile ever written to that path. Because the build-directory names derive from the stable
test name, the shared `Decoder/checkpoints/` destinations had not changed since **2026-06-21**, and
217 unread nested compiles totalling 285 MB had accumulated across four directories.

Measured directly rather than argued: compiling the encoder-only model (224 schedulable ops) and
then the with-velocity model (226) to one shared destination returns 224 both times.

The fix is to build every package and compile under the test's own `tmp_path`, so the destination
cannot pre-exist; `rederive_coreml.py` additionally removes any existing destination and then
asserts that no nested compile appeared. After the fix, five consecutive runs on random weights and
three on the real weights each returned a byte-identical verdict, including the full per-op-type
histogram. The op tally below is therefore published as measured on a gate that returns the same
answer on the same inputs.

---

## ANE eligibility (RD-06a)

Scanned on the compiled 4-bit palettized real-data `NDT1ANEWithVelocity`, scoped to `CPU_AND_NE`.

| Quantity | Value |
|---|---|
| Schedulable ops (`n_schedulable`) | **239** |
| ANE-eligible (`neuralEngine` in `supported_compute_devices`) | **239 / 239** |
| `all_eligible` | **true** |
| CPU-only ops (the regression) | **0** |
| Mac `preferred` tally | `{CPU: 239}`, informational |

Phase-5 baseline: 226/226 eligible, 0 CPU-only, on a randomly-initialized graph.

**The op count changed and that is a finding, not noise.** D-17 says op types are determined by the
module structure and the trace rather than by weight values, so a change means the traced graph
changed. It did, and the reason was measured:

| Op type | Randomly initialized | Real data | Change |
|---|---|---|---|
| `ios18.add` | 24 | 25 | +1 |
| `ios18.batch_norm` | 0 | 12 | +12 |
| every other op type | identical | identical | 0 |
| **total** | **226** | **239** | **+13** |

`pos_encoding` is initialized to `torch.zeros`, so in an untrained model the positional-encoding
`add` is folded away before the graph is traced. Training gives it values, the `add` survives, and
the six encoder layers' twelve `LayerNormANE` modules lower to `ios18.batch_norm` rather than being
simplified away. The practical consequence is that **Phase 5's 226 was never the shipped graph's
op count**; it was the op count of an untrained stand-in. The eligibility verdict itself survives
the correction: all 239 ops, including the twelve `batch_norm` ops Phase 5 never scanned, are
ANE-eligible with zero CPU-only.

**ELIGIBILITY is what is asserted here. PLACEMENT is not.** ELIGIBILITY means `neuralEngine` is in
every schedulable op's `supported_compute_devices`; it is a compiler property, device-independent
and assertable on the dev Mac, and it is the hard gate. PLACEMENT means `preferred_compute_device
== neuralEngine` at runtime, which is scheduler-, scale- and chip-dependent. At roughly 1.29M
parameters this model is below the Mac runtime ANE-placement scale threshold, so the Mac
`preferred` tally is `{CPU: 239}` and asserting placement here would false-fail a model that is
genuinely, fully ANE-eligible. The placement claim belongs to the device artifact, not to this doc.

---

## Latency with real weights (RD-06b)

`CortexDecoderBench`, in-process Swift, `ContinuousClock`, 50 warmup passes then 10,000 timed
passes through the zero-copy input path.

| Quantity | 4-bit package (shipped artifact) | fp16 package |
|---|---|---|
| p50 | **0.130708 ms** (130,708 ns) | 0.131291 ms |
| p99 | **0.141083 ms** (141,083 ns) | 0.141959 ms |
| min / max | 0.110458 / 0.355584 ms | 0.110875 / 0.271208 ms |
| n | 10,000 | 10,000 |
| `deviceAnnotation`, MEASURED | **CPU** | **CPU** |

Device: **Apple M5 Pro (arm64), macOS-26.5-arm64-arm-64bit**, Xcode 26.3 / Swift 6.2.4.

**This is a CORROBORATING number, not a canonical one.** The ops were measured as CPU-placed, so
0.141083 ms p99 is a CPU latency on an M5 Pro, and it is labeled with the device that produced it.
It is not an iPad-M4 number and is not presented as one. The canonical on-device capture is
optional, is owned by Plan 09-11, is tracked in `09-HUMAN-UAT.md`, and under D-17 is never
auto-approved: it is presented to a human because a hardware-measurement gate that an agent
approves for itself fabricates the project's load-bearing numbers.

Phase-5 baseline, measured on a randomly-initialized graph: 0.12325 ms p50, 0.139333 ms p99, also
CPU-placed on M5 Pro. Real weights moved p99 by 1.7 microseconds, which is the reassuring result:
the 13 extra ops the trained graph carries cost essentially nothing, and both numbers sit far
inside the decoder budget. The bench never enforces a threshold; it prints and records.

---

## The scikit-learn requirement, which is itself a finding

Palettizing either real-data checkpoint failed outright with
`ModuleNotFoundError: scikit-learn is required for k-means quantization`, while palettizing a
randomly-initialized model of the identical architecture succeeded. Instrumenting coremltools' LUT
builder explains it:

```
is_better_to_use_kmeans1d = weight.shape[1] == 1 and num_weights >= 10_000 and dtype == float16
```

coremltools uses its bundled `kmeans1d` only for tensors of at least 10,000 elements. Anything
smaller that still clears `weight_threshold=2048` falls through to scikit-learn. The untrained model
palettizes 38 tensors, all at least 12,288 elements, and never reaches that branch. The real model
palettizes 39, and the extra one is the 4,096-element positional encoding, which exists as a
palettizable const only once training has given it non-zero values.

scikit-learn was added as a `Decoder` dependency, which is coremltools' own documented remedy.
Forcing `kmeans1d` for every tensor would have avoided the dependency but would have changed the
algorithm being compared, and it is the unchanged `OpPalettizerConfig` defaults that make the size
ratio comparable to the Phase-4 measurement at all.

This also means **no synthetic-weight run of this pipeline ever exercised the code path the real
model takes.** Three separate consequences of the same root cause surfaced in this plan: the extra
palettized tensor, the changed op count, and the sklearn requirement. All three trace back to a
positional encoding that is zero until the model is trained.

---

## Reproduce

```bash
# Python leg. --extra dev is mandatory: pytest/ruff live in the dev extra and a bare
# `uv run pytest` resolves a different interpreter and fails with a misleading numpy error.
uv sync --project Decoder --extra dev

# The slow evidence tests (size ratio, NLL delta, ANE scan), which record their weight provenance:
uv run --project Decoder pytest Decoder/tests -m slow -k "palettiz or ane_compute" -q -s

# The full re-derivation. Exits nonzero unless both real-data checkpoints load:
uv run --project Decoder python Decoder/scripts/rederive_coreml.py
uv run --project Decoder python Decoder/scripts/rederive_coreml.py --smoke   # wiring check only

# Swift leg. Build the bench, then run it against the 4-bit package the Python leg wrote:
swift build --package-path Packages/CortexDecoder
CORTEX_DECODER_MODEL_URL="$PWD/Decoder/checkpoints/ndt1_real_vel_4bit.mlpackage" \
  swift run --package-path Packages/CortexDecoder CortexDecoderBench
cat Packages/CortexDecoder/.bench/latency_histogram.json
```

Every artifact these commands produce is gitignored: the checkpoints, the `.mlpackage` and
`.mlmodelc` bundles, and `Packages/CortexDecoder/.bench/`. What is committed is the code that
rebuilds them, the numbers in `09-decoder-metrics.json`, and this note.

---

## What a reader may and may not quote

- **+0.423870** is the held-out velocity R2 of the **fp16** package, and it reproduces Plan 09-07's
  PyTorch figure. It is a within-pool number on sessions the encoder trained on, against a constant
  TRAIN-split mean-velocity null, with no error bar, and it inherits every constraint Plan 09-07
  placed on 0.4238.
- **-1.786971** is the held-out velocity R2 of the **4-bit** package. It may not be quoted without
  the fp16 figure beside it, because the pair is the result and either alone is misleading.
- **-0.770991** is a diagnostic with a train-estimated offset removed. It is not a decode result and
  must never be quoted as one.
- **239/239 ANE-eligible, 0 CPU-only** is an ELIGIBILITY claim on the dev Mac. It is not a residency
  or placement claim.
- **0.141083 ms p99** is a CPU-placed measurement on an Apple M5 Pro. It may not be quoted as an
  iPad-M4 number, or as an ANE number, under any circumstance.
- Phase 5's **226/226** and Phase 4's **3.471x** and **0.009114** are synthetic-weight figures and
  are superseded here. 226 in particular was never the shipped graph's op count.

---
*Phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034*
*Plan: 09-08 -- RD-05 / RD-06 re-derivation on the real-data checkpoints*
