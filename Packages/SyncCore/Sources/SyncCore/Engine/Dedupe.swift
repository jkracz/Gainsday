import Foundation

/// Finds events the app wrote earlier, so a reinstall, a new phone or a lost ledger
/// entry never leads to a duplicate.
extension SyncEngine {
    /// Dedupe steps 2 and 3 for a cluster the ledger doesn't know: looks for an event
    /// the app wrote for it earlier and records it in the ledger again as owned.
    /// Returns nil, so the caller creates the event, when there is none or the app
    /// can't read the calendar.
    func relinkEarlierEvent(for cluster: WorkoutCluster, in calendarID: String, composer: EventComposer) async throws -> SyncAction? {
        // In add-only mode the ledger is the only way to avoid duplicates.
        guard await calendar.accessMode() == .full else { return nil }
        let workout = cluster.preferred
        let expected = composer.content(for: workout)
        guard let event = try await findOwnEvent(for: cluster.memberIDs, matching: expected, in: calendarID) else {
            return nil
        }
        let now = clock.now
        try await ledger.save(LedgerEntry(
            workoutID: workout.id,
            memberIDs: cluster.memberIDs,
            workoutStart: workout.start,
            workoutEnd: workout.end,
            state: .owned,
            eventExternalIdentifier: event.id,
            calendarID: event.calendarID,
            // The app doesn't know what it wrote back then. The event as it is now is
            // the baseline for spotting later user edits.
            written: event.content,
            createdAt: now,
            updatedAt: now,
            activityType: workout.activityType
        ))
        return .relink(workoutID: workout.id, eventID: event.id)
    }

    /// Re-reads the event's external identifier, which a server sync can change, and
    /// fixes it in the ledger. The stored identifier is only a hint: when no event in
    /// the entry's calendar has it, the event is found by footer or by what the app wrote.
    /// Returns the entry as it is now in the ledger.
    @discardableResult
    func correctExternalIdentifier(of entry: LedgerEntry) async throws -> LedgerEntry {
        guard entry.state == .owned || entry.state == .adopted,
              let calendarID = entry.calendarID,
              await calendar.accessMode() == .full else { return entry }
        let expected = entry.written ?? EventContent(title: "", start: entry.workoutStart, end: entry.workoutEnd)
        guard let event = try await findOwnEvent(for: entry.memberIDs.union([entry.workoutID]), matching: expected, in: calendarID, knownID: entry.eventExternalIdentifier),
              event.id != entry.eventExternalIdentifier else { return entry }
        var corrected = entry
        corrected.eventExternalIdentifier = event.id
        corrected.updatedAt = clock.now
        try await ledger.save(corrected)
        return corrected
    }

    /// The app's event for the workout in the calendar, during `expected`'s times:
    /// the one with `knownID` if it's there, then by the footer's short id, then by
    /// the same title and times (±1 min). The footer may name any of the cluster's
    /// members. Events the ledger links to other workouts are never picked.
    func findOwnEvent(for workoutIDs: Set<UUID>, matching expected: EventContent, in calendarID: String, knownID: String? = nil) async throws -> CalendarEvent? {
        let window = DateInterval(start: expected.start, end: max(expected.start, expected.end))
        let claimed = Set(try await ledger.entries(in: window)
            .filter { entry in !workoutIDs.contains(where: entry.covers) }
            .compactMap(\.eventExternalIdentifier))
        let candidates = try await calendar.events(in: window, calendarIDs: [calendarID])
            .filter { !claimed.contains($0.id) }
            .sorted { ($0.content.start, $0.id) < ($1.content.start, $1.id) }
        return candidates.first { knownID != nil && $0.id == knownID }
            ?? candidates.first { event in workoutIDs.contains { Footer.isPresent(in: event.content.notes, workoutID: $0) } }
            ?? candidates.first { $0.content.title == expected.title && Self.sameTimes($0.content, expected) }
    }

    private static func sameTimes(_ a: EventContent, _ b: EventContent) -> Bool {
        abs(a.start.timeIntervalSince(b.start)) <= 60 && abs(a.end.timeIntervalSince(b.end)) <= 60
    }
}
