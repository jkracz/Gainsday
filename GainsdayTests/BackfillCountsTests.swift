import Foundation
import SyncCore
import Testing
@testable import Gainsday

@Suite("Backfill counts")
struct BackfillCountsTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("A backfill that only updates planned events counts them and is worth committing")
    func adoptOnlyBackfillHasWrites() {
        let content = EventContent(title: "Gym", start: start, end: start.addingTimeInterval(3600))
        let result = SyncResult(actions: [
            .adopt(workoutID: UUID(), eventID: "gym", content, decidedBy: .rules),
            .skip(workoutID: UUID(), .alreadySynced),
        ])

        let counts = SyncCoordinator.BackfillCounts(result)

        #expect(counts == SyncCoordinator.BackfillCounts(newEventCount: 0, plannedEventCount: 1))
        #expect(counts.hasWrites)
    }

    @Test("A backfill that creates events counts them, and one that only skips writes nothing")
    func createsAndSkips() {
        let draft = EventDraft(calendarID: "workouts", content: EventContent(title: "Run", start: start, end: start.addingTimeInterval(1800)))
        let creates = SyncCoordinator.BackfillCounts(SyncResult(actions: [
            .create(workoutID: UUID(), draft),
            .create(workoutID: UUID(), draft),
        ]))
        let skips = SyncCoordinator.BackfillCounts(SyncResult(actions: [.skip(workoutID: UUID(), .tooShort)]))

        #expect(creates == SyncCoordinator.BackfillCounts(newEventCount: 2, plannedEventCount: 0))
        #expect(skips.hasWrites == false)
    }
}
