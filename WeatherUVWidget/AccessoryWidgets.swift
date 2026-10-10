import WidgetKit
import SwiftUI

struct WeatherUVAccessoryWidget: Widget {
    let kind = "PulseboardAccessoryWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AccessoryView(entry: entry).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Pulseboard glance")
        .description("A selected metric and your next event.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct AccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DashboardEntry
    private var primary: DashboardMetric? {
        entry.orderedMetrics.first
    }
    private var event: DashboardMetric? { entry.metrics.first(where: { $0.id == "nextEvent" }) }

    private var displayedMetrics: [DashboardMetric] {
        guard let primary else { return [] }
        if family == .accessoryRectangular, let event, event.id != primary.id {
            return [primary, event]
        }
        return [primary]
    }

    private var freshness: DashboardFreshness { entry.freshness(for: displayedMetrics) }
    private var isStale: Bool { freshness.isStale(at: entry.date) }

    var body: some View {
        if let primary {
            switch family {
            case .accessoryCircular:
                circular(primary)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("\(primary.title) \(primary.value)", systemImage: primary.symbol).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    if let event, event.id != primary.id {
                        Label("\(event.value) · \(event.detail)", systemImage: "calendar").font(.caption).lineLimit(1)
                    } else {
                        Text(primary.detail).font(.caption).lineLimit(1)
                    }
                    freshnessLabel
                }
            default:
                Label("\(isStale ? "Stale · " : "")\(primary.title) \(primary.value)", systemImage: isStale ? "exclamationmark.clock" : primary.symbol)
            }
        } else {
            Label("Open Pulseboard", systemImage: "link.badge.plus")
        }
    }

    @ViewBuilder
    private func circular(_ metric: DashboardMetric) -> some View {
        if let progress = metric.gaugeProgress {
            Gauge(value: progress, in: 0...1) {
                Image(systemName: isStale ? "exclamationmark.clock" : metric.symbol)
            } currentValueLabel: {
                Text(metric.value).font(.system(size: 14, weight: .semibold)).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
            .overlay(alignment: .bottom) {
                if isStale {
                    Text("Stale").font(.system(size: 8, weight: .bold)).padding(.bottom, 2)
                }
            }
            .accessibilityLabel("\(metric.title), \(metric.value)\(isStale ? ", stale, open Pulseboard to refresh" : "")")
        } else {
            VStack(spacing: 1) {
                Image(systemName: isStale ? "exclamationmark.clock" : metric.symbol).font(.caption2)
                Text(metric.value).font(.system(size: 13, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.5)
                Text(isStale ? "Stale" : metric.title).font(.system(size: 8)).lineLimit(1)
            }
            .accessibilityLabel("\(metric.title), \(metric.value)\(isStale ? ", stale, open Pulseboard to refresh" : "")")
        }
    }

    @ViewBuilder
    private var freshnessLabel: some View {
        HStack(spacing: 2) {
            if freshness.hasError {
                Label("Refresh failed · Open app", systemImage: "exclamationmark.triangle")
            } else if freshness.hasMissingFetch {
                Text("Open app to refresh")
            } else if let fetchedAt = freshness.oldestFetchAt {
                Text(isStale ? "Stale ·" : "Fetched")
                Text(fetchedAt, style: .relative)
            }
        }.font(.system(size: 9)).lineLimit(1)
    }
}
