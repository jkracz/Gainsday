import Foundation

/// Tells the user about problems (local notifications in the app).
public protocol ProblemNotifier: Sendable {
    /// Problems already notified and not yet resolved. Kept across launches, so
    /// each problem notifies once.
    func notifiedProblems() async -> Set<Problem>

    /// Notifies the user and records the problem as notified, if the notification
    /// could be delivered.
    func notify(_ problem: Problem) async

    /// Removes the problem's notification and forgets it, so it notifies again if
    /// it comes back.
    func withdraw(_ problem: Problem) async
}
