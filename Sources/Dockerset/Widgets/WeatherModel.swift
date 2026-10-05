import SwiftUI

/// Weather from Open-Meteo (free, no API key).
@MainActor
final class WeatherModel: ObservableObject {
    static let shared = WeatherModel()

    struct Day: Identifiable, Equatable {
        let id: String
        let date: Date
        let code: Int
        let high: Double
        let low: Double
    }

    struct Place: Decodable, Identifiable {
        let id: Int
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?

        var displayName: String { [name, admin1, country].compactMap { $0 }.joined(separator: ", ") }
    }

    @Published private(set) var temperature: Double?
    @Published private(set) var code: Int?
    @Published private(set) var days: [Day] = []
    @Published private(set) var error: String?
    /// City shown in the widget: the located city, or the one picked in Settings.
    @Published private(set) var placeName: String?

    private var lastFetch: (settings: WeatherSettings, date: Date)?
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh(AppState.shared.config.widgets.weather, force: true) }
            }
        }
    }

    func refresh(_ settings: WeatherSettings, force: Bool = false) async {
        // Several widgets may ask at once; reuse a fetch made for the same settings in the last minute.
        if !force, let last = lastFetch, last.settings == settings, Date().timeIntervalSince(last.date) < 60 { return }
        lastFetch = (settings, Date())

        var latitude = settings.latitude
        var longitude = settings.longitude
        var name = settings.city
        if settings.useCurrentLocation, let place = await LocationProvider.shared.currentPlace() {
            latitude = place.latitude
            longitude = place.longitude
            name = place.name
        }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            .init(name: "temperature_unit", value: settings.fahrenheit ? "fahrenheit" : "celsius"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: String(min(16, max(1, settings.forecastDays)))),
        ]
        struct Response: Decodable {
            struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
            struct Daily: Decodable {
                let time: [String]
                let weather_code: [Int]
                let temperature_2m_max: [Double]
                let temperature_2m_min: [Double]
            }
            let current: Current
            let daily: Daily
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            let r = try JSONDecoder().decode(Response.self, from: data)
            let parser = DateFormatter()
            parser.dateFormat = "yyyy-MM-dd"
            placeName = name
            temperature = r.current.temperature_2m
            code = r.current.weather_code
            days = r.daily.time.indices.map { i in
                Day(id: r.daily.time[i], date: parser.date(from: r.daily.time[i]) ?? Date(), code: r.daily.weather_code[i],
                    high: r.daily.temperature_2m_max[i], low: r.daily.temperature_2m_min[i])
            }
            error = nil
        } catch {
            self.error = "Weather unavailable"
            lastFetch = nil
        }
    }

    static func search(_ name: String) async throws -> [Place] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [.init(name: "name", value: name), .init(name: "count", value: "8")]
        struct Response: Decodable { let results: [Place]? }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(Response.self, from: data).results ?? []
    }

    /// WMO weather interpretation code → SF Symbol.
    static func symbol(_ code: Int) -> String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func gradient(_ code: Int) -> LinearGradient {
        let colors: [Color] = switch code {
        case 0, 1: [Color(red: 0.25, green: 0.55, blue: 0.95), Color(red: 0.12, green: 0.38, blue: 0.82)]
        case 2, 3, 45, 48: [Color(red: 0.45, green: 0.52, blue: 0.62), Color(red: 0.30, green: 0.36, blue: 0.46)]
        case 71...77, 85, 86: [Color(red: 0.55, green: 0.65, blue: 0.80), Color(red: 0.38, green: 0.47, blue: 0.62)]
        default: [Color(red: 0.25, green: 0.33, blue: 0.48), Color(red: 0.14, green: 0.19, blue: 0.30)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}
