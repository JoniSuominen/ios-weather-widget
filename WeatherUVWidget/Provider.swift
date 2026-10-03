import WidgetKit

struct DashboardEntry: TimelineEntry {
    let date: Date
    let metrics: [DashboardMetric]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry {
        DashboardEntry(date: .now, metrics: DashboardMetric.defaults)
    }

    func getSnapshot(in context: Context, completion: @escaping (DashboardEntry) -> Void) {
        completion(DashboardEntry(date: .now, metrics: DashboardStore.metrics))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardEntry>) -> Void) {
        let entry = DashboardEntry(date: .now, metrics: DashboardStore.metrics)
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}
