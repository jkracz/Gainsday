import Foundation
import Synchronization

/// Turns the actions of a pass into activity log entries.
///
/// Undoing an update or a delete needs the content the pass replaced. The ledger keeps
/// only a fingerprint of it, so the pass runs inside `capturingChanges`, which keeps
/// each event as it was just before the app changed it.
///
/// Recording is best effort. The events are already written by then, so losing a
/// log line is better than failing the pass.
struct ActivityRecorder {
    let engine: SyncEngine
    /// The workouts the pass reads.
    let added: [Workout]
    /// Ledger entries for the workouts deleted in Health, and for the times of those
    /// added, as they were before the pass. A late copy of a synced workout can rewrite
    /// its event, and Undo puts back what the event held.
    let before: [LedgerEntry]
    /// The events the pass changed, as they were before.
    let changed = EventsBeforeChange()

    init(engine: SyncEngine, added: [Workout]) {
        self.engine = engine
        self.added = added
        self.before = []
    }

    init(engine: SyncEngine, added: [Workout], deletedIDs: [UUID]) async throws {
        self.engine = engine
        self.added = added
        var before: [LedgerEntry] = []
        for deletedID in deletedIDs {
            before += try await engine.ledger.entries(forWorkout: deletedID)
        }
        if let start = added.map(\.start).min(), let end = added.map(\.end).max() {
            let seen = Set(before.map(\.id))
            before += try await engine.ledger.entries(in: DateInterval(start: start, end: max(start, end)))
                .filter { !seen.contains($0.id) }
        }
        self.before = before
    }

    /// Runs the pass, keeping each event as it was before the pass changed it.
    nonisolated(nonsending) func capturingChanges<T>(_ pass: nonisolated(nonsending) () async throws -> T) async rethrows -> T {
        try await SyncEngine.$eventsBeforeChange.withValue(changed, operation: pass)
    }

    /// Adds the result's actions to the top of the log, keeping it to its capacity
    /// apart from workouts still held for review.
    func record(_ result: SyncResult) async -> SyncResult {
        let syncStartDate = await engine.settings.load().syncStartDate
        var log = (try? await engine.activityLog.load()) ?? []
        var recorded: [ActivityLogEntry] = []
        for action in result.actions where !isOldHistory(action, syncStartDate: syncStartDate) {
            if let entry = await entry(for: action, log: log) {
                recorded.append(entry)
            }
        }
        guard !recorded.isEmpty else { return result }
        for case .release(let workoutID, let eventID) in result.actions {
            log = log.map { $0.lettingGoOfEvent(eventID, workoutID: workoutID) }
        }
        try? await engine.activityLog.save((recorded.reversed() + log).trimmedToCapacity())
        return result
    }

    /// Whether the action skips a workout from before the sync start date, for any
    /// reason. Health sends the whole history again when the anchor is lost, e.g. after
    /// a reinstall, and the filters may leave old workouts out before the date does.
    private func isOldHistory(_ action: SyncAction, syncStartDate: Date?) -> Bool {
        guard case .skip(let workoutID, _) = action, let syncStartDate,
              let workout = added.first(where: { $0.id == workoutID }) else { return false }
        return workout.start < syncStartDate
    }

    private func entry(for action: SyncAction, log: [ActivityLogEntry]) async -> ActivityLogEntry? {
        switch action {
        case .skip(_, .beforeSyncStartDate), .skip(_, .alreadySynced):
            // Health sends the whole history again when the anchor is lost, e.g. after a
            // reinstall. These skips repeat old decisions and would push out every
            // useful entry.
            return nil
        default:
            break
        }
        let workout = added.first { $0.id == action.workoutID }
        // A replacement's entry is found by its event, since it covered the deleted workout.
        let previous = before.first { entry in
            entry.covers(action.workoutID) || (entry.eventExternalIdentifier != nil && entry.eventExternalIdentifier == action.eventID)
        }
        // What the event held before the pass changed it, if it did.
        let replaced = [action.eventID, previous?.eventExternalIdentifier].lazy.compactMap { $0.flatMap { changed[$0] } }.first
        var entry = ActivityLogEntry(
            date: engine.clock.now,
            action: action,
            title: replaced?.content.title
                ?? previous.flatMap { loggedTitle(of: $0, in: log) }
                ?? workout.map { "\($0.activityType.emoji) \($0.activityType.name)" } ?? "",
            activityType: workout?.activityType ?? previous?.activityType,
            workoutStart: workout?.start ?? previous?.workoutStart,
            eventID: action.eventID ?? previous?.eventExternalIdentifier
        )
        switch action {
        case .create(let workoutID, let draft):
            entry.title = draft.content.title
            entry.workoutStart = draft.content.start
            let created = try? await engine.ledger.entries(forWorkout: workoutID).first { $0.state == .owned }
            entry.eventID = created?.eventExternalIdentifier
            entry.ledgerEntryID = created?.id
            entry.undo = .removeCreatedEvent
        case .relink(_, let eventID):
            if let title = try? await engine.calendar.event(withID: eventID)?.content.title {
                entry.title = title
            }
        case .adopt(let workoutID, _, let content, _):
            // The planned event keeps the user's title.
            entry.title = content.title
            let adopted = try? await engine.ledger.entries(forWorkout: workoutID).first { $0.state == .adopted }
            entry.ledgerEntryID = adopted?.id
            entry.undo = adopted?.preUpdate.map { .restorePlannedEvent($0) }
        case .update(let workoutID, let eventID, let content):
            entry.title = content.title
            // An adopted event's own Undo is on its adoption's log entry.
            entry.undo = previous == nil || previous?.state == .adopted ? nil : replaced.map { .restoreEvent($0.content) }
            entry.ledgerEntryID = (try? await engine.ledger.entries(forWorkout: workoutID))?
                .first { $0.eventExternalIdentifier == eventID }?.id ?? previous?.id
        case .removeWorkoutSection(_, _, let content):
            entry.title = content.title
        case .delete:
            if let replaced, let calendarID = previous?.calendarID {
                entry.undo = .recreateEvent(EventDraft(calendarID: calendarID, content: replaced.content))
            }
        default:
            break
        }
        return entry
    }

    /// The title the log last showed for the ledger entry's event, e.g. its create's.
    private func loggedTitle(of ledgerEntry: LedgerEntry, in log: [ActivityLogEntry]) -> String? {
        log.first { logged in
            !logged.title.isEmpty && (logged.ledgerEntryID == ledgerEntry.id
                || (logged.eventID != nil && logged.eventID == ledgerEntry.eventExternalIdentifier))
        }?.title
    }
}

/// The events a pass is about to change, as the app wrote them, by event ID. Only the
/// first copy of each is kept: what the event held before the pass.
final class EventsBeforeChange: Sendable {
    private let events = Mutex<[String: CalendarEvent]>([:])

    func record(_ event: CalendarEvent) {
        events.withLock { events in
            if events[event.id] == nil {
                events[event.id] = event
            }
        }
    }

    subscript(eventID: String) -> CalendarEvent? {
        events.withLock { $0[eventID] }
    }
}

extension SyncEngine {
    /// Where the running pass keeps the events it changes, for the activity log.
    @TaskLocal static var eventsBeforeChange: EventsBeforeChange?
}

extension ActivityLogEntry {
    /// The entry without its Undo, if undoing it would overwrite or delete an event
    /// the user has since edited and the app has let go of. Only Undo of a delete,
    /// which makes a new event, stays.
    func lettingGoOfEvent(_ eventID: String, workoutID: UUID) -> ActivityLogEntry {
        guard self.eventID == eventID || self.workoutID == workoutID else { return self }
        switch undo {
        case nil, .recreateEvent:
            return self
        default:
            var entry = self
            entry.undo = nil
            return entry
        }
    }
}

private extension SyncAction {
    var eventID: String? {
        switch self {
        case .update(_, let eventID, _), .delete(_, let eventID), .release(_, let eventID), .relink(_, let eventID),
             .adopt(_, let eventID, _, _), .removeWorkoutSection(_, let eventID, _): eventID
        case .create, .skip, .holdForReview: nil
        }
    }
}
