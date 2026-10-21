import Foundation

/// Add-only mode: with EventKit write-only access the app adds events but can't read,
/// update or delete them, so the ledger is the only way to avoid duplicates. Entries
/// written then are marked `needsLinking`.
extension SyncEngine {
    /// Creates the workout's event in add-only mode. The ledger entry is saved first:
    /// the app can't remove an event in this mode, so an event the ledger didn't know
    /// about would be created again on the next pass.
    func createWithoutReadAccess(for workout: Workout, _ draft: EventDraft) async throws -> SyncAction {
        let now = clock.now
        var entry = LedgerEntry(
            workoutID: workout.id,
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
    /// identifier. Returns a relink for each entry whose identifier changed.
    ///
    /// The snapshot of what the app wrote is kept, so edits the user made in the
    /// meantime are still spotted later. An event that can't be found is left to the
    /// lifecycle rules, which treat it as deleted by the user.
    func linkEventsAddedWithoutReadAccess() async throws -> [SyncAction] {
        guard await calendar.accessMode() == .full else { return [] }
        var actions: [SyncAction] = []
        for pending in try await ledger.entriesNeedingLinking() {
            guard var entry = try await resolvedEntry(forWorkout: pending.workoutID), entry.needsLinking else { continue }
            entry.needsLinking = false
            if entry.state == .owned, let calendarID = entry.calendarID,
               let expected = entry.written,
               let event = try await findOwnEvent(for: entry.workoutID, matching: expected, in: calendarID, knownID: entry.eventExternalIdentifier),
               event.id != entry.eventExternalIdentifier {
                entry.eventExternalIdentifier = event.id
                actions.append(.relink(workoutID: entry.workoutID, eventID: event.id))
            }
            entry.updatedAt = clock.now
            try await ledger.save(entry)
        }
        return actions
    }
}
