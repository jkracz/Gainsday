import Foundation

extension SyncEngine {
    /// Follows workouts deleted in Health.
    ///
    /// HealthKit workouts are immutable, so an edit, merge or re-import arrives as a
    /// delete plus an add. When an added workout overlaps a deleted one in the same
    /// pass, it replaces it: the existing event is updated in place.
    ///
    /// Returns the actions taken and the added workouts that still need syncing.
    func followDeletions(
        in changes: WorkoutChanges,
        composer: EventComposer
    ) async throws -> (actions: [SyncAction], remaining: [Workout]) {
        var actions: [SyncAction] = []
        var remaining = changes.added
        for workoutID in changes.deletedIDs {
            for entry in try await ledger.entries(forWorkout: workoutID) where entry.state == .owned {
                guard let eventID = entry.eventExternalIdentifier else { continue }
                if let index = try await replacementIndex(for: entry, in: remaining) {
                    let replacement = remaining.remove(at: index)
                    actions.append(try await replace(workoutID, with: replacement, in: entry, eventID: eventID, composer: composer))
                } else {
                    try await calendar.delete(eventID: eventID)
                    try await ledger.delete(entryID: entry.id)
                    actions.append(.delete(workoutID: workoutID, eventID: eventID))
                }
            }
        }
        return (actions, remaining)
    }

    /// The first added workout of the same type that overlaps the entry's workout
    /// and isn't synced yet.
    private func replacementIndex(for entry: LedgerEntry, in added: [Workout]) async throws -> Int? {
        for (index, workout) in added.enumerated()
        where workout.start < entry.workoutEnd && workout.end > entry.workoutStart
            && (entry.activityType ?? workout.activityType) == workout.activityType {
            if try await ledger.entries(forWorkout: workout.id).isEmpty {
                return index
            }
        }
        return nil
    }

    private func replace(
        _ deletedID: UUID,
        with replacement: Workout,
        in entry: LedgerEntry,
        eventID: String,
        composer: EventComposer
    ) async throws -> SyncAction {
        let event = try await calendar.update(eventID: eventID, to: composer.content(for: replacement))
        var entry = entry
        entry.memberIDs.remove(deletedID)
        entry.memberIDs.insert(replacement.id)
        if entry.workoutID == deletedID {
            entry.workoutID = replacement.id
            entry.workoutStart = replacement.start
            entry.workoutEnd = replacement.end
            entry.activityType = replacement.activityType
        }
        entry.eventExternalIdentifier = event.id
        entry.written = event.content
        entry.updatedAt = clock.now
        try await ledger.save(entry)
        return .update(workoutID: replacement.id, eventID: event.id, event.content)
    }
}
