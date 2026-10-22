import Foundation
import HealthKit
import EventKit
import WidgetKit

/// Refreshes sources that can be read without opening the app: weather,
/// Apple Health, Oura sleep shared with Apple Health, and calendars. Direct
/// Oura account data needs the app's Keychain credentials and refreshes when
/// the app runs.
@MainActor
enum WidgetDataRefresher {
    /// Timeline reloads skip sources fetched more recently than this.
    static let passiveMinimumAge: TimeInterval = 10 * 60

    private static var inFlight: Task<Void, Never>?

    /// `userInitiated` comes from the widget's sync button: it refreshes every
    /// eligible source and reports failures. Passive timeline refreshes skip
    /// fresh sources and stay silent, because a locked device makes Health
    /// data briefly unreadable and that is not a failure worth showing.
    static func refresh(userInitiated: Bool) async {
        if let inFlight {
            await inFlight.value
            if !userInitiated { return }
        }
        let task = Task { @MainActor in
            await WidgetDataRefresher.refresh(userInitiated: userInitiated, now: .now) {
                WidgetDataRefresher.connector(for: $0)
            }
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    static func refresh(
        userInitiated: Bool,
        now: Date,
        connectorFor: @MainActor (DataSource) -> (any DashboardConnector)?
    ) async {
        var published = false
        for source in DataSource.allCases where DashboardStore.connectedSources.contains(source) {
            guard let connector = connectorFor(source) else { continue }
            if !userInitiated, let fetchedAt = DashboardStore.updatedAt(for: source),
               now.timeIntervalSince(fetchedAt) < passiveMinimumAge {
                continue
            }
            let calendarRevision = CalendarPreferences.revision
            do {
                let metrics = try await connector.refresh()
                // Disconnecting or changing calendar privacy during the fetch wins.
                guard DashboardStore.connectedSources.contains(source),
                      source != .googleCalendar || calendarRevision == CalendarPreferences.revision else { continue }
                DashboardStore.replaceMetrics(metrics, for: source)
                published = true
            } catch {
                guard userInitiated, DashboardStore.connectedSources.contains(source),
                      !isTemporarilyUnreadable(error) else { continue }
                DashboardStore.recordError(error.localizedDescription, for: source)
                published = true
            }
        }
        if published && userInitiated {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func connector(for source: DataSource) -> (any DashboardConnector)? {
        switch source {
        case .weather:
            return WeatherConnector()
        case .appleHealth:
            return HealthKitConnector()
        case .oura:
            return OuraConnectionMethod.stored == .appleHealth ? OuraHealthConnector() : nil
        case .googleCalendar:
            // Without full access here, leave the snapshot alone; the app clears
            // it when permission is revoked.
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess ? CalendarConnector() : nil
        }
    }

    private static func isTemporarilyUnreadable(_ error: Error) -> Bool {
        (error as? HKError)?.code == .errorDatabaseInaccessible
    }
}
