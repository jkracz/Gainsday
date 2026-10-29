import Foundation

/// Add-only mode: with EventKit write-only access the app adds events but can't read,
/// update or delete them, so the ledger is the only way to avoid duplicates. Entries
/// written then are marked `needsLinking`, and entries whose Health change couldn't be
/// applied `needsHealthFollowUp`.
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
            writtenFingerprint: draft.content.fingerprint,
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
        entry.writtenFingerprint = event.content.fingerprint
        try await ledger.save(entry)
        return .create(workoutID: workout.id, draft)
    }

    /// Once the user grants full access, finds each event written in add-only mode in
    /// its calendar, by identifier, footer, or title and times, and records its current
    /// identifier. Returns a relink for each entry whose identifier changed. Then applies
    /// the Health deletes and replacements the app couldn't apply in add-only mode. Each
    /// marker is cleared only once its work is saved, so a failed pass retries it.
    ///
    /// The fingerprint of what the app wrote is kept, so edits the user made in the
    /// meantime are still spotted later. An event that can't be found is left to the
    /// lifecycle rules, which treat it as deleted by the user.
    func linkEventsAddedWithoutReadAccess(settings: Settings, composer: EventComposer) async throws -> [SyncAction] {
        guard await calendar.accessMode() == .full else { return [] }
        var actions: [SyncAction] = []
        for pending in try await ledger.entriesNeedingLinking() {
            guard var entry = try await resolvedEntry(forWorkout: pending.workoutID),
                  entry.needsLinking || entry.needsHealthFollowUp else { continue }
            if entry.needsLinking {
                entry.needsLinking = false
                if entry.calendarID == CalendarReference.defaultCalendarID {
                    // It went to the default calendar, which the destination now names.
                    entry.calendarID = settings.destinationCalendar?.id
                }
                if entry.state == .owned, let calendarID = entry.calendarID,
                   entry.writtenFingerprint != nil,
                   let event = try await findOwnEvent(for: entry.memberIDs.union([entry.workoutID]), matching: ExpectedEvent(entry), in: calendarID, knownID: entry.eventExternalIdentifier),
                   event.id != entry.eventExternalIdentifier {
                    entry.eventExternalIdentifier = event.id
                    actions.append(.relink(workoutID: entry.workoutID, eventID: event.id))
                }
                entry.updatedAt = clock.now
                try await ledger.save(entry)
            }
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
    ///
    /// The marker is cleared in the same ledger write that records the outcome, so a
    /// failure on the way leaves the entry queued for the next pass.
    private func followUpHealthChange(to entry: LedgerEntry, settings: Settings, composer: EventComposer) async throws -> SyncAction? {
        var entry = entry
        entry.needsHealthFollowUp = false
        guard [.owned, .adopted].contains(entry.state), let eventID = entry.eventExternalIdentifier else {
            entry.updatedAt = clock.now
            try await ledger.save(entry)
            return nil
        }
        let inHealth = settings.splitBySource(try await healthWorkouts(in: entry)).allowed
        if let workout = inHealth.first(where: { $0.id == entry.workoutID }) ?? inHealth.min(by: Workout.isPreferred) {
            entry.takeIdentity(from: workout)
            return try await rewrite(entry, for: workout, composer: composer)
        }
        let event: CalendarEvent
        switch try await checkChange(to: entry, eventID: eventID, workoutID: entry.workoutID) {
        case .blocked(let action): return action
        case .allowed(let checked): event = checked
        }
        if entry.state == .adopted {
            return try await removeWorkoutSection(of: entry, from: event, workoutID: entry.workoutID)
        }
        try await calendar.delete(eventID: eventID)
        try await ledger.delete(entryID: entry.id)
        return .delete(workoutID: entry.workoutID, eventID: eventID)
    }
}
