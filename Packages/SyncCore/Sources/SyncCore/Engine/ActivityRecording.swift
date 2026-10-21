import Foundation

/// Turns the actions of a pass into activity log entries.
///
/// It's made before the pass, so it can remember what deleted workouts' events held:
/// undoing an update or a delete needs the content the pass replaced.
///
/// Recording is best effort. The events are already written by then, so losing a
/// log line is better than failing the pass.
struct ActivityRecorder {
    let engine: SyncEngine
    /// The workouts the pass reads.
    let added: [Workout]
    /// Ledger entries for the workouts deleted in Health, as they were before the pass.
    let before: [LedgerEntry]

    init(engine: SyncEngine, added: [Workout], deletedIDs: [UUID]) async throws {
        self.engine = engine
        self.added = added
        var before: [LedgerEntry] = []
        for deletedID in deletedIDs {
            before += try await engine.ledger.entries(forWorkout: deletedID)
        }
        self.before = before
    }

    /// Adds the result's actions to the top of the log, keeping it to its capacity.
    func record(_ result: SyncResult) async -> SyncResult {
        var recorded: [ActivityLogEntry] = []
        for action in result.actions {
            if let entry = await entry(for: action) {
                recorded.append(entry)
            }
        }
        guard !recorded.isEmpty else { return result }
        let log = (try? await engine.activityLog.load()) ?? []
        try? await engine.activityLog.save(Array((recorded.reversed() + log).prefix(ActivityLogEntry.capacity)))
        return result
    }

    private func entry(for action: SyncAction) async -> ActivityLogEntry? {
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
        var entry = ActivityLogEntry(
            date: engine.clock.now,
            action: action,
            title: previous?.written?.title ?? workout.map { "\($0.activityType.emoji) \($0.activityType.name)" } ?? "",
            activityType: workout?.activityType ?? previous?.activityType,
            workoutStart: workout?.start ?? previous?.workoutStart,
            eventID: action.eventID ?? previous?.eventExternalIdentifier
        )
        switch action {
        case .create(let workoutID, let draft):
            entry.title = draft.content.title
            entry.workoutStart = draft.content.start
            entry.eventID = try? await engine.ledger.entries(forWorkout: workoutID)
                .compactMap(\.eventExternalIdentifier).first
            entry.undo = .removeCreatedEvent
        case .relink(let workoutID, _):
            if let title = try? await engine.ledger.entries(forWorkout: workoutID).compactMap(\.written?.title).first {
                entry.title = title
            }
        case .update(_, _, let content):
            entry.title = content.title
            entry.undo = previous?.written.map { .restoreEvent($0) }
        case .delete:
            if let written = previous?.written, let calendarID = previous?.calendarID {
                entry.undo = .recreateEvent(EventDraft(calendarID: calendarID, content: written))
            }
        default:
            break
        }
        return entry
    }
}

private extension SyncAction {
    var eventID: String? {
        switch self {
        case .update(_, let eventID, _), .delete(_, let eventID), .release(_, let eventID), .relink(_, let eventID): eventID
        case .create, .skip, .holdForReview: nil
        }
    }
}
