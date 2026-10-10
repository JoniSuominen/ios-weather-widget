import XCTest
@testable import WeatherUV

final class ConnectorManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DashboardStore.deleteLocalData()
    }

    override func tearDown() {
        DashboardStore.deleteLocalData()
        super.tearDown()
    }

    @MainActor
    func testForegroundRefreshSkipsFreshSourcesButUpdatesOldOnes() async {
        let health = MockDashboardConnector(source: .appleHealth)
        let calendar = MockDashboardConnector(source: .googleCalendar)
        DashboardStore.connectedSources = [.appleHealth, .googleCalendar]
        DashboardStore.replaceMetrics([health.metric], for: .appleHealth, fetchedAt: .now.addingTimeInterval(-600))
        DashboardStore.replaceMetrics([calendar.metric], for: .googleCalendar)
        let manager = ConnectorManager(connectors: [health, calendar], directOuraConnector: MockDashboardConnector(source: .oura))
        await manager.refreshIfNeeded()
        XCTAssertEqual(health.refreshCount, 1)
        XCTAssertEqual(calendar.refreshCount, 0)
    }

    @MainActor
    func testRefreshFailureKeepsCachedDataAndOriginalTimestamp() async {
        let health = MockDashboardConnector(source: .appleHealth)
        let oldDate = Date.now.addingTimeInterval(-600)
        DashboardStore.connectedSources = [.appleHealth]
        DashboardStore.replaceMetrics([health.metric], for: .appleHealth, fetchedAt: oldDate)
        health.refreshError = ConnectorError.unavailable("Health data is unavailable")
        let manager = ConnectorManager(connectors: [health], directOuraConnector: MockDashboardConnector(source: .oura))
        await manager.refresh(.appleHealth)
        XCTAssertEqual(manager.metrics, [health.metric])
        XCTAssertEqual(DashboardStore.updatedAt(for: .appleHealth), oldDate)
        XCTAssertEqual(DashboardStore.error(for: .appleHealth), "Health data is unavailable")
        XCTAssertEqual(manager.activity(for: .appleHealth), .failed("Health data is unavailable"))
        health.refreshError = nil
        await manager.refresh(.appleHealth)
        XCTAssertNil(DashboardStore.error(for: .appleHealth))
        XCTAssertEqual(manager.activity(for: .appleHealth), .idle)
    }

    @MainActor
    func testDeleteDuringAuthorizationCannotRestoreData() async {
        let health = MockDashboardConnector(source: .appleHealth)
        let direct = MockDashboardConnector(source: .oura)
        let started = expectation(description: "Authorization started")
        health.holdAuthorization = true
        health.onAuthorize = { started.fulfill() }
        let manager = ConnectorManager(connectors: [health], directOuraConnector: direct)
        let connecting = Task { await manager.connect(.appleHealth) }
        await fulfillment(of: [started], timeout: 2)
        await manager.deleteLocalData()
        health.resumeAuthorization()
        await connecting.value
        XCTAssertTrue(manager.metrics.isEmpty)
        XCTAssertTrue(manager.connectedSources.isEmpty)
        XCTAssertTrue(DashboardStore.metrics.isEmpty)
        XCTAssertEqual(health.refreshCount, 0)
        XCTAssertEqual(direct.disconnectCount, 1, "Tokens must be cleared even if Oura was never marked connected")
    }

    @MainActor
    func testDisconnectDuringRefreshCannotRestoreSnapshot() async {
        let health = MockDashboardConnector(source: .appleHealth)
        DashboardStore.connectedSources = [.appleHealth]
        DashboardStore.replaceMetrics([health.metric], for: .appleHealth)
        let started = expectation(description: "Refresh started")
        health.holdRefresh = true
        health.onRefresh = { started.fulfill() }
        let manager = ConnectorManager(connectors: [health], directOuraConnector: MockDashboardConnector(source: .oura))
        let refreshing = Task { await manager.refresh(.appleHealth) }
        await fulfillment(of: [started], timeout: 2)
        await manager.disconnect(.appleHealth)
        health.resumeRefresh()
        await refreshing.value
        XCTAssertTrue(manager.metrics.isEmpty)
        XCTAssertTrue(DashboardStore.metrics.isEmpty)
        XCTAssertFalse(manager.connectedSources.contains(.appleHealth))
    }
}

@MainActor
private final class MockDashboardConnector: DashboardConnector {
    let source: DataSource
    var refreshCount = 0
    var disconnectCount = 0
    var refreshError: Error?
    var holdAuthorization = false
    var holdRefresh = false
    var onAuthorize: (() -> Void)?
    var onRefresh: (() -> Void)?
    private var authorization: CheckedContinuation<Void, Never>?
    private var refreshContinuation: CheckedContinuation<Void, Never>?

    init(source: DataSource) { self.source = source }
    var metric: DashboardMetric {
        DashboardMetric(id: source == .googleCalendar ? "nextEvent" : "steps", source: source,
                        title: "Test", value: "42", detail: "Live", symbol: "circle", tint: "blue")
    }
    func authorize() async throws {
        if holdAuthorization {
            await withCheckedContinuation { continuation in
                authorization = continuation
                onAuthorize?()
            }
        } else { onAuthorize?() }
    }
    func refresh() async throws -> [DashboardMetric] {
        refreshCount += 1
        if holdRefresh {
            await withCheckedContinuation { continuation in
                refreshContinuation = continuation
                onRefresh?()
            }
        } else { onRefresh?() }
        if let refreshError { throw refreshError }
        return [metric]
    }
    func disconnect() async { disconnectCount += 1 }
    func resumeAuthorization() { authorization?.resume(); authorization = nil }
    func resumeRefresh() { refreshContinuation?.resume(); refreshContinuation = nil }
}
