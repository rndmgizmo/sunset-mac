import Foundation
import CoreBluetooth

final class BluetoothLamp: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let name = "SSL-253FEB"
    private let serviceID = CBUUID(string: "0000ac50-1212-efde-1523-785fedbeda25")
    private let writeID = CBUUID(string: "0000ac52-1212-efde-1523-785fedbeda25")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notificationCharacteristic: CBCharacteristic?
    private var timeout: DispatchWorkItem?
    private var retry: DispatchWorkItem?
    private var handshakeFallback: DispatchWorkItem?
    private var rediscovery: DispatchWorkItem?
    private var scanEnd: DispatchWorkItem?
    private var replacement: CBPeripheral?
    private var restartAfterDisconnect = false
    private var consecutiveFailures = 0
    private var connectionStarted: TimeInterval?
    private var pending: Data?
    private var stopped = false
    private(set) var ready = false
    private(set) var status = "Bluetooth wird gestartet …"
    var onChange: (() -> Void)?
    var onState: (([UInt8]) -> Void)?
    var onReady: (() -> Void)?
    private var handshakeSent = false
    private let logURL = URL(fileURLWithPath: "/tmp/sunsetmac.log")

    override init() {
        super.init()
        try? Data().write(to: logURL)
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func log(_ message: String) {
        guard let file = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: Data(("\(Date()): \(message)\n").utf8))
    }

    private func update(_ text: String) {
        status = text; log(text); onChange?()
    }

    func reconnect(force: Bool = false) {
        stopped = false
        retry?.cancel()
        // An existing healthy link is already the fastest connection.
        if ready && !force { update("Verbunden"); return }
        // Do not reset an in-flight radio connection on repeated menu clicks.
        if peripheral?.state == .connecting && !force {
            startFallbackScan()
            return
        }
        timeout?.cancel(); handshakeFallback?.cancel(); rediscovery?.cancel(); scanEnd?.cancel()
        central.stopScan()
        pending = nil
        replacement = nil
        consecutiveFailures = 0
        resetConnection()
        if let peripheral, peripheral.state != .disconnected {
            restartAfterDisconnect = true
            central.cancelPeripheralConnection(peripheral)
        } else { restartAfterDisconnect = false; find() }
    }

    func stop() {
        stopped = true
        pending = nil
        restartAfterDisconnect = false; replacement = nil
        retry?.cancel(); timeout?.cancel(); handshakeFallback?.cancel(); rediscovery?.cancel(); scanEnd?.cancel()
        central.stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        resetConnection()
        update("Verbindung getrennt")
    }

    func send(_ data: Data) {
        guard !stopped else { update("Bitte zuerst verbinden"); return }
        pending = data
        flush()
        if !ready && peripheral?.state != .connecting && peripheral?.state != .connected { find() }
    }

    private func flush() {
        guard ready, let peripheral, let characteristic = writeCharacteristic,
              peripheral.canSendWriteWithoutResponse, let data = pending else { return }
        pending = nil
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        log("TX RGB: \(data.map { String(format: "%02x", $0) }.joined())")
    }

    private func resetConnection() {
        ready = false; handshakeSent = false
        writeCharacteristic = nil; notificationCharacteristic = nil
        handshakeFallback?.cancel()
    }

    private func find(useSaved: Bool = true) {
        guard !stopped, central.state == .poweredOn else { return }
        if peripheral?.state == .connecting || peripheral?.state == .connected { return }
        retry?.cancel(); timeout?.cancel()
        resetConnection()
        update("Suche \(Self.name) …")
        let saved = UserDefaults.standard.string(forKey: "peripheralID").flatMap(UUID.init(uuidString:))
        if useSaved, let connected = central.retrieveConnectedPeripherals(withServices: [serviceID]).first(where: {
            $0.identifier == saved || $0.name?.caseInsensitiveCompare(Self.name) == .orderedSame
        }) {
            connect(connected)
        } else if useSaved, let uuid = saved,
           let known = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            connect(known)
        } else {
            central.scanForPeripherals(withServices: nil)
            armTimeout()
        }
    }

    private func armTimeout() {
        timeout?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped, !self.ready else { return }
            self.pending = nil
            if self.peripheral?.state == .connecting {
                // CoreBluetooth keeps this request pending until the lamp returns.
                // Canceling every 20 seconds used to create recurring 8-second blind gaps.
                self.update("Warte auf Lampe · Reichweite und iPhone-App prüfen")
                return
            }
            self.central.stopScan()
            self.update("Lampe nicht erreichbar · iPhone-App schließen")
            if let peripheral = self.peripheral, peripheral.state != .disconnected {
                self.central.cancelPeripheralConnection(peripheral)
            } else { self.scheduleRetry() }
        }
        timeout = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: task)
    }

    private func scheduleRetry() {
        guard !stopped else { return }
        retry?.cancel()
        let delay = ConnectionTiming.retryDelay(afterFailures: consecutiveFailures)
        consecutiveFailures += 1
        log(String(format: "Retry in %.2f s", delay))
        let task = DispatchWorkItem { [weak self] in self?.find() }
        retry = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func connect(_ device: CBPeripheral) {
        guard !stopped, central.state == .poweredOn else { return }
        peripheral = device
        device.delegate = self
        central.stopScan()
        rediscovery?.cancel(); scanEnd?.cancel()
        connectionStarted = ProcessInfo.processInfo.systemUptime
        update("Verbinde mit \(Self.name) …")
        central.connect(device)
        armTimeout()
        let fallback = DispatchWorkItem { [weak self] in
            guard let self, self.peripheral?.state == .connecting else { return }
            self.startFallbackScan()
        }
        rediscovery = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: fallback)
    }

    private func startFallbackScan() {
        guard !stopped, !ready, central.state == .poweredOn, !central.isScanning else { return }
        log("Checking for a changed Bluetooth identifier")
        central.scanForPeripherals(withServices: nil)
        let end = DispatchWorkItem { [weak self] in self?.central.stopScan() }
        scanEnd?.cancel(); scanEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: end)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            retry?.cancel(); timeout?.cancel(); rediscovery?.cancel(); scanEnd?.cancel()
            pending = nil; replacement = nil; restartAfterDisconnect = false
            resetConnection()
        }
        switch central.state {
        case .poweredOn: find()
        case .poweredOff: update("Bluetooth ist ausgeschaltet")
        case .unauthorized: update("Bluetooth-Zugriff in den Systemeinstellungen erlauben")
        case .unsupported: update("Bluetooth LE wird nicht unterstützt")
        default: update("Bluetooth wird gestartet …")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover device: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? device.name ?? ""
        guard !stopped, name.caseInsensitiveCompare(Self.name) == .orderedSame else { return }
        if let current = peripheral, current.state != .disconnected {
            guard current.state == .connecting, replacement == nil else { return }
            central.stopScan(); scanEnd?.cancel()
            guard current.identifier != device.identifier else { return }
            log("Lamp identifier changed; switching to freshly discovered device")
            replacement = device
            central.cancelPeripheralConnection(current)
            return
        }
        log("Found \(name), RSSI \(RSSI)")
        connect(device)
    }

    func centralManager(_ central: CBCentralManager, didConnect device: CBPeripheral) {
        guard !stopped, device == peripheral, !restartAfterDisconnect, replacement == nil else {
            central.cancelPeripheralConnection(device); return
        }
        central.stopScan(); rediscovery?.cancel(); scanEnd?.cancel()
        UserDefaults.standard.set(device.identifier.uuidString, forKey: "peripheralID")
        log("Connected: \(device.identifier)")
        device.discoverServices([serviceID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect device: CBPeripheral, error: Error?) {
        guard device == peripheral else { return }
        timeout?.cancel(); pending = nil; resetConnection()
        if resumeAfterCancellation() { return }
        update("Verbindung fehlgeschlagen")
        log(error?.localizedDescription ?? "Unknown connection error")
        scheduleRetry()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral device: CBPeripheral, error: Error?) {
        guard device == peripheral else { return }
        timeout?.cancel(); pending = nil; resetConnection()
        if resumeAfterCancellation() { return }
        if !stopped { update("Verbindung verloren · erneuter Versuch folgt"); scheduleRetry() }
    }

    private func resumeAfterCancellation() -> Bool {
        rediscovery?.cancel(); scanEnd?.cancel(); central.stopScan()
        guard !stopped, central.state == .poweredOn else { return true }
        if let device = replacement {
            replacement = nil; restartAfterDisconnect = false
            connect(device)
            return true
        }
        if restartAfterDisconnect {
            restartAfterDisconnect = false
            log("Manual reconnect: continuing immediately after disconnect")
            find()
            return true
        }
        return false
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
            update("iStrip-Steuerdienst nicht verfügbar"); return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil,
              let write = service.characteristics?.first(where: { $0.uuid == writeID && $0.properties.contains(.writeWithoutResponse) }) else {
            update("iStrip-Steuerkanal nicht verfügbar"); return
        }
        writeCharacteristic = write
        if let notify = service.characteristics?.first(where: { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }) {
            notificationCharacteristic = notify
            peripheral.setNotifyValue(true, for: notify)
        } else { beginHandshake() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic == notificationCharacteristic else { return }
        if let error { log("Notifications unavailable: \(error.localizedDescription)") }
        beginHandshake()
    }

    private func beginHandshake() {
        guard !stopped, !handshakeSent, let peripheral, let characteristic = writeCharacteristic else { return }
        guard peripheral.canSendWriteWithoutResponse else { return }
        handshakeSent = true
        peripheral.writeValue(LampProtocol.join(), for: characteristic, type: .withoutResponse)
        log("TX JOIN")
        let fallback = DispatchWorkItem { [weak self] in self?.markReady() }
        handshakeFallback = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: fallback)
    }

    private func markReady() {
        guard !stopped, !ready, peripheral?.state == .connected, handshakeSent else { return }
        handshakeFallback?.cancel(); timeout?.cancel()
        ready = true
        consecutiveFailures = 0
        if let start = connectionStarted {
            log(String(format: "READY in %.3f s", ProcessInfo.processInfo.systemUptime - start))
        }
        update("Verbunden")
        flush()
        onReady?()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        if !handshakeSent { beginHandshake() } else { flush() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, let bytes = LampProtocol.decrypt(data) else { return }
        log("RX: \(bytes.map { String(format: "%02x", $0) }.joined())")
        if bytes[4] == 1 { log("JOIN confirmed by lamp"); markReady() }
        if bytes[4] == 2 { onState?(bytes) }
    }
}
