import WidgetKit
import SwiftUI

/// Lock Screen widgets — the smallest glanceable surfaces on iOS (iOS 16+).
struct WeatherUVAccessoryWidget: Widget {
    let kind = "WeatherUVAccessoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AccessoryView(weather: entry.weather)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Weather + UV")
        .description("Temperature and UV on your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct AccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let weather: WeatherData

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        default:
            inline
        }
    }

    // Circular: a UV gauge — the most glanceable, smallest possible widget.
    private var circular: some View {
        Gauge(value: min(weather.uvIndex, 11), in: 0...11) {
            Text("UV")
        } currentValueLabel: {
            Text("\(weather.uvRounded)")
        }
        .gaugeStyle(.accessoryCircular)
        .tint(UVLevel(index: weather.uvIndex).color)
    }

    // Rectangular: temp + condition on top, UV level below.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: weather.symbolName)
                Text("\(weather.temperatureRounded)°")
                    .font(.headline)
                Text(weather.conditionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                Image(systemName: "sun.max.trianglebadge.exclamationmark")
                Text("UV \(weather.uvRounded) · \(UVLevel(index: weather.uvIndex).rawValue)")
                    .font(.caption)
            }
        }
        .widgetAccentable()
    }

    // Inline: single line next to the clock.
    private var inline: some View {
        Label {
            Text("\(weather.temperatureRounded)° · UV \(weather.uvRounded)")
        } icon: {
            Image(systemName: weather.symbolName)
        }
    }
}
