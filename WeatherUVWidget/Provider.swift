import WidgetKit

struct DashboardEntry: TimelineEntry {
    let date: Date
    let metrics: [DashboardMetric]
    let layout: WidgetLayout
    let primaryMetricID: String
    let updatedAtBySource: [DataSource: Date]
    let errorsBySource: [DataSource: String]

    var orderedMetrics: [DashboardMetric] {
        WidgetPreferences.orderedMetrics(metrics, layout: layout, primaryMetricID: primaryMetricID)
    }

    func freshness(for displayedMetrics: [DashboardMetric]) -> DashboardFreshness {
        DashboardFreshness(
            metrics: displayedMetrics,
            updatedAtBySource: updatedAtBySource,
            errorsBySource: errorsBySource
        )
    }

    static func cached(at date: Date) -> DashboardEntry {
        var updates: [DataSource: Date] = [:]
        var errors: [DataSource: String] = [:]
        for source in DataSource.allCases {
            updates[source] = DashboardStore.updatedAt(for: source)
            errors[source] = DashboardStore.error(for: source)
        }
        return DashboardEntry(
            date: date,
            metrics: DashboardStore.metrics,
            layout: WidgetPreferences.layout,
            primaryMetricID: WidgetPreferences.primaryMetricID,
            updatedAtBySource: updates,
            errorsBySource: errors
        )
    }

    static func preview(at date: Date = .now) -> DashboardEntry {
        DashboardEntry(
            date: date,
            metrics: DashboardMetric.defaults,
            layout: .balance,
            primaryMetricID: "",
            updatedAtBySource: Dictionary(uniqueKeysWithValues: DataSource.allCases.map { ($0, date) }),
            errorsBySource: [:]
        )
    }

    func scheduled(at date: Date) -> DashboardEntry {
        DashboardEntry(
            date: date,
            metrics: metrics,
            layout: layout,
            primaryMetricID: primaryMetricID,
            updatedAtBySource: updatedAtBySource,
            errorsBySource: errorsBySource
        )
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry {
        .preview()
    }

    func getSnapshot(in context: Context, completion: @escaping (DashboardEntry) -> Void) {
        completion(context.isPreview ? .preview() : .cached(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardEntry>) -> Void) {
        let now = Date.now
        let entry = DashboardEntry.cached(at: now)
        let rereadAt = now.addingTimeInterval(30 * 60)
        // WidgetKit rereads the shared cache; it does not fetch source data.
        // Schedule the stale boundary so a previously fresh widget visibly
        // ages even if the app is not opened again.
        let boundaries = Set(entry.updatedAtBySource.values.map {
            $0.addingTimeInterval(DashboardFreshness.staleInterval)
        }).filter { $0 > now && $0 <= rereadAt }.sorted()
        let entries = [entry] + boundaries.map { entry.scheduled(at: $0) }
        completion(Timeline(entries: entries, policy: .after(rereadAt)))
    }
}
