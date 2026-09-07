@testable import CortexBCIHID

// BCIHIDReportTests — Phase 8 (SYS-01/05): exact-byte-layout + round-trip tests for the 5 ported
// Apple BCI HID report structs. Source of truth for sizes/fields:
//   developer.apple.com/documentation/accessibility/brain-computer-interface-hid-reference-for-connecting-to-apple-platforms
//
// Threat T-08-01-01 (a wrong field width silently corrupting the wire format) is mitigated HERE:
// every struct asserts its EXACT documented byte size and decode(encode(x)) == x, and the signed
// pointer deltas round-trip their SInt8 extremes with no sign loss.
//
// Test-naming convention mirrors the CI-passing CortexReFIT suites: `@Test("descriptive")` + a
// camelCase function name (SwiftLint identifier_name-clean — the form CI's SwiftFormat accepts).
import Testing

@Suite("BCIHIDReportTests")
struct BCIHIDReportTests {
  /// Test 1 — each struct encodes to a byte buffer of the EXACT documented size, and
  /// decode(encode(x)) == x for representative values.
  @Test("Signal report encodes to 3 bytes and round-trips")
  func signalRoundTrip() throws {
    let report = BCIInputSignalReport(signalQuality: (3, 200)) // buttonID=3, neural strength=200
    let bytes = report.encode()
    #expect(bytes.count == 3) // reportId + 2
    #expect(bytes == [1, 3, 200])
    let decoded = try #require(BCIInputSignalReport.decode(bytes))
    #expect(decoded == report)
  }

  @Test("Button report encodes to 5 bytes and round-trips")
  func buttonRoundTrip() throws {
    let report = BCIInputButtonReport(buttons: (0b0000_0001, 0x00, 0xFF, 0x80)) // 32 buttons / 4 bytes
    let bytes = report.encode()
    #expect(bytes.count == 5) // reportId + 4
    #expect(bytes == [2, 0b0000_0001, 0x00, 0xFF, 0x80])
    let decoded = try #require(BCIInputButtonReport.decode(bytes))
    #expect(decoded == report)
  }

  @Test("Pointer report encodes to 4 bytes and round-trips")
  func pointerRoundTrip() throws {
    let report = BCIInputPointerReport(position: (12, -5, 0))
    let bytes = report.encode()
    #expect(bytes.count == 4) // reportId + 3 SInt8
    let decoded = try #require(BCIInputPointerReport.decode(bytes))
    #expect(decoded == report)
  }

  @Test("ItemSelection report encodes to 2 bytes and round-trips")
  func itemSelectionRoundTrip() throws {
    let report = BCIInputItemSelection(itemIndex: 42)
    let bytes = report.encode()
    #expect(bytes.count == 2) // reportId + itemIndex
    #expect(bytes == [4, 42])
    let decoded = try #require(BCIInputItemSelection.decode(bytes))
    #expect(decoded == report)
  }

  @Test("ScanInfo output report encodes to 7 bytes and round-trips")
  func scanInfoRoundTrip() throws {
    let report = BCIOutputScanInfoReport(
      selectedItem: 7, numberOfItems: 30, seed: 99,
      itemControlType: 1, uiScanningLatencyInt: 12, uiScanningLatencyFrac: 128
    )
    let bytes = report.encode()
    #expect(bytes.count == 7) // reportId + 6
    #expect(bytes == [4, 7, 30, 99, 1, 12, 128])
    let decoded = try #require(BCIOutputScanInfoReport.decode(bytes))
    #expect(decoded == report)
  }

  /// Test 2 — Pointer position round-trips the signed extremes (-127, 0, 127) as SInt8 with no
  /// sign-loss; ScanInfo uiScanningLatencyInt/Frac round-trip a fixed-point latency (12.5 -> int=12,
  /// frac=128, reconstructing as int + frac/255.0 per the Apple reference).
  @Test("Pointer position round-trips signed SInt8 extremes")
  func pointerSignedExtremes() throws {
    let report = BCIInputPointerReport(position: (-127, 0, 127))
    let bytes = report.encode()
    // The signed -127 must encode to a UInt8 bit pattern, NOT clamp/wrap to 0.
    #expect(bytes[1] == UInt8(bitPattern: Int8(-127))) // 0x81
    #expect(bytes[2] == 0)
    #expect(bytes[3] == 127) // 0x7F
    let decoded = try #require(BCIInputPointerReport.decode(bytes))
    #expect(decoded.position == (-127, 0, 127))
  }

  @Test("ScanInfo fixed-point latency 12.5 maps to int=12, frac=128 and reconstructs near 12.5")
  func scanInfoFixedPointLatency() throws {
    // 12.5 seconds -> int part 12, fractional part round(0.5 * 255) = 128 (Apple reference: the host
    // reconstructs as int + frac/255.0).
    let intPart = UInt8(12)
    let fracPart = UInt8((0.5 * 255.0).rounded()) // 128
    #expect(fracPart == 128)
    let report = BCIOutputScanInfoReport(
      selectedItem: 0, numberOfItems: 0, seed: 0,
      itemControlType: 0, uiScanningLatencyInt: intPart, uiScanningLatencyFrac: fracPart
    )
    let decoded = try #require(BCIOutputScanInfoReport.decode(report.encode()))
    #expect(decoded.uiScanningLatencyInt == 12)
    #expect(decoded.uiScanningLatencyFrac == 128)
    // Reconstructed latency in seconds (the callback's float math): 12 + 128/255 ~= 12.502.
    #expect(abs(decoded.uiScanningLatencySeconds - 12.5) < 0.01)
  }

  /// Test 3 — each struct exposes its reportId constant (1,2,3,4,4) and the BCIReportID enum maps
  /// input vs output RID-4 unambiguously (ItemSelection is input RID4; ScanInfo is output RID4).
  @Test("Each report exposes its documented reportId (1,2,3,4,4)")
  func reportIds() {
    #expect(BCIInputSignalReport(signalQuality: (0, 0)).reportId == 1)
    #expect(BCIInputButtonReport(buttons: (0, 0, 0, 0)).reportId == 2)
    #expect(BCIInputPointerReport(position: (0, 0, 0)).reportId == 3)
    #expect(BCIInputItemSelection(itemIndex: 0).reportId == 4)
    #expect(
      BCIOutputScanInfoReport(
        selectedItem: 0, numberOfItems: 0, seed: 0,
        itemControlType: 0, uiScanningLatencyInt: 0, uiScanningLatencyFrac: 0
      ).reportId == 4
    )
  }

  @Test("BCIReportID disambiguates RID-4 input (ItemSelection) vs output (ScanInfo) by direction")
  func reportIdDirectionDisambiguation() {
    #expect(BCIReportID.signal.rawValue == 1)
    #expect(BCIReportID.button.rawValue == 2)
    #expect(BCIReportID.pointer.rawValue == 3)
    #expect(BCIReportID.itemSelectionOrScanInfo.rawValue == 4)
    // RID4 is INPUT (device->host) when it carries an Item-Selection, OUTPUT (host->device) when it
    // carries Scan-Info. The enum exposes that disambiguation explicitly.
    #expect(BCIReportID.itemSelectionOrScanInfo.inputDirection == .deviceToHost)
    #expect(BCIReportID.itemSelectionOrScanInfo.outputDirection == .hostToDevice)
    #expect(BCIInputItemSelection.direction == .deviceToHost)
    #expect(BCIOutputScanInfoReport.direction == .hostToDevice)
  }

  /// Decode rejects wrong-length buffers (defensive: validates length before reconstructing).
  @Test("decode rejects wrong-length buffers")
  func decodeRejectsBadLength() {
    #expect(BCIInputSignalReport.decode([1, 2]) == nil) // too short
    #expect(BCIInputButtonReport.decode([2, 0, 0, 0, 0, 0]) == nil) // too long
    #expect(BCIInputPointerReport.decode([]) == nil) // empty
    #expect(BCIOutputScanInfoReport.decode([4, 0, 0]) == nil) // too short
  }
}
