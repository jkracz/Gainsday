import Foundation

extension SyncEngine {
    /// Follows workouts deleted in Health.
    ///
    /// HealthKit workouts are immutable, so an edit, merge or re-import arrives as a
    /// delete plus an add. When an added workout of the same type overlaps a deleted
    /// one in the same pass, it replaces it: the existing event is updated in place.
    /// A replacement the user's filters leave out keeps the event as it is. When a
    /// cluster loses the member whose values the event shows, another copy still in
    /// Health takes over and the event is rewritten with its values.
    ///
    /// Before touching an owned event, the engine compares it with what it last wrote.
    /// If the user edited it, the event is released and left alone from then on. If
    /// the user deleted it, the workout is tombstoned so it's never recreated.
    /// Released and tombstoned entries are left alone; adopted events are [v1.1].
    ///
    /// Returns the actions taken and the added workouts that still need syncing.
    func followDeletions(
        in changes: WorkoutChanges,
        settings: Settings,
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
                if entry.workoutID == deletedID, let successor = try await successor(in: entry, among: survivors, settings: settings) {
                    entry.memberIDs.remove(deletedID)
                    entry.takeIdentity(from: successor)
                    actions.append(try await rewrite(entry, for: successor, composer: composer))
                    continue
                }
                entry.remove(deletedID, keeping: survivors)
                entry.updatedAt = clock.now
                try await ledger.save(entry)
                continue
            }
            var replacement: Workout?
            if let index = try await replacementIndex(for: entry, in: remaining) {
                replacement = remaining.remove(at: index)
            }
            if let replacement, let reason = settings.skipReason(for: replacement) {
                // Leave the event alone, but follow the replacement so a later delete still reaches it.
                var entry = entry
                entry.replace(deletedID, with: replacement)
                entry.updatedAt = clock.now
                try await ledger.save(entry)
                actions.append(.skip(workoutID: replacement.id, reason))
                continue
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
        if let replacement {
            var entry = entry
            entry.replace(deletedID, with: replacement)
            return try await rewrite(entry, for: replacement, composer: composer)
        }
        if let blocked = try await blockedChange(to: entry, eventID: eventID, workoutID: deletedID) {
            return blocked
        }
        try await calendar.delete(eventID: eventID)
        try await ledger.delete(entryID: entry.id)
        return .delete(workoutID: deletedID, eventID: eventID)
    }

    /// Writes `workout`'s values to an owned entry's event, which the entry already
    /// names as the workout's, and saves the entry. An entry with no event to
    /// change, e.g. a tombstone, is only saved.
    func rewrite(_ entry: LedgerEntry, for workout: Workout, composer: EventComposer) async throws -> SyncAction {
        var entry = entry
        entry.updatedAt = clock.now
        guard entry.state == .owned, let eventID = entry.eventExternalIdentifier else {
            try await ledger.save(entry)
            return .skip(workoutID: workout.id, entry.state == .tombstoned ? .tombstoned : .alreadySynced)
        }
        if let blocked = try await blockedChange(to: entry, eventID: eventID, workoutID: workout.id) {
            return blocked
        }
        let updated = try await calendar.update(eventID: eventID, to: composer.content(for: workout))
        entry.eventExternalIdentifier = updated.id
        entry.written = updated.content
        try await ledger.save(entry)
        return .update(workoutID: workout.id, eventID: updated.id, updated.content)
    }

    /// Checks an owned event before the app changes it. When it can't be changed,
    /// saves the entry and returns what happened instead: add-only access keeps the
    /// event as it is, a deleted event tombstones the workout so it's never
    /// recreated, and an edited one is released. Nil when the event is still as the
    /// app wrote it.
    private func blockedChange(to entry: LedgerEntry, eventID: String, workoutID: UUID) async throws -> SyncAction? {
        var entry = entry
        entry.updatedAt = clock.now
        let event: CalendarEvent?
        do {
            event = try await calendar.event(withID: eventID)
        } catch CalendarStoreError.requiresFullAccess {
            // Keep the entry, which may now point at a replacement, so the event isn't created a second time.
            try await ledger.save(entry)
            return .skip(workoutID: workoutID, .requiresFullAccess)
        }
        guard let event else {
            entry.state = .tombstoned
            try await ledger.save(entry)
            return .skip(workoutID: workoutID, .tombstoned)
        }
        guard event.content.matches(entry.written) else {
            entry.state = .released
            try await ledger.save(entry)
            return .release(workoutID: workoutID, eventID: eventID)
        }
        return nil
    }

    /// The surviving cluster member whose values the event should show now, if any
    /// is still in Health and allowed.
    private func successor(in entry: LedgerEntry, among survivors: Set<UUID>, settings: Settings) async throws -> Workout? {
        let remaining = try await healthWorkouts(in: entry).filter { survivors.contains($0.id) }
        return settings.splitBySource(remaining).allowed.min(by: Workout.isPreferred)
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
            takeIdentity(from: replacement)
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
