// Swift API surface for the CortexCore package. Re-exports the C-level symbols
// from CortexCoreC so that consumers of `import CortexCore` see CORTEX_SHM_NAME
// without needing a separate `import CortexCoreC`.
@_exported import CortexCoreC

/// Top-level Cortex namespace. Phase 1 surface area is intentionally small —
/// shared types and utilities arrive in later phases as their packages activate.
public enum Cortex {
  /// Canonical shared-memory region name. Compile-time-validated to fit Darwin PSHMNAMLEN.
  ///
  /// The underlying C constant is enforced at C precompile time via _Static_assert
  /// in Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h — changes that
  /// would break Darwin's 31-byte cap fail the build before tests run.
  public static let shmName: String = String(cString: CORTEX_SHM_NAME)
}
