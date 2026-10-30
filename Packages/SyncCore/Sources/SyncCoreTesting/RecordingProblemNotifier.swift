import Foundation
import SyncCore

/// A problem notifier that records every notification instead of showing it.
public actor RecordingProblemNotifier: ProblemNotifier {
    /// Every notification sent, in order, including repeats.
    public private(set) var notifications: [Problem] = []
    /// Every withdrawal, in order.
    public private(set) var withdrawals: [Problem] = []
    private var notified: Set<Problem> = []

    public init() {}

    public func notifiedProblems() async -> Set<Problem> {
        notified
    }

    public func notify(_ problem: Problem) async {
        notifications.append(problem)
        notified.insert(problem)
    }

    public func withdraw(_ problem: Problem) async {
        withdrawals.append(problem)
        notified.remove(problem)
    }
}
