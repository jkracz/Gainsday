import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Event lifecycle")
struct LifecycleTests {
    @Test("Deleting a workout in Health deletes its event and its ledger entry")
    func healthDeleteRemovesEvent() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        let first = try await harness.engine.run(.changes(since: nil))
        let event = try #require(await harness.calendar.allEvents.first)

        await harness.workouts.delete(workout.id)
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        #expect(second.actions == [.delete(workoutID: workout.id, eventID: event.id)])
        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await harness.ledger.allEntries.isEmpty)
    }

    @Test("A workout replaced in Health updates its event in place instead of duplicating it")
    func healthReplaceUpdatesInPlace() async throws {
        let original = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let harness = SyncHarness(workouts: [original])
        let first = try await harness.engine.run(.changes(since: nil))
        let event = try #require(await harness.calendar.allEvents.first)

        let replacement = SyncHarness.run(minutes: 35, minutesAgo: 5)
        await harness.workouts.delete(original.id)
        await harness.workouts.add(replacement)
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        let updated = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(updated.id == event.id)
        #expect(updated.content.start == replacement.start)
        #expect(updated.content.end == replacement.end)
        #expect(updated.content.notes?.hasSuffix(replacement.shortID) == true)
        #expect(second.actions == [.update(workoutID: replacement.id, eventID: event.id, updated.content)])
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.state == .owned)
        #expect(entry.workoutID == replacement.id)
        #expect(entry.covers(original.id) == false)
        #expect(entry.workoutStart == replacement.start)
        #expect(entry.workoutEnd == replacement.end)
        #expect(entry.written == updated.content)
        #expect(entry.createdAt == SyncHarness.now)
    }

    @Test("A deleted run and an overlapping ride added in the same pass are a delete and a create, not a replacement")
    func differentTypeIsNotAReplacement() async throws {
        let run = SyncHarness.run()
        let harness = SyncHarness(workouts: [run])
        let first = try await harness.engine.run(.changes(since: nil))
        let runEvent = try #require(await harness.calendar.allEvents.first)

        let ride = SyncHarness.ride(start: run.start, end: run.end)
        await harness.workouts.delete(run.id)
        await harness.workouts.add(ride)
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        #expect(second.actions.first == .delete(workoutID: run.id, eventID: runEvent.id))
        let events = await harness.calendar.allEvents
        #expect(events.count == 1)
        #expect(events.first?.id != runEvent.id)
        #expect(events.first?.content.title.contains("Cycling") == true)
        #expect(await harness.ledger.allEntries.map(\.workoutID) == [ride.id])
    }
}

extension SyncHarness {
    static func ride(start: Date, end: Date) -> Workout {
        Workout(
            activityType: .cycling,
            start: start,
            end: end,
            source: watch,
            metrics: WorkoutMetrics(distanceMeters: 20_000, averageHeartRate: 140)
        )
    }
}
