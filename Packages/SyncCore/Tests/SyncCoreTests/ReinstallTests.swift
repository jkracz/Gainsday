import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Reinstall safety")
struct ReinstallTests {
    @Test("After a reinstall, an event with the workout's footer is re-linked in the ledger instead of duplicated")
    func footerEventIsRelinked() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        let existing = try await SyncHarness.eventLeftByEarlierInstall(for: workout)
        await harness.calendar.put(existing)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents == [existing])
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.workoutID == workout.id)
        #expect(entry.state == .owned)
        #expect(entry.eventExternalIdentifier == existing.id)
        #expect(entry.calendarID == SyncHarness.destination.id)
        #expect(entry.written == existing.content)
        #expect(result.actions == [.relink(workoutID: workout.id, eventID: existing.id)])
    }

    @Test("An event with another workout's footer is left alone and the workout gets its own event")
    func otherWorkoutsFooterIsIgnored() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        var other = try await SyncHarness.eventLeftByEarlierInstall(for: SyncHarness.run())
        other.content.title = "Lunch run with Sam"
        other.content.start = workout.start
        other.content.end = workout.end
        await harness.calendar.put(other)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents.count == 2)
        #expect(result.actions.allSatisfy { if case .create = $0 { true } else { false } })
    }

    @Test("With the footer off, an earlier event with the same title and times (±1 min) is re-linked instead of duplicated")
    func footerOffEventIsRelinkedByTitleAndTimes() async throws {
        let workout = SyncHarness.run()
        var settings = SyncHarness.defaultSettings
        settings.footerEnabled = false
        let harness = SyncHarness(workouts: [workout], settings: settings)
        var existing = try await SyncHarness.eventLeftByEarlierInstall(for: workout, footer: false)
        existing.content.start = workout.start.addingTimeInterval(45)
        await harness.calendar.put(existing)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents == [existing])
        #expect(await harness.ledger.allEntries.map(\.eventExternalIdentifier) == [existing.id])
        #expect(result.actions == [.relink(workoutID: workout.id, eventID: existing.id)])
    }

    @Test("An event at the same times with a different title and no footer isn't taken for the app's own")
    func userEventAtSameTimeIsNotRelinked() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        var planned = try await SyncHarness.eventLeftByEarlierInstall(for: workout, id: "planned", footer: false)
        planned.content.title = "Run club"
        await harness.calendar.put(planned)

        _ = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents.count == 2)
        #expect(await harness.ledger.allEntries.map(\.eventExternalIdentifier) != ["planned"])
    }

    @Test("An event the ledger already links to another workout is never re-linked to this one")
    func eventClaimedByAnotherWorkoutIsNotRelinked() async throws {
        let first = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let second = SyncHarness.run(minutes: 30, minutesAgo: 10)
        var settings = SyncHarness.defaultSettings
        settings.footerEnabled = false
        let harness = SyncHarness(workouts: [second], settings: settings)
        let firstsEvent = try await SyncHarness.eventLeftByEarlierInstall(for: first, footer: false)
        await harness.calendar.put(firstsEvent)
        try await harness.ledger.save(SyncHarness.ownedEntry(for: first, eventID: firstsEvent.id))

        _ = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents.count == 2)
        let secondsEntry = try #require(await harness.ledger.entries(forWorkout: second.id).first)
        #expect(secondsEntry.eventExternalIdentifier != firstsEvent.id)
    }

    @Test("In add-only mode, where the calendar can't be read, a workout the ledger doesn't know still gets an event")
    func addOnlyModeCreatesWithoutScanning() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout], accessMode: .addOnly)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents.count == 1)
        #expect(result.actions.count == 1)
        #expect(result.actions.allSatisfy { if case .create = $0 { true } else { false } })
    }
}

extension SyncHarness {
    /// The event an earlier install wrote for the workout, made by running a pass on
    /// a separate harness, as it would sit in the destination calendar today.
    static func eventLeftByEarlierInstall(for workout: Workout, id: String = "earlier-install", footer: Bool = true) async throws -> CalendarEvent {
        var settings = defaultSettings
        settings.footerEnabled = footer
        let earlier = SyncHarness(workouts: [workout], settings: settings)
        _ = try await earlier.engine.run(.changes(since: nil))
        var event = try #require(await earlier.calendar.allEvents.first)
        event.id = id
        return event
    }

    /// An owned ledger entry linking the workout to an event, as an earlier pass would write it.
    static func ownedEntry(for workout: Workout, eventID: String, updatedAt: Date = now) -> LedgerEntry {
        LedgerEntry(
            workoutID: workout.id,
            workoutStart: workout.start,
            workoutEnd: workout.end,
            state: .owned,
            eventExternalIdentifier: eventID,
            calendarID: destination.id,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }
}
