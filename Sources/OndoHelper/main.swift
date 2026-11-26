import Foundation
import os
import OndoShared

/// ondo's privileged helper, a LaunchDaemon registered by the app with SMAppService.
///
/// Restore guarantees (SPEC section 6): sleep is allowed again when the helper starts (boot, crash restart),
/// when the connection that disabled sleep goes away (app quit or crash), and on SIGTERM (unload, shutdown).

let log = Logger(subsystem: Identity.helperID, category: "helper")

guard let requirement = Identity.sameTeamRequirement(identifier: Identity.appBundleID) else {
    // Unsigned: there is no way to tell ondo from any other caller, so accept nobody.
    log.error("helper has no team ID; refusing to start the XPC listener")
    if let error = Power.setSleepDisabled(false) { log.error("restore failed: \(error, privacy: .public)") }
    exit(1)
}

if let error = Power.setSleepDisabled(false) { log.error("restore at start failed: \(error, privacy: .public)") }

signal(SIGTERM, SIG_IGN)
let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminate.setEventHandler {
    if let error = Power.setSleepDisabled(false) { log.error("restore at exit failed: \(error, privacy: .public)") }
    exit(0)
}
terminate.resume()

let helper = Helper(requirement: requirement)
let listener = NSXPCListener(machServiceName: Identity.helperID)
listener.delegate = helper
listener.resume()
helper.start()
log.notice("helper started")
dispatchMain()
