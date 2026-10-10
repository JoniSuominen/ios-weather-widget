import Foundation

enum DataSource: String, Codable, CaseIterable, Identifiable {
    case appleHealth = "Apple Health"
    case oura = "Oura"
    case googleCalendar = "Google Calendar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .googleCalendar: return "Calendar"
        default: return rawValue
        }
    }

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

    // Numeric metadata belongs to the source. Never infer a gauge from a
    // formatted value such as "7h 42m" or "8,420".
    let numericValue: Double?
    let targetValue: Double?
    let observedAt: Date?

    init(
        id: String,
        source: DataSource,
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: String,
        numericValue: Double? = nil,
        targetValue: Double? = nil,
        observedAt: Date? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.value = value
        self.detail = detail
        self.symbol = symbol
        self.tint = tint
        self.numericValue = numericValue
        self.targetValue = targetValue
        self.observedAt = observedAt
    }

    /// A normalized, finite goal or score. Metrics without a meaningful target
    /// (sleep duration, heart rate, events) use a text presentation instead.
    var gaugeProgress: Double? {
        guard let numericValue, let targetValue,
              numericValue.isFinite, targetValue.isFinite,
              numericValue >= 0, targetValue > 0 else { return nil }
        return min(numericValue / targetValue, 1)
    }

    /// Illustrative data for WidgetKit placeholders and previews only.
    static let defaults: [DashboardMetric] = [
        .init(id: "readiness", source: .oura, title: "Readiness", value: "86", detail: "Optimal", symbol: "sparkles", tint: "violet", numericValue: 86, targetValue: 100),
        .init(id: "sleep", source: .oura, title: "Sleep", value: "7h 42m", detail: "Score 91", symbol: "moon.stars.fill", tint: "indigo"),
        .init(id: "steps", source: .appleHealth, title: "Steps", value: "8,420", detail: "84% of goal", symbol: "figure.walk", tint: "mint", numericValue: 8420, targetValue: 10000),
        .init(id: "heart", source: .appleHealth, title: "Heart rate", value: "62", detail: "bpm resting", symbol: "heart.fill", tint: "pink"),
        .init(id: "nextEvent", source: .googleCalendar, title: "Up next", value: "Design sync", detail: "10:30 · in 24 min", symbol: "calendar", tint: "blue")
    ]
}

enum DashboardStore {
    static let appGroupID = "group.com.jonisuominen.pulseboard"
    private static let metricsKey = "dashboard.metrics"
    private static let sourcesKey = "dashboard.sources"
    private static let updatedAtKey = "dashboard.updatedAt"
    private static let sourceUpdatesKey = "dashboard.sourceUpdates"
    private static let sourceErrorsKey = "dashboard.sourceErrors"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var metrics: [DashboardMetric] {
        get {
            guard let data = defaults.data(forKey: metricsKey),
                  let metrics = try? JSONDecoder().decode([DashboardMetric].self, from: data) else {
                return []
            }
            return metrics
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: metricsKey)
        }
    }

    static var connectedSources: Set<DataSource> {
        get {
            let values = defaults.stringArray(forKey: sourcesKey) ?? []
            return Set(values.compactMap(DataSource.init(rawValue:)))
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: sourcesKey) }
    }

    static var updatedAt: Date? {
        get { defaults.object(forKey: updatedAtKey) as? Date }
        set { defaults.set(newValue, forKey: updatedAtKey) }
    }

    static func updatedAt(for source: DataSource) -> Date? {
        let updates = defaults.dictionary(forKey: sourceUpdatesKey) ?? [:]
        return updates[source.rawValue] as? Date
    }

    static func error(for source: DataSource) -> String? {
        let errors = defaults.dictionary(forKey: sourceErrorsKey) ?? [:]
        return errors[source.rawValue] as? String
    }

    static func recordError(_ message: String, for source: DataSource) {
        var errors = defaults.dictionary(forKey: sourceErrorsKey) ?? [:]
        errors[source.rawValue] = message
        defaults.set(errors, forKey: sourceErrorsKey)
    }

    static func replaceMetrics(_ newMetrics: [DashboardMetric], for source: DataSource, fetchedAt: Date = .now) {
        var current = metrics
        current.removeAll { $0.source == source }
        current.append(contentsOf: newMetrics.filter { $0.source == source })
        let order = ["readiness", "sleep", "steps", "heart", "nextEvent"]
        current.sort {
            (order.firstIndex(of: $0.id) ?? order.count) <
                (order.firstIndex(of: $1.id) ?? order.count)
        }
        metrics = current
        var updates = defaults.dictionary(forKey: sourceUpdatesKey) ?? [:]
        updates[source.rawValue] = fetchedAt
        defaults.set(updates, forKey: sourceUpdatesKey)
        clearError(for: source)
        updatedAt = fetchedAt
    }

    static func removeMetrics(for source: DataSource) {
        metrics = metrics.filter { $0.source != source }
        var updates = defaults.dictionary(forKey: sourceUpdatesKey) ?? [:]
        updates.removeValue(forKey: source.rawValue)
        defaults.set(updates, forKey: sourceUpdatesKey)
        clearError(for: source)
        // Removing a source is not a data fetch.
        updatedAt = DataSource.allCases.compactMap { updatedAt(for: $0) }.max()
    }

    static func deleteLocalData() {
        defaults.removeObject(forKey: metricsKey)
        defaults.removeObject(forKey: sourcesKey)
        defaults.removeObject(forKey: updatedAtKey)
        defaults.removeObject(forKey: sourceUpdatesKey)
        defaults.removeObject(forKey: sourceErrorsKey)
        WidgetPreferences.reset()
    }

    private static func clearError(for source: DataSource) {
        var errors = defaults.dictionary(forKey: sourceErrorsKey) ?? [:]
        errors.removeValue(forKey: source.rawValue)
        defaults.set(errors, forKey: sourceErrorsKey)
    }
}

/// Freshness describes the last successful source fetch, not a widget timeline
/// read or the date of the underlying measurement. One stale source makes the
/// displayed group stale even when another source fetched successfully.
struct DashboardFreshness {
    static let staleInterval: TimeInterval = 60 * 60

    let oldestFetchAt: Date?
    let hasError: Bool
    let hasMissingFetch: Bool
    let hasMetrics: Bool

    init(
        metrics: [DashboardMetric],
        updatedAtBySource: [DataSource: Date],
        errorsBySource: [DataSource: String]
    ) {
        let sources = Set(metrics.map(\.source))
        let dates = sources.compactMap { updatedAtBySource[$0] }
        oldestFetchAt = dates.min()
        hasError = sources.contains { errorsBySource[$0] != nil }
        hasMissingFetch = dates.count < sources.count
        hasMetrics = !metrics.isEmpty
    }

    static func stored(for metrics: [DashboardMetric]) -> DashboardFreshness {
        var updates: [DataSource: Date] = [:]
        var errors: [DataSource: String] = [:]
        for source in Set(metrics.map(\.source)) {
            updates[source] = DashboardStore.updatedAt(for: source)
            errors[source] = DashboardStore.error(for: source)
        }
        return DashboardFreshness(metrics: metrics, updatedAtBySource: updates, errorsBySource: errors)
    }

    func isStale(at date: Date = .now) -> Bool {
        guard hasMetrics else { return false }
        guard !hasError, !hasMissingFetch, let oldestFetchAt else { return true }
        return date.timeIntervalSince(oldestFetchAt) >= Self.staleInterval
    }
}
