import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Add-only mode")
struct AddOnlyModeTests {
    @Test("In add-only mode a pass only adds events, and the ledger alone stops a later pass adding them again")
    func addOnlyCreatesAndDedupesThroughLedger() async throws {
        let run = SyncHarness.run(minutesAgo: 120)
        let laterRun = SyncHarness.run()
        let harness = SyncHarness(workouts: [run, laterRun], accessMode: .addOnly)

        let first = try await harness.engine.run(.changes(since: nil))
        let fromScratch = try await harness.engine.run(.changes(since: nil))

        #expect(first.actions.map(\.isCreate) == [true, true])
        #expect(await harness.calendar.allEvents.count == 2)
        #expect(await harness.ledger.allEntries.allSatisfy { $0.state == .owned && $0.needsLinking })
        #expect(fromScratch.actions == [
            .skip(workoutID: run.id, .alreadySynced),
            .skip(workoutID: laterRun.id, .alreadySynced),
        ])
    }

    @Test("After upgrading to full access, an event written in add-only mode is linked to its ledger entry, not duplicated")
    func upgradeLinksEventWithChangedIdentifier() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout], accessMode: .addOnly)
        let first = try await harness.engine.run(.changes(since: nil))
        let written = try #require(await harness.calendar.allEvents.first)
        // A server sync changed the identifier while the app couldn't read the calendar.
        await harness.calendar.changeIdentifier(of: written.id, to: "after-server-sync")

        await harness.calendar.setAccessMode(.full)
        let result = try await harness.engine.run(.changes(since: first.nextAnchor))

        #expect(await harness.calendar.allEvents.map(\.id) == ["after-server-sync"])
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.state == .owned)
        #expect(entry.eventExternalIdentifier == "after-server-sync")
        #expect(entry.written == written.content)
        #expect(!entry.needsLinking)
        #expect(result.actions == [.relink(workoutID: workout.id, eventID: "after-server-sync")])

        let next = try await harness.engine.run(.changes(since: result.nextAnchor))

        #expect(next.actions.isEmpty)
    }

    @Test("With the footer off, upgrading finds an event written in add-only mode by its title and times")
    func upgradeLinksByTitleAndTimesWithoutFooter() async throws {
        let workout = SyncHarness.run()
        var settings = SyncHarness.defaultSettings
        settings.footerEnabled = false
        let harness = SyncHarness(workouts: [workout], settings: settings, accessMode: .addOnly)
        let first = try await harness.engine.run(.changes(since: nil))
        let written = try #require(await harness.calendar.allEvents.first)
        await harness.calendar.changeIdentifier(of: written.id, to: "after-server-sync")

        await harness.calendar.setAccessMode(.full)
        let result = try await harness.engine.run(.changes(since: first.nextAnchor))

        #expect(result.actions == [.relink(workoutID: workout.id, eventID: "after-server-sync")])
        #expect(await harness.calendar.allEvents.count == 1)
    }

    @Test("An event the user edited while the app had add-only access is linked on upgrade, then released rather than deleted when Health deletes the workout")
    func editMadeInAddOnlyModeIsRespected() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout], accessMode: .addOnly)
        let first = try await harness.engine.run(.changes(since: nil))
        var edited = try #require(await harness.calendar.allEvents.first)
        edited.content.title = "Easy run with Sam"
        await harness.calendar.put(edited)

        await harness.calendar.setAccessMode(.full)
        let upgraded = try await harness.engine.run(.changes(since: first.nextAnchor))
        await harness.workouts.delete(workout.id)
        let afterDelete = try await harness.engine.run(.changes(since: upgraded.nextAnchor))

        #expect(afterDelete.actions == [.release(workoutID: workout.id, eventID: edited.id)])
        #expect(await harness.calendar.allEvents == [edited])
        #expect(await harness.ledger.allEntries.map(\.state) == [.released])
    }

    @Test("An event the user deleted while the app had add-only access isn't recreated after upgrading")
    func deleteMadeInAddOnlyModeIsRespected() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout], accessMode: .addOnly)
        _ = try await harness.engine.run(.changes(since: nil))
        let written = try #require(await harness.calendar.allEvents.first)
        await harness.calendar.remove(eventID: written.id)

        await harness.calendar.setAccessMode(.full)
        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions == [.skip(workoutID: workout.id, .alreadySynced)])
        #expect(await harness.calendar.allEvents.isEmpty)
    }

    @Test("In add-only mode, when the ledger can't be saved, no event is added, since the app couldn't remove it and a retry would duplicate it")
    func addOnlyLedgerFailureAddsNoEvent() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout], accessMode: .addOnly)
        await harness.ledger.failSaves(with: TestError.diskFull)

        await #expect(throws: TestError.diskFull) {
            try await harness.engine.run(.changes(since: nil))
        }

        #expect(await harness.calendar.allEvents.isEmpty)
    }

    @Test("In add-only mode, when the new event's identifier can't be recorded, the workout isn't added again, and upgrading finds the event by its footer")
    func addOnlyIdentifierSaveFailure() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout], accessMode: .addOnly)
        await harness.ledger.failSaves(with: TestError.diskFull, afterSucceeding: 1)
        await #expect(throws: TestError.diskFull) {
            try await harness.engine.run(.changes(since: nil))
        }
        await harness.ledger.resumeSaves()

        let retry = try await harness.engine.run(.changes(since: nil))

        #expect(retry.actions == [.skip(workoutID: workout.id, .alreadySynced)])
        let event = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)

        await harness.calendar.setAccessMode(.full)
        let upgraded = try await harness.engine.run(.changes(since: retry.nextAnchor))

        #expect(upgraded.actions == [.relink(workoutID: workout.id, eventID: event.id)])
        #expect(await harness.calendar.allEvents == [event])
        #expect(await harness.ledger.allEntries.map(\.eventExternalIdentifier) == [event.id])
    }

    @Test("Undo in add-only mode reports that it needs full access, and after upgrading it removes the linked event")
    func undoNeedsFullAccessThenRemovesLinkedEvent() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout], accessMode: .addOnly)
        let first = try await harness.engine.run(.changes(since: nil))
        let entry = try #require(await harness.activityLog.entries.first)

        await #expect(throws: CalendarStoreError.requiresFullAccess) {
            try await harness.engine.undo(entryID: entry.id)
        }
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(await harness.activityLog.entries.first?.canUndo == true)

        let written = try #require(await harness.calendar.allEvents.first)
        await harness.calendar.changeIdentifier(of: written.id, to: "after-server-sync")
        await harness.calendar.setAccessMode(.full)
        let upgraded = try await harness.engine.run(.changes(since: first.nextAnchor))
        try await harness.engine.undo(entryID: entry.id)
        let next = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await harness.ledger.allEntries.map(\.state) == [.tombstoned])
        #expect(upgraded.actions == [.relink(workoutID: workout.id, eventID: "after-server-sync")])
        #expect(next.actions == [.skip(workoutID: workout.id, .tombstoned)])
    }
}

private extension SyncAction {
    var isCreate: Bool {
        if case .create = self { true } else { false }
    }
}

private enum TestError: Error {
    case diskFull
}
