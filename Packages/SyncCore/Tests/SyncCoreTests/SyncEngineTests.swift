import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Sync engine")
struct SyncEngineTests {
    @Test("A pass with no Health changes writes nothing and returns the next anchor")
    func quietPass() async throws {
        let harness = SyncHarness()

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.isEmpty)
        #expect(result.nextAnchor != nil)
        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await harness.ledger.allEntries.isEmpty)
    }

    @Test("The first pass creates one free event per workout, at the workout's real times, with the footer")
    func firstPassCreatesOneEventPerWorkout() async throws {
        let morning = SyncHarness.run(minutes: 45, minutesAgo: 6 * 60)
        let lunch = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let harness = SyncHarness(workouts: [morning, lunch])

        let result = try await harness.engine.run(.changes(since: nil))

        let events = await harness.calendar.allEvents
        #expect(events.count == 2)
        for (event, workout) in zip(events, [morning, lunch]) {
            #expect(event.calendarID == SyncHarness.destination.id)
            #expect(event.content.start == workout.start)
            #expect(event.content.end == workout.end)
            #expect(event.availability == .free)
            #expect(event.content.title.contains("Running"))
            #expect(event.content.notes?.hasSuffix("\n\n— Logged by Gainsday · \(workout.shortID)") == true)
        }
        #expect(result.actions.count == 2)
        #expect(result.actions.allSatisfy { if case .create = $0 { true } else { false } })
    }

    @Test("Each created event is recorded in the ledger as owned, with what was written")
    func firstPassRecordsLedgerEntries() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])

        _ = try await harness.engine.run(.changes(since: nil))

        let event = try #require(await harness.calendar.allEvents.first)
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.workoutID == workout.id)
        #expect(entry.state == .owned)
        #expect(entry.eventExternalIdentifier == event.id)
        #expect(entry.calendarID == SyncHarness.destination.id)
        #expect(entry.writtenFingerprint == event.content.fingerprint)
        #expect(entry.workoutStart == workout.start)
        #expect(entry.workoutEnd == workout.end)
        #expect(entry.createdAt == SyncHarness.now)
    }

    @Test("If the ledger can't record a new event, the event is removed so the next pass doesn't duplicate it")
    func ledgerFailureRemovesEvent() async throws {
        struct DiskFull: Error {}
        let harness = SyncHarness(workouts: [SyncHarness.run()])
        await harness.ledger.failSaves(with: DiskFull())

        await #expect(throws: DiskFull.self) {
            try await harness.engine.run(.changes(since: nil))
        }

        #expect(await harness.calendar.allEvents.isEmpty)
    }

    @Test("A second pass from the stored anchor is a no-op")
    func secondPassIsNoOp() async throws {
        let harness = SyncHarness(workouts: [SyncHarness.run()])
        let first = try await harness.engine.run(.changes(since: nil))

        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        #expect(second.actions.isEmpty)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(await harness.ledger.allEntries.count == 1)
    }

    @Test("A second pass that sees the same workout again skips it as already synced")
    func secondPassWithoutAnchorCreatesNoDuplicate() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        _ = try await harness.engine.run(.changes(since: nil))

        let second = try await harness.engine.run(.changes(since: nil))

        #expect(second.actions == [.skip(workoutID: workout.id, .alreadySynced)])
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(await harness.ledger.allEntries.count == 1)
    }

    @Test("Workouts that started before the sync start date are skipped")
    func preSetupWorkoutsAreSkipped() async throws {
        let lastMonth = SyncHarness.run(minutesAgo: 30 * 24 * 60)
        let today = SyncHarness.run()
        let harness = SyncHarness(workouts: [lastMonth, today])

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.contains(.skip(workoutID: lastMonth.id, .beforeSyncStartDate)))
        #expect(await harness.calendar.allEvents.map(\.content.start) == [today.start])
        #expect(await harness.ledger.allEntries.map(\.workoutID) == [today.id])
    }

    @Test("A workout with a tombstone is never given an event")
    func tombstonedWorkoutIsSkipped() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        try await harness.ledger.save(LedgerEntry(
            workoutID: workout.id,
            workoutStart: workout.start,
            workoutEnd: workout.end,
            state: .tombstoned,
            createdAt: SyncHarness.now,
            updatedAt: SyncHarness.now
        ))

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions == [.skip(workoutID: workout.id, .tombstoned)])
        #expect(await harness.calendar.allEvents.isEmpty)
    }

    @Test("With the footer turned off, the event's notes have no footer")
    func footerOff() async throws {
        var settings = SyncHarness.defaultSettings
        settings.footerEnabled = false
        let harness = SyncHarness(workouts: [SyncHarness.run()], settings: settings)

        _ = try await harness.engine.run(.changes(since: nil))

        let event = try #require(await harness.calendar.allEvents.first)
        #expect(event.content.notes?.contains("Logged by Gainsday") == false)
    }

    @Test("Before setup is finished, a pass reads nothing, writes nothing and keeps the anchor")
    func passBeforeSetup() async throws {
        let harness = SyncHarness(workouts: [SyncHarness.run()], settings: Settings())

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.isEmpty)
        #expect(result.nextAnchor == nil)
        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await harness.ledger.allEntries.isEmpty)
    }

    @Test("A backfill preview writes nothing")
    func backfillPreviewWritesNothing() async throws {
        let harness = SyncHarness(workouts: [SyncHarness.run()])
        let lastWeek = DateInterval(start: SyncHarness.now.addingTimeInterval(-7 * 24 * 60 * 60), end: SyncHarness.now)

        let result = try await harness.engine.run(.backfill(lastWeek, .preview))

        #expect(result.nextAnchor == nil)
        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await harness.ledger.allEntries.isEmpty)
    }
}
