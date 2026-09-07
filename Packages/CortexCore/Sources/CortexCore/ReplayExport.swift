// ReplayExport - Phase 10 (RD-08, D-06): the ONE Swift reader of the replay export.
//
// The WRITER is `Decoder/src/ndt1/replay_export.py`. The two are a CROSS-LANGUAGE CONTRACT, and the
// committed `Decoder/tests/fixtures/tiny_replay.{bin,json}` fixture is what proves they agree: the
// Python side writes those bytes, `ReplayExportTests` reads them here, and a layout change on either
// side fails that test rather than silently corrupting a measurement.
//
// It lives in `CortexCore` because BOTH `CortexDemo` (the Seam A replay loop, Plan 10-04) and
// `CortexReFITBench` (the real-data ablation, Plan 10-05) consume the export. A second reader would be
// a silent drift hole - the same reasoning D-06 applies to binning, which stays in `ndt1` for exactly
// this reason rather than being re-implemented in Swift.
//
// ## The format (pinned by Plan 10-02; little-endian, row-major, NO header)
//
//     per bin: spikes 96 x Float32 | velocity 2 x Float64 | target 2 x Float64 | t_start 1 x Float64
//     recordBytes = 96*4 + 2*8 + 2*8 + 8 = 424
//
// The header IS the sidecar. That is what lets this reader BOUND the file before reading it: the
// sidecar's declared `n_bins * 424` is checked against the binary's actual byte length on disk, and
// the check happens BEFORE `Data(contentsOf:)` maps anything (ASVS V5 - never size an allocation from
// an untrusted header). See `init(sidecarURL:)`, step 10 versus step 11.
//
// ## Validation posture
// Explicit typed refusals, never a silent truncation and never a fallback to empty data - the
// `SampleCodec` discipline (`badChannelCount` / `malformedBuffer`) applied to a new format. An absent
// export throws `.notFound`; it does NOT quietly become synthetic data (ASVS V12/V14, and the
// Pattern-2 defect Plan 10-04 exists to remove).
import Foundation

/// Every way the replay export can be refused. Explicit cases so a caller (and a test) can name which
/// invariant bit, rather than discovering a generic failure.
public nonisolated enum ReplayExportError: Error, Sendable, Equatable {
  /// The sidecar or the binary it names is not on disk. Fail closed - never substitute empty data.
  case notFound(path: String)
  /// The sidecar is not readable JSON in the expected shape; carries the underlying description.
  case malformedSidecar(reason: String)
  /// `schema_version` is not the version this reader implements.
  case unsupportedSchema(found: Int, expected: Int)
  /// `n_channels` is not the 96-channel Indy contract (DEC-02).
  case badChannelCount(found: Int, expected: Int)
  /// `record_bytes` is not the pinned 424-byte record.
  case badRecordSize(found: Int, expected: Int)
  /// A provenance digest field is not 64 lowercase hex characters.
  case malformedProvenance(field: String)
  /// `binary_path` resolves outside the sidecar's own directory (ASVS V12 - symlink escape).
  case pathEscape(declared: String, resolvedParent: String)
  /// The sidecar's declared byte length disagrees with the file on disk (ASVS V5).
  case sizeMismatch(declared: Int, actual: Int)
  /// A bin index (or a window that would start before bin 0) is outside the export.
  case outOfRange(index: Int, count: Int)
}

/// The `cursor_bbox_square` workspace-to-grid mapping the export was built on
/// (10-PREREGISTRATION section 3, as amended by section 3a: the box is the recorded `cursor_pos`
/// track). Carried so a consumer can convert a decoded cm/s velocity into grid units without
/// re-deriving the box - the drift hole 10-03a closed on the Python side.
public nonisolated struct ReplayWorkspace: Sendable, Equatable, Decodable {
  public let normalisation: String
  public let xMinMm: Double
  public let xMaxMm: Double
  public let yMinMm: Double
  public let yMaxMm: Double
  public let centreXMm: Double
  public let centreYMm: Double
  public let sideMm: Double
  public let gridRows: Int
  public let gridCols: Int
  public let cellMm: Double
  public let acquisitionRadiusMm: Double
  public let gridUnitsPerCm: Double

  /// Explicit snake_case mapping rather than a key-decoding strategy, so every mapped key is greppable
  /// from this file alone (the same reason the Python side pins `SIDECAR_KEYS` as a literal tuple).
  private enum CodingKeys: String, CodingKey {
    case normalisation
    case xMinMm = "x_min_mm"
    case xMaxMm = "x_max_mm"
    case yMinMm = "y_min_mm"
    case yMaxMm = "y_max_mm"
    case centreXMm = "centre_x_mm"
    case centreYMm = "centre_y_mm"
    case sideMm = "side_mm"
    case gridRows = "grid_rows"
    case gridCols = "grid_cols"
    case cellMm = "cell_mm"
    case acquisitionRadiusMm = "acquisition_radius_mm"
    case gridUnitsPerCm = "grid_units_per_cm"
  }
}

/// The discrete target grid the recorded session actually presented. `distinctTargets` is the N the
/// task ran at (64 for `indy_20160630_01`), which 10-PREREGISTRATION section 6 requires be reported
/// beside any counterfactual 900-cell score.
public nonisolated struct ReplayTargetGrid: Sendable, Equatable, Decodable {
  public let distinctTargets: Int
  public let pitchMm: Double
  public let log2NTask: Double

  private enum CodingKeys: String, CodingKey {
    case distinctTargets = "distinct_targets"
    case pitchMm = "pitch_mm"
    case log2NTask = "log2_n_task"
  }
}

/// The export's JSON sidecar: the header, the provenance and the workspace mapping, in one file a
/// human and a gate read the same way (D-06). The key set mirrors `ndt1.replay_export.SIDECAR_KEYS`.
public nonisolated struct ReplaySidecar: Sendable, Equatable, Decodable {
  public let schemaVersion: Int
  public let sessionId: String
  public let sourceSha256: String
  public let manifestPath: String
  public let binMs: Double
  public let nBins: Int
  public let nChannels: Int
  public let recordBytes: Int
  public let binaryPath: String
  public let binarySha256: String
  public let lagBins: Int
  public let lagMs: Double
  public let behaviorHz: Double
  public let units: [String: String]
  public let frameScaleMmPerCm: Double
  public let workspace: ReplayWorkspace
  public let targetGrid: ReplayTargetGrid
  public let trials: Int
  public let encoderCheckpointSha256: String
  public let velocityCheckpointSha256: String
  public let env: [String: String]
  public let disclosure: String

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case sessionId = "session_id"
    case sourceSha256 = "source_sha256"
    case manifestPath = "manifest_path"
    case binMs = "bin_ms"
    case nBins = "n_bins"
    case nChannels = "n_channels"
    case recordBytes = "record_bytes"
    case binaryPath = "binary_path"
    case binarySha256 = "binary_sha256"
    case lagBins = "lag_bins"
    case lagMs = "lag_ms"
    case behaviorHz = "behavior_hz"
    case units
    case frameScaleMmPerCm = "frame_scale_mm_per_cm"
    case workspace
    case targetGrid = "target_grid"
    case trials
    case encoderCheckpointSha256 = "encoder_checkpoint_sha256"
    case velocityCheckpointSha256 = "velocity_checkpoint_sha256"
    case env
    case disclosure
  }
}

/// A validated, memory-mapped view of one replay export.
///
/// `nonisolated` + `Sendable`: every stored property is an immutable value (the decoded sidecar, the
/// resolved URL, and the mapped `Data`), so it can be read from any isolation context - the MainActor
/// bench, the MainActor demo pipeline, or a nonisolated consumer.
public final nonisolated class ReplayExport: Sendable {
  // MARK: - The pinned format

  /// Bytes per record: 96 Float32 spike counts, 2 Float64 velocity, 2 Float64 target, 1 Float64 start.
  /// The same fact `ndt1.replay_export.RECORD_BYTES` states on the writing side.
  public static let recordBytes = 424
  /// The only sidecar schema this reader implements.
  public static let schemaVersion = 1
  /// The 96-channel Indy contract (DEC-02).
  public static let expectedChannels = 96

  /// Byte offsets of each field WITHIN one 424-byte record.
  private static let spikesOffset = 0
  private static let velocityOffset = 384 // 96 * 4
  private static let targetOffset = 400 // 384 + 2 * 8
  private static let binStartOffset = 416 // 400 + 2 * 8

  // MARK: - State

  /// The parsed sidecar: the header, the provenance triple and the workspace mapping.
  public let sidecar: ReplaySidecar
  /// The binary the sidecar named, with symlinks resolved and proven to sit beside the sidecar.
  public let binaryURL: URL

  /// The mapped record bytes. Mapped only AFTER every header check passed (see `init`).
  private let bytes: Data

  /// Number of 20 ms bins in the export.
  public var binCount: Int {
    sidecar.nBins
  }

  /// Recording channels per bin (96).
  public var channelCount: Int {
    sidecar.nChannels
  }

  // MARK: - Init

  /// Validate a sidecar and map the binary it names.
  ///
  /// The order below is load-bearing and is the ASVS V5 requirement stated concretely: EVERY check
  /// runs before any file bytes are loaded, and the LAST of them compares the sidecar's declared
  /// `n_bins * 424` against the binary's actual size on disk. `Data(contentsOf:)` is reached only on
  /// step 11, so a header claiming a size the file does not support can never size a mapping.
  ///
  ///  1. the sidecar exists
  ///  2. it decodes as JSON in the expected shape
  ///  3. `schema_version == 1`
  ///  4. `n_channels == 96`
  ///  5. `record_bytes == 424`
  ///  6. `n_bins > 0` (and cannot overflow the declared byte length)
  ///  7. `source_sha256` is 64 lowercase hex
  ///  8. `binary_path` resolves to a sibling of the sidecar (no symlink or absolute-path escape)
  ///  9. the binary exists
  /// 10. its size on disk equals `n_bins * 424`
  /// 11. ONLY NOW map the bytes
  ///
  /// Every branch below is one of those eleven checks, so the complexity IS the check count.
  /// Extracting them would scatter a deliberately linear, numbered, auditable sequence across
  /// helpers and make it harder to confirm that no step was skipped or reordered.
  public init(sidecarURL: URL) throws(ReplayExportError) { // swiftlint:disable:this function_body_length cyclomatic_complexity
    let manager = FileManager.default

    // 1. The sidecar exists. An absent export FAILS CLOSED; it never becomes synthetic data.
    guard manager.fileExists(atPath: sidecarURL.path) else {
      throw .notFound(path: sidecarURL.path)
    }

    // 2. It decodes. The refusal carries the underlying description so a schema drift is legible.
    let sidecarData: Data
    do {
      sidecarData = try Data(contentsOf: sidecarURL)
    } catch {
      throw .malformedSidecar(reason: "could not read \(sidecarURL.lastPathComponent): \(error)")
    }
    let decoded: ReplaySidecar
    do {
      decoded = try JSONDecoder().decode(ReplaySidecar.self, from: sidecarData)
    } catch {
      throw .malformedSidecar(reason: String(describing: error))
    }

    // 3-5. The three pinned shape constants.
    guard decoded.schemaVersion == Self.schemaVersion else {
      throw .unsupportedSchema(found: decoded.schemaVersion, expected: Self.schemaVersion)
    }
    guard decoded.nChannels == Self.expectedChannels else {
      throw .badChannelCount(found: decoded.nChannels, expected: Self.expectedChannels)
    }
    guard decoded.recordBytes == Self.recordBytes else {
      throw .badRecordSize(found: decoded.recordBytes, expected: Self.recordBytes)
    }

    // 6. A positive bin count that cannot overflow the declared byte length. The overflow guard is
    //    the same threat as the size check: an `n_bins` near Int.max would wrap `n_bins * 424` into a
    //    small positive number that a truncated file would then "match".
    guard decoded.nBins > 0 else {
      throw .malformedSidecar(reason: "n_bins must be positive")
    }
    guard decoded.nBins <= Int.max / Self.recordBytes else {
      throw .malformedSidecar(reason: "n_bins \(decoded.nBins) overflows the declared byte length")
    }

    // 7. Provenance shape: `^[0-9a-f]{64}$`. Checked as bytes rather than through a regex so the rule
    //    is exact and case-sensitive - the manifest's digests are lowercase, and tolerating a second
    //    spelling is how one digest becomes two.
    guard Self.isLowercaseHexDigest(decoded.sourceSha256) else {
      throw .malformedProvenance(field: "source_sha256")
    }

    // 8. The binary must resolve to a SIBLING of the sidecar (ASVS V12). `resolvingSymlinksInPath`
    //    is applied to both sides so a symlink pointing out of the export directory, and an absolute
    //    `binary_path`, are refused identically.
    let sidecarResolved = sidecarURL.resolvingSymlinksInPath().standardizedFileURL
    let sidecarParent = sidecarResolved.deletingLastPathComponent().path
    let declaredURL = URL(
      fileURLWithPath: decoded.binaryPath,
      relativeTo: sidecarURL.deletingLastPathComponent()
    ).absoluteURL
    let resolvedBinary = declaredURL.resolvingSymlinksInPath().standardizedFileURL
    let binaryParent = resolvedBinary.deletingLastPathComponent().path
    guard binaryParent == sidecarParent else {
      throw .pathEscape(declared: decoded.binaryPath, resolvedParent: binaryParent)
    }

    // 9. The binary exists.
    guard manager.fileExists(atPath: resolvedBinary.path) else {
      throw .notFound(path: resolvedBinary.path)
    }

    // 10. Its size on disk equals what the header declares. `attributesOfItem` does not follow
    //     symlinks, which is why the RESOLVED path is used - otherwise a symlink's own size would be
    //     compared against the record count.
    let attributes: [FileAttributeKey: Any]
    do {
      attributes = try manager.attributesOfItem(atPath: resolvedBinary.path)
    } catch {
      throw .notFound(path: resolvedBinary.path)
    }
    guard let actualSize = attributes[.size] as? Int else {
      throw .malformedSidecar(reason: "could not stat \(resolvedBinary.lastPathComponent)")
    }
    let declaredSize = decoded.nBins * Self.recordBytes
    guard actualSize == declaredSize else {
      throw .sizeMismatch(declared: declaredSize, actual: actualSize)
    }

    // 11. ONLY NOW are the bytes mapped. Everything above bounded this mapping against the file.
    do {
      bytes = try Data(contentsOf: resolvedBinary, options: .mappedIfSafe)
    } catch {
      throw .notFound(path: resolvedBinary.path)
    }
    sidecar = decoded
    binaryURL = resolvedBinary
  }

  /// Resolve the export's sidecar from `CORTEX_REPLAY_EXPORT`. Absent or empty means NIL, and a
  /// caller that gets nil must SKIP - never fall back to synthetic data and report it as real
  /// (ASVS V14; D-07's clean-clone idiom).
  public static func sidecarURLFromEnvironment() -> URL? {
    guard let raw = ProcessInfo.processInfo.environment["CORTEX_REPLAY_EXPORT"], !raw.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: raw)
  }

  // MARK: - Reads

  /// The `length`-bin spike window ENDING at `bin` (inclusive), in BIN-MAJOR order:
  /// `window[binOffset * channels + channel]` - byte-for-byte the layout `SyntheticSpikeSource.window`
  /// emits, so the two sources are interchangeable at the `SpikeWindowSource` seam.
  ///
  /// The Float32 counts on disk are converted to Float16 at this boundary, which is the type the NDT1
  /// `spikes` input consumes.
  public func window(endingAt bin: Int, length: Int) throws(ReplayExportError) -> [Float16] {
    guard length > 0 else { throw .outOfRange(index: length, count: binCount) }
    guard bin >= 0, bin < binCount else { throw .outOfRange(index: bin, count: binCount) }
    let first = bin - length + 1
    guard first >= 0 else { throw .outOfRange(index: first, count: binCount) }

    let channels = channelCount
    var out = [Float16](repeating: 0, count: length * channels)
    bytes.withUnsafeBytes { raw in
      for row in 0 ..< length {
        let recordBase = (first + row) * Self.recordBytes + Self.spikesOffset
        for channel in 0 ..< channels {
          let offset = recordBase + channel * MemoryLayout<Float32>.size
          out[row * channels + channel] = Float16(Self.float32(in: raw, at: offset))
        }
      }
    }
    return out
  }

  /// The true binned cursor velocity paired with `bin` (cm/s), exactly as stored.
  public func velocity(at bin: Int) throws(ReplayExportError) -> SIMD2<Double> {
    try checkBounds(bin)
    let base = bin * Self.recordBytes + Self.velocityOffset
    return SIMD2<Double>(double(at: base), double(at: base + MemoryLayout<Float64>.size))
  }

  /// The session's real target position for `bin` (mm), exactly as stored.
  public func target(at bin: Int) throws(ReplayExportError) -> SIMD2<Double> {
    try checkBounds(bin)
    let base = bin * Self.recordBytes + Self.targetOffset
    return SIMD2<Double>(double(at: base), double(at: base + MemoryLayout<Float64>.size))
  }

  /// The session-clock start time of `bin` in seconds, exactly as stored.
  public func binStart(at bin: Int) throws(ReplayExportError) -> Double {
    try checkBounds(bin)
    return double(at: bin * Self.recordBytes + Self.binStartOffset)
  }

  // MARK: - Byte-level helpers

  private func checkBounds(_ bin: Int) throws(ReplayExportError) {
    guard bin >= 0, bin < binCount else { throw .outOfRange(index: bin, count: binCount) }
  }

  /// Read one little-endian Float64 at an absolute byte offset.
  private func double(at offset: Int) -> Double {
    bytes.withUnsafeBytes { raw in
      // `loadUnaligned` throughout: a record's Float64 fields begin at 424*bin + 384/392/400/408/416,
      // and 424 is not a multiple of 8, so those offsets are NOT 8-aligned for odd bins. An aligned
      // `load` there is undefined behaviour. Same reasoning for the Float32 spikes, whose element k
      // begins at 424*bin + 4*k.
      let bits = raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
      return Double(bitPattern: UInt64(littleEndian: bits))
    }
  }

  /// Read one little-endian Float32 at an absolute byte offset inside an already-open raw view.
  private static func float32(in raw: UnsafeRawBufferPointer, at offset: Int) -> Float {
    let bits = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
    return Float(bitPattern: UInt32(littleEndian: bits))
  }

  /// `^[0-9a-f]{64}$`, checked over UTF-8 bytes so the rule is exact and case-sensitive.
  private static func isLowercaseHexDigest(_ value: String) -> Bool {
    let utf8 = value.utf8
    guard utf8.count == 64 else { return false }
    return utf8.allSatisfy { byte in
      (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
        || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "f"))
    }
  }
}
