import Foundation

// Diagnostic log in /tmp/sunsetmac.log. "basic" records connection milestones and
// errors only; "verbose" adds every Bluetooth packet; "off" never touches the file.
//   defaults write local.sunsetmac logLevel -string verbose   (or: basic, off)
//   open -n /Applications/Sunset.app --args --log-verbose      (or: --log-off)
enum LogLevel: Int, Comparable {
    case off = 0, basic = 1, verbose = 2

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    static func resolve(arguments: [String], stored: String?) -> LogLevel {
        if arguments.contains("--log-off") { return .off }
        if arguments.contains("--log-verbose") { return .verbose }
        switch stored?.lowercased() {
        case "off", "none", "0": return .off
        case "verbose", "debug", "2": return .verbose
        default: return .basic
        }
    }

    // The file is truncated when it outgrows this size, so a long-running app with
    // a flapping connection cannot fill /tmp.
    static let maxFileBytes: UInt64 = 256 * 1024

    static func shouldTruncate(fileSize: UInt64) -> Bool { fileSize >= maxFileBytes }
}
