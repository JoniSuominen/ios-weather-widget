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
            if family == .systemSmall { small } else { medium }
            Spacer(minLength: 0)
            Text("Updated \(entry.date, style: .relative)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
        }.foregroundStyle(.white)
    }

    private var small: some View {
        let readiness = metric("readiness")
        return VStack(alignment: .leading, spacing: 1) {
            Text(readiness.value).font(.system(size: 48, weight: .bold, design: .rounded))
            Text("Readiness · \(readiness.detail)").font(.caption.bold()).lineLimit(1)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(metric("readiness").value).font(.system(size: 42, weight: .bold, design: .rounded))
                Text("Ready").font(.caption.bold()).foregroundStyle(.white.opacity(0.8))
            }
            Divider().overlay(.white.opacity(0.25))
            VStack(alignment: .leading, spacing: 8) {
                metricRow(metric("steps"))
                metricRow(metric("nextEvent"))
            }
        }
    }

    private func metric(_ id: String) -> DashboardMetric {
        entry.metrics.first(where: { $0.id == id }) ?? DashboardMetric.defaults.first(where: { $0.id == id })!
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
