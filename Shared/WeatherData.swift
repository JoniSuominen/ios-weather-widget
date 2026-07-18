import Foundation

/// A snapshot of current conditions used by both the app and the widgets.
struct WeatherData: Codable, Equatable {
    var temperatureC: Double
    var uvIndex: Double
    var weatherCode: Int
    /// Human-readable place the reading is for (e.g. "Helsinki").
    var placeName: String
    /// When the reading was produced.
    var date: Date

    /// Temperature rounded to a whole number for compact display.
    var temperatureRounded: Int { Int(temperatureC.rounded()) }

    /// UV index rounded to a whole number for compact display.
    var uvRounded: Int { Int(uvIndex.rounded()) }

    /// SF Symbol name for the current WMO weather code.
    var symbolName: String { WeatherCode(rawValue: weatherCode).symbolName }

    /// Short textual description of the sky condition.
    var conditionText: String { WeatherCode(rawValue: weatherCode).text }
}

extension WeatherData {
    /// Placeholder shown in widget galleries and before the first fetch.
    static let placeholder = WeatherData(
        temperatureC: 21,
        uvIndex: 4,
        weatherCode: 1,
        placeName: "—",
        date: Date()
    )
}

/// WMO weather interpretation codes mapped to SF Symbols and short text.
/// Reference: https://open-meteo.com/en/docs (Weather variable documentation).
struct WeatherCode {
    let rawValue: Int

    var symbolName: String {
        switch rawValue {
        case 0: return "sun.max"                       // Clear sky
        case 1: return "sun.max"                        // Mainly clear
        case 2: return "cloud.sun"                       // Partly cloudy
        case 3: return "cloud"                           // Overcast
        case 45, 48: return "cloud.fog"                  // Fog
        case 51, 53, 55: return "cloud.drizzle"          // Drizzle
        case 56, 57: return "cloud.sleet"                // Freezing drizzle
        case 61, 63, 65: return "cloud.rain"             // Rain
        case 66, 67: return "cloud.sleet"                // Freezing rain
        case 71, 73, 75, 77: return "cloud.snow"         // Snow
        case 80, 81, 82: return "cloud.heavyrain"        // Rain showers
        case 85, 86: return "cloud.snow"                 // Snow showers
        case 95: return "cloud.bolt.rain"                // Thunderstorm
        case 96, 99: return "cloud.bolt.rain"            // Thunderstorm w/ hail
        default: return "cloud"
        }
    }

    var text: String {
        switch rawValue {
        case 0: return "Clear"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm"
        default: return "—"
        }
    }
}
