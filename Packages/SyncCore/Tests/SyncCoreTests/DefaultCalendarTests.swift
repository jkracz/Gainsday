import Foundation
import SyncCore
import SyncCoreTesting
import Testing

/// With add-only access iOS doesn't let the app choose a calendar: new events go to
/// the user's default calendar, so that's the destination add-only setup saves.
@Suite("Default calendar destination")
struct DefaultCalendarTests {
    @Test("In add-only mode, workouts are added to the user's default calendar")
    func addOnlyWritesToDefaultCalendar() async throws {
        let harness = await SyncHarness.addOnlyToDefaultCalendar(workouts: [SyncHarness.run()])

        _ = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents.map(\.calendarID) == [SyncHarness.destination.id])
    }

    @Test("After upgrading to full access, the destination becomes the default calendar by name, and the events added before are linked, not duplicated")
    func upgradeAdoptsDefaultCalendar() async throws {
        let workout = SyncHarness.run()
        let harness = await SyncHarness.addOnlyToDefaultCalendar(workouts: [workout])
        let first = try await harness.engine.run(.changes(since: nil))
        let written = try #require(await harness.calendar.allEvents.first)
        await harness.calendar.changeIdentifier(of: written.id, to: "after-server-sync")

        await harness.calendar.setAccessMode(.full)
        let upgraded = try await harness.engine.run(.changes(since: first.nextAnchor))
        let next = try await harness.engine.run(.changes(since: upgraded.nextAnchor))

        #expect(await harness.settings.load().destinationCalendar == CalendarReference(id: "workouts", title: "Workouts"))
        #expect(upgraded.actions == [.relink(workoutID: workout.id, eventID: "after-server-sync")])
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(entry.calendarID == "workouts")
        #expect(!entry.needsLinking)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(next.actions.isEmpty)
    }
}

extension SyncHarness {
    /// Set up with add-only access, so the destination is the default calendar, which
    /// is the Workouts calendar in the user's settings.
    static func addOnlyToDefaultCalendar(workouts: [Workout]) async -> SyncHarness {
        var settings = defaultSettings
        settings.destinationCalendar = .defaultCalendar
        let harness = SyncHarness(workouts: workouts, settings: settings, accessMode: .addOnly)
        await harness.calendar.setDefaultCalendar(id: destination.id)
        return harness
    }
}
