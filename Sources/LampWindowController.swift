import AppKit

private final class LightPreview: NSView {
    var color = NSColor(srgbRed: 1, green: 0.31, blue: 0.03, alpha: 1) { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18)
        NSColor.controlBackgroundColor.setFill()
        background.fill()
        NSGraphicsContext.saveGraphicsState()
        background.addClip()
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let halo = NSRect(x: center.x - 128, y: center.y - 128, width: 256, height: 256)
        NSGradient(starting: color.withAlphaComponent(0.44), ending: color.withAlphaComponent(0))?
            .draw(in: NSBezierPath(ovalIn: halo), relativeCenterPosition: .zero)
        let disc = NSRect(x: center.x - 43, y: center.y - 43, width: 86, height: 86)
        NSGradient(starting: color.blended(withFraction: 0.24, of: .white) ?? color, ending: color)?
            .draw(in: NSBezierPath(ovalIn: disc), angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class LampWindowController: NSWindowController {
    var onPower: (() -> Void)?
    var onBrightness: ((Int) -> Void)?
    var onPreset: ((Int) -> Void)?
    var onCustomColor: (() -> Void)?
    var onEffect: ((Int) -> Void)?
    var onReconnect: (() -> Void)?
    var onDisconnect: (() -> Void)?

    private let statusLabel = NSTextField(wrappingLabelWithString: "Bluetooth wird gestartet …")
    private let indicator = NSImageView()
    private let preview = LightPreview()
    private let selectionLabel = NSTextField(labelWithString: "Letzte Farbauswahl")
    private let powerButton = NSButton(title: "Einschalten", target: nil, action: nil)
    private let brightnessSlider = NSSlider(value: 40, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let brightnessValue = NSTextField(labelWithString: "40 %")
    private let effectPicker = NSPopUpButton()
    private var controls: [NSControl] = []
    private var presetButtons: [NSButton] = []
    private let presets: [(String, UInt8, UInt8, UInt8)]

    init(presets: [(String, UInt8, UInt8, UInt8)]) {
        self.presets = presets
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Sunset"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.titlebarAppearsTransparent = true
        window.setFrameAutosaveName("SunsetMainWindow")
        window.center()
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func row(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let result = NSTextField(labelWithString: text)
        result.font = .systemFont(ofSize: size, weight: weight)
        return result
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 16)
        ])

        let heading = label("Sunset", size: 28, weight: .bold)
        let name = label(BluetoothLamp.name, size: 12)
        name.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [heading, name])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 3
        let headerSpacer = NSView()
        powerButton.bezelStyle = .rounded
        powerButton.controlSize = .large
        powerButton.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        powerButton.imagePosition = .imageLeading
        powerButton.target = self; powerButton.action = #selector(power)
        powerButton.setContentHuggingPriority(.required, for: .horizontal)
        let header = row([titles, headerSpacer, powerButton])
        root.addArrangedSubview(header)

        indicator.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([indicator.widthAnchor.constraint(equalToConstant: 9), indicator.heightAnchor.constraint(equalToConstant: 9)])
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        let status = row([indicator, statusLabel], spacing: 7)
        root.addArrangedSubview(status)

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalToConstant: 132).isActive = true
        preview.setAccessibilityLabel("Vorschau der gewählten Lichtfarbe")
        root.addArrangedSubview(preview)

        selectionLabel.font = .systemFont(ofSize: 12)
        selectionLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(selectionLabel)

        let brightnessLabel = label("Helligkeit", weight: .semibold)
        brightnessValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        brightnessValue.alignment = .right
        let brightnessHeader = row([brightnessLabel, NSView(), brightnessValue])
        root.addArrangedSubview(brightnessHeader)
        root.setCustomSpacing(4, after: brightnessHeader)
        brightnessSlider.target = self; brightnessSlider.action = #selector(brightnessChanged)
        brightnessSlider.isContinuous = true
        brightnessSlider.setAccessibilityLabel("Helligkeit in Prozent")
        root.addArrangedSubview(brightnessSlider)

        let paletteTitle = label("Lichtstimmungen", weight: .semibold)
        root.addArrangedSubview(paletteTitle)
        root.setCustomSpacing(8, after: paletteTitle)
        let grid = NSStackView()
        grid.orientation = .vertical; grid.spacing = 8; grid.alignment = .leading
        for start in stride(from: 0, to: presets.count, by: 3) {
            var buttons: [NSView] = []
            for index in start..<min(start + 3, presets.count) {
                let preset = presets[index]
                let button = NSButton(title: preset.0, target: self, action: #selector(presetSelected(_:)))
                button.tag = index
                button.bezelStyle = .rounded
                button.imagePosition = .imageLeading
                button.image = swatch(preset.1, preset.2, preset.3)
                button.controlSize = .large
                button.setAccessibilityLabel(preset.0)
                presetButtons.append(button); controls.append(button); buttons.append(button)
            }
            let line = row(buttons, spacing: 8)
            line.distribution = .fillEqually
            grid.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        }
        root.addArrangedSubview(grid)

        let custom = NSButton(title: "Eigene Farbe …", target: self, action: #selector(customColor))
        custom.bezelStyle = .rounded
        custom.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
        custom.imagePosition = .imageLeading
        effectPicker.addItems(withTitles: ["Statische Farbe", "7 Farben überblenden", "3 Farben überblenden"])
        effectPicker.target = self; effectPicker.action = #selector(effectChanged)
        effectPicker.setAccessibilityLabel("Farbwechsel")
        let colorOptions = row([custom, NSView(), effectPicker])
        root.addArrangedSubview(colorOptions)
        controls += [powerButton, brightnessSlider, custom, effectPicker]

        let divider = NSBox(); divider.boxType = .separator
        root.addArrangedSubview(divider)
        let connect = NSButton(title: "Verbinden", target: self, action: #selector(reconnect))
        connect.bezelStyle = .rounded
        let disconnect = NSButton(title: "Für iPhone freigeben", target: self, action: #selector(releaseConnection))
        disconnect.bezelStyle = .rounded
        disconnect.toolTip = "Trennt die Bluetooth-Verbindung. Die Lampe leuchtet weiter."
        let connections = row([connect, NSView(), disconnect])
        root.addArrangedSubview(connections)
        let hint = label("Beim Schließen bleibt Sunset in der Menüleiste aktiv.", size: 11)
        hint.textColor = .tertiaryLabelColor
        root.addArrangedSubview(hint)

        for view in [header, status, preview, brightnessHeader, brightnessSlider, grid, colorOptions, divider, connections] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        // Size to the actual native control metrics, including larger accessibility fonts.
        content.layoutSubtreeIfNeeded()
        let height = root.fittingSize.height + 40
        window?.setContentSize(NSSize(width: 480, height: max(650, height)))
    }

    private func swatch(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    func update(ready: Bool, status: String, isOn: Bool, hasState: Bool,
                red: UInt8, green: UInt8, blue: UInt8, brightness: Int, mode: UInt8) {
        statusLabel.stringValue = status
        indicator.contentTintColor = ready ? .systemGreen : .secondaryLabelColor
        for control in controls { control.isEnabled = ready }
        powerButton.title = hasState && isOn ? "Ausschalten" : "Einschalten"
        brightnessValue.stringValue = "\(brightness) %"
        if !brightnessSlider.isHighlighted { brightnessSlider.doubleValue = Double(brightness) }
        preview.color = NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        let preset = presets.first { $0.1 == red && $0.2 == green && $0.3 == blue }
        if hasState {
            selectionLabel.stringValue = isOn ? (mode == 0 ? preset?.0 ?? "Eigene Farbe" : "Sanfter Farbwechsel") : "Lampe ausgeschaltet"
        } else { selectionLabel.stringValue = "Letzte Farbauswahl · \(preset?.0 ?? "Eigene Farbe")" }
        effectPicker.selectItem(at: mode == 1 ? 1 : mode == 2 ? 2 : 0)
        for button in presetButtons {
            let entry = presets[button.tag]
            button.state = mode == 0 && entry.1 == red && entry.2 == green && entry.3 == blue ? .on : .off
        }
    }

    @objc private func power() { onPower?() }
    @objc private func brightnessChanged() { onBrightness?(Int(brightnessSlider.doubleValue.rounded())) }
    @objc private func presetSelected(_ sender: NSButton) { onPreset?(sender.tag) }
    @objc private func customColor() { onCustomColor?() }
    @objc private func effectChanged() { onEffect?(effectPicker.indexOfSelectedItem) }
    @objc private func reconnect() { onReconnect?() }
    @objc private func releaseConnection() { onDisconnect?() }
}
