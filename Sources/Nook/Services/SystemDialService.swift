import AppKit
import Combine
import CoreGraphics
import Foundation
import Darwin

/// Watches system volume + display brightness so the notch can show a HUD,
/// and exposes them as sliders in the media panel.
final class SystemDialService: ObservableObject {
    static let shared = SystemDialService()

    @Published var volume: Double = 50
    @Published var muted = false
    @Published var brightness: Double = 0.6
    @Published var hasDisplayControls = false

    private var timer: Timer?
    private var script: NSAppleScript?
    private var lastVolume = -1.0
    private var lastBrightness = -1.0
    private var suppressUntil = Date.distantPast

    private init() {}

    func start() {
        script = NSAppleScript(source: """
        set v to output volume of (get volume settings)
        set m to output muted of (get volume settings)
        return (v as text) & "," & (m as text)
        """)
        hasDisplayControls = BrightnessBridge.isAvailable
        if hasDisplayControls, let value = BrightnessBridge.readMainDisplay() {
            brightness = value
            lastBrightness = value * 100
        }
        // Seed the first volume sample so launching doesn't flash a HUD.
        if let value = readVolume() {
            volume = value
            lastVolume = value
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    private func tick() {
        guard AppSettings.shared.showSystemHUD else { return }
        if let value = readVolume(), abs(value - lastVolume) >= 1 {
            lastVolume = value
            volume = value
            if Date() > suppressUntil {
                NotchController.shared.show(hud: HUDMessage(symbol: value <= 0 ? "speaker.slash" : "speaker.wave.2",
                                                           title: "Volume", detail: "\(Int(value))%",
                                                           progress: value / 100))
            }
        }
        if hasDisplayControls, let value = BrightnessBridge.readMainDisplay() {
            if abs(value * 100 - lastBrightness) > 1 {
                lastBrightness = value * 100
                brightness = value
                if Date() > suppressUntil {
                    NotchController.shared.show(hud: HUDMessage(symbol: "sun.max", title: "Brightness",
                                                               detail: "\(Int(value * 100))%", progress: value))
                }
            }
        }
    }

    private func readVolume() -> Double? {
        var error: NSDictionary?
        guard let out = script?.executeAndReturnError(&error), error == nil else { return nil }
        let raw = out.stringValue ?? ""
        let parts = raw.components(separatedBy: ",")
        muted = parts.count > 1 ? parts[1].contains("true") : false
        return Double(parts[0])
    }

    func setVolume(_ value: Double) {
        volume = value
        suppressUntil = Date().addingTimeInterval(1.2)
        let source = "set volume output volume \(Int(value)) output muted \(value <= 0)"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        lastVolume = value
    }

    func toggleMute() {
        setVolume(muted ? max(10, volume) : 0)
    }

    func setBrightness(_ value: Double) {
        brightness = value
        suppressUntil = Date().addingTimeInterval(1.2)
        BrightnessBridge.writeAllDisplays(Float(value))
        lastBrightness = value * 100
    }
}

/// Reaches the private DisplayServices functions through dlopen so brightness
/// control works without linking unavailable IOKit headers.
enum BrightnessBridge {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> kern_return_t
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> kern_return_t

    private static let handle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/Frameworks/IOKit.framework/Versions/Current/IOKit", RTLD_NOW)
    }()

    static var isAvailable: Bool {
        handle != nil && dlsym(handle, "DisplayServicesGetBrightness") != nil
    }

    static func readMainDisplay() -> Double? {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        let fn = unsafeBitCast(symbol, to: GetFn.self)
        guard let main = CGDisplayMainValue() else { return nil }
        var value: Float = 0
        guard fn(main, &value) == 0 else { return nil }
        return Double(max(0, min(1, value)))
    }

    static func writeAllDisplays(_ value: Float) {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return }
        let fn = unsafeBitCast(symbol, to: SetFn.self)
        var count: UInt32 = 0
        _ = CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        _ = CGGetActiveDisplayList(count, &ids, &count)
        for id in ids { _ = fn(id, value) }
    }
}

private func CGDisplayMainValue() -> CGDirectDisplayID? {
    let id = CGMainDisplayID()
    return id == 0 ? nil : id
}
