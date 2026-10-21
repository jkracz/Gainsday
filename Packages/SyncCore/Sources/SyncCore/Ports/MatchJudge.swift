import Foundation

/// Whether the matching model can be asked right now.
public enum MatchJudgeAvailability: Hashable, Sendable {
    case available
    case unavailable
    case rateLimited
}

/// The model's answer: the index of the chosen candidate, or nil for none.
public struct MatchJudgement: Hashable, Sendable {
    public var chosenIndex: Int?
    /// From 0 to 1.
    public var confidence: Double

    /// How confident the model has to be for its answer to count.
    public static let confidenceNeeded = 0.8

    public init(chosenIndex: Int?, confidence: Double) {
        self.chosenIndex = chosenIndex
        self.confidence = confidence
    }
}

/// Why the model gave no answer. Any error from `judge` leaves the match undecided.
public enum MatchJudgeError: Error, Hashable, Sendable {
    case unavailable
    case rateLimited
}

/// Decides unclear matches between a workout and planned events (the on-device
/// model in the app). [v1.1]
public protocol MatchJudge: Sendable {
    func availability() async -> MatchJudgeAvailability

    func judge(_ workout: Workout, candidates: [CalendarEvent]) async throws -> MatchJudgement
}
