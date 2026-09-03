# Plan 09-08 deferred items

Out-of-scope discoveries found while re-deriving the CoreML numbers on the real-data checkpoints.
Logged, not fixed, per the executor scope boundary. Items 1 and 2 are the consequential ones.

| # | Found during | Item | Why deferred |
|---|--------------|------|--------------|
| 1 | Task 3 | **The 4-bit palettized shipped model does not decode velocity** (held-out R2 -1.786971 against the fp16 package's +0.423870). The choice of deployment artifact is now an open question. | Fixing it means either refitting the readout on the palettized encoder's output or excluding the encoder from palettization. Both change the shipped model, and this plan is forbidden from retraining either model. Phase-10 work. |
| 2 | Task 3 | `ndt1.compute_plan.compiled_model_path` silently returns a stale `.mlmodelc` when its destination already exists. | Fixed at both call sites this plan owns, but the library function itself is unhardened and `compute_plan.py` is outside this plan's `files_modified`. |
| 3 | Task 3 | Phase 5's `05-ane-eligibility-evidence.md` and `05-latency-evidence.md` publish 226/226 and 0.139333 ms as properties of the shipped graph. 226 was measured on an untrained graph and is not the shipped op count. | Plan 09-10 owns the supersession sweep across Phase 4/5 artifacts. |
| 4 | Task 3 | No error bar on any number here, matching the gap Plans 09-06d and 09-07 recorded. | Same reason as those plans: no resampling scheme is defined for autocorrelated held-out bins. |

## Item 1: the 4-bit velocity collapse

The measured facts, in full, are in `09-coreml-evidence.md`. In brief: per-tensor 4-bit k-means
introduces a systematic per-channel mean shift in the encoder's output (up to 1.21573 against a
residual scatter of 0.07793), and the ridge readout, fit on the un-palettized encoder's output,
turns that into a constant velocity error of [-11.24, +12.92] cm/s against a signal whose per-axis
standard deviation is [2.87, 2.02] cm/s. The reconstruction objective barely registers the same
quantization (Poisson-NLL delta 0.020352).

Two candidate remedies, neither run here:

1. **Refit the readout on the palettized encoder's output.** Cheap: the design matrix would come
   from the 4-bit package instead of the float32 model, and Plan 09-07's cached-rates machinery
   already exists. This is the obvious first attempt.
2. **Ship the fp16 package.** It decodes (R2 +0.423870) and its measured p99 on this Mac is
   0.141959 ms against the 4-bit package's 0.141083 ms, so the latency cost is about 0.9
   microseconds. The cost is package size: 2,708,540 B against 796,165 B.

A bias-corrected diagnostic was run to distinguish "offset" from "destroyed" and is reported in the
evidence. It leaves R2 at -0.770991, so a constant correction is not sufficient and remedy 1 is not
guaranteed to work either. Whoever takes this should treat remedy 1 as a hypothesis to test, not a
fix to apply.

**This item must be resolved before any claim that this repository ships a working 4-bit
on-device velocity decoder.** No such claim currently exists in a committed artifact, and
`09-coreml-evidence.md` states the constraint explicitly.

## Item 2: the unhardened `compiled_model_path`

`coremltools.models.utils.compile_model` moves its freshly compiled directory to `destination_path`
with `shutil.move`, which nests the new directory inside an existing destination rather than
replacing it, and then returns the unchanged destination anyway. Any caller that compiles twice to
the same path silently scans the first compile forever.

Measured: compiling the encoder-only model (224 schedulable ops) then the with-velocity model (226)
to one shared destination returns 224 both times.

This plan fixed it at the two call sites it owns: `test_ane_compute_plan.py` now builds under the
test's own `tmp_path`, and `rederive_coreml.py` removes any existing destination and then asserts no
nested compile appeared. The library function is still a footgun for the next caller. The fix is
three lines in `ndt1.compute_plan.compiled_model_path`: remove `destination` if it exists before
calling `compile_model`. It was not applied because `compute_plan.py` is outside this plan's
declared `files_modified`.
