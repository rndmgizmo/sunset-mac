import Foundation

struct Preset {
    let name: String
    let red: UInt8, green: UInt8, blue: UInt8
}

// Pure menu state, kept free of AppKit so it can be tested.
enum LampPresentation {
    static let presets = [
        Preset(name: "Sunset", red: 255, green: 80, blue: 8), Preset(name: "Gold", red: 255, green: 170, blue: 32),
        Preset(name: "Rosé", red: 255, green: 36, blue: 100), Preset(name: "Violett", red: 130, green: 40, blue: 255),
        Preset(name: "Ozean", red: 20, green: 100, blue: 255), Preset(name: "Warmweiß", red: 255, green: 210, blue: 160)
    ]
    static let effects: [(name: String, mode: UInt8)] = [("7 Farben überblenden", 1), ("3 Farben überblenden", 2)]

    enum Selection: Equatable {
        case unknown, off, preset(Int), custom, effect(UInt8)
    }

    // Without a confirmed lamp state nothing is checked: Sunset never guesses.
    static func selection(hasState: Bool, isOn: Bool, red: UInt8, green: UInt8, blue: UInt8, mode: UInt8) -> Selection {
        guard hasState else { return .unknown }
        guard isOn else { return .off }
        if mode != 0 { return .effect(mode) }
        if let index = presets.firstIndex(where: { $0.red == red && $0.green == green && $0.blue == blue }) {
            return .preset(index)
        }
        return .custom
    }

    static func powerTitle(hasState: Bool, isOn: Bool) -> String {
        hasState && isOn ? "Ausschalten" : "Einschalten"
    }

    static func brightnessTitle(_ brightness: Int) -> String { "Helligkeit  ·  \(brightness) %" }

    // Lamp state notification: bytes 6 mode, 7–9 RGB, 10 brightness, 11 speed.
    struct LampState: Equatable {
        let isOn: Bool
        let red: UInt8, green: UInt8, blue: UInt8, brightness: Int, mode: UInt8, speed: Int
    }

    static func decodeState(_ bytes: [UInt8]) -> LampState? {
        guard bytes.count >= 12 else { return nil }
        let on = bytes[10] > 0 && (bytes[6] > 0 || bytes[7] > 0 || bytes[8] > 0 || bytes[9] > 0)
        return LampState(isOn: on, red: bytes[7], green: bytes[8], blue: bytes[9],
                         brightness: max(1, min(100, Int(bytes[10]))), mode: bytes[6],
                         speed: max(1, min(100, Int(bytes[11]))))
    }
}
