import Foundation

extension ActivityLogEntry {
    /// Whether the entry is a workout held for review that the user hasn't settled yet. [v1.1]
    public var isAwaitingReview: Bool {
        guard case .holdForReview = action else { return false }
        return reviewedAt == nil
    }

    /// Whether the user can add the entry's held workout as a separate event. [v1.1]
    public var canAddAsSeparateEvent: Bool { isAwaitingReview }
}

extension [ActivityLogEntry] {
    /// The newest entries, up to the log's capacity, plus any older workouts still held
    /// for review: a held workout exists only as its log entry, so it's never dropped.
    /// A held entry the user settled stays while a kept entry can still undo that and
    /// hold it for review again.
    func trimmedToCapacity() -> [ActivityLogEntry] {
        let kept = enumerated().filter { $0.offset < ActivityLogEntry.capacity || $0.element.isAwaitingReview }.map(\.element)
        let reopenable = Set(kept.compactMap { entry -> UUID? in
            guard entry.canUndo, case .returnToReview(let heldEntryID) = entry.undo else { return nil }
            return heldEntryID
        })
        return enumerated().filter {
            $0.offset < ActivityLogEntry.capacity || $0.element.isAwaitingReview || reopenable.contains($0.element.id)
        }.map(\.element)
    }
}

/// Settling a workout held for review: the user matches it to a plan (see `match`)
/// or adds it as a separate event. Either can be undone, and the workout waits for
/// review again. [v1.1]
extension SyncEngine {
    /// Adds the held workout as its own event, as if no plan had matched, and logs it
    /// with an Undo that holds it for review again. Throws `ManualMatchError.notAdded`
    /// and leaves the workout held when it isn't added, e.g. the filters now leave it out.
    ///
    /// Needs full calendar access, and throws `CalendarStoreError.requiresFullAccess`
    /// in add-only mode.
    @discardableResult
    public func addSeparateEvent(entryID: UUID) async throws -> ActivityLogEntry {
        let workout = try await settlingWorkout(forEntryID: entryID, if: \.canAddAsSeparateEvent)
        let (actions, _) = try await syncSeparately(workout.cluster.members)
        let preferred = workout.cluster.preferred
        guard let action = actions.first else { throw ManualMatchError.workoutNotFound }
        if case .skip(_, let reason) = action {
            // Nothing was added, so the workout still waits for review.
            throw ManualMatchError.notAdded(reason)
        }
        var entry = ActivityLogEntry(
            date: clock.now,
            action: action,
            title: workout.logEntry.title,
            activityType: preferred.activityType,
            workoutStart: preferred.start
        )
        if case .create(let workoutID, let draft) = action {
            entry.title = draft.content.title
            let created = try await ledger.entries(forWorkout: workoutID).first { $0.state == .owned }
            entry.eventID = created?.eventExternalIdentifier
            entry.ledgerEntryID = created?.id
            entry.undo = .returnToReview(heldEntryID: workout.logEntry.id)
        }
        return try await recordSettled(workout, with: entry)
    }

    /// The held workout's copies still in Health, the way a pass clusters them.
    func heldCluster(for logEntry: ActivityLogEntry) async throws -> WorkoutCluster {
        guard let start = logEntry.workoutStart else { throw ManualMatchError.workoutNotFound }
        // Copies overlap the workout, and a workout rarely lasts longer than a day.
        let day: TimeInterval = 24 * 60 * 60
        let found = try await workouts.workouts(in: DateInterval(start: start.addingTimeInterval(-day), end: start.addingTimeInterval(day)))
        let allowed = await settings.load().splitBySource(found).allowed
        guard let cluster = WorkoutCluster.clusters(of: allowed).first(where: { $0.memberIDs.contains(logEntry.workoutID) }) else {
            throw ManualMatchError.workoutNotFound
        }
        return cluster
    }
}
