import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Undo acts only on its own entry, and only while it's safe")
struct UndoSafetyTests {
    @Test("An update's Undo can't overwrite the plan its workout was matched to later")
    func updateUndoAfterManualMatch() async throws {
        let watchRun = SyncHarness.run(from: (10, 10), to: (11, 5))
        let stravaRun = SyncHarness.stravaCopy(of: watchRun)
        let harness = try await SyncHarness.matching(workouts: [stravaRun])
        let first = try await harness.engine.run(.changes(since: nil))
        let created = try #require(await harness.activityLog.entries.first)
        // The Watch copy arrives later and rewrites the event with its own values.
        await harness.workouts.add(watchRun)
        _ = try await harness.engine.run(.changes(since: first.nextAnchor))
        let updated = try #require(await harness.activityLog.entries.first)
        guard case .update = updated.action else {
            Issue.record("Expected an update, got \(updated.action)")
            return
        }
        let planned = SyncHarness.planned("Run with Sam", from: (10, 0), to: (11, 0), notes: "Bring gels")
        await harness.calendar.put(planned)
        _ = try await harness.engine.match(entryID: created.id, toEventID: planned.id)
        let plan = try #require(try await harness.calendar.event(withID: planned.id))

        #expect(await harness.activityLog.entries.first { $0.id == updated.id }?.canUndo == false)
        await #expect(throws: (any Error).self) {
            try await harness.engine.undo(entryID: updated.id)
        }
        #expect(try await harness.calendar.event(withID: planned.id) == plan)
        #expect(await harness.ledger.allEntries.map(\.state) == [.adopted])
    }

    @Test("An update's Undo refuses, keeps the user's edits and lets go of the event")
    func updateUndoAfterUserEdit() async throws {
        let original = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let harness = SyncHarness(workouts: [original])
        let first = try await harness.engine.run(.changes(since: nil))
        let replacement = SyncHarness.run(minutes: 35, minutesAgo: 5)
        await harness.workouts.delete(original.id)
        await harness.workouts.add(replacement)
        _ = try await harness.engine.run(.changes(since: first.nextAnchor))
        let updated = try #require(await harness.activityLog.entries.first)
        var edited = try #require(await harness.calendar.allEvents.first)
        edited.content.title = "Run with Sam"
        edited.content.notes = "Felt great"
        await harness.calendar.put(edited)

        await #expect(throws: UndoError.eventEditedByUser) {
            try await harness.engine.undo(entryID: updated.id)
        }

        #expect(await harness.calendar.allEvents == [edited])
        #expect(await harness.ledger.allEntries.map(\.state) == [.released])
        #expect(await harness.activityLog.entries.first?.canUndo == false)
    }

    @Test("An old adoption's Undo can't take over a later workout matched to the same plan")
    func adoptionUndoAfterAnotherWorkoutAdoptsThePlan() async throws {
        let (harness, workout, planned, anchor) = try await SyncHarness.adopting()
        let adoption = try #require(await harness.activityLog.entries.first)
        await harness.workouts.delete(workout.id)
        let second = try await harness.engine.run(.changes(since: anchor))
        var renamed = try #require(try await harness.calendar.event(withID: planned.id))
        renamed.content.title = "Ride with coach"
        await harness.calendar.put(renamed)
        let ride = SyncHarness.run(from: (10, 5), to: (11, 0), type: .cycling)
        await harness.workouts.add(ride)
        _ = try await harness.engine.run(.changes(since: second.nextAnchor))
        let rideEntry = try #require(await harness.ledger.allEntries.first)
        #expect(rideEntry.state == .adopted)
        #expect(rideEntry.covers(ride.id))
        let plan = try #require(try await harness.calendar.event(withID: planned.id))

        await #expect(throws: (any Error).self) {
            try await harness.engine.undo(entryID: adoption.id, choice: .dropWorkout)
        }

        #expect(try await harness.calendar.event(withID: planned.id) == plan)
        #expect(await harness.ledger.allEntries == [rideEntry])
        #expect(await harness.activityLog.entries.first { $0.id == adoption.id }?.canUndo == false)
    }

    @Test("Once the app lets go of a plan the user changed, its adoption can't be undone")
    func adoptionUndoAfterRelease() async throws {
        let (harness, workout, planned, anchor) = try await SyncHarness.adopting()
        let adoption = try #require(await harness.activityLog.entries.first)
        var moved = try #require(try await harness.calendar.event(withID: planned.id))
        moved.content.start = SyncHarness.today((18, 0))
        moved.content.end = SyncHarness.today((19, 0))
        moved.content.notes = (moved.content.notes ?? "") + "\n\nKnee OK"
        await harness.calendar.put(moved)
        await harness.workouts.delete(workout.id)
        _ = try await harness.engine.run(.changes(since: anchor))
        #expect(await harness.ledger.allEntries.map(\.state) == [.released])

        #expect(await harness.activityLog.entries.first { $0.id == adoption.id }?.canUndo == false)
        await #expect(throws: (any Error).self) {
            try await harness.engine.undo(entryID: adoption.id, choice: .separateEvent)
        }
        #expect(try await harness.calendar.event(withID: planned.id) == moved)
    }

    @Test("Undoing a match refuses once the user moved the plan, and leaves it where they put it")
    func matchUndoAfterPlanMoved() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let (harness, created, _) = try await SyncHarness.withSeparateEvent(for: [workout])
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0), notes: "Bring gels")
        await harness.calendar.put(planned)
        let matched = try await harness.engine.match(entryID: created.id, toEventID: planned.id)
        var moved = try #require(try await harness.calendar.event(withID: planned.id))
        moved.content.start = SyncHarness.today((18, 0))
        moved.content.end = SyncHarness.today((19, 0))
        await harness.calendar.put(moved)

        await #expect(throws: UndoError.eventEditedByUser) {
            try await harness.engine.undo(entryID: matched.id)
        }

        #expect(await harness.calendar.allEvents == [moved])
        #expect(await harness.ledger.allEntries.map(\.state) == [.released])
        #expect(await harness.activityLog.entries.allSatisfy { !$0.canUndo })
    }

    @Test("An adoption's Undo refuses once the plan has guests, and doesn't change it")
    func adoptionUndoAfterGuestsAdded() async throws {
        let (harness, _, planned, _) = try await SyncHarness.adopting()
        let adoption = try #require(await harness.activityLog.entries.first)
        var invited = try #require(try await harness.calendar.event(withID: planned.id))
        invited.attendeeCount = 1
        await harness.calendar.put(invited)

        await #expect(throws: UndoError.eventEditedByUser) {
            try await harness.engine.undo(entryID: adoption.id, choice: .separateEvent)
        }

        #expect(await harness.calendar.allEvents == [invited])
        #expect(await harness.ledger.allEntries.map(\.state) == [.released])
    }

    @Test("A create logged before Undo was tied to its ledger entry can still be undone")
    func legacyCreateUndo() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        _ = try await harness.engine.run(.changes(since: nil))
        var log = await harness.activityLog.entries
        log[0].ledgerEntryID = nil
        try await harness.activityLog.save(log)

        try await harness.engine.undo(entryID: log[0].id)

        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await harness.ledger.allEntries.map(\.state) == [.tombstoned])
    }
}

@Suite("Undo never deletes an event the user edited")
struct UndoDeleteSafetyTests {
    @Test("Undoing \"Add as separate event\" refuses once the user edited the event, and keeps it")
    func returnToReviewAfterUserEdit() async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let (harness, held, _) = try await SyncHarness.withHeldWorkout(workout)
        let added = try await harness.engine.addSeparateEvent(entryID: held.id)
        let eventID = try #require(added.eventID)
        var edited = try #require(try await harness.calendar.event(withID: eventID))
        edited.content.title = "Leg day — PR!"
        await harness.calendar.put(edited)

        await #expect(throws: UndoError.eventEditedByUser) {
            try await harness.engine.undo(entryID: added.id)
        }

        #expect(try await harness.calendar.event(withID: edited.id) == edited)
        let entry = try #require(await harness.ledger.allEntries.first { $0.eventExternalIdentifier == edited.id })
        #expect(entry.state == .released)
        let log = await harness.activityLog.entries
        #expect(log.first { $0.id == added.id }?.canUndo == false)
        #expect(log.first { $0.id == held.id }?.isAwaitingReview == false)
    }

    @Test("Undoing a create after Health replaced the workout refuses once the user edited the event")
    func createUndoAfterReplacementAndEdit() async throws {
        let original = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let harness = SyncHarness(workouts: [original])
        let first = try await harness.engine.run(.changes(since: nil))
        let created = try #require(await harness.activityLog.entries.first)
        let replacement = SyncHarness.run(minutes: 35, minutesAgo: 5)
        await harness.workouts.delete(original.id)
        await harness.workouts.add(replacement)
        _ = try await harness.engine.run(.changes(since: first.nextAnchor))
        var edited = try #require(await harness.calendar.allEvents.first)
        edited.content.notes = "Felt great"
        await harness.calendar.put(edited)

        await #expect(throws: UndoError.eventEditedByUser) {
            try await harness.engine.undo(entryID: created.id)
        }

        #expect(await harness.calendar.allEvents == [edited])
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.state == .released)
        #expect(entry.covers(replacement.id))
    }

    @Test("Undoing a create after Health replaced the workout removes the event and keeps the replacement out")
    func createUndoAfterReplacement() async throws {
        let original = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let harness = SyncHarness(workouts: [original])
        let first = try await harness.engine.run(.changes(since: nil))
        let created = try #require(await harness.activityLog.entries.first)
        let replacement = SyncHarness.run(minutes: 35, minutesAgo: 5)
        await harness.workouts.delete(original.id)
        await harness.workouts.add(replacement)
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        try await harness.engine.undo(entryID: created.id)

        #expect(await harness.calendar.allEvents.isEmpty)
        let entries = await harness.ledger.allEntries
        #expect(entries.map(\.state) == [.tombstoned])
        #expect(entries.first?.covers(replacement.id) == true)
        let next = try await harness.engine.run(.changes(since: second.nextAnchor))
        #expect(next.actions.isEmpty)
        #expect(await harness.calendar.allEvents.isEmpty)
    }
}

@Suite("Workouts held for review stay in the activity log")
struct HeldEntryRetentionTests {
    @Test("A held workout isn't trimmed from the log however many entries come after it")
    func heldEntrySurvivesTrimming() async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let harness = try await SyncHarness.matching(workouts: [workout]) { $0.holdUnclearMatchesForReview = true }
        await harness.calendar.put(SyncHarness.planned("Gym w/ Alex", from: (12, 0), to: (13, 0)))
        var anchor = try await harness.engine.run(.changes(since: nil)).nextAnchor
        let held = try #require(await harness.activityLog.entries.first)
        #expect(held.isAwaitingReview)
        for index in 0..<55 {
            await harness.workouts.add(SyncHarness.run(minutes: 20, minutesAgo: Double(index + 3) * 60))
            anchor = try await harness.engine.run(.changes(since: anchor)).nextAnchor
        }

        let log = await harness.activityLog.entries
        #expect(log.count == ActivityLogEntry.capacity + 1)
        #expect(log.last?.id == held.id)
        #expect(log.last?.isAwaitingReview == true)
    }

    @Test("Undo of adding an old held workout separately holds it for review again, though 50 newer entries came after it")
    func undoAddingOldHeldWorkout() async throws {
        let (harness, held, _) = try await Self.oldHeldWorkout()

        let added = try await harness.engine.addSeparateEvent(entryID: held.id)
        try await harness.engine.undo(entryID: added.id)

        #expect(await harness.ledger.allEntries.allSatisfy { !$0.covers(held.workoutID) })
        #expect(await harness.activityLog.entries.first { $0.id == held.id }?.isAwaitingReview == true)
    }

    @Test("Undo of matching an old held workout holds it for review again, though 50 newer entries came after it")
    func undoMatchingOldHeldWorkout() async throws {
        let (harness, held, gym) = try await Self.oldHeldWorkout()

        let matched = try await harness.engine.match(entryID: held.id, toEventID: gym.id)
        try await harness.engine.undo(entryID: matched.id)

        #expect(await harness.calendar.allEvents.first { $0.id == gym.id }?.content == gym.content)
        #expect(await harness.ledger.allEntries.allSatisfy { !$0.covers(held.workoutID) })
        #expect(await harness.activityLog.entries.first { $0.id == held.id }?.isAwaitingReview == true)
    }

    /// A workout held for review, with more than the log's capacity of entries after it.
    static func oldHeldWorkout() async throws -> (SyncHarness, held: ActivityLogEntry, plan: CalendarEvent) {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let (harness, held, gym) = try await SyncHarness.withHeldWorkout(workout)
        var anchor: WorkoutAnchor? = try await harness.workouts.changes(since: nil).anchor
        for index in 0..<55 {
            await harness.workouts.add(SyncHarness.run(minutes: 20, minutesAgo: Double(index + 3) * 60))
            anchor = try await harness.engine.run(.changes(since: anchor)).nextAnchor
        }
        #expect(await harness.activityLog.entries.last?.id == held.id)
        return (harness, held, gym)
    }
}
