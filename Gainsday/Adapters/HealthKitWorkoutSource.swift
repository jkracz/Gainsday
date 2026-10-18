import Foundation
import HealthKit
import SyncCore

/// Reads workouts and their metrics from HealthKit. Read only: the app never writes to Health.
nonisolated final class HealthKitWorkoutSource: WorkoutSource {
    private let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    /// Workouts plus the metrics events can show. Route and location are deliberately absent.
    static let readTypes: Set<HKObjectType> = [
        .workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceCycling),
        HKQuantityType(.distanceSwimming),
    ]

    /// Shows the Health permission sheet. HealthKit never reveals whether read
    /// access was granted, so this only throws if the sheet couldn't be shown.
    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    func changes(since anchor: WorkoutAnchor?) async throws -> WorkoutChanges {
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout()],
            anchor: anchor.flatMap(Self.queryAnchor)
        )
        let result = try await descriptor.result(for: store)
        return WorkoutChanges(
            added: result.addedSamples.map(Self.workout),
            deletedIDs: result.deletedObjects.map { $0.uuid },
            anchor: try Self.workoutAnchor(result.newAnchor)
        )
    }

    func workouts(in interval: DateInterval) async throws -> [Workout] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).map(Self.workout)
    }

    func recentWorkouts(limit: Int) async throws -> [Workout] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout()],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: limit
        )
        return try await descriptor.result(for: store).map(Self.workout)
    }

    private static func workout(_ sample: HKWorkout) -> Workout {
        let source = sample.sourceRevision.source
        return Workout(
            id: sample.uuid,
            activityType: WorkoutActivityType(rawValue: sample.workoutActivityType.rawValue),
            start: sample.startDate,
            end: sample.endDate,
            source: WorkoutSourceApp(bundleIdentifier: source.bundleIdentifier, name: source.name),
            metrics: metrics(of: sample)
        )
    }

    private static func metrics(of sample: HKWorkout) -> WorkoutMetrics {
        func sum(_ identifier: HKQuantityTypeIdentifier, in unit: HKUnit) -> Double? {
            sample.statistics(for: HKQuantityType(identifier))?.sumQuantity()?.doubleValue(for: unit)
        }
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        let heartRate = sample.statistics(for: HKQuantityType(.heartRate))
        let elevation = sample.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity
        return WorkoutMetrics(
            distanceMeters: [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
                .lazy.compactMap { sum($0, in: .meter()) }.first,
            activeEnergyKilocalories: sum(.activeEnergyBurned, in: .kilocalorie()),
            averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: beatsPerMinute),
            maxHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: beatsPerMinute),
            elevationAscendedMeters: elevation?.doubleValue(for: .meter())
        )
    }

    private static func workoutAnchor(_ anchor: HKQueryAnchor) throws -> WorkoutAnchor {
        WorkoutAnchor(data: try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true))
    }

    /// An anchor that can't be read is treated as lost, which is safe, rather than failing every pass.
    private static func queryAnchor(_ anchor: WorkoutAnchor) -> HKQueryAnchor? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: anchor.data)
    }
}
