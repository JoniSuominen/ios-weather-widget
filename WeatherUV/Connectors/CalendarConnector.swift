import EventKit
import Foundation

final class CalendarConnector: DashboardConnector {
    let source: DataSource = .googleCalendar

    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func authorize() async throws {
        let granted = try await eventStore.requestFullAccessToEvents()
        guard granted else {
            throw ConnectorError.authorizationDenied("Calendar access was not granted.")
        }
    }

    func refresh() async throws -> [DashboardMetric] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw ConnectorError.authorizationDenied("Allow full calendar access in Settings to refresh events.")
        }

        let end = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        let predicate = eventStore.predicateForEvents(withStart: .now, end: end, calendars: nil)
        let nextEvent = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > .now }
            .sorted { $0.startDate < $1.startDate }
            .first

        return [DashboardMetric(
            id: "nextEvent",
            source: .googleCalendar,
            title: "Up next",
            value: nextEvent?.title.nilIfBlank ?? "No upcoming events",
            detail: nextEvent.map(Self.eventDetail) ?? "Next 7 days",
            symbol: "calendar",
            tint: "blue"
        )]
    }

    func disconnect() async {
        // EventKit has no per-app revocation API. Users revoke access in Settings.
    }

    private static func eventDetail(_ event: EKEvent) -> String {
        let time = event.startDate.formatted(date: .omitted, time: .shortened)
        let relative = event.startDate.formatted(.relative(presentation: .numeric))
        return "\(time) · \(relative)"
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        return value
    }
}
