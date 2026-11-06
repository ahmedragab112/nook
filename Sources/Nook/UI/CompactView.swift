import Combine
import SwiftUI

struct CompactView: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var stats = StatsService.shared
    @ObservedObject private var player = NowPlayingService.shared

    private var hasVisibleCard: Bool {
        if state.hud != nil { return true }
        guard let activity = state.liveActivity else { return false }
        if activity.kind == .media {
            return state.showsMediaCard || player.isPlaying
        }
        return true
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack {
                // Tapping anywhere but the transport button opens the notch.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { openCompact() }

                // Charging percentage sits in the left ear of the bare notch.
                if !hasVisibleCard, NotchController.shared.compactNotchGap == 0,
                   stats.snapshot.charging, let percent = stats.snapshot.batteryPercent {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(percent)%")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.leading, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                }

                ZStack {
                    // camera lens so the pill reads like a real notch
                    if !hasVisibleCard {
                        Circle()
                            .fill(RadialGradient(colors: [Color.white.opacity(0.14), Color.black],
                                                 center: .center, startRadius: 0, endRadius: 4))
                            .frame(width: 9, height: 9)
                            .position(x: geo.size.width - 16, y: height / 2 - 1)
                            .allowsHitTesting(false)
                    }

                    if let hud = state.hud {
                        HUDRow(hud: hud)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .allowsHitTesting(false)
                    } else if let activity = state.liveActivity {
                        if activity.kind == .media {
                            if state.showsMediaCard {
                                ActivityRow(activity: activity)
                            } else if player.isPlaying {
                                MiniMediaRow()
                            }
                        } else {
                            ActivityRow(activity: activity)
                        }
                    } else {
                        Color.clear
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(width: geo.size.width, height: height)
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onEnded { value in
                    guard settings.swipeToOpen else { return }
                    if value.translation.height > 18 {
                        NotchController.shared.open(tab: state.tab, pin: true)
                    }
                }
        )
    }

    private func openCompact() {
        guard state.hud == nil else { return }
        guard settings.clickToOpen else { return }
        if state.liveActivity?.kind == .media, settings.enabledTabs.contains(.media) {
            NotchController.shared.open(tab: .media, pin: true)
        } else {
            NotchController.shared.toggle()
        }
    }
}

private struct ActivityRow: View {
    let activity: NotchState.LiveActivity
    @ObservedObject var player = NowPlayingService.shared

    /// Keep the camera housing clear: content lives in the two "ears".
    private var notchGap: CGFloat { NotchController.shared.compactNotchGap }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 9) {
                if activity.kind == .media {
                    MediaArtwork(size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(activity.text)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let detail = activity.detail {
                            Text(detail)
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                } else {
                    Image(systemName: activity.symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.accent)
                    Text(activity.text)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)

            if notchGap > 0 {
                Spacer()
                    .frame(width: notchGap)
            }

            HStack(spacing: 6) {
                if activity.kind == .media {
                    playPauseButton
                } else if let detail = activity.detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private var playPauseButton: some View {
        Button {
            player.togglePlayback()
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.accent))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(player.isPlaying ? "Pause" : "Play")
    }
}

/// Small persistent now-playing strip: artwork, title/artist and live waves.
private struct MiniMediaRow: View {
    @ObservedObject var player = NowPlayingService.shared
    private var notchGap: CGFloat { NotchController.shared.compactNotchGap }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                MediaArtwork(size: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.title.isEmpty ? "Now playing" : player.title)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    let body = player.artist.isEmpty ? player.album : player.artist
                    if !body.isEmpty {
                        Text(body)
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if notchGap > 0 {
                Spacer()
                    .frame(width: notchGap)
            }

            MiniWave(active: player.isPlaying)
                .fixedSize()
        }
        .allowsHitTesting(false)
    }
}

private struct MiniWave: View {
    var active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !active)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    let phase = time * 5.2 + Double(index) * 1.15
                    let height = 3.5 + (sin(phase) + 1) / 2 * 8.5
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: 2.5, height: height)
                }
            }
            .frame(height: 14)
        }
    }
}

private struct MediaArtwork: View {
    var size: CGFloat = 28
    @ObservedObject var player = NowPlayingService.shared

    var body: some View {
        Group {
            if let image = player.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .fill(Theme.accent.opacity(0.18))
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }
                .frame(width: size, height: size)
            }
        }
    }
}

private struct HUDRow: View {
    let hud: HUDMessage
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: hud.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.accent)
            Text(hud.title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.text)
            if let progress = hud.progress {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule().fill(Theme.accent)
                            .frame(width: max(2, g.size.width * CGFloat(min(max(progress, 0), 1))))
                    }
                }
                .frame(height: 4)
            }
            if let detail = hud.detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct EqualizerBars: View {
    var active: Bool
    var color: Color = Theme.accent

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            bar(active ? 0.85 : 0.35, delay: 0.0)
            bar(active ? 0.45 : 0.6, delay: 0.12)
            bar(active ? 1.0 : 0.4, delay: 0.24)
            bar(active ? 0.55 : 0.7, delay: 0.36)
        }
    }

    private func bar(_ fraction: CGFloat, delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 2)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .scaleEffect(y: max(0.18, fraction), anchor: .bottom)
            .animation(.easeInOut(duration: 0.3).delay(delay), value: active)
    }
}

extension NotificationCenter {
    func timer(interval: TimeInterval) -> AnyPublisher<Date, Never> {
        Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .eraseToAnyPublisher()
    }
}
