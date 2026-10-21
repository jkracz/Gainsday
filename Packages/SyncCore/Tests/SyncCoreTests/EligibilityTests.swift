import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Eligibility")
struct EligibilityTests {
    @Test("A workout of a type the user turned off is skipped as type disabled")
    func disabledTypeIsSkipped() async throws {
        let walk = SyncHarness.walk()
        let harness = SyncHarness(workouts: [walk])

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions == [.skip(workoutID: walk.id, .typeDisabled)])
        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await harness.ledger.allEntries.isEmpty)
    }

    @Test("A workout shorter than the minimum duration is skipped as too short; one exactly at it is synced")
    func shortWorkoutIsSkipped() async throws {
        let shortRun = SyncHarness.run(minutes: 9, minutesAgo: 60)
        let tenMinuteRun = SyncHarness.run(minutes: 10, minutesAgo: 10)
        let harness = SyncHarness(workouts: [shortRun, tenMinuteRun])

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.first == .skip(workoutID: shortRun.id, .tooShort))
        #expect(await harness.calendar.allEvents.map(\.content.start) == [tenMinuteRun.start])
        #expect(await harness.ledger.allEntries.map(\.workoutID) == [tenMinuteRun.id])
    }

    @Test("The minimum duration is the user's choice")
    func minimumDurationIsConfigurable() async throws {
        let run = SyncHarness.run(minutes: 20)
        var settings = SyncHarness.defaultSettings
        settings.minimumDuration = 30 * 60
        let harness = SyncHarness(workouts: [run], settings: settings)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions == [.skip(workoutID: run.id, .tooShort)])
    }

    @Test("After a reinstall, with no anchor and an empty local ledger, history before the restored sync start date isn't imported")
    func reinstallDoesNotImportHistory() async throws {
        let lastYear = SyncHarness.run(minutes: 45, minutesAgo: 365 * 24 * 60)
        let lastMonth = SyncHarness.run(minutes: 45, minutesAgo: 30 * 24 * 60)
        let yesterday = SyncHarness.run(minutes: 45, minutesAgo: 24 * 60)
        let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(SyncHarness.defaultSettings))
        let harness = SyncHarness(workouts: [lastYear, lastMonth, yesterday], settings: restored)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.prefix(2) == [
            .skip(workoutID: lastYear.id, .beforeSyncStartDate),
            .skip(workoutID: lastMonth.id, .beforeSyncStartDate),
        ])
        #expect(await harness.ledger.allEntries.map(\.workoutID) == [yesterday.id])
        #expect(await harness.calendar.allEvents.count == 1)
    }

    @Test("With the default filters, common workouts sync but walks don't")
    func defaultFilters() async throws {
        let run = SyncHarness.run()
        let walk = SyncHarness.walk(minutesAgo: 60)
        let settings = Settings(
            destinationCalendar: SyncHarness.defaultSettings.destinationCalendar,
            syncStartDate: SyncHarness.defaultSettings.syncStartDate
        )
        let harness = SyncHarness(workouts: [walk, run], settings: settings)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.first == .skip(workoutID: walk.id, .typeDisabled))
        #expect(await harness.ledger.allEntries.map(\.workoutID) == [run.id])
    }
}

extension SyncHarness {
    /// A walk that ended `minutesAgo` before now. Walking is off in the default settings.
    static func walk(minutes: Double = 30, minutesAgo: Double = 10) -> Workout {
        let end = now.addingTimeInterval(-minutesAgo * 60)
        return Workout(activityType: .walking, start: end.addingTimeInterval(-minutes * 60), end: end, source: watch)
    }
}
