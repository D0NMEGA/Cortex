// CursorVelocity — the renderer's dedicated `(vx, vy)` fp16 VELOCITY seam (Phase 6 D-03).
//
// This is the ONLY input the renderer consumes. It is deliberately NOT the raw 96-channel
// `CortexFrame` ring (that would couple the renderer to neural data it cannot decode). A synthetic
// producer fills it in Phase 6; the Phase 5 decoder + Phase 7 ReFIT-Kalman become the producer
// later — and because the seam is velocity-typed (the Kalman also emits a velocity), it is
// unchanged when the real decoder lands.
//
// ## Layout discipline (load-bearing — D-03)
// The field order — `ts_ns` (u64), `seq` (u64), then the fp16 payload — MIRRORS the
// `#[repr(C)] CortexFrame` ABI in `Packages/CortexRing/rust/include/cortex_ring.h`
// (`uint64_t ts_ns; uint64_t seq; uint16_t channel_data[…]`). Keeping the same discipline means a
// future `#[repr(C)] CursorVelocity` + `cbindgen` Rust producer (Phase 7) is a DROP-IN: the Swift
// consumer sees an identical struct across the FFI, exactly as `CortexFrame` does today. `Float16`
// is the project's hardware-half IPC type (Phase 2 D-10), matching DEC-10's 2-vector fp16 cursor
// velocity emitted every 20ms.
//
// All fields are trivial fixed-width scalars (no references), so the value is trivially copyable —
// a single store copies the whole frame across the SPSC ring slot (no torn pointer, no ARC).

/// One cursor-velocity frame crossing the producer→renderer seam (D-03).
///
/// `Sendable` + `nonisolated`: this value crosses into the display-link callback (Plan 03) and is
/// read from nonisolated contexts under the package's `.defaultIsolation(MainActor.self)` +
/// complete strict-concurrency posture. It is a trivial value type, so the conformance is sound.
///
/// - `vx`/`vy` are velocities in GRID-UNITS PER SECOND (the integrator advances
///   `position += velocity * dt` with no extra scale factor — see `CursorIntegrator`).
public nonisolated struct CursorVelocity: Sendable, Equatable {
  /// `mach_absolute_time`-derived nanoseconds — mirrors `CortexFrame.ts_ns` (Phase 2 D-12).
  public var tsNs: UInt64
  /// Monotonic sequence number — mirrors `CortexFrame.seq` (Phase 2 D-12).
  public var seq: UInt64
  /// fp16 velocity x, grid-units/second (DEC-10 2-vector fp16).
  public var vx: Float16
  /// fp16 velocity y, grid-units/second (DEC-10 2-vector fp16).
  public var vy: Float16

  /// Memberwise initializer (explicit so the public API is stable across a future FFI mirror).
  public init(tsNs: UInt64, seq: UInt64, vx: Float16, vy: Float16) {
    self.tsNs = tsNs
    self.seq = seq
    self.vx = vx
    self.vy = vy
  }
}
