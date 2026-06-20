// Spike-A Swift glue: prove a Rust `extern "C"` function is callable from Swift through the
// CortexRingFFI xcframework `.binaryTarget` (D-R1). `import CortexRingFFI` pulls in the
// cbindgen-generated C module (cortex_ring.h via the bundled modulemap); `cortex_ping` is the
// Rust symbol. Plan 04 grows this into the real ring producer/consumer wrappers over the same ABI.
import CortexRingFFI

/// Calls the Rust `cortex_ping` across the C ABI and returns its result.
///
/// The Rust side computes `x ^ 0x5A5A_5A5A` (a non-identity transform), so a green round-trip
/// proves a real FFI call through the xcframework rather than a hard-coded Swift constant.
public func cortexPing(_ x: UInt32) -> UInt32 {
  cortex_ping(x)
}
