import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Matching by hand keeps the user's edits")
struct ManualMatchEditTests {
    @Test("Matching by hand refuses when the user edited the separate event, and lets go of it")
    func editedSeparateEventIsReleased() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let (harness, created, separate) = try await SyncHarness.withSeparateEvent(for: [workout])
        var edited = separate
        edited.content.notes = (edited.content.notes ?? "") + "\nLegs felt heavy"
        await harness.calendar.put(edited)
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0), notes: "Bring gels")
        await harness.calendar.put(planned)

        await #expect(throws: ManualMatchError.eventEditedByUser) {
            try await harness.engine.match(entryID: created.id, toEventID: planned.id)
        }

        #expect(Set(await harness.calendar.allEvents) == [edited, planned])
        #expect(await harness.ledger.allEntries.map(\.state) == [.released])
        let log = await harness.activityLog.entries
        #expect(log.map(\.id) == [created.id])
        #expect(log[0].canMatchToEvent == false)
        #expect(log[0].canUndo == false)
    }
}

@Suite("Matched planned events with guests are never changed")
struct AdoptedGuestTests {
    @Test("Guests added after the match make the app let go of the event", arguments: ["replace", "delete"])
    func guestsAddedLaterReleaseEvent(_ change: String) async throws {
        let (harness, workout, planned, anchor) = try await SyncHarness.adopting()
        var invited = try #require(await harness.calendar.allEvents.first)
        invited.attendeeCount = 1
        await harness.calendar.put(invited)

        let replacement = SyncHarness.run(from: (10, 15), to: (11, 15))
        await harness.workouts.delete(workout.id)
        if change == "replace" {
            await harness.workouts.add(replacement)
        }
        let result = try await harness.engine.run(.changes(since: anchor))

        #expect(await harness.calendar.allEvents == [invited])
        let workoutID = change == "replace" ? replacement.id : workout.id
        #expect(result.actions == [.release(workoutID: workoutID, eventID: planned.id)])
        #expect(await harness.ledger.allEntries.map(\.state) == [.released])
    }

    @Test("A plan that gains guests while the model judges it gets a separate event instead")
    func guestsAddedWhileJudgingAreChecked() async throws {
        try await expectPlanLeftAlone { $0.attendeeCount = 2 }
    }

    @Test("A plan the user changes while the model judges it isn't overwritten")
    func editsWhileJudgingAreKept() async throws {
        try await expectPlanLeftAlone { $0.content.notes = "Bring gels and a jacket" }
    }

    /// The model confidently picks the plan, but the user changes it before the answer comes back.
    private func expectPlanLeftAlone(_ change: @escaping @Sendable (inout CalendarEvent) -> Void) async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let base = try await SyncHarness.matching(workouts: [workout])
        let gym = SyncHarness.planned("Gym w/ Alex", from: (12, 0), to: (13, 0))
        await base.calendar.put(gym)
        var changed = gym
        change(&changed)
        let judge = ChangingJudge(calendar: base.calendar, changed: changed)
        let engine = SyncEngine(
            workouts: base.workouts,
            calendar: base.calendar,
            ledger: base.ledger,
            settings: base.settings,
            judge: judge,
            clock: base.clock,
            notifier: base.notifier,
            activityLog: base.activityLog
        )

        let result = try await engine.run(.changes(since: nil))

        try await base.expectSeparateEvent(for: workout, leaving: [changed], result: result)
    }
}

/// A confident judge that picks the first plan, after the user changes it in their calendar.
private struct ChangingJudge: MatchJudge {
    let calendar: InMemoryCalendarStore
    let changed: CalendarEvent

    func availability() async -> MatchJudgeAvailability { .available }

    func judge(_ workout: Workout, candidates: [CalendarEvent]) async throws -> MatchJudgement {
        await calendar.put(changed)
        return MatchJudgement(chosenIndex: 0, confidence: 0.9)
    }
}
