import Foundation

enum WidgetLayout: String, CaseIterable, Identifiable {
    case balance
    case recovery
    case schedule

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balance: return "Balance"
        case .recovery: return "Recovery"
        case .schedule: return "Schedule"
        }
    }

    fileprivate var metricPriority: [String] {
        switch self {
        case .balance: return ["readiness", "steps", "nextEvent", "sleep", "heart"]
        case .recovery: return ["readiness", "sleep", "heart", "nextEvent", "steps"]
        case .schedule: return ["nextEvent", "readiness", "steps", "sleep", "heart"]
        }
    }
}

enum WidgetPreferences {
    private static let layoutKey = "widget.layout"
    private static let primaryMetricKey = "widget.primaryMetricID"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: DashboardStore.appGroupID) ?? .standard
    }

    static var layout: WidgetLayout {
        get { WidgetLayout(rawValue: defaults.string(forKey: layoutKey) ?? "") ?? .balance }
        set { defaults.set(newValue.rawValue, forKey: layoutKey) }
    }

    /// Empty means use the current layout's first available metric.
    static var primaryMetricID: String {
        get { defaults.string(forKey: primaryMetricKey) ?? "" }
        set { defaults.set(newValue, forKey: primaryMetricKey) }
    }

    static func orderedMetrics(_ metrics: [DashboardMetric]) -> [DashboardMetric] {
        orderedMetrics(metrics, layout: layout, primaryMetricID: primaryMetricID)
    }

    static func orderedMetrics(
        _ metrics: [DashboardMetric],
        layout: WidgetLayout,
        primaryMetricID: String
    ) -> [DashboardMetric] {
        let priorities = layout.metricPriority
        // Preserve source order for equally ranked or new metric types.
        var ordered = metrics.enumerated().sorted { lhs, rhs in
            let left = priorities.firstIndex(of: lhs.element.id) ?? priorities.count
            let right = priorities.firstIndex(of: rhs.element.id) ?? priorities.count
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
        if !primaryMetricID.isEmpty, let index = ordered.firstIndex(where: { $0.id == primaryMetricID }) {
            let primary = ordered.remove(at: index)
            ordered.insert(primary, at: 0)
        }
        // A medium widget shows four metrics. Keep the next event visible when
        // a custom primary metric would otherwise push it out of that group.
        if let index = ordered.firstIndex(where: { $0.id == "nextEvent" }), index > 3 {
            let event = ordered.remove(at: index)
            ordered.insert(event, at: 3)
        }
        return ordered
    }

    static func primaryMetric(in metrics: [DashboardMetric]) -> DashboardMetric? {
        orderedMetrics(metrics).first
    }

    static func reset() {
        defaults.removeObject(forKey: layoutKey)
        defaults.removeObject(forKey: primaryMetricKey)
    }
}
