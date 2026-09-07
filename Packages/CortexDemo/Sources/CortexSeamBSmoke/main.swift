// CortexSeamBSmoke - the RD-08 Seam B chain smoke (Phase 10, Plan 10-06).
//
// ## What Seam B is, verbatim from 10-PREREGISTRATION section 9
//
//   "Seam B is the D-05 chain: daemon reads the export, AES-GCM seal, shm ring, consumer decrypt,
//    rolling 32-bin window, SpikeInputBuffer, decode. This is a strictly WIDER measurement boundary
//    and is reported as a new number, never against 8.3 ms."
//
// Seam B is WIDER than Seam A and wider than the Phase-8 8.3 ms, so nothing this binary produces may
// be reported against either. 10-RESEARCH Correction 2, in one sentence: the Phase-8 number did not
// include an IPC leg at all (`Packages/CortexDemo/Package.swift` declared no CortexIPC dependency and
// no app-side ring consumer existed), so this is NEW wiring, not a re-run of an existing measurement.
//
// ## No verdict, ever (D-09, 10-PREREGISTRATION section 9)
// This binary emits no `passed` key, compares nothing against any budget, and exits 0 on a clean run
// whatever the counters are. It fails ONLY on a STRUCTURAL violation: frames out of order, a window
// that was never completed, a payload that changed in flight, or a tampered frame that decoded.
//
// ## The process boundary, stated plainly (Plan 10-06, Rule 3 deviation)
// The chain below runs IN ONE PROCESS, in producer/consumer lock-step over a real `shm_open`ed
// `ShmRing`, a real `Doorbell` socketpair, real AES-GCM and the real FlatBuffers codec. It does NOT
// posix_spawn a second process, and the JSON says so in `process_boundary`.
//
// That is the repo's OWN always-on idiom, not a shortcut invented here. `HarnessE2ETests` documents
// it in Phase 2: `testInProcessRoundTrip` is "the ALWAYS-ON CI correctness gate (runs on the
// macos-15/M1 runner with no spawn flakiness)", while `testTwoProcessSpawnRoundTrip` is
// XCTSkip-guarded. Re-measured on 2026-09-05 on the developer machine, the daemon's two-process
// rendezvous fails BEFORE any Phase-10 change: the child returns MACH_SEND_INVALID_DEST (0x10000003)
// from `Rendezvous.childAcquire` and the parent then times out in `parentAwaitReply`
// (MACH_RCV_TIMED_OUT, 0x10004004), identically with and without a replay export configured. Building
// a CI gate on that mechanism would produce a red or flaky step, which is the opposite of what this
// gate is for. Every stage section 9 names is exercised here; the one thing not crossed is the
// process boundary, which section 9's definition does not name.
//
// ## What the renderer and HID counters do and do NOT claim
// `cursor_updates` and `pointer_reports_encoded` measure that the renderer's INTEGRATION seam and the
// HID report ENCODER each received every decoded window - DELIVERY, not presentation. No
// `CAMetalDisplayLink` runs here, no HID device is registered, and no frame is scanned out. The
// measured display cadence remains the Plan 10-10 GUI capture plus the deferred iPad-M4 gate.
import CortexBCIHID // BCIInputPointerReport - the HID encode leg.
import CortexCore // ReplayExport - the ONE Swift reader of the D-06 export (Plan 10-04).
import CortexDecoder // SpikeInputBuffer (zero-copy) + NeuralDecoder (NDT1 CoreML).
import CortexDemo // RollingSpikeWindow + RecordedSpikeSource.modelSeqLen.
import CortexIPCSession // SampleCodec, SessionCrypto, HarnessConsumer.packSlot.
import CortexIPCTransport // ShmRing + Doorbell - the real Phase-2 transport.
import CortexRender // CursorIntegrator + CursorVelocity - the single [0,1] clamp seam.
import CryptoKit // SHA256 over the sidecar bytes actually read.
import Darwin // shm_unlink for the unique per-run ring name.
import Foundation
import Metal // MTLCreateSystemDefaultDevice, for the shared-surface spike buffer.

// MARK: - Pre-registered constants

/// The decode/filter tick: one 20 ms bin (10-PREREGISTRATION section 2).
let dt = 0.020
/// The shipped `ndt1_real_vel_sweep_fp16` input is `(1, 96, 1, 32)`. Locked, not a tunable.
let seqLen = RecordedSpikeSource.modelSeqLen
/// The 96-channel Indy contract (DEC-02), and exactly what `SampleCodec.encode` requires per frame.
let channelCount = 96
/// The open-loop disclosure, byte-identical everywhere it appears (10-PREREGISTRATION section 12).
let openLoopDisclosure = "open-loop replay of a recorded session; the subject was not in the loop"

// MARK: - CLI

let arguments = CommandLine.arguments

func flagValue(_ name: String) -> String? {
  guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
  let value = arguments[index + 1]
  return value.isEmpty ? nil : value
}

let tamperRequested = arguments.contains("--tamper")
let requestedFrames = flagValue("--frames").flatMap(Int.init) ?? 512
let modelURL = flagValue("--model").map { URL(fileURLWithPath: $0) }
  ?? ClosedLoopPipeline.modelURLFromEnvironment()

/// The repo root, walked up from this file: `<root>/Packages/CortexDemo/Sources/CortexSeamBSmoke/`.
let repoRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent() // CortexSeamBSmoke
  .deletingLastPathComponent() // Sources
  .deletingLastPathComponent() // CortexDemo (package root)
  .deletingLastPathComponent() // Packages
  .deletingLastPathComponent() // repo root
let packageRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
let outputURL = flagValue("--out").map { URL(fileURLWithPath: $0) }
  ?? packageRoot.appendingPathComponent(".bench/seam_b.json")

/// The committed synthetic fixture (Plan 10-02 task 3b), TRACKED via explicit `.gitignore` negations.
let fixtureSidecar = repoRoot.appendingPathComponent("Decoder/tests/fixtures/tiny_replay.json")

// MARK: - Export resolution ORDER, not a skip (review D-7, 2026-09-05)

// The earlier design skipped whenever no export was configured, and CI NEVER configures one because
// the D-07 tier split keeps the dataset off the runner. That step would therefore have exercised
// nothing while reporting green, and a gate that always passes is not a gate. The fix is an ORDER
// with the committed fixture as the third step. The skip survives only for the case where even the
// fixture is missing, which on a checkout means the repo is broken.

enum DataSource: String {
  case real
  case syntheticFixture = "synthetic_fixture"
}

struct ResolvedSource {
  let url: URL
  let kind: DataSource
  let why: String
}

func resolveSource() -> ResolvedSource? {
  if let explicit = flagValue("--export") {
    return ResolvedSource(url: URL(fileURLWithPath: explicit), kind: .real, why: "--export was given")
  }
  if let fromEnv = ReplayExport.sidecarURLFromEnvironment() {
    return ResolvedSource(url: fromEnv, kind: .real, why: "CORTEX_REPLAY_EXPORT is set")
  }
  if FileManager.default.fileExists(atPath: fixtureSidecar.path) {
    return ResolvedSource(
      url: fixtureSidecar,
      kind: .syntheticFixture,
      why: "no export was configured, so the COMMITTED SYNTHETIC FIXTURE is the source; "
        + "this run measures the chain, never real data"
    )
  }
  return nil
}

guard let source = resolveSource() else {
  print("CortexSeamBSmoke: skipping - no spike source could be resolved. Tried, in order:")
  print("  1. --export <sidecar.json>            (not given)")
  print("  2. CORTEX_REPLAY_EXPORT               (not set)")
  print("  3. \(fixtureSidecar.path)  (absent)")
  print("")
  print("  Step 3 is committed to the repo, so its absence means this is not a complete checkout.")
  print("  Exiting 0 - nothing was measured, so nothing is reported.")
  exit(0)
}

let export: ReplayExport
do {
  export = try ReplayExport(sidecarURL: source.url)
} catch {
  print("CortexSeamBSmoke: could not open \(source.url.path) - \(error)")
  print("  A configured source that cannot be read is a FAILURE, never a fallback to synthetic data.")
  exit(1)
}

/// `--frames` is clamped to the source's own bin count, so the fixture run does 256 and not 512.
let frameCount = min(requestedFrames, export.binCount)
/// The frame whose AES-GCM tag `--tamper` corrupts (T-10-06-01). Frame `n/2`, so the run is already
/// mid-stream with a partially filled accumulator when the tamper lands.
let tamperSeq = UInt64(max(1, frameCount / 2))

print("CortexSeamBSmoke - the RD-08 Seam B chain (10-PREREGISTRATION section 9)")
print("  source        = \(source.url.path)")
print("  data_source   = \(source.kind.rawValue)   [\(source.why)]")
print("  session       = \(export.sidecar.sessionId)")
print("  bins          = \(export.binCount), channels = \(export.channelCount)")
print("  frames        = \(frameCount) (requested \(requestedFrames), clamped to the source's n_bins)")
print("  window        = \(seqLen) bins, assembled consumer-side by RollingSpikeWindow")
print("  tamper        = \(tamperRequested ? "ON, frame \(tamperSeq)" : "off")")

// MARK: - The seq -> bin mapping, mirroring Apps/CortexDaemon/Producer.binF16

// `Producer.binF16` maps `seq % binCount`, so consecutive sequence numbers carry consecutive export
// bins and 32 accumulated frames are 32 CONTIGUOUS bins of the recorded session. This binary cannot
// import that type (`Apps/` is an xcodebuild target, not a SwiftPM module), so the mapping is
// restated here. If one side ever changes, the payload-integrity assertion below is what catches it.

func exportBin(forSeq seq: UInt64) -> Int {
  Int(seq % UInt64(export.binCount))
}

func binValues(forSeq seq: UInt64) throws -> [Float16] {
  try export.window(endingAt: exportBin(forSeq: seq), length: 1)
}

// MARK: - The chain

/// A unique shm name per run so two concurrent smokes cannot share a region (the Phase-2 RingTests
/// precedent). Darwin caps the name at 31 bytes.
let shmName = "/cx-seamb-\(String(UInt32.random(in: 0 ..< UInt32.max), radix: 16))"
defer { _ = shmName.withCString { shm_unlink($0) } }

let keys = SessionKeys(secret: SessionKeys.generateSecret())
let ring: ShmRing
let doorbell: Doorbell
do {
  ring = try ShmRing(name: shmName, create: true)
  doorbell = try Doorbell()
  try doorbell.arm()
} catch {
  print("CortexSeamBSmoke: could not open the transport (\(shmName)) - \(error)")
  exit(1)
}

let accumulator = RollingSpikeWindow(channels: channelCount, length: seqLen)
let integrator = CursorIntegrator()

/// The zero-copy decode buffer. Absent only on a machine with no Metal device, in which case every
/// other leg still runs and `spike_buffer_backed` records that the fill was not exercised.
let spikeBuffer: SpikeInputBuffer? = {
  guard let device = MTLCreateSystemDefaultDevice() else { return nil }
  return try? SpikeInputBuffer(device: device, seqLen: seqLen, channels: channelCount)
}()

/// The real NDT1 decoder, when one was supplied. Both the model and the real export are gitignored
/// (D-07), so on a clean clone and in CI this is nil and only the CoreML call is skipped.
let decoder: NeuralDecoder? = {
  guard let modelURL else { return nil }
  do {
    return try NeuralDecoder(modelURL: modelURL)
  } catch {
    print("CortexSeamBSmoke: the model at \(modelURL.path) could not be loaded - \(error)")
    print("  A supplied-but-unloadable model is a FAILURE, not a silent fall-through to no-decode.")
    exit(1)
  }
}()

var framesAccepted = 0
var framesDropped = 0
var windowsCompleted = 0
var windowsFilled = 0
var decodesSucceeded = 0
var cursorUpdates = 0
var pointerReportsEncoded = 0
var doorbellWakes = 0
/// Per-completed-window Seam B chain latency in ns (Plan 10-08). A MEASUREMENT INSTRUMENT ONLY: it
/// adds two `Time.machAbsoluteNanoseconds()` reads per iteration and changes no frame byte, no crypto
/// step and no counter. The interval starts at the top of the producer iteration, immediately before
/// the export bin is read, and ends the instant the NDT1 decode returns on the consumer side - so it
/// spans export read -> seal -> ring write -> doorbell -> poll -> decrypt -> FlatBuffers decode ->
/// ordering -> 32-bin accumulation -> SpikeInputBuffer fill -> decode. It EXCLUDES the cursor
/// integration and the HID encode that follow, which is where the `boundary` string above ends for
/// the counters but NOT for this number; `latency_boundary` below states the narrower span verbatim.
///
/// It is NOT comparable to Seam A or to the Phase-8 number, and it carries one further caveat that
/// `latency_caveat` states in the artifact: this run is single-process lock-step, so no cross-process
/// wakeup or scheduling delay is included. Both halves read the SAME `mach_absolute_time` timebase in
/// the same thread, which is why the arithmetic is trustworthy and why the number is a floor on what
/// a real two-process chain would cost, never an estimate of it.
var chainLatenciesNs = [UInt64]()
/// Plan 10-08 / 10-PREREGISTRATION section 14, `velocity_amplitude_shrinkage`. Per completed window,
/// the DECODED speed |v| in cm/s straight off `NeuralDecoder.decode` and the export's own TRUE binned
/// speed for the same bin, in the same cm/s units the sidecar declares (`units.velocity = "cm/s"`).
/// Pairing follows the repo's existing alignment convention, the one the payload-integrity check
/// already uses: the window ENDING at a bin pairs with that bin. Populated only when a model is
/// supplied - with no decoder the decoded velocity is structurally zero and a ratio would be a
/// fabricated number rather than a measured one. Another measurement instrument: no frame byte, no
/// crypto step and no counter changes.
var decodedSpeedsCmPerS = [Double]()
var trueSpeedsCmPerS = [Double]()
/// The bin-major values of the FIRST completed window, and the seq that completed it, kept for the
/// end-to-end payload-integrity check below.
var firstWindow: [Float16] = []
var firstWindowClosingSeq: UInt64 = 0

var scratch = [UInt8](repeating: 0, count: ring.layout.slotStride)
var lastSeen: UInt64 = 0

/// The 3-tuple returned below is `BCIInputPointerReport.position`'s own shape (x, y, z), not a shape
/// chosen here; `BCIHIDReports.swift` carries the same scoped lint disable for the same reason.
///
/// Map a `[0,1]` cursor position onto the pointer report's `Int8` triple. The report carries signed
/// bytes, so the grid-normalised position is shifted to `[-128, 127]`: `round(p * 255) - 128`. The z
/// axis is 0 - this decoder drives a 2-D cursor, and inventing a depth would be fabricating a signal.
func pointerTriple(for position: CursorPosition) -> (Int8, Int8, Int8) { // swiftlint:disable:this large_tuple
  func quantise(_ value: Float) -> Int8 {
    let scaled = (value.isFinite ? value : 0).clamped(to: 0 ... 1) * 255
    return Int8(clamping: Int(scaled.rounded()) - 128)
  }
  return (quantise(position.x), quantise(position.y), 0)
}

extension Float {
  func clamped(to range: ClosedRange<Float>) -> Float {
    min(max(self, range.lowerBound), range.upperBound)
  }
}

for _ in 0 ..< frameCount {
  // Seam B latency clock starts HERE (Plan 10-08), before the export bin is read. Same
  // `mach_absolute_time` timebase as the consumer-side read below.
  let chainStartNs = Time.machAbsoluteNanoseconds()

  // ---- Producer half: one export bin -> FlatBuffers Sample -> AES-GCM seal -> ring slot -> doorbell.
  let seq = ring.loadProducerSeq() &+ 1
  let bin: [Float16]
  do {
    bin = try binValues(forSeq: seq)
  } catch {
    print("CortexSeamBSmoke: could not read export bin \(exportBin(forSeq: seq)) - \(error)")
    exit(1)
  }
  let plain: [UInt8]
  var ciphertext: [UInt8]
  var tag: [UInt8]
  do {
    plain = try SampleCodec.encode(tsNs: UInt64(seq) &* 20_000_000, seq: seq, channels: bin)
    (ciphertext, tag) = try SessionCrypto.seal(plain, keys: keys, direction: .daemonToApp, seq: seq)
  } catch {
    print("CortexSeamBSmoke: seal failed at seq \(seq) - \(error)")
    exit(1)
  }

  // T-10-06-01, the negative control: flip ONE bit of the AES-GCM tag, mirroring the Phase-2
  // `CryptoTests.tamperFailsClosed` shape. The frame is otherwise byte-identical, so the ONLY thing
  // that can reject it is the authentication tag.
  let isTampered = tamperRequested && seq == tamperSeq
  if isTampered {
    tag[0] ^= 0x01
  }

  let slot = HarnessConsumer.packSlot(ciphertext: ciphertext, tag: tag)
  let written = slot.withUnsafeBytes { ring.write(slotBytes: $0) }
  doorbell.ring(seq: written)
  // Drain the doorbell notification and COUNT it, so the wake leg is exercised rather than assumed
  // (and so the socketpair cannot fill at a large --frames). Timeout 0: the notification is already
  // queued, this run is lock-step.
  if case let .woke(wokeSeq) = doorbell.wait(timeoutNanos: 0), wokeSeq == written {
    doorbellWakes += 1
  }

  // ---- Consumer half: poll the ring, parse [len][ct][tag], open, decode, order, accumulate.
  guard let observed = (scratch.withUnsafeMutableBytes { ring.pollLatest(into: $0, lastSeen: lastSeen) }),
        observed > lastSeen
  else {
    print("CortexSeamBSmoke: the ring did not publish a seq past \(lastSeen); the chain stalled.")
    exit(1)
  }

  let ctLen = scratch.withUnsafeBytes { raw -> Int in
    Int(raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self).littleEndian)
  }
  let ctStart = HarnessConsumer.lengthPrefixBytes
  let ctEnd = ctStart + ctLen
  let tagEnd = ctEnd + HarnessConsumer.tagLength
  guard ctLen > 0, tagEnd <= scratch.count else {
    print("CortexSeamBSmoke: malformed slot at seq \(observed) (ciphertext length \(ctLen)).")
    exit(1)
  }

  let openedPlain: [UInt8]
  do {
    openedPlain = try SessionCrypto.open(
      ciphertext: Array(scratch[ctStart ..< ctEnd]),
      tag: Array(scratch[ctEnd ..< tagEnd]),
      keys: keys,
      direction: .daemonToApp,
      seq: observed
    )
  } catch {
    // FAIL CLOSED (T-10-06-01). The frame is NOT pushed into the accumulator, so the accumulator's own
    // acceptance count cannot have counted it, no window can have formed from it, and the process
    // exits NON-ZERO naming the sequence number.
    //
    // The load-bearing assertion is on the ACCUMULATOR's counters, not on this loop's: `count` is a
    // rolling fill that sits at 32 mid-stream either way, so it would prove nothing. What proves the
    // tampered frame never entered the chain is that `acceptedFrames` stopped one short of the frames
    // produced, and that no window formed for it.
    let acceptedByAccumulator = accumulator.acceptedFrames
    let producedSoFar = Int(observed)
    print("")
    print("CortexSeamBSmoke: AES-GCM open FAILED CLOSED at seq \(observed) - \(error)")
    print("  frames produced up to and including the tampered one = \(producedSoFar)")
    print("  frames the accumulator ACCEPTED                       = \(acceptedByAccumulator)")
    print("  windows_completed                                     = \(windowsCompleted)")
    precondition(
      acceptedByAccumulator == producedSoFar - 1,
      "the tampered frame at seq \(observed) must NOT have been accumulated: the accumulator accepted "
        + "\(acceptedByAccumulator) of \(producedSoFar) produced frames, expected \(producedSoFar - 1)"
    )
    precondition(
      windowsCompleted == max(0, acceptedByAccumulator - (seqLen - 1)),
      "no decode window may have formed from the tampered frame: windows_completed is "
        + "\(windowsCompleted) after \(acceptedByAccumulator) accepted frames"
    )
    print("  The tampered frame was never decrypted, never decoded, and never entered a decode window.")
    exit(1)
  }

  guard let sample = try? SampleCodec.decode(openedPlain), sample.seq == observed else {
    print("CortexSeamBSmoke: decoded Sample did not match the slot's seq \(observed).")
    exit(1)
  }

  let channels = sample.withChannelF16 { Array($0) }
  let result = accumulator.push(seq: observed, channels: channels)
  switch result {
  case .accepted:
    framesAccepted += 1
  case let .duplicate(seq):
    framesDropped += 1
    print("CortexSeamBSmoke: duplicate seq \(seq) refused by the accumulator.")
  case let .gap(expected, got):
    framesDropped += 1
    print("CortexSeamBSmoke: sequence gap - expected \(expected), got \(got); the fill was RESET.")
  case let .badChannelCount(found, expected):
    framesDropped += 1
    print("CortexSeamBSmoke: frame carried \(found) channels, expected \(expected).")
  }

  // ---- A completed window: fill the zero-copy buffer, decode, integrate, encode a pointer report.
  if accumulator.isFull {
    windowsCompleted += 1
    if firstWindow.isEmpty {
      firstWindow = accumulator.window()
      firstWindowClosingSeq = observed
    }

    var decodedVelocity = SIMD2<Float>(0, 0)
    if let spikeBuffer {
      do {
        try accumulator.fill(spikeBuffer)
        windowsFilled += 1
      } catch {
        print("CortexSeamBSmoke: could not fill the decode buffer at seq \(observed) - \(error)")
        exit(1)
      }
      if let decoder {
        do {
          decodedVelocity = try decoder.decode(spikeBuffer)
          decodesSucceeded += 1
        } catch {
          print("CortexSeamBSmoke: NDT1 decode failed at seq \(observed) - \(error)")
          exit(1)
        }
      }
    }

    // Seam B latency clock ENDS here (Plan 10-08): the instant the decode returned. Recording it
    // inside `isFull` is what makes this a PER-COMPLETED-WINDOW number rather than a per-frame one.
    let chainEndNs = Time.machAbsoluteNanoseconds()
    chainLatenciesNs.append(chainEndNs >= chainStartNs ? chainEndNs - chainStartNs : 0)

    // The amplitude-shrinkage pair for this window, AFTER the latency clock stopped so the extra
    // export read is not charged to the chain latency (Plan 10-08).
    if decoder != nil {
      let trueVelocity = (try? export.velocity(at: exportBin(forSeq: observed))) ?? SIMD2<Double>(0, 0)
      decodedSpeedsCmPerS.append(Double((decodedVelocity.x * decodedVelocity.x
          + decodedVelocity.y * decodedVelocity.y).squareRoot()))
      trueSpeedsCmPerS.append((trueVelocity.x * trueVelocity.x + trueVelocity.y * trueVelocity.y)
        .squareRoot())
    }

    // The renderer's integration seam (review D-7, SC#2). With no model the velocity is zero, so the
    // cursor holds - the leg still RAN, which is what is being counted.
    let velocity = CursorVelocity(
      tsNs: sample.tsNs,
      seq: observed,
      vx: Float16(decodedVelocity.x),
      vy: Float16(decodedVelocity.y)
    )
    let position = integrator.integrate(latest: velocity, dt: dt)
    cursorUpdates += 1

    // The HID report ENCODER (review D-7, SC#2). The bytes are discarded: what is measured is that a
    // report was produced for every decoded window (DELIVERY), not that anything was presented.
    let report = BCIInputPointerReport(position: pointerTriple(for: position))
    let encoded = report.encode()
    precondition(encoded.count == 4, "a BCI pointer report is 4 bytes: report id + xyz")
    pointerReportsEncoded += 1
  }

  // D-02 ack-bounce: the consumer signals the producer this seq was consumed.
  ring.ack(seq: observed)
  guard let acked = ring.pollAck(lastSeen: lastSeen), acked == observed else {
    print("CortexSeamBSmoke: the ack-bounce did not report seq \(observed).")
    exit(1)
  }
  lastSeen = observed
}

// A `--tamper` run that reaches here never hit the tampered frame, which means the control did not
// execute and proves nothing.
if tamperRequested {
  print("")
  print("CortexSeamBSmoke: --tamper ran to completion WITHOUT a failed open at seq \(tamperSeq).")
  print("  The negative control did not bite, so it proves nothing. This is a FAILURE.")
  exit(1)
}

// MARK: - Structural assertions (never a measured value - D-09)

precondition(
  framesDropped == 0,
  "frames_dropped must be 0 on a clean run; got \(framesDropped) of \(frameCount) frames "
    + "(accepted \(framesAccepted)). A dropped frame means the chain did not deliver in order."
)
precondition(
  framesAccepted == frameCount,
  "frames_accepted \(framesAccepted) != frames produced \(frameCount)"
)
// The ANTI-VACUITY assertion (review D-7, T-10-06-08). A run that resolved a source and completed
// zero windows has proven nothing about the chain and must FAIL rather than exit 0 with a green tick.
precondition(
  windowsCompleted >= 1,
  "windows_completed is 0 after \(framesAccepted) accepted frames: the chain was never exercised "
    + "through a decode window. \(seqLen) contiguous bins are needed to complete one, so --frames "
    + "must be at least \(seqLen). A run that measures nothing must not report success."
)
precondition(
  windowsCompleted == framesAccepted - (seqLen - 1),
  "windows_completed \(windowsCompleted) != frames_accepted \(framesAccepted) - \(seqLen - 1); "
    + "a rolling window completes once per frame after the first \(seqLen)"
)
precondition(
  cursorUpdates == windowsCompleted,
  "cursor_updates \(cursorUpdates) != windows_completed \(windowsCompleted): the renderer's "
    + "integration seam did not receive every decoded window"
)
precondition(
  pointerReportsEncoded == windowsCompleted,
  "pointer_reports_encoded \(pointerReportsEncoded) != windows_completed \(windowsCompleted): the "
    + "HID report encoder did not receive every decoded window"
)
if decoder != nil {
  precondition(
    decodesSucceeded == windowsCompleted,
    "decodes_succeeded \(decodesSucceeded) != windows_completed \(windowsCompleted): a model was "
      + "supplied, so every completed window must have been decoded by it"
  )
}

precondition(
  doorbellWakes == frameCount,
  "doorbell_wakes \(doorbellWakes) != \(frameCount): a frame was written without a delivered wake"
)

// End-to-end PAYLOAD INTEGRITY: the newest bin of the first completed window must be, to Float16
// precision, the export bin the producer read for the seq that closed it. This is what proves the
// bytes that left the producer are the bytes the decoder saw, through the seal, the ring and the
// accumulator, rather than a plausible-looking window assembled from the wrong bins.
do {
  let expectedBin = try binValues(forSeq: firstWindowClosingSeq)
  precondition(
    firstWindow.count == seqLen * channelCount,
    "the first completed window is \(firstWindow.count) values, expected \(seqLen * channelCount)"
  )
  let newestBase = (seqLen - 1) * channelCount
  for channel in 0 ..< channelCount {
    let got = firstWindow[newestBase + channel]
    let want = expectedBin[channel]
    precondition(
      got == want,
      "payload integrity: window bin \(seqLen - 1) channel \(channel) is \(got), but export bin "
        + "\(exportBin(forSeq: firstWindowClosingSeq)) holds \(want). The bytes changed in flight."
    )
  }
} catch {
  print("CortexSeamBSmoke: could not re-read the export for the integrity check - \(error)")
  exit(1)
}

// MARK: - Output

struct SeamBReport: Encodable {
  let schemaVersion: Int
  let seam: String
  let boundary: String
  let processBoundary: String
  let dataSource: String
  let sessionId: String
  let exportSidecarSha256: String
  let framesAccepted: Int
  let framesDropped: Int
  let windowsCompleted: Int
  let windowsFilled: Int
  let decodesSucceeded: Int
  let cursorUpdates: Int
  let pointerReportsEncoded: Int
  let doorbellWakes: Int
  /// Plan 10-08: the per-completed-window chain latency distribution, nearest-rank over
  /// `LatencyHistogram` - the SAME percentile math Seam A uses, so the two numbers differ only by the
  /// boundary they span and not by how the percentile was taken. `count` is `windows_completed`.
  let p50Ns: UInt64
  let p99Ns: UInt64
  let maxNs: UInt64
  let count: Int
  let latencyBoundary: String
  let latencyCaveat: String
  /// Plan 10-08: the `velocity_amplitude_shrinkage` inputs and both ratio conventions, in cm/s.
  let velocityAmplitude: [String: Double]
  let velocityAmplitudeNote: String
  let modelBacked: Bool
  let spikeBufferBacked: Bool
  let aesGcm: String
  let device: String
  let status: String
  let env: [String: String]
  let disclosure: String
  let notComparableTo: String

  /// The JSON keys are snake_case and LOAD-BEARING: this artifact is read back by
  /// `Decoder/tests/test_real_replay_schema.py` and by the Tools/scripts policy gates, which match the
  /// key strings literally. A key rename breaks them. CodingKeys keeps Swift camelCase (SwiftLint
  /// identifier_name) and the wire format snake_case (byte identity) at the same time. Do not remove.
  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case seam
    case boundary
    case processBoundary = "process_boundary"
    case dataSource = "data_source"
    case sessionId = "session_id"
    case exportSidecarSha256 = "export_sidecar_sha256"
    case framesAccepted = "frames_accepted"
    case framesDropped = "frames_dropped"
    case windowsCompleted = "windows_completed"
    case windowsFilled = "windows_filled"
    case decodesSucceeded = "decodes_succeeded"
    case cursorUpdates = "cursor_updates"
    case pointerReportsEncoded = "pointer_reports_encoded"
    case doorbellWakes = "doorbell_wakes"
    case p50Ns = "p50_ns"
    case p99Ns = "p99_ns"
    case maxNs = "max_ns"
    case count
    case latencyBoundary = "latency_boundary"
    case latencyCaveat = "latency_caveat"
    case velocityAmplitude = "velocity_amplitude"
    case velocityAmplitudeNote = "velocity_amplitude_note"
    case modelBacked = "model_backed"
    case spikeBufferBacked = "spike_buffer_backed"
    case aesGcm = "aes_gcm"
    case device
    case status
    case env
    case disclosure
    case notComparableTo = "not_comparable_to"
  }
}

// MARK: - The amplitude-shrinkage measurement (Plan 10-08, 10-PREREGISTRATION section 14)

/// Nearest-rank percentile over Doubles: `rank = ceil(p * n)` clamped to `[1, n]`, the SAME convention
/// `LatencyHistogram` uses, so the two distributions in this artifact are summarised the same way.
func percentile(_ samples: [Double], _ p: Double) -> Double {
  guard !samples.isEmpty else { return 0 }
  let sorted = samples.sorted()
  let clamped = Swift.min(1.0, Swift.max(0.0, p))
  let rank = Int((clamped * Double(sorted.count)).rounded(.up))
  return sorted[Swift.min(sorted.count - 1, Swift.max(0, rank - 1))]
}

func mean(_ samples: [Double]) -> Double {
  samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
}

let decodedMeanSpeed = mean(decodedSpeedsCmPerS)
let trueMeanSpeed = mean(trueSpeedsCmPerS)
let decodedP95Speed = percentile(decodedSpeedsCmPerS, 0.95)
let trueP95Speed = percentile(trueSpeedsCmPerS, 0.95)
// RATIO OF MEANS and RATIO OF P95s, not the mean/p95 of a per-window quotient. Stated because the two
// conventions differ and the choice must not be inferable only from the code: a per-window quotient
// diverges whenever the true speed passes through zero, which it does at every reach reversal, so its
// mean is dominated by near-zero denominators and measures nothing about amplitude. `realized_gain` in
// 10-refit-real.json takes the ratio of means for the same reason.
let amplitudeMeanRatio = trueMeanSpeed > 0 ? decodedMeanSpeed / trueMeanSpeed : 0
let amplitudeP95Ratio = trueP95Speed > 0 ? decodedP95Speed / trueP95Speed : 0

/// Plan 10-08: reuse the CortexDecoder nearest-rank percentile math rather than duplicating it, which
/// is the same helper Seam A reaches through `GlassToGlassTimer.histogram`. The device annotation names
/// the seam so a stray copy of this histogram cannot be mistaken for a glass-to-glass number.
let chainHistogram = LatencyHistogram(
  samplesNs: chainLatenciesNs,
  deviceAnnotation: "M5-Pro-seam-B-in-process-corroborating"
)
precondition(
  chainHistogram.count == windowsCompleted,
  "the Seam B latency sample count \(chainHistogram.count) != windows_completed \(windowsCompleted): "
    + "every completed window must contribute exactly one sample"
)

let sidecarDigest: String
do {
  sidecarDigest = try SHA256.hash(data: Data(contentsOf: source.url))
    .map { String(format: "%02x", $0) }
    .joined()
} catch {
  print("CortexSeamBSmoke: could not re-read the sidecar to digest it - \(error)")
  exit(1)
}

#if compiler(>=6.2)
  let compilerLabel = ">=6.2"
#else
  let compilerLabel = "<6.2"
#endif

let payload = SeamBReport(
  schemaVersion: 1,
  seam: "B",
  boundary: "export bin -> AES-GCM seal -> shm ring -> doorbell -> decrypt -> ordering -> 32-bin "
    + "accumulation -> SpikeInputBuffer fill -> NDT1 decode -> cursor integration -> HID pointer "
    + "report encode",
  processBoundary: "in_process",
  dataSource: source.kind.rawValue,
  sessionId: export.sidecar.sessionId,
  exportSidecarSha256: sidecarDigest,
  framesAccepted: framesAccepted,
  framesDropped: framesDropped,
  windowsCompleted: windowsCompleted,
  windowsFilled: windowsFilled,
  decodesSucceeded: decodesSucceeded,
  cursorUpdates: cursorUpdates,
  pointerReportsEncoded: pointerReportsEncoded,
  doorbellWakes: doorbellWakes,
  p50Ns: chainHistogram.p50,
  p99Ns: chainHistogram.p99,
  maxNs: chainHistogram.max,
  count: chainHistogram.count,
  latencyBoundary: "one completed decode window, timed from the top of the producer iteration "
    + "(immediately BEFORE the export bin is read) to the instant the NDT1 decode RETURNS on the "
    + "consumer side. Spans export read -> AES-GCM seal -> shm ring write -> doorbell -> poll -> "
    + "decrypt -> FlatBuffers decode -> ordering -> 32-bin accumulation -> SpikeInputBuffer fill -> "
    + "NDT1 decode. Excludes the cursor integration and the HID encode that follow.",
  latencyCaveat: "SINGLE-PROCESS LOCK-STEP. Both clock reads are Time.machAbsoluteNanoseconds() on "
    + "the same mach_absolute_time timebase in the same thread, so the arithmetic is sound, but no "
    + "cross-process wakeup, context switch or scheduling delay is included because there is no "
    + "second process (process_boundary = in_process). Read this as a FLOOR on what the same chain "
    + "would cost across a real process boundary, never as an estimate of it. It is not comparable "
    + "to Seam A and not comparable to the Phase-8 number.",
  velocityAmplitude: [
    "n": Double(decodedSpeedsCmPerS.count),
    "decoded_mean_speed_cm_s": decodedMeanSpeed,
    "true_mean_speed_cm_s": trueMeanSpeed,
    "decoded_p95_speed_cm_s": decodedP95Speed,
    "true_p95_speed_cm_s": trueP95Speed,
    "mean_ratio": amplitudeMeanRatio,
    "p95_ratio": amplitudeP95Ratio
  ],
  velocityAmplitudeNote: "decoded speed is |v| straight off NeuralDecoder.decode in cm/s; true "
    + "speed is the export's own binned cursor velocity magnitude for the SAME bin, in the cm/s the "
    + "sidecar declares. mean_ratio is mean(decoded)/mean(true) and p95_ratio is p95(decoded)/"
    + "p95(true) - RATIOS OF SUMMARIES, not summaries of a per-window quotient, because that quotient "
    + "diverges at every reach reversal where the true speed passes through zero. A ratio below 1 is "
    + "amplitude shrinkage toward the mean. Empty (n = 0) when no model was supplied.",
  modelBacked: decoder != nil,
  spikeBufferBacked: spikeBuffer != nil,
  aesGcm: "applied to every frame; no bypass path exists",
  device: "Apple M5 Pro (arm64)",
  status: "corroborating",
  env: [
    "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "swift_compiler": compilerLabel,
    "bin_ms": String(export.sidecar.binMs),
    "seq_len": String(seqLen),
    "channels": String(channelCount),
    "frames_requested": String(requestedFrames),
    "ring_slot_stride": String(ring.layout.slotStride),
    "ring_depth": String(ring.layout.depth),
    "source_path": source.url.lastPathComponent,
    "source_reason": source.why
  ],
  // The fixture carries its OWN disclosure, which contains the literal `synthetic fixture`; a real
  // export gets the pre-registered open-loop string. No number from this file may ever be presented
  // as a real-data result without the `data_source` field beside it.
  disclosure: source.kind == .syntheticFixture ? export.sidecar.disclosure : openLoopDisclosure,
  notComparableTo: "the Phase-8 glass-to-glass p99 and the Plan 10-04 Seam A p99. Seam B is a "
    + "strictly WIDER boundary (10-PREREGISTRATION section 9), and the Phase-8 number had no IPC leg "
    + "and was not model-backed (10-RESEARCH Correction 2)."
)

try? FileManager.default.createDirectory(
  at: outputURL.deletingLastPathComponent(),
  withIntermediateDirectories: true
)
do {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  try encoder.encode(payload).write(to: outputURL)
} catch {
  print("CortexSeamBSmoke: warning - failed to write \(outputURL.path): \(error)")
}

print("")
print("  frames_accepted         = \(framesAccepted)   frames_dropped = \(framesDropped)")
print("  windows_completed       = \(windowsCompleted)   windows_filled = \(windowsFilled)")
print("  decodes_succeeded       = \(decodesSucceeded)   (model_backed = \(decoder != nil))")
print("  cursor_updates          = \(cursorUpdates)")
print("  pointer_reports_encoded = \(pointerReportsEncoded)")
print("  doorbell_wakes          = \(doorbellWakes)")
print("  payload integrity       = the newest bin of the first window matches export bin "
  + "\(exportBin(forSeq: firstWindowClosingSeq)) exactly")
print("  AES-GCM                 = applied to every frame; there is no bypass path")
print("")
print("  Seam B chain latency, per completed window (Plan 10-08), n = \(chainHistogram.count):")
print("    p50 = \(chainHistogram.p50) ns  (\(String(format: "%.3f", Double(chainHistogram.p50) / 1_000_000)) ms)")
print("    p99 = \(chainHistogram.p99) ns  (\(String(format: "%.3f", Double(chainHistogram.p99) / 1_000_000)) ms)")
print("    max = \(chainHistogram.max) ns  (\(String(format: "%.3f", Double(chainHistogram.max) / 1_000_000)) ms)")
print("    \(payload.latencyCaveat)")
print("")
if decoder != nil {
  print("  Velocity amplitude, decoded vs true, over \(decodedSpeedsCmPerS.count) windows (cm/s):")
  print("    mean:  decoded \(decodedMeanSpeed)   true \(trueMeanSpeed)   ratio \(amplitudeMeanRatio)")
  print("    p95:   decoded \(decodedP95Speed)   true \(trueP95Speed)   ratio \(amplitudeP95Ratio)")
  print("    \(payload.velocityAmplitudeNote)")
  print("")
}

print("  data_source: \(source.kind.rawValue)")
print("  disclosure: \(payload.disclosure)")
print("  \(payload.notComparableTo)")
print("  D-09: this smoke asserts STRUCTURE only. It compares nothing against any budget and emits")
print("  no pass/fail field; a clean run exits 0 whatever the counters are.")
print("  wrote: \(outputURL.path)")

exit(0)
