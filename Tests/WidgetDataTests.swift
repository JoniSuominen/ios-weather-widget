import Foundation
import XCTest
@testable import WeatherUV

final class WidgetDataTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DashboardStore.deleteLocalData()
        clearOuraPreferences()
    }

    override func tearDown() {
        DashboardStore.deleteLocalData()
        clearOuraPreferences()
        super.tearDown()
    }

    func testLegacySnapshotStillDecodesWithoutNumericMetadata() throws {
        let json = """
        [{"id":"sleep","source":"Oura","title":"Sleep","value":"7h 42m","detail":"Score 91","symbol":"moon.stars.fill","tint":"indigo"}]
        """
        let metrics = try JSONDecoder().decode([DashboardMetric].self, from: Data(json.utf8))
        XCTAssertEqual(metrics.first?.value, "7h 42m")
        XCTAssertNil(metrics.first?.numericValue)
        XCTAssertNil(metrics.first?.targetValue)
        XCTAssertNil(metrics.first?.observedAt)
        XCTAssertNil(metrics.first?.privateValue)
        XCTAssertNil(metrics.first?.gaugeProgress)
    }

    func testLegacyCalendarPrivacyMigrationPreservesHealthDataAndItsFetchState() throws {
        let defaults = UserDefaults(suiteName: DashboardStore.appGroupID) ?? .standard
        let healthFetch = Date(timeIntervalSince1970: 1000)
        let calendarFetch = Date(timeIntervalSince1970: 2000)
        let json = """
        [{"id":"steps","source":"Apple Health","title":"Steps","value":"42","detail":"Today","symbol":"figure.walk","tint":"mint"},
         {"id":"nextEvent","source":"Google Calendar","title":"Up next","value":"Confidential appointment","detail":"10:30","symbol":"calendar","tint":"blue"}]
        """
        defaults.set(Data(json.utf8), forKey: "dashboard.metrics")
        defaults.set([DataSource.appleHealth.rawValue: healthFetch, DataSource.googleCalendar.rawValue: calendarFetch], forKey: "dashboard.sourceUpdates")
        defaults.set([DataSource.appleHealth.rawValue: "Health unavailable", DataSource.googleCalendar.rawValue: "Calendar unavailable"], forKey: "dashboard.sourceErrors")
        defaults.set(calendarFetch, forKey: "dashboard.updatedAt")
        defaults.removeObject(forKey: "dashboard.privacyVersion")

        let migrated = DashboardStore.metrics

        XCTAssertEqual(migrated.map(\.id), ["steps"])
        XCTAssertEqual(migrated.first?.value, "42")
        XCTAssertEqual(DashboardStore.updatedAt(for: .appleHealth), healthFetch)
        XCTAssertEqual(DashboardStore.updatedAt, healthFetch)
        XCTAssertEqual(DashboardStore.error(for: .appleHealth), "Health unavailable")
        XCTAssertNil(DashboardStore.updatedAt(for: .googleCalendar))
        XCTAssertNil(DashboardStore.error(for: .googleCalendar))
        let savedData = try XCTUnwrap(defaults.data(forKey: "dashboard.metrics"))
        XCTAssertFalse(String(decoding: savedData, as: UTF8.self).contains("Confidential appointment"))

        // The migration is one-time: new titles explicitly opted into under the
        // new schema must not disappear on the next widget or app cache read.
        CalendarPreferences.showEventTitles = true
        let allowedEvent = DashboardMetric(id: "nextEvent", source: .googleCalendar, title: "Up next", value: "Busy",
                                          detail: "10:30", symbol: "calendar", tint: "blue", privateValue: "Allowed title")
        DashboardStore.replaceMetrics([allowedEvent], for: .googleCalendar)
        XCTAssertTrue(DashboardStore.metrics.contains(allowedEvent))
        XCTAssertEqual(DashboardStore.error(for: .appleHealth), "Health unavailable")
    }

    func testLegacyCalendarOnlyMigrationClearsGlobalFreshness() throws {
        let defaults = UserDefaults(suiteName: DashboardStore.appGroupID) ?? .standard
        let calendarFetch = Date(timeIntervalSince1970: 2000)
        let json = """
        [{"id":"nextEvent","source":"Google Calendar","title":"Up next","value":"Private appointment","detail":"10:30","symbol":"calendar","tint":"blue"}]
        """
        defaults.set(Data(json.utf8), forKey: "dashboard.metrics")
        defaults.set([DataSource.googleCalendar.rawValue: calendarFetch], forKey: "dashboard.sourceUpdates")
        defaults.set([DataSource.googleCalendar.rawValue: "Permission revoked"], forKey: "dashboard.sourceErrors")
        defaults.set(calendarFetch, forKey: "dashboard.updatedAt")
        defaults.removeObject(forKey: "dashboard.privacyVersion")

        XCTAssertTrue(DashboardStore.metrics.isEmpty)
        XCTAssertNil(DashboardStore.updatedAt)
        XCTAssertNil(DashboardStore.updatedAt(for: .googleCalendar))
        XCTAssertNil(DashboardStore.error(for: .googleCalendar))
        let savedData = try XCTUnwrap(defaults.data(forKey: "dashboard.metrics"))
        XCTAssertFalse(String(decoding: savedData, as: UTF8.self).contains("Private appointment"))
    }

    func testNewInstallDoesNotShowSampleMetrics() {
        XCTAssertTrue(DashboardStore.metrics.isEmpty)
        XCTAssertTrue(DashboardStore.connectedSources.isEmpty)
    }

    func testGaugeUsesNumericMetadataInsteadOfFormattedValue() {
        let steps = metric("steps", source: .appleHealth, value: "8,420", numericValue: 8420, targetValue: 10000)
        XCTAssertEqual(steps.gaugeProgress ?? -1, 0.842, accuracy: 0.0001)

        let readiness = metric("readiness", source: .oura, value: "86", numericValue: 86, targetValue: 100)
        XCTAssertEqual(readiness.gaugeProgress ?? -1, 0.86, accuracy: 0.0001)

        let sleep = metric("sleep", source: .oura, value: "7h 42m", numericValue: 27720)
        XCTAssertNil(sleep.gaugeProgress)
        XCTAssertNil(metric("steps", source: .appleHealth, value: "8,420").gaugeProgress)
    }

    func testGaugeClampsExcessAndRejectsInvalidTargets() {
        XCTAssertEqual(metric("steps", numericValue: 12000, targetValue: 10000).gaugeProgress, 1)
        XCTAssertNil(metric("steps", numericValue: 12000, targetValue: 0).gaugeProgress)
        XCTAssertNil(metric("steps", numericValue: -1, targetValue: 10000).gaugeProgress)
        XCTAssertNil(metric("steps", numericValue: .infinity, targetValue: 10000).gaugeProgress)
        XCTAssertNil(metric("steps", numericValue: 10, targetValue: .nan).gaugeProgress)
    }

    func testPreferencesPersistAndChangeMetricOrder() {
        WidgetPreferences.layout = .schedule
        WidgetPreferences.primaryMetricID = ""
        XCTAssertEqual(WidgetPreferences.layout, .schedule)
        XCTAssertEqual(WidgetPreferences.orderedMetrics(DashboardMetric.defaults).first?.id, "nextEvent")

        WidgetPreferences.layout = .recovery
        XCTAssertEqual(Array(WidgetPreferences.orderedMetrics(DashboardMetric.defaults).prefix(3)).map(\.id), ["readiness", "sleep", "heart"])

        WidgetPreferences.primaryMetricID = "steps"
        XCTAssertEqual(WidgetPreferences.primaryMetricID, "steps")
        XCTAssertEqual(WidgetPreferences.primaryMetric(in: DashboardMetric.defaults)?.id, "steps")
        XCTAssertTrue(WidgetPreferences.orderedMetrics(DashboardMetric.defaults).prefix(4).contains { $0.id == "nextEvent" })
    }

    func testEveryMediumLayoutIncludesCalendarAndUnavailablePrimaryFallsBack() {
        for layout in WidgetLayout.allCases {
            let ordered = WidgetPreferences.orderedMetrics(DashboardMetric.defaults, layout: layout, primaryMetricID: "steps")
            XCTAssertEqual(ordered.first?.id, "steps")
            XCTAssertTrue(ordered.prefix(4).contains { $0.id == "nextEvent" }, "Calendar missing from \(layout)")
        }
        WidgetPreferences.layout = .schedule
        WidgetPreferences.primaryMetricID = "removedMetric"
        XCTAssertEqual(WidgetPreferences.primaryMetric(in: DashboardMetric.defaults)?.id, "nextEvent")
        XCTAssertNil(WidgetPreferences.primaryMetric(in: []))
    }

    func testRefreshFailurePreservesLastSuccessfulFetchAndMetrics() {
        let fetchedAt = Date(timeIntervalSince1970: 1000)
        let readiness = metric("readiness", source: .oura)
        DashboardStore.replaceMetrics([readiness], for: .oura, fetchedAt: fetchedAt)
        DashboardStore.recordError("Connection unavailable", for: .oura)
        XCTAssertEqual(DashboardStore.updatedAt(for: .oura), fetchedAt)
        XCTAssertEqual(DashboardStore.metrics, [readiness])
        XCTAssertEqual(DashboardStore.error(for: .oura), "Connection unavailable")

        DashboardStore.replaceMetrics([readiness], for: .oura, fetchedAt: fetchedAt.addingTimeInterval(100))
        XCTAssertNil(DashboardStore.error(for: .oura))
        XCTAssertEqual(DashboardStore.updatedAt(for: .oura), fetchedAt.addingTimeInterval(100))
    }

    func testRefreshingOneSourceDoesNotMakeAnotherSourcesCacheFresh() {
        let now = Date(timeIntervalSince1970: 10000)
        DashboardStore.replaceMetrics([metric("readiness", source: .oura)], for: .oura, fetchedAt: now.addingTimeInterval(-4000))
        DashboardStore.replaceMetrics([metric("steps", source: .appleHealth)], for: .appleHealth, fetchedAt: now)

        let freshness = DashboardFreshness.stored(for: DashboardStore.metrics)
        XCTAssertEqual(freshness.oldestFetchAt, now.addingTimeInterval(-4000))
        XCTAssertTrue(freshness.isStale(at: now))
        let onlyHealth = DashboardStore.metrics.filter { $0.source == .appleHealth }
        XCTAssertFalse(DashboardFreshness.stored(for: onlyHealth).isStale(at: now))
    }

    func testFreshnessStalesAtOneHourAndImmediatelyOnFetchError() {
        let fetchedAt = Date(timeIntervalSince1970: 1000)
        let metrics = [metric("readiness", source: .oura)]
        let freshness = DashboardFreshness(metrics: metrics, updatedAtBySource: [.oura: fetchedAt], errorsBySource: [:])
        XCTAssertFalse(freshness.isStale(at: fetchedAt.addingTimeInterval(3599)))
        XCTAssertTrue(freshness.isStale(at: fetchedAt.addingTimeInterval(3600)))

        let failed = DashboardFreshness(metrics: metrics, updatedAtBySource: [.oura: fetchedAt], errorsBySource: [.oura: "Offline"])
        XCTAssertTrue(failed.hasError)
        XCTAssertTrue(failed.isStale(at: fetchedAt))
    }

    func testFreshnessDoesNotSubstituteTimelineOrMeasurementDateForFetchDate() {
        let metrics = [metric("readiness", source: .oura, observedAt: .now)]
        let unknown = DashboardFreshness(metrics: metrics, updatedAtBySource: [:], errorsBySource: [:])
        XCTAssertNil(unknown.oldestFetchAt)
        XCTAssertTrue(unknown.hasMissingFetch)
        XCTAssertTrue(unknown.isStale())

        let empty = DashboardFreshness(metrics: [], updatedAtBySource: [:], errorsBySource: [:])
        XCTAssertFalse(empty.isStale())
    }

    func testRemovingAndDeletingDataClearsSourceErrorsAndTimestamps() {
        DashboardStore.replaceMetrics([metric("readiness", source: .oura)], for: .oura)
        DashboardStore.replaceMetrics([metric("steps", source: .appleHealth)], for: .appleHealth)
        DashboardStore.recordError("Offline", for: .oura)
        DashboardStore.removeMetrics(for: .oura)
        XCTAssertNil(DashboardStore.updatedAt(for: .oura))
        XCTAssertNil(DashboardStore.error(for: .oura))
        XCTAssertEqual(DashboardStore.metrics.map(\.id), ["steps"])
        XCTAssertNotNil(DashboardStore.updatedAt(for: .appleHealth))

        DashboardStore.recordError("Offline", for: .appleHealth)
        WidgetPreferences.layout = .schedule
        WidgetPreferences.primaryMetricID = "steps"
        DashboardStore.deleteLocalData()
        XCTAssertTrue(DashboardStore.metrics.isEmpty)
        XCTAssertNil(DashboardStore.updatedAt)
        XCTAssertNil(DashboardStore.updatedAt(for: .appleHealth))
        XCTAssertNil(DashboardStore.error(for: .appleHealth))
        XCTAssertEqual(WidgetPreferences.layout, .balance)
        XCTAssertEqual(WidgetPreferences.primaryMetricID, "")
    }

    private func clearOuraPreferences() {
        UserDefaults.standard.removeObject(forKey: "oura.disconnectResult")
        (UserDefaults(suiteName: DashboardStore.appGroupID) ?? .standard).removeObject(forKey: "oura.connectionMethod")
    }

    private func metric(
        _ id: String,
        source: DataSource = .appleHealth,
        value: String = "1",
        numericValue: Double? = nil,
        targetValue: Double? = nil,
        observedAt: Date? = nil
    ) -> DashboardMetric {
        DashboardMetric(
            id: id,
            source: source,
            title: id,
            value: value,
            detail: "Test",
            symbol: "circle",
            tint: "blue",
            numericValue: numericValue,
            targetValue: targetValue,
            observedAt: observedAt
        )
    }
}
