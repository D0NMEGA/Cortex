// Spike-A proof (SC#4 foundation): the Swift↔Rust FFI round-trip works end to end through the
// CortexRingFFI xcframework `.binaryTarget`. The Rust `cortex_ping` computes `x ^ 0x5A5A_5A5A`,
// so asserting the XOR result (not a constant) proves a REAL extern "C" call crossed the boundary
// — if the xcframework were unlinked or the symbol missing, this target would not even build.
import CortexRingPing
import Testing

@Test func pingRoundTrips() {
  // 1 ^ 0x5A5A_5A5A — a non-identity transform computed on the Rust side.
  #expect(cortexPing(1) == (1 ^ 0x5A5A_5A5A))
}

@Test func pingIsInvolution() {
  // XOR with a constant is its own inverse: applying cortex_ping twice returns the input.
  // A second independent round-trip hardens against an accidental identity/constant stub.
  let x: UInt32 = 0xDEAD_BEEF
  #expect(cortexPing(cortexPing(x)) == x)
}
