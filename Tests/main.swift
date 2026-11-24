import Foundation

func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

// Independent AES-ECB vectors cross-checked with OpenSSL.
precondition(hex(LampProtocol.join()) == "814070cf48ab60e4b8079d5e273c78a0")
let orange = LampProtocol.color(red: 255, green: 80, blue: 8, brightness: 40)
precondition(hex(orange) == "706272fc3fee3259ec18c67d341bf90c")
let decoded = LampProtocol.decrypt(orange)!
precondition(decoded == [0x54, 0x52, 0, 0x57, 2, 1, 0, 255, 80, 8, 40, 100, 0, 0, 0, 0])
precondition(LampProtocol.decrypt(Data(repeating: 0, count: 16)) == nil)
precondition(LampProtocol.decrypt(Data(repeating: 0, count: 15)) == nil)
let off = LampProtocol.decrypt(LampProtocol.off())!
precondition(off[6...10].allSatisfy { $0 == 0 })
let clamped = LampProtocol.decrypt(LampProtocol.color(red: 1, green: 2, blue: 3, brightness: 999, speed: -10))!
precondition(clamped[10] == 100 && clamped[11] == 1)
// Regression: the first reconnect must not spend eight seconds in a retry gap.
precondition(ConnectionTiming.retryDelay(afterFailures: 0) == 0)
let repeatedFailures = (0..<10).map { ConnectionTiming.retryDelay(afterFailures: $0) }
precondition(repeatedFailures == [0, 1, 2, 4, 8, 8, 8, 8, 8, 8])
// Scanning for an absent, unknown lamp stops after a bounded number of rounds.
precondition(ConnectionTiming.shouldScanAgain(afterUnsuccessfulScans: 0))
precondition(ConnectionTiming.shouldScanAgain(afterUnsuccessfulScans: ConnectionTiming.maxUnsuccessfulScans - 1))
precondition(!ConnectionTiming.shouldScanAgain(afterUnsuccessfulScans: ConnectionTiming.maxUnsuccessfulScans))
let scanBudget = (0..<ConnectionTiming.maxUnsuccessfulScans).reduce(0.0) {
    $0 + ConnectionTiming.scanDuration + ($1 < ConnectionTiming.maxUnsuccessfulScans - 1 ? ConnectionTiming.retryDelay(afterFailures: $1) : 0)
}
precondition(scanBudget > 60 && scanBudget < 180, "search should last roughly two minutes, got \(scanBudget)")

// Logging: basic by default, switchable, bounded in size.
precondition(LogLevel.resolve(arguments: [], stored: nil) == .basic)
precondition(LogLevel.resolve(arguments: [], stored: "off") == .off)
precondition(LogLevel.resolve(arguments: [], stored: "VERBOSE") == .verbose)
precondition(LogLevel.resolve(arguments: [], stored: "unbekannt") == .basic)
precondition(LogLevel.resolve(arguments: ["--log-verbose"], stored: "off") == .verbose)
precondition(LogLevel.resolve(arguments: ["--log-off", "--log-verbose"], stored: "verbose") == .off)
precondition(LogLevel.off < .basic && LogLevel.basic < .verbose)
precondition(!LogLevel.shouldTruncate(fileSize: 0) && LogLevel.shouldTruncate(fileSize: LogLevel.maxFileBytes))

// Menu state: nothing is checked until the lamp reports or receives a state.
typealias P = LampPresentation
precondition(P.presets.count == 6 && P.presets[0].name == "Sunset")
precondition(P.selection(hasState: false, isOn: true, red: 255, green: 80, blue: 8, mode: 0) == .unknown)
precondition(P.selection(hasState: true, isOn: false, red: 255, green: 80, blue: 8, mode: 0) == .off)
precondition(P.selection(hasState: true, isOn: true, red: 255, green: 80, blue: 8, mode: 0) == .preset(0))
precondition(P.selection(hasState: true, isOn: true, red: 255, green: 210, blue: 160, mode: 0) == .preset(5))
precondition(P.selection(hasState: true, isOn: true, red: 1, green: 2, blue: 3, mode: 0) == .custom)
precondition(P.selection(hasState: true, isOn: true, red: 255, green: 80, blue: 8, mode: 2) == .effect(2))
precondition(P.powerTitle(hasState: true, isOn: true) == "Ausschalten")
precondition(P.powerTitle(hasState: false, isOn: true) == "Einschalten")
precondition(P.powerTitle(hasState: true, isOn: false) == "Einschalten")
precondition(P.brightnessTitle(40) == "Helligkeit  ·  40 %")

// Lamp state notifications decode the colour packet the app itself sends.
let state = P.decodeState(decoded)!
precondition(state == P.LampState(isOn: true, red: 255, green: 80, blue: 8, brightness: 40, mode: 0, speed: 100))
precondition(P.decodeState(off)!.isOn == false)
precondition(P.decodeState(Array(decoded.prefix(11))) == nil)
let fading = P.decodeState(LampProtocol.decrypt(LampProtocol.color(red: 0, green: 0, blue: 0, brightness: 0, mode: 1, speed: 1))!)!
precondition(!fading.isOn && fading.brightness == 1, "brightness 0 means off; stored brightness stays within 1–100")
print("Checks passed: protocol, reconnect timing, bounded scan, logging policy, menu state, state decoding.")
