import CoreServices

enum TerminationPolicy {
    static func shouldTerminate(explicitQuit: Bool, systemReason: UInt32?) -> Bool {
        if explicitQuit { return true }
        // A normal Quit hides Sunset. Session shutdown and system-wide quit
        // requests must still finish, so Sunset never prevents logout/restart.
        let systemReasons = [kAEQuitAll, kAEShutDown, kAERestart, kAELogOut, kAEReallyLogOut,
                             kAEShowShutdownDialog, kAEShowRestartDialog]
        return systemReason.map { systemReasons.contains($0) } ?? false
    }
}
