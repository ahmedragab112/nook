import Combine
import SwiftUI

struct StatsPanel: View {
    @ObservedObject var stats = StatsService.shared
    private var poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 8) {
                meter("CPU", symbol: "cpu", value: stats.snapshot.cpu / 100,
                      detail: "\(Int(stats.snapshot.cpu))% · \(stats.snapshot.cores) cores")
                meter("Memory", symbol: "memorychip", value: stats.snapshot.memoryTotal > 0 ? stats.snapshot.memoryUsed / stats.snapshot.memoryTotal : 0,
                      detail: String(format: "%.1f of %.0f GB", stats.snapshot.memoryUsed, stats.snapshot.memoryTotal))
                meter("Storage", symbol: "internaldrive", value: stats.snapshot.diskTotal > 0 ? stats.snapshot.diskUsed / stats.snapshot.diskTotal : 0,
                      detail: "\(Util.bytes(Int64(stats.snapshot.diskUsed))) of \(Util.bytes(Int64(stats.snapshot.diskTotal)))")
                if let battery = stats.snapshot.batteryPercent {
                    meter("Battery", symbol: battery < 20 ? "battery.25" : "battery.100",
                          value: Double(battery) / 100,
                          detail: "\(battery)%\(stats.snapshot.charging ? " · charging" : "")",
                          color: battery < 20 ? .red : Theme.accent)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 7) {
                row("Download", "\(Util.rounded(stats.snapshot.netDown, 2)) MB/s", "arrow.down.circle")
                row("Upload", "\(Util.rounded(stats.snapshot.netUp, 2)) MB/s", "arrow.up.circle")
                row("Load", String(format: "%.2f · %.2f · %.2f", stats.snapshot.load1,
                                   stats.snapshot.load2, stats.snapshot.load3), "waveform.path.ecg")
                row("Uptime", Util.hoursMinutes(stats.snapshot.uptime), "clock.arrow.circlepath")
                row("Displays", "\(NSScreen.screens.count)", "display")
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ActivityMonitor-Settings.extension")!)
                } label: {
                    Text("Open Activity Monitor").font(.system(size: 10))
                }
                .buttonStyle(PressableButtonStyle())
                .foregroundColor(Theme.textTertiary)
            }
            .frame(width: 180, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(poll) { _ in stats.sample() }
        .onAppear { stats.sample() }
    }

    private func meter(_ title: String, symbol: String, value: Double, detail: String, color: Color? = nil) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundColor(color ?? Theme.accent)
                Text(title).font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundColor(Theme.text)
                Spacer()
                Text(detail).font(.system(size: 9, design: .monospaced)).foregroundColor(Theme.textTertiary)
            }
            MeterBar(fraction: value, color: color ?? Theme.accent, height: 5)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    private func row(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9)).foregroundColor(Theme.textTertiary)
            Text(title).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(Theme.text)
        }
    }
}
