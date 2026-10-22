import Foundation
import HealthKit
import SyncCore

/// Reads workouts and their metrics from HealthKit. Read only: the app never writes to Health.
nonisolated final class HealthKitWorkoutSource: WorkoutSource {
    /// Thrown instead of touching HealthKit on devices without it, such as some iPads.
    struct Unavailable: LocalizedError {
        var errorDescription: String? { String(localized: "Health isn't available on this device.") }
    }

    let isHealthDataAvailable: Bool
    private let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore(), isHealthDataAvailable: Bool = HKHealthStore.isHealthDataAvailable()) {
        self.store = store
        self.isHealthDataAvailable = isHealthDataAvailable
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
        try requireHealthData()
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    /// Lets Health launch or wake the app as soon as a workout is saved. The setting
    /// persists, so calling this again on later launches is harmless.
    func enableBackgroundDelivery() async throws {
        try requireHealthData()
        try await store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate)
    }

    /// Calls `onChange` when workouts are added or deleted in Health, including when
    /// Health launches the app in the background. Start this early in launch, or a
    /// background launch isn't delivered. `onChange` must call `finished` once it has
    /// synced, or Health wakes the app less often.
    func observeWorkouts(onChange: @escaping @Sendable (_ finished: @escaping @Sendable () -> Void) -> Void) {
        guard isHealthDataAvailable else { return }
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { _, completionHandler, error in
            guard error == nil else { return completionHandler() }
            // HealthKit lets the handler be called from any thread, but doesn't mark it Sendable.
            nonisolated(unsafe) let completionHandler = completionHandler
            onChange { completionHandler() }
        }
        store.execute(query)
    }

    func changes(since anchor: WorkoutAnchor?) async throws -> WorkoutChanges {
        try requireHealthData()
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout()],
            anchor: anchor.flatMap(Self.queryAnchor)
        )
        let result = try await Self.mappingAccessErrors { try await descriptor.result(for: store) }
        return WorkoutChanges(
            added: result.addedSamples.map(Self.workout),
            deletedIDs: result.deletedObjects.map { $0.uuid },
            anchor: try Self.workoutAnchor(result.newAnchor)
        )
    }

    func workouts(in interval: DateInterval) async throws -> [Workout] {
        try requireHealthData()
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await Self.mappingAccessErrors { try await descriptor.result(for: store) }.map(Self.workout)
    }

    func recentWorkouts(limit: Int) async throws -> [Workout] {
        try requireHealthData()
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout()],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: limit
        )
        return try await Self.mappingAccessErrors { try await descriptor.result(for: store) }.map(Self.workout)
    }

    private func requireHealthData() throws {
        guard isHealthDataAvailable else { throw Unavailable() }
    }

    /// Reports HealthKit's authorization errors as `WorkoutSourceError.accessDenied`,
    /// and its locked-phone error as `.locked`, for every Health read, so a pass that
    /// finds the phone locked runs again on unlock. HealthKit usually hides denied read
    /// access by returning no results instead.
    static func mappingAccessErrors<T>(_ read: () async throws -> T) async throws -> T {
        do {
            return try await read()
        } catch let error as HKError where [.errorAuthorizationDenied, .errorAuthorizationNotDetermined].contains(error.code) {
            throw WorkoutSourceError.accessDenied
        } catch let error as HKError where error.code == .errorDatabaseInaccessible {
            throw WorkoutSourceError.locked
        }
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
