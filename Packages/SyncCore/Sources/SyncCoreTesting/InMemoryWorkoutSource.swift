import Foundation
import SyncCore

/// A Health store held in memory. Anchors are positions in its change history.
public actor InMemoryWorkoutSource: WorkoutSource {
    private enum Change {
        case added(Workout)
        case deleted(UUID)
    }

    private var history: [Change] = []
    private var isAccessDenied = false

    public init(workouts: [Workout] = []) {
        history = workouts.map(Change.added)
    }

    /// The workouts currently in the store.
    public var workouts: [Workout] {
        var current: [UUID: Workout] = [:]
        var order: [UUID] = []
        for change in history {
            switch change {
            case .added(let workout):
                if current[workout.id] == nil { order.append(workout.id) }
                current[workout.id] = workout
            case .deleted(let id):
                current[id] = nil
            }
        }
        return order.compactMap { current[$0] }
    }

    public func add(_ workout: Workout) {
        history.append(.added(workout))
    }

    public func delete(_ workoutID: UUID) {
        history.append(.deleted(workoutID))
    }

    /// Makes every read fail as if the user had turned off Health access.
    public func setAccessDenied(_ denied: Bool) {
        isAccessDenied = denied
    }

    public func changes(since anchor: WorkoutAnchor?) async throws -> WorkoutChanges {
        if isAccessDenied { throw WorkoutSourceError.accessDenied }
        let start = anchor.map(Self.position) ?? 0
        var added: [Workout] = []
        var deletedIDs: [UUID] = []
        for change in history.dropFirst(start) {
            switch change {
            case .added(let workout):
                added.append(workout)
            case .deleted(let id):
                if let index = added.firstIndex(where: { $0.id == id }) {
                    added.remove(at: index)
                } else {
                    deletedIDs.append(id)
                }
            }
        }
        return WorkoutChanges(added: added, deletedIDs: deletedIDs, anchor: Self.anchor(at: history.count))
    }

    public func workouts(in interval: DateInterval) async throws -> [Workout] {
        if isAccessDenied { throw WorkoutSourceError.accessDenied }
        return workouts.filter { interval.contains($0.start) }
    }

    public func recentWorkouts(limit: Int) async throws -> [Workout] {
        if isAccessDenied { throw WorkoutSourceError.accessDenied }
        return Array(workouts.sorted { $0.start > $1.start }.prefix(limit))
    }

    private static func anchor(at position: Int) -> WorkoutAnchor {
        WorkoutAnchor(data: Data(String(position).utf8))
    }

    private static func position(of anchor: WorkoutAnchor) -> Int {
        Int(String(decoding: anchor.data, as: UTF8.self)) ?? 0
    }
}
