import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Activity log")
struct ActivityLogTests {
    @Test("A created event appears in the log, with its title and workout")
    func createIsLogged() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])

        let result = try await harness.engine.run(.changes(since: nil))

        let event = try #require(await harness.calendar.allEvents.first)
        let entry = try #require(await harness.activityLog.entries.first)
        #expect(await harness.activityLog.entries.count == 1)
        #expect(entry.action == result.actions.first)
        #expect(entry.date == SyncHarness.now)
        #expect(entry.title == event.content.title)
        #expect(entry.activityType == .running)
        #expect(entry.workoutStart == workout.start)
        #expect(entry.eventID == event.id)
        #expect(entry.canUndo)
    }

    @Test("Undoing a create removes the event, and the next pass doesn't recreate it")
    func undoCreateSticks() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        _ = try await harness.engine.run(.changes(since: nil))
        let entry = try #require(await harness.activityLog.entries.first)

        let undone = try await harness.engine.undo(entryID: entry.id)

        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await harness.ledger.allEntries.map(\.state) == [.tombstoned])
        #expect(undone.undoneAt == SyncHarness.now)
        #expect(await harness.activityLog.entries == [undone])
        #expect(undone.canUndo == false)

        // Even with the anchor lost, Health sends the workout again and it stays out.
        let next = try await harness.engine.run(.changes(since: nil))
        #expect(next.actions == [.skip(workoutID: workout.id, .tombstoned)])
        #expect(await harness.calendar.allEvents.isEmpty)
    }

    @Test("The log keeps the newest 50 entries, newest first")
    func logIsCapped() async throws {
        let harness = SyncHarness()
        var anchor: WorkoutAnchor?
        var workouts: [Workout] = []
        for index in 0..<55 {
            let workout = SyncHarness.run(minutes: 30, minutesAgo: Double(55 - index) * 60)
            workouts.append(workout)
            await harness.workouts.add(workout)
            anchor = try await harness.engine.run(.changes(since: anchor)).nextAnchor
        }

        let entries = await harness.activityLog.entries
        #expect(entries.count == 50)
        #expect(entries.map(\.workoutID) == workouts.suffix(50).reversed().map(\.id))
    }

    @Test("Deletes, releases and tombstones from Health changes are logged with the event's title")
    func lifecycleActionsAreLogged() async throws {
        let deleted = SyncHarness.run(minutesAgo: 300)
        let edited = SyncHarness.run(minutesAgo: 200)
        let removed = SyncHarness.run(minutesAgo: 100)
        let harness = SyncHarness(workouts: [deleted, edited, removed])
        let first = try await harness.engine.run(.changes(since: nil))
        let events = await harness.calendar.allEvents
        var editedEvent = events[1]
        editedEvent.content.title = "Easy run with Sam"
        await harness.calendar.put(editedEvent)
        await harness.calendar.remove(eventID: events[2].id)

        for workout in [deleted, edited, removed] {
            await harness.workouts.delete(workout.id)
        }
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        let logged = await harness.activityLog.entries.prefix(3).reversed()
        #expect(logged.map(\.action) == second.actions)
        #expect(logged.map(\.title) == events.map(\.content.title))
        #expect(logged.map(\.workoutStart) == [deleted.start, edited.start, removed.start])
        #expect(logged.map(\.activityType) == [.running, .running, .running])
        #expect(logged.map(\.eventID) == events.map(\.id))
        #expect(logged.map(\.canUndo) == [true, false, false])
    }

    @Test("Undoing a delete puts the event back as it was, and the app leaves it alone afterwards")
    func undoDeleteRecreatesEvent() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        let first = try await harness.engine.run(.changes(since: nil))
        let original = try #require(await harness.calendar.allEvents.first)
        await harness.workouts.delete(workout.id)
        _ = try await harness.engine.run(.changes(since: first.nextAnchor))
        let entry = try #require(await harness.activityLog.entries.first)

        try await harness.engine.undo(entryID: entry.id)

        let restored = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(restored.content == original.content)
        #expect(restored.calendarID == SyncHarness.destination.id)
        #expect(restored.availability == .free)
        let ledgerEntry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(ledgerEntry.state == .released)
        #expect(ledgerEntry.workoutID == workout.id)
        #expect(ledgerEntry.eventExternalIdentifier == restored.id)
    }

    @Test("Undoing an update puts back what the event held before, and a later Health delete leaves it alone")
    func undoUpdateRestoresEvent() async throws {
        let original = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let harness = SyncHarness(workouts: [original])
        let first = try await harness.engine.run(.changes(since: nil))
        let before = try #require(await harness.calendar.allEvents.first)
        let replacement = SyncHarness.run(minutes: 35, minutesAgo: 5)
        await harness.workouts.delete(original.id)
        await harness.workouts.add(replacement)
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))
        let entry = try #require(await harness.activityLog.entries.first)
        #expect(entry.workoutID == replacement.id)

        try await harness.engine.undo(entryID: entry.id)

        let restored = try #require(await harness.calendar.allEvents.first)
        #expect(restored.id == before.id)
        #expect(restored.content == before.content)
        #expect(await harness.ledger.allEntries.map(\.state) == [.released])

        await harness.workouts.delete(replacement.id)
        let third = try await harness.engine.run(.changes(since: second.nextAnchor))
        #expect(third.actions.isEmpty)
        #expect(await harness.calendar.allEvents == [restored])
    }

    @Test("Workouts Health sends again after the anchor is lost don't flood the log")
    func resentHistoryIsNotLogged() async throws {
        let old = SyncHarness.run(minutesAgo: 8 * 24 * 60)
        let synced = SyncHarness.run()
        let harness = SyncHarness(workouts: [old, synced])
        _ = try await harness.engine.run(.changes(since: nil))
        let logged = await harness.activityLog.entries

        let again = try await harness.engine.run(.changes(since: nil))

        #expect(again.actions.count == 2)
        #expect(await harness.activityLog.entries == logged)
        #expect(logged.map(\.workoutID) == [synced.id])
    }

    @Test("A skip for a reason the user can act on is logged, but can't be undone")
    func skipIsLoggedWithoutUndo() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout], accessMode: .addOnly)
        let first = try await harness.engine.run(.changes(since: nil))
        await harness.workouts.delete(workout.id)
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        let entry = try #require(await harness.activityLog.entries.first)
        #expect(second.actions == [.skip(workoutID: workout.id, .requiresFullAccess)])
        #expect(entry.action == second.actions.first)
        #expect(entry.title == "🏃 Running")
        #expect(entry.canUndo == false)
        await #expect(throws: UndoError.notUndoable) {
            try await harness.engine.undo(entryID: entry.id)
        }
    }

    @Test("Undo needs full calendar access: in add-only mode it changes nothing and stays available")
    func undoNeedsFullAccess() async throws {
        let harness = SyncHarness(workouts: [SyncHarness.run()], accessMode: .addOnly)
        _ = try await harness.engine.run(.changes(since: nil))
        let entry = try #require(await harness.activityLog.entries.first)

        await #expect(throws: CalendarStoreError.requiresFullAccess) {
            try await harness.engine.undo(entryID: entry.id)
        }

        #expect(await harness.calendar.allEvents.count == 1)
        #expect(await harness.ledger.allEntries.map(\.state) == [.owned])
        #expect(await harness.activityLog.entries == [entry])
    }

    @Test("Undoing a create whose event was already removed still keeps the workout out")
    func undoCreateAfterHealthDelete() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        let first = try await harness.engine.run(.changes(since: nil))
        let create = try #require(await harness.activityLog.entries.first)
        await harness.workouts.delete(workout.id)
        _ = try await harness.engine.run(.changes(since: first.nextAnchor))

        try await harness.engine.undo(entryID: create.id)

        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await harness.ledger.allEntries.map(\.state) == [.tombstoned])
        #expect(await harness.ledger.allEntries.first?.workoutID == workout.id)
    }
}
