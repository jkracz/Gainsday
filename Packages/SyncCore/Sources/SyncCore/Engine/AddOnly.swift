import Foundation

/// Add-only mode: with EventKit write-only access the app adds events but can't read,
/// update or delete them, so the ledger is the only way to avoid duplicates. Entries
/// written then are marked `needsLinking`.
extension SyncEngine {
    /// Creates the cluster's event in add-only mode. The ledger entry, holding every
    /// member, is saved first: the app can't remove an event in this mode, so an event
    /// the ledger didn't know about would be created again on the next pass.
    func createWithoutReadAccess(for cluster: WorkoutCluster, _ draft: EventDraft) async throws -> SyncAction {
        let workout = cluster.preferred
        let now = clock.now
        var entry = LedgerEntry(
            workoutID: workout.id,
            memberIDs: cluster.memberIDs,
            workoutStart: workout.start,
            workoutEnd: workout.end,
            state: .owned,
            calendarID: draft.calendarID,
            written: draft.content,
            createdAt: now,
            updatedAt: now,
            activityType: workout.activityType,
            needsLinking: true
        )
        try await ledger.save(entry)
        let event: CalendarEvent
        do {
            event = try await createEvent(draft)
        } catch {
            try? await ledger.delete(entryID: entry.id)
            throw error
        }
        // If this save fails, the entry still stops a second event, and upgrading to
        // full access finds this one by its footer.
        entry.eventExternalIdentifier = event.id
        entry.calendarID = event.calendarID
        entry.written = event.content
        try await ledger.save(entry)
        return .create(workoutID: workout.id, draft)
    }

    /// Once the user grants full access, finds each event written in add-only mode in
    /// its calendar, by identifier, footer, or title and times, and records its current
    /// identifier. Returns a relink for each entry whose identifier changed. Then applies
    /// the Health deletes and replacements the app couldn't apply in add-only mode.
    ///
    /// The snapshot of what the app wrote is kept, so edits the user made in the
    /// meantime are still spotted later. An event that can't be found is left to the
    /// lifecycle rules, which treat it as deleted by the user.
    func linkEventsAddedWithoutReadAccess(settings: Settings, composer: EventComposer) async throws -> [SyncAction] {
        guard await calendar.accessMode() == .full else { return [] }
        var actions: [SyncAction] = []
        for pending in try await ledger.entriesNeedingLinking() {
            guard var entry = try await resolvedEntry(forWorkout: pending.workoutID), entry.needsLinking else { continue }
            entry.needsLinking = false
            if entry.state == .owned, let calendarID = entry.calendarID,
               let expected = entry.written,
               let event = try await findOwnEvent(for: entry.memberIDs.union([entry.workoutID]), matching: expected, in: calendarID, knownID: entry.eventExternalIdentifier),
               event.id != entry.eventExternalIdentifier {
                entry.eventExternalIdentifier = event.id
                actions.append(.relink(workoutID: entry.workoutID, eventID: event.id))
            }
            entry.updatedAt = clock.now
            try await ledger.save(entry)
            if entry.needsHealthFollowUp, let action = try await followUpHealthChange(to: entry, settings: settings, composer: composer) {
                actions.append(action)
            }
        }
        return actions
    }

    /// Applies a Health delete or replacement that add-only access held back: an event
    /// whose workout is gone from Health is deleted, and one whose workout was replaced
    /// shows the replacement's values. An event the user edited or deleted meanwhile is
    /// released or tombstoned instead, as in a pass.
    private func followUpHealthChange(to entry: LedgerEntry, settings: Settings, composer: EventComposer) async throws -> SyncAction? {
        var entry = entry
        entry.needsHealthFollowUp = false
        try await ledger.save(entry)
        guard [.owned, .adopted].contains(entry.state), let eventID = entry.eventExternalIdentifier else { return nil }
        let inHealth = settings.splitBySource(try await healthWorkouts(in: entry)).allowed
        if let workout = inHealth.first(where: { $0.id == entry.workoutID }) ?? inHealth.min(by: Workout.isPreferred) {
            entry.takeIdentity(from: workout)
            return try await rewrite(entry, for: workout, composer: composer)
        }
        if let blocked = try await blockedChange(to: entry, eventID: eventID, workoutID: entry.workoutID) {
            return blocked
        }
        if entry.state == .adopted {
            return try await removeWorkoutSection(of: entry, eventID: eventID, workoutID: entry.workoutID)
        }
        try await calendar.delete(eventID: eventID)
        try await ledger.delete(entryID: entry.id)
        return .delete(workoutID: entry.workoutID, eventID: eventID)
    }
}
