import Combine
import EventKit
import SwiftUI

struct CalendarPanel: View {
    @ObservedObject var calendar = CalendarService.shared
    private var timeline = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            if calendar.hasAccess || RunMode.isRendering { weekStrip }
            Group {
                if !calendar.hasAccess && !RunMode.isRendering {
                    permissionView
                } else if calendar.todays.isEmpty && calendar.nextEvent == nil {
                    EmptyState(symbol: "calendar.badge.clock",
                               title: "Nothing scheduled",
                               detail: "No events for the rest of today.") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        nextCard
                            .frame(width: 200)
                        list
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onReceive(timeline) { _ in calendar.refresh() }
        .onAppear {
            if calendar.status == .notDetermined && !RunMode.isRendering { calendar.requestAccess() }
        }
    }

    // MARK: - week strip

    private var weekStrip: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let first = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
        return HStack(spacing: 5) {
            ForEach(days, id: \.self) { day in
                dayChip(day)
            }
        }
    }

    private func dayChip(_ day: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let hasEvents = calendar.events.contains { $0.start < end && $0.end >= start }
        let isPast = end <= Date() && !isToday
        return VStack(spacing: 3) {
            Text(dayLetter(day))
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundColor(isToday ? Theme.accent : Theme.textTertiary)
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 11.5, weight: isToday ? .bold : .semibold, design: .rounded))
                .foregroundColor(isToday ? .black : (isPast ? Theme.textTertiary : Theme.text))
                .frame(width: 24, height: 24)
                .background(Circle().fill(isToday ? Theme.accent : Color.white.opacity(0.05)))
            Circle()
                .fill(hasEvents ? (isToday ? Theme.accent : Theme.textSecondary.opacity(0.7)) : Color.clear)
                .frame(width: 3, height: 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(isToday ? Theme.accent.opacity(0.10) : Color.white.opacity(0.03)))
        .opacity(isPast ? 0.6 : 1)
    }

    private func dayLetter(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date)
    }

    private var permissionView: some View {
        let blocked = calendar.status == .denied || calendar.status == .restricted
        return EmptyState(symbol: "calendar",
                          title: blocked ? "Calendar access is off" : "Calendar access needed",
                          detail: "Nook reads your events locally and never uploads anything.",
                          actionTitle: blocked ? "Open System Settings" : "Allow access") {
            if blocked {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            } else {
                calendar.requestAccess()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let next = calendar.nextEvent {
                let minutes = Int((next.start.timeIntervalSinceNow / 60).rounded())
                HStack(spacing: 5) {
                    Image(systemName: minutes <= 0 ? "play.circle.fill" : "clock")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.accent)
                    Text(minutes <= 0 ? "Happening now" : "In \(Util.hoursMinutes(next.start.timeIntervalSinceNow))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.accent)
                }
                Text(next.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(timeRange(next))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                if !next.location.isEmpty {
                    Label(next.location, systemImage: "location")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                }
                if let join = next.joinURL {
                    Button {
                        NSWorkspace.shared.open(join)
                    } label: {
                        Label("Join", systemImage: "arrow.forward.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Theme.accent)
                }
            } else {
                Label("No upcoming events", systemImage: "moon.stars")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private var list: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Today", subtitle: dayString)
                .padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(calendar.todays) { event in row(event) }
                    if calendar.todays.isEmpty {
                        Text("Clear day.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                    }
                }
            }
        }
    }

    private func row(_ event: CalEvent) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Util.color(hex: event.colorHex))
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 11.5, weight: event.isPast ? .regular : .semibold, design: .rounded))
                    .foregroundColor(event.isPast ? Theme.textTertiary : Theme.text)
                    .lineLimit(1)
                Text(event.allDay ? "All day" : shortTime(event.start) + " – " + shortTime(event.end))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
            }
            Spacer()
            if event.isRunning { ChipLabel(text: "NOW", color: Theme.accent) }
            if let join = event.joinURL {
                Button {
                    NSWorkspace.shared.open(join)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(PressableButtonStyle())
                .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(event.isRunning ? Theme.accent.opacity(0.10) : Color.white.opacity(0.03)))
        .opacity(event.isPast ? 0.55 : 1)
    }

    private var dayString: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return f.string(from: Date())
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: date)
    }

    private func timeRange(_ event: CalEvent) -> String {
        event.allDay ? "All day" : "\(shortTime(event.start)) – \(shortTime(event.end))"
    }
}
