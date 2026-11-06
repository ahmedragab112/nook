import Foundation

struct WeatherSnapshot: Codable, Equatable {
    struct Now: Codable, Equatable {
        var temp: Double
        var feels: Double
        var humidity: Int
        var wind: Double
        var code: Int
        var isDay: Bool
    }

    struct Day: Codable, Equatable {
        var date: Date
        var code: Int
        var high: Double
        var low: Double
        var precip: Int
    }

    var city: String
    var now: Now
    var days: [Day]
    var updated: Date
}

/// Open-Meteo forecast, geocoded by city name. No API key, no account.
@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private var timer: Timer?
    private var coords: [String: (lat: Double, lon: Double, label: String)] = [:]
    private var fetching = false
    private let cacheURL = Util.appSupport.appendingPathComponent("weather.json")

    private init() {}

    func start() {
        loadCache()
        refresh(force: true)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }
    }

    func refresh(force: Bool = false) {
        guard !fetching else { return }
        if !force, let snap = snapshot, snap.city == AppSettings.shared.weatherCity,
           Date().timeIntervalSince(snap.updated) < 600 { return }
        fetching = true
        Task { await fetch() }
    }

    private func fetch() async {
        defer { fetching = false }
        let city = AppSettings.shared.weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else {
            error = "Add a city in Settings."
            return
        }
        isLoading = true
        error = nil
        do {
            let place = try await place(for: city)
            var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            comps.queryItems = [
                .init(name: "latitude", value: String(place.lat)),
                .init(name: "longitude", value: String(place.lon)),
                .init(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"),
                .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
                .init(name: "timezone", value: "auto"),
                .init(name: "forecast_days", value: "6")
            ]
            let (data, response) = try await URLSession.shared.data(from: comps.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw WeatherError.badResponse
            }
            let decoded = try JSONDecoder().decode(Forecast.self, from: data)
            let now = decoded.current
            let days = zip(decoded.daily.time.indices, decoded.daily.time).compactMap { idx, day -> WeatherSnapshot.Day? in
                guard let date = Self.dayFormatter.date(from: day) else { return nil }
                let high = idx < decoded.daily.max.count ? decoded.daily.max[idx] : now.temperature2m
                let low = idx < decoded.daily.min.count ? decoded.daily.min[idx] : now.temperature2m
                let code = idx < decoded.daily.code.count ? decoded.daily.code[idx] : now.weatherCode
                let precip = idx < decoded.daily.precip.count ? (decoded.daily.precip[idx] ?? 0) : 0
                return .init(date: date, code: code, high: high, low: low, precip: precip)
            }
            let snap = WeatherSnapshot(city: place.label,
                                       now: .init(temp: now.temperature2m,
                                                  feels: now.apparentTemperature,
                                                  humidity: now.relativeHumidity2m,
                                                  wind: now.windSpeed10m,
                                                  code: now.weatherCode,
                                                  isDay: now.isDay == 1),
                                       days: days,
                                       updated: Date())
            snapshot = snap
            saveCache(snap)
        } catch {
            self.error = "Couldn't load the forecast."
        }
        isLoading = false
    }

    private func place(for city: String) async throws -> (lat: Double, lon: Double, label: String) {
        if let hit = coords[city] { return hit }
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            .init(name: "name", value: city),
            .init(name: "count", value: "1"),
            .init(name: "language", value: "en"),
            .init(name: "format", value: "json")
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let geo = try JSONDecoder().decode(Geocode.self, from: data)
        guard let first = geo.results?.first else { throw WeatherError.unknownCity }
        let label = [first.name, first.country].compactMap { $0 }.joined(separator: ", ")
        let hit = (lat: first.latitude, lon: first.longitude, label: label)
        coords[city] = hit
        return hit
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let snap = try? JSONDecoder().decode(WeatherSnapshot.self, from: data) else { return }
        snapshot = snap
    }

    private func saveCache(_ snap: WeatherSnapshot) {
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    // MARK: - presentation helpers

    static func symbol(for code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func label(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67: return "Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Storm with hail"
        default: return "Cloudy"
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    // MARK: - wire types

    private enum WeatherError: Error {
        case unknownCity
        case badResponse
    }

    private struct Geocode: Decodable {
        struct Result: Decodable {
            let name: String
            let country: String?
            let latitude: Double
            let longitude: Double
        }
        let results: [Result]?
    }

    private struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature2m: Double
            let relativeHumidity2m: Int
            let apparentTemperature: Double
            let isDay: Int
            let weatherCode: Int
            let windSpeed10m: Double

            enum CodingKeys: String, CodingKey {
                case temperature2m = "temperature_2m"
                case relativeHumidity2m = "relative_humidity_2m"
                case apparentTemperature = "apparent_temperature"
                case isDay = "is_day"
                case weatherCode = "weather_code"
                case windSpeed10m = "wind_speed_10m"
            }
        }
        struct Daily: Decodable {
            let time: [String]
            let code: [Int]
            let max: [Double]
            let min: [Double]
            let precip: [Int?]

            enum CodingKeys: String, CodingKey {
                case time
                case code = "weather_code"
                case max = "temperature_2m_max"
                case min = "temperature_2m_min"
                case precip = "precipitation_probability_max"
            }
        }
        let current: Current
        let daily: Daily
    }
}
