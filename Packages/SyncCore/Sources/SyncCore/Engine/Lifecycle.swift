import Foundation

extension SyncEngine {
    /// Follows workouts deleted in Health.
    ///
    /// HealthKit workouts are immutable, so an edit, merge or re-import arrives as a
    /// delete plus an add. When an added workout of the same type overlaps a deleted
    /// one in the same pass, it replaces it: the existing event is updated in place.
    ///
    /// Before touching an owned event, the engine compares it with what it last wrote.
    /// If the user edited it, the event is released and left alone from then on. If
    /// the user deleted it, the workout is tombstoned so it's never recreated.
    /// Released and tombstoned entries are left alone; adopted events are [v1.1].
    ///
    /// Returns the actions taken and the added workouts that still need syncing.
    func followDeletions(
        in changes: WorkoutChanges,
        composer: EventComposer
    ) async throws -> (actions: [SyncAction], remaining: [Workout]) {
        var actions: [SyncAction] = []
        var remaining = changes.added
        for deletedID in changes.deletedIDs {
            // Collapse iCloud duplicates and fix a changed identifier first, so an event
            // that's still there isn't mistaken for one the user deleted.
            guard let resolved = try await resolvedEntry(forWorkout: deletedID), resolved.state == .owned else { continue }
            let entry = try await correctExternalIdentifier(of: resolved)
            let survivors = entry.memberIDs.subtracting(changes.deletedIDs)
            if !survivors.isEmpty {
                // Another copy of the workout is still in Health, so the event stays.
                var entry = entry
                entry.remove(deletedID, keeping: survivors)
                entry.updatedAt = clock.now
                try await ledger.save(entry)
                continue
            }
            var replacement: Workout?
            if let index = try await replacementIndex(for: entry, in: remaining) {
                replacement = remaining.remove(at: index)
            }
            if let action = try await follow(deletedID, in: entry, replacedBy: replacement, composer: composer) {
                actions.append(action)
            }
        }
        return (actions, remaining)
    }

    /// Deletes, updates, releases or tombstones one owned entry's event after its
    /// workout was deleted, and possibly replaced, in Health.
    private func follow(
        _ deletedID: UUID,
        in entry: LedgerEntry,
        replacedBy replacement: Workout?,
        composer: EventComposer
    ) async throws -> SyncAction? {
        guard let eventID = entry.eventExternalIdentifier else { return nil }
        var entry = entry
        if let replacement {
            entry.replace(deletedID, with: replacement)
        }
        let workoutID = replacement?.id ?? deletedID
        let save = { (state: LedgerEntry.State) in
            entry.state = state
            entry.updatedAt = clock.now
            try await ledger.save(entry)
        }

        let event: CalendarEvent?
        do {
            event = try await calendar.event(withID: eventID)
        } catch CalendarStoreError.requiresFullAccess {
            // Add-only access can't read, update or delete the event. Keep it, and
            // point the entry at any replacement so it isn't created a second time.
            if replacement != nil {
                try await save(.owned)
            }
            return .skip(workoutID: workoutID, .requiresFullAccess)
        }
        guard let event else {
            // The user deleted the event: never create one for this workout again.
            try await save(.tombstoned)
            return .skip(workoutID: workoutID, .tombstoned)
        }
        guard event.content.matches(entry.written) else {
            try await save(.released)
            return .release(workoutID: workoutID, eventID: eventID)
        }
        guard let replacement else {
            try await calendar.delete(eventID: eventID)
            try await ledger.delete(entryID: entry.id)
            return .delete(workoutID: workoutID, eventID: eventID)
        }
        let updated = try await calendar.update(eventID: eventID, to: composer.content(for: replacement))
        entry.eventExternalIdentifier = updated.id
        entry.written = updated.content
        try await save(.owned)
        return .update(workoutID: workoutID, eventID: updated.id, updated.content)
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
}

private extension LedgerEntry {
    /// Drops a deleted member from the cluster, handing its identity to a survivor if needed.
    mutating func remove(_ deletedID: UUID, keeping survivors: Set<UUID>) {
        memberIDs.remove(deletedID)
        if workoutID == deletedID, let survivor = survivors.min(by: { $0.uuidString < $1.uuidString }) {
            workoutID = survivor
        }
    }

    /// Points the entry at the workout that replaced `deletedID` in Health.
    mutating func replace(_ deletedID: UUID, with replacement: Workout) {
        memberIDs.remove(deletedID)
        memberIDs.insert(replacement.id)
        if workoutID == deletedID {
            workoutID = replacement.id
            workoutStart = replacement.start
            workoutEnd = replacement.end
            activityType = replacement.activityType
        }
    }
}

private extension EventContent {
    /// Whether the event still holds what the app wrote. Times are compared to the
    /// second, since calendar stores may drop sub-second precision; nil and empty
    /// notes are the same. With no snapshot, assume the user changed it.
    func matches(_ written: EventContent?) -> Bool {
        guard let written else { return false }
        return title == written.title
            && abs(start.timeIntervalSince(written.start)) < 1
            && abs(end.timeIntervalSince(written.end)) < 1
            && (notes ?? "") == (written.notes ?? "")
    }
}
