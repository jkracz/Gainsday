import Foundation

/// Planned events the app updated (adopted) stay the user's. The app only ever changes
/// their time and its own workout section, and only while both are as it wrote them:
/// the title and the rest of the notes are the user's to change. [v1.1]
extension SyncEngine {
    /// Takes the workout section out of an adopted event whose workout was deleted in
    /// Health. The event keeps its time and everything the user wrote, and the app lets
    /// go of it. `event` is the event as `checkChange` checked it.
    func removeWorkoutSection(of entry: LedgerEntry, from event: CalendarEvent, workoutID: UUID) async throws -> SyncAction {
        var content = event.content
        content.notes = WorkoutSection.removing(from: content.notes, workoutID: entry.workoutID)
        let updated = try await calendar.update(eventID: event.id, to: content)
        try await ledger.delete(entryID: entry.id)
        return .removeWorkoutSection(workoutID: workoutID, eventID: updated.id, updated.content)
    }

    /// Writes `workout`'s times and section to an adopted event, keeping the user's title
    /// and the rest of their notes, and saves the entry.
    func rewriteAdopted(_ entry: LedgerEntry, for workout: Workout, composer: EventComposer) async throws -> SyncAction {
        var entry = entry
        entry.updatedAt = clock.now
        guard let eventID = entry.eventExternalIdentifier else {
            try await ledger.save(entry)
            return .skip(workoutID: workout.id, .alreadySynced)
        }
        let event: CalendarEvent
        switch try await checkChange(to: entry, eventID: eventID, workoutID: workout.id) {
        case .blocked(let action): return action
        case .allowed(let checked): event = checked
        }
        var content = event.content
        content.start = workout.start
        content.end = workout.end
        content.notes = WorkoutSection.replacing(
            in: content.notes,
            with: composer.workoutSectionBody(for: workout, planned: entry.preUpdate ?? event.content),
            workoutID: workout.id
        )
        let updated = try await calendar.update(eventID: eventID, to: content)
        entry.eventExternalIdentifier = updated.id
        entry.writtenFingerprint = updated.content.fingerprint
        try await ledger.save(entry)
        return .update(workoutID: workout.id, eventID: updated.id, updated.content)
    }
}

extension LedgerEntry {
    /// Whether an adopted event still has the time and workout section the app wrote,
    /// by the fingerprint of them (see `ContentFingerprint`). With no fingerprint,
    /// assume the user changed it.
    func adoptedEventIsAsWritten(_ content: EventContent) -> Bool {
        guard let writtenFingerprint else { return false }
        return content.fingerprint.timesAndSection == writtenFingerprint.timesAndSection
    }
}
