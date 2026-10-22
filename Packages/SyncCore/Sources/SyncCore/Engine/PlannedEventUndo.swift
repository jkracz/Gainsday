import Foundation

extension SyncEngine {
    /// Undoes an update to a planned event: puts the event back exactly as the user
    /// planned it and lets go of it. Then the workout either gets its own owned event,
    /// as if no plan had matched, or is tombstoned so it's never added. [v1.1]
    ///
    /// Works after the workout was replaced in Health too, since the adoption's ledger
    /// entry follows the replacement. After the workout was deleted in Health, the log's
    /// copy of the plan is enough. Only while the plan is still as the app left it.
    /// Returns what was done for the workout, for the activity log.
    func restorePlannedEvent(
        _ planned: EventContent,
        of logEntry: ActivityLogEntry,
        choice: ActivityLogEntry.PlannedEventUndoChoice
    ) async throws -> (actions: [SyncAction], workouts: [Workout]) {
        guard case .adopt(_, let adoptedEventID, let adopted, _) = logEntry.action else { throw UndoError.notUndoable }
        var entries: [LedgerEntry] = []
        var eventID = adoptedEventID
        if let target = try await undoTarget(of: logEntry) {
            let (entry, event) = try await verified(target, of: logEntry, in: .adopted)
            guard let event else { throw UndoError.outOfDate }
            entries = [entry]
            eventID = event.id
        } else {
            try await checkPlanLeftByDeletedWorkout(adoptedEventID, adopted: adopted)
        }
        _ = try await calendar.update(eventID: eventID, to: planned)

        let now = clock.now
        var workout = entries.first ?? LedgerEntry(
            workoutID: logEntry.workoutID,
            workoutStart: adopted.start,
            workoutEnd: adopted.end,
            state: .tombstoned,
            createdAt: now,
            updatedAt: now,
            activityType: logEntry.activityType
        )
        workout.memberIDs = entries.reduce(workout.memberIDs.union([logEntry.workoutID])) { $0.union($1.memberIDs) }
        for entry in entries {
            try await ledger.delete(entryID: entry.id)
        }

        switch choice {
        case .dropWorkout:
            var tombstone = workout
            tombstone.id = UUID()
            tombstone.state = .tombstoned
            tombstone.eventExternalIdentifier = nil
            tombstone.calendarID = nil
            tombstone.written = nil
            tombstone.preUpdate = nil
            tombstone.createdAt = now
            tombstone.updatedAt = now
            try await ledger.save(tombstone)
            return ([], [])
        case .separateEvent:
            return try await syncSeparately(workout)
        }
    }

    /// Checks a plan whose adoption's ledger entry has gone, because Health deleted the
    /// workout and the app took its section out, can be put back: no other workout uses
    /// it, and it's still where the workout left it, with no workout section or guests.
    private func checkPlanLeftByDeletedWorkout(_ eventID: String, adopted: EventContent) async throws {
        guard try await liveEntries(linkedTo: eventID, around: adopted).isEmpty,
              let event = try await calendar.event(withID: eventID) else { throw UndoError.outOfDate }
        guard abs(event.content.start.timeIntervalSince(adopted.start)) < 1,
              abs(event.content.end.timeIntervalSince(adopted.end)) < 1,
              !WorkoutSection.isAnyPresent(in: event.content.notes),
              event.attendeeCount == 0 else { throw UndoError.eventEditedByUser }
    }

    /// Syncs the workout's copies still in Health as if no plan had matched.
    private func syncSeparately(_ workout: LedgerEntry) async throws -> (actions: [SyncAction], workouts: [Workout]) {
        try await syncSeparately(try await healthWorkouts(in: workout))
    }

    /// Syncs workouts as if no plan had matched.
    func syncSeparately(_ found: [Workout]) async throws -> (actions: [SyncAction], workouts: [Workout]) {
        var settings = await settings.load()
        guard let destination = settings.destinationCalendar else { return ([], []) }
        // The plan the user just took back must not be matched again.
        settings.matchingEnabled = false
        let composer = EventComposer(settings: settings, clock: clock)
        let workouts = settings.splitBySource(found).allowed
        var actions: [SyncAction] = []
        for cluster in WorkoutCluster.clusters(of: workouts) {
            actions.append(try await sync(cluster, to: destination.id, settings: settings, composer: composer))
        }
        return (actions, workouts)
    }
}
