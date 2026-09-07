@testable import CortexCore

// ReplayExportTests - Phase 10 (RD-08, Plan 10-04): the CROSS-LANGUAGE contract test for the D-06
// replay export.
//
// This is deliberately a cross-language contract test. The fixture
// `Decoder/tests/fixtures/tiny_replay.{bin,json}` is written by PYTHON
// (`Decoder/scripts/make_tiny_replay.py` through `ndt1.replay_export.write_export`) and read here by
// SWIFT. A layout change on either side therefore fails HERE, in a cheap unit test, rather than
// inside a measurement whose numbers would silently be garbage. The fixture is committed precisely so
// this coverage survives on a clean clone with no dataset and no `Decoder/exports/`.
//
// The mutation controls (truncation, schema bump, channel count, record size, digest shape, symlink
// escape) all COPY the fixture into a temporary directory and mutate the copy. The committed bytes are
// never touched.
import Foundation
import Testing

@Suite("RD-08 / D-06: the Swift reader of the Python-written replay export")
@MainActor
struct ReplayExportTests {
  // MARK: - Fixture resolution

  /// The repo root, resolved from this file's own path. `#filePath` is
  /// `<repo>/Packages/CortexCore/Tests/CortexCoreTests/ReplayExportTests.swift`, so five parent hops
  /// (CortexCoreTests, Tests, CortexCore, Packages, repo) land on the repo root.
  static var repoRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // CortexCoreTests
      .deletingLastPathComponent() // Tests
      .deletingLastPathComponent() // CortexCore (package root)
      .deletingLastPathComponent() // Packages
      .deletingLastPathComponent() // repo root
  }

  /// The committed synthetic fixture sidecar (Plan 10-02): 256 bins x 424 bytes = 108,544 bytes.
  static var fixtureSidecar: URL {
    repoRoot.appendingPathComponent("Decoder/tests/fixtures/tiny_replay.json")
  }

  static var fixtureBinary: URL {
    repoRoot.appendingPathComponent("Decoder/tests/fixtures/tiny_replay.bin")
  }

  /// Copy the committed fixture pair into a fresh temporary directory and return that directory.
  /// Every mutation control works on this copy so the committed bytes stay pristine.
  static func stageFixture() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("cortex-replay-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: fixtureBinary, to: dir.appendingPathComponent("tiny_replay.bin"))
    try FileManager.default.copyItem(at: fixtureSidecar, to: dir.appendingPathComponent("tiny_replay.json"))
    return dir
  }

  /// Rewrite one top-level key of a staged sidecar. This is the faithful threat: a hand-edited or
  /// substituted export on disk, not a writer talked into emitting one (the Plan 10-02 `_tamper` idiom).
  static func tamper(_ dir: URL, key: String, value: Any) throws -> URL {
    let sidecarURL = dir.appendingPathComponent("tiny_replay.json")
    let data = try Data(contentsOf: sidecarURL)
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CocoaError(.propertyListReadCorrupt)
    }
    object[key] = value
    let rewritten = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try rewritten.write(to: sidecarURL)
    return sidecarURL
  }

  /// Read one Float32 spike count straight out of the raw fixture bytes at
  /// `424 * bin + 4 * channel`, with NO help from `ReplayExport`. This is what makes the ordering
  /// assertion a real cross-check of the layout rather than a restatement of the reader's own math.
  static func rawSpike(bin: Int, channel: Int) throws -> Float {
    let bytes = try Data(contentsOf: fixtureBinary)
    let offset = ReplayExport.recordBytes * bin + MemoryLayout<Float32>.size * channel
    let bits = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    return Float(bitPattern: UInt32(littleEndian: bits))
  }

  // MARK: Test 1 - the committed Python-written fixture reads

  @Test("Test 1: the committed Python-written fixture reads with the declared shape")
  func readsTheCommittedFixture() throws {
    let export = try ReplayExport(sidecarURL: Self.fixtureSidecar)
    #expect(export.binCount == 256, "the committed fixture is 256 bins (108,544 bytes / 424)")
    #expect(export.channelCount == 96, "the 96-channel Indy contract (DEC-02)")
    #expect(export.sidecar.schemaVersion == ReplayExport.schemaVersion)
    #expect(export.sidecar.recordBytes == ReplayExport.recordBytes)
    #expect(export.sidecar.sessionId == "tiny_replay_synthetic")
    #expect(export.sidecar.workspace.normalisation == "cursor_bbox_square")
    #expect(export.sidecar.targetGrid.distinctTargets == 4)
    #expect(export.sidecar.lagBins == 1)

    let window = try export.window(endingAt: 31, length: 32)
    #expect(window.count == 32 * 96, "a 32-bin window over 96 channels is 3072 fp16 values")
  }

  // MARK: Test 2 - a size mismatch is refused BEFORE the bytes are loaded

  @Test("Test 2: a one-byte truncation throws .sizeMismatch (checked before any read)")
  func refusesASizeMismatch() throws {
    let dir = try Self.stageFixture()
    let binaryURL = dir.appendingPathComponent("tiny_replay.bin")
    let handle = try FileHandle(forWritingTo: binaryURL)
    try handle.truncate(atOffset: 108_544 - 1)
    try handle.close()

    #expect(throws: ReplayExportError.sizeMismatch(declared: 256 * 424, actual: 108_543)) {
      _ = try ReplayExport(sidecarURL: dir.appendingPathComponent("tiny_replay.json"))
    }
  }

  // MARK: Test 3 - a schema bump is refused

  @Test("Test 3: schema_version != 1 throws .unsupportedSchema")
  func refusesASchemaBump() throws {
    let dir = try Self.stageFixture()
    let sidecarURL = try Self.tamper(dir, key: "schema_version", value: 2)
    #expect(throws: ReplayExportError.unsupportedSchema(found: 2, expected: 1)) {
      _ = try ReplayExport(sidecarURL: sidecarURL)
    }
  }

  // MARK: Test 4 - a wrong channel count is refused

  @Test("Test 4: n_channels != 96 throws .badChannelCount")
  func refusesAWrongChannelCount() throws {
    let dir = try Self.stageFixture()
    let sidecarURL = try Self.tamper(dir, key: "n_channels", value: 192)
    #expect(throws: ReplayExportError.badChannelCount(found: 192, expected: 96)) {
      _ = try ReplayExport(sidecarURL: sidecarURL)
    }
  }

  // MARK: Test 5 - a wrong record size is refused

  @Test("Test 5: record_bytes != 424 throws .badRecordSize")
  func refusesAWrongRecordSize() throws {
    let dir = try Self.stageFixture()
    let sidecarURL = try Self.tamper(dir, key: "record_bytes", value: 400)
    #expect(throws: ReplayExportError.badRecordSize(found: 400, expected: 424)) {
      _ = try ReplayExport(sidecarURL: sidecarURL)
    }
  }

  // MARK: Test 6 - a malformed provenance digest is refused

  @Test("Test 6: a source_sha256 that is not 64 lowercase hex throws .malformedProvenance")
  func refusesAMalformedDigest() throws {
    let dir = try Self.stageFixture()
    let sidecarURL = try Self.tamper(dir, key: "source_sha256", value: "NOT-A-DIGEST")
    #expect(throws: ReplayExportError.malformedProvenance(field: "source_sha256")) {
      _ = try ReplayExport(sidecarURL: sidecarURL)
    }

    // An UPPERCASE 64-char hex string is still refused: the manifest's digests are lowercase, and a
    // case-insensitive compare downstream is how two spellings of one digest start to diverge.
    let upper = try Self.tamper(dir, key: "source_sha256", value: String(repeating: "A", count: 64))
    #expect(throws: ReplayExportError.malformedProvenance(field: "source_sha256")) {
      _ = try ReplayExport(sidecarURL: upper)
    }
  }

  // MARK: Test 7 - a symlinked binary_path escaping the sidecar's directory is refused (ASVS V12)

  @Test("Test 7: a binary_path resolving outside the sidecar's directory throws .pathEscape")
  func refusesASymlinkEscape() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("cortex-escape-\(UUID().uuidString)", isDirectory: true)
    let exports = root.appendingPathComponent("exports", isDirectory: true)
    let outside = root.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

    // The real bytes live OUTSIDE; the sidecar's directory only holds a symlink pointing at them.
    try FileManager.default.copyItem(at: Self.fixtureBinary, to: outside.appendingPathComponent("tiny_replay.bin"))
    try FileManager.default.copyItem(at: Self.fixtureSidecar, to: exports.appendingPathComponent("tiny_replay.json"))
    try FileManager.default.createSymbolicLink(
      at: exports.appendingPathComponent("tiny_replay.bin"),
      withDestinationURL: outside.appendingPathComponent("tiny_replay.bin")
    )

    let sidecarURL = exports.appendingPathComponent("tiny_replay.json")
    #expect(throws: ReplayExportError.self) {
      _ = try ReplayExport(sidecarURL: sidecarURL)
    }
    do {
      _ = try ReplayExport(sidecarURL: sidecarURL)
      Issue.record("a symlinked binary_path outside the sidecar's directory must be refused")
    } catch {
      guard case let .pathEscape(declared, resolvedParent) = error else {
        Issue.record("expected .pathEscape, got \(error)")
        return
      }
      #expect(declared == "tiny_replay.bin")
      #expect(resolvedParent.hasSuffix("/outside"), "the refusal names where the path actually landed")
    }

    // An ABSOLUTE binary_path is the same threat without a symlink and is refused identically.
    let absolute = try Self.tamper(exports, key: "binary_path", value: outside
      .appendingPathComponent("tiny_replay.bin").path)
    #expect(throws: ReplayExportError.self) { _ = try ReplayExport(sidecarURL: absolute) }
  }

  // MARK: Test 8 - the window is bin-major and bounds-checked

  @Test("Test 8: window(endingAt:length:) is bin-major over the raw bytes and refuses out-of-range")
  func windowIsBinMajorAndBounded() throws {
    let export = try ReplayExport(sidecarURL: Self.fixtureSidecar)
    let window = try export.window(endingAt: 31, length: 32)

    // Cross-check three (bin, channel) cells against the raw bytes read independently above. The
    // window's first row is export bin 0, so window[binOffset * 96 + channel] == spikes[binOffset][channel].
    for (bin, channel) in [(0, 0), (1, 3), (31, 95)] {
      let expected = try Float16(Self.rawSpike(bin: bin, channel: channel))
      #expect(
        window[bin * 96 + channel] == expected,
        "window is bin-major (window[bin * channels + channel]) - bin \(bin), channel \(channel)"
      )
    }
    // The Python fixture has a spike at (bin 1, channel 0) and (bin 1, channel 3), so the ordering
    // assertion above is not vacuously comparing zeros.
    #expect(window[1 * 96 + 0] == Float16(1.0))
    #expect(window[1 * 96 + 3] == Float16(1.0))

    // A window that would start before bin 0 is refused rather than clamped.
    #expect(throws: ReplayExportError.self) { _ = try export.window(endingAt: 5, length: 32) }
    // A window ending past the last bin is refused.
    #expect(throws: ReplayExportError.self) { _ = try export.window(endingAt: 256, length: 32) }
    // A non-positive length is refused.
    #expect(throws: ReplayExportError.self) { _ = try export.window(endingAt: 31, length: 0) }

    // The last whole window is legal and complete.
    let last = try export.window(endingAt: 255, length: 32)
    #expect(last.count == 32 * 96)
  }

  // MARK: Test 9 - the kinematic accessors return the stored doubles unchanged

  @Test("Test 9: velocity/target/binStart return the stored Float64 values unchanged")
  func kinematicAccessorsAreExact() throws {
    let export = try ReplayExport(sidecarURL: Self.fixtureSidecar)

    let velocity0 = try export.velocity(at: 0)
    #expect(velocity0.x == 6.5973445725385655)
    #expect(velocity0.y == 4.887171231974204)

    let target0 = try export.target(at: 0)
    #expect(target0.x == -15.0)
    #expect(target0.y == 0.0)

    let targetLast = try export.target(at: 255)
    #expect(targetLast.x == 15.0)
    #expect(targetLast.y == 15.0)

    #expect(try export.binStart(at: 0) == 0.0)
    #expect(try export.binStart(at: 1) == 0.02)

    #expect(throws: ReplayExportError.outOfRange(index: 256, count: 256)) { _ = try export.velocity(at: 256) }
    #expect(throws: ReplayExportError.outOfRange(index: 256, count: 256)) { _ = try export.target(at: 256) }
    #expect(throws: ReplayExportError.outOfRange(index: -1, count: 256)) { _ = try export.binStart(at: -1) }
  }

  // MARK: Test 10 - an absent sidecar or binary fails closed

  @Test("Test 10: an absent sidecar or binary throws .notFound rather than returning empty data")
  func failsClosedOnAbsentFiles() throws {
    let missing = FileManager.default.temporaryDirectory
      .appendingPathComponent("cortex-absent-\(UUID().uuidString).json")
    #expect(throws: ReplayExportError.notFound(path: missing.path)) {
      _ = try ReplayExport(sidecarURL: missing)
    }

    // Sidecar present, binary deleted: still .notFound, never a silent empty read.
    let dir = try Self.stageFixture()
    try FileManager.default.removeItem(at: dir.appendingPathComponent("tiny_replay.bin"))
    #expect(throws: ReplayExportError.self) {
      _ = try ReplayExport(sidecarURL: dir.appendingPathComponent("tiny_replay.json"))
    }
  }

  // MARK: Test 11 - a malformed sidecar names why

  @Test("Test 11: unparseable JSON and a non-positive n_bins both throw .malformedSidecar")
  func refusesAMalformedSidecar() throws {
    let dir = try Self.stageFixture()
    let sidecarURL = dir.appendingPathComponent("tiny_replay.json")
    try Data("{ not json".utf8).write(to: sidecarURL)
    do {
      _ = try ReplayExport(sidecarURL: sidecarURL)
      Issue.record("unparseable JSON must be refused")
    } catch {
      guard case let .malformedSidecar(reason) = error else {
        Issue.record("expected .malformedSidecar, got \(error)")
        return
      }
      #expect(!reason.isEmpty, "the refusal carries the underlying decoding failure")
    }

    let zeroBins = try Self.stageFixture()
    let tampered = try Self.tamper(zeroBins, key: "n_bins", value: 0)
    #expect(throws: ReplayExportError.malformedSidecar(reason: "n_bins must be positive")) {
      _ = try ReplayExport(sidecarURL: tampered)
    }
  }

  // MARK: Test 12 - the environment hook is absent-means-skip, never absent-means-synthetic

  @Test("Test 12: sidecarURLFromEnvironment treats an absent or empty CORTEX_REPLAY_EXPORT as nil")
  func environmentHookSkipsCleanly() {
    // The variable is not set in the test process, so the clean-clone answer is nil - the caller then
    // SKIPS, which is the D-07 / ASVS V14 idiom. It must never mean "fall back to synthetic".
    let resolved = ReplayExport.sidecarURLFromEnvironment()
    if let raw = ProcessInfo.processInfo.environment["CORTEX_REPLAY_EXPORT"], !raw.isEmpty {
      #expect(resolved?.path == URL(fileURLWithPath: raw).path)
    } else {
      #expect(resolved == nil, "absent or empty CORTEX_REPLAY_EXPORT resolves to nil (skip cleanly)")
    }
  }
}
