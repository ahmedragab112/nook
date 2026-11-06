import EventKit
import SwiftUI

struct RemindersPanel: View {
    @ObservedObject var service = RemindersService.shared
    @State private var draft = ""
    @FocusState private var composing: Bool

    var body: some View {
        VStack(spacing: 7) {
            if service.hasAccess || RunMode.isRendering {
                addBar
                if displayItems.isEmpty {
                    EmptyState(symbol: "checkmark.circle",
                               title: "All clear",
                               detail: "No reminders waiting. Add one above.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            } else {
                permissionView
            }
        }
        .onAppear {
            if service.status == .notDetermined && !RunMode.isRendering { service.requestAccess() }
            else if service.hasAccess { service.refresh() }
        }
    }

    private var displayItems: [ReminderItem] {
        RunMode.isRendering && !service.hasAccess ? Self.demo : service.items
    }

    private var addBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(Theme.accent)
            TextField("Add a reminder for today…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(Theme.text)
                .focused($composing)
                .onSubmit(add)
            if !trimmedDraft.isEmpty {
                Button("Add", action: add)
                    .buttonStyle(PressableButtonStyle())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.accent)
            } else {
                Text("Today")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white.opacity(0.05)))
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                section("Today", items: todayItems)
                section("Upcoming", items: upcomingItems)
                section("Done", items: doneItems)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [ReminderItem]) -> some View {
        if !items.isEmpty {
            Text(title)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textTertiary)
                .textCase(.uppercase)
                .padding(.top, 3)
                .padding(.leading, 2)
            ForEach(items) { item in
                row(item)
            }
        }
    }

    private func row(_ item: ReminderItem) -> some View {
        HStack(spacing: 7) {
            Button {
                service.toggle(item)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(item.isCompleted ? Theme.accent : Theme.textTertiary)
            }
            .buttonStyle(.plain)

            Capsule()
                .fill(Util.color(hex: item.colorHex).opacity(item.isCompleted ? 0.35 : 0.9))
                .frame(width: 2.5, height: 16)

            Text(item.title)
                .font(.system(size: 11, weight: item.isCompleted ? .regular : .medium, design: .rounded))
                .foregroundColor(item.isCompleted ? Theme.textTertiary : Theme.text)
                .strikethrough(item.isCompleted, color: Theme.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let due = item.due {
                Text(dueText(due, timed: item.hasTime, item: item))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(dueColor(due, item: item))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(item.isOverdue ? Color.red.opacity(0.07) : Color.white.opacity(0.03)))
    }

    private var permissionView: some View {
        let blocked = service.status == .denied || service.status == .restricted
        return EmptyState(symbol: "checklist",
                          title: blocked ? "Reminders access is off" : "Reminders access needed",
                          detail: "Nook reads your reminders locally and never uploads anything.",
                          actionTitle: blocked ? "Open System Settings" : "Allow access") {
            if blocked {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
            } else {
                service.requestAccess()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - grouping

    private var todayItems: [ReminderItem] {
        let end = Calendar.current.date(byAdding: .day, value: 1,
                                        to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return displayItems.filter { !$0.isCompleted && ($0.due.map { $0 < end } ?? false) }
    }

    private var upcomingItems: [ReminderItem] {
        let end = Calendar.current.date(byAdding: .day, value: 1,
                                        to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return displayItems.filter { !$0.isCompleted && (($0.due.map { $0 >= end }) ?? true) }
    }

    private var doneItems: [ReminderItem] {
        displayItems.filter(\.isCompleted)
    }

    // MARK: - helpers

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        guard !trimmedDraft.isEmpty else { return }
        if service.add(trimmedDraft) { draft = "" }
    }

    private func dueText(_ date: Date, timed: Bool, item: ReminderItem) -> String {
        let cal = Calendar.current
        let time = DateFormatter()
        time.setLocalizedDateFormatFromTemplate("jmm")
        if cal.isDateInToday(date) {
            return timed ? time.string(from: date) : "Today"
        }
        if item.isOverdue {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                          to: cal.startOfDay(for: Date())).day ?? 0
            return days <= 1 ? "Yesterday" : "\(days)d late"
        }
        if cal.isDateInTomorrow(date) { return timed ? "Tmrw " + time.string(from: date) : "Tomorrow" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d")
        return f.string(from: date)
    }

    private func dueColor(_ date: Date, item: ReminderItem) -> Color {
        if item.isCompleted { return Theme.textTertiary }
        if item.isOverdue { return Color(red: 1.0, green: 0.45, blue: 0.45) }
        if Calendar.current.isDateInToday(date) { return Theme.accent }
        return Theme.textTertiary
    }

    private static let demo: [ReminderItem] = {
        let cal = Calendar.current
        let today = Date()
        return [
            .init(id: "d1", title: "Send the Nook build to the team", due: today, hasTime: true,
                  isCompleted: false, listName: "Work", colorHex: "#FF7A1A", completedAt: nil),
            .init(id: "d2", title: "Renew Apple Developer membership", due: cal.date(byAdding: .day, value: -2, to: today),
                  hasTime: false, isCompleted: false, listName: "Admin", colorHex: "#4C9BFF", completedAt: nil),
            .init(id: "d3", title: "Book dentist appointment", due: cal.date(byAdding: .day, value: 2, to: today),
                  hasTime: false, isCompleted: false, listName: "Personal", colorHex: "#42C98B", completedAt: nil),
            .init(id: "d4", title: "Review pull request #42", due: nil, hasTime: false,
                  isCompleted: false, listName: "Work", colorHex: "#FF7A1A", completedAt: nil),
            .init(id: "d5", title: "Water the plants", due: today, hasTime: false,
                  isCompleted: true, listName: "Home", colorHex: "#B87CFF", completedAt: today)
        ]
    }()
}
