import Combine
import Foundation
import WidgetKit

@MainActor
final class ConnectorManager: ObservableObject {
    static let shared = ConnectorManager()

    enum Activity: Equatable {
        case idle
        case connecting
        case refreshing
        case disconnecting
        case failed(String)
        var isBusy: Bool { self == .connecting || self == .refreshing || self == .disconnecting }
    }

    @Published private(set) var connectedSources: Set<DataSource>
    @Published private(set) var metrics: [DashboardMetric]
    @Published private(set) var updatedAt: Date?
    @Published private(set) var activities: [DataSource: Activity] = [:]
    @Published private(set) var ouraConnectionMethod: OuraConnectionMethod
    @Published private(set) var disconnectResults: [DataSource: DisconnectResult] = [:]
    @Published private(set) var dataDeletionResult: DisconnectResult?
    @Published private(set) var isDeletingLocalData = false
    var directOuraAvailable: Bool { OuraConfiguration.isConfigured }

    private let connectors: [DataSource: any DashboardConnector]
    private let directOuraConnector: any DashboardConnector
    private var operationIDs: [DataSource: UUID] = [:]
    private var isResetting = false
    private var isSwitchingOura = false
    private var resetRevision = 0
    private static let methodKey = OuraConnectionMethod.preferenceKey
    // Retain only cleanup status, never account identifiers or credentials. A
    // failed Keychain deletion must remain visible after relaunching the app.
    private static let disconnectResultKey = "oura.disconnectResult"
    private var preferences: UserDefaults {
        UserDefaults(suiteName: DashboardStore.appGroupID) ?? .standard
    }

    init(connectors: [any DashboardConnector]? = nil,
         directOuraConnector: (any DashboardConnector)? = nil) {
        let local = connectors ?? [WeatherConnector(locator: DeviceLocator()), HealthKitConnector(), OuraHealthConnector(), CalendarConnector()]
        self.connectors = Dictionary(uniqueKeysWithValues: local.map { ($0.source, $0) })
        self.directOuraConnector = directOuraConnector ?? OuraAPIConnector()
        let defaults = UserDefaults(suiteName: DashboardStore.appGroupID) ?? .standard
        ouraConnectionMethod = OuraConnectionMethod(rawValue: defaults.string(forKey: Self.methodKey) ?? "") ?? .appleHealth
        // Permission can be revoked while the app is closed. Clear the private
        // snapshot before publishing it, regardless of its fetch age.
        _ = local.compactMap { $0 as? CalendarConnector }.first?.clearSnapshotIfAccessUnavailable()
        connectedSources = DashboardStore.connectedSources
        metrics = DashboardStore.metrics
        updatedAt = DashboardStore.updatedAt
        if let data = UserDefaults.standard.data(forKey: Self.disconnectResultKey),
           let result = try? JSONDecoder().decode(DisconnectResult.self, from: data) {
            disconnectResults[.oura] = result
        }
        for source in connectedSources {
            if let error = DashboardStore.error(for: source) { activities[source] = .failed(error) }
        }
    }

    private func connector(for source: DataSource) -> (any DashboardConnector)? {
        source == .oura && ouraConnectionMethod == .direct ? directOuraConnector : connectors[source]
    }

    func connect(_ source: DataSource) async {
        guard !isResetting, !(source == .oura && isSwitchingOura),
              let connector = connector(for: source), !activity(for: source).isBusy else { return }
        if source == .oura, let result = disconnectResults[.oura], !result.localCredentialsCleared {
            activities[source] = .failed(result.statusMessage)
            return
        }
        let operation = UUID()
        let calendarRevision = CalendarPreferences.revision
        operationIDs[source] = operation
        activities[source] = .connecting
        do {
            try await connector.authorize()
            try Task.checkCancellation()
            guard canPublish(source, operation: operation, calendarRevision: calendarRevision) else { return }
            let newMetrics = try await connector.refresh()
            try Task.checkCancellation()
            guard canPublish(source, operation: operation, calendarRevision: calendarRevision) else { return }
            DashboardStore.replaceMetrics(newMetrics, for: source)
            connectedSources.insert(source)
            DashboardStore.connectedSources = connectedSources
            synchronizeFromStore()
            if source != .oura || ouraConnectionMethod == .direct ||
                disconnectResults[.oura]?.remoteAuthorization == .notApplicable {
                disconnectResults.removeValue(forKey: source)
            }
            if source == .oura && ouraConnectionMethod == .direct {
                UserDefaults.standard.removeObject(forKey: Self.disconnectResultKey)
                dataDeletionResult = nil
            }
            activities[source] = .idle
            WidgetCenter.shared.reloadAllTimelines()
            PulseboardBackgroundRefresh.schedule()
        } catch { handle(error, for: source, operation: operation) }
    }

    func disconnect(_ source: DataSource) async {
        guard !isResetting, activity(for: source) != .disconnecting,
              let connector = connector(for: source) else { return }
        await disconnect(source, using: connector)
    }

    private func disconnect(_ source: DataSource, using connector: any DashboardConnector) async {
        let operation = UUID()
        operationIDs[source] = operation
        connectedSources.remove(source)
        DashboardStore.connectedSources = connectedSources
        DashboardStore.removeMetrics(for: source)
        activities[source] = .disconnecting
        synchronizeFromStore()
        WidgetCenter.shared.reloadAllTimelines()
        if connectedSources.isEmpty { PulseboardBackgroundRefresh.cancel() }
        let result = await connector.disconnect()
        guard operationIDs[source] == operation else { return }
        record(result, for: source)
        activities[source] = .idle
    }

    func retryOuraDisconnection() async {
        guard !isResetting, !isSwitchingOura, !activity(for: .oura).isBusy else { return }
        // Deletion resets the selected method to Apple Health, but any failed
        // cleanup still belongs to the direct-account Keychain and broker.
        await disconnect(.oura, using: directOuraConnector)
        if dataDeletionResult != nil { dataDeletionResult = disconnectResults[.oura] }
    }

    func setOuraConnectionMethod(_ method: OuraConnectionMethod) async {
        guard method != ouraConnectionMethod, !isResetting, !isSwitchingOura else { return }
        guard disconnectResults[.oura]?.localCredentialsCleared != false else { return }
        if method == .direct && !directOuraAvailable { return }
        isSwitchingOura = true
        defer { isSwitchingOura = false }
        let revision = resetRevision
        await disconnect(.oura)
        guard revision == resetRevision, !isResetting else { return }
        guard disconnectResults[.oura]?.localCredentialsCleared != false else { return }
        ouraConnectionMethod = method
        preferences.set(method.rawValue, forKey: Self.methodKey)
    }

    func refresh(_ source: DataSource) async {
        guard !isResetting, !(source == .oura && isSwitchingOura),
              connectedSources.contains(source), let connector = connector(for: source),
              !activity(for: source).isBusy else { return }
        let operation = UUID()
        let calendarRevision = CalendarPreferences.revision
        operationIDs[source] = operation
        activities[source] = .refreshing
        do {
            let newMetrics = try await connector.refresh()
            try Task.checkCancellation()
            guard canPublish(source, operation: operation, calendarRevision: calendarRevision) else { return }
            DashboardStore.replaceMetrics(newMetrics, for: source)
            synchronizeFromStore()
            activities[source] = .idle
            WidgetCenter.shared.reloadAllTimelines()
        } catch { handle(error, for: source, operation: operation) }
    }

    func refreshConnectedSources() async {
        for source in DataSource.allCases where connectedSources.contains(source) {
            if Task.isCancelled { break }
            await refresh(source)
        }
    }

    /// Picks a city, or nil for the device location, then fetches its forecast.
    func setWeatherLocation(_ location: WeatherLocation?) async {
        guard !isResetting, !activity(for: .weather).isBusy else { return }
        if let location {
            WeatherLocationStore.save(location)
        } else {
            WeatherLocationStore.clear()
        }
        if connectedSources.contains(.weather) {
            await refresh(.weather)
        } else {
            await connect(.weather)
        }
    }

    /// Widgets refresh the shared cache on their own; show what they fetched.
    func reloadFromStore() {
        synchronizeFromStore()
        for source in connectedSources where !activity(for: source).isBusy {
            if let error = DashboardStore.error(for: source) {
                activities[source] = .failed(error)
            } else if case .failed = activity(for: source) {
                activities[source] = .idle
            }
        }
    }

    func refreshIfNeeded(minimumInterval: TimeInterval = 300) async {
        reloadFromStore()
        if let calendar = connectors[.googleCalendar] as? CalendarConnector,
           calendar.clearSnapshotIfAccessUnavailable() {
            calendarPreferencesDidChange()
        }
        for source in DataSource.allCases where connectedSources.contains(source) {
            guard !Task.isCancelled else { return }
            let fetchedAt = DashboardStore.updatedAt(for: source) ?? .distantPast
            if Date.now.timeIntervalSince(fetchedAt) >= minimumInterval { await refresh(source) }
        }
    }

    func deleteLocalData() async {
        guard !isResetting else { return }
        isResetting = true
        isDeletingLocalData = true
        resetRevision += 1
        defer {
            isResetting = false
            isDeletingLocalData = false
        }
        operationIDs.removeAll()
        // A pending authorization cannot restore a deleted snapshot.
        DashboardStore.deleteLocalData()
        preferences.removeObject(forKey: Self.methodKey)
        connectedSources = []
        metrics = []
        updatedAt = nil
        activities = [:]
        disconnectResults = [:]
        dataDeletionResult = nil
        ouraConnectionMethod = .appleHealth
        PulseboardBackgroundRefresh.cancel()
        WidgetCenter.shared.reloadAllTimelines()
        // Clear credentials even if the account never finished connecting.
        let result = await directOuraConnector.disconnect()
        dataDeletionResult = result
        record(result, for: .oura)
        for connector in connectors.values { _ = await connector.disconnect() }
    }

    func calendarPreferencesDidChange() {
        operationIDs[.googleCalendar] = UUID()
        activities[.googleCalendar] = .idle
        synchronizeFromStore()
    }

    func applyCalendarPreferences() async {
        calendarPreferencesDidChange()
        await refresh(.googleCalendar)
    }

    func activity(for source: DataSource) -> Activity { activities[source] ?? .idle }

    private func canPublish(_ source: DataSource, operation: UUID, calendarRevision: Int) -> Bool {
        guard operationIDs[source] == operation else { return false }
        guard source != .googleCalendar || calendarRevision == CalendarPreferences.revision else {
            activities[source] = .idle
            synchronizeFromStore()
            return false
        }
        return true
    }

    private func record(_ result: DisconnectResult, for source: DataSource) {
        // Disconnecting the HealthKit projection says nothing about a previous
        // direct account's credentials or remote grant.
        if source == .oura, result.remoteAuthorization == .notApplicable,
           let previous = disconnectResults[.oura], previous.remoteAuthorization != .notApplicable { return }
        disconnectResults[source] = result
        if source == .oura, let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: Self.disconnectResultKey)
        }
    }

    private func handle(_ error: Error, for source: DataSource, operation: UUID) {
        guard operationIDs[source] == operation else { return }
        if error is CancellationError {
            activities[source] = .idle
        } else {
            activities[source] = .failed(error.localizedDescription)
            DashboardStore.recordError(error.localizedDescription, for: source)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func synchronizeFromStore() {
        metrics = DashboardStore.metrics
        updatedAt = DashboardStore.updatedAt
    }
}
