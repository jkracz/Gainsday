import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Settling a workout held for review")
struct HeldReviewTests {
    @Test("Matching a held workout by hand adopts the plan, and Undo holds it for review again")
    func matchHeldWorkout() async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let (harness, held, gym) = try await SyncHarness.withHeldWorkout(workout)

        let candidates = try await harness.engine.matchCandidates(forEntryID: held.id)
        let matched = try await harness.engine.match(entryID: held.id, toEventID: gym.id)

        #expect(candidates.map(\.id) == [gym.id])
        let event = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(event.id == gym.id)
        #expect(event.content.title == "Gym w/ Alex")
        #expect(event.content.start == workout.start)
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.state == .adopted)
        #expect(entry.preUpdate == gym.content)
        #expect(matched.action == .adopt(workoutID: workout.id, eventID: gym.id, event.content, decidedBy: .user))
        #expect(matched.canUndo)
        var log = await harness.activityLog.entries
        #expect(log.map(\.id) == [matched.id, held.id])
        #expect(log[1].isAwaitingReview == false)
        #expect(log[1].canMatchToEvent == false)
        #expect(log[1].canAddAsSeparateEvent == false)

        try await harness.engine.undo(entryID: matched.id)

        #expect(await harness.calendar.allEvents.map(\.content) == [gym.content])
        #expect(await harness.ledger.allEntries.isEmpty)
        log = await harness.activityLog.entries
        #expect(log[0].canUndo == false)
        #expect(log[1].isAwaitingReview)
        #expect(log[1].canMatchToEvent)
        #expect(log[1].canAddAsSeparateEvent)
    }

    @Test("A held workout the filters now leave out isn't added as a separate event, says why, and stays held")
    func addHeldWorkoutTheFiltersLeaveOut() async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let (harness, held, gym) = try await SyncHarness.withHeldWorkout(workout)
        var settings = await harness.settings.load()
        settings.enabledTypes.remove(.traditionalStrengthTraining)
        await harness.settings.save(settings)

        await #expect(throws: ManualMatchError.notAdded(.typeDisabled)) {
            try await harness.engine.addSeparateEvent(entryID: held.id)
        }

        #expect(await harness.calendar.allEvents == [gym])
        #expect(await harness.ledger.allEntries.isEmpty)
        let log = await harness.activityLog.entries
        #expect(log.map(\.id) == [held.id])
        #expect(log[0].isAwaitingReview)
        #expect(log[0].canAddAsSeparateEvent)
    }

    @Test("Adding a held workout as a separate event creates its own event and leaves the plan alone, and Undo holds it for review again")
    func addHeldWorkoutSeparately() async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let (harness, held, gym) = try await SyncHarness.withHeldWorkout(workout)

        let added = try await harness.engine.addSeparateEvent(entryID: held.id)

        let events = await harness.calendar.allEvents
        #expect(events.count == 2)
        #expect(events.first { $0.id == gym.id } == gym)
        let separate = try #require(events.first { $0.id != gym.id })
        #expect(separate.calendarID == SyncHarness.destination.id)
        #expect(separate.content.start == workout.start)
        #expect(separate.content.end == workout.end)
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.state == .owned)
        #expect(entry.eventExternalIdentifier == separate.id)
        guard case .create(let workoutID, let draft) = added.action else {
            Issue.record("Expected a create, got \(added.action)")
            return
        }
        #expect(workoutID == workout.id)
        #expect(draft.content == separate.content)
        #expect(added.title == separate.content.title)
        #expect(added.eventID == separate.id)
        #expect(added.canUndo)
        // Undo puts the workout back to review, so it isn't offered for matching meanwhile.
        #expect(added.canMatchToEvent == false)
        var log = await harness.activityLog.entries
        #expect(log.map(\.id) == [added.id, held.id])
        #expect(log[1].isAwaitingReview == false)

        try await harness.engine.undo(entryID: added.id)

        #expect(await harness.calendar.allEvents == [gym])
        #expect(await harness.ledger.allEntries.isEmpty)
        log = await harness.activityLog.entries
        #expect(log[1].isAwaitingReview)
        // Later passes still leave the plan alone.
        _ = try await harness.engine.run(.changes(since: nil))
        #expect(await harness.calendar.allEvents.count == 1)
    }

    @Test("A held workout can be settled only once, and only with full calendar access")
    func settleOnce() async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let (harness, held, gym) = try await SyncHarness.withHeldWorkout(workout)

        await harness.calendar.setAccessMode(.addOnly)
        await #expect(throws: CalendarStoreError.requiresFullAccess) {
            try await harness.engine.addSeparateEvent(entryID: held.id)
        }
        await harness.calendar.setAccessMode(.full)
        try await harness.engine.addSeparateEvent(entryID: held.id)

        await #expect(throws: ManualMatchError.notMatchable) {
            try await harness.engine.addSeparateEvent(entryID: held.id)
        }
        await #expect(throws: ManualMatchError.notMatchable) {
            try await harness.engine.match(entryID: held.id, toEventID: gym.id)
        }
        #expect(await harness.calendar.allEvents.count == 2)
        #expect(await harness.ledger.allEntries.count == 1)
    }
}

extension SyncHarness {
    /// A harness whose first pass held a strength workout for review, because the rules
    /// found its plan "Gym w/ Alex" unclear. Returns the held log entry and the plan.
    static func withHeldWorkout(_ workout: Workout) async throws -> (SyncHarness, held: ActivityLogEntry, plan: CalendarEvent) {
        let harness = try await matching(workouts: [workout]) { $0.holdUnclearMatchesForReview = true }
        let gym = planned("Gym w/ Alex", from: (12, 0), to: (13, 0))
        await harness.calendar.put(gym)
        _ = try await harness.engine.run(.changes(since: nil))
        let held = try #require(await harness.activityLog.entries.first)
        #expect(held.action == .holdForReview(workoutID: workout.id))
        #expect(held.isAwaitingReview)
        return (harness, held, gym)
    }
}
