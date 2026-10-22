import AppKit
import CoreServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let connectionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let powerItem = NSMenuItem(title: "Einschalten", action: #selector(togglePower), keyEquivalent: "")
    private let brightnessText = NSTextField(labelWithString: "Helligkeit")
    private let slider = NSSlider(value: 40, minValue: 1, maxValue: 100, target: nil, action: nil)
    private var controlledItems: [NSMenuItem] = []
    private var lamp: BluetoothLamp!
    private var lampWindow: LampWindowController!
    private var explicitQuit = false
    private var red: UInt8 = 255
    private var green: UInt8 = 80
    private var blue: UInt8 = 8
    private var brightness = 40
    private var mode: UInt8 = 0
    private var speed = 100
    private var isOn = false
    private var hasState = false
    private var colorPanelOpen = false
    private var delayedSend: DispatchWorkItem?
    private var runOrangeTest = CommandLine.arguments.contains("--test-orange")
    private var reconnectChecksRemaining = CommandLine.arguments.contains("--test-reconnect") ? 2 : 0
    private let defaults = UserDefaults.standard
    private let presets: [(String, UInt8, UInt8, UInt8)] = [
        ("Sunset", 255, 80, 8), ("Gold", 255, 170, 32),
        ("Rosé", 255, 36, 100), ("Violett", 130, 40, 255),
        ("Ozean", 20, 100, 255), ("Warmweiß", 255, 210, 160)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let values = defaults.array(forKey: "lastRGB") as? [Int], values.count == 3 {
            red = UInt8(clamping: values[0]); green = UInt8(clamping: values[1]); blue = UInt8(clamping: values[2])
        }
        if defaults.object(forKey: "brightness") != nil { brightness = max(1, min(100, defaults.integer(forKey: "brightness"))) }
        buildMenu()
        buildApplicationMenu()
        buildWindow()
        lamp = BluetoothLamp()
        lamp.onChange = { [weak self] in self?.refresh() }
        lamp.onState = { [weak self] bytes in self?.receive(bytes) }
        lamp.onReady = { [weak self] in
            guard let self else { return }
            if self.runOrangeTest {
                self.runOrangeTest = false
                self.red = 255; self.green = 80; self.blue = 8
                self.brightness = 40; self.mode = 0; self.speed = 100
                self.applyColor()
            }
            if self.reconnectChecksRemaining > 0 {
                self.reconnectChecksRemaining -= 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                    guard let self, self.lamp.ready else { return }
                    self.lamp.log("CHECK: manual reconnect")
                    self.lamp.reconnect(force: true)
                }
            }
        }
        refresh()
        showWindow()
    }

    private func buildApplicationMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Sunset")
        appMenu.addItem(withTitle: "Über Sunset", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Sunset ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        let background = NSMenuItem(title: "Sunset beenden", action: #selector(quit), keyEquivalent: "q")
        background.target = self
        appMenu.addItem(background)
        let fullQuit = NSMenuItem(title: "Vollständig beenden", action: #selector(quitCompletely), keyEquivalent: "q")
        fullQuit.keyEquivalentModifierMask = [.command, .option]
        fullQuit.target = self
        appMenu.addItem(fullQuit)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Bearbeiten")
        editMenu.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Fenster")
        let show = NSMenuItem(title: "Sunset öffnen", action: #selector(showWindow), keyEquivalent: "0")
        show.target = self; windowMenu.addItem(show)
        windowMenu.addItem(withTitle: "Minimieren", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func buildWindow() {
        lampWindow = LampWindowController(presets: presets)
        lampWindow.onPower = { [weak self] in self?.togglePower() }
        lampWindow.onBrightness = { [weak self] value in self?.setBrightness(value) }
        lampWindow.onPreset = { [weak self] index in self?.choosePreset(index) }
        lampWindow.onCustomColor = { [weak self] in self?.showColors() }
        lampWindow.onEffect = { [weak self] index in
            guard let self else { return }
            self.delayedSend?.cancel()
            self.mode = UInt8(index)
            self.speed = index == 0 ? 100 : 1
            self.applyColor()
        }
        lampWindow.onReconnect = { [weak self] in self?.reconnect() }
        lampWindow.onDisconnect = { [weak self] in self?.disconnect() }
    }

    @objc private func showWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        lampWindow.present()
        lamp?.log("Foreground mode: window open; Dock visible")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.horizon.fill", accessibilityDescription: "Sunset-Lampe")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "Sunset · \(BluetoothLamp.name)"
        statusItem.menu = menu
        menu.autoenablesItems = false
        menu.delegate = self

        let show = NSMenuItem(title: "Sunset öffnen …", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())

        let title = NSMenuItem(title: "Sunset", action: nil, keyEquivalent: "")
        title.attributedTitle = NSAttributedString(string: "Sunset", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        title.isEnabled = false
        menu.addItem(title)
        let device = NSMenuItem(title: BluetoothLamp.name, action: nil, keyEquivalent: "")
        device.isEnabled = false
        menu.addItem(device)
        connectionItem.isEnabled = false
        menu.addItem(connectionItem)
        menu.addItem(.separator())

        powerItem.target = self
        menu.addItem(powerItem)
        controlledItems.append(powerItem)

        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: 290, height: 62))
        brightnessText.frame = NSRect(x: 20, y: 36, width: 250, height: 18)
        brightnessText.font = .systemFont(ofSize: 12)
        slider.frame = NSRect(x: 18, y: 9, width: 254, height: 22)
        slider.target = self; slider.action = #selector(changeBrightness)
        slider.isContinuous = true
        slider.setAccessibilityLabel("Helligkeit in Prozent")
        sliderView.addSubview(brightnessText); sliderView.addSubview(slider)
        let sliderItem = NSMenuItem()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)
        menu.addItem(.separator())

        for (index, preset) in presets.enumerated() {
            let item = NSMenuItem(title: preset.0, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.image = swatch(preset.1, preset.2, preset.3)
            menu.addItem(item); controlledItems.append(item)
        }
        let custom = NSMenuItem(title: "Eigene Farbe …", action: #selector(showColors), keyEquivalent: "")
        custom.target = self
        menu.addItem(custom); controlledItems.append(custom)
        menu.addItem(.separator())

        let effects = NSMenuItem(title: "Sanfte Farbwechsel", action: nil, keyEquivalent: "")
        let effectMenu = NSMenu()
        effectMenu.autoenablesItems = false
        for (name, value) in [("7 Farben überblenden", 1), ("3 Farben überblenden", 2)] {
            let item = NSMenuItem(title: name, action: #selector(selectEffect(_:)), keyEquivalent: "")
            item.target = self; item.tag = value
            effectMenu.addItem(item); controlledItems.append(item)
        }
        effects.submenu = effectMenu
        menu.addItem(effects); controlledItems.append(effects)
        menu.addItem(.separator())

        let reconnect = NSMenuItem(title: "Erneut verbinden", action: #selector(reconnect), keyEquivalent: "")
        reconnect.target = self; menu.addItem(reconnect)
        let disconnect = NSMenuItem(title: "Verbindung freigeben", action: #selector(disconnect), keyEquivalent: "")
        disconnect.toolTip = "Gibt die Bluetooth-Verbindung für die iPhone-App frei. Die Lampe leuchtet weiter."
        disconnect.target = self; menu.addItem(disconnect)
        menu.addItem(.separator())
        let background = NSMenuItem(title: "Fenster und Dock ausblenden", action: #selector(quit), keyEquivalent: "q")
        background.target = self; menu.addItem(background)
        let quit = NSMenuItem(title: "Vollständig beenden", action: #selector(quitCompletely), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command, .option]
        quit.target = self; menu.addItem(quit)
    }

    private func swatch(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        guard lamp != nil else { return }
        if !lamp.ready { hasState = false }
        connectionItem.title = lamp.status
        powerItem.title = hasState && isOn ? "Ausschalten" : "Einschalten"
        powerItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        slider.isEnabled = lamp.ready
        for item in controlledItems { item.isEnabled = lamp.ready }
        if !slider.isHighlighted { slider.doubleValue = Double(brightness) }
        brightnessText.stringValue = "Helligkeit  ·  \(brightness) %"
        statusItem.button?.appearsDisabled = !lamp.ready
        statusItem.button?.toolTip = "Sunset · \(lamp.status)"
        lampWindow?.update(ready: lamp.ready, status: lamp.status, isOn: isOn, hasState: hasState,
                           red: red, green: green, blue: blue, brightness: brightness, mode: mode)
    }

    private func saveSelection() {
        defaults.set([Int(red), Int(green), Int(blue)], forKey: "lastRGB")
        defaults.set(brightness, forKey: "brightness")
    }

    private func applyColor() {
        guard lamp.ready else { return }
        isOn = true; hasState = true
        saveSelection()
        lamp.send(LampProtocol.color(red: red, green: green, blue: blue, brightness: brightness, mode: mode, speed: speed))
        refresh()
    }

    @objc private func togglePower() {
        delayedSend?.cancel()
        if hasState && isOn {
            lamp.send(LampProtocol.off()); isOn = false; hasState = true; refresh()
        } else { applyColor() }
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        choosePreset(sender.tag)
    }

    private func choosePreset(_ index: Int) {
        delayedSend?.cancel()
        let preset = presets[index]
        red = preset.1; green = preset.2; blue = preset.3; mode = 0; speed = 100
        applyColor()
    }

    @objc private func changeBrightness() {
        setBrightness(Int(slider.doubleValue.rounded()))
    }

    private func setBrightness(_ value: Int) {
        brightness = max(1, min(100, value))
        refresh()
        debounceColor()
    }

    private func debounceColor() {
        delayedSend?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyColor() }
        delayedSend = work
        // CoreBluetooth uses the main queue; common run-loop modes keep this responsive while the menu tracks.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    @objc private func showColors() {
        let panel = NSColorPanel.shared
        panel.color = NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self); panel.setAction(#selector(pickColor(_:)))
        panel.title = "Sunset · Eigene Farbe"
        colorPanelOpen = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func pickColor(_ sender: NSColorPanel) {
        guard let color = sender.color.usingColorSpace(.sRGB) else { return }
        red = UInt8(clamping: Int((color.redComponent * 255).rounded()))
        green = UInt8(clamping: Int((color.greenComponent * 255).rounded()))
        blue = UInt8(clamping: Int((color.blueComponent * 255).rounded()))
        mode = 0; speed = 100
        debounceColor()
    }

    @objc private func selectEffect(_ sender: NSMenuItem) {
        delayedSend?.cancel()
        mode = UInt8(sender.tag); speed = 1
        applyColor()
    }

    private func receive(_ bytes: [UInt8]) {
        hasState = true
        isOn = bytes[10] > 0 && (bytes[6] > 0 || bytes[7] > 0 || bytes[8] > 0 || bytes[9] > 0)
        if isOn {
            red = bytes[7]; green = bytes[8]; blue = bytes[9]
            brightness = max(1, min(100, Int(bytes[10])))
            mode = bytes[6]; speed = max(1, min(100, Int(bytes[11])))
            saveSelection()
        }
        refresh()
    }

    @objc private func reconnect() {
        delayedSend?.cancel()
        if !lamp.ready { hasState = false }
        lamp.reconnect()
    }
    @objc private func disconnect() { delayedSend?.cancel(); lamp.stop() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func quitCompletely() {
        explicitQuit = true
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let reason = (event?.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))
                      ?? event?.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason)))?.enumCodeValue
        if TerminationPolicy.shouldTerminate(explicitQuit: explicitQuit, systemReason: reason) {
            return .terminateNow
        }
        for window in sender.windows { window.orderOut(nil) }
        sender.hide(nil)
        sender.setActivationPolicy(.accessory)
        lamp.log("Background mode: window hidden; accessory=\(sender.activationPolicy() == .accessory); Bluetooth remains active")
        return .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        delayedSend?.cancel(); lamp.stop()
        if colorPanelOpen { NSColorPanel.shared.close() }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
