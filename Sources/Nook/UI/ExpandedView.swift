import SwiftUI

struct ExpandedView: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var stats = StatsService.shared

    private var headerHeight: CGFloat { NotchController.shared.compactSize.height }
    private var contentHeight: CGFloat {
        NotchController.shared.expandedSize.height - headerHeight - TabBarMetrics.height - 6
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch state.visibleTab {
                case .media: NowPlayingPanel()
                case .calendar: CalendarPanel()
                case .weather: WeatherPanel()
                case .reminders: RemindersPanel()
                case .mirror: MirrorPanel()
                case .shelf: ShelfPanel()
                case .launcher: LauncherPanel()
                case .clipboard: ClipboardPanel()
                case .notes: NotesPanel()
                case .timer: TimerPanel()
                case .color: ColorPickerPanel()
                case .stats: StatsPanel()
                case .agents: AgentsPanel()
                case .settings: SettingsPanel()
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: max(80, contentHeight), alignment: .top)
            .padding(.horizontal, 14)

            TabBar()
                .padding(.top, 4)
        }
        .frame(width: settings.expandedSize.width)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > abs(dy), abs(dx) > 40 {
                        NotchController.shared.stepTab(dx < 0 ? 1 : -1)
                    } else if dy < -40 {
                        NotchController.shared.unpin()
                        NotchController.shared.collapse()
                    }
                }
        )
    }

    private var header: some View {
        ZStack {
            // keeps the physical notch clear of controls
            Color.clear
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: state.visibleTab.symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.accent)
                    Text(state.visibleTab.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text)
                    if state.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 14)

            HStack(spacing: 8) {
                if stats.snapshot.charging, let percent = stats.snapshot.batteryPercent {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(percent)%")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent.opacity(0.12)))
                    .help("Charging")
                }
                Button {
                    state.pinned.toggle()
                    if !state.pinned { NotchController.shared.scheduleCollapseNow() }
                } label: {
                    Image(systemName: state.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                }
                Button {
                    NotchController.shared.unpin()
                    NotchController.shared.collapse()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(PressableButtonStyle())
            .fixedSize()
            .foregroundColor(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 14)
        }
        .frame(height: headerHeight)
    }
}

enum TabBarMetrics {
    static let height: CGFloat = 40
}

struct TabBar: View {
    @EnvironmentObject var state: NotchState

    var body: some View {
        HStack(spacing: 2) {
            ForEach(state.visibleTabs) { tab in
                TabButton(tab: tab, isSelected: state.visibleTab == tab)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: TabBarMetrics.height)
        .padding(.bottom, 4)
    }
}

private struct TabButton: View {
    let tab: NookTab
    let isSelected: Bool
    @EnvironmentObject var state: NotchState
    @ObservedObject private var agents = AgentService.shared
    @State private var hovering = false

    var body: some View {
        Button {
            NotchController.shared.open(tab: tab, pin: true)
        } label: {
            Image(systemName: tab.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? Theme.accent : (hovering ? Theme.text : Theme.textSecondary))
                .frame(width: 34, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Theme.accent.opacity(0.16) : Color.white.opacity(hovering ? 0.07 : 0))
                )
                .overlay(alignment: .topTrailing) {
                    if tab == .agents, agents.anyWorking {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 5, height: 5)
                            .padding(.top, 3)
                            .padding(.trailing, 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.title)
    }
}
