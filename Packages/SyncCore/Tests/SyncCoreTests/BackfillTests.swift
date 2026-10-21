import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Backfill")
struct BackfillTests {
    @Test("A preview lists the events it would create and writes nothing")
    func previewWritesNothing() async throws {
        let older = SyncHarness.run(minutesAgo: 10 * 24 * 60)
        let recent = SyncHarness.run(minutesAgo: 2 * 24 * 60)
        let harness = SyncHarness(workouts: [recent, older])

        let result = try await harness.engine.run(.backfill(SyncHarness.lastDays(14), .preview))

        #expect(result.actions.map(\.createdWorkoutID) == [older.id, recent.id])
        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await harness.ledger.allEntries.isEmpty)
        #expect(await harness.settings.load() == SyncHarness.defaultSettings)
    }

    @Test("A commit takes exactly the actions its preview listed: new events, re-links and skips")
    func commitMatchesPreview() async throws {
        let new = SyncHarness.run(minutesAgo: 9 * 24 * 60)
        let synced = SyncHarness.run(minutesAgo: 6 * 24 * 60)
        let tombstoned = SyncHarness.run(minutesAgo: 5 * 24 * 60)
        let earlierInstall = SyncHarness.run(minutesAgo: 4 * 24 * 60)
        let short = SyncHarness.run(minutes: 5, minutesAgo: 3 * 24 * 60)
        let walk = SyncHarness.walk(minutesAgo: 2 * 24 * 60)
        let harness = SyncHarness(workouts: [new, synced, tombstoned, earlierInstall, short, walk])
        let syncedEvent = try await SyncHarness.eventLeftByEarlierInstall(for: synced, id: "synced")
        let footerEvent = try await SyncHarness.eventLeftByEarlierInstall(for: earlierInstall)
        await harness.calendar.put(syncedEvent)
        await harness.calendar.put(footerEvent)
        try await harness.ledger.save(SyncHarness.ownedEntry(for: synced, eventID: "synced"))
        try await harness.ledger.save(SyncHarness.ownedEntry(for: synced, eventID: "synced", updatedAt: SyncHarness.now.addingTimeInterval(-60)))
        try await harness.ledger.save(LedgerEntry(workoutID: tombstoned.id, workoutStart: tombstoned.start, workoutEnd: tombstoned.end, state: .tombstoned, createdAt: SyncHarness.now, updatedAt: SyncHarness.now))
        let ledgerBefore = await harness.ledger.allEntries

        let preview = try await harness.engine.run(.backfill(SyncHarness.lastDays(14), .preview))

        #expect(await harness.calendar.allEvents.count == 2)
        #expect(await harness.ledger.allEntries == ledgerBefore)

        let commit = try await harness.engine.run(.backfill(SyncHarness.lastDays(14), .commit))

        #expect(commit == preview)
        #expect(commit.actions.map(\.createdWorkoutID).compactMap { $0 } == [new.id])
        #expect(commit.actions.contains(.skip(workoutID: synced.id, .alreadySynced)))
        #expect(commit.actions.contains(.skip(workoutID: tombstoned.id, .tombstoned)))
        #expect(commit.actions.contains(.relink(workoutID: earlierInstall.id, eventID: footerEvent.id)))
        #expect(commit.actions.contains(.skip(workoutID: short.id, .tooShort)))
        #expect(commit.actions.contains(.skip(workoutID: walk.id, .typeDisabled)))
        #expect(await harness.calendar.allEvents.count == 3)
        let entry = try #require(await harness.ledger.entries(forWorkout: new.id).first)
        #expect(entry.state == .owned)
    }

    @Test("A commit moves the sync start date back to the start of the range, and a preview leaves it alone")
    func commitMovesSyncStartDateBack() async throws {
        let harness = SyncHarness()
        let range = SyncHarness.lastDays(30)

        _ = try await harness.engine.run(.backfill(range, .preview))
        #expect(await harness.settings.load().syncStartDate == SyncHarness.defaultSettings.syncStartDate)

        _ = try await harness.engine.run(.backfill(range, .commit))
        #expect(await harness.settings.load().syncStartDate == range.start)

        _ = try await harness.engine.run(.backfill(SyncHarness.lastDays(1), .commit))
        #expect(await harness.settings.load().syncStartDate == range.start)
    }

    @Test("Repeating a backfill over the same range creates nothing new")
    func repeatIsNoOp() async throws {
        let workouts = [SyncHarness.run(minutesAgo: 10 * 24 * 60), SyncHarness.run(minutesAgo: 2 * 24 * 60)]
        let harness = SyncHarness(workouts: workouts)
        _ = try await harness.engine.run(.backfill(SyncHarness.lastDays(14), .commit))
        let events = await harness.calendar.allEvents
        let entries = await harness.ledger.allEntries

        let preview = try await harness.engine.run(.backfill(SyncHarness.lastDays(14), .preview))
        let again = try await harness.engine.run(.backfill(SyncHarness.lastDays(14), .commit))

        #expect(preview.actions.allSatisfy { $0.createdWorkoutID == nil })
        #expect(again.actions == workouts.map { .skip(workoutID: $0.id, .alreadySynced) })
        #expect(await harness.calendar.allEvents == events)
        #expect(await harness.ledger.allEntries == entries)
    }

    @Test("A changes pass after a backfill doesn't add the backfilled workouts again")
    func changesAfterBackfillAddNothing() async throws {
        let workout = SyncHarness.run(minutesAgo: 10 * 24 * 60)
        let harness = SyncHarness(workouts: [workout])
        _ = try await harness.engine.run(.backfill(SyncHarness.lastDays(14), .commit))

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions == [.skip(workoutID: workout.id, .alreadySynced)])
        #expect(await harness.calendar.allEvents.count == 1)
    }

    @Test("Workouts outside the range are left out")
    func outsideRangeIsLeftOut() async throws {
        let inside = SyncHarness.run(minutesAgo: 2 * 24 * 60)
        let outside = SyncHarness.run(minutesAgo: 20 * 24 * 60)
        let harness = SyncHarness(workouts: [inside, outside])

        let result = try await harness.engine.run(.backfill(SyncHarness.lastDays(14), .commit))

        #expect(result.actions.map(\.createdWorkoutID) == [inside.id])
        #expect(await harness.calendar.allEvents.count == 1)
    }

    @Test("In add-only mode, a backfill creates events only for workouts the ledger doesn't know")
    func addOnlyUsesLedger() async throws {
        let synced = SyncHarness.run(minutesAgo: 10 * 24 * 60)
        let new = SyncHarness.run(minutesAgo: 2 * 24 * 60)
        let harness = SyncHarness(workouts: [synced, new], accessMode: .addOnly)
        try await harness.ledger.save(SyncHarness.ownedEntry(for: synced, eventID: "synced"))

        let preview = try await harness.engine.run(.backfill(SyncHarness.lastDays(14), .preview))
        let commit = try await harness.engine.run(.backfill(SyncHarness.lastDays(14), .commit))

        #expect(commit == preview)
        #expect(commit.actions == [.skip(workoutID: synced.id, .alreadySynced), commit.actions[1]])
        #expect(commit.actions[1].createdWorkoutID == new.id)
    }

    @Test("Before setup finishes, a backfill does nothing")
    func beforeSetupDoesNothing() async throws {
        var settings = SyncHarness.defaultSettings
        settings.destinationCalendar = nil
        let harness = SyncHarness(workouts: [SyncHarness.run(minutesAgo: 2 * 24 * 60)], settings: settings)

        let result = try await harness.engine.run(.backfill(SyncHarness.lastDays(14), .commit))

        #expect(result.actions.isEmpty)
        #expect(await harness.calendar.allEvents.isEmpty)
    }
}

extension SyncHarness {
    /// The `days` before now.
    static func lastDays(_ days: Double) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-days * 24 * 60 * 60), end: now)
    }

    /// A walk, which the default settings leave out.
    static func walk(minutesAgo: Double) -> Workout {
        let end = now.addingTimeInterval(-minutesAgo * 60)
        return Workout(activityType: .walking, start: end.addingTimeInterval(-40 * 60), end: end, source: watch)
    }
}

extension SyncAction {
    /// The workout an event is created for, or nil for any other action.
    var createdWorkoutID: UUID? {
        if case .create(let workoutID, _) = self { workoutID } else { nil }
    }
}
