import Foundation
import CoreLocation
import WidgetKit

/// Wraps CoreLocation for the host app. When a new location arrives it reverse-geocodes
/// a friendly name, saves the coordinate into the App Group, and reloads the widgets.
///
/// The widget extension never runs this — it only reads the stored coordinate — so the
/// widget stays reliable regardless of live GPS state.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var lastPlaceName: String = SharedStore.placeName

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Ask for a one-shot location fix (used when in auto mode).
    func refresh() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await self.store(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Non-fatal: keep whatever coordinate we already had.
    }

    private func store(_ location: CLLocation) async {
        var name = "My Location"
        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            name = placemark.locality ?? placemark.name ?? name
        }
        // Only overwrite the shared coordinate when the user wants auto GPS.
        if SharedStore.mode == .auto {
            SharedStore.setCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                placeName: name
            )
            lastPlaceName = name
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
