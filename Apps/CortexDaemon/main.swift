// CortexDaemon -- placeholder background-helper bundle target per D-03.
// Phase 1 ships an empty main(). Phase 2 will populate the IPC primitive (kqueue +
// recvmsg + POSIX shm) here, consuming Packages/CortexIPC.
//
// The bundle's Cortex.entitlements declares the same App Group as CortexMac, so the
// manual SC#2 runbook can verify cross-process shm_open works between the two
// processes inside ~/Library/Group Containers/group.com.donovansantine.cortex.shared/.

import Foundation
import CortexCore

NSLog("Cortex daemon stub (Phase 1). App Group: \(CortexCore.AppGroup.identifier).")

// Block briefly so a manual launch from the runbook can observe the process.
// Phase 2 replaces this with a real run loop.
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
