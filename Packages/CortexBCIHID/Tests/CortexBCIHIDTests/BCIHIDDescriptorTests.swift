// BCIHIDDescriptorTests — Phase 8 (SYS-05): the ported Apple BCI HID report descriptor byte array
// and the high-level button-action enum. Source of truth:
//   developer.apple.com/documentation/accessibility/brain-computer-interface-hid-reference-for-connecting-to-apple-platforms
//
// The descriptor's documented HEADER bytes are LOAD-BEARING (Usage Page 0x60 = Brain Control
// Interface, Usage 0x01 = BCI Application, then Signal-Quality / Report ID 1). The structural CI gate
// (hid-surface-policy.sh) asserts these same bytes, so a silent regression is caught two ways.
import Testing

@testable import CortexBCIHID

@Suite("BCIHIDDescriptorTests")
struct BCIHIDDescriptorTests {
  // Test 4 — BCIHIDDescriptor.bytes begins with the documented header and is a non-empty [UInt8].
  // NOTE: the canonical Apple BCIDescriptor[] REPEATS the Usage Page (0x05, 0x60) immediately before
  // the Signal-Quality usage (0x09, 0x02) — i.e. the verified first 12 bytes are
  // [0x05,0x60, 0x09,0x01, 0xA1,0x01, 0x05,0x60, 0x09,0x02, 0x85,0x01]. The 08-PLAN header literal
  // collapsed that repeat; we port Apple's bytes verbatim (the honest source-of-truth) and assert
  // BOTH load-bearing tokens: the application header (Usage Page + Usage + Collection) and the
  // documented Signal-Quality usage + Report ID 1. hid-surface-policy.sh asserts the 0x05,0x60 pair.
  @Test("Descriptor begins with the documented Apple BCI HID header and is non-empty")
  func descriptorHeader() {
    // The verbatim canonical header, including the repeated Usage Page before Signal Quality.
    let canonicalHeader: [UInt8] = [
      0x05, 0x60, // Usage Page (Brain Control Interface)
      0x09, 0x01, // Usage 1 (BCI Application)
      0xA1, 0x01, // Collection (Application)
      0x05, 0x60, // Usage Page (Brain Control Interface) — repeated per Apple's descriptor
      0x09, 0x02, // Usage 2 (Signal Quality)
      0x85, 0x01, // Report ID (1)
    ]
    #expect(!BCIHIDDescriptor.bytes.isEmpty)
    #expect(BCIHIDDescriptor.bytes.count >= canonicalHeader.count)
    #expect(Array(BCIHIDDescriptor.bytes.prefix(canonicalHeader.count)) == canonicalHeader)
    // The load-bearing application-collection prefix and the Report-ID-1 main item are present.
    #expect(Array(BCIHIDDescriptor.bytes.prefix(6)) == [0x05, 0x60, 0x09, 0x01, 0xA1, 0x01])
    #expect(BCIHIDDescriptor.bytes.contains(0x85)) // a Report ID main item is present
  }

  @Test("Descriptor exposes the Usage Page and Usage byte pairs")
  func descriptorUsageConstants() {
    #expect(BCIHIDDescriptor.usagePage == [0x05, 0x60]) // Usage Page (Brain Control Interface)
    #expect(BCIHIDDescriptor.usage == [0x09, 0x01]) // Usage 1 (BCI Application)
    // The Usage Page / Usage pairs lead the descriptor.
    #expect(Array(BCIHIDDescriptor.bytes.prefix(2)) == BCIHIDDescriptor.usagePage)
    #expect(Array(BCIHIDDescriptor.bytes[2 ..< 4]) == BCIHIDDescriptor.usage)
  }

  @Test("Descriptor declares all five report IDs (0x85 0x01..0x04, with RID4 shared)")
  func descriptorDeclaresReportIDs() {
    // Each report-ID main item is the byte pair 0x85, <id>. The descriptor declares report IDs
    // 1 (signal), 2 (button), 3 (pointer), and 4 (item-selection input + scan-info output share 4).
    let bytes = BCIHIDDescriptor.bytes
    func declaresReportID(_ identifier: UInt8) -> Bool {
      bytes.indices.dropLast().contains { bytes[$0] == 0x85 && bytes[$0 + 1] == identifier }
    }
    #expect(declaresReportID(0x01))
    #expect(declaresReportID(0x02))
    #expect(declaresReportID(0x03))
    #expect(declaresReportID(0x04))
  }

  // Test 5 — BCIHIDButtonAction enum has exactly the 22 documented cases and the canonical actions
  // exist with stable rawValues.
  @Test("BCIHIDButtonAction has exactly 22 documented cases")
  func buttonActionCount() {
    #expect(BCIHIDButtonAction.allCases.count == 22)
  }

  @Test("BCIHIDButtonAction canonical cases exist with stable rawValues")
  func buttonActionCanonicalCases() {
    // The descriptor comment fixes the default button map: 0=select, 1=next, 2=previous, 3=menu.
    #expect(BCIHIDButtonAction.select.rawValue == 0)
    #expect(BCIHIDButtonAction.moveToNextItem.rawValue == 1)
    #expect(BCIHIDButtonAction.moveToPreviousItem.rawValue == 2)
    #expect(BCIHIDButtonAction.toggleAssistiveTechnologyMenu.rawValue == 3)
    // Spot-check the rest of the load-bearing actions exist (stable identity).
    #expect(BCIHIDButtonAction.activate.rawValue == 4)
    #expect(BCIHIDButtonAction(rawValue: BCIHIDButtonAction.home.rawValue) == .home)
    #expect(BCIHIDButtonAction(rawValue: BCIHIDButtonAction.escape.rawValue) == .escape)
    #expect(BCIHIDButtonAction.scrollRight.rawValue == 21) // the 22nd case (0-based)
  }
}
