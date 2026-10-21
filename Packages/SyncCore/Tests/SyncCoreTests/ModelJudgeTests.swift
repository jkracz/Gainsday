import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("On-device model for unclear matches")
struct ModelJudgeTests {
    @Test("A confident model answer updates the plan it chose, and the log credits the model")
    func confidentAnswerAdoptsPlan() async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let harness = try await SyncHarness.matching(workouts: [workout])
        let gym = SyncHarness.planned("Gym w/ Alex", from: (12, 0), to: (13, 0))
        await harness.calendar.put(gym)
        await harness.judge.setAvailability(.available)
        await harness.judge.setAnswers([MatchJudgement(chosenIndex: 0, confidence: 0.9)])

        let result = try await harness.engine.run(.changes(since: nil))

        let event = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(event.id == gym.id)
        #expect(event.content.title == "Gym w/ Alex")
        #expect(event.content.start == workout.start)
        #expect(result.actions == [.adopt(workoutID: workout.id, eventID: gym.id, event.content, decidedBy: .model)])
        #expect(await harness.ledger.allEntries.map(\.state) == [.adopted])
        #expect(await harness.activityLog.entries.map(\.action.matchDecider) == [.model])
        let question = try #require(await harness.judge.questions.first)
        #expect(question.workout == workout)
        #expect(question.candidates == [gym])
    }

    struct Fallback: Sendable, CustomTestStringConvertible {
        var testDescription: String
        var modelEnabled = true
        var availability: MatchJudgeAvailability = .available
        var answer = MatchJudgement(chosenIndex: 0, confidence: 0.9)
        var failure: MatchJudgeError?
        /// Whether the model gets asked at all.
        var asks = true
    }

    static let fallbacks: [Fallback] = [
        Fallback(testDescription: "the model is turned off", modelEnabled: false, asks: false),
        Fallback(testDescription: "the model is unavailable", availability: .unavailable, asks: false),
        Fallback(testDescription: "the model is rate-limited", availability: .rateLimited, asks: false),
        Fallback(testDescription: "the model hits its rate limit while answering", failure: .rateLimited),
        Fallback(testDescription: "the model isn't confident", answer: MatchJudgement(chosenIndex: 0, confidence: 0.5)),
        Fallback(testDescription: "the model confidently picks none", answer: MatchJudgement(chosenIndex: nil, confidence: 0.95)),
        Fallback(testDescription: "the model picks a plan that isn't there", answer: MatchJudgement(chosenIndex: 3, confidence: 0.9)),
    ]

    @Test("An unclear match gets a separate event when", arguments: fallbacks)
    func undecidedMatchFallsBack(_ fallback: Fallback) async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let harness = try await SyncHarness.matching(workouts: [workout]) { $0.matchModelEnabled = fallback.modelEnabled }
        let gym = SyncHarness.planned("Gym w/ Alex", from: (12, 0), to: (13, 0))
        await harness.calendar.put(gym)
        await harness.judge.setAvailability(fallback.availability)
        await harness.judge.setAnswers([fallback.answer])
        if let failure = fallback.failure {
            await harness.judge.failJudging(with: failure)
        }

        let result = try await harness.engine.run(.changes(since: nil))

        try await harness.expectSeparateEvent(for: workout, leaving: [gym], result: result)
        #expect(await harness.judge.questions.count == (fallback.asks ? 1 : 0))
        #expect(await harness.notifier.notifications.isEmpty)
    }

    @Test("With hold for review on, an undecided match writes nothing, waits in the log and notifies")
    func undecidedMatchIsHeldForReview() async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let harness = try await SyncHarness.matching(workouts: [workout]) { $0.holdUnclearMatchesForReview = true }
        let gym = SyncHarness.planned("Gym w/ Alex", from: (12, 0), to: (13, 0))
        await harness.calendar.put(gym)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions == [.holdForReview(workoutID: workout.id)])
        #expect(await harness.calendar.allEvents == [gym])
        #expect(await harness.ledger.allEntries.isEmpty)
        #expect(await harness.notifier.notifications == [.matchWaitingForReview])
        let logged = try #require(await harness.activityLog.entries.first)
        #expect(logged.action == .holdForReview(workoutID: workout.id))
        #expect(logged.workoutStart == workout.start)
    }

    @Test("Every pass that holds a workout notifies again, replacing the earlier notification")
    func eachHoldNotifies() async throws {
        let first = SyncHarness.run(from: (8, 5), to: (9, 0), type: .traditionalStrengthTraining)
        let harness = try await SyncHarness.matching(workouts: [first]) { $0.holdUnclearMatchesForReview = true }
        await harness.calendar.put(SyncHarness.planned("Gym w/ Alex", from: (8, 0), to: (9, 0)))
        let firstPass = try await harness.engine.run(.changes(since: nil))
        let second = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        await harness.calendar.put(SyncHarness.planned("Gym w/ Sam", from: (12, 0), to: (13, 0)))
        await harness.workouts.add(second)

        _ = try await harness.engine.run(.changes(since: firstPass.nextAnchor))

        #expect(await harness.notifier.notifications == [.matchWaitingForReview, .matchWaitingForReview])
    }

    @Test("Hold for review leaves clear decisions alone: a confident \"none\" still gets a separate event")
    func confidentNoneIsNotHeld() async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let harness = try await SyncHarness.matching(workouts: [workout]) { $0.holdUnclearMatchesForReview = true }
        let gym = SyncHarness.planned("Gym w/ Alex", from: (12, 0), to: (13, 0))
        await harness.calendar.put(gym)
        await harness.judge.setAvailability(.available)
        await harness.judge.setAnswers([MatchJudgement(chosenIndex: nil, confidence: 0.95)])

        let result = try await harness.engine.run(.changes(since: nil))

        try await harness.expectSeparateEvent(for: workout, leaving: [gym], result: result)
        #expect(await harness.notifier.notifications.isEmpty)
    }

    @Test("A backfill preview lists a held workout without notifying, and the commit notifies")
    func backfillPreviewDoesNotNotify() async throws {
        let workout = SyncHarness.run(from: (8, 5), to: (9, 0), type: .traditionalStrengthTraining)
        let harness = try await SyncHarness.matching(workouts: [workout]) { $0.holdUnclearMatchesForReview = true }
        await harness.calendar.put(SyncHarness.planned("Gym w/ Alex", from: (8, 0), to: (9, 0)))
        let range = SyncHarness.lastDays(1)

        let preview = try await harness.engine.run(.backfill(range, .preview))
        #expect(preview.actions == [.holdForReview(workoutID: workout.id)])
        #expect(await harness.notifier.notifications.isEmpty)

        let commit = try await harness.engine.run(.backfill(range, .commit))
        #expect(commit.actions == [.holdForReview(workoutID: workout.id)])
        #expect(await harness.notifier.notifications == [.matchWaitingForReview])
    }

    @Test("A plan the model picks is still never updated when it has guests")
    func modelPickWithGuestsGetsSeparateEvent() async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let harness = try await SyncHarness.matching(workouts: [workout])
        let gym = SyncHarness.planned("Gym w/ Alex", from: (12, 0), to: (13, 0), attendees: 1)
        await harness.calendar.put(gym)
        await harness.judge.setAvailability(.available)
        await harness.judge.setAnswers([MatchJudgement(chosenIndex: 0, confidence: 0.9)])

        let result = try await harness.engine.run(.changes(since: nil))

        try await harness.expectSeparateEvent(for: workout, leaving: [gym], result: result)
    }

    @Test("A plan the model updated can be undone like any other, with a choice for the workout")
    func modelAdoptionIsUndoable() async throws {
        let workout = SyncHarness.run(from: (12, 5), to: (13, 0), type: .traditionalStrengthTraining)
        let harness = try await SyncHarness.matching(workouts: [workout])
        let gym = SyncHarness.planned("Gym w/ Alex", from: (12, 0), to: (13, 0), notes: "Leg day")
        await harness.calendar.put(gym)
        await harness.judge.setAvailability(.available)
        await harness.judge.setAnswers([MatchJudgement(chosenIndex: 0, confidence: 0.9)])
        _ = try await harness.engine.run(.changes(since: nil))

        #expect(await harness.ledger.allEntries.first?.preUpdate == gym.content)
        let entry = try #require(await harness.activityLog.entries.first)
        #expect(entry.undo == .restorePlannedEvent(gym.content))

        try await harness.engine.undo(entryID: entry.id, choice: .dropWorkout)

        #expect(await harness.calendar.allEvents.map(\.content) == [gym.content])
    }
}
