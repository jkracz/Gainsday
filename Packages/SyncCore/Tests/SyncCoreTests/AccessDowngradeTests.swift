import Foundation
import SyncCore
import SyncCoreTesting
import Testing

/// With add-only access iOS adds events only to the default calendar, and the app can't
/// look up any other calendar, so a destination picked with full access looks deleted.
@Suite("Switching from full to add-only access")
struct AccessDowngradeTests {
    @Test("After switching to add-only access, the destination becomes the default calendar and workouts keep being added there")
    func downgradeUsesDefaultCalendar() async throws {
        let harness = SyncHarness(workouts: [SyncHarness.run()])
        await harness.calendar.addCalendar(SyncHarness.personal)
        await harness.calendar.setDefaultCalendar(id: SyncHarness.personal.id)

        await harness.calendar.setAccessMode(.addOnly)
        let settings = await harness.engine.usingDefaultCalendarWithAddOnlyAccess()
        _ = try await harness.engine.run(.changes(since: nil))

        #expect(settings.destinationCalendar == .defaultCalendar)
        #expect(await harness.settings.load().destinationCalendar == .defaultCalendar)
        #expect(await harness.calendar.allEvents.map(\.calendarID) == [SyncHarness.personal.id])
    }

    @Test("With full access the destination the user picked is kept")
    func fullAccessKeepsDestination() async throws {
        let harness = SyncHarness()

        let settings = await harness.engine.usingDefaultCalendarWithAddOnlyAccess()

        #expect(settings.destinationCalendar?.id == SyncHarness.destination.id)
        #expect(await harness.settings.load().destinationCalendar?.id == SyncHarness.destination.id)
    }
}
