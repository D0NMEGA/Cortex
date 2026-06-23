/// The direction a BCI HID report travels across the device↔host boundary.
public nonisolated enum BCIReportDirection: Sendable, Equatable {
  /// Device → host (an INPUT report: signal, button, pointer, item-selection).
  case deviceToHost
  /// Host → device (an OUTPUT report: scan-info feedback — the closed-loop channel).
  case hostToDevice
}

/// The BCI HID report IDs. Report ID 4 is SHARED: it is an INPUT Item-Selection report device→host
/// and an OUTPUT Scan-Info report host→device, so it is disambiguated by direction (see
/// `inputDirection`/`outputDirection`), never by ID alone.
public nonisolated enum BCIReportID: UInt8, Sendable, CaseIterable {
  case signal = 1
  case button = 2
  case pointer = 3
  case itemSelectionOrScanInfo = 4

  /// The direction this report ID takes when it carries an INPUT report (device → host).
  public var inputDirection: BCIReportDirection {
    .deviceToHost
  }

  /// The direction this report ID takes when it carries an OUTPUT report (host → device).
  /// Only `.itemSelectionOrScanInfo` (RID 4) carries an output (Scan-Info) report.
  public var outputDirection: BCIReportDirection {
    .hostToDevice
  }
}

/// RID 1 — BCI input signal report. `signalQuality[0]` = button number ID, `signalQuality[1]` =
/// neural activity strength (0–255). Use to show selection during item scanning.
public nonisolated struct BCIInputSignalReport: Sendable, Equatable {
  public static let direction: BCIReportDirection = .deviceToHost
  public let reportId: UInt8
  public var signalQuality: (UInt8, UInt8)

  public init(signalQuality: (UInt8, UInt8)) {
    reportId = BCIReportID.signal.rawValue
    self.signalQuality = signalQuality
  }

  public func encode() -> [UInt8] {
    [reportId, signalQuality.0, signalQuality.1]
  }

  public static func decode(_ bytes: [UInt8]) -> BCIInputSignalReport? {
    guard bytes.count == 3, bytes[0] == BCIReportID.signal.rawValue else { return nil }
    return BCIInputSignalReport(signalQuality: (bytes[1], bytes[2]))
  }

  public static func == (lhs: BCIInputSignalReport, rhs: BCIInputSignalReport) -> Bool {
    lhs.reportId == rhs.reportId && lhs.signalQuality == rhs.signalQuality
  }
}

// swiftlint:disable large_tuple
// The button (UInt8[4]) and pointer (SInt8[3]) reports port Apple's fixed-size C arrays
// `UInt8 buttons[4]` / `SInt8 position[3]` as fixed-arity Swift tuples — a faithful, exact port of the
// HID wire layout, not an ad-hoc large tuple. large_tuple is re-enabled right after these two structs.

/// RID 2 — BCI input button report. 32 buttons packed over 4 bytes (HID Button Usage Page).
/// Default map: button 0 = select, 1 = next, 2 = previous, 3 = menu.
public nonisolated struct BCIInputButtonReport: Sendable, Equatable {
  public static let direction: BCIReportDirection = .deviceToHost
  public let reportId: UInt8
  public var buttons: (UInt8, UInt8, UInt8, UInt8)

  public init(buttons: (UInt8, UInt8, UInt8, UInt8)) {
    reportId = BCIReportID.button.rawValue
    self.buttons = buttons
  }

  public func encode() -> [UInt8] {
    [reportId, buttons.0, buttons.1, buttons.2, buttons.3]
  }

  public static func decode(_ bytes: [UInt8]) -> BCIInputButtonReport? {
    guard bytes.count == 5, bytes[0] == BCIReportID.button.rawValue else { return nil }
    return BCIInputButtonReport(buttons: (bytes[1], bytes[2], bytes[3], bytes[4]))
  }

  public static func == (lhs: BCIInputButtonReport, rhs: BCIInputButtonReport) -> Bool {
    lhs.reportId == rhs.reportId && lhs.buttons == rhs.buttons
  }
}

/// RID 3 — BCI input pointer report. x,y,z relative deltas in −127…127 (Generic Desktop). THE cursor
/// report. The deltas are SIGNED (`Int8`) — modeling them as UInt8 would silently corrupt motion.
public nonisolated struct BCIInputPointerReport: Sendable, Equatable {
  public static let direction: BCIReportDirection = .deviceToHost
  public let reportId: UInt8
  public var position: (Int8, Int8, Int8)

  public init(position: (Int8, Int8, Int8)) {
    reportId = BCIReportID.pointer.rawValue
    self.position = position
  }

  public func encode() -> [UInt8] {
    [
      reportId,
      UInt8(bitPattern: position.0),
      UInt8(bitPattern: position.1),
      UInt8(bitPattern: position.2)
    ]
  }

  public static func decode(_ bytes: [UInt8]) -> BCIInputPointerReport? {
    guard bytes.count == 4, bytes[0] == BCIReportID.pointer.rawValue else { return nil }
    return BCIInputPointerReport(
      position: (
        Int8(bitPattern: bytes[1]),
        Int8(bitPattern: bytes[2]),
        Int8(bitPattern: bytes[3])
      )
    )
  }

  public static func == (lhs: BCIInputPointerReport, rhs: BCIInputPointerReport) -> Bool {
    lhs.reportId == rhs.reportId && lhs.position == rhs.position
  }
}

// swiftlint:enable large_tuple

/// RID 4 (input) — BCI input item-selection report. The focused item index 0…255 (BCI Usage 0x04).
public nonisolated struct BCIInputItemSelection: Sendable, Equatable {
  public static let direction: BCIReportDirection = .deviceToHost
  public let reportId: UInt8
  public var itemIndex: UInt8

  public init(itemIndex: UInt8) {
    reportId = BCIReportID.itemSelectionOrScanInfo.rawValue
    self.itemIndex = itemIndex
  }

  public func encode() -> [UInt8] {
    [reportId, itemIndex]
  }

  public static func decode(_ bytes: [UInt8]) -> BCIInputItemSelection? {
    guard bytes.count == 2, bytes[0] == BCIReportID.itemSelectionOrScanInfo.rawValue else {
      return nil
    }
    return BCIInputItemSelection(itemIndex: bytes[1])
  }
}

/// RID 4 (output) — BCI output scan-info report. The HOST → DEVICE scan-feedback channel: the
/// closed-loop seam consumed in Plan 02. Carries the selected item, item count, a scan-cycle `seed`,
/// the item control type, and a two-byte fixed-point UI scanning latency (`int` + `frac`, reconstructed
/// host-side as `int + frac/255.0` seconds — Apple reference).
public nonisolated struct BCIOutputScanInfoReport: Sendable, Equatable {
  public static let direction: BCIReportDirection = .hostToDevice
  public let reportId: UInt8
  public var selectedItem: UInt8
  public var numberOfItems: UInt8
  public var seed: UInt8
  public var itemControlType: UInt8
  public var uiScanningLatencyInt: UInt8
  public var uiScanningLatencyFrac: UInt8

  public init(
    selectedItem: UInt8,
    numberOfItems: UInt8,
    seed: UInt8,
    itemControlType: UInt8,
    uiScanningLatencyInt: UInt8,
    uiScanningLatencyFrac: UInt8
  ) {
    reportId = BCIReportID.itemSelectionOrScanInfo.rawValue
    self.selectedItem = selectedItem
    self.numberOfItems = numberOfItems
    self.seed = seed
    self.itemControlType = itemControlType
    self.uiScanningLatencyInt = uiScanningLatencyInt
    self.uiScanningLatencyFrac = uiScanningLatencyFrac
  }

  public func encode() -> [UInt8] {
    [
      reportId, selectedItem, numberOfItems, seed,
      itemControlType, uiScanningLatencyInt, uiScanningLatencyFrac
    ]
  }

  public static func decode(_ bytes: [UInt8]) -> BCIOutputScanInfoReport? {
    guard bytes.count == 7, bytes[0] == BCIReportID.itemSelectionOrScanInfo.rawValue else {
      return nil
    }
    return BCIOutputScanInfoReport(
      selectedItem: bytes[1],
      numberOfItems: bytes[2],
      seed: bytes[3],
      itemControlType: bytes[4],
      uiScanningLatencyInt: bytes[5],
      uiScanningLatencyFrac: bytes[6]
    )
  }

  /// The UI scanning latency in seconds, reconstructed as the Apple output-report callback does:
  /// `uiScanningLatencyInt + uiScanningLatencyFrac / 255.0`.
  public var uiScanningLatencySeconds: Double {
    Double(uiScanningLatencyInt) + Double(uiScanningLatencyFrac) / 255.0
  }
}
