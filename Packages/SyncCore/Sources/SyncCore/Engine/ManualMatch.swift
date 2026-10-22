import Foundation

public enum ManualMatchError: Error, Hashable, Sendable {
    /// The entry is no longer in the activity log.
    case entryNotFound
    /// The entry isn't a workout with its own event, or it was undone or matched already.
    case notMatchable
    /// The event isn't one the workout can be matched to, e.g. it has guests or has gone.
    case eventNotOffered
    /// The workout is no longer in Health.
    case workoutNotFound
    /// The workout wasn't added as an event, e.g. because the filters now leave it out.
    case notAdded(SkipReason)
    /// The user edited the workout's separate event, so it's theirs now and the app
    /// won't remove it. The entry can't be matched or undone any more.
    case eventEditedByUser
}

extension ActivityLogEntry {
    /// Whether the user can match this entry's workout to an event they planned: the
    /// workout waits for review, or the entry added a separate event that hasn't been
    /// undone or matched already. [v1.1]
    public var canMatchToEvent: Bool {
        if isAwaitingReview { return true }
        guard case .create = action else { return false }
        return canUndo && undo == .removeCreatedEvent
    }
}

/// A workout the user is settling by hand from the activity log. [v1.1]
struct SettlingWorkout {
    var logEntry: ActivityLogEntry
    /// The owned entry for the workout's separate event, or nil for a workout held for review.
    var separate: LedgerEntry?
    /// The workout's copies still in Health.
    var cluster: WorkoutCluster
}

/// "Match to an event…": when a planned event reached the phone too late to be
/// matched, or the match was held for review, the user picks the plan from the
/// activity log. The plan is adopted as if it had matched, and the workout's separate
/// event, if it has one, is removed. [v1.1]
extension SyncEngine {
    /// The events the user can match the entry's workout to: the planned-event
    /// candidates the matching rules see, without the keyword rules, and never an
    /// event with guests.
    ///
    /// Needs full calendar access, and throws `CalendarStoreError.requiresFullAccess`
    /// in add-only mode.
    public func matchCandidates(forEntryID entryID: UUID) async throws -> [CalendarEvent] {
        try await matchCandidates(for: settlingWorkout(forEntryID: entryID, if: \.canMatchToEvent))
    }

    /// Adopts the planned event for the entry's workout and deletes its separate event,
    /// then logs the match with an Undo that restores both, or for a held workout, holds
    /// it for review again.
    ///
    /// Needs full calendar access, and throws `CalendarStoreError.requiresFullAccess`
    /// in add-only mode.
    @discardableResult
    public func match(entryID: UUID, toEventID eventID: String) async throws -> ActivityLogEntry {
        let workout = try await settlingWorkout(forEntryID: entryID, if: \.canMatchToEvent)
        let cluster = workout.cluster
        guard let plan = try await matchCandidates(for: workout).first(where: { $0.id == eventID }) else {
            throw ManualMatchError.eventNotOffered
        }

        var undo = ActivityLogEntry.Undo.returnToReview(heldEntryID: workout.logEntry.id)
        var separate: CalendarEvent?
        if let ledgerEntry = workout.separate {
            // What the separate event holds now, so Undo can add it back as it was.
            if let separateID = ledgerEntry.eventExternalIdentifier {
                separate = try await calendar.event(withID: separateID)
            }
            if let separate, !separate.content.matches(ledgerEntry.writtenFingerprint) {
                try await release(ledgerEntry, from: workout)
                throw ManualMatchError.eventEditedByUser
            }
            // The ledger keeps only a fingerprint of the event, so one the user deleted
            // since the last pass couldn't be added back by Undo. That pass tombstones it.
            guard let separate else { throw ManualMatchError.notMatchable }
            undo = .separateFromPlannedEvent(EventDraft(calendarID: separate.calendarID, content: separate.content), createEntryID: workout.logEntry.id)
        }

        let settings = await settings.load()
        let action = try await adopt(plan, for: cluster, decidedBy: .user, settings: settings, composer: EventComposer(settings: settings, clock: clock))
        do {
            if let separate {
                try await calendar.delete(eventID: separate.id)
            }
        } catch {
            // Leave things as they were rather than show the workout twice.
            _ = try? await calendar.update(eventID: plan.id, to: plan.content)
            for entry in try await ledger.entries(forWorkout: cluster.preferred.id) where entry.state == .adopted {
                try? await ledger.delete(entryID: entry.id)
            }
            throw error
        }
        if let ledgerEntry = workout.separate {
            try await ledger.delete(entryID: ledgerEntry.id)
        }

        return try await recordSettled(workout, with: ActivityLogEntry(
            date: clock.now,
            action: action,
            title: plan.content.title,
            activityType: cluster.preferred.activityType,
            workoutStart: cluster.preferred.start,
            eventID: plan.id,
            ledgerEntryID: try await ledger.entries(forWorkout: cluster.preferred.id).first { $0.state == .adopted }?.id,
            undo: undo
        ))
    }

    /// The workout of a log entry the user can settle by hand, with its copies still in
    /// Health. A held workout must still have no ledger entry.
    func settlingWorkout(forEntryID entryID: UUID, if allowed: (ActivityLogEntry) -> Bool) async throws -> SettlingWorkout {
        guard await calendar.accessMode() == .full else { throw CalendarStoreError.requiresFullAccess }
        guard let logEntry = try await activityLog.load().first(where: { $0.id == entryID }) else {
            throw ManualMatchError.entryNotFound
        }
        guard allowed(logEntry) else { throw ManualMatchError.notMatchable }
        if logEntry.isAwaitingReview {
            let cluster = try await heldCluster(for: logEntry)
            guard try await existingEntry(for: cluster) == nil else { throw ManualMatchError.notMatchable }
            return SettlingWorkout(logEntry: logEntry, cluster: cluster)
        }

        guard let resolved = try await resolvedEntry(forWorkout: logEntry.workoutID),
              resolved.state == .owned else { throw ManualMatchError.notMatchable }
        let ledgerEntry = try await correctExternalIdentifier(of: resolved)
        let members = try await healthWorkouts(in: ledgerEntry).sorted(by: Workout.isPreferred)
        guard let preferred = members.first(where: { $0.id == ledgerEntry.workoutID }) else {
            throw ManualMatchError.workoutNotFound
        }
        let cluster = WorkoutCluster(preferred: preferred, members: [preferred] + members.filter { $0.id != preferred.id })
        return SettlingWorkout(logEntry: logEntry, separate: ledgerEntry, cluster: cluster)
    }

    /// Adds the entry for what the user did to the top of the log, and marks the entry
    /// they did it from: a held workout as reviewed, or a create as having nothing left
    /// to undo, since its separate event has gone. Earlier Undos of the separate event,
    /// e.g. of an update, go too.
    func recordSettled(_ workout: SettlingWorkout, with entry: ActivityLogEntry) async throws -> ActivityLogEntry {
        var log = try await activityLog.load()
        if let index = log.firstIndex(where: { $0.id == workout.logEntry.id }), workout.separate == nil {
            log[index].reviewedAt = clock.now
        }
        if let separate = workout.separate {
            for index in log.indices where log[index].ledgerEntryID == separate.id
                || (log[index].ledgerEntryID == nil && log[index].eventID != nil && log[index].eventID == separate.eventExternalIdentifier) {
                if case .recreateEvent = log[index].undo { continue }
                log[index].undo = nil
            }
            if let index = log.firstIndex(where: { $0.id == workout.logEntry.id }) {
                log[index].undo = nil
            }
        }
        let settled = ([entry] + log).trimmedToCapacity()
        try await activityLog.save(settled)
        await withdrawReviewNotification(ifNoneAwaitingIn: settled)
        return entry
    }

    /// Lets go of a separate event the user edited: it's theirs now, so its create can't
    /// be matched or undone any more.
    private func release(_ ledgerEntry: LedgerEntry, from workout: SettlingWorkout) async throws {
        var ledgerEntry = ledgerEntry
        ledgerEntry.state = .released
        ledgerEntry.updatedAt = clock.now
        try await ledger.save(ledgerEntry)
        var log = try await activityLog.load()
        if let index = log.firstIndex(where: { $0.id == workout.logEntry.id }) {
            log[index].undo = nil
            try await activityLog.save(log)
        }
    }

    private func matchCandidates(for workout: SettlingWorkout) async throws -> [CalendarEvent] {
        let settings = await settings.load()
        guard let destination = settings.destinationCalendar?.id ?? workout.separate?.calendarID else { return [] }
        // Changing an event with guests can email every one of them.
        let calendarIDs = try await searchCalendarIDs(destination: destination, settings: settings)
        return try await plannedEventCandidates(for: workout.cluster.preferred, in: calendarIDs, settings: settings)
            .filter { $0.attendeeCount == 0 }
    }
}
