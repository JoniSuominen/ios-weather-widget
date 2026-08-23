import Foundation
import HealthKit

final class OuraHealthConnector: DashboardConnector {
    let source: DataSource = .oura

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func authorize() async throws {
        guard HKHealthStore.isHealthDataAvailable(), let sleepType = Self.sleepType else {
            throw ConnectorError.unavailable("Apple Health sleep data is not available on this device.")
        }
        try await healthStore.requestAuthorization(toShare: [], read: Set<HKObjectType>([sleepType]))
    }

    func refresh() async throws -> [DashboardMetric] {
        guard HKHealthStore.isHealthDataAvailable(), let sleepType = Self.sleepType else {
            throw ConnectorError.unavailable("Apple Health sleep data is not available on this device.")
        }

        let start = Calendar.current.date(byAdding: .hour, value: -36, to: .now) ?? .distantPast
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let samples = try await sleepSamples(for: sleepType, predicate: predicate)
        let ouraSamples = samples.filter { sample in
            let source = sample.sourceRevision.source
            return source.name.localizedCaseInsensitiveContains("oura") ||
                source.bundleIdentifier.localizedCaseInsensitiveContains("oura")
        }
        let asleep = Self.totalDuration(of: ouraSamples.filter(Self.isAsleep))

        let sleepMetric = DashboardMetric(
            id: "sleep",
            source: .oura,
            title: "Oura sleep",
            value: asleep > 0 ? Self.durationFormatter.string(from: asleep) ?? "—" : "—",
            detail: asleep > 0 ? "Synced through Apple Health" : "No Oura sleep data found",
            symbol: "moon.stars.fill",
            tint: "indigo"
        )
        return [sleepMetric]
    }

    func disconnect() async {
        // This connector stores no token or provider account state.
    }

    private static var sleepType: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    private static func isAsleep(_ sample: HKCategorySample) -> Bool {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
        switch value {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            return true
        default:
            return false
        }
    }

    private static func totalDuration(of samples: [HKCategorySample]) -> TimeInterval {
        let intervals = samples
            .map { ($0.startDate, $0.endDate) }
            .sorted { $0.0 < $1.0 }
        guard var current = intervals.first else { return 0 }
        var total: TimeInterval = 0

        for interval in intervals.dropFirst() {
            if interval.0 <= current.1 {
                current.1 = max(current.1, interval.1)
            } else {
                total += current.1.timeIntervalSince(current.0)
                current = interval
            }
        }
        return total + current.1.timeIntervalSince(current.0)
    }

    private func sleepSamples(
        for type: HKCategoryType,
        predicate: NSPredicate
    ) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKCategorySample] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }
}
