import Foundation

/// Finds events the app wrote earlier, so a reinstall, a new phone or a lost ledger
/// entry never leads to a duplicate.
extension SyncEngine {
    /// Dedupe steps 2 and 3 for a cluster the ledger doesn't know: looks for an event
    /// the app wrote for it earlier and records it in the ledger again. A planned event
    /// the app matched to the workout, found by its workout section, is recorded as
    /// adopted; any other event as owned. Returns nil, so the caller creates the event,
    /// when there is none or the app can't read the calendar.
    func relinkEarlierEvent(for cluster: WorkoutCluster, in calendarID: String, composer: EventComposer) async throws -> SyncAction? {
        // In add-only mode the ledger is the only way to avoid duplicates.
        guard await calendar.accessMode() == .full else { return nil }
        let workout = cluster.preferred
        let event: CalendarEvent
        let state: LedgerEntry.State
        if let plan = try await findMatchedPlan(for: cluster, destination: calendarID, settings: composer.settings) {
            (event, state) = (plan, .adopted)
        } else if let own = try await findOwnEvent(for: cluster.memberIDs, matching: ExpectedEvent(composer.content(for: workout)), in: calendarID) {
            (event, state) = (own, .owned)
        } else {
            return nil
        }
        let now = clock.now
        try await ledger.save(LedgerEntry(
            workoutID: workout.id,
            memberIDs: cluster.memberIDs,
            workoutStart: workout.start,
            workoutEnd: workout.end,
            state: state,
            eventExternalIdentifier: event.id,
            calendarID: event.calendarID,
            // The app doesn't know what it wrote back then. The event as it is now is
            // the baseline for spotting later user edits. A plan's content from before
            // the match is lost too, so it has no Undo.
            writtenFingerprint: event.content.fingerprint,
            createdAt: now,
            updatedAt: now,
            activityType: workout.activityType
        ))
        return .relink(workoutID: workout.id, eventID: event.id)
    }

    /// A planned event the app matched to one of the cluster's workouts, found by its
    /// workout section in the destination or, while matching is on, a calendar searched
    /// for plans. Other calendars aren't read while matching is off.
    private func findMatchedPlan(for cluster: WorkoutCluster, destination calendarID: String, settings: Settings) async throws -> CalendarEvent? {
        var calendarIDs: Set<String> = [calendarID]
        if settings.matchingEnabled, settings.matchMode == .updatePlannedEvent {
            calendarIDs.formUnion(try await searchCalendarIDs(destination: calendarID, settings: settings))
        }
        return try await unclaimedEvents(for: cluster.memberIDs, during: cluster.interval, in: calendarIDs)
            .first { $0.hasWorkoutSection(for: cluster.memberIDs) }
    }

    /// Re-reads the event's external identifier, which a server sync can change, and
    /// fixes it in the ledger. The stored identifier is only a hint: when no event in
    /// the entry's calendar has it, the event is found by footer or by what the app wrote,
    /// or, for a matched plan, by its workout section, which survives a rename.
    /// Returns the entry as it is now in the ledger.
    @discardableResult
    func correctExternalIdentifier(of entry: LedgerEntry) async throws -> LedgerEntry {
        guard entry.state == .owned || entry.state == .adopted,
              let calendarID = entry.calendarID,
              await calendar.accessMode() == .full else { return entry }
        guard let event = try await findOwnEvent(
            for: entry.memberIDs.union([entry.workoutID]),
            matching: ExpectedEvent(entry),
            in: calendarID,
            knownID: entry.eventExternalIdentifier,
            adopted: entry.state == .adopted
        ), event.id != entry.eventExternalIdentifier else { return entry }
        var corrected = entry
        corrected.eventExternalIdentifier = event.id
        corrected.updatedAt = clock.now
        try await ledger.save(corrected)
        return corrected
    }

    /// The app's event for the workout in the calendar, during `expected`'s times:
    /// the one with `knownID` if it's there, then by the footer's short id, then by
    /// the same title and times (±1 min), then by exactly what was written. The footer
    /// may name any of the cluster's members. Events the ledger links to other
    /// workouts are never picked.
    ///
    /// A planned event the app matched is the user's, so it's never taken for an owned
    /// event. For an `adopted` entry it's found by its workout section instead.
    func findOwnEvent(for workoutIDs: Set<UUID>, matching expected: ExpectedEvent, in calendarID: String, knownID: String? = nil, adopted: Bool = false) async throws -> CalendarEvent? {
        let window = DateInterval(start: expected.start, end: max(expected.start, expected.end))
        let candidates = try await unclaimedEvents(for: workoutIDs, during: window, in: [calendarID])
        if let known = candidates.first(where: { knownID != nil && $0.id == knownID }) {
            return known
        }
        if adopted {
            return candidates.first { $0.hasWorkoutSection(for: workoutIDs) }
        }
        let unmatched = candidates.filter { !WorkoutSection.isAnyPresent(in: $0.content.notes) }
        return unmatched.first { event in workoutIDs.contains { Footer.isPresent(in: event.content.notes, workoutID: $0) } }
            ?? unmatched.first { expected.written.hasTitle($0.content.title) && Self.sameTimes($0.content, expected) }
            ?? unmatched.first { $0.content.matches(expected.written) }
    }

    /// The calendars' events during `window` that the ledger doesn't link to other workouts.
    private func unclaimedEvents(for workoutIDs: Set<UUID>, during window: DateInterval, in calendarIDs: Set<String>) async throws -> [CalendarEvent] {
        let claimed = Set(try await ledger.entries(in: window)
            .filter { entry in !workoutIDs.contains(where: entry.covers) }
            .compactMap(\.eventExternalIdentifier))
        return try await calendar.events(in: window, calendarIDs: calendarIDs)
            .filter { !claimed.contains($0.id) }
            .sorted { ($0.content.start, $0.id) < ($1.content.start, $1.id) }
    }

    private static func sameTimes(_ a: EventContent, _ b: ExpectedEvent) -> Bool {
        abs(a.start.timeIntervalSince(b.start)) <= 60 && abs(a.end.timeIntervalSince(b.end)) <= 60
    }
}

/// What finding an event the app wrote goes on: the times it should be at, and the
/// fingerprint of what was written, whose title part finds it by title.
struct ExpectedEvent {
    var start: Date
    var end: Date
    var written: ContentFingerprint

    /// The event the app would write now.
    init(_ content: EventContent) {
        start = content.start
        end = content.end
        written = content.fingerprint
    }

    /// The event a ledger entry links, at its workout's times. The ledger keeps only a
    /// fingerprint of the content. With none, the title is taken to be empty.
    init(_ entry: LedgerEntry) {
        start = entry.workoutStart
        end = entry.workoutEnd
        written = entry.writtenFingerprint ?? EventContent(title: "", start: entry.workoutStart, end: entry.workoutEnd).fingerprint
    }
}

private extension CalendarEvent {
    /// Whether the event carries a workout section for any of the workouts.
    func hasWorkoutSection(for workoutIDs: Set<UUID>) -> Bool {
        workoutIDs.contains { WorkoutSection.isPresent(in: content.notes, workoutID: $0) }
    }
}
