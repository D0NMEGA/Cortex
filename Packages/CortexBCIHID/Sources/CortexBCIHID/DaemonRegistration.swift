// DaemonRegistration.swift — Phase 8 (SYS-02, D-03): the SMAppService daemon register/status SCAFFOLD.
// D-09 (Phase 2) named SMAppService as the App-Store production daemon form. This phase keeps the
// standalone `type:tool` CortexDaemon driving the runnable demo and writes the
// `SMAppService.daemon(plistName:).register()/.status` path here, behind a protocol so the status path
// is unit-testable via a mock. The signed privileged-helper INSTALL is GATED on paid signing: a real
// `register()` needs the helper signed + the LaunchDaemons plist bundled at
// `Contents/Library/LaunchDaemons/<name>.plist` (paid enrollment) — so the scaffold + a script exist
// now, the live install is the Plan 07 HUMAN-UAT gate.
//
// SOURCE OF TRUTH: developer.apple.com/documentation/servicemanagement/smappservice (macOS 13.0+).

/// The registration status of a launch daemon, mirroring `SMAppService.Status`.
public enum DaemonRegistrationStatus: Sendable, Equatable {
  /// The service is not registered (or was unregistered).
  case notRegistered
  /// The service is registered and enabled; it can launch.
  case enabled
  /// The service requires user approval in System Settings > Login Items.
  case requiresApproval
  /// The service (its bundled plist) was not found.
  case notFound
}

/// A registrable daemon service. The production conformer wraps `SMAppService.daemon(plistName:)`;
/// the mock provides a fixed status for unit tests.
public protocol DaemonService: Sendable {
  /// The current registration status.
  var status: DaemonRegistrationStatus { get }
  /// Register the service so it can begin launching, subject to user approval.
  /// - Note: the live install requires a signed helper + bundled LaunchDaemons plist (paid signing,
  ///   D-03) — gated to the Plan 07 HUMAN-UAT checkpoint.
  func register() throws
  /// Unregister the service.
  func unregister() throws
}

/// Models a launch-daemon registration by its bundled plist name (the
/// `Contents/Library/LaunchDaemons/<plistName>` the production conformer registers).
public struct DaemonRegistration: Sendable, Equatable {
  /// The launch-daemon plist file name bundled in the app (e.g. `com.donovansantine.cortex.daemon.plist`).
  public let plistName: String

  public init(plistName: String) {
    self.plistName = plistName
  }
}

/// A test/double `DaemonService` with a fixed status. `register()`/`unregister()` are callable and
/// record that they were invoked, so the status path can be unit-tested with no real SMAppService.
public final class MockDaemonService: DaemonService, @unchecked Sendable {
  public let status: DaemonRegistrationStatus
  public private(set) var registerCallCount = 0
  public private(set) var unregisterCallCount = 0

  public init(status: DaemonRegistrationStatus) {
    self.status = status
  }

  public func register() throws {
    registerCallCount += 1
  }

  public func unregister() throws {
    unregisterCallCount += 1
  }
}

#if os(macOS)
  import ServiceManagement

  /// The production `DaemonService` conformer wrapping `SMAppService.daemon(plistName:)`.
  ///
  /// macOS-only. The `register()` call is written here, but a SUCCESSFUL live registration requires the
  /// helper to be signed and the LaunchDaemons plist bundled — that install is the paid-signing
  /// HUMAN-UAT gate (D-03). On the free-team demo, constructing this and reading `.status` is safe; the
  /// live `register()` is reserved for the gated device session.
  @available(macOS 13.0, *)
  public struct SMAppServiceDaemon: DaemonService {
    private let service: SMAppService
    public let registration: DaemonRegistration

    public init(registration: DaemonRegistration) {
      self.registration = registration
      service = SMAppService.daemon(plistName: registration.plistName)
    }

    public var status: DaemonRegistrationStatus {
      switch service.status {
      case .notRegistered: return .notRegistered
      case .enabled: return .enabled
      case .requiresApproval: return .requiresApproval
      case .notFound: return .notFound
      @unknown default: return .notFound
      }
    }

    public func register() throws {
      try service.register()
    }

    public func unregister() throws {
      try service.unregister()
    }
  }
#endif
