import Foundation

extension SyncEngine {
    /// Undoes an update to a planned event: puts the event back exactly as the user
    /// planned it and lets go of it. Then the workout either gets its own owned event,
    /// as if no plan had matched, or is tombstoned so it's never added. [v1.1]
    ///
    /// Works after the workout was replaced or deleted in Health too: the adoption's
    /// ledger entry is also found by its event, and without one the log's copy of the
    /// plan is enough. Returns what was done for the workout, for the activity log.
    func restorePlannedEvent(
        _ planned: EventContent,
        of logEntry: ActivityLogEntry,
        choice: ActivityLogEntry.PlannedEventUndoChoice
    ) async throws -> (actions: [SyncAction], workouts: [Workout]) {
        guard case .adopt(_, let adoptedEventID, let adopted, _) = logEntry.action else { throw UndoError.notUndoable }
        let entries = try await adoptionEntries(of: logEntry.workoutID, eventID: adoptedEventID, workoutTimes: adopted)
        let eventID = entries.compactMap(\.eventExternalIdentifier).first ?? adoptedEventID
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

    /// The live ledger entries for an adopted event: those covering the workout, and
    /// those linked to the event, e.g. after a replacement in Health took over the workout.
    private func adoptionEntries(of workoutID: UUID, eventID: String, workoutTimes: EventContent) async throws -> [LedgerEntry] {
        let times = DateInterval(start: workoutTimes.start, end: max(workoutTimes.start, workoutTimes.end))
        let linked = try await ledger.entries(in: times).filter { $0.eventExternalIdentifier == eventID }
        var seen = Set<UUID>()
        return (try await ledger.entries(forWorkout: workoutID) + linked)
            .filter { $0.state != .tombstoned && seen.insert($0.id).inserted }
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
