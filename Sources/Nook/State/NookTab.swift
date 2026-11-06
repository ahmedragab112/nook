import Foundation

enum NookTab: String, CaseIterable, Identifiable, Codable {
    case media
    case calendar
    case weather
    case reminders
    case shelf
    case launcher
    case clipboard
    case notes
    case timer
    case mirror
    case color
    case stats
    case agents
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: return "Now Playing"
        case .calendar: return "Calendar"
        case .weather: return "Weather"
        case .reminders: return "Reminders"
        case .shelf: return "Shelf"
        case .launcher: return "Shortcuts"
        case .clipboard: return "Clipboard"
        case .notes: return "Notes"
        case .timer: return "Timer"
        case .mirror: return "Mirror"
        case .color: return "Color"
        case .stats: return "System"
        case .agents: return "Agents"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .media: return "play.circle"
        case .calendar: return "calendar"
        case .weather: return "cloud.sun"
        case .reminders: return "checklist"
        case .shelf: return "tray.and.arrow.down"
        case .launcher: return "square.grid.2x2"
        case .clipboard: return "doc.on.clipboard"
        case .notes: return "note.text"
        case .timer: return "timer"
        case .mirror: return "camera"
        case .color: return "eyedropper"
        case .stats: return "gauge.medium"
        case .agents: return "sparkles"
        case .settings: return "gearshape"
        }
    }

    /// Extra room some tools need.
    var preferredHeight: CGFloat {
        switch self {
        case .shelf, .launcher, .clipboard: return 40
        case .settings, .stats: return 50
        case .agents: return 140
        default: return 0
        }
    }

    var group: String {
        switch self {
        case .media, .calendar, .weather, .timer: return "Live"
        case .reminders, .shelf, .launcher, .clipboard, .notes: return "Capture"
        case .mirror, .color, .stats: return "Utilities"
        case .agents: return "AI"
        case .settings: return "App"
        }
    }
}
