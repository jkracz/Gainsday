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

    @Test("With the footer off, a workout the restored ledger knows is skipped, not duplicated")
    func footerOffWithLedgerCreatesNoDuplicate() async throws {
        let workout = SyncHarness.run()
        var settings = SyncHarness.defaultSettings
        settings.footerEnabled = false
        let harness = SyncHarness(workouts: [workout], settings: settings)
        var existing = try await SyncHarness.eventLeftByEarlierInstall(for: workout, footer: false)
        existing.content.title = "Easy run"
        await harness.calendar.put(existing)
        try await harness.ledger.save(SyncHarness.ownedEntry(for: workout, eventID: existing.id))

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions == [.skip(workoutID: workout.id, .alreadySynced)])
        #expect(await harness.calendar.allEvents == [existing])
        #expect(await harness.ledger.allEntries.count == 1)
    }

    @Test("Duplicate ledger entries from an iCloud merge collapse to a live entry over a newer tombstone, whichever arrived first")
    func duplicatesPreferLiveEntry() async throws {
        let workout = SyncHarness.run()
        let owned = SyncHarness.ownedEntry(for: workout, eventID: "event", updatedAt: SyncHarness.now.addingTimeInterval(-7200))
        var tombstone = SyncHarness.ownedEntry(for: workout, eventID: "event", updatedAt: SyncHarness.now.addingTimeInterval(-3600))
        tombstone.state = .tombstoned

        for arrivalOrder in [[owned, tombstone], [tombstone, owned]] {
            let harness = SyncHarness(workouts: [workout])
            await harness.calendar.put(try await SyncHarness.eventLeftByEarlierInstall(for: workout, id: "event"))
            for (index, entry) in arrivalOrder.enumerated() {
                var arrived = entry
                arrived.createdAt = SyncHarness.now.addingTimeInterval(Double(index))
                try await harness.ledger.save(arrived)
            }

            let result = try await harness.engine.run(.changes(since: nil))

            #expect(result.actions == [.skip(workoutID: workout.id, .alreadySynced)])
            #expect(await harness.ledger.allEntries.map(\.id) == [owned.id])
            #expect(await harness.calendar.allEvents.count == 1)
        }
    }

    @Test("Of duplicate live entries, the most recently updated one survives, and ties break the same way every time")
    func duplicatesPreferMostRecentlyUpdated() async throws {
        let workout = SyncHarness.run()
        let older = SyncHarness.ownedEntry(for: workout, eventID: "event", updatedAt: SyncHarness.now.addingTimeInterval(-7200))
        let newer = SyncHarness.ownedEntry(for: workout, eventID: "event", updatedAt: SyncHarness.now.addingTimeInterval(-3600))
        let newerTwin = SyncHarness.ownedEntry(for: workout, eventID: "event", updatedAt: newer.updatedAt)

        var survivors: [UUID] = []
        for arrivalOrder in [[older, newer, newerTwin], [newerTwin, older, newer], [newer, newerTwin, older]] {
            let harness = SyncHarness(workouts: [workout])
            await harness.calendar.put(try await SyncHarness.eventLeftByEarlierInstall(for: workout, id: "event"))
            for (index, entry) in arrivalOrder.enumerated() {
                var arrived = entry
                arrived.createdAt = SyncHarness.now.addingTimeInterval(Double(index))
                try await harness.ledger.save(arrived)
            }

            _ = try await harness.engine.run(.changes(since: nil))

            let remaining = await harness.ledger.allEntries
            #expect(remaining.count == 1)
            survivors += remaining.map(\.id)
        }
        #expect(Set(survivors).count == 1)
        #expect(survivors.first != older.id)
    }

    @Test("A collapsed duplicate's cluster members stay covered by the surviving entry")
    func duplicatesKeepEveryMember() async throws {
        let workout = SyncHarness.run()
        let strava = UUID()
        let survivor = SyncHarness.ownedEntry(for: workout, eventID: "event", updatedAt: SyncHarness.now)
        var loser = SyncHarness.ownedEntry(for: workout, eventID: "event", updatedAt: SyncHarness.now.addingTimeInterval(-3600))
        loser.memberIDs.insert(strava)
        let harness = SyncHarness(workouts: [workout])
        await harness.calendar.put(try await SyncHarness.eventLeftByEarlierInstall(for: workout, id: "event"))
        try await harness.ledger.save(survivor)
        try await harness.ledger.save(loser)

        _ = try await harness.engine.run(.changes(since: nil))

        let remaining = await harness.ledger.allEntries
        #expect(remaining.map(\.id) == [survivor.id])
        #expect(remaining.first?.memberIDs == [workout.id, strava])
    }

    @Test("When a server sync changes the event's external identifier, the ledger is corrected on a later pass")
    func changedExternalIdentifierIsCorrected() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        _ = try await harness.engine.run(.changes(since: nil))
        let original = try #require(await harness.calendar.allEvents.first)
        await harness.calendar.changeIdentifier(of: original.id, to: "after-server-sync")

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions == [.skip(workoutID: workout.id, .alreadySynced)])
        #expect(await harness.calendar.allEvents.map(\.id) == ["after-server-sync"])
        #expect(await harness.ledger.allEntries.map(\.eventExternalIdentifier) == ["after-server-sync"])
    }

    @Test("With the footer off, a changed external identifier is corrected by matching what the app wrote")
    func changedExternalIdentifierIsCorrectedWithoutFooter() async throws {
        let workout = SyncHarness.run()
        var settings = SyncHarness.defaultSettings
        settings.footerEnabled = false
        let harness = SyncHarness(workouts: [workout], settings: settings)
        _ = try await harness.engine.run(.changes(since: nil))
        let original = try #require(await harness.calendar.allEvents.first)
        await harness.calendar.changeIdentifier(of: original.id, to: "after-server-sync")

        _ = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents.count == 1)
        #expect(await harness.ledger.allEntries.map(\.eventExternalIdentifier) == ["after-server-sync"])
    }

    @Test("An unchanged external identifier leaves the ledger entry untouched")
    func unchangedExternalIdentifierLeavesLedgerAlone() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        let event = try await SyncHarness.eventLeftByEarlierInstall(for: workout)
        await harness.calendar.put(event)
        var entry = SyncHarness.ownedEntry(for: workout, eventID: event.id, updatedAt: SyncHarness.now.addingTimeInterval(-3600))
        entry.written = event.content
        try await harness.ledger.save(entry)
        let before = await harness.ledger.allEntries

        _ = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.ledger.allEntries == before)
    }

    @Test("In add-only mode a synced workout is skipped without reading the calendar")
    func addOnlyModeSkipsIdentifierCheck() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout], accessMode: .addOnly)
        _ = try await harness.engine.run(.changes(since: nil))

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions == [.skip(workoutID: workout.id, .alreadySynced)])
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
