import Foundation
import HealthKit

final class HealthKitConnector: DashboardConnector {
    let source: DataSource = .appleHealth

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func authorize() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw ConnectorError.unavailable("Apple Health is not available on this device.")
        }
        try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    func refresh() async throws -> [DashboardMetric] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw ConnectorError.unavailable("Apple Health is not available on this device.")
        }

        async let steps = todaySteps()
        async let heart = heartMetrics()
        let results = try await (steps, heart)
        return [results.0] + results.1
    }

    func disconnect() async -> DisconnectResult {
        // iOS owns HealthKit grants. Users revoke them in Settings.
        return .localOnly
    }

    /// True when a type added in a newer version has not been offered to the
    /// user yet. Only the app can show the permission sheet.
    func needsAuthorizationRequest() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let status = try? await healthStore.statusForAuthorizationRequest(toShare: [], read: Self.readTypes)
        return status == .shouldRequest
    }

    private static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        for heart in HeartMetric.all {
            if let type = HKObjectType.quantityType(forIdentifier: heart.identifier) {
                types.insert(type)
            }
        }
        return types
    }

    /// Heart readings a tile can show; each is its own metric so every tile
    /// picks the one it wants. Denied types return no samples, not an error.
    private struct HeartMetric {
        let id: String
        let title: String
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        let unitLabel: String

        static let all: [HeartMetric] = [
            .init(id: "heart", title: "Resting heart rate", identifier: .restingHeartRate,
                  unit: .count().unitDivided(by: .minute()), unitLabel: "bpm"),
            .init(id: "heartRate", title: "Heart rate", identifier: .heartRate,
                  unit: .count().unitDivided(by: .minute()), unitLabel: "bpm"),
            .init(id: "hrv", title: "HRV", identifier: .heartRateVariabilitySDNN,
                  unit: .secondUnit(with: .milli), unitLabel: "ms"),
            .init(id: "walkingHeartRate", title: "Walking heart rate", identifier: .walkingHeartRateAverage,
                  unit: .count().unitDivided(by: .minute()), unitLabel: "bpm")
        ]
    }

    /// The queries run side by side; widget refreshes have little time.
    private func heartMetrics() async throws -> [DashboardMetric] {
        try await withThrowingTaskGroup(of: (Int, DashboardMetric).self) { group in
            for (index, heart) in HeartMetric.all.enumerated() {
                guard let type = HKQuantityType.quantityType(forIdentifier: heart.identifier) else { continue }
                group.addTask { (index, try await self.heartMetric(heart, type: type)) }
            }
            var metrics: [(Int, DashboardMetric)] = []
            for try await metric in group { metrics.append(metric) }
            return metrics.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func heartMetric(_ heart: HeartMetric, type: HKQuantityType) async throws -> DashboardMetric {
        let sample = try await latestQuantitySample(for: type)
        let value = sample?.quantity.doubleValue(for: heart.unit)
        return DashboardMetric(
            id: heart.id,
            source: .appleHealth,
            title: heart.title,
            value: value.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—",
            detail: sample.map { "\(heart.unitLabel) · \(Self.sampleTime($0.endDate))" } ?? "No measurement found",
            symbol: "heart.fill",
            tint: "pink",
            numericValue: value,
            observedAt: sample?.endDate,
            origin: sample?.sourceRevision.source.name
        )
    }

    /// A clock time today, else a date. Unlike "5 min ago", it stays correct
    /// while the widget shows a cached value.
    private static func sampleTime(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.day().month(.abbreviated))
    }

    private func todaySteps() async throws -> DashboardMetric {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw ConnectorError.unavailable("Step count is not supported on this device.")
        }
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let statistics = try await statistics(for: type, predicate: predicate, options: [.cumulativeSum, .separateBySource])
        let count = statistics?.sumQuantity()?.doubleValue(for: .count())
        let value = count?.formatted(.number.precision(.fractionLength(0))) ?? "—"
        return DashboardMetric(
            id: "steps",
            source: .appleHealth,
            title: "Steps",
            value: value,
            detail: count == nil ? "No step data available" : "Today · goal 10,000",
            symbol: "figure.walk",
            tint: "mint",
            numericValue: count,
            targetValue: 10000,
            observedAt: count == nil ? nil : .now,
            // Today's total must not be shown as tomorrow's.
            expiresAt: Calendar.current.date(byAdding: .day, value: 1, to: start),
            origin: Self.originNames(statistics?.sources)
        )
    }

    /// Health merges overlapping step samples; name every app that counted.
    private static func originNames(_ sources: [HKSource]?) -> String? {
        let names = Array(Set((sources ?? []).map(\.name))).sorted()
        return names.isEmpty ? nil : names.formatted(.list(type: .and))
    }

    private func statistics(
        for type: HKQuantityType,
        predicate: NSPredicate?,
        options: HKStatisticsOptions
    ) async throws -> HKStatistics? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
            healthStore.execute(query)
        }
    }

    private func latestQuantitySample(for type: HKQuantityType) async throws -> HKQuantitySample? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.first as? HKQuantitySample)
                }
            }
            healthStore.execute(query)
        }
    }
}
