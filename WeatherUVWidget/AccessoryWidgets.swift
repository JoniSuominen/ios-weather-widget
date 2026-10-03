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
        entry.metrics.first(where: { $0.id == "readiness" }) ?? entry.metrics.first
    }
    private var event: DashboardMetric? { entry.metrics.first(where: { $0.id == "nextEvent" }) }

    var body: some View {
        if let primary {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(primary.value) ?? 0, in: 0...100) {
                    Text(primary.title)
                } currentValueLabel: {
                    Text(primary.value)
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Label("\(primary.title) \(primary.value)", systemImage: primary.symbol).font(.headline)
                    if let event {
                        Label("\(event.value) · \(event.detail)", systemImage: "calendar").font(.caption).lineLimit(1)
                    }
                }
            default:
                Label("\(primary.title) \(primary.value)", systemImage: primary.symbol)
            }
        } else {
            Label("Open Pulseboard", systemImage: "link.badge.plus")
        }
    }
}
