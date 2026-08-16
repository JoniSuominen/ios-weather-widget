import Combine
import Foundation
import WidgetKit

@MainActor
final class ConnectorManager: ObservableObject {
    enum Activity: Equatable {
        case idle
        case connecting
        case refreshing
        case failed(String)

        var isBusy: Bool {
            self == .connecting || self == .refreshing
        }
    }

    @Published private(set) var connectedSources: Set<DataSource>
    @Published private(set) var metrics: [DashboardMetric]
    @Published private(set) var updatedAt: Date?
    @Published private(set) var activities: [DataSource: Activity] = [:]

    private let connectors: [DataSource: any DashboardConnector]

    init(connectors: [any DashboardConnector] = [
        HealthKitConnector(),
        OuraHealthConnector(),
        CalendarConnector()
    ]) {
        self.connectors = Dictionary(uniqueKeysWithValues: connectors.map { ($0.source, $0) })
        connectedSources = DashboardStore.connectedSources
        metrics = DashboardStore.metrics
        updatedAt = DashboardStore.updatedAt
    }

    func connect(_ source: DataSource) async {
        guard let connector = connectors[source], activities[source]?.isBusy != true else { return }
        activities[source] = .connecting
        do {
            try await connector.authorize()
            let newMetrics = try await connector.refresh()
            DashboardStore.replaceMetrics(newMetrics, for: source)
            connectedSources.insert(source)
            DashboardStore.connectedSources = connectedSources
            synchronizeFromStore()
            activities[source] = .idle
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            activities[source] = .failed(error.localizedDescription)
        }
    }

    func disconnect(_ source: DataSource) async {
        guard let connector = connectors[source], activities[source]?.isBusy != true else { return }
        await connector.disconnect()
        connectedSources.remove(source)
        DashboardStore.connectedSources = connectedSources
        DashboardStore.removeMetrics(for: source)
        activities[source] = .idle
        synchronizeFromStore()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refresh(_ source: DataSource) async {
        guard connectedSources.contains(source),
              let connector = connectors[source],
              activities[source]?.isBusy != true else { return }
        activities[source] = .refreshing
        do {
            let newMetrics = try await connector.refresh()
            DashboardStore.replaceMetrics(newMetrics, for: source)
            synchronizeFromStore()
            activities[source] = .idle
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            activities[source] = .failed(error.localizedDescription)
        }
    }

    func refreshConnectedSources() async {
        for source in connectedSources {
            await refresh(source)
        }
    }

    func deleteLocalData() async {
        for source in connectedSources {
            await connectors[source]?.disconnect()
        }
        DashboardStore.deleteLocalData()
        connectedSources = []
        metrics = []
        updatedAt = nil
        activities = [:]
        WidgetCenter.shared.reloadAllTimelines()
    }

    func activity(for source: DataSource) -> Activity {
        activities[source] ?? .idle
    }

    private func synchronizeFromStore() {
        metrics = DashboardStore.metrics
        updatedAt = DashboardStore.updatedAt
    }
}
