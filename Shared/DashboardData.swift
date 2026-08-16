import Foundation

enum DataSource: String, Codable, CaseIterable, Identifiable {
    case appleHealth = "Apple Health"
    case oura = "Oura"
    case googleCalendar = "Google Calendar"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .appleHealth: return "heart.fill"
        case .oura: return "circle.hexagongrid.fill"
        case .googleCalendar: return "calendar"
        }
    }
}

struct DashboardMetric: Codable, Identifiable, Hashable {
    let id: String
    let source: DataSource
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: String

    static let defaults: [DashboardMetric] = [
        .init(id: "readiness", source: .oura, title: "Readiness", value: "86", detail: "Optimal", symbol: "sparkles", tint: "violet"),
        .init(id: "sleep", source: .oura, title: "Sleep", value: "7h 42m", detail: "Score 91", symbol: "moon.stars.fill", tint: "indigo"),
        .init(id: "steps", source: .appleHealth, title: "Steps", value: "8,420", detail: "84% of goal", symbol: "figure.walk", tint: "mint"),
        .init(id: "heart", source: .appleHealth, title: "Heart rate", value: "62", detail: "bpm resting", symbol: "heart.fill", tint: "pink"),
        .init(id: "nextEvent", source: .googleCalendar, title: "Up next", value: "Design sync", detail: "10:30 · in 24 min", symbol: "calendar", tint: "blue")
    ]
}

enum DashboardStore {
    static let appGroupID = "group.com.example.WeatherUV"
    private static let metricsKey = "dashboard.metrics"
    private static let sourcesKey = "dashboard.sources"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var metrics: [DashboardMetric] {
        get {
            guard let data = defaults.data(forKey: metricsKey),
                  let metrics = try? JSONDecoder().decode([DashboardMetric].self, from: data) else {
                return DashboardMetric.defaults
            }
            return metrics
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: metricsKey)
        }
    }

    static var connectedSources: Set<DataSource> {
        get {
            let values = defaults.stringArray(forKey: sourcesKey) ?? [DataSource.appleHealth.rawValue]
            return Set(values.compactMap(DataSource.init(rawValue:)))
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: sourcesKey) }
    }
}
