import AppKit
import Foundation

/// One now-playing item as reported by the system MediaRemote feed.
struct NowPlayingSnapshot {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var elapsed: TimeInterval
    var timestamp: Date
    var playing: Bool
    var bundleID: String
    var parentBundleID: String
    var artwork: NSImage?

    /// The user-facing app that owns playback (Safari for a YouTube tab, etc.).
    var appBundleID: String { parentBundleID.isEmpty ? bundleID : parentBundleID }

    var appName: String {
        let id = appBundleID
        guard !id.isEmpty else { return "" }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
           let name = running.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
           let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            return name
        }
        return id
    }
}

/// Reads Now Playing information for every app (browsers included) through the
/// bundled MediaRemoteAdapter helper. macOS 15.4+ no longer lets apps call the
/// MediaRemote framework directly, so a bundled Perl script that is entitled to
/// use it streams JSON lines to us.
final class MediaRemoteAdapter {
    var onUpdate: ((NowPlayingSnapshot?) -> Void)?

    private let queue = DispatchQueue(label: "com.nook.mediaremote")
    private var process: Process?
    private var buffer = Data()
    private var fields: [String: Any] = [:]
    private var artworkOwner = ""
    private var artwork: NSImage?
    private var stopping = false
    private var restart: DispatchWorkItem?
    private static let iso = ISO8601DateFormatter()

    var isAvailable: Bool { Self.resources != nil }

    private static var resources: (script: URL, framework: URL)? {
        guard let dir = Bundle.main.resourceURL else { return nil }
        let script = dir.appendingPathComponent("mediaremote-adapter.pl")
        let framework = dir.appendingPathComponent("MediaRemoteAdapter.framework")
        let fm = FileManager.default
        guard fm.fileExists(atPath: script.path),
              fm.fileExists(atPath: framework.path) else { return nil }
        return (script, framework)
    }

    func start() {
        stopping = false
        guard process == nil, let res = Self.resources else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [res.script.path, res.framework.path, "stream", "--debounce=150"]
        let output = Pipe()
        proc.standardOutput = output
        proc.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        proc.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.process = nil
            guard !self.stopping else { return }
            let work = DispatchWorkItem { [weak self] in self?.launch() }
            self.restart = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }
        do {
            try proc.run()
            process = proc
        } catch {
            process = nil
        }
    }

    private func launch() { start() }

    func stop() {
        stopping = true
        restart?.cancel()
        restart = nil
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        queue.async { [weak self] in
            self?.fields = [:]
            self?.artwork = nil
            self?.artworkOwner = ""
        }
    }

    // MARK: playback commands

    /// MRMediaRemoteCommand: 2 toggle, 4 next, 5 previous.
    func send(_ command: Int) {
        run(["send", "\(command)"])
    }

    func seek(to seconds: TimeInterval) {
        run(["seek", "\(max(0, Int(seconds * 1_000_000)))"])
    }

    private func run(_ extra: [String]) {
        guard let res = Self.resources else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [res.script.path, res.framework.path] + extra
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    // MARK: stream parsing

    private func consume(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            self.buffer.append(data)
            while let newline = self.buffer.firstIndex(of: 0x0A) {
                let line = self.buffer[..<newline]
                self.buffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                self.handle(line: Data(line))
            }
        }
    }

    private func handle(line data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any] else { return }
        if !(object["diff"] as? Bool ?? false) { fields = [:] }
        for (key, value) in payload {
            if value is NSNull {
                fields.removeValue(forKey: key)
            } else {
                fields[key] = value
            }
        }
        emit()
    }

    private func emit() {
        let title = fields["title"] as? String ?? ""
        guard !title.isEmpty else {
            artwork = nil
            artworkOwner = ""
            DispatchQueue.main.async { [weak self] in self?.onUpdate?(nil) }
            return
        }

        let owner = identifier(fields["uniqueIdentifier"] ?? fields["contentItemIdentifier"])
        if owner != artworkOwner {
            artwork = nil
            artworkOwner = owner
        }
        if let raw = fields["artworkData"] as? String,
           let data = Data(base64Encoded: raw), !data.isEmpty,
           let image = NSImage(data: data) {
            artwork = image
        }

        let playing: Bool
        if let value = fields["playing"] as? Bool {
            playing = value
        } else {
            playing = ((fields["playbackRate"] as? NSNumber)?.doubleValue ?? 0) > 0
        }
        let snapshot = NowPlayingSnapshot(
            title: title,
            artist: fields["artist"] as? String ?? "",
            album: fields["album"] as? String ?? "",
            duration: number(fields["duration"]),
            elapsed: number(fields["elapsedTime"]),
            timestamp: (fields["timestamp"] as? String).flatMap { Self.iso.date(from: $0) } ?? Date(),
            playing: playing,
            bundleID: fields["bundleIdentifier"] as? String ?? "",
            parentBundleID: fields["parentApplicationBundleIdentifier"] as? String ?? "",
            artwork: artwork
        )
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(snapshot) }
    }

    private func identifier(_ value: Any?) -> String {
        guard let value else { return "" }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }

    private func number(_ value: Any?) -> TimeInterval {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return TimeInterval(string) ?? 0 }
        return 0
    }
}
