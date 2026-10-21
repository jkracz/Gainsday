import Foundation

extension Settings {
    /// Why the user's filters leave a workout out, or nil when it may be synced.
    /// Tombstones and earlier syncs are checked against the ledger afterwards.
    func skipReason(for workout: Workout) -> SkipReason? {
        if !enabledTypes.contains(workout.activityType) { return .typeDisabled }
        if workout.duration < minimumDuration { return .tooShort }
        guard let syncStartDate, workout.start >= syncStartDate else { return .beforeSyncStartDate }
        return nil
    }
}
