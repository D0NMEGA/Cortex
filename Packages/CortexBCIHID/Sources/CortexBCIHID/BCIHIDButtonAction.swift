/// The 22 documented high-level BCI button actions. `rawValue` is the stable 0-based ordinal; the
/// descriptor's default button map fixes the first four (0=select, 1=next, 2=previous, 3=menu).
///
/// `nonisolated`: a pure `Sendable` value enum, freely usable across isolation boundaries despite the
/// package's default `MainActor` isolation.
public nonisolated enum BCIHIDButtonAction: UInt8, CaseIterable, Sendable {
  case select = 0
  case moveToNextItem
  case moveToPreviousItem
  case toggleAssistiveTechnologyMenu
  case activate
  case startSequentialNavigation
  case stopSequentialNavigation
  case triggerAutomation
  case toggleAppSwitcher
  case home
  case toggleNotificationsView
  case assistant
  case volumeDown
  case volumeUp
  case toggleDictation
  case toggleAccessibilityFeature
  case toggleQuickSettingsView
  case escape
  case scrollUp
  case scrollDown
  case scrollLeft
  case scrollRight
}
