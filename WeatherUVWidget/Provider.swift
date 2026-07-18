import WidgetKit
import SwiftUI

/// One timeline entry: the weather to render at `date`.
struct WeatherEntry: TimelineEntry {
    let date: Date
    let weather: WeatherData
}

/// Reads the shared coordinate, fetches Open-Meteo, and emits a timeline.
/// Never uses live GPS inside the extension — it only reads what the app stored.
struct Provider: TimelineProvider {

    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: Date(), weather: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        // In the gallery (isPreview) show the placeholder instantly.
        if context.isPreview || !SharedStore.hasCoordinate {
            completion(WeatherEntry(date: Date(), weather: .placeholder))
            return
        }
        Task {
            let weather = await currentWeather()
            completion(WeatherEntry(date: Date(), weather: weather))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        Task {
            let weather = await currentWeather()
            let entry = WeatherEntry(date: Date(), weather: weather)
            // Refresh roughly every 30 minutes.
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// Fetch weather for the stored coordinate, falling back to the placeholder on error.
    private func currentWeather() async -> WeatherData {
        guard SharedStore.hasCoordinate else { return .placeholder }
        do {
            return try await WeatherService.fetch(
                latitude: SharedStore.latitude,
                longitude: SharedStore.longitude,
                placeName: SharedStore.placeName
            )
        } catch {
            return .placeholder
        }
    }
}
