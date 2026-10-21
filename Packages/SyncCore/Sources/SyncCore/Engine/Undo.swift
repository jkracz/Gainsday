import Foundation

public enum UndoError: Error, Hashable, Sendable {
    /// The entry is no longer in the activity log.
    case entryNotFound
    /// The entry can't be undone, or was undone already.
    case notUndoable
    /// Undoing an update to a planned event needs the user's choice of what happens to the workout.
    case choiceRequired
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

        switch undo {
        case .removeCreatedEvent:
            try await removeCreatedEvent(of: entry)
        case .recreateEvent(let draft):
            try await recreateEvent(draft, of: entry)
        case .restoreEvent(let content):
            try await restoreEvent(to: content, of: entry)
        case .restorePlannedEvent(let content):
            guard let choice else { throw UndoError.choiceRequired }
            followUp = try await restorePlannedEvent(content, of: entry, choice: choice)
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
    /// so later passes never create it again.
    private func removeCreatedEvent(of logEntry: ActivityLogEntry) async throws {
        let entries = try await ledger.entries(forWorkout: logEntry.workoutID).filter { $0.state != .tombstoned }
        // With no live ledger entry left, fall back to the event the log remembers.
        let eventIDs = entries.isEmpty ? [logEntry.eventID].compactMap(\.self) : entries.compactMap(\.eventExternalIdentifier)
        for eventID in Set(eventIDs) where try await calendar.event(withID: eventID) != nil {
            try await calendar.delete(eventID: eventID)
        }

        let now = clock.now
        for var entry in entries {
            entry.state = .tombstoned
            entry.updatedAt = now
            try await ledger.save(entry)
        }
        if entries.isEmpty, case .create(let workoutID, let draft) = logEntry.action,
           try await ledger.entries(forWorkout: workoutID).isEmpty {
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
            written: event.content,
            createdAt: now,
            updatedAt: now,
            activityType: logEntry.activityType
        ))
    }

    /// Puts back what an updated event held before. The user chose that content, so
    /// the event is released: the app leaves it alone from then on.
    private func restoreEvent(to content: EventContent, of logEntry: ActivityLogEntry) async throws {
        let entries = try await ledger.entries(forWorkout: logEntry.workoutID)
            .filter { $0.state != .tombstoned && $0.eventExternalIdentifier != nil }
        guard let eventID = entries.first?.eventExternalIdentifier ?? logEntry.eventID else {
            throw UndoError.notUndoable
        }
        let restored = try await calendar.update(eventID: eventID, to: content)
        let now = clock.now
        for var entry in entries where entry.eventExternalIdentifier == eventID {
            entry.state = .released
            entry.eventExternalIdentifier = restored.id
            entry.written = restored.content
            entry.updatedAt = now
            try await ledger.save(entry)
        }
    }
}
