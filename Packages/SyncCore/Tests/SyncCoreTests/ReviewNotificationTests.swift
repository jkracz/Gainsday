import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Review notification")
struct ReviewNotificationTests {
    @Test("Once the last held workout is matched by hand, the review notification is withdrawn")
    func withdrawnAfterMatch() async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let (harness, held, gym) = try await SyncHarness.withHeldWorkout(workout)
        #expect(await harness.notifier.notifications == [.matchWaitingForReview])

        try await harness.engine.match(entryID: held.id, toEventID: gym.id)

        #expect(await harness.notifier.withdrawals == [.matchWaitingForReview])
        #expect(await harness.notifier.notifiedProblems().isEmpty)
    }

    @Test("Once the last held workout is added as a separate event, the review notification is withdrawn")
    func withdrawnAfterAddingSeparately() async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let (harness, held, _) = try await SyncHarness.withHeldWorkout(workout)

        try await harness.engine.addSeparateEvent(entryID: held.id)

        #expect(await harness.notifier.withdrawals == [.matchWaitingForReview])
    }

    @Test("While another workout still waits for review, settling one keeps the notification")
    func keptWhileAnotherWaits() async throws {
        let lunch = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let evening = SyncHarness.run(from: (18, 5), to: (19, 0), type: .traditionalStrengthTraining)
        let harness = try await SyncHarness.matching(workouts: [lunch, evening]) { $0.holdUnclearMatchesForReview = true }
        await harness.calendar.put(SyncHarness.planned("Gym w/ Alex", from: (12, 0), to: (13, 0)))
        await harness.calendar.put(SyncHarness.planned("Gym w/ Sam", from: (18, 0), to: (19, 0)))
        _ = try await harness.engine.run(.changes(since: nil))
        let held = await harness.activityLog.entries.filter(\.isAwaitingReview)
        #expect(held.count == 2)

        try await harness.engine.addSeparateEvent(entryID: held[0].id)
        #expect(await harness.notifier.withdrawals.isEmpty)

        try await harness.engine.addSeparateEvent(entryID: held[1].id)
        #expect(await harness.notifier.withdrawals == [.matchWaitingForReview])
    }
}
