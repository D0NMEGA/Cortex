// Source: Swift Testing 6.2 — apple/swift-testing
// Purpose: prove the C constant is reachable from Swift via the SwiftPM module map,
// and that its value matches the canonical "/cortex.samples" string. The compile-time
// _Static_assert in cortex_shm.h handles length enforcement; this test handles
// "Swift can see it AND it has the right value."

@testable import CortexCore
import Testing

@Test
func `Swift can read CORTEX_SHM_NAME from CortexCoreC and value matches /cortex.samples`() {
  #expect(Cortex.shmName == "/cortex.samples")
  #expect(Cortex.shmName.count == 15)
  #expect(Cortex.shmName.utf8.count <= 31, "Must fit Darwin PSHMNAMLEN")
}

@Test
func `App Group identifier matches D-07`() {
  #expect(AppGroup.identifier == "group.com.donovansantine.cortex.shared")
}

@Test
func `mach_absolute_time wrapper returns monotonically non-decreasing values`() {
  let t0 = Time.machAbsoluteNanoseconds()
  let t1 = Time.machAbsoluteNanoseconds()
  #expect(t1 >= t0)
}
