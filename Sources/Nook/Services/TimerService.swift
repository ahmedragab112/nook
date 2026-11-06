import AppKit
import Combine
import Foundation

final class TimerService: ObservableObject {
    static let shared = TimerService()

    enum Mode { case idle, countdown, stopwatch }

    @Published var mode: Mode = .idle
    @Published var running = false
    @Published var total: TimeInterval = 0
    @Published var remaining: TimeInterval = 0
    @Published var elapsed: TimeInterval = 0
    @Published var laps: [TimeInterval] = []

    private var ticker: Timer?
    private var stamp = Date()
    private var sound: NSSound?

    private init() {}

    // MARK: countdown

    func startCountdown(_ seconds: TimeInterval) {
        stopTicker()
        mode = .countdown
        total = seconds
        remaining = seconds
        running = true
        stamp = Date()
        startTicker()
        publishActivity()
    }

    func addMinutes(_ minutes: Int) {
        guard mode == .countdown else { return }
        total += TimeInterval(minutes * 60)
        remaining += TimeInterval(minutes * 60)
        publishActivity()
    }

    func togglePause() {
        guard mode != .idle else { return }
        running.toggle()
        if running { stamp = Date(); startTicker() } else { stopTicker() }
        publishActivity()
    }

    func reset() {
        stopTicker()
        mode = .idle
        running = false
        total = 0
        remaining = 0
        elapsed = 0
        laps = []
        NotchController.shared.clearActivity(.timer)
    }

    // MARK: stopwatch

    func startStopwatch() {
        stopTicker()
        mode = .stopwatch
        running = true
        elapsed = 0
        laps = []
        stamp = Date()
        startTicker()
        publishActivity()
    }

    func lap() {
        guard mode == .stopwatch, running else { return }
        laps.append(currentElapsed)
        ToastCenter.shared.show("Lap \(laps.count)")
    }

    private var currentElapsed: TimeInterval {
        elapsed + (running ? Date().timeIntervalSince(stamp) : 0)
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        switch mode {
        case .idle:
            stopTicker()
        case .stopwatch:
            elapsed = currentElapsed
            stamp = Date()
            publishActivity()
        case .countdown:
            remaining -= 0.2
            if remaining <= 0 {
                remaining = 0
                finish()
                return
            }
            publishActivity()
        }
    }

    private func finish() {
        stopTicker()
        running = false
        if let preset = NSSound(named: "Glass") {
            preset.play()
        } else {
            NSSound.beep()
        }
        NotchController.shared.show(hud: HUDMessage(symbol: "bell.badge", title: "Timer finished",
                                                    detail: Util.clock(total), progress: nil))
        NotchController.shared.open(tab: .timer, pin: true)
        NotchController.shared.clearActivity(.timer)
    }

    private func publishActivity() {
        guard AppSettings.shared.compactContent != .none else { return }
        switch mode {
        case .idle:
            NotchController.shared.clearActivity(.timer)
        case .countdown:
            NotchController.shared.setActivity(.init(kind: .timer, symbol: "timer",
                                                     text: "Timer",
                                                     detail: Util.clock(remaining),
                                                     progress: total > 0 ? 1 - remaining / total : nil))
        case .stopwatch:
            NotchController.shared.setActivity(.init(kind: .timer, symbol: "stopwatch",
                                                     text: "Stopwatch",
                                                     detail: Util.clock(elapsed), progress: nil))
        }
    }
}
