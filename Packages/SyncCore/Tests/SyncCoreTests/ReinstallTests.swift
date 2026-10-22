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
                // Both were created before the tombstone, so the owned one knew the event.
                arrived.createdAt = SyncHarness.now.addingTimeInterval(-7200 + Double(index))
                try await harness.ledger.save(arrived)
            }

            let result = try await harness.engine.run(.changes(since: nil))

            #expect(result.actions == [.skip(workoutID: workout.id, .alreadySynced)])
            #expect(await harness.ledger.allEntries.map(\.id) == [owned.id])
            #expect(await harness.ledger.allEntries.map(\.state) == [.owned])
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

    @Test("After a reinstall, a matched plan is recovered as matched, not duplicated, and Health deleting the workout only removes its section")
    func matchedPlanIsRecoveredAsAdopted() async throws {
        let (harness, workout, planned, _) = try await SyncHarness.adopting()
        let adopted = try #require(await harness.calendar.allEvents.first)
        await harness.forgetLedger()

        let recovered = try await harness.engine.run(.changes(since: nil))

        #expect(recovered.actions == [.relink(workoutID: workout.id, eventID: planned.id)])
        #expect(await harness.calendar.allEvents == [adopted])
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.state == .adopted)
        #expect(entry.calendarID == SyncHarness.personal.id)
        #expect(entry.preUpdate == nil)
        #expect(await harness.activityLog.entries.first?.canUndo == false)

        await harness.workouts.delete(workout.id)
        _ = try await harness.engine.run(.changes(since: recovered.nextAnchor))

        #expect(await harness.calendar.allEvents.map(\.content) == [
            EventContent(title: "Run", start: workout.start, end: workout.end, notes: "Bring gels"),
        ])
    }

    @Test("After a reinstall, a renamed matched plan with the workout's title and times is never taken for the app's own event")
    func renamedMatchedPlanIsNotRecoveredAsOwned() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let harness = try await SyncHarness.matching(workouts: [workout]) { $0.renameMatchedEvents = true }
        await harness.calendar.put(SyncHarness.planned("Morning run", from: (10, 0), to: (11, 0), in: SyncHarness.destination, notes: "Bring gels"))
        _ = try await harness.engine.run(.changes(since: nil))
        await harness.forgetLedger()

        let recovered = try await harness.engine.run(.changes(since: nil))
        await harness.workouts.delete(workout.id)
        _ = try await harness.engine.run(.changes(since: recovered.nextAnchor))

        #expect(await harness.calendar.allEvents.map(\.content.notes) == ["Bring gels"])
        #expect(await harness.ledger.allEntries.isEmpty)
    }

    @Test("When a renamed matched plan's identifier changes, it's found by its workout section, and Health deleting the workout only removes the section")
    func matchedPlanWithChangedIdentifierIsFoundBySection() async throws {
        let (harness, workout, planned, anchor) = try await SyncHarness.adopting()
        var renamed = try #require(await harness.calendar.allEvents.first)
        renamed.content.title = "Tempo"
        await harness.calendar.put(renamed)
        await harness.calendar.changeIdentifier(of: planned.id, to: "after-server-sync")

        await harness.workouts.delete(workout.id)
        let result = try await harness.engine.run(.changes(since: anchor))

        let event = try #require(await harness.calendar.allEvents.first)
        #expect(event.id == "after-server-sync")
        #expect(event.content.notes == "Bring gels")
        #expect(result.actions == [.removeWorkoutSection(workoutID: workout.id, eventID: "after-server-sync", event.content)])
        #expect(await harness.ledger.allEntries.isEmpty)
    }

    @Test("An edit released before a reinstall still holds when the old entry arrives after the event was re-linked")
    func lateReleasedEntryKeepsTheUsersEdit() async throws {
        let workout = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let harness = SyncHarness(workouts: [workout])
        var edited = try await SyncHarness.eventLeftByEarlierInstall(for: workout)
        edited.content.title = "Run with Sam"
        await harness.calendar.put(edited)
        let first = try await harness.engine.run(.changes(since: nil))
        #expect(first.actions == [.relink(workoutID: workout.id, eventID: edited.id)])
        var released = SyncHarness.ownedEntry(for: workout, eventID: edited.id, updatedAt: SyncHarness.now.addingTimeInterval(-3600))
        released.state = .released
        try await harness.ledger.save(released)

        let replacement = SyncHarness.run(minutes: 35, minutesAgo: 5)
        await harness.workouts.delete(workout.id)
        await harness.workouts.add(replacement)
        _ = try await harness.engine.run(.changes(since: first.nextAnchor))

        #expect(await harness.calendar.allEvents.map(\.content.title) == ["Run with Sam"])
        #expect(await harness.ledger.allEntries.map(\.state) == [.released])
    }

    @Test("An event deleted before a reinstall is deleted again when its tombstone arrives after the event was recreated")
    func lateTombstoneDeletesRecreatedEvent() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        _ = try await harness.engine.run(.changes(since: nil))
        var tombstone = SyncHarness.ownedEntry(for: workout, eventID: "deleted-before-reinstall", updatedAt: SyncHarness.now.addingTimeInterval(-3600))
        tombstone.state = .tombstoned
        try await harness.ledger.save(tombstone)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions == [.skip(workoutID: workout.id, .tombstoned)])
        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await harness.ledger.allEntries.map(\.state) == [.tombstoned])
    }

    @Test("A recreated event the user has since edited is kept, and released, when the old tombstone arrives")
    func lateTombstoneKeepsEditedRecreatedEvent() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        _ = try await harness.engine.run(.changes(since: nil))
        var recreated = try #require(await harness.calendar.allEvents.first)
        recreated.content.title = "Run with Sam"
        await harness.calendar.put(recreated)
        var tombstone = SyncHarness.ownedEntry(for: workout, eventID: "deleted-before-reinstall", updatedAt: SyncHarness.now.addingTimeInterval(-3600))
        tombstone.state = .tombstoned
        try await harness.ledger.save(tombstone)

        _ = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents == [recreated])
        #expect(await harness.ledger.allEntries.map(\.state) == [.released])
    }

    @Test("When duplicate entries link different events, the losing entry's unedited event is deleted")
    func duplicateWithOtherEventDeletesIt() async throws {
        let workout = SyncHarness.run()
        let (harness, kept, duplicate) = try await SyncHarness.withDuplicateEvents(for: workout)

        _ = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents == [kept])
        #expect(await harness.ledger.allEntries.map(\.eventExternalIdentifier) == [kept.id])
        #expect(await harness.calendar.allEvents.contains { $0.id == duplicate.id } == false)
    }

    @Test("When duplicate entries link different events, and the user edited the losing one, it's kept and released")
    func duplicateWithEditedEventIsReleased() async throws {
        let workout = SyncHarness.run()
        let (harness, kept, duplicate) = try await SyncHarness.withDuplicateEvents(for: workout)
        var edited = duplicate
        edited.content.title = "Run with Sam"
        await harness.calendar.put(edited)

        _ = try await harness.engine.run(.changes(since: nil))
        let again = try await harness.engine.run(.changes(since: nil))

        #expect(Set(await harness.calendar.allEvents) == [kept, edited])
        let entries = await harness.ledger.allEntries
        #expect(entries.first { $0.eventExternalIdentifier == kept.id }?.state == .owned)
        #expect(entries.first { $0.eventExternalIdentifier == edited.id }?.state == .released)
        #expect(again.actions == [.skip(workoutID: workout.id, .alreadySynced)])
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

    /// Empties the ledger, as a reinstall does before iCloud brings it back.
    func forgetLedger() async {
        for entry in await ledger.allEntries {
            try? await ledger.delete(entryID: entry.id)
        }
    }

    /// Two devices each synced the workout before iCloud merged their ledgers: the newer
    /// entry links `kept`, the older one `duplicate`.
    static func withDuplicateEvents(for workout: Workout) async throws -> (SyncHarness, kept: CalendarEvent, duplicate: CalendarEvent) {
        let harness = SyncHarness(workouts: [workout])
        let kept = try await eventLeftByEarlierInstall(for: workout, id: "kept")
        let duplicate = try await eventLeftByEarlierInstall(for: workout, id: "duplicate")
        await harness.calendar.put(kept)
        await harness.calendar.put(duplicate)
        var survivor = ownedEntry(for: workout, eventID: kept.id)
        survivor.written = kept.content
        var loser = ownedEntry(for: workout, eventID: duplicate.id, updatedAt: now.addingTimeInterval(-3600))
        loser.written = duplicate.content
        try await harness.ledger.save(survivor)
        try await harness.ledger.save(loser)
        return (harness, kept, duplicate)
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
