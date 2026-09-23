import AppKit
import GameController
import ServiceManagement

final class RemoteApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var connectionLabel: NSTextField!
    private var permissionLabel: NSTextField!
    private var activityLabel: NSTextField!
    private var pauseButton: NSButton!
    private var permissionButton: NSButton!
    private var loginButton: NSButton!
    private var pauseMenu: NSMenuItem!
    private var controller: GCController?
    private var timer: Timer?
    private var activityToken: NSObjectProtocol?
    private var actions = ActionState()
    private var commandHeld = false
    private var nextRepeat: [RemoteAction: TimeInterval] = [:]
    private var mappings: [String: RemoteAction] = [:]
    private var popups: [NSPopUpButton] = []
    private var pressedInputs: Set<String> = []
    private var enabled = true
    private var trusted = false
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var lastStatusTick: TimeInterval = 0
    private var scrollRemainder = CGPoint.zero
    private var screenRects: [CGRect] = []
    private var lastClick: TimeInterval = 0
    private var lastClickPoint = CGPoint.zero
    private var clickCount: Int64 = 1
    private var inputCount = 0
    private var pointerSpeed: Double { UserDefaults.standard.double(forKey: "pointerSpeed") }
    private let eventSource = CGEventSource(stateID: .privateState)

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["pointerSpeed": 1050.0])
        for binding in bindings {
            if let stored = UserDefaults.standard.string(forKey: "binding.\(binding.input)"),
               let action = RemoteAction(rawValue: stored) {
                mappings[binding.input] = action
            } else {
                mappings[binding.input] = binding.initial
            }
        }
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        buildWindow()
        updateScreens()
        trusted = AXIsProcessTrusted()
        GCController.shouldMonitorBackgroundEvents = true
        NotificationCenter.default.addObserver(self, selector: #selector(controllersChanged), name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllersChanged), name: .GCControllerDidDisconnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateScreens), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(controllersChanged), name: NSWorkspace.didWakeNotification, object: nil)
        controllersChanged()
        activityToken = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Respond to the TV remote while another app is active")
        timer = Timer(timeInterval: 1.0 / 90.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        refreshStatus()
        showWindow()
        if !trusted { requestPermission() }
    }

    private func buildMenu() {
        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: "Quit Couch Remote", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = submenu
        appMenu.addItem(appItem)
        NSApp.mainMenu = appMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: "Couch Remote")
        let menu = NSMenu()
        menu.addItem(withTitle: "Couch Remote — Controls…", action: #selector(showWindow), keyEquivalent: "").target = self
        pauseMenu = menu.addItem(withTitle: "Pause Remote", action: #selector(toggleEnabled), keyEquivalent: "")
        pauseMenu.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Couch Remote", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        return field
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 820), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Couch Remote"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
        ])
        stack.addArrangedSubview(label("Your controller. Your couch. Your Mac.", size: 23, weight: .semibold))
        connectionLabel = label("Looking for your controller…", weight: .medium)
        stack.addArrangedSubview(connectionLabel)
        permissionLabel = label("")
        stack.addArrangedSubview(permissionLabel)
        permissionButton = NSButton(title: "Allow Mouse & Keyboard Control…", target: self, action: #selector(requestPermission))
        stack.addArrangedSubview(permissionButton)
        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)
        stack.addArrangedSubview(label("Left stick: move pointer     ·     Right stick: scroll", size: 14, weight: .semibold))
        stack.addArrangedSubview(label("Hold LT for precision. Hold A while moving to drag."))
        stack.addArrangedSubview(label("Hold left stick click, then click right stick to switch apps."))
        let speedRow = NSStackView()
        speedRow.orientation = .horizontal
        speedRow.spacing = 12
        speedRow.addArrangedSubview(label("Pointer speed"))
        let slider = NSSlider(value: pointerSpeed, minValue: 300, maxValue: 2400, target: self, action: #selector(speedChanged(_:)))
        slider.widthAnchor.constraint(equalToConstant: 260).isActive = true
        speedRow.addArrangedSubview(slider)
        stack.addArrangedSubview(speedRow)
        var rows: [[NSView]] = []
        for (index, binding) in bindings.enumerated() {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: RemoteAction.allCases.map(\.title))
            popup.selectItem(withTitle: mappings[binding.input]!.title)
            popup.tag = index
            popup.target = self
            popup.action = #selector(bindingChanged(_:))
            popups.append(popup)
            rows.append([label(binding.title), popup])
        }
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 24
        grid.rowSpacing = 5
        grid.column(at: 0).width = 225
        grid.column(at: 1).width = 255
        grid.yPlacement = .center
        stack.addArrangedSubview(grid)
        activityLabel = label("Move a stick or press a button to test the connection.")
        activityLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(activityLabel)
        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 12
        pauseButton = NSButton(title: "Pause Remote", target: self, action: #selector(toggleEnabled))
        controls.addArrangedSubview(pauseButton)
        controls.addArrangedSubview(NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults)))
        controls.addArrangedSubview(NSButton(title: "Done", target: self, action: #selector(hideWindow)))
        stack.addArrangedSubview(controls)
        loginButton = NSButton(checkboxWithTitle: "Open automatically when I log in", target: self, action: #selector(loginChanged))
        loginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
        stack.addArrangedSubview(loginButton)
        let footnote = label("Closing this window keeps the remote running in the menu bar.")
        footnote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(footnote)
        stack.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 590, height: stack.fittingSize.height + 46))
        window.center()
    }

    @objc private func controllersChanged() {
        let connected = GCController.controllers().filter { $0.extendedGamepad != nil }
        if let controller, connected.contains(where: { $0 === controller }) { return }
        releaseAll()
        controller = connected.first(where: { $0.vendorName?.localizedCaseInsensitiveContains("8BitDo") == true })
        controller?.handlerQueue = .main
        pressedInputs.removeAll()
        refreshStatus()
    }

    @objc private func sleeping() {
        releaseAll()
        pressedInputs.removeAll()
    }

    @objc private func updateScreens() {
        screenRects = NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(CGDirectDisplayID(id.uint32Value))
        }
    }

    private func inputButtons(_ pad: GCExtendedGamepad) -> [(String, GCControllerButtonInput)] {
        var result: [(String, GCControllerButtonInput)] = [
            ("a", pad.buttonA), ("b", pad.buttonB), ("x", pad.buttonX), ("y", pad.buttonY),
            ("lb", pad.leftShoulder), ("rb", pad.rightShoulder), ("lt", pad.leftTrigger), ("rt", pad.rightTrigger),
            ("up", pad.dpad.up), ("down", pad.dpad.down), ("left", pad.dpad.left), ("right", pad.dpad.right),
            ("menu", pad.buttonMenu),
        ]
        if let options = pad.buttonOptions { result.append(("options", options)) }
        if let leftThumbstickButton = pad.leftThumbstickButton { result.append(("leftStick", leftThumbstickButton)) }
        if let rightThumbstickButton = pad.rightThumbstickButton { result.append(("rightStick", rightThumbstickButton)) }
        return result
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastTick, 0.04)
        lastTick = now
        if now - lastStatusTick > 1 {
            let currentTrust = AXIsProcessTrusted()
            if trusted != currentTrust {
                releaseAll()
                trusted = currentTrust
            }
            refreshStatus()
            lastStatusTick = now
        }
        guard let pad = controller?.extendedGamepad else { return }
        let current = Set(inputButtons(pad).filter { $0.1.value > 0.45 }.map { $0.0 })
        let newPresses = current.subtracting(pressedInputs)
        pressedInputs = current
        if let input = newPresses.sorted().first, let binding = bindings.first(where: { $0.input == input }) {
            inputCount += 1
            activityLabel.stringValue = "Received: \(binding.title) → \(mappings[input]!.title)"
        }
        if newPresses.contains(where: { mappings[$0] == .pause }) { toggleEnabled() }
        guard enabled && trusted else { return }
        let active = Set(current.compactMap { mappings[$0] }).subtracting([.pause, .none])
        let changes = actions.update(active)
        for action in changes.released where action != .command {
            send(action, down: false)
            nextRepeat.removeValue(forKey: action)
        }
        if changes.released.contains(.command) { send(.command, down: false) }
        if changes.pressed.contains(.command) { send(.command, down: true) }
        for action in changes.pressed where action != .command {
            send(action, down: true)
            if action.repeats { nextRepeat[action] = now + 0.4 }
        }
        for action in active where action.repeats {
            if let next = nextRepeat[action], now >= next {
                send(action, down: true, repeating: true)
                nextRepeat[action] = now + 0.10
            }
        }
        let velocity = stickVelocity(x: Double(pad.leftThumbstick.xAxis.value), y: Double(pad.leftThumbstick.yAxis.value))
        if velocity != .zero {
            let multiplier = active.contains(.precision) ? 0.22 : 1.0
            movePointer(dx: velocity.x * pointerSpeed * multiplier * dt, dy: -velocity.y * pointerSpeed * multiplier * dt)
            if window.isVisible && newPresses.isEmpty { activityLabel.stringValue = "Receiving left stick · pointer moving" }
        }
        let scroll = stickVelocity(x: Double(pad.rightThumbstick.xAxis.value), y: Double(pad.rightThumbstick.yAxis.value), deadZone: 0.2)
        if scroll != .zero {
            scrollRemainder.x += -scroll.x * 950 * dt
            scrollRemainder.y += scroll.y * 950 * dt
            let horizontal = Int32(scrollRemainder.x)
            let vertical = Int32(scrollRemainder.y)
            scrollRemainder.x -= Double(horizontal)
            scrollRemainder.y -= Double(vertical)
            if horizontal != 0 || vertical != 0 {
                CGEvent(scrollWheelEvent2Source: eventSource, units: .pixel, wheelCount: 2, wheel1: vertical, wheel2: horizontal, wheel3: 0)?.post(tap: .cghidEventTap)
            }
        } else { scrollRemainder = .zero }
    }

    private func movePointer(dx: Double, dy: Double) {
        guard let position = CGEvent(source: nil)?.location else { return }
        let destination = nearestVisiblePoint(CGPoint(x: position.x + dx, y: position.y + dy), screens: screenRects)
        let type: CGEventType
        let button: CGMouseButton
        if actions.held.contains(.leftClick) { type = .leftMouseDragged; button = .left }
        else if actions.held.contains(.rightClick) { type = .rightMouseDragged; button = .right }
        else { type = .mouseMoved; button = .left }
        let event = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: destination, mouseButton: button)
        event?.setIntegerValueField(.mouseEventDeltaX, value: Int64(destination.x - position.x))
        event?.setIntegerValueField(.mouseEventDeltaY, value: Int64(destination.y - position.y))
        event?.post(tap: .cghidEventTap)
    }

    private func send(_ action: RemoteAction, down: Bool, repeating: Bool = false) {
        if let key = action.keyCode {
            if action == .command { commandHeld = down }
            let event = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: down)
            event?.flags = keyboardFlags(for: action, down: down, commandHeld: commandHeld)
            event?.setIntegerValueField(.keyboardEventAutorepeat, value: repeating ? 1 : 0)
            event?.post(tap: .cghidEventTap)
        } else if action == .leftClick || action == .rightClick {
            guard let point = CGEvent(source: nil)?.location else { return }
            let isLeft = action == .leftClick
            let type: CGEventType = isLeft ? (down ? .leftMouseDown : .leftMouseUp) : (down ? .rightMouseDown : .rightMouseUp)
            let event = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: isLeft ? .left : .right)
            if isLeft && down {
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastClick < NSEvent.doubleClickInterval && hypot(point.x - lastClickPoint.x, point.y - lastClickPoint.y) < 6 {
                    clickCount += 1
                } else { clickCount = 1 }
                lastClick = now
                lastClickPoint = point
            }
            event?.setIntegerValueField(.mouseEventClickState, value: isLeft ? clickCount : 1)
            event?.post(tap: .cghidEventTap)
        } else if down && (action == .volumeUp || action == .volumeDown) {
            let key = action == .volumeUp ? 0 : 1
            for isDown in [true, false] {
                let flags: NSEvent.ModifierFlags = isDown ? .init(rawValue: 0xA00) : .init(rawValue: 0xB00)
                let data = (key << 16) | ((isDown ? 0xA : 0xB) << 8)
                NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
            }
        }
    }

    private func releaseAll() {
        let changes = actions.update([])
        for action in changes.released where action != .command { send(action, down: false) }
        if changes.released.contains(.command) { send(.command, down: false) }
        nextRepeat.removeAll()
        scrollRemainder = .zero
    }

    private func refreshStatus() {
        guard connectionLabel != nil else { return }
        if let name = controller?.vendorName {
            connectionLabel.stringValue = "Connected: \(name) · \(enabled ? "Remote on" : "Paused")"
            connectionLabel.textColor = .labelColor
        } else {
            connectionLabel.stringValue = "Turn on your 8BitDo controller — it will reconnect automatically."
            connectionLabel.textColor = .secondaryLabelColor
        }
        permissionLabel.stringValue = trusted ? "Mouse & keyboard control is allowed. Ready to use." : "One-time setup: enable Couch Remote in Accessibility."
        permissionLabel.textColor = trusted ? .secondaryLabelColor : .systemOrange
        permissionButton.isHidden = trusted
        pauseButton.title = enabled ? "Pause Remote" : "Resume Remote"
        pauseMenu.title = pauseButton.title
        statusItem.button?.appearsDisabled = !enabled
        statusItem.button?.toolTip = connectionLabel.stringValue
        // Small local status snapshot for troubleshooting without collecting key contents.
        let status: [String: Any] = ["connected": controller != nil, "accessibility": trusted, "enabled": enabled, "buttonPresses": inputCount, "lastInput": activityLabel.stringValue]
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("couch-remote-status.json")
            try? data.write(to: url, options: .atomic)
        }
    }

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func hideWindow() { window.orderOut(nil) }

    @objc private func toggleEnabled() {
        releaseAll()
        enabled.toggle()
        refreshStatus()
    }

    @objc private func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshStatus()
    }

    @objc private func speedChanged(_ slider: NSSlider) { UserDefaults.standard.set(slider.doubleValue, forKey: "pointerSpeed") }

    @objc private func bindingChanged(_ popup: NSPopUpButton) {
        releaseAll()
        let binding = bindings[popup.tag]
        let action = RemoteAction.allCases[popup.indexOfSelectedItem]
        mappings[binding.input] = action
        UserDefaults.standard.set(action.rawValue, forKey: "binding.\(binding.input)")
    }

    @objc private func restoreDefaults() {
        releaseAll()
        for (index, binding) in bindings.enumerated() {
            mappings[binding.input] = binding.initial
            UserDefaults.standard.removeObject(forKey: "binding.\(binding.input)")
            popups[index].selectItem(withTitle: binding.initial.title)
        }
    }

    @objc private func loginChanged() {
        do {
            if loginButton.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            loginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
            let alert = NSAlert()
            alert.messageText = "Couldn’t update automatic launch"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        releaseAll()
        timer?.invalidate()
        if let activityToken { ProcessInfo.processInfo.endActivity(activityToken) }
    }
}

func makeIcon(path: String) {
    let image = NSImage(size: NSSize(width: 512, height: 512))
    image.lockFocus()
    NSColor(calibratedRed: 0.13, green: 0.19, blue: 0.33, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 12, y: 12, width: 488, height: 488), xRadius: 110, yRadius: 110).fill()
    if let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(paletteColors: [.white])
        symbol.withSymbolConfiguration(config)?.draw(in: NSRect(x: 78, y: 116, width: 356, height: 280))
    }
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not generate icon") }
    // ICNS permits a PNG payload for the 512-point representation.
    func uint32(_ value: Int) -> Data {
        var number = UInt32(value).bigEndian
        return Data(bytes: &number, count: 4)
    }
    var data = Data("icns".utf8)
    data.append(uint32(png.count + 16))
    data.append(Data("ic09".utf8))
    data.append(uint32(png.count + 8))
    data.append(png)
    try! data.write(to: URL(fileURLWithPath: path))
}

if CommandLine.arguments.contains("--self-test") {
    runSelfTests()
} else if let index = CommandLine.arguments.firstIndex(of: "--make-icon"), CommandLine.arguments.count > index + 1 {
    _ = NSApplication.shared
    makeIcon(path: CommandLine.arguments[index + 1])
} else {
    let app = NSApplication.shared
    let delegate = RemoteApp()
    app.delegate = delegate
    app.run()
}
