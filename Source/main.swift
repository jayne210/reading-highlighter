import AppKit
import Carbon
import ImageIO

// A local, menu-bar reading aid. No network, document access, or key logging.
struct HighlightStyle {
    var width: CGFloat = 420
    var height: CGFloat = 28
    var opacity: CGFloat = 0.30
    var colorIndex: Int = 0
    var fullWidth = false
    static let colors: [NSColor] = [
        NSColor(srgbRed: 1, green: 0.84, blue: 0.02, alpha: 1),
        NSColor(srgbRed: 0.40, green: 0.88, blue: 0.54, alpha: 1),
        NSColor(srgbRed: 0.32, green: 0.75, blue: 1, alpha: 1),
        NSColor(srgbRed: 1, green: 0.48, blue: 0.68, alpha: 1)
    ]
    var color: NSColor { Self.colors[max(0, min(colorIndex, Self.colors.count - 1))] }
    func frame(at mouse: NSPoint, in screen: NSRect) -> NSRect {
        let w = fullWidth ? screen.width : min(width, screen.width)
        let h = min(height, screen.height)
        return NSRect(x: max(screen.minX, min(mouse.x - w / 2, screen.maxX - w)),
                      y: max(screen.minY, min(mouse.y - h / 2, screen.maxY - h)), width: w, height: h)
    }
}

final class MarkerView: NSView {
    var style = HighlightStyle() { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        // Slightly slanted ends and a soft rim resemble a single pen stroke.
        let r = bounds.insetBy(dx: 1, dy: 1)
        let slant = min(5, r.height / 5)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: r.minX + slant, y: r.minY))
        p.line(to: NSPoint(x: r.maxX, y: r.minY + 1))
        p.line(to: NSPoint(x: r.maxX - slant, y: r.maxY))
        p.line(to: NSPoint(x: r.minX, y: r.maxY - 1))
        p.close()
        style.color.withAlphaComponent(style.opacity).setFill()
        p.fill()
        style.color.withAlphaComponent(style.opacity * 0.22).setStroke()
        p.lineWidth = 1.5
        p.stroke()
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        if #available(macOS 14.0, *) { collectionBehavior.insert(.canJoinAllApplications) }
        animationBehavior = .none
        contentView = MarkerView()
    }
}

final class PreviewView: NSView {
    let marker = MarkerView()
    var style = HighlightStyle() { didSet { marker.style = style; needsLayout = true } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        let first = NSTextField(labelWithString: "Reading begins with a single line of focus.")
        first.font = .systemFont(ofSize: 15)
        first.textColor = .labelColor
        first.frame = NSRect(x: 22, y: 55, width: 460, height: 23)
        let second = NSTextField(labelWithString: "让目光停留在正在读的这一行。")
        second.font = .systemFont(ofSize: 15)
        second.frame = NSRect(x: 22, y: 22, width: 460, height: 23)
        addSubview(first)
        addSubview(second)
        addSubview(marker)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let w = style.fullWidth ? bounds.width - 24 : min(style.width, bounds.width - 24)
        marker.frame = NSRect(x: 14, y: 33 - style.height / 2, width: w, height: style.height)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var style = HighlightStyle()
    var enabled = false
    var overlay: OverlayPanel!
    var positionTimer: Timer?
    var statusItem: NSStatusItem!
    var toggleItem: NSMenuItem!
    var window: NSWindow?
    var preview: PreviewView?
    var testButton: NSButton?
    var hotKey: EventHotKeyRef?
    var hotKeyHandler: EventHandlerRef?
    var hotKeyAvailable = false
    let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["width": 420.0, "height": 28.0, "opacity": 0.30,
            "color": 0, "fullWidth": false])
        style.width = CGFloat(min(1400, max(120, defaults.double(forKey: "width"))))
        style.height = CGFloat(min(90, max(14, defaults.double(forKey: "height"))))
        style.opacity = CGFloat(min(0.65, max(0.08, defaults.double(forKey: "opacity"))))
        style.colorIndex = defaults.integer(forKey: "color")
        style.fullWidth = defaults.bool(forKey: "fullWidth")
        overlay = OverlayPanel()
        makeMenu()
        registerHotKey()
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.screensDidSleepNotification, object: nil)
        // BetterMouse launches this app. Launch once = on; reopen the running app = toggle.
        setEnabled(true)
        if CommandLine.arguments.contains("--settings") { showSettings(nil) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        toggle(nil)
        return false
    }

    func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: "荧光阅读")
        statusItem.button?.toolTip = "荧光阅读 · 点击打开菜单"
        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "关闭高亮", action: #selector(toggle(_:)), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出荧光阅读", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    func registerHotKey() {
        var kind = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().toggle(nil)
            return noErr
        }, 1, &kind, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        if result == noErr {
            hotKeyAvailable = RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey | cmdKey),
                EventHotKeyID(signature: 0x484C4954, id: 1), GetApplicationEventTarget(), 0, &hotKey) == noErr
        }
    }

    @objc func toggle(_ sender: Any?) { setEnabled(!enabled) }
    func setEnabled(_ value: Bool) {
        enabled = value
        positionTimer?.invalidate()
        positionTimer = nil
        if value {
            updatePosition()
            overlay.orderFrontRegardless()
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.updatePosition() }
            timer.tolerance = 0.003
            RunLoop.main.add(timer, forMode: .common)
            positionTimer = timer
        } else { overlay.orderOut(nil) }
        toggleItem.state = value ? .on : .off
        toggleItem.title = (value ? "关闭高亮" : "开启高亮") + (hotKeyAvailable ? "    ⌃⌥⌘H" : "")
        statusItem.button?.contentTintColor = value ? .systemOrange : nil
        testButton?.title = value ? "关闭高亮" : "开启高亮"
    }

    func updatePosition() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else {
            overlay.orderOut(nil)
            return
        }
        let frame = style.frame(at: mouse, in: screen.frame)
        if overlay.frame != frame { overlay.setFrame(frame, display: false) }
        if let marker = overlay.contentView as? MarkerView {
            if marker.style.width != style.width || marker.style.height != style.height
                || marker.style.opacity != style.opacity || marker.style.colorIndex != style.colorIndex
                || marker.style.fullWidth != style.fullWidth { marker.style = style }
        }
        if enabled && !overlay.isVisible { overlay.orderFrontRegardless() }
    }
    @objc func displayChanged() { if enabled { updatePosition() } }
    @objc func sleeping() { setEnabled(false) }

    @objc func showSettings(_ sender: Any?) {
        if window == nil { makeSettings() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    func label(_ text: String, size: CGFloat = 13, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size)
        field.textColor = color
        return field
    }
    func row(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = spacing
        stack.alignment = .centerY
        return stack
    }
    func actionButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    func makeSettings() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 574, height: 540),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "荧光阅读"
        w.isReleasedWhenClosed = false
        w.center()
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        w.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: w.contentView!.topAnchor, constant: 24)
        ])
        let title = label("让目光，停在这一行。", size: 25)
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        root.addArrangedSubview(title)
        root.addArrangedSubview(label("打开应用即开启，再次打开即关闭。侧键交给 BetterMouse。", color: .secondaryLabelColor))
        let preview = PreviewView(frame: .zero)
        preview.style = style
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalToConstant: 102).isActive = true
        preview.widthAnchor.constraint(equalToConstant: 518).isActive = true
        root.addArrangedSubview(preview)
        self.preview = preview
        root.addArrangedSubview(sliderRow("长度", value: Double(style.width), min: 120, max: 1400, tag: 1))
        root.addArrangedSubview(sliderRow("粗细", value: Double(style.height), min: 14, max: 90, tag: 2))
        root.addArrangedSubview(sliderRow("透明度", value: Double(style.opacity * 100), min: 8, max: 65, tag: 3))
        let color = NSPopUpButton()
        color.addItems(withTitles: ["荧光黄", "薄荷绿", "天空蓝", "浅玫红"])
        color.selectItem(at: max(0, min(style.colorIndex, 3)))
        color.target = self
        color.action = #selector(colorChanged(_:))
        let fullWidth = NSButton(checkboxWithTitle: "横跨整屏", target: self, action: #selector(fullWidthChanged(_:)))
        fullWidth.state = style.fullWidth ? .on : .off
        root.addArrangedSubview(row([label("颜色"), color, fullWidth], spacing: 20))
        let separator = NSBox()
        separator.boxType = .separator
        separator.widthAnchor.constraint(equalToConstant: 518).isActive = true
        root.addArrangedSubview(separator)
        let test = actionButton(enabled ? "关闭高亮" : "开启高亮", #selector(toggle(_:)))
        testButton = test
        root.addArrangedSubview(row([test, label("不影响选字、点击和滚动。", size: 12, color: .secondaryLabelColor)]))
        let guide = label("在 BetterMouse 中把侧键绑定为打开这个应用。\n也可绑定备用快捷键：⌃ Control + ⌥ Option + ⌘ Command + H。", size: 12, color: .secondaryLabelColor)
        guide.preferredMaxLayoutWidth = 518
        root.addArrangedSubview(guide)
        if !hotKeyAvailable {
            root.addArrangedSubview(label("备用快捷键被其他程序占用；打开应用和菜单栏开关仍可用。", size: 12, color: .systemOrange))
        }
        root.addArrangedSubview(label("关闭此窗口后，程序留在顶部菜单栏。", size: 12, color: .secondaryLabelColor))
        root.layoutSubtreeIfNeeded()
        w.setContentSize(NSSize(width: 574, height: max(540, root.fittingSize.height + 48)))
        window = w
    }

    func sliderRow(_ title: String, value: Double, min: Double, max: Double, tag: Int) -> NSView {
        let name = label(title)
        name.widthAnchor.constraint(equalToConstant: 54).isActive = true
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: #selector(sliderChanged(_:)))
        slider.tag = tag
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 350).isActive = true
        let valueLabel = label(tag == 3 ? "\(Int(value))%" : "\(Int(value)) pt", size: 12, color: .secondaryLabelColor)
        valueLabel.tag = 100 + tag
        valueLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true
        return row([name, slider, valueLabel])
    }
    @objc func sliderChanged(_ sender: NSSlider) {
        let v = sender.doubleValue.rounded()
        switch sender.tag {
        case 1: style.width = CGFloat(v); defaults.set(v, forKey: "width")
        case 2: style.height = CGFloat(v); defaults.set(v, forKey: "height")
        default: style.opacity = CGFloat(v / 100); defaults.set(v / 100, forKey: "opacity")
        }
        if let valueLabel = sender.superview?.viewWithTag(100 + sender.tag) as? NSTextField {
            valueLabel.stringValue = sender.tag == 3 ? "\(Int(v))%" : "\(Int(v)) pt"
        }
        refreshStyle()
    }
    func refreshStyle() { preview?.style = style; (overlay.contentView as? MarkerView)?.style = style; if enabled { updatePosition() } }
    @objc func colorChanged(_ sender: NSPopUpButton) { style.colorIndex = sender.indexOfSelectedItem; defaults.set(style.colorIndex, forKey: "color"); refreshStyle() }
    @objc func fullWidthChanged(_ sender: NSButton) { style.fullWidth = sender.state == .on; defaults.set(style.fullWidth, forKey: "fullWidth"); refreshStyle() }
    @objc func quit(_ sender: Any?) { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        positionTimer?.invalidate()
        overlay.orderOut(nil)
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }
}

func selfTest() {
    let style = HighlightStyle()
    let screen = NSRect(x: -1920, y: -200, width: 1920, height: 1080)
    for point in [NSPoint(x: -1900, y: -180), NSPoint(x: -10, y: 870), NSPoint(x: -900, y: 400)] {
        let frame = style.frame(at: point, in: screen)
        precondition(screen.contains(frame), "Overlay must stay inside its current display")
        precondition(frame.width == 420 && frame.height == 28)
    }
    var full = style
    full.fullWidth = true
    precondition(full.frame(at: .zero, in: screen).width == screen.width)
    let tiny = NSRect(x: 0, y: 0, width: 200, height: 20)
    precondition(style.frame(at: .zero, in: tiny) == tiny)
    print("PASS: display geometry with negative coordinates, edge clamping, full-width mode, small-screen bounds")
}

func makeIcon(at path: String) {
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.97, green: 0.96, blue: 0.91, alpha: 1))
    context.addPath(CGPath(roundedRect: CGRect(x: 40, y: 40, width: 944, height: 944),
        cornerWidth: 206, cornerHeight: 206, transform: nil))
    context.fillPath()
    context.setFillColor(CGColor(red: 0.18, green: 0.22, blue: 0.19, alpha: 0.8))
    for (y, width) in [(650.0, 580.0), (485.0, 540.0), (320.0, 380.0)] {
        context.addPath(CGPath(roundedRect: CGRect(x: 220, y: y, width: width, height: 35),
            cornerWidth: 17, cornerHeight: 17, transform: nil))
        context.fillPath()
    }
    context.setFillColor(CGColor(red: 1, green: 0.83, blue: 0, alpha: 0.72))
    context.move(to: CGPoint(x: 170, y: 442)); context.addLine(to: CGPoint(x: 847, y: 454))
    context.addLine(to: CGPoint(x: 866, y: 557)); context.addLine(to: CGPoint(x: 190, y: 543))
    context.closePath(); context.fillPath()
    let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
}

if CommandLine.arguments.contains("--self-test") {
    selfTest()
} else if let i = CommandLine.arguments.firstIndex(of: "--make-icon"), CommandLine.arguments.count > i + 1 {
    makeIcon(at: CommandLine.arguments[i + 1])
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
