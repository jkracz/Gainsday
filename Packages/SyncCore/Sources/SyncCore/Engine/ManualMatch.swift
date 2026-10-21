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
}

extension ActivityLogEntry {
    /// Whether the user can match this entry's workout to an event they planned: the
    /// entry added a separate event, which hasn't been undone or matched already. [v1.1]
    public var canMatchToEvent: Bool {
        guard case .create = action else { return false }
        return canUndo
    }
}

/// "Match to an event…": when a planned event reached the phone too late to be
/// matched, the user picks it from the activity log. The plan is adopted as if it had
/// matched, and the workout's separate event is removed. [v1.1]
extension SyncEngine {
    /// The events the user can match the entry's workout to: the planned-event
    /// candidates the matching rules see, without the keyword rules, and never an
    /// event with guests.
    ///
    /// Needs full calendar access, and throws `CalendarStoreError.requiresFullAccess`
    /// in add-only mode.
    public func matchCandidates(forEntryID entryID: UUID) async throws -> [CalendarEvent] {
        let (_, ledgerEntry, cluster) = try await matchableWorkout(forEntryID: entryID)
        return try await matchCandidates(for: cluster.preferred, ledgerEntry: ledgerEntry)
    }

    /// Adopts the planned event for the entry's workout and deletes its separate event,
    /// then logs the match with an Undo that restores both.
    ///
    /// Needs full calendar access, and throws `CalendarStoreError.requiresFullAccess`
    /// in add-only mode.
    @discardableResult
    public func match(entryID: UUID, toEventID eventID: String) async throws -> ActivityLogEntry {
        let (logEntry, ledgerEntry, cluster) = try await matchableWorkout(forEntryID: entryID)
        let candidates = try await matchCandidates(for: cluster.preferred, ledgerEntry: ledgerEntry)
        guard let plan = candidates.first(where: { $0.id == eventID }) else { throw ManualMatchError.eventNotOffered }

        // What the separate event holds now, so Undo can add it back as it was.
        var separate: CalendarEvent?
        if let separateID = ledgerEntry.eventExternalIdentifier {
            separate = try await calendar.event(withID: separateID)
        }
        guard let content = separate?.content ?? ledgerEntry.written,
              let calendarID = separate?.calendarID ?? ledgerEntry.calendarID else { throw ManualMatchError.notMatchable }
        let separateDraft = EventDraft(calendarID: calendarID, content: content)

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
        try await ledger.delete(entryID: ledgerEntry.id)

        let matched = ActivityLogEntry(
            date: clock.now,
            action: action,
            title: plan.content.title,
            activityType: cluster.preferred.activityType,
            workoutStart: cluster.preferred.start,
            eventID: plan.id,
            undo: .separateFromPlannedEvent(separateDraft, createEntryID: logEntry.id)
        )
        var log = try await activityLog.load()
        if let index = log.firstIndex(where: { $0.id == logEntry.id }) {
            // The separate event has gone, so there's nothing for the create's Undo to remove.
            log[index].undo = nil
        }
        try await activityLog.save(Array(([matched] + log).prefix(ActivityLogEntry.capacity)))
        return matched
    }

    /// The log entry, its workout's owned ledger entry and the workout's copies still in Health.
    private func matchableWorkout(forEntryID entryID: UUID) async throws -> (ActivityLogEntry, LedgerEntry, WorkoutCluster) {
        guard await calendar.accessMode() == .full else { throw CalendarStoreError.requiresFullAccess }
        guard let logEntry = try await activityLog.load().first(where: { $0.id == entryID }) else {
            throw ManualMatchError.entryNotFound
        }
        guard logEntry.canMatchToEvent,
              let resolved = try await resolvedEntry(forWorkout: logEntry.workoutID),
              resolved.state == .owned else { throw ManualMatchError.notMatchable }
        let ledgerEntry = try await correctExternalIdentifier(of: resolved)
        let members = try await healthWorkouts(in: ledgerEntry).sorted(by: Workout.isPreferred)
        guard let preferred = members.first(where: { $0.id == ledgerEntry.workoutID }) else {
            throw ManualMatchError.workoutNotFound
        }
        let cluster = WorkoutCluster(preferred: preferred, members: [preferred] + members.filter { $0.id != preferred.id })
        return (logEntry, ledgerEntry, cluster)
    }

    private func matchCandidates(for workout: Workout, ledgerEntry: LedgerEntry) async throws -> [CalendarEvent] {
        let settings = await settings.load()
        guard let destination = settings.destinationCalendar?.id ?? ledgerEntry.calendarID else { return [] }
        // Changing an event with guests can email every one of them.
        return try await plannedEventCandidates(for: workout, destination: destination, settings: settings)
            .filter { $0.attendeeCount == 0 }
    }
}
