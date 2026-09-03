# Plan 09-08 deferred items

Out-of-scope discoveries found while re-deriving the CoreML numbers on the real-data checkpoints.
Logged, not fixed, per the executor scope boundary. Items 1 and 2 are the consequential ones.

| # | Found during | Item | Why deferred |
|---|--------------|------|--------------|
| 1 | Task 3 | **The 4-bit palettized shipped model does not decode velocity** (held-out R2 -1.786971 against the fp16 package's +0.423870). | **RESOLVED with a recommendation**, after the authorized per-channel follow-up. Ship fp16. See below. |
| 2 | Task 3 | `ndt1.compute_plan.compiled_model_path` silently returns a stale `.mlmodelc` when its destination already exists. | Fixed at both call sites this plan owns, but the library function itself is unhardened and `compute_plan.py` is outside this plan's `files_modified`. |
| 3 | Task 3 | Phase 5's `05-ane-eligibility-evidence.md` and `05-latency-evidence.md` publish 226/226 and 0.139333 ms as properties of the shipped graph. 226 was measured on an untrained graph and is not the shipped op count. | Plan 09-10 owns the supersession sweep across Phase 4/5 artifacts. |
| 4 | Task 3 | No error bar on any number here, matching the gap Plans 09-06d and 09-07 recorded. | Same reason as those plans: no resampling scheme is defined for autocorrelated held-out bins. |
| 5 | the per-channel follow-up | `Decoder/checkpoints/` was emptied between plan 09-08 and this follow-up, destroying both real-data checkpoints, Plan 09-07's 218 MB rates cache and the 09-08 run logs. The checkpoints were restored from a scratch backup and verified against their committed sha256 values before any measurement ran. | Nothing in this plan wipes that directory, so the cause is elsewhere and outside this plan's scope. Worth finding, because the checkpoints represent hours of training and are gitignored by design, so nothing would have detected the loss except a run that needed them. |

## Item 1: the 4-bit velocity collapse, and its resolution

**Status: resolved with a recommendation. The recommendation is to ship the fp16 package.**

The original finding stands: per-tensor 4-bit k-means introduces a systematic per-channel mean
shift in the encoder's output (up to 1.21573 against a residual scatter of 0.07793), and the ridge
readout, fit on the un-palettized encoder's output, turns that into a constant velocity error of
[-11.24, +12.92] cm/s against a signal whose per-axis standard deviation is [2.87, 2.02] cm/s. The
reconstruction objective barely registers the same quantization (Poisson-NLL delta 0.020352).

A pre-registered four-point granularity sweep then tested the obvious remedy. Full table and
mechanism analysis are in `09-coreml-evidence.md`; the decision-relevant rows:

| Candidate | Held-out R2 | Package bytes | ANE eligibility | p99, M5 Pro |
|---|---|---|---|---|
| **fp16** | **+0.423870** | 2,708,540 | 239/239, 0 CPU-only | 0.141959 ms |
| 4-bit `per_grouped_channel` group 1 | +0.191784 | 1,031,338 | 239/239, 0 CPU-only | 0.165042 ms |
| 4-bit `per_tensor` (today's default) | -1.786971 | 796,165 | 239/239, 0 CPU-only | 0.141083 ms |

Per-channel palettization does rescue the decode, from -1.79 to a positive +0.19, and the shift
statistic confirms why: max abs per-channel shift falls 7.2x, from 1.21573 to 0.16916. But it stays
shift-dominated (shift-to-residual ratio 3.35 against per-tensor's 15.6), so the mechanism is
attenuated rather than removed, and the recovered R2 is only 45% of fp16's.

**The trade therefore does not pay.** Moving to the best 4-bit configuration costs 55% of the
decode quality to save 1,677,202 bytes on a model already under 3 MB, while every candidate has at
least 12x latency headroom against the 2 ms budget and both viable candidates are fully ANE-eligible.
R2 decides, and nothing else contradicts it.

Two constraints that follow:

1. **Whatever ships, it must not be the current `per_tensor` 4-bit default.** It is the one option
   measured as broken.
2. **If a future memory constraint forces 4-bit**, the configuration is `per_grouped_channel` with
   `group_size=1`, and the remedy below should be tried first.

**Still untested, and deliberately so:** refitting the readout on the palettized encoder's output.
It is cheap, Plan 09-07's cached-rates machinery already exists, and nothing measured here rules it
out. It was not run because this plan may not retrain either model. Whoever takes it should treat it
as a hypothesis: the bias-corrected diagnostic (-0.770991 with a train-estimated constant removed)
shows the damage is not a pure offset, so a refit is not guaranteed to recover fp16 quality.

Two incidental results from the sweep, recorded because they are traps for the next person:
`enable_per_channel_scale=True` **breaks ANE eligibility** (38 CPU-only ops, `all_eligible` false),
and a `group_size` that does not divide a tensor's channel count silently leaves that tensor
uncompressed, which is why `group_size=32` skips all six 71,680-element FFN tensors and compresses
worse than per-tensor.

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
