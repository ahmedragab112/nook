import Combine
import SwiftUI

struct NowPlayingPanel: View {
    @ObservedObject var player = NowPlayingService.shared
    @ObservedObject var dials = SystemDialService.shared
    @State private var refresh = false

    private var timeline = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            artwork
                .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 8) {
                if player.source == .none || player.title.isEmpty {
                    EmptyState(symbol: "music.note.list",
                               title: "Nothing playing",
                               detail: "Play something in Safari, Chrome, Spotify, or Music.",
                               actionTitle: player.available.isEmpty
                                    ? "Open Music"
                                    : "Open \(player.source == .spotify ? "Spotify" : "Music")") {
                        if player.available.isEmpty {
                            open(bundle: "com.apple.Music")
                        } else {
                            player.openSourceApp()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    headline
                    progress
                    controls
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                sourceButtons
                volumeBlock
                Spacer()
            }
            .frame(width: 150)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(timeline) { _ in refresh.toggle() }
    }

    @ViewBuilder private var artwork: some View {
        Group {
            if let image = player.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accent.opacity(0.5), Color.white.opacity(0.08)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: player.isPlaying ? "music.note" : "pause.circle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(player.title.isEmpty ? "Unknown track" : player.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 6) {
                Text(player.artist)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                if !player.album.isEmpty {
                    Text("·").foregroundColor(Theme.textTertiary)
                    Text(player.album)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            ChipLabel(text: player.sourceLabel,
                      systemImage: player.isPlaying ? "play.fill" : "pause.fill",
                      color: player.isPlaying ? Theme.accent : Theme.textSecondary)
        }
    }

    private var progress: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let ratio = player.duration > 0 ? min(max(player.livePosition / player.duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 4)
                    Capsule().fill(Theme.accent)
                        .frame(width: max(2, geo.size.width * CGFloat(ratio)), height: 4)
                }
                .frame(height: geo.size.height, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard player.duration > 0 else { return }
                            let x = max(0, min(geo.size.width, value.location.x))
                            player.position = player.duration * Double(x / max(1, geo.size.width))
                            player.lastPositionSampleAt = Date()
                        }
                        .onEnded { value in
                            guard player.duration > 0 else { return }
                            let x = max(0, min(geo.size.width, value.location.x))
                            player.seek(to: player.duration * Double(x / max(1, geo.size.width)))
                        }
                )
            }
            .frame(height: 14)

            HStack {
                Text(Util.clock(player.livePosition))
                Spacer()
                Text(player.duration > 0 ? "-" + Util.clock(max(0, player.duration - player.livePosition)) : "--:--")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(Theme.textTertiary)
            .monospacedDigit()
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 14))
            }
            Button { player.togglePlayback() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.accent))
                    .foregroundColor(.black)
            }
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 14))
            }
        }
        .foregroundColor(Theme.text)
        .buttonStyle(PressableButtonStyle())
    }

    private var sourceButtons: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if player.isSystemSource {
                HStack(spacing: 3) {
                    Image(systemName: "globe")
                        .font(.system(size: 8, weight: .bold))
                    Text(player.clientName.isEmpty ? "Now Playing" : player.clientName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.accent.opacity(0.14)))
            }
            ForEach([NowPlayingService.Source.spotify, .music], id: \.self) { candidate in
                Button {
                    guard let id = bundle(for: candidate),
                          let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
                    if candidate == .music { NowPlayingService.shared.setMusicPreferred() }
                    else { NowPlayingService.shared.setSpotifyPreferred() }
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: candidate == .music ? "music.note" : "circle.grid.2x2.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(candidate == .music ? "Music" : "Spotify")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableButtonStyle())
                .foregroundColor(player.source == candidate ? Theme.accent : Theme.textSecondary)
                .disabled(!player.available.contains(candidate))
            }
        }
    }

    private var volumeBlock: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: dials.volume <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textSecondary)
                Text("\(Int(dials.volume))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
            }
            if AppSettings.shared.mediaVolumeControl {
                Slider(value: Binding(get: { dials.volume }, set: { dials.setVolume($0) }), in: 0...100)
                    .controlSize(.small)
                    .tint(Theme.accent)
            }
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill").font(.system(size: 9)).foregroundColor(Theme.textSecondary)
                Text("\(Int(dials.brightness * 100))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
            }
            Slider(value: Binding(get: { dials.brightness * 100 },
                                  set: { dials.setBrightness($0 / 100) }), in: 0...100)
                .controlSize(.small)
                .tint(.yellow)
                .disabled(!dials.hasDisplayControls)
        }
    }

    private func bundle(for source: NowPlayingService.Source) -> String? {
        switch source {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        case .system, .none: return nil
        }
    }

    private func open(bundle: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
