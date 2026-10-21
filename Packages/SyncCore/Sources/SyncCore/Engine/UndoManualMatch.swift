import Foundation

/// Undo of "Match to an event…". [v1.1]
extension SyncEngine {
    /// Adds the workout's separate event again, then puts the planned event back as it
    /// was before the match, from the copy the ledger kept when it was adopted. The
    /// workout owns the separate event again, so the create it came from can be undone
    /// or matched again.
    func separateFromPlannedEvent(
        _ draft: EventDraft,
        of logEntry: ActivityLogEntry,
        reenabling createEntryID: UUID,
        in log: inout [ActivityLogEntry]
    ) async throws {
        guard var entry = try await resolvedEntry(forWorkout: logEntry.workoutID), entry.state == .adopted,
              let planID = entry.eventExternalIdentifier, let plan = entry.preUpdate else {
            throw UndoError.notUndoable
        }
        let separate = try await calendar.create(draft)
        do {
            _ = try await calendar.update(eventID: planID, to: plan)
        } catch {
            // Showing the workout twice is worse than leaving the match in place.
            try? await calendar.delete(eventID: separate.id)
            throw error
        }

        entry.state = .owned
        entry.eventExternalIdentifier = separate.id
        entry.calendarID = separate.calendarID
        entry.written = separate.content
        entry.preUpdate = nil
        entry.updatedAt = clock.now
        try await ledger.save(entry)

        if let index = log.firstIndex(where: { $0.id == createEntryID }) {
            log[index].undo = .removeCreatedEvent
            log[index].eventID = separate.id
        }
    }

    /// Undoes settling a workout held for review: removes the separate event it was
    /// added as, or puts the planned event it was matched to back as it was, from the
    /// copy the ledger kept. The workout has no ledger entry again, as when it was held,
    /// and its held entry waits for review again.
    func returnToReview(_ logEntry: ActivityLogEntry, heldEntryID: UUID, in log: inout [ActivityLogEntry]) async throws {
        guard let entry = try await resolvedEntry(forWorkout: logEntry.workoutID),
              let eventID = entry.eventExternalIdentifier else { throw UndoError.notUndoable }
        switch entry.state {
        case .owned:
            if try await calendar.event(withID: eventID) != nil {
                try await calendar.delete(eventID: eventID)
            }
        case .adopted:
            guard let plan = entry.preUpdate else { throw UndoError.notUndoable }
            _ = try await calendar.update(eventID: eventID, to: plan)
        case .released, .tombstoned:
            throw UndoError.notUndoable
        }
        try await ledger.delete(entryID: entry.id)

        if let index = log.firstIndex(where: { $0.id == heldEntryID }) {
            log[index].reviewedAt = nil
        }
    }
}
