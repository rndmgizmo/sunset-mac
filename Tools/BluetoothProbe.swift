import AppKit
import CoreBluetooth

// Read-only inspection: no pairing, subscriptions, or light commands.
final class BluetoothProbe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var lamp: CBPeripheral?
    private var pendingServices = 0
    private var finished = false
    private let target = "SSL-253FEB"
    private let logURL = URL(fileURLWithPath: "/tmp/sunset-bt-probe.log")

    func start() {
        try? Data().write(to: logURL)
        log("Searching for \(target)")
        central = CBCentralManager(delegate: self, queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [self] in
            finish(lamp == nil ? "TIMEOUT: lamp not found" : "TIMEOUT: service discovery incomplete")
        }
    }

    private func log(_ message: String) {
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((message + "\n").utf8))
    }

    private func finish(_ message: String) {
        guard !finished else { return }
        finished = true
        log(message)
        central.stopScan()
        if let lamp { central.cancelPeripheralConnection(lamp) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("Bluetooth state: \(central.state.rawValue), authorization: \(CBManager.authorization.rawValue)")
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: nil)
        case .unauthorized: finish("BLOCKED: Bluetooth permission required")
        case .poweredOff: finish("BLOCKED: Bluetooth is turned off")
        case .unsupported: finish("BLOCKED: Bluetooth LE unsupported")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard name.caseInsensitiveCompare(target) == .orderedSame, lamp == nil else { return }
        lamp = peripheral
        log("FOUND: \(name), identifier: \(peripheral.identifier), signal: \(RSSI) dBm")
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            log("Manufacturer data: " + data.map { String(format: "%02x", $0) }.joined())
        }
        central.stopScan()
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("CONNECTED")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish("CONNECTION FAILED: \(error?.localizedDescription ?? "unknown error")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if !finished { finish("DISCONNECTED: \(error?.localizedDescription ?? "connection closed")") }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { finish("SERVICE ERROR: \(error.localizedDescription)"); return }
        let services = peripheral.services ?? []
        pendingServices = services.count
        if services.isEmpty { finish("No services discovered"); return }
        for service in services {
            log("SERVICE: \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { log("CHARACTERISTIC ERROR: \(error.localizedDescription)") }
        for char in service.characteristics ?? [] {
            var properties: [String] = []
            if char.properties.contains(.read) { properties.append("read") }
            if char.properties.contains(.write) { properties.append("write") }
            if char.properties.contains(.writeWithoutResponse) { properties.append("write-without-response") }
            if char.properties.contains(.notify) { properties.append("notify") }
            if char.properties.contains(.indicate) { properties.append("indicate") }
            log("CHAR: \(service.uuid.uuidString) / \(char.uuid.uuidString) [\(properties.joined(separator: ", "))]")
        }
        pendingServices -= 1
        if pendingServices == 0 { finish("DONE: inspection complete; no light commands sent") }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let probe = BluetoothProbe()
probe.start()
app.run()
