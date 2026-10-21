import Foundation

/// Finds events the app wrote earlier, so a reinstall, a new phone or a lost ledger
/// entry never leads to a duplicate.
extension SyncEngine {
    /// Dedupe steps 2 and 3 for a workout the ledger doesn't know: looks for an event
    /// the app wrote for it earlier and records it in the ledger again as owned.
    /// Returns nil, so the caller creates the event, when there is none or the app
    /// can't read the calendar.
    func relinkEarlierEvent(for workout: Workout, in calendarID: String, composer: EventComposer) async throws -> SyncAction? {
        // In add-only mode the ledger is the only way to avoid duplicates.
        guard await calendar.accessMode() == .full else { return nil }
        let expected = composer.content(for: workout)
        guard let event = try await findOwnEvent(for: workout.id, matching: expected, in: calendarID) else {
            return nil
        }
        let now = clock.now
        try await ledger.save(LedgerEntry(
            workoutID: workout.id,
            workoutStart: workout.start,
            workoutEnd: workout.end,
            state: .owned,
            eventExternalIdentifier: event.id,
            calendarID: event.calendarID,
            // The app doesn't know what it wrote back then. The event as it is now is
            // the baseline for spotting later user edits.
            written: event.content,
            createdAt: now,
            updatedAt: now
        ))
        return .relink(workoutID: workout.id, eventID: event.id)
    }

    /// Re-reads the event's external identifier, which a server sync can change, and
    /// fixes it in the ledger. The stored identifier is only a hint: when no event in
    /// the entry's calendar has it, the event is found by footer or by what the app wrote.
    func correctExternalIdentifier(of entry: LedgerEntry) async throws {
        guard entry.state == .owned || entry.state == .adopted,
              let calendarID = entry.calendarID,
              await calendar.accessMode() == .full else { return }
        let expected = entry.written ?? EventContent(title: "", start: entry.workoutStart, end: entry.workoutEnd)
        guard let event = try await findOwnEvent(for: entry.workoutID, matching: expected, in: calendarID, knownID: entry.eventExternalIdentifier),
              event.id != entry.eventExternalIdentifier else { return }
        var corrected = entry
        corrected.eventExternalIdentifier = event.id
        corrected.updatedAt = clock.now
        try await ledger.save(corrected)
    }

    /// The app's event for the workout in the calendar, during `expected`'s times:
    /// the one with `knownID` if it's there, then by the footer's short id, then by
    /// the same title and times (±1 min). Events the ledger links to other workouts
    /// are never picked.
    func findOwnEvent(for workoutID: UUID, matching expected: EventContent, in calendarID: String, knownID: String? = nil) async throws -> CalendarEvent? {
        let window = DateInterval(start: expected.start, end: max(expected.start, expected.end))
        let claimed = Set(try await ledger.entries(in: window)
            .filter { !$0.covers(workoutID) }
            .compactMap(\.eventExternalIdentifier))
        let candidates = try await calendar.events(in: window, calendarIDs: [calendarID])
            .filter { !claimed.contains($0.id) }
            .sorted { ($0.content.start, $0.id) < ($1.content.start, $1.id) }
        return candidates.first { knownID != nil && $0.id == knownID }
            ?? candidates.first { Footer.isPresent(in: $0.content.notes, workoutID: workoutID) }
            ?? candidates.first { $0.content.title == expected.title && Self.sameTimes($0.content, expected) }
    }

    private static func sameTimes(_ a: EventContent, _ b: EventContent) -> Bool {
        abs(a.start.timeIntervalSince(b.start)) <= 60 && abs(a.end.timeIntervalSince(b.end)) <= 60
    }
}
