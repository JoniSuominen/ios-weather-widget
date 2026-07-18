import Foundation

/// Where the widget should read weather for.
enum LocationMode: String {
    case auto   // follow device GPS (updated while the app is open)
    case fixed  // a city the user pinned in the app
}

/// Shared settings + last resolved coordinate, persisted in the App Group so the
/// app and the widget extension read/write the same values.
///
/// IMPORTANT: `appGroupID` must match the App Group configured in both targets'
/// entitlements and in `project.yml`. If you change your bundle id prefix, change
/// this too.
enum SharedStore {
    static let appGroupID = "group.com.example.WeatherUV"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private enum Key {
        static let mode = "mode"
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let placeName = "placeName"
        static let hasCoordinate = "hasCoordinate"
    }

    static var mode: LocationMode {
        get { LocationMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: Key.mode) }
    }

    static var hasCoordinate: Bool {
        defaults.bool(forKey: Key.hasCoordinate)
    }

    static var latitude: Double {
        get { defaults.double(forKey: Key.latitude) }
        set { defaults.set(newValue, forKey: Key.latitude) }
    }

    static var longitude: Double {
        get { defaults.double(forKey: Key.longitude) }
        set { defaults.set(newValue, forKey: Key.longitude) }
    }

    static var placeName: String {
        get { defaults.string(forKey: Key.placeName) ?? "—" }
        set { defaults.set(newValue, forKey: Key.placeName) }
    }

    /// Store a resolved coordinate + name (from GPS or a pinned city).
    static func setCoordinate(latitude: Double, longitude: Double, placeName: String) {
        defaults.set(latitude, forKey: Key.latitude)
        defaults.set(longitude, forKey: Key.longitude)
        defaults.set(placeName, forKey: Key.placeName)
        defaults.set(true, forKey: Key.hasCoordinate)
    }
}
