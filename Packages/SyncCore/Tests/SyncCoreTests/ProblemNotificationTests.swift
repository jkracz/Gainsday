import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Problem notifications")
struct ProblemNotificationTests {
    @Test("Revoking calendar access notifies once on the next sync, not again on later ones")
    func calendarAccessRevokedNotifiesOnce() async throws {
        let harness = SyncHarness()
        _ = try await harness.engine.run(.changes(since: nil))
        await harness.calendar.setAccessMode(.none)

        _ = try? await harness.engine.run(.changes(since: nil))
        _ = try? await harness.engine.run(.changes(since: nil))

        #expect(await harness.notifier.notifications == [.calendarAccessRevoked])
    }

    @Test("Deleting the destination calendar notifies once, even when no workout needs writing")
    func destinationCalendarMissingNotifiesOnce() async throws {
        let harness = SyncHarness()
        await harness.calendar.removeCalendar(id: SyncHarness.destination.id)

        _ = try? await harness.engine.run(.changes(since: nil))
        _ = try? await harness.engine.run(.changes(since: nil))

        #expect(await harness.notifier.notifications == [.destinationCalendarMissing])
    }

    @Test("With add-only access, a deleted destination calendar notifies once when a workout can't be written")
    func addOnlyDestinationCalendarMissingNotifiesOnce() async throws {
        let harness = SyncHarness(workouts: [SyncHarness.run()], accessMode: .addOnly)
        await harness.calendar.removeCalendar(id: SyncHarness.destination.id)

        _ = try? await harness.engine.run(.changes(since: nil))
        _ = try? await harness.engine.run(.changes(since: nil))

        #expect(await harness.notifier.notifications == [.destinationCalendarMissing])
    }

    @Test("Once calendar access is back, the notification is withdrawn, and losing it again notifies again")
    func restoredCalendarAccessIsWithdrawn() async throws {
        let harness = SyncHarness()
        await harness.calendar.setAccessMode(.none)
        _ = try? await harness.engine.run(.changes(since: nil))

        await harness.calendar.setAccessMode(.full)
        _ = try await harness.engine.run(.changes(since: nil))
        #expect(await harness.notifier.withdrawals == [.calendarAccessRevoked])

        await harness.calendar.setAccessMode(.none)
        _ = try? await harness.engine.run(.changes(since: nil))
        #expect(await harness.notifier.notifications == [.calendarAccessRevoked, .calendarAccessRevoked])
    }

    @Test("Once the destination calendar is back, the notification is withdrawn")
    func restoredDestinationIsWithdrawn() async throws {
        let harness = SyncHarness()
        await harness.calendar.removeCalendar(id: SyncHarness.destination.id)
        _ = try? await harness.engine.run(.changes(since: nil))

        // The user picks a calendar that exists.
        let replacement = CalendarInfo(id: "training", title: "Training")
        await harness.calendar.addCalendar(replacement)
        var settings = await harness.settings.load()
        settings.destinationCalendar = CalendarReference(id: replacement.id, title: replacement.title)
        await harness.settings.save(settings)
        _ = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.notifier.withdrawals == [.destinationCalendarMissing])
        #expect(await harness.notifier.notifiedProblems().isEmpty)
    }

    @Test("Losing Health access notifies once, and getting it back withdraws the notification")
    func healthAccessRevoked() async throws {
        let harness = SyncHarness()
        await harness.workouts.setAccessDenied(true)

        _ = try? await harness.engine.run(.changes(since: nil))
        _ = try? await harness.engine.run(.changes(since: nil))
        #expect(await harness.notifier.notifications == [.healthAccessRevoked])

        await harness.workouts.setAccessDenied(false)
        _ = try await harness.engine.run(.changes(since: nil))
        #expect(await harness.notifier.withdrawals == [.healthAccessRevoked])
    }

    @Test("Normal syncs never notify", arguments: [AccessMode.full, .addOnly])
    func normalSyncsStaySilent(accessMode: AccessMode) async throws {
        let harness = SyncHarness(workouts: [SyncHarness.run()], accessMode: accessMode)

        let first = try await harness.engine.run(.changes(since: nil))
        await harness.workouts.add(SyncHarness.run(minutesAgo: 1))
        _ = try await harness.engine.run(.changes(since: first.nextAnchor))
        _ = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.calendar.allEvents.count == 2)
        #expect(await harness.notifier.notifications.isEmpty)
        #expect(await harness.notifier.withdrawals.isEmpty)
    }
}
