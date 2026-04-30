// CortexDaemon -- placeholder background-helper bundle target per D-03.
// Phase 1 ships a small SC#2 verification surface: on launch, the daemon calls
// shm_open against CORTEX_SHM_NAME and prints the result to stdout, so the user
// can visually compare against CortexMac's button-driven ShmCheck.
//
// Phase 2 will populate the IPC primitive (kqueue + recvmsg + POSIX shm) here,
// consuming Packages/CortexIPC.
//
// The bundle's Cortex.entitlements declares the same App Group as CortexMac, so the
// manual SC#2 runbook can verify cross-process shm_open works between the two
// processes inside ~/Library/Group Containers/group.com.donovansantine.cortex.shared/.

import Foundation
import CortexCore

NSLog("Cortex daemon stub (Phase 1). App Group: \(CortexCore.AppGroup.identifier).")

let result = ShmCheck.openSharedRegion(processLabel: "CortexDaemon")
print(result.description)
NSLog("[Cortex SC#2 daemon] %@", String(describing: result))

// Block briefly so the user can read stdout and inspect /Library/Group Containers in Finder.
RunLoop.main.run(until: Date(timeIntervalSinceNow: 5.0))
