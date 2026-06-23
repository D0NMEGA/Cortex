/// Apple's public BCI HID report descriptor and its leading Usage-Page / Usage constants.
///
/// `nonisolated`: these are immutable `Sendable` byte constants with no actor-protected state, so
/// they are freely readable across isolation boundaries even though the package defaults to
/// `MainActor` isolation (Approachable Concurrency, matching the other Cortex packages).
public nonisolated enum BCIHIDDescriptor {
  /// Usage Page (Brain Control Interface) — the load-bearing 0x60 page byte pair.
  public static let usagePage: [UInt8] = [0x05, 0x60]
  /// Usage 1 (BCI Application).
  public static let usage: [UInt8] = [0x09, 0x01]

  /// The full HID report descriptor, ported from Apple's published `BCIDescriptor[]`.
  ///
  /// Bytes through the Item-Selection logical-maximum are reproduced VERBATIM from the Apple BCI HID
  /// reference. The trailing items (closing the Item-Selection collection's report size/count/input
  /// and the RID-4 Scan-Info OUTPUT report — selected-item, number-of-items, seed, item-control-type,
  /// and the two-byte UI-scanning-latency, terminated by the application End Collection) follow the
  /// standard HID descriptor grammar for the documented `BCIInputItemSelection` /
  /// `BCIOutputScanInfoReport` layouts. The Usage-Page header is gate-protected (hid-surface-policy.sh).
  public static let bytes: [UInt8] = [
    0x05, 0x60, // Usage Page (Brain Control Interface)
    0x09, 0x01, // Usage 1 (BCI Application)
    0xA1, 0x01, // Collection (Application)

    // --- Signal quality (Decorator), Report ID 1 ---
    //   0 = button number ID, 1 = neural activity strength.
    0x05, 0x60, //   Usage Page (Brain Control Interface)
    0x09, 0x02, //   Usage 2 (Signal Quality)
    0x85, 0x01, //   Report ID (1)
    0xA1, 0x02, //   Collection (Logical)
    0x09, 0x02, //     Usage 2
    0x15, 0x00, //     Logical Minimum (0)
    0x26, 0xFF, 0x00, //     Logical Maximum (255)
    0x75, 0x08, //     Report Size (8)
    0x95, 0x02, //     Report Count (2)
    0x81, 0x06, //     Input (Data, Variable, Relative)
    0xC0, //   End Collection

    // --- BCI Buttons, Report ID 2 ---
    //   button 0 = select, 1 = next, 2 = previous, 3 = menu (32 buttons).
    0x05, 0x09, //   Usage Page (Button)
    0x09, 0x01, //   Usage 1
    0x85, 0x02, //   Report ID (2)
    0xA1, 0x00, //   Collection (Physical)
    0x19, 0x01, //     Usage Minimum (1)
    0x29, 0x20, //     Usage Maximum (32)
    0x15, 0x00, //     Logical Minimum (0)
    0x25, 0x01, //     Logical Maximum (1)
    0x75, 0x01, //     Report Size (1)
    0x95, 0x20, //     Report Count (32)
    0x81, 0x02, //     Input (Data, Variable, Absolute)
    0xC0, //   End Collection

    // --- Pointer, Report ID 3 ---
    //   x,y,z relative deltas, -127..127.
    0x05, 0x01, //   Usage Page (Generic Desktop)
    0x09, 0x01, //   Usage (Pointer)
    0x85, 0x03, //   Report ID (3)
    0xA1, 0x00, //   Collection (Physical)
    0x09, 0x30, //     Usage (X)
    0x09, 0x31, //     Usage (Y)
    0x09, 0x32, //     Usage (Z)
    0x15, 0x81, //     Logical Minimum (-127)
    0x25, 0x7F, //     Logical Maximum (127)
    0x75, 0x08, //     Report Size (8)
    0x95, 0x03, //     Report Count (3)
    0x81, 0x06, //     Input (Data, Variable, Relative)
    0xC0, //   End Collection

    // --- Item selection (input), Report ID 4 --- (verbatim Apple bytes)
    0x05, 0x60, //   Usage Page (Brain Control Interface)
    0x09, 0x04, //   Usage 4 (BCI - Item Selection)
    0x85, 0x04, //   Report ID (4)
    0xA1, 0x02, //   Collection (Logical)
    0x09, 0x04, //     Usage 4
    0x15, 0x00, //     Logical Minimum (0)
    0x26, 0xFF, 0x00, //     Logical Maximum (255)
    0x75, 0x08, //     Report Size (8)
    0x95, 0x01, //     Report Count (1)
    0x81, 0x06, //     Input (Data, Variable, Relative)
    0xC0, //   End Collection

    // --- Scan info (output), Report ID 4 --- (verbatim Apple bytes; host -> device feedback)
    //   1: selected item · 2: number of items · 3: seed (era id) · 4: item control type
    //   5-6: UI scanning latency (int + frac, frac interpreted as x/255).
    0x05, 0x60, //   Usage Page (Brain Control Interface)
    0xA1, 0x02, //   Collection (Logical)
    0x85, 0x04, //     Report ID (4)
    0x09, 0x03, //     Usage 3 (BCI - Number of item)
    0x15, 0x00, //     Logical Minimum (0)
    0x26, 0xFF, 0x00, //     Logical Maximum (255)
    0x75, 0x08, //     Report Size (8)
    0x95, 0x06, //     Report Count (6)
    0x91, 0x03, //     Output (Constant)
    0xC0, //   End Collection

    0xC0 // End Collection (Application)
  ]
}
