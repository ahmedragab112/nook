import AppKit
import EventKit
import Foundation
import Combine

struct CalEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String
    let calendarName: String
    let colorHex: String
    let joinURL: URL?
    var isRunning: Bool { Date() >= start && Date() < end }
    var isPast: Bool { end < Date() }
}

final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published var events: [CalEvent] = []
    @Published var status: EKAuthorizationStatus = .notDetermined
    @Published var message: String?

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    private init() {}

    func start() {
        status = EKEventStore.authorizationStatus(for: .event)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    func requestAccess() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard status == .notDetermined else { refresh(); return }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.status = EKEventStore.authorizationStatus(for: .event)
                    if granted { self?.refresh() }
                    else { self?.message = "Calendar access denied" }
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.status = EKEventStore.authorizationStatus(for: .event)
                    if granted { self?.refresh() } else { self?.message = "Calendar access denied" }
                }
            }
        }
    }

    var hasAccess: Bool {
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    func refresh() {
        guard hasAccess else {
            if RunMode.isRendering { events = Self.demoEvents }
            return
        }
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let raw = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        let mapped: [CalEvent] = raw.map { event in
            let join = Self.joinURL(for: event)
            let rgb = event.calendar.color ?? NSColor.systemGray
            return CalEvent(id: event.eventIdentifier ?? UUID().uuidString,
                            title: event.title.isEmpty ? "Untitled" : event.title,
                            start: event.startDate,
                            end: event.endDate,
                            allDay: event.isAllDay,
                            location: event.location ?? "",
                            calendarName: event.calendar.title,
                            colorHex: Util.hexString(rgb),
                            joinURL: join)
        }
        events = mapped
        publishActivity()
    }

    /// Events happening today, upcoming first.
    var todays: [CalEvent] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return events.filter { $0.start < endOfDay && $0.end >= startOfDay }
    }

    var nextEvent: CalEvent? {
        events.first { $0.end > Date() }
    }

    var nextEventMinutes: Int? {
        guard let next = nextEvent else { return nil }
        return Int((next.start.timeIntervalSinceNow / 60).rounded())
    }

    private static func joinURL(for event: EKEvent) -> URL? {
        let candidates = [event.url?.absoluteString ?? "", event.notes ?? "", event.location ?? ""]
            .joined(separator: " ")
        let pattern = "https?://[^\\s|\"']+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(candidates.startIndex..., in: candidates)
        guard let match = regex.firstMatch(in: candidates, range: range) else { return nil }
        guard let swift = Range(match.range, in: candidates) else { return nil }
        let url = String(candidates[swift])
        let tokens = ["zoom", "teams", "meet", "webex", "hangout", "gather", "jitsi", "clickmeeting", "gotomeeting"]
        if tokens.contains(where: { url.lowercased().contains($0) }) { return URL(string: url) }
        return nil
    }

    private func publishActivity() {
        guard let next = nextEvent else { NotchController.shared.clearActivity(.calendar); return }
        let minutes = Int((next.start.timeIntervalSinceNow / 60).rounded())
        if minutes > 30 || next.allDay {
            NotchController.shared.clearActivity(.calendar)
            return
        }
        let text = next.title
        let detail = minutes <= 0 ? "now" : "\(minutes)m"
        NotchController.shared.setActivity(.init(kind: .calendar, symbol: "calendar",
                                                 text: text, detail: detail, progress: nil))
    }

    /// Sample schedule for offscreen renders so docs never expose real calendars.
    private static var demoEvents: [CalEvent] {
        let now = Date()
        func offset(_ minutes: Int) -> Date { now.addingTimeInterval(TimeInterval(minutes * 60)) }
        return [
            CalEvent(id: "demo-running", title: "Design review — notch motion",
                     start: offset(-25), end: offset(20), allDay: false,
                     location: "Zoom", calendarName: "Work", colorHex: "#6C5CE7",
                     joinURL: URL(string: "https://zoom.us/j/123456789")),
            CalEvent(id: "demo-lunch", title: "Lunch with Sara",
                     start: offset(95), end: offset(155), allDay: false,
                     location: "Sequoia", calendarName: "Personal", colorHex: "#00B894",
                     joinURL: nil),
            CalEvent(id: "demo-tomorrow", title: "Ship Nook 1.0 build",
                     start: offset(60 * 21), end: offset(60 * 23), allDay: false,
                     location: "", calendarName: "Work", colorHex: "#FDCB6E",
                     joinURL: nil),
            CalEvent(id: "demo-dentist", title: "Dentist appointment",
                     start: offset(60 * 43), end: offset(60 * 44), allDay: false,
                     location: "Smile Clinic", calendarName: "Personal", colorHex: "#E17055",
                     joinURL: nil)
        ]
    }
}

extension CalEvent: Equatable {
    static func == (lhs: CalEvent, rhs: CalEvent) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.start == rhs.start && lhs.end == rhs.end
    }
}
