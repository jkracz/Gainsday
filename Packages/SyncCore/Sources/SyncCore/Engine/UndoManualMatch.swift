import Foundation

/// Undo of "Match to an event…". [v1.1]
extension SyncEngine {
    /// Adds the workout's separate event again, then puts the planned event back as it
    /// was before the match, from the copy the ledger kept when it was adopted. The
    /// workout owns the separate event again, so the create it came from can be undone
    /// or matched again. Only while the plan is still as the match left it.
    func separateFromPlannedEvent(
        _ draft: EventDraft,
        of logEntry: ActivityLogEntry,
        reenabling createEntryID: UUID,
        in log: inout [ActivityLogEntry]
    ) async throws {
        var (entry, event) = try await verified(try await undoTarget(of: logEntry), of: logEntry, in: .adopted)
        guard let planID = event?.id, let plan = entry.preUpdate else { throw UndoError.outOfDate }
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
        entry.writtenFingerprint = separate.content.fingerprint
        entry.preUpdate = nil
        entry.updatedAt = clock.now
        try await ledger.save(entry)

        if let index = log.firstIndex(where: { $0.id == createEntryID }) {
            log[index].undo = .removeCreatedEvent
            log[index].eventID = separate.id
            log[index].ledgerEntryID = entry.id
        }
    }

    /// Undoes settling a workout held for review: removes the separate event it was
    /// added as, or puts the planned event it was matched to back as it was, from the
    /// copy the ledger kept. The workout has no ledger entry again, as when it was held,
    /// and its held entry waits for review again. Only while the event is still as the
    /// app wrote it.
    func returnToReview(_ logEntry: ActivityLogEntry, heldEntryID: UUID, in log: inout [ActivityLogEntry]) async throws {
        let target = try await undoTarget(of: logEntry)
        let (entry, event) = try await verified(target, of: logEntry, in: target?.state == .adopted ? .adopted : .owned)
        switch entry.state {
        case .adopted:
            guard let event, let plan = entry.preUpdate else { throw UndoError.outOfDate }
            _ = try await calendar.update(eventID: event.id, to: plan)
        default:
            if let event {
                try await calendar.delete(eventID: event.id)
            }
        }
        try await ledger.delete(entryID: entry.id)

        if let index = log.firstIndex(where: { $0.id == heldEntryID }) {
            log[index].reviewedAt = nil
        }
    }
}
