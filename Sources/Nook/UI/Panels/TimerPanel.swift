import Combine
import SwiftUI

struct TimerPanel: View {
    @ObservedObject var timer = TimerService.shared
    @State private var modeChoice: Choice = .countdown
    private var tick = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    enum Choice: String, CaseIterable { case countdown = "Timer", stopwatch = "Stopwatch" }

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $modeChoice) {
                ForEach(Choice.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .tint(Theme.accent)
            .frame(width: 200)

            if modeChoice == .countdown { countdown } else { stopwatch }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(tick) { _ in }
    }

    private var countdown: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: timer.total > 0 ? CGFloat(1 - timer.remaining / timer.total) : 0)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(Util.clock(timer.mode == .countdown ? timer.remaining : 300))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.text)
                            .monospacedDigit()
                        Text(timer.running ? "running" : "ready")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.textTertiary)
                            .textCase(.uppercase)
                    }
                }
                .frame(width: 84, height: 84)
            }

            VStack(alignment: .leading, spacing: 6) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 5)], spacing: 5) {
                    ForEach([1, 3, 5, 10, 25, 45], id: \.self) { minutes in
                        Button {
                            timer.startCountdown(TimeInterval(minutes * 60))
                        } label: {
                            Text("\(minutes)m")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .foregroundColor(timer.total == TimeInterval(minutes * 60) ? Theme.accent : Theme.textSecondary)
                    }
                }
                HStack(spacing: 6) {
                    Button {
                        timer.togglePause()
                    } label: {
                        icon(timer.running ? "pause.fill" : "play.fill", timer.mode == .countdown ? "Pause" : "Start")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                    Button { timer.addMinutes(1) } label: { Text("+1m") }
                        .buttonStyle(PressableButtonStyle())
                        .foregroundColor(Theme.textSecondary)
                        .disabled(timer.mode != .countdown)
                    Button { timer.reset() } label: { icon("arrow.counterclockwise", "Reset") }
                        .buttonStyle(PressableButtonStyle())
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer()
        }
    }

    private var stopwatch: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Util.clock(timer.elapsed))
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.text)
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Button {
                        if timer.mode == .stopwatch { timer.togglePause() } else { timer.startStopwatch() }
                    } label: {
                        icon(timer.mode == .stopwatch && timer.running ? "pause.fill" : "play.fill",
                             timer.mode == .stopwatch && timer.running ? "Pause" : "Start")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)

                    Button { timer.lap() } label: { icon("flag", "Lap") }
                        .buttonStyle(PressableButtonStyle())
                        .foregroundColor(Theme.textSecondary)
                        .disabled(timer.mode != .stopwatch)
                    Button { timer.reset() } label: { icon("arrow.counterclockwise", "Reset") }
                        .buttonStyle(PressableButtonStyle())
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer()
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(Array(timer.laps.enumerated()), id: \.offset) { index, lap in
                        HStack {
                            Text("Lap \(index + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text(Util.clock(lap))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.text)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                    }
                }
            }
            .frame(width: 140)
        }
    }

    private func icon(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(title).font(.system(size: 10, weight: .semibold))
        }
    }
}
