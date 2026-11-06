import SwiftUI

struct WeatherPanel: View {
    @ObservedObject var service = WeatherService.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Group {
            if let snap = service.snapshot {
                content(snap)
            } else if service.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(symbol: "cloud.sun",
                           title: "Weather unavailable",
                           detail: service.error ?? "Add a city in Settings.",
                           actionTitle: "Open Settings") {
                    NotchController.shared.open(tab: .settings, pin: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { service.refresh() }
    }

    private func content(_ snap: WeatherSnapshot) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                currentCard(snap)
                    .frame(width: 218)
                details(snap)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 98)

            forecast(snap)
                .frame(height: 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func currentCard(_ snap: WeatherSnapshot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: WeatherService.symbol(for: snap.now.code, isDay: snap.now.isDay))
                .font(.system(size: 34, weight: .regular))
                .symbolRenderingMode(.multicolor)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(Int(snap.now.temp.rounded()))°")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text)
                    Text(WeatherService.label(for: snap.now.code))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
                Text(snap.city)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                Text("Feels like \(Int(snap.now.feels.rounded()))°")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
            }

            Spacer(minLength: 0)

            Button {
                service.refresh(force: true)
            } label: {
                Image(systemName: service.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(service.isLoading ? 360 : 0))
                    .animation(service.isLoading
                               ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                               : .default,
                               value: service.isLoading)
            }
            .buttonStyle(PressableButtonStyle())
            .foregroundColor(Theme.textSecondary)
            .help("Refresh forecast")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [Theme.accent.opacity(0.16), Color.white.opacity(0.04)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private func details(_ snap: WeatherSnapshot) -> some View {
        VStack(spacing: 4) {
            detailRow(symbol: "humidity.fill", title: "Humidity", value: "\(snap.now.humidity)%")
            detailRow(symbol: "wind", title: "Wind", value: "\(Int(snap.now.wind.rounded())) km/h")
            if let today = snap.days.first {
                detailRow(symbol: "umbrella.fill", title: "Rain", value: "\(today.precip)%")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.05)))
    }

    private func detailRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.accent)
                .frame(width: 12)
            Text(title)
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func forecast(_ snap: WeatherSnapshot) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(snap.days.prefix(5).enumerated()), id: \.offset) { index, day in
                dayCell(day, isToday: index == 0)
            }
        }
    }

    private func dayCell(_ day: WeatherSnapshot.Day, isToday: Bool) -> some View {
        VStack(spacing: 3) {
            Text(isToday ? "Today" : dayName(day.date))
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundColor(isToday ? Theme.accent : Theme.textTertiary)
            Image(systemName: WeatherService.symbol(for: day.code))
                .font(.system(size: 15))
                .symbolRenderingMode(.multicolor)
                .frame(height: 18)
            HStack(spacing: 2) {
                Text("\(Int(day.high.rounded()))°")
                    .foregroundColor(Theme.text)
                Text("\(Int(day.low.rounded()))°")
                    .foregroundColor(Theme.textTertiary)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(isToday ? Theme.accent.opacity(0.10) : Color.white.opacity(0.03)))
    }

    private func dayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date)
    }
}
