// CortexRenderBench — the macOS GPU-time / frame-pacing measurement executable (RENDER-05/09, SC#2).
//
// Plan 04 lands this one-line stub so the XcodeGen target + scheme resolve end-to-end (xcodegen +
// xcodebuild) BEFORE Plan 05 writes the real measurement. Plan 05 replaces this with the
// commandBuffer.gpuStartTime/gpuEndTime histogram (≤0.4ms GPU on the M5 Pro ProMotion panel,
// CONTEXT D-11 corroborating-canonical) + the 60s sustained-120Hz no-dropped-frames soak (SC#4),
// driven over the CortexRender display-link adapters and the deterministic LissajousProducer.
// In-process bench, NOT a swift-test timing gate (D-18 — a flaky latency assertion stays out of CI).
print("bench: Plan 05 lands here")
