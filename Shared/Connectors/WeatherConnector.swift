import Foundation

/// A forecast location. Coordinates are rounded to about 1 km; the forecast
/// grid is coarser than that, so no precision is lost.
struct WeatherLocation: Codable, Hashable, Identifiable {
    let name: String
    let detail: String?
    let latitude: Double
    let longitude: Double
    let isCurrentLocation: Bool

    var id: String { "\(latitude),\(longitude),\(name)" }

    init(name: String, detail: String? = nil, latitude: Double, longitude: Double, isCurrentLocation: Bool) {
        self.name = name
        self.detail = detail
        self.latitude = (latitude * 100).rounded() / 100
        self.longitude = (longitude * 100).rounded() / 100
        self.isCurrentLocation = isCurrentLocation
    }
}

enum WeatherLocationStore {
    private static let locationKey = "weather.location"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: DashboardStore.appGroupID) ?? .standard
    }

    /// Nil until a city is chosen or the device location is first found.
    static var location: WeatherLocation? {
        guard let data = defaults.data(forKey: locationKey) else { return nil }
        return try? JSONDecoder().decode(WeatherLocation.self, from: data)
    }

    static func save(_ location: WeatherLocation) {
        defaults.set(try? JSONEncoder().encode(location), forKey: locationKey)
    }

    static func clear() {
        defaults.removeObject(forKey: locationKey)
    }
}

struct DeviceCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
}

/// Finds the device location. Only the app provides one; widgets reuse the
/// last stored coordinate.
@MainActor
protocol DeviceLocating {
    func currentCoordinate() async throws -> DeviceCoordinate
}

final class WeatherConnector: DashboardConnector {
    let source: DataSource = .weather

    private let client: OpenMeteoClient
    private let locator: (any DeviceLocating)?

    init(client: OpenMeteoClient = OpenMeteoClient(), locator: (any DeviceLocating)? = nil) {
        self.client = client
        self.locator = locator
    }

    func authorize() async throws {
        if let location = WeatherLocationStore.location, !location.isCurrentLocation { return }
        try await updateCurrentLocation()
    }

    func refresh() async throws -> [DashboardMetric] {
        if locator != nil, WeatherLocationStore.location?.isCurrentLocation ?? true {
            do {
                try await updateCurrentLocation()
            } catch {
                // Keep forecasting for the last known coordinate when a new fix fails.
                if WeatherLocationStore.location == nil { throw error }
            }
        }
        guard let location = WeatherLocationStore.location else {
            throw ConnectorError.unavailable("Choose a weather location in Sources.")
        }
        let forecast = try await client.forecast(latitude: location.latitude, longitude: location.longitude)
        return WeatherSnapshotBuilder.metrics(from: forecast, now: .now)
    }

    func disconnect() async -> DisconnectResult {
        WeatherLocationStore.clear()
        return .localOnly
    }

    private func updateCurrentLocation() async throws {
        guard let locator else {
            throw ConnectorError.unavailable("Open the app to find your location, or choose a city.")
        }
        let coordinate = try await locator.currentCoordinate()
        WeatherLocationStore.save(WeatherLocation(
            name: "Current location",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            isCurrentLocation: true
        ))
    }
}

/// Free Open-Meteo forecast and geocoding APIs. No account or key is needed;
/// requests contain only the rounded coordinate or the search text.
struct OpenMeteoClient {
    var session: URLSession = .shared

    func forecast(latitude: Double, longitude: Double) async throws -> OpenMeteoForecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,uv_index,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,uv_index,precipitation_probability"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,uv_index_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "2")
        ]
        guard let url = components?.url else { throw ConnectorError.unavailable("The weather request is invalid.") }
        let data = try await get(url)
        return try JSONDecoder().decode(OpenMeteoForecast.self, from: data)
    }

    func searchPlaces(_ query: String) async throws -> [WeatherLocation] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { return [] }
        let data = try await get(url)
        let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        return (response.results ?? []).map { place in
            let detail = [place.admin1, place.country].compactMap { $0 }.joined(separator: ", ")
            return WeatherLocation(
                name: place.name,
                detail: detail.isEmpty ? nil : detail,
                latitude: place.latitude,
                longitude: place.longitude,
                isCurrentLocation: false
            )
        }
    }

    private func get(_ url: URL) async throws -> Data {
        let request = URLRequest(url: url, timeoutInterval: 15)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ConnectorError.unavailable("The weather service is unavailable. Try again later.")
        }
        return data
    }

    private struct GeocodingResponse: Decodable {
        struct Place: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }
        let results: [Place]?
    }
}

/// The subset of an Open-Meteo forecast response used for the weather tiles,
/// requested with `timeformat=unixtime`.
struct OpenMeteoForecast: Decodable {
    struct Current: Decodable {
        let time: TimeInterval
        let temperature: Double?
        let weatherCode: Double?
        let uvIndex: Double?
        let isDay: Double?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case uvIndex = "uv_index"
            case isDay = "is_day"
        }
    }

    struct Hourly: Decodable {
        let time: [TimeInterval]
        let temperature: [Double?]?
        let uvIndex: [Double?]?
        let precipitationProbability: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case uvIndex = "uv_index"
            case precipitationProbability = "precipitation_probability"
        }
    }

    struct Daily: Decodable {
        let time: [TimeInterval]
        let weatherCode: [Double?]?
        let temperatureMax: [Double?]?
        let temperatureMin: [Double?]?
        let precipitationSum: [Double?]?
        let precipitationProbabilityMax: [Double?]?
        let uvIndexMax: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case precipitationSum = "precipitation_sum"
            case precipitationProbabilityMax = "precipitation_probability_max"
            case uvIndexMax = "uv_index_max"
        }
    }

    let current: Current
    let hourly: Hourly?
    let daily: Daily
}

enum WeatherSnapshotBuilder {
    static func metrics(from forecast: OpenMeteoForecast, now: Date) -> [DashboardMetric] {
        let current = forecast.current
        let daily = forecast.daily
        let observedAt = Date(timeIntervalSince1970: current.time)
        let todayStart = daily.time.first.map { Date(timeIntervalSince1970: $0) } ?? now
        let tomorrowStart = daily.time.count > 1
            ? Date(timeIntervalSince1970: daily.time[1])
            : todayStart.addingTimeInterval(24 * 60 * 60)
        let tomorrowEnd = tomorrowStart.addingTimeInterval(24 * 60 * 60)
        let hours = forecast.hourly.map { hourly in
            hourly.time.enumerated().map { index, time in
                Hour(
                    start: Date(timeIntervalSince1970: time),
                    temperature: element(hourly.temperature, index),
                    uvIndex: element(hourly.uvIndex, index),
                    precipitationProbability: element(hourly.precipitationProbability, index)
                )
            }
        } ?? []
        let today = hours.filter { $0.start >= todayStart && $0.start < tomorrowStart }
        // An hour that has started is still upcoming until it ends.
        let upcomingToday = today.filter { $0.start.addingTimeInterval(60 * 60) > now }

        var metrics: [DashboardMetric] = []

        let todayCode = (current.weatherCode ?? element(daily.weatherCode, 0)).map { Int($0) } ?? -1
        if let temperature = current.temperature {
            metrics.append(DashboardMetric(
                id: "temperature",
                source: .weather,
                title: "Now",
                value: WeatherFormat.temperature(temperature),
                detail: joined([WeatherCode.text(for: todayCode), highLow(element(daily.temperatureMax, 0), element(daily.temperatureMin, 0))]),
                symbol: WeatherCode.symbol(for: todayCode, isDay: (current.isDay ?? 1) >= 1),
                tint: "orange",
                numericValue: temperature,
                observedAt: observedAt
            ))
        }

        if let uv = current.uvIndex {
            let level = UVLevel(index: uv)
            let peak = upcomingToday.filter { $0.uvIndex != nil }.max { ($0.uvIndex ?? 0) < ($1.uvIndex ?? 0) }
            let todayMax = element(daily.uvIndexMax, 0) ?? today.compactMap(\.uvIndex).max()
            let detail: String
            if let peak, let peakValue = peak.uvIndex, peakValue >= 0.5, peakValue.rounded() > uv.rounded() {
                detail = "\(level.label) · peak \(Int(peakValue.rounded())) at \(peak.start.formatted(date: .omitted, time: .shortened))"
            } else if uv < 0.5, let tomorrowMax = element(daily.uvIndexMax, 1) {
                detail = "\(level.label) · tomorrow \(Int(tomorrowMax.rounded()))"
            } else if let todayMax {
                detail = "\(level.label) · max \(Int(todayMax.rounded())) today"
            } else {
                detail = level.label
            }
            metrics.append(DashboardMetric(
                id: "uv",
                source: .weather,
                title: "UV index",
                value: "\(Int(uv.rounded()))",
                detail: detail,
                symbol: "sun.max.fill",
                tint: level.tint,
                numericValue: uv,
                targetValue: 11,
                observedAt: observedAt
            ))
        }

        let rain = element(daily.precipitationSum, 0)
        let rainChance = element(daily.precipitationProbabilityMax, 0)
        if rain != nil || rainChance != nil {
            let amount = rain ?? 0
            let detail: String
            if amount < 0.1 && (rainChance ?? 0) < 20 {
                detail = "Dry today"
            } else {
                let likely = upcomingToday
                    .filter { ($0.precipitationProbability ?? 0) >= 30 }
                    .max { ($0.precipitationProbability ?? 0) < ($1.precipitationProbability ?? 0) }
                detail = joined([
                    rainChance.map { "\(Int($0.rounded()))%" },
                    likely.map { "most likely \($0.start.formatted(date: .omitted, time: .shortened))" }
                ])
            }
            metrics.append(DashboardMetric(
                id: "rain",
                source: .weather,
                title: "Rain today",
                value: WeatherFormat.precipitation(amount),
                detail: detail,
                symbol: "drop.fill",
                tint: "blue",
                numericValue: amount,
                observedAt: observedAt
            ))
        }

        let tomorrowTemperatures = hours
            .filter { $0.start >= tomorrowStart && $0.start < tomorrowEnd }
            .compactMap(\.temperature)
        let tomorrowHigh = element(daily.temperatureMax, 1)
        let tomorrowLow = element(daily.temperatureMin, 1)
        let tomorrowAverage = tomorrowTemperatures.isEmpty
            ? tomorrowHigh.flatMap { high in tomorrowLow.map { (high + $0) / 2 } }
            : tomorrowTemperatures.reduce(0, +) / Double(tomorrowTemperatures.count)
        if let tomorrowAverage {
            let code = element(daily.weatherCode, 1).map { Int($0) } ?? -1
            let tomorrowRain = element(daily.precipitationSum, 1).flatMap { $0 >= 0.1 ? WeatherFormat.precipitation($0) : nil }
            metrics.append(DashboardMetric(
                id: "tomorrow",
                source: .weather,
                title: "Tomorrow",
                value: WeatherFormat.temperature(tomorrowAverage),
                detail: joined([WeatherCode.text(for: code), highLow(tomorrowHigh, tomorrowLow), tomorrowRain]),
                symbol: WeatherCode.symbol(for: code),
                tint: "teal",
                numericValue: tomorrowAverage,
                observedAt: observedAt
            ))
        }

        return metrics
    }

    private struct Hour {
        let start: Date
        let temperature: Double?
        let uvIndex: Double?
        let precipitationProbability: Double?
    }

    private static func element(_ values: [Double?]?, _ index: Int) -> Double? {
        guard let values, values.indices.contains(index) else { return nil }
        return values[index]
    }

    private static func highLow(_ high: Double?, _ low: Double?) -> String? {
        guard let high, let low else { return nil }
        return "\(WeatherFormat.temperature(high)) / \(WeatherFormat.temperature(low))"
    }

    private static func joined(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty && $0 != "Unknown" }.joined(separator: " · ")
    }
}
