import Combine
import Foundation
import WidgetKit

enum OuraConnectionMethod: String, CaseIterable, Identifiable {
    case appleHealth
    case direct
    var id: String { rawValue }
    var displayName: String { self == .direct ? "Oura account" : "Apple Health" }
}

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
    var directOuraAvailable: Bool { OuraConfiguration.isConfigured }

    private let connectors: [DataSource: any DashboardConnector]
    private let directOuraConnector: any DashboardConnector
    private var operationIDs: [DataSource: UUID] = [:]
    private var isResetting = false
    private var isSwitchingOura = false
    private var resetRevision = 0
    private static let methodKey = "oura.connectionMethod"
    private var preferences: UserDefaults {
        UserDefaults(suiteName: DashboardStore.appGroupID) ?? .standard
    }

    init(connectors: [any DashboardConnector]? = nil,
         directOuraConnector: (any DashboardConnector)? = nil) {
        let local = connectors ?? [HealthKitConnector(), OuraHealthConnector(), CalendarConnector()]
        self.connectors = Dictionary(uniqueKeysWithValues: local.map { ($0.source, $0) })
        self.directOuraConnector = directOuraConnector ?? OuraAPIConnector()
        let defaults = UserDefaults(suiteName: DashboardStore.appGroupID) ?? .standard
        ouraConnectionMethod = OuraConnectionMethod(rawValue: defaults.string(forKey: Self.methodKey) ?? "") ?? .appleHealth
        connectedSources = DashboardStore.connectedSources
        metrics = DashboardStore.metrics
        updatedAt = DashboardStore.updatedAt
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
        let operation = UUID()
        operationIDs[source] = operation
        activities[source] = .connecting
        do {
            try await connector.authorize()
            try Task.checkCancellation()
            guard operationIDs[source] == operation else { return }
            let newMetrics = try await connector.refresh()
            try Task.checkCancellation()
            guard operationIDs[source] == operation else { return }
            DashboardStore.replaceMetrics(newMetrics, for: source)
            connectedSources.insert(source)
            DashboardStore.connectedSources = connectedSources
            synchronizeFromStore()
            activities[source] = .idle
            WidgetCenter.shared.reloadAllTimelines()
            PulseboardBackgroundRefresh.schedule()
        } catch { handle(error, for: source, operation: operation) }
    }

    func disconnect(_ source: DataSource) async {
        guard !isResetting, activity(for: source) != .disconnecting,
              let connector = connector(for: source) else { return }
        let operation = UUID()
        operationIDs[source] = operation
        connectedSources.remove(source)
        DashboardStore.connectedSources = connectedSources
        DashboardStore.removeMetrics(for: source)
        activities[source] = .disconnecting
        synchronizeFromStore()
        WidgetCenter.shared.reloadAllTimelines()
        if connectedSources.isEmpty { PulseboardBackgroundRefresh.cancel() }
        await connector.disconnect()
        if operationIDs[source] == operation { activities[source] = .idle }
    }

    func setOuraConnectionMethod(_ method: OuraConnectionMethod) async {
        guard method != ouraConnectionMethod, !isResetting, !isSwitchingOura else { return }
        if method == .direct && !directOuraAvailable { return }
        isSwitchingOura = true
        defer { isSwitchingOura = false }
        let revision = resetRevision
        await disconnect(.oura)
        guard revision == resetRevision, !isResetting else { return }
        ouraConnectionMethod = method
        preferences.set(method.rawValue, forKey: Self.methodKey)
    }

    func refresh(_ source: DataSource) async {
        guard !isResetting, !(source == .oura && isSwitchingOura),
              connectedSources.contains(source), let connector = connector(for: source),
              !activity(for: source).isBusy else { return }
        let operation = UUID()
        operationIDs[source] = operation
        activities[source] = .refreshing
        do {
            let newMetrics = try await connector.refresh()
            try Task.checkCancellation()
            guard operationIDs[source] == operation else { return }
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

    func refreshIfNeeded(minimumInterval: TimeInterval = 300) async {
        for source in DataSource.allCases where connectedSources.contains(source) {
            guard !Task.isCancelled else { return }
            let fetchedAt = DashboardStore.updatedAt(for: source) ?? .distantPast
            if Date.now.timeIntervalSince(fetchedAt) >= minimumInterval { await refresh(source) }
        }
    }

    func deleteLocalData() async {
        guard !isResetting else { return }
        isResetting = true
        resetRevision += 1
        defer { isResetting = false }
        operationIDs.removeAll()
        // A pending authorization cannot restore a deleted snapshot.
        DashboardStore.deleteLocalData()
        preferences.removeObject(forKey: Self.methodKey)
        connectedSources = []
        metrics = []
        updatedAt = nil
        activities = [:]
        ouraConnectionMethod = .appleHealth
        PulseboardBackgroundRefresh.cancel()
        WidgetCenter.shared.reloadAllTimelines()
        // Clear credentials even if the account never finished connecting.
        await directOuraConnector.disconnect()
        for connector in connectors.values { await connector.disconnect() }
    }

    func activity(for source: DataSource) -> Activity { activities[source] ?? .idle }

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
