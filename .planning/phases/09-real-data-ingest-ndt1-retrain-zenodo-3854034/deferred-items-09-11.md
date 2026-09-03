# Deferred items from plan 09-11

Out-of-scope discoveries from executing 09-11. Plan 09-11's declared file is `09-HUMAN-UAT.md`; the
2026-09-02 device capture also added `09-perf-report-ipad-m2.json`. Everything below touches files
owned by other plans and was deliberately not changed here.

## 1. `09-coreml-evidence.md` does not carry the iPad Air M2 row

Owner: plan 09-08. The "Latency with real weights (RD-06b)" table lists the 4-bit and fp16 Mac
columns only. A follow-up should add the M2 corroborating row (p50 0.2240 ms, p99 0.5790 ms, n=120,
`{cpu: 239}` under `.all`, iPad Air 11-inch (M2) / iPadOS 18.7.8) beside them, without touching the
Mac numbers.

The "ANE eligibility (RD-06a)" section would also be strengthened by one sentence: the 239-op tally
and the 12 `batch_norm` ops were independently confirmed on device by the Xcode Core ML Performance
Report, which does not go through the `compile_model` path that caused the stale reads. That is a
stronger corroboration than anything measurable on the Mac, because it is a different tool on
different silicon.

The "What a reader may and may not quote" list should gain a line: 0.5790 ms p99 is a CPU-placed
measurement on an iPad Air M2 under `computeUnits=.all`, and may not be quoted as an iPad-M4 number,
as an ANE number, or as directly comparable to the M5 Pro figure measured under
`.cpuAndNeuralEngine`.

## 2. `09-decoder-metrics.json` has no M2 entry

Owner: plan 09-08 (and `rederive_coreml.py` writes this file). The `latency` section carries the M5
Pro entry, `fp16_comparison` and `per_channel_4bit_comparison`, all Mac. A second device entry, for
example `latency.ipad_m2_corroborating`, would make the M2 capture machine-readable. It must be
clearly labeled with its device and its `.all` compute-unit set, and `latency.status` must stay
`corroborating` for the Mac entry. Not added here because `rederive_coreml.py` rewrites this file
and a hand-added key could be silently dropped on the next re-derivation; whoever adds it should
decide whether the writer or the artifact owns the key.

## 3. Identifier hygiene across the two committed raw performance reports

`05-perf-report-ipad-m2.json` and now `09-perf-report-ipad-m2.json` are the tool's raw output and
both carry the same device's `deviceID`, `serialNumber` and display name. Committing the second one
added no identifier the repository did not already hold, and committing raw is what makes every
figure independently recomputable, which is why it was done. But if this repository is ever
published for review, the two files have to be scrubbed together or not at all. Scrubbing one is
pointless. Flagged rather than acted on, because unilaterally rewriting a Phase-5 evidence artifact
is not this plan's call.

## 4. `05-HUMAN-UAT.md` still presents 226 as the graph's op count

Phase 5 recorded "226/226 ops" from a capture that is now known to have been an untrained stand-in,
and 09-coreml-evidence.md already says so. The Phase-5 file itself carries no such note, so a reader
who lands there first will take 226 as the shipped graph's count. A one-line pointer forward would
fix it. Not edited here because it belongs to a closed phase.
