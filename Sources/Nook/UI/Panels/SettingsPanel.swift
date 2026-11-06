import Carbon.HIToolbox
import SwiftUI

struct SettingsPanel: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                NotchSettingsSection(settings: settings)
                SizeSettingsSection(settings: settings)
                PanelsSettingsSection(settings: settings)
                GestureSettingsSection(settings: settings)
                WeatherSettingsSection(settings: settings)
                LiveActivitySettingsSection(settings: settings)
                ToolsSettingsSection(settings: settings)
                HotkeySettingsSection(settings: settings)
                GeneralSettingsSection(settings: settings)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: settings.widthPreset) { _ in NotchController.shared.rebuildForSettings() }
        .onChange(of: settings.notchWidthOffset) { _ in NotchController.shared.rebuildForSettings() }
        .onChange(of: settings.notchHeightOffset) { _ in NotchController.shared.rebuildForSettings() }
        .onChange(of: settings.compactContent) { _ in NotchController.shared.rebuildForSettings() }
    }
}

// MARK: - building blocks

struct SettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.accent)
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                    .textCase(.uppercase)
            }
            content
            Divider().overlay(Theme.hairline)
        }
    }
}

struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textSecondary)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(Theme.accent)
    }
}

struct SettingsNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundColor(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsCounter: View {
    let title: String
    var help: String? = nil
    @Binding var value: CGFloat
    var step: CGFloat = 1
    var lower: CGFloat = -40
    var upper: CGFloat = 60
    var integer = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textSecondary)
                if let help {
                    Text(help).font(.system(size: 9)).foregroundColor(Theme.textTertiary)
                }
            }
            Spacer()
            Button { value = max(lower, value - step) } label: {
                Image(systemName: "minus").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(PressableButtonStyle())
            Text(integer ? "\(Int(value))" : String(format: "%+.0f", value))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.text)
                .frame(minWidth: 26)
            Button { value = min(upper, value + step) } label: {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .foregroundColor(Theme.textSecondary)
    }
}

// MARK: - sections

struct NotchSettingsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsSection(title: "Notch", symbol: "rectangle.topthird.inset") {
            VStack(alignment: .leading, spacing: 6) {
                SettingsToggle(title: "Open on hover", isOn: $settings.hoverToOpen)
                SettingsToggle(title: "Auto-collapse when the pointer leaves", isOn: $settings.autoCollapse)
                if settings.autoCollapse {
                    HStack {
                        Text("Collapse delay")
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.textSecondary)
                        Slider(value: $settings.collapseDelay, in: 0.15...1.5)
                            .controlSize(.mini)
                            .tint(Theme.accent)
                        Text(String(format: "%.2fs", settings.collapseDelay))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                SettingsToggle(title: "Hide in fullscreen spaces", isOn: $settings.hideInFullscreen)
                SettingsToggle(title: "Follow the display under the pointer", isOn: $settings.followFrontmostScreen)
            }
        }
    }
}

struct SizeSettingsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsSection(title: "Size & look", symbol: "ruler") {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    SettingsLabel(text: "Panel size")
                    Spacer()
                    Picker("", selection: $settings.widthPreset) {
                        ForEach(AppSettings.WidthPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                SettingsCounter(title: "Notch width offset",
                                help: "Match the pill to your real notch",
                                value: $settings.notchWidthOffset)
                SettingsCounter(title: "Notch height offset",
                                help: "Seat the pill on the bezel",
                                value: $settings.notchHeightOffset)
                HStack {
                    SettingsLabel(text: "Shell opacity")
                    Spacer()
                    Slider(value: $settings.shellOpacity, in: 0.6...1.0)
                        .controlSize(.mini)
                        .tint(Theme.accent)
                        .frame(width: 120)
                }
                HStack {
                    SettingsLabel(text: "Accent")
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: Util.nsColor(settings.accentHex)) },
                        set: { settings.accentHex = Util.hexString(NSColor($0)) }))
                        .labelsHidden()
                        .frame(width: 50)
                }
                HStack {
                    SettingsLabel(text: "In the notch")
                    Spacer()
                    Picker("", selection: $settings.compactContent) {
                        ForEach(AppSettings.CompactContent.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }
        }
    }
}

struct SettingsLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundColor(Theme.textSecondary)
    }
}

struct PanelsSettingsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsSection(title: "Panels", symbol: "square.grid.3x3") {
            VStack(alignment: .leading, spacing: 7) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 6)], spacing: 6) {
                    ForEach(NookTab.allCases) { tab in
                        TabChip(tab: tab,
                                isOn: settings.enabledTabs.contains(tab)) {
                            settings.toggleTab(tab)
                        }
                    }
                }
                HStack(spacing: 4) {
                    Text("Order")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textTertiary)
                        .textCase(.uppercase)
                    Spacer()
                    Text("Tabs left to right, like the notch bar")
                        .font(.system(size: 8.5))
                        .foregroundColor(Theme.textTertiary)
                }
                VStack(spacing: 3) {
                    ForEach(Array(settings.enabledTabs.enumerated()), id: \.element) { index, tab in
                        HStack(spacing: 6) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Theme.accent)
                                .frame(width: 12)
                            Text(tab.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            orderButton("chevron.up", enabled: index > 0) {
                                settings.moveTab(tab, by: -1)
                            }
                            orderButton("chevron.down", enabled: index < settings.enabledTabs.count - 1) {
                                settings.moveTab(tab, by: 1)
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.03)))
                    }
                }
            }
        }
    }

    private func orderButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 18, height: 16)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(enabled ? 0.06 : 0.02)))
        }
        .buttonStyle(.plain)
        .foregroundColor(enabled ? Theme.textSecondary : Theme.textTertiary.opacity(0.3))
        .disabled(!enabled)
    }
}

struct GestureSettingsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsSection(title: "Gestures & layout", symbol: "hand.draw") {
            VStack(alignment: .leading, spacing: 6) {
                SettingsToggle(title: "Swipe down on the notch to open", isOn: $settings.swipeToOpen)
                SettingsToggle(title: "Scroll over the notch to open", isOn: $settings.scrollToOpen)
                SettingsToggle(title: "Click the notch to toggle", isOn: $settings.clickToOpen)
                SettingsToggle(title: "Reopen the last panel", isOn: $settings.rememberLastTab)
                SettingsNote(text: "Swipe left or right inside the panel to change tabs. Pin keeps it open.")
            }
        }
    }
}

struct LiveActivitySettingsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsSection(title: "Live activity", symbol: "bolt.badge.clock") {
            VStack(alignment: .leading, spacing: 6) {
                SettingsToggle(title: "Charging indicator with battery percentage", isOn: $settings.showChargingHUD)
                SettingsToggle(title: "Bluetooth connect & disconnect alerts", isOn: $settings.showBluetoothActivity)
                SettingsNote(text: "Activity pills appear beside the notch, then fold away after a few seconds.")
            }
        }
    }
}

struct WeatherSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var weather = WeatherService.shared

    var body: some View {
        SettingsSection(title: "Weather", symbol: "cloud.sun") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    SettingsLabel(text: "City")
                    TextField("Cairo", text: $settings.weatherCity)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.text)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.06)))
                        .onSubmit { weather.refresh(force: true) }
                    Button {
                        weather.refresh(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .foregroundColor(Theme.accent)
                    .help("Refresh forecast")
                }
                if let snap = weather.snapshot {
                    SettingsNote(text: "\(snap.city) · \(WeatherService.label(for: snap.now.code)) · updated \(updatedText(snap.updated))")
                } else if let error = weather.error {
                    SettingsNote(text: error)
                } else {
                    SettingsNote(text: "Geocoded by Open-Meteo. No account, no API key.")
                }
            }
        }
    }

    private func updatedText(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
}

struct TabChip: View {
    let tab: NookTab
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(tab.title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(isOn ? Theme.accent : Theme.textTertiary)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct ToolsSettingsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsSection(title: "Tools", symbol: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: 6) {
                SettingsToggle(title: "Clipboard history", isOn: $settings.clipboardEnabled)
                if settings.clipboardEnabled {
                    SettingsCounter(title: "History size", value: Binding(
                        get: { CGFloat(settings.clipboardLimit) },
                        set: { settings.clipboardLimit = Int(max(5, $0)) }),
                        step: 5, lower: 5, upper: 100, integer: true)
                    SettingsToggle(title: "Paste right after choosing a clip", isOn: $settings.pasteOnSelect)
                    if settings.pasteOnSelect {
                        SettingsNote(text: "Requires Accessibility permission in System Settings › Privacy & Security.")
                    }
                }
                SettingsToggle(title: "Volume slider in Now Playing", isOn: $settings.mediaVolumeControl)
                SettingsToggle(title: "Volume & brightness HUD", isOn: $settings.showSystemHUD)
                SettingsToggle(title: "Auto-clean shelf after 7 days", isOn: $settings.shelfAutoClean)
            }
        }
    }
}

struct HotkeySettingsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsSection(title: "Shortcut", symbol: "command") {
            VStack(alignment: .leading, spacing: 6) {
                SettingsToggle(title: "Global hotkey to toggle Nook", isOn: $settings.hotkeyEnabled)
                if settings.hotkeyEnabled {
                    HStack {
                        Text("Key").font(.system(size: 10.5)).foregroundColor(Theme.textSecondary)
                        Spacer()
                        Picker("", selection: $settings.hotkeyKeyCode) {
                            ForEach(HotkeyCenter.selectableKeys, id: \.self) { code in
                                Text(HotkeyCenter.keyName(code)).tag(code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }
                    ModifierRow(modifiers: $settings.hotkeyModifiers)
                    HStack {
                        Spacer()
                        Text(HotkeyCenter.describe(keyCode: settings.hotkeyKeyCode,
                                                   modifiers: settings.hotkeyModifiers))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.accent)
                    }
                }
            }
        }
    }
}

struct ModifierRow: View {
    @Binding var modifiers: UInt32

    var body: some View {
        HStack(spacing: 6) {
            chip("⌘", Int(cmdKey))
            chip("⌥", Int(optionKey))
            chip("⌃", Int(controlKey))
            chip("⇧", Int(shiftKey))
            Spacer()
        }
    }

    private func chip(_ symbol: String, _ flag: Int) -> some View {
        let on = modifiers & UInt32(flag) != 0
        return Button {
            modifiers ^= UInt32(flag)
        } label: {
            Text(symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(on ? Theme.accent.opacity(0.2) : Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .foregroundColor(on ? Theme.accent : Theme.textTertiary)
    }
}

struct GeneralSettingsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsSection(title: "General", symbol: "gearshape") {
            VStack(alignment: .leading, spacing: 6) {
                SettingsToggle(title: "Launch at login", isOn: $settings.launchAtLogin)
                HStack(spacing: 6) {
                    smallButton("Support folder") {
                        NSWorkspace.shared.open(Util.appSupport)
                    }
                    smallButton("Permissions") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
                    }
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                        .buttonStyle(PressableButtonStyle())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.red)
                }
                SettingsNote(text: "Nook \(version) · local-first. Only the weather forecast is fetched online; everything else stays on this Mac.")
            }
        }
    }

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PressableButtonStyle())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Theme.textSecondary)
    }
}
