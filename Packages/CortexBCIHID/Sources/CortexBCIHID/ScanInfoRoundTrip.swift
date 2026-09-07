// ScanInfoRoundTrip — Phase 8 (SYS-03/04, SC#2): the bidirectional closed-loop round trip over the BCI
// HID Scan-Info channel (CONTEXT D-05, RESEARCH §0.2/§1.1). The protocol *names* the round trip for us:
// the "bidirectional context sharing" channel is literally the BCI HID Scan-Info OUTPUT report.
//
// MODEL (host <-> device contract):
//   host emits a Scan-Info OUTPUT report (RID 4, host->device) carrying UI state -> Cortex returns
//   intent as an Item-Selection INPUT report (RID 4) + a Pointer report (RID 3) -> one instrumented log
//   line records the cycle. The scan `seed` ties a cycle to its response.
//
// In Plan 03 the decoder is GENUINELY in this loop (synthetic-spike -> NDT1 -> ReFIT). HERE the harness
// models the host<->device contract deterministically so SYS-03/04 are satisfiable + unit-testable today
// with no external app, no granted entitlement, and no device (CONTEXT D-05).
//
// DETERMINISM CONTRACT (threat T-08-02-03, mirrors CortexReFITBench): the intent is a PURE function of
// the Scan-Info input — NO RNG, NO wall-clock. The only nondeterminism, `mach_absolute_time()`, is
// confined to the LOG timestamp (asserted monotonic, not exact). The deterministic perturbation uses a
// pure SplitMix64 integer hash of (seed, selectedItem), NOT an entropy-backed generator.
//
// Foundation-free: `Darwin` provides `mach_absolute_time()` + `mach_timebase_info` so CortexBCIHID stays
// dependency-free (no CortexCore link) — the round-trip/log is off the hot path, but keeping the package
// lean mirrors its existing posture (the buildable-now HID surface is pure value types).
import Darwin

/// The intent Cortex returns for one Scan-Info cycle: an Item-Selection (RID 4 input, the focused item)
/// + a Pointer report (RID 3, the coherent cursor delta steering toward that item).
///
/// `nonisolated`: a pure `Sendable` value carrying two `nonisolated` report structs.
public nonisolated struct RoundTripResponse: Sendable, Equatable {
  /// The focus item the device selected (RID 4, device->host).
  public let itemSelection: BCIInputItemSelection
  /// The cursor delta steering toward the focused item (RID 3, device->host).
  public let pointer: BCIInputPointerReport

  public init(itemSelection: BCIInputItemSelection, pointer: BCIInputPointerReport) {
    self.itemSelection = itemSelection
    self.pointer = pointer
  }
}

/// The in-app host harness for the SYS-03/04 round trip. "Closed loop" here means the HID PROTOCOL
/// loop -- a Scan-Info OUTPUT report in, an intent report out -- and nothing about neural control:
/// callers drive it with their own `selectedItem`, so a running log demonstrates that the report
/// path works, NOT that a decoded cursor selected anything. `CortexMac` drives it from a sequence
/// counter for exactly this reason.
/// Holds the instrumented `RoundTripLog` and a
/// monotonic cycle counter; `respond(to:)` turns one host Scan-Info OUTPUT report into a deterministic
/// intent and appends exactly one log entry.
///
/// A `final class` (reference semantics): a single harness instance owns the cumulative log + cycle
/// counter across the demo session (Plan 03 surfaces `log` live). The package's default `MainActor`
/// isolation applies (the harness is driven off the hot path, alongside the UI).
public final class ScanInfoRoundTrip {
  /// The instrumented round-trip log (the SC#2 evidence). Exposed so the demo (Plan 03) can surface it.
  public let log: RoundTripLog

  /// Monotonic 0-based cycle counter, incremented once per `respond(to:)`.
  private var cycleCounter: UInt64 = 0

  public init(log: RoundTripLog = RoundTripLog()) {
    self.log = log
  }

  /// Run one closed-loop cycle: consume the host's Scan-Info OUTPUT report, compute the deterministic
  /// intent (item selection + coherent pointer delta), record one instrumented log entry, and return
  /// the intent. The intent is a PURE function of `scanInfo`; only the log timestamp varies (monotonic).
  public func respond(to scanInfo: BCIOutputScanInfoReport) -> RoundTripResponse {
    let (itemIndex, pointerDelta) = Self.computeIntent(for: scanInfo)

    // Timestamp the cycle for the instrumented log (mach_absolute_time -> ns). LOG-ONLY nondeterminism.
    let entry = RoundTripEntry(
      timestampNs: Self.machAbsoluteNanoseconds(),
      seed: scanInfo.seed,
      selectedItemIn: scanInfo.selectedItem,
      numberOfItems: scanInfo.numberOfItems,
      itemIndexOut: itemIndex,
      pointerDelta: pointerDelta,
      cycleIndex: cycleCounter
    )
    log.record(entry)
    cycleCounter &+= 1

    return RoundTripResponse(
      itemSelection: BCIInputItemSelection(itemIndex: itemIndex),
      pointer: BCIInputPointerReport(position: (pointerDelta.x, pointerDelta.y, pointerDelta.z))
    )
  }

  // ───────────────────────────────────────────────────────────────────────────────────────────────
  // The deterministic intent model — a PURE function of the Scan-Info input (threat T-08-02-03).

  /// Compute the focus `itemIndex` (clamped to `0..<max(1, numberOfItems)`) and a coherent cursor delta
  /// steering toward the focused cell on the (inferred square) scan grid. Degenerate `numberOfItems==0`
  /// returns the safe no-selection intent (index 0, zero delta) — no out-of-bounds (threat T-08-02-01).
  static func computeIntent(for scanInfo: BCIOutputScanInfoReport) -> (UInt8, SIMD3<Int8>) {
    let count = Int(scanInfo.numberOfItems)
    // T-08-02-01: degenerate scan list -> safe no-selection, no division/indexing on an empty list.
    guard count > 0 else { return (0, SIMD3<Int8>(0, 0, 0)) }

    let selected = Int(scanInfo.selectedItem)
    // The "MoveToNextItem/Select" semantics: advance one step from the host's current selection toward
    // the focus, perturbed by a pure hash of (seed, selectedItem) so distinct cycles can land on
    // distinct focus cells — deterministically, with NO RNG. Clamp into the valid scan-list range.
    let hash = splitMix64(UInt64(scanInfo.seed) &<< 8 | UInt64(scanInfo.selectedItem))
    let focus = (selected &+ 1 &+ Int(hash % UInt64(count))) % count
    let itemIndex = UInt8(focus) // focus ∈ 0..<count ≤ 255, always representable

    // A coherent cursor delta: steer from the selected cell toward the focused cell on the inferred
    // square grid (side = ceil(sqrt(count))). The delta is the per-cycle step toward the target cell,
    // scaled into the documented Pointer range and clamped to -127...127.
    let side = max(1, isqrtCeil(count))
    let selRow = (selected % count) / side
    let selCol = (selected % count) % side
    let focRow = focus / side
    let focCol = focus % side
    let deltaX = clampToPointer((focCol - selCol) * pointerStepPerCell)
    let deltaY = clampToPointer((focRow - selRow) * pointerStepPerCell)
    // The depth axis is unused by the 2-D webgrid cursor — always 0, a coherent "no depth motion".
    return (itemIndex, SIMD3<Int8>(deltaX, deltaY, 0))
  }

  /// Pixels-of-intent per grid cell of separation, before clamping into the Pointer's -127...127 range.
  private static let pointerStepPerCell: Int = 8

  /// Clamp an Int step into the BCI Pointer report's documented signed delta range (-127...127).
  private static func clampToPointer(_ value: Int) -> Int8 {
    Int8(max(-127, min(127, value)))
  }

  /// Ceil(sqrt(itemCount)) for itemCount >= 1 — the inferred square-grid side for that many scan items
  /// (integer-only, pure).
  private static func isqrtCeil(_ itemCount: Int) -> Int {
    var root = 0
    while root * root < itemCount {
      root += 1
    }
    return root
  }

  /// SplitMix64 — a pure, allocation-free integer hash (Steele/Vigna). Used ONLY for a deterministic
  /// per-cycle perturbation of the focus index; it is a fixed integer mix, NOT an entropy-backed
  /// generator (no hidden state, no entropy source — the same input always yields the same output),
  /// satisfying the determinism contract (threat T-08-02-03; mirrors the CortexReFITBench no-RNG guarantee).
  static func splitMix64(_ input: UInt64) -> UInt64 {
    var state = input &+ 0x9E37_79B9_7F4A_7C15
    state = (state ^ (state >> 30)) &* 0xBF58_476D_1CE4_E5B9
    state = (state ^ (state >> 27)) &* 0x94D0_49BB_1331_11EB
    return state ^ (state >> 31)
  }

  // ───────────────────────────────────────────────────────────────────────────────────────────────
  // LOG-ONLY clock. Confined here so the intent path stays pure (threat T-08-02-03).

  /// A monotonic nanosecond timestamp from `mach_absolute_time()` (same clock as the PERF-04 latency
  /// bench in Plan 03). Inlined from `Darwin` to keep CortexBCIHID dependency-free; the required-reason
  /// API usage is declared in the apps' `PrivacyInfo.xcprivacy` (CA92.1), matching `CortexCore.Time`.
  static func machAbsoluteNanoseconds() -> UInt64 {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let raw = mach_absolute_time()
    return raw &* UInt64(info.numer) / UInt64(info.denom)
  }
}
