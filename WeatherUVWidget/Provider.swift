import WidgetKit

struct DashboardEntry: TimelineEntry {
    let date: Date
    let metrics: [DashboardMetric]
    let configuration: WidgetInstanceConfiguration
    let updatedAtBySource: [DataSource: Date]
    let errorsBySource: [DataSource: String]

    var layout: WidgetLayout { configuration.layout }

    var orderedMetrics: [DashboardMetric] {
        configuration.orderedMetrics(metrics)
    }

    func freshness(for displayedMetrics: [DashboardMetric]) -> DashboardFreshness {
        DashboardFreshness(
            metrics: displayedMetrics,
            updatedAtBySource: updatedAtBySource,
            errorsBySource: errorsBySource
        )
    }

    static func cached(at date: Date, configuration: WidgetInstanceConfiguration) -> DashboardEntry {
        var updates: [DataSource: Date] = [:]
        var errors: [DataSource: String] = [:]
        for source in DataSource.allCases {
            updates[source] = DashboardStore.updatedAt(for: source)
            errors[source] = DashboardStore.error(for: source)
        }
        return DashboardEntry(
            date: date,
            metrics: configuration.renderedMetrics(DashboardStore.metrics),
            configuration: configuration,
            updatedAtBySource: updates,
            errorsBySource: errors
        )
    }

    static func preview(at date: Date = .now, configuration: WidgetInstanceConfiguration) -> DashboardEntry {
        DashboardEntry(
            date: date,
            metrics: configuration.renderedMetrics(DashboardMetric.defaults),
            configuration: configuration,
            updatedAtBySource: Dictionary(uniqueKeysWithValues: DataSource.allCases.map { ($0, date) }),
            errorsBySource: [:]
        )
    }

    func scheduled(at date: Date) -> DashboardEntry {
        DashboardEntry(
            date: date,
            metrics: metrics,
            configuration: configuration,
            updatedAtBySource: updatedAtBySource,
            errorsBySource: errorsBySource
        )
    }
}

struct Provider<Configuration: PulseboardWidgetIntent>: AppIntentTimelineProvider {
    typealias Intent = Configuration

    func placeholder(in context: Context) -> DashboardEntry {
        .preview(configuration: Configuration.defaultConfiguration)
    }

    func snapshot(for configuration: Configuration, in context: Context) async -> DashboardEntry {
        context.isPreview
            ? .preview(configuration: configuration.instanceConfiguration)
            : .cached(at: .now, configuration: configuration.instanceConfiguration)
    }

    func timeline(for configuration: Configuration, in context: Context) async -> Timeline<DashboardEntry> {
        let now = Date.now
        let entry = DashboardEntry.cached(at: now, configuration: configuration.instanceConfiguration)
        let rereadAt = now.addingTimeInterval(30 * 60)
        // WidgetKit rereads the shared cache; it does not fetch source data.
        // Schedule the stale boundary so a previously fresh widget visibly
        // ages even if the app is not opened again.
        let boundaries = Set(entry.updatedAtBySource.values.map {
            $0.addingTimeInterval(DashboardFreshness.staleInterval)
        }).filter { $0 > now && $0 <= rereadAt }.sorted()
        let entries = [entry] + boundaries.map { entry.scheduled(at: $0) }
        return Timeline(entries: entries, policy: .after(rereadAt))
    }
}
