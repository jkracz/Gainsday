import Foundation
import SyncCore
import SyncCoreTesting
import Testing

/// The status screen's count of events added today, read from the activity log.
@Suite("Events added today")
struct AddedTodayTests {
    @Test("Events a backfill added still count after a later pass that adds nothing")
    func backfillCountsAfterEmptyPass() async throws {
        let lastWeek = SyncHarness.run(minutesAgo: 3 * 24 * 60)
        let yesterday = SyncHarness.run(minutesAgo: 24 * 60)
        let harness = SyncHarness(workouts: [lastWeek, yesterday], settings: SyncHarness.setUpJustNow)

        let changes = try await harness.engine.run(.changes(since: nil))
        _ = try await harness.engine.run(.backfill(SyncHarness.lastDays(7), .commit))
        _ = try await harness.engine.run(.changes(since: changes.nextAnchor))

        let log = await harness.activityLog.entries
        #expect(log.addedEventCount(on: SyncHarness.now, in: harness.clock.calendar) == 2)
    }

    @Test("Events added on an earlier day, or undone, don't count")
    func earlierDaysAndUndoneDontCount() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout, SyncHarness.run(minutesAgo: 60)])
        _ = try await harness.engine.run(.changes(since: nil))
        let undone = try #require(await harness.activityLog.entries.first)
        _ = try await harness.engine.undo(entryID: undone.id)

        let log = await harness.activityLog.entries
        let tomorrow = SyncHarness.now.addingTimeInterval(24 * 60 * 60)
        #expect(log.addedEventCount(on: SyncHarness.now, in: harness.clock.calendar) == 1)
        #expect(log.addedEventCount(on: tomorrow, in: harness.clock.calendar) == 0)
    }
}

extension SyncHarness {
    /// Set up now, so only a backfill adds earlier workouts.
    static var setUpJustNow: Settings {
        var settings = defaultSettings
        settings.syncStartDate = now
        return settings
    }
}
