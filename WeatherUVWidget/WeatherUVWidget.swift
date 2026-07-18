import WidgetKit
import SwiftUI

/// The small Home Screen widget (2x2) — the smallest Home Screen size.
struct WeatherUVWidget: Widget {
    let kind = "WeatherUVWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SmallWidgetView(weather: entry.weather)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color.blue.opacity(0.35), Color.indigo.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Weather + UV")
        .description("Current temperature and UV index at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

struct SmallWidgetView: View {
    let weather: WeatherData

    var body: some View {
        let level = UVLevel(index: weather.uvIndex)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: weather.symbolName)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.multicolor)
                Spacer()
                Text(weather.placeName)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer(minLength: 4)

            Text("\(weather.temperatureRounded)°")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Circle()
                    .fill(level.color)
                    .frame(width: 8, height: 8)
                Text("UV \(weather.uvRounded)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                Text(level.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .foregroundStyle(.white)
    }
}
