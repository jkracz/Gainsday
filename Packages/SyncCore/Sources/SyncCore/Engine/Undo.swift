import Foundation

public enum UndoError: Error, Hashable, Sendable {
    /// The entry is no longer in the activity log.
    case entryNotFound
    /// The entry can't be undone, or was undone already.
    case notUndoable
    /// Undoing an update to a planned event needs the user's choice of what happens to the workout.
    case choiceRequired
    /// The user edited the event since the app wrote it, so it's theirs now and the app
    /// won't delete it. The entry can't be undone any more.
    case eventEditedByUser
    /// The workout or its event changed since, e.g. the workout was matched to another
    /// event or a later action rewrote it, so undoing would change something else. The
    /// entry can't be undone any more.
    case outOfDate
}

extension SyncEngine {
    /// Reverses the action of an activity log entry and marks the entry undone.
    ///
    /// Undo needs full calendar access, and throws `CalendarStoreError.requiresFullAccess`
    /// in add-only mode.
    @discardableResult
    public func undo(entryID: UUID) async throws -> ActivityLogEntry {
        try await performUndo(entryID: entryID, choice: nil)
    }

    /// Reverses the action of an activity log entry, as above. Undoing an update to a
    /// planned event also does what the user chose with the workout; other entries
    /// ignore the choice.
    @discardableResult
    public func undo(entryID: UUID, choice: ActivityLogEntry.PlannedEventUndoChoice) async throws -> ActivityLogEntry {
        try await performUndo(entryID: entryID, choice: choice)
    }

    private func performUndo(entryID: UUID, choice: ActivityLogEntry.PlannedEventUndoChoice?) async throws -> ActivityLogEntry {
        var log = try await activityLog.load()
        guard let index = log.firstIndex(where: { $0.id == entryID }) else { throw UndoError.entryNotFound }
        var entry = log[index]
        guard entry.canUndo, let undo = entry.undo else { throw UndoError.notUndoable }
        guard await calendar.accessMode() == .full else { throw CalendarStoreError.requiresFullAccess }
        var followUp: (actions: [SyncAction], workouts: [Workout])?

        do {
            switch undo {
            case .removeCreatedEvent:
                try await removeCreatedEvent(of: entry)
            case .recreateEvent(let draft):
                try await recreateEvent(draft, of: entry)
            case .restoreEvent(let content):
                try await restoreEvent(to: content, of: entry)
            case .separateFromPlannedEvent(let draft, let createEntryID):
                try await separateFromPlannedEvent(draft, of: entry, reenabling: createEntryID, in: &log)
            case .returnToReview(let heldEntryID):
                try await returnToReview(entry, heldEntryID: heldEntryID, in: &log)
            case .restorePlannedEvent(let content):
                guard let choice else { throw UndoError.choiceRequired }
                followUp = try await restorePlannedEvent(content, of: entry, choice: choice)
            }
        } catch let error as UndoError where [.eventEditedByUser, .outOfDate].contains(error) {
            log[index].undo = nil
            if error == .eventEditedByUser, let eventID = entry.eventID {
                // The app has let go of the event, so nothing else may change it either.
                log = log.map { $0.lettingGoOfEvent(eventID, workoutID: entry.workoutID) }
            }
            try await activityLog.save(log)
            throw error
        }
        entry.undoneAt = clock.now
        log[index] = entry
        try await activityLog.save(log)
        if let followUp {
            // A separate event made for the workout gets its own log entry, which can be undone in turn.
            _ = await ActivityRecorder(engine: self, added: followUp.workouts).record(SyncResult(actions: followUp.actions))
        }
        return entry
    }

    /// Deletes the event created for the entry's workout and tombstones the workout,
    /// so later passes never create it again. An event the user edited is theirs: it's
    /// released, if it wasn't already, and kept.
    private func removeCreatedEvent(of logEntry: ActivityLogEntry) async throws {
        guard let target = try await undoTarget(of: logEntry) else {
            try await removeUnlinkedEvent(of: logEntry)
            return
        }
        let (entry, event) = try await verified(target, of: logEntry, in: .owned)
        if let event {
            try await calendar.delete(eventID: event.id)
        }

        let now = clock.now
        // iCloud duplicates of the entry for the same event go too, so none outlives the tombstone.
        let duplicates = try await ledger.entries(forWorkout: entry.workoutID).filter {
            $0.id != entry.id && $0.state == .owned && $0.eventExternalIdentifier == entry.eventExternalIdentifier
        }
        for var entry in [entry] + duplicates {
            entry.state = .tombstoned
            entry.updatedAt = now
            try await ledger.save(entry)
        }
    }

    /// Undo of a create whose ledger entry has gone, e.g. Health deleted the workout and
    /// its event with it. An event still there is deleted only when nothing links it and
    /// it's still as the app created it. The workout is tombstoned, if nothing else
    /// records it, so it isn't created again.
    private func removeUnlinkedEvent(of logEntry: ActivityLogEntry) async throws {
        guard case .create(let workoutID, let draft) = logEntry.action else { throw UndoError.notUndoable }
        if let eventID = logEntry.eventID, let event = try await calendar.event(withID: eventID) {
            guard try await liveEntries(linkedTo: eventID, around: draft.content).isEmpty else { throw UndoError.outOfDate }
            guard event.content.matches(draft.content) else { throw UndoError.eventEditedByUser }
            try await calendar.delete(eventID: eventID)
        }
        guard try await ledger.entries(forWorkout: workoutID).isEmpty else { return }
        let now = clock.now
        try await ledger.save(LedgerEntry(
            workoutID: workoutID,
            workoutStart: draft.content.start,
            workoutEnd: draft.content.end,
            state: .tombstoned,
            createdAt: now,
            updatedAt: now,
            activityType: logEntry.activityType
        ))
    }

    /// Creates a deleted event again. The workout is gone from Health, so the event is
    /// recorded as released: the app leaves it alone from then on.
    private func recreateEvent(_ draft: EventDraft, of logEntry: ActivityLogEntry) async throws {
        let event = try await calendar.create(draft)
        let now = clock.now
        try await ledger.save(LedgerEntry(
            workoutID: logEntry.workoutID,
            workoutStart: logEntry.workoutStart ?? draft.content.start,
            workoutEnd: draft.content.end,
            state: .released,
            eventExternalIdentifier: event.id,
            calendarID: event.calendarID,
            writtenFingerprint: event.content.fingerprint,
            createdAt: now,
            updatedAt: now,
            activityType: logEntry.activityType
        ))
    }

    /// Puts back what an updated event held before. The user chose that content, so
    /// the event is released: the app leaves it alone from then on. Only the update's
    /// own event is changed, and only while it still holds what the update wrote.
    private func restoreEvent(to content: EventContent, of logEntry: ActivityLogEntry) async throws {
        guard case .update(_, _, let updated) = logEntry.action else { throw UndoError.notUndoable }
        var (entry, event) = try await verified(try await undoTarget(of: logEntry), of: logEntry, in: .owned)
        // A later change by the app, which the update's Undo would throw away.
        guard let event, event.content.matches(updated) else { throw UndoError.outOfDate }
        let restored = try await calendar.update(eventID: event.id, to: content)
        entry.state = .released
        entry.eventExternalIdentifier = restored.id
        entry.writtenFingerprint = restored.content.fingerprint
        entry.updatedAt = clock.now
        try await ledger.save(entry)
    }
}

extension SyncEngine {
    /// The ledger entry an Undo acts on: the one its log entry was recorded against,
    /// which follows the workout through replacements in Health. Entries logged before
    /// that was recorded use the live entry for the workout that links the same event.
    func undoTarget(of logEntry: ActivityLogEntry) async throws -> LedgerEntry? {
        if let ledgerEntryID = logEntry.ledgerEntryID {
            return try await ledger.entry(withID: ledgerEntryID)
        }
        guard let eventID = logEntry.eventID else { return nil }
        return try await ledger.entries(forWorkout: logEntry.workoutID)
            .first { $0.state != .tombstoned && $0.eventExternalIdentifier == eventID }
    }

    /// Checks an Undo may still change its entry's event: the entry is still in `state`
    /// and links the event the action was about, and the event is still as the app
    /// wrote it, with no guests. Returns the entry and its event, or nil if the event
    /// has gone.
    ///
    /// An entry the app has let go of, or an event the user changed, is the user's:
    /// throws `eventEditedByUser`, releasing the entry if it wasn't already. Anything
    /// else that changed throws `outOfDate`.
    func verified(
        _ target: LedgerEntry?,
        of logEntry: ActivityLogEntry,
        in state: LedgerEntry.State
    ) async throws -> (entry: LedgerEntry, event: CalendarEvent?) {
        guard var entry = target else { throw UndoError.outOfDate }
        guard entry.state != .released else { throw UndoError.eventEditedByUser }
        guard entry.state == state else { throw UndoError.outOfDate }
        if let loggedID = logEntry.eventID, entry.eventExternalIdentifier != loggedID {
            // A calendar server can change an event's identifier, and the entry then links
            // it by its new one. If the action's event is still there, the entry has
            // moved on to another event.
            guard try await calendar.event(withID: loggedID) == nil else { throw UndoError.outOfDate }
        }
        guard let eventID = entry.eventExternalIdentifier, let event = try await calendar.event(withID: eventID) else {
            return (entry, nil)
        }
        let asWritten = state == .adopted ? entry.adoptedEventIsAsWritten(event.content) : event.content.matches(entry.writtenFingerprint)
        // Changing an event with guests can email every one of them.
        guard asWritten, event.attendeeCount == 0 else {
            entry.state = .released
            entry.updatedAt = clock.now
            try await ledger.save(entry)
            throw UndoError.eventEditedByUser
        }
        return (entry, event)
    }

    /// The live ledger entries linked to an event, among those whose workout overlaps `times`.
    func liveEntries(linkedTo eventID: String, around times: EventContent) async throws -> [LedgerEntry] {
        try await ledger.entries(in: DateInterval(start: times.start, end: max(times.start, times.end)))
            .filter { $0.state != .tombstoned && $0.eventExternalIdentifier == eventID }
    }
}
