# CortexDecoder

Reserved for Phase 5: CoreML deployment of the NDT1 decoder on the M4 Neural Engine.
NDT1 (~1.3M params, h=1-2 heads, 6 layers, 128 hidden dim, 20ms binning, BC1S
`(B, C, 1, S)` tensor layout) runs at <2ms p99 via `MLModelConfiguration.computeUnits = .cpuAndNeuralEngine`,
with ANE residency verified through Instruments → CoreML template.

Empty in Phase 1 — see `.planning/REQUIREMENTS.md` DEC-06 through DEC-12.

## Why CoreML, not MLX

MLX has unbounded P99 latency and no ANE support — disqualifying for the <2ms p99 budget.
CoreML on ANE is the only path meeting the sub-25ms glass-to-glass commitment.
