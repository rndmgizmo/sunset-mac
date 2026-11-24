import Foundation

enum ConnectionTiming {
    // Reconnect immediately after an isolated failure. Only repeated real errors
    // back off to avoid spinning; pending CoreBluetooth requests are left intact.
    static func retryDelay(afterFailures failures: Int) -> TimeInterval {
        failures <= 0 ? 0 : min(8, pow(2, Double(min(failures - 1, 3))))
    }

    // A known lamp is reconnected through a pending CoreBluetooth request, which
    // costs nothing while idle. Only an open-ended search for an unknown lamp scans
    // the radio, so it stops after a few unsuccessful rounds (about two minutes).
    static let scanDuration: TimeInterval = 20
    static let maxUnsuccessfulScans = 5

    static func shouldScanAgain(afterUnsuccessfulScans scans: Int) -> Bool {
        scans < maxUnsuccessfulScans
    }
}
