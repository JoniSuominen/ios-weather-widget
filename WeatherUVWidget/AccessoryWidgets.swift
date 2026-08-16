import WidgetKit
import SwiftUI

struct WeatherUVAccessoryWidget: Widget {
    let kind = "PulseboardAccessoryWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AccessoryView(entry: entry).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Pulseboard glance")
        .description("Your readiness and next event.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct AccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DashboardEntry
    private var readiness: DashboardMetric { entry.metrics.first(where: { $0.id == "readiness" }) ?? DashboardMetric.defaults[0] }
    private var event: DashboardMetric { entry.metrics.first(where: { $0.id == "nextEvent" }) ?? DashboardMetric.defaults[4] }
    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(readiness.value) ?? 0, in: 0...100) { Text("Ready") } currentValueLabel: { Text(readiness.value) }.gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading) { Label("Readiness \(readiness.value)", systemImage: "sparkles").font(.headline); Label("\(event.value) · \(event.detail)", systemImage: "calendar").font(.caption).lineLimit(1) }
        default:
            Label("Ready \(readiness.value) · \(event.value)", systemImage: "sparkles")
        }
    }
}
