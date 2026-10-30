import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Matching a logged workout to an event by hand")
struct ManualMatchTests {
    @Test("Matching by hand adopts the plan and removes the separate event")
    func manualMatchAdoptsPlan() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let (harness, created, separate) = try await SyncHarness.withSeparateEvent(for: [workout])
        // The plan reaches the phone only after the workout got its own event.
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0), notes: "Bring gels")
        await harness.calendar.put(planned)

        let matched = try await harness.engine.match(entryID: created.id, toEventID: planned.id)

        let event = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(try await harness.calendar.event(withID: separate.id) == nil)
        #expect(event.id == planned.id)
        #expect(event.content.title == "Run")
        #expect(event.content.start == workout.start)
        #expect(event.content.end == workout.end)
        #expect(event.content.notes?.hasPrefix("Bring gels\n\n") == true)
        #expect(WorkoutSection.isPresent(in: event.content.notes ?? "", workoutID: workout.id))

        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.state == .adopted)
        #expect(entry.workoutID == workout.id)
        #expect(entry.eventExternalIdentifier == planned.id)
        #expect(entry.writtenFingerprint == event.content.fingerprint)
        #expect(entry.preUpdate == planned.content)

        #expect(matched.action == .adopt(workoutID: workout.id, eventID: planned.id, event.content, decidedBy: .user))
        #expect(matched.title == "Run")
        #expect(matched.eventID == planned.id)
        #expect(matched.canUndo)
        let log = await harness.activityLog.entries
        #expect(log.map(\.id) == [matched.id, created.id])
        // The separate event is gone, so the create can no longer be undone or matched again.
        #expect(log[1].canUndo == false)
        #expect(log[1].canMatchToEvent == false)
    }

    @Test("Undoing a match by hand puts the plan back as it was and adds the separate event again")
    func undoRestoresPlanAndSeparateEvent() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let (harness, created, separate) = try await SyncHarness.withSeparateEvent(for: [workout])
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0), notes: "Bring gels")
        await harness.calendar.put(planned)
        let matched = try await harness.engine.match(entryID: created.id, toEventID: planned.id)

        let undone = try await harness.engine.undo(entryID: matched.id)

        let events = await harness.calendar.allEvents
        #expect(events.count == 2)
        #expect(events.first { $0.id == planned.id }?.content == planned.content)
        let restored = try #require(events.first { $0.id != planned.id })
        #expect(restored.calendarID == separate.calendarID)
        #expect(restored.content == separate.content)

        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.state == .owned)
        #expect(entry.workoutID == workout.id)
        #expect(entry.eventExternalIdentifier == restored.id)
        #expect(entry.writtenFingerprint == restored.content.fingerprint)
        #expect(entry.preUpdate == nil)

        #expect(undone.undoneAt == SyncHarness.now)
        let log = await harness.activityLog.entries
        #expect(log.map(\.id) == [matched.id, created.id])
        #expect(log[0].canUndo == false)
        // The separate event is back, so it can be removed or matched again.
        #expect(log[1].canUndo)
        #expect(log[1].canMatchToEvent)

        // Later passes leave both events alone.
        let next = try await harness.engine.run(.changes(since: nil))
        #expect(next.actions == [.skip(workoutID: workout.id, .alreadySynced)])
        #expect(await harness.calendar.allEvents == events)
    }

    @Test("Plans the rules found unclear are offered, but events with guests aren't")
    func eventsWithGuestsAreNotOffered() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let (harness, created, separate) = try await SyncHarness.withSeparateEvent(for: [workout])
        let gym = SyncHarness.planned("Gym w/ Alex", from: (10, 0), to: (11, 0))
        let group = SyncHarness.planned("Group run", from: (10, 5), to: (11, 0), attendees: 3)
        let evening = SyncHarness.planned("Run", from: (18, 0), to: (19, 0))
        for event in [gym, group, evening] {
            await harness.calendar.put(event)
        }

        let candidates = try await harness.engine.matchCandidates(forEntryID: created.id)

        #expect(candidates.map(\.id) == [gym.id])
        await #expect(throws: ManualMatchError.eventNotOffered) {
            try await harness.engine.match(entryID: created.id, toEventID: group.id)
        }
        #expect(await harness.calendar.allEvents.first { $0.id == group.id } == group)
        #expect(try await harness.calendar.event(withID: separate.id) == separate)
        #expect(await harness.ledger.allEntries.map(\.state) == [.owned])
    }

    @Test("Matching by hand needs full calendar access")
    func addOnlyCantMatch() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let (harness, created, _) = try await SyncHarness.withSeparateEvent(for: [workout])
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0))
        await harness.calendar.put(planned)
        await harness.calendar.setAccessMode(.addOnly)

        await #expect(throws: CalendarStoreError.requiresFullAccess) {
            try await harness.engine.matchCandidates(forEntryID: created.id)
        }
        await #expect(throws: CalendarStoreError.requiresFullAccess) {
            try await harness.engine.match(entryID: created.id, toEventID: planned.id)
        }
        #expect(await harness.calendar.allEvents.count == 2)
        #expect(await harness.ledger.allEntries.map(\.state) == [.owned])
    }

    @Test("A workout matched already, or whose create was undone, can't be matched")
    func onlyLiveCreatesCanBeMatched() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let (harness, created, _) = try await SyncHarness.withSeparateEvent(for: [workout])
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0))
        await harness.calendar.put(planned)
        let matched = try await harness.engine.match(entryID: created.id, toEventID: planned.id)

        await #expect(throws: ManualMatchError.notMatchable) {
            try await harness.engine.match(entryID: created.id, toEventID: planned.id)
        }
        await #expect(throws: ManualMatchError.notMatchable) {
            try await harness.engine.match(entryID: matched.id, toEventID: planned.id)
        }

        let other = SyncHarness.run(from: (15, 0), to: (15, 40))
        let second = try await SyncHarness.withSeparateEvent(for: [other])
        try await second.0.engine.undo(entryID: second.created.id)
        await #expect(throws: ManualMatchError.notMatchable) {
            try await second.0.engine.match(entryID: second.created.id, toEventID: "anything")
        }
    }

    @Test("A workout whose separate event the user deleted since the last pass can't be matched, and nothing changes")
    func deletedSeparateEventIsNotMatchable() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let (harness, created, separate) = try await SyncHarness.withSeparateEvent(for: [workout])
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0))
        await harness.calendar.put(planned)
        await harness.calendar.remove(eventID: separate.id)
        let ledger = await harness.ledger.allEntries

        // The ledger keeps no copy of the event, so its Undo couldn't add it back.
        await #expect(throws: ManualMatchError.notMatchable) {
            try await harness.engine.match(entryID: created.id, toEventID: planned.id)
        }
        #expect(await harness.calendar.allEvents == [planned])
        #expect(await harness.ledger.allEntries == ledger)
    }

    @Test("Copies of the workout from other apps stay recorded with the plan")
    func clusterMembersAreKept() async throws {
        let watch = SyncHarness.run(from: (10, 10), to: (11, 5))
        let strava = SyncHarness.stravaCopy(of: watch)
        let (harness, created, _) = try await SyncHarness.withSeparateEvent(for: [watch, strava])
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0))
        await harness.calendar.put(planned)

        try await harness.engine.match(entryID: created.id, toEventID: planned.id)

        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.workoutID == watch.id)
        #expect(entry.memberIDs == [watch.id, strava.id])
        #expect(await harness.calendar.allEvents.map(\.id) == [planned.id])
    }
}

extension SyncHarness {
    /// A harness whose first pass gave each workout a separate event, before any plan
    /// reached the phone. Returns the create's log entry and event for the first workout.
    static func withSeparateEvent(
        for workouts: [Workout],
        accessMode: AccessMode = .full
    ) async throws -> (SyncHarness, created: ActivityLogEntry, separate: CalendarEvent) {
        let harness = try await matching(workouts: workouts)
        _ = try await harness.engine.run(.changes(since: nil))
        await harness.calendar.setAccessMode(accessMode)
        let created = try #require(await harness.activityLog.entries.last)
        let separate = try #require(await harness.calendar.allEvents.first)
        return (harness, created, separate)
    }
}
