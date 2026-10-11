import Foundation
import XCTest
@testable import WeatherUV

final class WidgetPrivacyTests: XCTestCase {
    private var previousLayout: WidgetLayout = .balance
    private var previousPrimaryMetricID = ""

    override func setUp() {
        super.setUp()
        previousLayout = WidgetPreferences.layout
        previousPrimaryMetricID = WidgetPreferences.primaryMetricID
    }

    override func tearDown() {
        WidgetPreferences.layout = previousLayout
        WidgetPreferences.primaryMetricID = previousPrimaryMetricID
        super.tearDown()
    }

    func testNewLockWidgetKeepsHealthValuesPrivate() {
        let configuration = LockWidgetIntent().instanceConfiguration
        XCTAssertEqual(configuration, .lockDefault)
        XCTAssertEqual(configuration.layout, .balance)
        XCTAssertEqual(configuration.primaryMetricID, "")
        XCTAssertEqual(configuration.privacyMode, .discreet)

        let rendered = configuration.renderedMetrics([healthMetric("readiness")])
        XCTAssertEqual(rendered.first?.value, "Hidden")
        XCTAssertNil(rendered.first?.gaugeProgress)
    }

    func testNewHomeWidgetShowsHealthValuesByDefault() {
        let configuration = HomeWidgetIntent().instanceConfiguration
        XCTAssertEqual(configuration, .homeDefault)
        XCTAssertEqual(configuration.layout, .balance)
        XCTAssertEqual(configuration.primaryMetricID, "")
        XCTAssertEqual(configuration.privacyMode, .showValues)

        let original = healthMetric("readiness")
        let rendered = configuration.renderedMetrics([original])
        XCTAssertEqual(rendered.first?.value, original.value)
        XCTAssertEqual(rendered.first?.numericValue, original.numericValue)
    }

    func testLockWidgetRequiresAnExplicitOptInToShowHealthValues() {
        var intent = LockWidgetIntent()
        intent.privacyMode = .showValues

        let original = healthMetric("readiness")
        let configuration = intent.instanceConfiguration
        XCTAssertEqual(configuration.privacyMode, .showValues)
        XCTAssertEqual(configuration.renderedMetrics([original]).first?.value, original.value)
        XCTAssertEqual(LockWidgetIntent().instanceConfiguration.privacyMode, .discreet)
    }

    func testUnspecifiedInstancePrivacyIsConservative() {
        XCTAssertEqual(WidgetInstanceConfiguration().privacyMode, .discreet)
        XCTAssertEqual(WidgetInstanceConfiguration(layout: .schedule, primaryMetricID: "steps").privacyMode, .discreet)
    }

    func testIntentParametersDescribeOnlyTheConfiguredWidget() {
        var home = HomeWidgetIntent()
        home.layout = .schedule
        home.primaryMetric = .steps
        home.privacyMode = .discreet
        var lock = LockWidgetIntent()
        lock.layout = .recovery
        lock.primaryMetric = .sleep
        lock.privacyMode = .showValues

        XCTAssertEqual(home.instanceConfiguration, WidgetInstanceConfiguration(layout: .schedule, primaryMetricID: "steps", privacyMode: .discreet))
        XCTAssertEqual(lock.instanceConfiguration, WidgetInstanceConfiguration(layout: .recovery, primaryMetricID: "sleep", privacyMode: .showValues))
        XCTAssertEqual(HomeWidgetIntent().instanceConfiguration, .homeDefault)
        XCTAssertEqual(LockWidgetIntent().instanceConfiguration, .lockDefault)
    }

    func testEachWidgetKeepsItsOwnLayoutAndPrimaryMetricWhenAppPreferencesChange() {
        let schedule = WidgetInstanceConfiguration(layout: .schedule, privacyMode: .showValues)
        let recovery = WidgetInstanceConfiguration(layout: .recovery, primaryMetricID: "sleep", privacyMode: .discreet)
        let metrics = [
            healthMetric("steps", source: .appleHealth),
            calendarMetric(),
            healthMetric("heart", source: .appleHealth),
            healthMetric("readiness"),
            healthMetric("sleep")
        ]

        WidgetPreferences.layout = .balance
        WidgetPreferences.primaryMetricID = "heart"
        let scheduleOrder = schedule.orderedMetrics(metrics).map(\.id)
        let recoveryOrder = recovery.orderedMetrics(metrics).map(\.id)
        XCTAssertEqual(scheduleOrder.first, "nextEvent")
        XCTAssertEqual(recoveryOrder.first, "sleep")
        XCTAssertNotEqual(scheduleOrder, recoveryOrder)

        WidgetPreferences.layout = .recovery
        WidgetPreferences.primaryMetricID = "steps"
        XCTAssertEqual(schedule.orderedMetrics(metrics).map(\.id), scheduleOrder)
        XCTAssertEqual(recovery.orderedMetrics(metrics).map(\.id), recoveryOrder)
        XCTAssertEqual(schedule.renderedMetrics(metrics).map(\.id), scheduleOrder)
        XCTAssertEqual(recovery.renderedMetrics(metrics).map(\.id), recoveryOrder)
        XCTAssertEqual(recovery.renderedMetrics(metrics).first?.value, "Hidden")
    }

    func testMissingInstancePrimaryFallsBackToThatInstancesLayout() {
        WidgetPreferences.layout = .balance
        WidgetPreferences.primaryMetricID = "steps"
        let configuration = WidgetInstanceConfiguration(layout: .schedule, primaryMetricID: "removedMetric")
        let metrics = [healthMetric("steps", source: .appleHealth), calendarMetric()]
        XCTAssertEqual(configuration.orderedMetrics(metrics).first?.id, "nextEvent")
        XCTAssertTrue(configuration.renderedMetrics([]).isEmpty)
    }

    func testMetricChoicesUseStableCacheIDsAndAutomaticNeedsNoPrimary() {
        let choices: [(WidgetMetricChoice, String)] = [
            (.automatic, ""), (.readiness, "readiness"), (.sleep, "sleep"),
            (.steps, "steps"), (.heart, "heart"), (.nextEvent, "nextEvent")
        ]
        for (choice, expectedID) in choices {
            XCTAssertEqual(choice.metricID, expectedID)
        }
    }

    func testDiscreetHealthRemovesValuesAndAllIndirectValueChannels() throws {
        let metrics = [
            healthMetric("readiness"), healthMetric("sleep"),
            healthMetric("steps", source: .appleHealth), healthMetric("heart", source: .appleHealth)
        ]
        let expectedTitles = ["readiness": "Readiness", "sleep": "Sleep", "steps": "Steps", "heart": "Resting heart rate"]
        let rendered = WidgetPrivacy.render(metrics, mode: .discreet)
        XCTAssertEqual(rendered.count, metrics.count)

        for (original, safe) in zip(metrics, rendered) {
            XCTAssertEqual(safe.id, original.id)
            XCTAssertEqual(safe.source, original.source)
            XCTAssertEqual(safe.title, expectedTitles[original.id])
            XCTAssertEqual(safe.value, "Hidden")
            XCTAssertEqual(safe.detail, "Open app for value")
            XCTAssertEqual(safe.tint, "gray")
            XCTAssertNil(safe.numericValue)
            XCTAssertNil(safe.targetValue)
            XCTAssertNil(safe.observedAt)
            XCTAssertNil(safe.privateValue)
            XCTAssertNil(safe.gaugeProgress)
        }
        let encoded = String(decoding: try JSONEncoder().encode(rendered), as: UTF8.self)
        XCTAssertFalse(encoded.contains("SECRET"), "Redacted widget data must not carry hidden values in another field")
        XCTAssertEqual(metrics.first?.value, "SECRET health value", "Rendering must not alter the source snapshot")
    }

    func testDiscreetUnknownHealthMetricAlsoHidesValue() {
        let original = healthMetric("futureHealthMetric")
        let rendered = WidgetPrivacy.render([original], mode: .discreet)
        XCTAssertEqual(rendered.first?.value, "Hidden")
        XCTAssertFalse(rendered.first?.title.contains("SECRET") ?? true)
        XCTAssertNil(rendered.first?.gaugeProgress)
        XCTAssertNil(rendered.first?.privateValue)
    }

    func testShowingHealthValuesPreservesMeasurementAndGaugeMetadata() {
        let original = healthMetric("readiness")
        let rendered = WidgetPrivacy.render([original], mode: .showValues)
        XCTAssertEqual(rendered.first?.value, original.value)
        XCTAssertEqual(rendered.first?.detail, original.detail)
        XCTAssertEqual(rendered.first?.numericValue, original.numericValue)
        XCTAssertEqual(rendered.first?.targetValue, original.targetValue)
        XCTAssertEqual(rendered.first?.observedAt, original.observedAt)
        XCTAssertEqual(rendered.first?.tint, original.tint)
        XCTAssertEqual(rendered.first?.gaugeProgress, original.gaugeProgress)
    }

    func testCalendarTitleNeedsBothSourceAndWidgetOptIn() {
        let optedIn = calendarMetric(privateValue: "Confidential strategy meeting")
        let discreet = WidgetPrivacy.render([optedIn], mode: .discreet)
        XCTAssertEqual(discreet.first?.value, "Busy")
        XCTAssertNil(discreet.first?.privateValue)

        let shown = WidgetPrivacy.render([optedIn], mode: .showValues)
        XCTAssertEqual(shown.first?.value, "Confidential strategy meeting")
        XCTAssertNil(shown.first?.privateValue)
        XCTAssertFalse(shown.first?.detail.contains("SECRET") ?? true)

        let sourceNotOptedIn = WidgetPrivacy.render([calendarMetric()], mode: .showValues)
        XCTAssertEqual(sourceNotOptedIn.first?.value, "Busy")
        XCTAssertNil(sourceNotOptedIn.first?.privateValue)
    }

    func testEmptyCalendarOptInDoesNotExposeLegacyTitle() {
        for privateValue in ["", "   "] {
            let shown = WidgetPrivacy.render([calendarMetric(privateValue: privateValue)], mode: .showValues)
            XCTAssertEqual(shown.first?.value, "Busy")
            XCTAssertNil(shown.first?.privateValue)
        }
    }

    func testNoUpcomingEventsRemainsUsefulWithoutExposingAnEventTitle() {
        let metric = calendarMetric(value: "No upcoming events")
        for mode in [WidgetPrivacyMode.discreet, .showValues] {
            let rendered = WidgetPrivacy.render([metric], mode: mode)
            XCTAssertEqual(rendered.first?.value, "No upcoming events")
            XCTAssertNil(rendered.first?.privateValue)
            XCTAssertFalse(rendered.first?.detail.contains("SECRET") ?? true)
        }
    }

    func testCalendarTimeMetadataNeverReusesLegacyConfidentialDetails() {
        let original = calendarMetric(observedAt: Date(timeIntervalSince1970: 1_800_000_000))
        for mode in [WidgetPrivacyMode.discreet, .showValues] {
            let rendered = WidgetPrivacy.render([original], mode: mode)
            XCTAssertEqual(rendered.first?.title, "Up next")
            XCTAssertEqual(rendered.first?.value, "Busy")
            XCTAssertFalse(rendered.first?.detail.contains("SECRET") ?? true)
            XCTAssertNil(rendered.first?.privateValue)
        }
    }

    func testPrePrivacyCacheDecodesAndCannotLeakLegacyTitlesOrDetails() throws {
        let json = """
        [
          {"id":"readiness","source":"Oura","title":"SECRET health title","value":"86","detail":"SECRET health detail","symbol":"sparkles","tint":"violet"},
          {"id":"nextEvent","source":"Google Calendar","title":"SECRET calendar title","value":"SECRET calendar event","detail":"SECRET calendar location","symbol":"calendar","tint":"blue"}
        ]
        """
        let oldMetrics = try JSONDecoder().decode([DashboardMetric].self, from: Data(json.utf8))
        XCTAssertNil(oldMetrics.first?.privateValue)

        let discreet = WidgetPrivacy.render(oldMetrics, mode: .discreet)
        XCTAssertEqual(discreet.map(\.title), ["Readiness", "Up next"])
        XCTAssertEqual(discreet.map(\.value), ["Hidden", "Busy"])
        let encoded = String(decoding: try JSONEncoder().encode(discreet), as: UTF8.self)
        XCTAssertFalse(encoded.contains("SECRET"))

        let shownCalendar = WidgetPrivacy.render(oldMetrics.filter { $0.source == .googleCalendar }, mode: .showValues)
        XCTAssertEqual(shownCalendar.first?.value, "Busy")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(shownCalendar), as: UTF8.self).contains("SECRET"))
    }

    private func healthMetric(_ id: String, source: DataSource = .oura) -> DashboardMetric {
        DashboardMetric(
            id: id, source: source, title: "SECRET health title", value: "SECRET health value",
            detail: "SECRET health detail", symbol: "heart.fill", tint: "pink",
            numericValue: 86, targetValue: 100, observedAt: Date(timeIntervalSince1970: 1_800_000_000),
            privateValue: "SECRET hidden health value"
        )
    }

    private func calendarMetric(
        value: String = "SECRET legacy calendar event",
        privateValue: String? = nil,
        observedAt: Date? = nil
    ) -> DashboardMetric {
        DashboardMetric(
            id: "nextEvent", source: .googleCalendar, title: "SECRET calendar title", value: value,
            detail: "SECRET calendar location", symbol: "calendar", tint: "blue",
            observedAt: observedAt, privateValue: privateValue
        )
    }
}
