import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Adopted event lifecycle")
struct AdoptedLifecycleTests {
    @Test("Deleting the workout in Health removes only the workout section, and the event keeps its new time")
    func healthDeleteRemovesSection() async throws {
        let (harness, workout, planned, anchor) = try await SyncHarness.adopting()

        await harness.workouts.delete(workout.id)
        let result = try await harness.engine.run(.changes(since: anchor))

        let event = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(event.id == planned.id)
        #expect(event.content == EventContent(title: "Run", start: workout.start, end: workout.end, notes: "Bring gels"))
        #expect(result.actions == [.removeWorkoutSection(workoutID: workout.id, eventID: planned.id, event.content)])
        #expect(await harness.ledger.allEntries.isEmpty)
    }

    @Test("Renaming the event and adding to its notes doesn't make the app let go of it")
    func titleAndNotesChangesKeepEventAdopted() async throws {
        let (harness, workout, planned, anchor) = try await SyncHarness.adopting()
        var edited = try #require(await harness.calendar.allEvents.first)
        edited.content.title = "Long run with Sam"
        edited.content.notes = "Felt great\n" + (edited.content.notes ?? "") + "\nShoes: Pegasus"
        await harness.calendar.put(edited)

        await harness.workouts.delete(workout.id)
        let result = try await harness.engine.run(.changes(since: anchor))

        let event = try #require(await harness.calendar.allEvents.first)
        #expect(event.content == EventContent(
            title: "Long run with Sam",
            start: workout.start,
            end: workout.end,
            notes: "Felt great\nBring gels\nShoes: Pegasus"
        ))
        #expect(result.actions == [.removeWorkoutSection(workoutID: workout.id, eventID: planned.id, event.content)])
    }

    @Test("Moving the event or editing its workout section makes the app let go of it", arguments: [
        "time", "section",
    ])
    func timeOrSectionEditReleasesEvent(_ change: String) async throws {
        let (harness, workout, planned, anchor) = try await SyncHarness.adopting()
        var edited = try #require(await harness.calendar.allEvents.first)
        if change == "time" {
            edited.content.start.addTimeInterval(15 * 60)
        } else {
            edited.content.notes = edited.content.notes?.replacingOccurrences(of: "Duration: 55 min", with: "Duration: 50 min")
        }
        await harness.calendar.put(edited)

        await harness.workouts.delete(workout.id)
        let result = try await harness.engine.run(.changes(since: anchor))

        #expect(await harness.calendar.allEvents == [edited])
        #expect(result.actions == [.release(workoutID: workout.id, eventID: planned.id)])
        #expect(await harness.ledger.allEntries.map(\.state) == [.released])
    }

    @Test("A workout replaced in Health moves the event to the new times and rewrites its one section")
    func replacementRewritesSection() async throws {
        let (harness, workout, planned, anchor) = try await SyncHarness.adopting()
        var renamed = try #require(await harness.calendar.allEvents.first)
        renamed.content.title = "Tempo"
        await harness.calendar.put(renamed)

        let replacement = SyncHarness.run(from: (10, 15), to: (11, 15))
        await harness.workouts.delete(workout.id)
        await harness.workouts.add(replacement)
        let result = try await harness.engine.run(.changes(since: anchor))

        let event = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(event.content.title == "Tempo")
        #expect(event.content.start == replacement.start)
        #expect(event.content.end == replacement.end)
        let notes = try #require(event.content.notes)
        #expect(notes.hasPrefix("Bring gels\n\n"))
        #expect(notes.contains("Duration: 1 hr"))
        #expect(notes.contains("Planned: 10:00\u{2009}–\u{2009}11:00\u{202F}AM"))
        #expect(WorkoutSection.isPresent(in: notes, workoutID: replacement.id))
        #expect(!WorkoutSection.isPresent(in: notes, workoutID: workout.id))
        #expect(notes.components(separatedBy: WorkoutSection.startMarker).count == 2)
        #expect(result.actions == [.update(workoutID: replacement.id, eventID: planned.id, event.content)])
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.state == .adopted)
        #expect(entry.workoutID == replacement.id)
        #expect(entry.writtenFingerprint == event.content.fingerprint)
        #expect(entry.preUpdate == planned.content)
    }
}

@Suite("Undoing an update to a planned event")
struct AdoptedUndoTests {
    @Test("The update is logged with an Undo that puts the plan back as it was")
    func adoptionIsUndoable() async throws {
        let (harness, _, planned, _) = try await SyncHarness.adopting()

        let entry = try #require(await harness.activityLog.entries.first)
        #expect(entry.undo == .restorePlannedEvent(planned.content))
        #expect(entry.canUndo)
    }

    @Test("Undo restores the plan exactly, and the workout gets its own event that later passes keep")
    func undoWithSeparateEvent() async throws {
        let (harness, workout, planned, _) = try await SyncHarness.adopting()
        var renamed = try #require(await harness.calendar.allEvents.first)
        renamed.content.title = "Long run"
        await harness.calendar.put(renamed)
        let entry = try #require(await harness.activityLog.entries.first)

        let undone = try await harness.engine.undo(entryID: entry.id, choice: .separateEvent)

        #expect(undone.undoneAt == SyncHarness.now)
        let events = await harness.calendar.allEvents
        #expect(events.count == 2)
        #expect(events.first { $0.id == planned.id }?.content == planned.content)
        let separate = try #require(events.first { $0.id != planned.id })
        #expect(separate.calendarID == SyncHarness.destination.id)
        #expect(separate.content.start == workout.start)
        #expect(separate.content.end == workout.end)
        #expect(await harness.ledger.allEntries.map(\.state) == [.owned])
        #expect(await harness.ledger.allEntries.first?.eventExternalIdentifier == separate.id)
        let log = await harness.activityLog.entries
        #expect(log.map(\.id) == [log[0].id, entry.id])
        #expect(log.first?.undo == .removeCreatedEvent)
        #expect(log.last == undone)

        // Even with the anchor lost, the plan isn't matched again.
        let next = try await harness.engine.run(.changes(since: nil))
        #expect(next.actions == [.skip(workoutID: workout.id, .alreadySynced)])
        #expect(await harness.calendar.allEvents.count == 2)
        #expect(await harness.calendar.allEvents.first { $0.id == planned.id }?.content == planned.content)
    }

    @Test("Undo restores the plan exactly and drops the workout, so later passes leave it out")
    func undoDroppingWorkout() async throws {
        let (harness, workout, planned, _) = try await SyncHarness.adopting()
        let entry = try #require(await harness.activityLog.entries.first)

        try await harness.engine.undo(entryID: entry.id, choice: .dropWorkout)

        #expect(await harness.calendar.allEvents.map(\.content) == [planned.content])
        #expect(await harness.ledger.allEntries.map(\.state) == [.tombstoned])
        #expect(await harness.ledger.allEntries.first?.covers(workout.id) == true)

        let next = try await harness.engine.run(.changes(since: nil))
        #expect(next.actions == [.skip(workoutID: workout.id, .tombstoned)])
        #expect(await harness.calendar.allEvents.map(\.content) == [planned.content])
    }

    @Test("Undo still restores the plan after the workout was deleted in Health")
    func undoAfterWorkoutDeleted() async throws {
        let (harness, workout, planned, anchor) = try await SyncHarness.adopting()
        let entry = try #require(await harness.activityLog.entries.first)
        await harness.workouts.delete(workout.id)
        _ = try await harness.engine.run(.changes(since: anchor))
        let removal = try #require(await harness.activityLog.entries.first)
        #expect(removal.title == "Run")
        #expect(removal.undo == nil)

        try await harness.engine.undo(entryID: entry.id, choice: .separateEvent)

        #expect(await harness.calendar.allEvents.map(\.content) == [planned.content])
        #expect(await harness.ledger.allEntries.isEmpty)
    }

    @Test("Undo after the workout was replaced in Health restores the plan and gives the replacement its own event")
    func undoAfterReplacement() async throws {
        let (harness, workout, planned, anchor) = try await SyncHarness.adopting()
        let entry = try #require(await harness.activityLog.entries.first)
        let replacement = SyncHarness.run(from: (10, 15), to: (11, 15))
        await harness.workouts.delete(workout.id)
        await harness.workouts.add(replacement)
        _ = try await harness.engine.run(.changes(since: anchor))

        try await harness.engine.undo(entryID: entry.id, choice: .separateEvent)

        let events = await harness.calendar.allEvents
        #expect(events.count == 2)
        #expect(events.first { $0.id == planned.id }?.content == planned.content)
        #expect(events.first { $0.id != planned.id }?.content.start == replacement.start)
        let ledger = await harness.ledger.allEntries
        #expect(ledger.map(\.state) == [.owned])
        #expect(ledger.first?.workoutID == replacement.id)
    }

    @Test("Undoing an update without saying what happens to the workout is refused")
    func undoNeedsChoice() async throws {
        let (harness, _, _, _) = try await SyncHarness.adopting()
        let entry = try #require(await harness.activityLog.entries.first)

        await #expect(throws: UndoError.choiceRequired) {
            try await harness.engine.undo(entryID: entry.id)
        }
        #expect(await harness.activityLog.entries.first?.canUndo == true)
    }
}

extension SyncHarness {
    /// A harness whose run has adopted the user's planned "Run", and the anchor after that pass.
    static func adopting() async throws -> (SyncHarness, Workout, CalendarEvent, WorkoutAnchor?) {
        let workout = run(from: (10, 10), to: (11, 5))
        let harness = try await matching(workouts: [workout])
        let planned = planned("Run", from: (10, 0), to: (11, 0), notes: "Bring gels")
        await harness.calendar.put(planned)
        let result = try await harness.engine.run(.changes(since: nil))
        guard case .adopt = result.actions.first else {
            Issue.record("Expected the plan to be adopted, got \(result.actions)")
            return (harness, workout, planned, result.nextAnchor)
        }
        return (harness, workout, planned, result.nextAnchor)
    }
}
