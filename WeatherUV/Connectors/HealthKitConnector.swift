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
        async let restingHeartRate = latestRestingHeartRate()
        let results = try await (steps, restingHeartRate)
        return [results.0, results.1]
    }

    func disconnect() async {
        // iOS owns HealthKit grants. Users revoke them in Settings.
    }

    private static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let heartRate = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(heartRate)
        }
        return types
    }

    private func todaySteps() async throws -> DashboardMetric {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw ConnectorError.unavailable("Step count is not supported on this device.")
        }
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let statistics = try await statistics(for: type, predicate: predicate, options: .cumulativeSum)
        let count = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
        let value = count.formatted(.number.precision(.fractionLength(0)))
        return DashboardMetric(
            id: "steps",
            source: .appleHealth,
            title: "Steps",
            value: value,
            detail: "Today",
            symbol: "figure.walk",
            tint: "mint"
        )
    }

    private func latestRestingHeartRate() async throws -> DashboardMetric {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            throw ConnectorError.unavailable("Resting heart rate is not supported on this device.")
        }
        let sample = try await latestQuantitySample(for: type)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let rate = sample?.quantity.doubleValue(for: unit)
        let detail = sample.map {
            "bpm · \($0.endDate.formatted(.relative(presentation: .named)))"
        } ?? "No measurement found"
        return DashboardMetric(
            id: "heart",
            source: .appleHealth,
            title: "Resting heart rate",
            value: rate.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—",
            detail: detail,
            symbol: "heart.fill",
            tint: "pink"
        )
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
