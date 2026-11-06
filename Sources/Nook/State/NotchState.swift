import AppKit
import Combine
import Foundation

private extension NSScreen {
    var isBuiltinDisplay: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
}

final class NotchState: ObservableObject {
    enum Phase: Equatable {
        case collapsed
        case expanded
    }

    @Published var phase: Phase = .collapsed
    @Published var tab: NookTab
    @Published var visibleTab: NookTab
    @Published var pinned: Bool = false
    @Published var isHovering: Bool = false
    @Published var hud: HUDMessage?
    @Published var liveActivity: LiveActivity?
    /// Full media card (hovered/focused). While playing but unfocused the
    /// notch shows the small now-playing strip instead.
    @Published var showsMediaCard: Bool = false
    @Published var isHidden: Bool = false
    @Published var toast: String?

    let settings: AppSettings

    struct LiveActivity: Equatable {
        enum Kind: String { case media, timer, calendar, agent, battery, bluetooth }
        var kind: Kind
        var symbol: String
        var text: String
        var detail: String?
        var progress: Double?
    }

    init(settings: AppSettings) {
        self.settings = settings
        let saved = NookTab(rawValue: settings.lastTab)
        let remembered = settings.rememberLastTab ? saved : nil
        let first = remembered.flatMap { settings.enabledTabs.contains($0) ? $0 : nil }
            ?? settings.enabledTabs.first
            ?? .media
        self.tab = first
        self.visibleTab = first
    }

    var expanded: Bool { phase == .expanded }

    var visibleTabs: [NookTab] { settings.enabledTabs }
}
