import AppKit
import Combine
import EventKit
import Foundation

struct ReminderItem: Identifiable, Equatable {
    let id: String
    var title: String
    var due: Date?
    var hasTime: Bool
    var isCompleted: Bool
    var listName: String
    var colorHex: String
    var completedAt: Date?

    var isOverdue: Bool {
        guard let due, !isCompleted else { return false }
        return due < Date()
    }
}

/// Reminders from EventKit, read and ticked off locally.
final class RemindersService: ObservableObject {
    static let shared = RemindersService()

    @Published private(set) var items: [ReminderItem] = []
    @Published private(set) var status: EKAuthorizationStatus = .notDetermined
    @Published private(set) var isLoading = false
    @Published var message: String?

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var loadToken = 0

    private init() {}

    func start() {
        status = EKEventStore.authorizationStatus(for: .reminder)
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged,
                                                          object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    var hasAccess: Bool {
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    func requestAccess() {
        status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .notDetermined else { refresh(); return }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.status = EKEventStore.authorizationStatus(for: .reminder)
                    if granted { self?.refresh() } else { self?.message = "Reminders access denied" }
                }
            }
        } else {
            store.requestAccess(to: .reminder) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.status = EKEventStore.authorizationStatus(for: .reminder)
                    if granted { self?.refresh() } else { self?.message = "Reminders access denied" }
                }
            }
        }
    }

    func refresh() {
        guard hasAccess else {
            items = []
            return
        }
        loadToken += 1
        let token = loadToken
        isLoading = true

        let incomplete = store.predicateForIncompleteReminders(withDueDateStarting: nil,
                                                              ending: nil,
                                                              calendars: nil)
        let completedSince = Calendar.current.date(byAdding: .day, value: -3,
                                                   to: Calendar.current.startOfDay(for: Date()))
        let completed = store.predicateForCompletedReminders(withCompletionDateStarting: completedSince,
                                                             ending: nil,
                                                             calendars: nil)

        store.fetchReminders(matching: incomplete) { [weak self] open in
            guard let self else { return }
            let openItems = (open ?? []).map(Self.makeItem)
            self.store.fetchReminders(matching: completed) { [weak self] done in
                guard let self else { return }
                let doneItems = (done ?? []).map(Self.makeItem)
                DispatchQueue.main.async {
                    guard token == self.loadToken else { return }
                    self.items = Self.ordered(openItems, doneItems)
                    self.isLoading = false
                }
            }
        }
    }

    func toggle(_ item: ReminderItem) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else {
            refresh()
            return
        }
        reminder.isCompleted.toggle()
        reminder.completionDate = reminder.isCompleted ? Date() : nil
        do {
            try store.save(reminder, commit: true)
            message = nil
            refresh()
        } catch {
            message = "Couldn't update the reminder."
            refresh()
        }
    }

    @discardableResult
    func add(_ title: String) -> Bool {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, hasAccess else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.title = clean
        reminder.calendar = store.defaultCalendarForNewReminders() ?? store.calendars(for: .reminder).first
        guard reminder.calendar != nil else {
            message = "No reminder list found."
            return false
        }
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        reminder.dueDateComponents = comps
        do {
            try store.save(reminder, commit: true)
            message = nil
            refresh()
            return true
        } catch {
            message = "Couldn't save the reminder."
            return false
        }
    }

    // MARK: - mapping

    private static func makeItem(_ reminder: EKReminder) -> ReminderItem {
        let comps = reminder.dueDateComponents
        let due = comps.flatMap { Calendar.current.date(from: $0) }
        let timed = comps?.hour != nil
        let color = reminder.calendar?.color ?? NSColor.systemGray
        return ReminderItem(id: reminder.calendarItemIdentifier,
                            title: reminder.title?.isEmpty == false ? reminder.title! : "Untitled reminder",
                            due: due,
                            hasTime: timed,
                            isCompleted: reminder.isCompleted,
                            listName: reminder.calendar?.title ?? "Reminders",
                            colorHex: Util.hexString(color),
                            completedAt: reminder.completionDate)
    }

    private static func ordered(_ open: [ReminderItem], _ done: [ReminderItem]) -> [ReminderItem] {
        let sortedOpen = open.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
        let sortedDone = done
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .prefix(6)
        return sortedOpen + Array(sortedDone)
    }
}
