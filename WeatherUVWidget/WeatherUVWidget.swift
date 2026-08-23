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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PULSEBOARD").font(.caption2.bold()).tracking(1)
                Spacer()
                Image(systemName: "sparkles")
            }.foregroundStyle(.white.opacity(0.8))
            if entry.metrics.isEmpty {
                noData
            } else if family == .systemSmall {
                small
            } else {
                medium
            }
            Spacer(minLength: 0)
            Text("Updated \(entry.date, style: .relative)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
        }.foregroundStyle(.white)
    }

    @ViewBuilder
    private var small: some View {
        if let metric = entry.metrics.first {
            VStack(alignment: .leading, spacing: 1) {
                Text(metric.value).font(.system(size: 48, weight: .bold, design: .rounded))
                Text("\(metric.title) · \(metric.detail)").font(.caption.bold()).lineLimit(1)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(entry.metrics.prefix(3))) { metric in
                    metricRow(metric)
                }
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
        HStack(spacing: 7) {
            Image(systemName: metric.symbol).frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(metric.value).font(.subheadline.bold()).lineLimit(1)
                Text(metric.title).font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
