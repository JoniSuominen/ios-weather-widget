import SwiftUI
import CoreLocation
import WidgetKit

struct ContentView: View {
    @StateObject private var location = LocationManager()
    @StateObject private var model = WeatherViewModel()

    @State private var mode: LocationMode = SharedStore.mode
    @State private var citySearch: String = ""
    @State private var searchResults: [WeatherService.Place] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            Form {
                currentConditionsSection
                sourceSection
                if mode == .fixed {
                    citySection
                }
                widgetHelpSection
            }
            .navigationTitle("Weather + UV")
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    // MARK: - Sections

    private var currentConditionsSection: some View {
        Section("Now") {
            if let w = model.weather {
                HStack(spacing: 16) {
                    Image(systemName: w.symbolName)
                        .font(.system(size: 40))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(w.temperatureRounded)°")
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                        Text(w.conditionText)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    uvBadge(for: w)
                }
                Text(w.placeName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let error = model.errorMessage {
                Text(error).foregroundStyle(.secondary)
            } else {
                HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            }
        }
    }

    private func uvBadge(for w: WeatherData) -> some View {
        let level = UVLevel(index: w.uvIndex)
        return VStack(spacing: 2) {
            Text("UV \(w.uvRounded)")
                .font(.headline)
            Text(level.rawValue)
                .font(.caption2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(level.color.opacity(0.2), in: Capsule())
        .foregroundStyle(level.color)
    }

    private var sourceSection: some View {
        Section("Location source") {
            Picker("Source", selection: $mode) {
                Text("Auto (GPS)").tag(LocationMode.auto)
                Text("Fixed city").tag(LocationMode.fixed)
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, newValue in
                SharedStore.mode = newValue
                Task { await applyModeChange(newValue) }
            }

            if mode == .auto {
                switch location.authorizationStatus {
                case .notDetermined:
                    Button("Allow location access") { location.requestPermission() }
                case .denied, .restricted:
                    Text("Location access is denied. Enable it in Settings to use auto mode.")
                        .font(.footnote).foregroundStyle(.secondary)
                default:
                    Label(location.lastPlaceName, systemImage: "location.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var citySection: some View {
        Section("Pinned city") {
            TextField("Search a city…", text: $citySearch)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onChange(of: citySearch) { _, query in
                    Task { await runSearch(query) }
                }

            if isSearching { ProgressView() }

            ForEach(searchResults) { place in
                Button {
                    Task { await pin(place) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(place.name).foregroundStyle(.primary)
                        if !place.subtitle.isEmpty {
                            Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if searchResults.isEmpty && !citySearch.isEmpty && !isSearching {
                Text("No matches").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var widgetHelpSection: some View {
        Section("Widgets") {
            Text("Add the small **WeatherUV** widget to your Home Screen, or the circular / rectangular / inline widgets to your Lock Screen. They update automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func refresh() async {
        if mode == .auto { location.refresh() }
        await model.load()
    }

    private func applyModeChange(_ newValue: LocationMode) async {
        if newValue == .auto {
            location.refresh()
        }
        await model.load()
    }

    private func runSearch(_ query: String) async {
        isSearching = true
        defer { isSearching = false }
        searchResults = (try? await WeatherService.searchCities(query)) ?? []
    }

    private func pin(_ place: WeatherService.Place) async {
        SharedStore.mode = .fixed
        SharedStore.setCoordinate(latitude: place.latitude,
                                  longitude: place.longitude,
                                  placeName: place.name)
        citySearch = ""
        searchResults = []
        await model.load()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Drives the in-app "Now" panel by reading the shared coordinate and fetching weather.
@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var weather: WeatherData?
    @Published var errorMessage: String?

    func load() async {
        guard SharedStore.hasCoordinate else {
            errorMessage = "Choose a location to see current weather."
            return
        }
        do {
            weather = try await WeatherService.fetch(
                latitude: SharedStore.latitude,
                longitude: SharedStore.longitude,
                placeName: SharedStore.placeName
            )
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load weather. Pull to retry."
        }
    }
}

#Preview {
    ContentView()
}
