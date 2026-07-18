import Foundation

/// Fetches current weather + UV from the free Open-Meteo API (no key required).
enum WeatherService {

    enum ServiceError: Error, LocalizedError {
        case badURL
        case badResponse

        var errorDescription: String? {
            switch self {
            case .badURL: return "Could not build the request URL."
            case .badResponse: return "The weather service returned an unexpected response."
            }
        }
    }

    // MARK: - Response models (match Open-Meteo JSON exactly)

    private struct ForecastResponse: Decodable {
        let current: Current
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let uv_index: Double?
        }
    }

    private struct GeocodingResponse: Decodable {
        let results: [Result]?
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }
    }

    // MARK: - Public API

    /// Fetch current conditions for a coordinate. `unit` is "celsius" or "fahrenheit".
    static func fetch(latitude: Double,
                      longitude: Double,
                      placeName: String,
                      unit: String = "celsius") async throws -> WeatherData {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,uv_index"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: unit)
        ]
        guard let url = components?.url else { throw ServiceError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.badResponse
        }

        let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)
        return WeatherData(
            temperatureC: decoded.current.temperature_2m,
            uvIndex: decoded.current.uv_index ?? 0,
            weatherCode: decoded.current.weather_code,
            placeName: placeName,
            date: Date()
        )
    }

    /// A simplified geocoding hit used by the in-app city search.
    struct Place: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let latitude: Double
        let longitude: Double
        let subtitle: String

        var displayName: String { name }
    }

    /// Search cities by name via Open-Meteo's geocoding endpoint.
    static func searchCities(_ query: String) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { throw ServiceError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.badResponse
        }

        let decoded = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        return (decoded.results ?? []).map { result in
            let parts = [result.admin1, result.country].compactMap { $0 }
            return Place(
                name: result.name,
                latitude: result.latitude,
                longitude: result.longitude,
                subtitle: parts.joined(separator: ", ")
            )
        }
    }
}
