import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController!
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings.shared
        controller = NotchController(settings: settings)
        controller.start()

        NowPlayingService.shared.start()
        CalendarService.shared.start()
        WeatherService.shared.start()
        RemindersService.shared.start()
        BluetoothService.shared.start()
        ClipboardStore.shared.start()
        StatsService.shared.start()
        SystemDialService.shared.start()
        HotkeyCenter.shared.reload()

        setupStatusItem()
        observeWorkspace()

        NotificationCenter.default.addObserver(self, selector: #selector(handleHotkey),
                                               name: .nookHotkeyToggled, object: nil)

        // Developer hooks: `--snapshot=file.png` renders the media panel,
        // `--render=dir` renders every enabled panel for visual checks.
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--render=") }) {
            let dir = String(arg.dropFirst("--render=".count))
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            renderPanels(into: dir, tabs: controller.state.visibleTabs)
        } else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--snapshot=") }) {
            let path = String(arg.dropFirst("--snapshot=".count))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                self.controller.open(tab: .media, pin: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    self.controller.snapshotPNG(to: path)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
                }
            }
        } else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--snapshot-mini=") }) {
            // Captures the collapsed music strip on a transparent background.
            let path = String(arg.dropFirst("--snapshot-mini=".count))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                guard let self else { return }
                self.controller.snapshotPNG(to: path)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
            }
        }

        settings.$widthPreset
            .combineLatest(settings.$notchWidthOffset, settings.$notchHeightOffset, settings.$shellOpacity)
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.controller.rebuildForSettings() }
            .store(in: &cancellables)
    }

    private func renderPanels(into dir: String, tabs: [NookTab]) {
        var remaining = tabs
        func next() {
            guard let tab = remaining.first else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
                return
            }
            remaining.removeFirst()
            controller.open(tab: tab, pin: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self else { return }
                let path = (dir as NSString).appendingPathComponent("\(tab.rawValue).png")
                self.controller.snapshotPNG(to: path)
                next()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { next() }
    }

    @objc private func handleHotkey() {
        if !controller.state.expanded { controller.activate() }
        controller.toggle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AgentService.shared.shutdown()
            NowPlayingService.shared.shutdown()
        }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(environmentChanged),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(environmentChanged),
                           name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func environmentChanged() {
        controller.rebuildForSettings()
    }

    // MARK: - menu bar item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.statusImage()
        item.button?.toolTip = "Nook — notch productivity hub"

        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Nook", action: #selector(handleHotkey), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        let panels = NSMenu(title: "Open panel")
        for tab in NotchController.shared.state.visibleTabs {
            let entry = NSMenuItem(title: tab.title, action: #selector(openPanel(_:)), keyEquivalent: "")
            entry.representedObject = tab.rawValue
            entry.target = self
            panels.addItem(entry)
        }
        let panelsItem = NSMenuItem(title: "Open panel", action: nil, keyEquivalent: "")
        panelsItem.submenu = panels
        menu.addItem(panelsItem)

        let playback = NSMenuItem(title: "Play / pause", action: #selector(togglePlayback), keyEquivalent: "")
        playback.target = self
        menu.addItem(playback)

        menu.addItem(NSMenuItem.separator())
        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = AppSettings.shared.launchAtLogin ? .on : .off
        menu.addItem(login)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Nook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        statusItem = item
    }

    private static func statusImage() -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(x: 3, y: 3, width: 14, height: 9)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + 3))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - 3, y: rect.minY + 3), radius: 3,
                       startAngle: 0, endAngle: -90, clockwise: true)
        path.line(to: NSPoint(x: rect.minX + 3, y: rect.minY))
        path.appendArc(withCenter: NSPoint(x: rect.minX + 3, y: rect.minY + 3), radius: 3,
                       startAngle: -90, endAngle: -180, clockwise: true)
        path.close()
        NSColor.black.setFill()
        path.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    @objc private func openPanel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tab = NookTab(rawValue: raw) else { return }
        controller.activate()
        controller.open(tab: tab, pin: true)
    }

    @objc private func togglePlayback() {
        NowPlayingService.shared.togglePlayback()
    }

    @objc private func openSettings() {
        controller.activate()
        controller.open(tab: .settings, pin: true)
    }

    @objc private func toggleLogin() {
        AppSettings.shared.launchAtLogin.toggle()
        statusItem?.menu?.update()
    }
}
