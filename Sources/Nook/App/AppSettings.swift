import AppKit
import Combine
import ServiceManagement

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard
    private var ready = false

    // MARK: behaviour
    @Published var hoverToOpen: Bool { didSet { save(hoverToOpen, "hoverToOpen") } }
    @Published var autoCollapse: Bool { didSet { save(autoCollapse, "autoCollapse") } }
    @Published var collapseDelay: Double { didSet { save(collapseDelay, "collapseDelay") } }
    @Published var hideInFullscreen: Bool { didSet { save(hideInFullscreen, "hideInFullscreen") } }
    @Published var followFrontmostScreen: Bool { didSet { save(followFrontmostScreen, "followFrontmostScreen") } }
    @Published var swipeToOpen: Bool { didSet { save(swipeToOpen, "swipeToOpen") } }
    @Published var scrollToOpen: Bool { didSet { save(scrollToOpen, "scrollToOpen") } }
    @Published var clickToOpen: Bool { didSet { save(clickToOpen, "clickToOpen") } }
    @Published var rememberLastTab: Bool { didSet { save(rememberLastTab, "rememberLastTab") } }
    @Published var lastTab: String { didSet { save(lastTab, "lastTab") } }
    @Published var hotkeyEnabled: Bool { didSet { save(hotkeyEnabled, "hotkeyEnabled"); HotkeyCenter.shared.reload() } }
    @Published var hotkeyKeyCode: UInt32 { didSet { save(hotkeyKeyCode, "hotkeyKeyCode"); HotkeyCenter.shared.reload() } }
    @Published var hotkeyModifiers: UInt32 { didSet { save(hotkeyModifiers, "hotkeyModifiers"); HotkeyCenter.shared.reload() } }

    // MARK: geometry
    @Published var widthPreset: WidthPreset { didSet { save(widthPreset.rawValue, "widthPreset"); objectWillChange.send() } }
    @Published var notchWidthOffset: CGFloat { didSet { save(notchWidthOffset, "notchWidthOffset") } }
    @Published var notchHeightOffset: CGFloat { didSet { save(notchHeightOffset, "notchHeightOffset") } }

    // MARK: look
    @Published var shellOpacity: Double { didSet { save(shellOpacity, "shellOpacity") } }
    @Published var accentHex: String { didSet { save(accentHex, "accentHex") } }
    @Published var compactContent: CompactContent { didSet { save(compactContent.rawValue, "compactContent") } }
    @Published var enabledTabs: [NookTab] { didSet { save(enabledTabs.map { $0.rawValue }, "enabledTabs") } }

    // MARK: tools
    @Published var clipboardEnabled: Bool { didSet { save(clipboardEnabled, "clipboardEnabled") } }
    @Published var clipboardLimit: Int { didSet { save(clipboardLimit, "clipboardLimit") } }
    @Published var pasteOnSelect: Bool { didSet { save(pasteOnSelect, "pasteOnSelect") } }
    @Published var shelfAutoClean: Bool { didSet { save(shelfAutoClean, "shelfAutoClean") } }
    @Published var mediaVolumeControl: Bool { didSet { save(mediaVolumeControl, "mediaVolumeControl") } }
    @Published var showSystemHUD: Bool { didSet { save(showSystemHUD, "showSystemHUD") } }
    @Published var showChargingHUD: Bool { didSet { save(showChargingHUD, "showChargingHUD") } }
    @Published var showBluetoothActivity: Bool { didSet { save(showBluetoothActivity, "showBluetoothActivity") } }
    @Published var launchAtLogin: Bool { didSet { saveLoginItem() } }

    // MARK: weather
    @Published var weatherCity: String { didSet { save(weatherCity, "weatherCity") } }

    // MARK: agents
    @Published var agentKind: String { didSet { save(agentKind, "agentKind") } }
    @Published var agentWorkingDirectory: String { didSet { save(agentWorkingDirectory, "agentWorkingDirectory") } }
    @Published var qoderPermissionMode: String { didSet { save(qoderPermissionMode, "qoderPermissionMode") } }
    @Published var qoderModel: String { didSet { save(qoderModel, "qoderModel") } }
    @Published var opencodeBaseURL: String { didSet { save(opencodeBaseURL, "opencodeBaseURL") } }
    @Published var opencodeModel: String { didSet { save(opencodeModel, "opencodeModel") } }
    @Published var agentAutoStart: Bool { didSet { save(agentAutoStart, "agentAutoStart") } }

    enum WidthPreset: Int, CaseIterable, Identifiable {
        case compact = 460, medium = 580, large = 700, extraLarge = 820
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .compact: return "Compact"
            case .medium: return "Medium"
            case .large: return "Large"
            case .extraLarge: return "Extra large"
            }
        }
        var height: CGFloat {
            switch self {
            case .compact: return 220
            case .medium: return 250
            case .large: return 290
            case .extraLarge: return 320
            }
        }
    }

    /// Tabs shown out of the box. The rest stay available in Settings.
    static let defaultTabs: [NookTab] = [.media, .calendar, .weather, .reminders,
                                         .timer, .mirror, .notes, .agents, .settings]

    enum CompactContent: String, CaseIterable, Identifiable {
        case auto, none, media, timer, calendar
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "Automatic"
            case .none: return "Nothing"
            case .media: return "Now playing"
            case .timer: return "Timer"
            case .calendar: return "Next event"
            }
        }
    }

    var expandedSize: CGSize {
        CGSize(width: CGFloat(widthPreset.rawValue), height: widthPreset.height)
    }

    private func save(_ value: Any?, _ key: String) {
        guard ready else { return }
        if let v = value { d.set(v, forKey: key) } else { d.removeObject(forKey: key) }
    }

    private func saveLoginItem() {
        guard ready else { return }
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Nook: login item failed - \(error.localizedDescription)")
            }
        }
    }

    private init() {
        d.register(defaults: [
            "hoverToOpen": true,
            "autoCollapse": true,
            "collapseDelay": 0.4,
            "hideInFullscreen": true,
            "followFrontmostScreen": true,
            "swipeToOpen": true,
            "scrollToOpen": true,
            "clickToOpen": true,
            "rememberLastTab": true,
            "lastTab": "media",
            "hotkeyEnabled": true,
            "hotkeyKeyCode": 45, // N
            "hotkeyModifiers": (1 << 8) | (1 << 11), // control | option
            "widthPreset": WidthPreset.medium.rawValue,
            "notchWidthOffset": 0.0,
            "notchHeightOffset": 0.0,
            "shellOpacity": 1.0,
            "accentHex": "#FF7A1A",
            "compactContent": CompactContent.auto.rawValue,
            "clipboardEnabled": true,
            "clipboardLimit": 20,
            "pasteOnSelect": false,
            "shelfAutoClean": false,
            "mediaVolumeControl": true,
            "showSystemHUD": true,
            "showChargingHUD": true,
            "showBluetoothActivity": true,
            "weatherCity": "Cairo",
            "launchAtLogin": false,
            "agentKind": "qoder",
            "agentWorkingDirectory": NSHomeDirectory(),
            "qoderPermissionMode": "default",
            "qoderModel": "",
            "opencodeBaseURL": "http://127.0.0.1:4096",
            "opencodeModel": "",
            "agentAutoStart": true
        ])

        hoverToOpen = d.bool(forKey: "hoverToOpen")
        autoCollapse = d.bool(forKey: "autoCollapse")
        collapseDelay = d.double(forKey: "collapseDelay")
        hideInFullscreen = d.bool(forKey: "hideInFullscreen")
        followFrontmostScreen = d.bool(forKey: "followFrontmostScreen")
        swipeToOpen = d.bool(forKey: "swipeToOpen")
        scrollToOpen = d.bool(forKey: "scrollToOpen")
        clickToOpen = d.bool(forKey: "clickToOpen")
        rememberLastTab = d.bool(forKey: "rememberLastTab")
        lastTab = d.string(forKey: "lastTab") ?? "media"
        hotkeyEnabled = d.bool(forKey: "hotkeyEnabled")
        hotkeyKeyCode = UInt32(d.integer(forKey: "hotkeyKeyCode"))
        hotkeyModifiers = UInt32(d.integer(forKey: "hotkeyModifiers"))
        widthPreset = WidthPreset(rawValue: d.integer(forKey: "widthPreset")) ?? .medium
        notchWidthOffset = CGFloat(d.double(forKey: "notchWidthOffset"))
        notchHeightOffset = CGFloat(d.double(forKey: "notchHeightOffset"))
        shellOpacity = d.double(forKey: "shellOpacity")
        accentHex = d.string(forKey: "accentHex") ?? "#FF7A1A"
        compactContent = CompactContent(rawValue: d.string(forKey: "compactContent") ?? "") ?? .auto
        if let raw = d.array(forKey: "enabledTabs") as? [String] {
            var tabs = raw.compactMap { NookTab(rawValue: $0) }
            if !d.bool(forKey: "agentsTabMigrated") {
                if !tabs.contains(.agents) { tabs.append(.agents) }
                d.set(true, forKey: "agentsTabMigrated")
            }
            if !d.bool(forKey: "phase1TabsMigrated") {
                for (offset, tab) in [NookTab.weather, .reminders, .mirror].enumerated() where !tabs.contains(tab) {
                    tabs.insert(tab, at: min(tabs.count, 2 + offset))
                }
                d.set(true, forKey: "phase1TabsMigrated")
            }
            enabledTabs = tabs.isEmpty ? Self.defaultTabs : tabs
        } else {
            enabledTabs = Self.defaultTabs
        }
        clipboardEnabled = d.bool(forKey: "clipboardEnabled")
        clipboardLimit = max(5, d.integer(forKey: "clipboardLimit"))
        pasteOnSelect = d.bool(forKey: "pasteOnSelect")
        shelfAutoClean = d.bool(forKey: "shelfAutoClean")
        mediaVolumeControl = d.bool(forKey: "mediaVolumeControl")
        showSystemHUD = d.bool(forKey: "showSystemHUD")
        showChargingHUD = d.bool(forKey: "showChargingHUD")
        showBluetoothActivity = d.bool(forKey: "showBluetoothActivity")
        weatherCity = d.string(forKey: "weatherCity") ?? "Cairo"
        agentKind = d.string(forKey: "agentKind") ?? "qoder"
        agentWorkingDirectory = d.string(forKey: "agentWorkingDirectory") ?? NSHomeDirectory()
        qoderPermissionMode = d.string(forKey: "qoderPermissionMode") ?? "default"
        qoderModel = d.string(forKey: "qoderModel") ?? ""
        opencodeBaseURL = d.string(forKey: "opencodeBaseURL") ?? "http://127.0.0.1:4096"
        opencodeModel = d.string(forKey: "opencodeModel") ?? ""
        agentAutoStart = d.bool(forKey: "agentAutoStart")
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLogin = false
        }
        ready = true
    }

    func toggleTab(_ tab: NookTab) {
        if let idx = enabledTabs.firstIndex(of: tab) {
            if idx > 0 { enabledTabs.remove(at: idx) }
        } else {
            enabledTabs.append(tab)
        }
        if enabledTabs.isEmpty { enabledTabs = [.media] }
    }

    func moveTab(_ tab: NookTab, by delta: Int) {
        guard let idx = enabledTabs.firstIndex(of: tab) else { return }
        let target = idx + delta
        guard target >= 0, target < enabledTabs.count else { return }
        enabledTabs.swapAt(idx, target)
    }
}
