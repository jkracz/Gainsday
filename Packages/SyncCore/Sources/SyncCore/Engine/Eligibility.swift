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

    /// Splits workouts into those from sources the allowlist lets in and the rest.
    /// With no allowlist, or an empty one, every source is allowed.
    func splitBySource(_ workouts: [Workout]) -> (allowed: [Workout], notAllowed: [Workout]) {
        guard let sourceAllowlist, !sourceAllowlist.isEmpty else { return (workouts, []) }
        let allowed = workouts.filter { sourceAllowlist.contains($0.source.bundleIdentifier) }
        return (allowed, workouts.filter { !sourceAllowlist.contains($0.source.bundleIdentifier) })
    }
}
