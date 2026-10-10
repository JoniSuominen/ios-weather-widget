import WidgetKit
import SwiftUI

struct WeatherUVWidget: Widget {
    let kind = "PulseboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PulseboardWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Pulseboard")
        .description("Health, recovery, and your schedule at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PulseboardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DashboardEntry

    private var displayedMetrics: [DashboardMetric] {
        Array(entry.orderedMetrics.prefix(family == .systemSmall ? 1 : 4))
    }

    private var freshness: DashboardFreshness { entry.freshness(for: displayedMetrics) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PULSEBOARD").font(.caption2.bold()).tracking(1)
                Spacer()
                Image(systemName: entry.layout == .schedule ? "calendar" : "sparkles")
            }.foregroundStyle(.white.opacity(0.8))
            if displayedMetrics.isEmpty {
                noData
            } else if family == .systemSmall {
                small
            } else {
                medium
            }
            Spacer(minLength: 0)
            freshnessLabel
        }.foregroundStyle(.white)
    }

    @ViewBuilder
    private var small: some View {
        if let metric = displayedMetrics.first {
            VStack(alignment: .leading, spacing: 3) {
                Text(metric.value)
                    .font(.system(size: metric.id == "nextEvent" ? 30 : 44, weight: .bold, design: .rounded))
                    .lineLimit(metric.id == "nextEvent" ? 2 : 1)
                    .minimumScaleFactor(0.55)
                Label(metric.title, systemImage: metric.symbol).font(.caption.bold()).lineLimit(1)
                Text(metric.detail).font(.caption2).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
        }
    }

    private var medium: some View {
        LazyVGrid(columns: [.init(.flexible(), alignment: .leading), .init(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(displayedMetrics) { metric in
                metricRow(metric)
            }
        }
    }

    private var noData: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "link.badge.plus").font(.title2)
            Text("Open Pulseboard to connect a data source.").font(.caption.bold())
        }
    }

    private func metricRow(_ metric: DashboardMetric) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(metric.title, systemImage: metric.symbol)
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            Text(metric.value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(metric.detail).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
        }
    }

    @ViewBuilder
    private var freshnessLabel: some View {
        HStack(spacing: 3) {
            if freshness.hasError {
                Label("Refresh failed · Open app", systemImage: "exclamationmark.triangle.fill")
            } else if freshness.hasMissingFetch {
                Label("Open app to refresh", systemImage: "exclamationmark.clock.fill")
            } else if let fetchedAt = freshness.oldestFetchAt {
                if freshness.isStale(at: entry.date) {
                    Image(systemName: "exclamationmark.clock.fill")
                    Text("Stale ·")
                } else {
                    Text("Fetched")
                }
                Text(fetchedAt, style: .relative)
            }
        }
        .font(.system(size: 9))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(freshness.isStale(at: entry.date) ? .yellow : .white.opacity(0.7))
    }
}
