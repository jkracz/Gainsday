import Foundation
import SyncCore

/// Keeps the HealthKit query anchor on this device only. Losing it is safe: the
/// sync start date and the ledger stop old workouts being written again.
nonisolated struct AnchorStore: WorkoutAnchorStore {
    private static let key = "workoutAnchor"
    // UserDefaults is thread-safe but not marked Sendable.
    nonisolated(unsafe) var defaults: UserDefaults = .standard

    func load() -> WorkoutAnchor? {
        defaults.data(forKey: Self.key).map(WorkoutAnchor.init)
    }

    func save(_ anchor: WorkoutAnchor) {
        defaults.set(anchor.data, forKey: Self.key)
    }
}
