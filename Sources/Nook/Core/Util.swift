import AppKit
import SwiftUI

enum Util {
    static let appSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Nook", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    @discardableResult
    static func shell(_ launchPath: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func hoursMinutes(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded())
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }

    static func bytes(_ count: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB, .useKB]
        return f.string(fromByteCount: count)
    }

    static func rounded(_ v: Double, _ places: Int = 1) -> Double {
        let m = pow(10.0, Double(places))
        return (v * m).rounded() / m
    }

    static func color(hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        }
        return Color(red: r, green: g, blue: b)
    }

    static func hexString(_ c: NSColor) -> String {
        guard let rgb = c.usingColorSpace(.sRGB) else { return "#FF7A1A" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func nsColor(_ hex: String) -> NSColor {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 8 {
            return NSColor(srgbRed: CGFloat((v >> 24) & 0xFF) / 255,
                           green: CGFloat((v >> 16) & 0xFF) / 255,
                           blue: CGFloat((v >> 8) & 0xFF) / 255,
                           alpha: CGFloat((v & 0xFF)) / 255)
        }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static func fileIcon(_ url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

extension Notification.Name {
    static let nookHotkeyToggled = Notification.Name("nook.hotkey.toggled")
    static let nookHUD = Notification.Name("nook.hud")
}

/// Detects the offscreen render modes used for visual checks.
enum RunMode {
    static var isRendering: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("--render=") || $0.hasPrefix("--snapshot=") || $0.hasPrefix("--snapshot-mini=") }
    }

    /// Populates preview data (a now-playing track, demo calendar events) so
    /// screenshots and docs never show permission prompts or the user's data.
    static var isDemo: Bool {
        CommandLine.arguments.contains("--demo")
    }
}

struct HUDMessage: Equatable {
    var symbol: String
    var title: String
    var detail: String?
    var progress: Double?
}

final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published var message: String?

    func show(_ text: String) {
        message = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.message == text { self?.message = nil }
        }
    }
}
