import AppKit

// Sunset lives only in the menu bar (LSUIElement): no Dock icon, no app menu, no window.
// The menu is built the first time it opens; the system color panel loads only on request.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var connectionItem: NSMenuItem?
    private var powerItem: NSMenuItem?
    private var brightnessText: NSTextField?
    private var slider: NSSlider?
    private var presetItems: [NSMenuItem] = []
    private var customItem: NSMenuItem?
    private var effectItems: [NSMenuItem] = []
    private var controlledItems: [NSMenuItem] = []
    private var lamp: BluetoothLamp!
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
    private let presets = LampPresentation.presets

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let values = defaults.array(forKey: "lastRGB") as? [Int], values.count == 3 {
            red = UInt8(clamping: values[0]); green = UInt8(clamping: values[1]); blue = UInt8(clamping: values[2])
        }
        if defaults.object(forKey: "brightness") != nil { brightness = max(1, min(100, defaults.integer(forKey: "brightness"))) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.horizon.fill", accessibilityDescription: "Sunset-Lampe")
        statusItem.button?.image?.isTemplate = true
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        let level = LogLevel.resolve(arguments: CommandLine.arguments, stored: defaults.string(forKey: "logLevel"))
        lamp = BluetoothLamp(logLevel: level)
        lamp.onChange = { [weak self] in self?.refresh() }
        lamp.onState = { [weak self] bytes in self?.receive(bytes) }
        lamp.onReady = { [weak self] in self?.runChecks() }
        refresh()
        if CommandLine.arguments.contains("--test-menu") {
            // Opens the menu once and closes it again; changes nothing on the lamp.
            // Run-loop timers, not GCD: menu tracking inside a main-queue block would
            // stall the main queue (and Bluetooth callbacks) until the menu closes.
            let close = Timer(timeInterval: 8, repeats: false) { [weak self] _ in self?.menu.cancelTracking() }
            let open = Timer(timeInterval: 5, repeats: false) { [weak self] _ in self?.statusItem.button?.performClick(nil) }
            RunLoop.main.add(close, forMode: .common)
            RunLoop.main.add(open, forMode: .common)
        }
    }

    // Opening Sunset again from Programme shows the menu instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.button?.performClick(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Only the Bluetooth link is released; the lamp keeps its current light.
        delayedSend?.cancel(); lamp.stop()
        if colorPanelOpen { NSColorPanel.shared.close() }
    }

    private func runChecks() {
        if runOrangeTest {
            runOrangeTest = false
            red = 255; green = 80; blue = 8
            brightness = 40; mode = 0; speed = 100
            applyColor()
        }
        if reconnectChecksRemaining > 0 {
            reconnectChecksRemaining -= 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                guard let self, self.lamp.ready else { return }
                self.lamp.log("CHECK: manual reconnect")
                self.lamp.reconnect(force: true)
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === self.menu && menu.items.isEmpty { buildMenu() }
        refresh()
    }

    private func addItem(_ title: String, _ action: Selector?, to target: NSMenu? = nil, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == nil ? nil : self
        item.isEnabled = action != nil
        (target ?? menu).addItem(item)
        return item
    }

    private func buildMenu() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let title = addItem("Sunset", nil)
        title.attributedTitle = NSAttributedString(string: "Sunset \(version)", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        _ = addItem(BluetoothLamp.name, nil)
        connectionItem = addItem("", nil)
        menu.addItem(.separator())

        let power = addItem("Einschalten", #selector(togglePower))
        powerItem = power; controlledItems.append(power)

        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 50))
        let text = NSTextField(labelWithString: "")
        text.frame = NSRect(x: 20, y: 28, width: 220, height: 16)
        text.font = .menuFont(ofSize: 12)
        text.textColor = .secondaryLabelColor
        let control = NSSlider(value: Double(brightness), minValue: 1, maxValue: 100, target: self, action: #selector(changeBrightness))
        control.frame = NSRect(x: 18, y: 4, width: 224, height: 22)
        control.isContinuous = true
        control.setAccessibilityLabel("Helligkeit in Prozent")
        sliderView.addSubview(text); sliderView.addSubview(control)
        let sliderItem = NSMenuItem()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)
        brightnessText = text; slider = control
        menu.addItem(.separator())

        for (index, preset) in presets.enumerated() {
            let item = addItem(preset.name, #selector(selectPreset(_:)))
            item.tag = index
            item.attributedTitle = swatchTitle(preset)
            presetItems.append(item); controlledItems.append(item)
        }
        let custom = addItem("Eigene Farbe …", #selector(showColors))
        customItem = custom; controlledItems.append(custom)

        let effects = addItem("Sanfte Farbwechsel", nil)
        let effectMenu = NSMenu()
        effectMenu.autoenablesItems = false
        for effect in LampPresentation.effects {
            let item = addItem(effect.name, #selector(selectEffect(_:)), to: effectMenu)
            item.tag = Int(effect.mode)
            effectItems.append(item); controlledItems.append(item)
        }
        effects.submenu = effectMenu
        controlledItems.append(effects)
        menu.addItem(.separator())

        _ = addItem("Erneut verbinden", #selector(reconnect))
        let release = addItem("Verbindung freigeben", #selector(disconnect))
        release.toolTip = "Gibt die Bluetooth-Verbindung für die iPhone-App frei. Die Lampe leuchtet weiter."
        menu.addItem(.separator())
        let quit = addItem("Sunset beenden", #selector(quit), key: "q")
        quit.toolTip = "Beendet Sunset und trennt Bluetooth. Die Lampe behält ihre Einstellung."
    }

    // A coloured dot in the title: current macOS menus do not show item images here.
    private func swatchTitle(_ preset: Preset) -> NSAttributedString {
        let color = NSColor(srgbRed: CGFloat(preset.red) / 255, green: CGFloat(preset.green) / 255,
                            blue: CGFloat(preset.blue) / 255, alpha: 1)
        let title = NSMutableAttributedString(string: "●  ", attributes: [.foregroundColor: color, .font: NSFont.menuFont(ofSize: 0)])
        title.append(NSAttributedString(string: preset.name, attributes: [.font: NSFont.menuFont(ofSize: 0)]))
        return title
    }

    private func refresh() {
        guard lamp != nil else { return }
        if !lamp.ready { hasState = false }
        statusItem.button?.appearsDisabled = !lamp.ready
        statusItem.button?.toolTip = "Sunset · \(lamp.status)"
        guard !menu.items.isEmpty else { return }   // menu not built yet

        connectionItem?.title = lamp.status
        powerItem?.title = LampPresentation.powerTitle(hasState: hasState, isOn: isOn)
        for item in controlledItems { item.isEnabled = lamp.ready }
        if let slider {
            slider.isEnabled = lamp.ready
            if !slider.isHighlighted { slider.doubleValue = Double(brightness) }
        }
        brightnessText?.stringValue = LampPresentation.brightnessTitle(brightness)
        let selection = LampPresentation.selection(hasState: hasState, isOn: isOn, red: red, green: green, blue: blue, mode: mode)
        for item in presetItems { item.state = selection == .preset(item.tag) ? .on : .off }
        customItem?.state = selection == .custom ? .on : .off
        for item in effectItems { item.state = selection == .effect(UInt8(item.tag)) ? .on : .off }
    }

    // MARK: Lamp actions

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
        delayedSend?.cancel()
        let preset = presets[sender.tag]
        red = preset.red; green = preset.green; blue = preset.blue; mode = 0; speed = 100
        applyColor()
    }

    @objc private func changeBrightness(_ sender: NSSlider) {
        brightness = max(1, min(100, Int(sender.doubleValue.rounded())))
        brightnessText?.stringValue = LampPresentation.brightnessTitle(brightness)
        debounceColor()
    }

    private func debounceColor() {
        delayedSend?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyColor() }
        delayedSend = work
        // One-shot, only while the user drags; the main queue also runs during menu tracking.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    @objc private func showColors() {
        installEditShortcuts()
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

    // Invisible for a menu bar app, but it routes ⌘C/⌘V/⌘W to the color panel's fields.
    private func installEditShortcuts() {
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu(), holder = NSMenuItem(), edit = NSMenu(title: "Bearbeiten")
        edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        holder.submenu = edit
        main.addItem(holder)
        NSApp.mainMenu = main
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
        guard let state = LampPresentation.decodeState(bytes) else { return }
        hasState = true
        isOn = state.isOn
        if state.isOn {
            red = state.red; green = state.green; blue = state.blue
            brightness = state.brightness; mode = state.mode; speed = state.speed
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
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
