import Foundation
import SyncCore

/// Keeps the HealthKit query anchor on this device only. Losing it is safe: the
/// sync start date and the ledger stop old workouts being written again.
struct AnchorStore {
    private static let key = "workoutAnchor"
    var defaults: UserDefaults = .standard

    func load() -> WorkoutAnchor? {
        defaults.data(forKey: Self.key).map(WorkoutAnchor.init)
    }

    func save(_ anchor: WorkoutAnchor) {
        defaults.set(anchor.data, forKey: Self.key)
    }
}
