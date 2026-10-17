import Foundation
import SyncCore

/// A match judge with a fixed availability that returns scripted answers in order.
/// When the script runs out, it answers "none" with no confidence.
public actor StubMatchJudge: MatchJudge {
    public struct Question: Hashable, Sendable {
        public var workout: Workout
        public var candidates: [CalendarEvent]
    }

    private var currentAvailability: MatchJudgeAvailability
    private var answers: [MatchJudgement]
    /// Every question asked, in order.
    public private(set) var questions: [Question] = []

    public init(availability: MatchJudgeAvailability = .unavailable, answers: [MatchJudgement] = []) {
        self.currentAvailability = availability
        self.answers = answers
    }

    public func setAvailability(_ availability: MatchJudgeAvailability) {
        currentAvailability = availability
    }

    public func availability() async -> MatchJudgeAvailability {
        currentAvailability
    }

    public func judge(_ workout: Workout, candidates: [CalendarEvent]) async throws -> MatchJudgement {
        questions.append(Question(workout: workout, candidates: candidates))
        guard !answers.isEmpty else { return MatchJudgement(chosenIndex: nil, confidence: 0) }
        return answers.removeFirst()
    }
}
