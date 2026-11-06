import AppKit
import Combine

/// Tracks what is playing across the system: Apple Music and Spotify through
/// AppleScript, plus every other app (browsers running YouTube, QuickTime,
/// podcast players, …) through the system now playing feed.
final class NowPlayingService: ObservableObject {
    static let shared = NowPlayingService()

    enum Source: String { case none = "Nothing playing", music = "Music", spotify = "Spotify", system = "Now Playing" }

    @Published private(set) var source: Source = .none
    @Published private(set) var isPlaying = false
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var volume: Double = 50
    @Published private(set) var artwork: NSImage?
    @Published private(set) var available: [Source] = []
    /// App that owns the active track, e.g. "Safari" for a YouTube tab.
    @Published private(set) var clientName = ""

    private struct Track {
        var source: Source
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
        var position: TimeInterval
        var playing: Bool
        var volume: Double
        var clientName: String = ""
        var clientBundle: String = ""
        var artwork: NSImage?
        var sampleDate = Date()
    }

    private let remote = MediaRemoteAdapter()
    private var timer: Timer?
    private var cache: [String: NSAppleScript] = [:]
    private var systemTrack: Track?
    private var lastPositionSample = Date.distantPast
    private var lastTrackKey = ""
    private var clientBundle = ""
    private var demo = false

    private var preferredSource: Source? {
        get {
            switch UserDefaults.standard.string(forKey: "preferredPlayer") {
            case "spotify": return .spotify
            case "music": return .music
            default: return nil
            }
        }
        set {
            if let newValue, newValue != .none {
                UserDefaults.standard.set(newValue.rawValue.lowercased(), forKey: "preferredPlayer")
            } else {
                UserDefaults.standard.set(nil, forKey: "preferredPlayer")
            }
        }
    }

    func setMusicPreferred() { preferredSource = .music; poll() }
    func setSpotifyPreferred() { preferredSource = .spotify; poll() }

    private init() {}

    func start() {
        if RunMode.isDemo {
            demo = true
            applyDemoTrack()
            return
        }
        remote.onUpdate = { [weak self] snapshot in
            guard let self else { return }
            self.applySystem(snapshot)
        }
        remote.start()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        remote.stop()
    }

    /// Short label for the panel chip, e.g. "Safari" or "Apple Music".
    var sourceLabel: String {
        switch source {
        case .none: return ""
        case .music: return "Apple Music"
        case .spotify: return "Spotify"
        case .system: return clientName.isEmpty ? "Now Playing" : clientName
        }
    }

    /// True when the current track comes from something other than the two
    /// AppleScript players (a browser, QuickTime, …).
    var isSystemSource: Bool { source == .system }

    private static let bundleIDs: [Source: String] = [.music: "com.apple.Music", .spotify: "com.spotify.client"]

    private func isRunning(_ source: Source) -> Bool {
        guard let id = Self.bundleIDs[source] else { return false }
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == id && !$0.isTerminated }
    }

    private func run(_ key: String, _ source: String) -> String? {
        let script: NSAppleScript
        if let cached = cache[key] {
            script = cached
        } else if let built = NSAppleScript(source: source) {
            cache[key] = built
            script = built
        } else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }

    // MARK: - demo preview

    /// A believable track for `--demo` runs (docs screenshots and the README
    /// strip capture) so no personal listening history is ever shown.
    private func applyDemoTrack() {
        let track = Track(source: .music,
                          title: "Midnight City",
                          artist: "M83",
                          album: "Hurry Up, We're Dreaming",
                          duration: 244,
                          position: 74,
                          playing: true,
                          volume: 62,
                          clientName: "Music",
                          clientBundle: "com.apple.Music",
                          artwork: nil,
                          sampleDate: Date())
        apply(track)
        artwork = Self.demoArtwork()
    }

    private static func demoArtwork() -> NSImage {
        let side: CGFloat = 512
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: side, height: side)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.38, alpha: 1),
            NSColor(calibratedRed: 0.48, green: 0.24, blue: 0.82, alpha: 1),
            NSColor(calibratedRed: 0.94, green: 0.43, blue: 0.60, alpha: 1)
        ])
        gradient?.draw(in: rect, angle: -62)
        NSColor.white.withAlphaComponent(0.14).setFill()
        NSBezierPath(ovalIn: NSRect(x: 40, y: 210, width: 430, height: 430)).fill()
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(ovalIn: NSRect(x: 250, y: -60, width: 320, height: 320)).fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 170, y: 170, width: 172, height: 172))
        ring.lineWidth = 3
        ring.stroke()
        image.unlockFocus()
        return image
    }

    // MARK: - system feed

    private func applySystem(_ snapshot: NowPlayingSnapshot?) {
        guard let snapshot, !snapshot.title.isEmpty else {
            let hadSystem = systemTrack != nil
            systemTrack = nil
            if hadSystem, source == .system { poll() }
            return
        }
        systemTrack = Track(source: .system,
                            title: snapshot.title,
                            artist: snapshot.artist,
                            album: snapshot.album,
                            duration: snapshot.duration,
                            position: snapshot.elapsed,
                            playing: snapshot.playing,
                            volume: volume,
                            clientName: snapshot.appName,
                            clientBundle: snapshot.appBundleID,
                            artwork: snapshot.artwork,
                            sampleDate: snapshot.timestamp)
        poll()
    }

    // MARK: - polling

    private func poll() {
        guard !demo else { return }
        var running: [Source] = []
        if isRunning(.spotify) { running.append(.spotify) }
        if isRunning(.music) { running.append(.music) }
        if available != running { available = running }

        var candidates: [Source: Track] = [:]
        if running.contains(.spotify), let track = spotifyTrack() { candidates[.spotify] = track }
        if running.contains(.music), let track = queryMusic() { candidates[.music] = track }

        let playingApps = running.filter { candidates[$0]?.playing == true }
        var chosen: Track?
        if let preferred = preferredSource, playingApps.contains(preferred) {
            chosen = candidates[preferred]
        } else if let first = playingApps.first {
            chosen = candidates[first]
        } else if let system = systemTrack, system.playing {
            chosen = system
        } else if let preferred = preferredSource, let track = candidates[preferred] {
            chosen = track
        } else if let track = candidates[running.first ?? .none] {
            chosen = track
        } else {
            chosen = systemTrack
        }

        guard let chosen else {
            clear()
            return
        }
        apply(chosen)
    }

    private func apply(_ track: Track) {
        let key = "\(track.source.rawValue)|\(track.title)|\(track.artist)"
        let changed = key != lastTrackKey
        lastTrackKey = key

        source = track.source
        title = track.title
        artist = track.artist
        album = track.album
        duration = track.duration
        position = track.position
        lastPositionSample = track.sampleDate
        isPlaying = track.playing
        clientName = track.clientName
        clientBundle = track.clientBundle
        if track.source != .system {
            volume = track.volume
        }

        if track.source == .music {
            if changed { loadArtwork() }
        } else if let art = track.artwork {
            artwork = art
        } else if track.source == .system {
            artwork = nil
        } else if let system = systemTrack,
                  system.clientBundle == Self.bundleIDs[track.source],
                  let art = system.artwork {
            artwork = art
        } else {
            artwork = nil
        }

        publishActivity()
    }

    private func clear() {
        lastTrackKey = ""
        source = .none
        isPlaying = false
        title = ""
        artist = ""
        album = ""
        duration = 0
        position = 0
        artwork = nil
        clientName = ""
        clientBundle = ""
        NotchController.shared.clearActivity(.media)
    }

    // MARK: - apple script players

    private func spotifyTrack() -> Track? {
        let script = """
        tell application "Spotify"
            if it is not running then return "off"
            set t to current track
            return (name of t) & tab & (artist of t) & tab & (album of t) & tab & ((duration of t) as text) & tab & ((player position) as text) & tab & ((player state) as text) & tab & ((sound volume) as text)
        end tell
        """
        guard let out = run("spotify.query", script) else { return nil }
        let parts = out.components(separatedBy: "\t")
        guard parts.count >= 6 else { return nil }
        return Track(source: .spotify,
                     title: parts[0],
                     artist: parts[1],
                     album: parts[2],
                     duration: (TimeInterval(parts[3]) ?? 0) / 1000,
                     position: (TimeInterval(parts[4]) ?? 0) / 1000,
                     playing: parts[5].contains("playing"),
                     volume: TimeInterval(parts.count > 6 ? parts[6] : "50") ?? 50,
                     clientName: "Spotify",
                     clientBundle: Self.bundleIDs[.spotify] ?? "")
    }

    private func queryMusic() -> Track? {
        let script = """
        tell application "Music"
            if (count of current track) = 0 then return "off"
            set t to current track
            return (name of t) & tab & (artist of t) & tab & (album of t) & tab & ((duration of t) as text) & tab & ((player position) as text) & tab & ((player playback state) as text) & tab & ((sound volume) as text)
        end tell
        """
        guard let out = run("music.query", script) else { return nil }
        let parts = out.components(separatedBy: "\t")
        guard parts.count >= 6 else { return nil }
        return Track(source: .music,
                     title: parts[0],
                     artist: parts[1],
                     album: parts[2],
                     duration: TimeInterval(parts[3]) ?? 0,
                     position: TimeInterval(parts[4]) ?? 0,
                     playing: parts[5].contains("playing"),
                     volume: TimeInterval(parts.count > 6 ? parts[6] : "50") ?? 50,
                     clientName: "Music",
                     clientBundle: Self.bundleIDs[.music] ?? "")
    }

    private func loadArtwork() {
        let script = """
        tell application "Music"
            if (count of artwork of current track) = 0 then return ""
            return (raw data of artwork 1 of current track)
        end tell
        """
        let apple = NSAppleScript(source: script)
        var error: NSDictionary?
        guard let descriptor = apple?.executeAndReturnError(&error), error == nil else { return }
        let data = descriptor.data
        guard data.count > 200 else { return }
        if let image = NSImage(data: data) { artwork = image }
    }

    // MARK: - controls

    private func tell(_ body: String) {
        let app = source == .spotify ? "Spotify" : "Music"
        let script = "tell application \"\(app)\"\n\(body)\nend tell"
        _ = run("control.\(body.hashValue)", script)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.poll() }
    }

    func togglePlayback() {
        switch source {
        case .system:
            remote.send(2)
            isPlaying.toggle()
            lastPositionSample = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.poll() }
        case .none:
            return
        default:
            tell("playpause")
        }
    }

    func next() {
        switch source {
        case .system:
            remote.send(4)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.poll() }
        case .none:
            return
        default:
            tell(source == .spotify ? "next" : "next track")
        }
    }

    func previous() {
        switch source {
        case .system:
            remote.send(5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.poll() }
        case .none:
            return
        default:
            tell(source == .spotify ? "previous" : "back track")
        }
    }

    func seek(to seconds: TimeInterval) {
        switch source {
        case .system:
            remote.seek(to: seconds)
        case .none:
            return
        case .spotify:
            tell("set player position to \(Int(seconds * 1000))")
        case .music:
            tell("set player position to \(seconds)")
        }
        position = seconds
        lastPositionSample = Date()
    }

    func setVolume(_ value: Double) {
        guard source != .system else { return }
        volume = value
        tell("set sound volume to \(Int(value))")
    }

    func openSourceApp() {
        let id: String
        if source == .system {
            id = clientBundle
        } else {
            id = Self.bundleIDs[source] ?? ""
        }
        guard !id.isEmpty,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Interpolated position for smooth progress bars.
    var livePosition: TimeInterval {
        guard isPlaying, duration > 0 else { return position }
        let drift = Date().timeIntervalSince(lastPositionSample)
        return min(duration, position + drift)
    }

    /// Written while scrubbing so the bar tracks the finger before the app catches up.
    var lastPositionSampleAt: Date {
        get { lastPositionSample }
        set { lastPositionSample = newValue }
    }

    private func publishActivity() {
        guard AppSettings.shared.compactContent != .none else {
            NotchController.shared.clearActivity(.media)
            return
        }
        guard !title.isEmpty else {
            NotchController.shared.clearActivity(.media)
            return
        }
        let detail: String? = artist.isEmpty
            ? (duration > 0 ? "-" + Util.clock(max(0, duration - livePosition)) : nil)
            : artist
        NotchController.shared.setActivity(.init(kind: .media, symbol: "music.note",
                                                 text: title, detail: detail,
                                                 progress: duration > 0 ? livePosition / duration : nil))
    }
}
