import Foundation

/// An opaque position in the Health store's change history (an `HKQueryAnchor`
/// in the app). Losing it is safe: the sync start date and ledger dedupe stop
/// history from being imported again.
public struct WorkoutAnchor: Hashable, Codable, Sendable {
    public var data: Data

    public init(data: Data) {
        self.data = data
    }
}

/// Workouts added and deleted since an anchor.
public struct WorkoutChanges: Hashable, Sendable {
    public var added: [Workout]
    public var deletedIDs: [UUID]
    /// Where the next fetch should continue from, once this pass has finished.
    public var anchor: WorkoutAnchor

    public init(added: [Workout], deletedIDs: [UUID], anchor: WorkoutAnchor) {
        self.added = added
        self.deletedIDs = deletedIDs
        self.anchor = anchor
    }
}

/// Reads workouts from Health.
public protocol WorkoutSource: Sendable {
    /// Workouts added and deleted since `anchor`, or all workouts when `anchor` is nil.
    func changes(since anchor: WorkoutAnchor?) async throws -> WorkoutChanges

    /// Workouts that started in `interval`, for backfill.
    func workouts(in interval: DateInterval) async throws -> [Workout]

    /// The most recent workouts, newest first, for the template preview picker.
    func recentWorkouts(limit: Int) async throws -> [Workout]
}
