import Foundation

enum ConnectionTiming {
    // Reconnect immediately after an isolated failure. Only repeated real errors
    // back off to avoid spinning; pending CoreBluetooth requests are left intact.
    static func retryDelay(afterFailures failures: Int) -> TimeInterval {
        failures <= 0 ? 0 : min(8, pow(2, Double(min(failures - 1, 3))))
    }
}
