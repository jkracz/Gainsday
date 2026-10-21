import Foundation

/// The workouts a template can be previewed with.
public enum TemplatePreview {
    /// A workout to preview with: a real recent one, or sample data.
    public struct Choice: Identifiable, Hashable, Sendable {
        public var workout: Workout
        public var isSample: Bool

        public var id: String { (isSample ? "sample-" : "") + workout.id.uuidString }
    }

    /// The recent workouts in the order given (newest first), then a sample for each
    /// known type the user hasn't recorded recently, so every type can be previewed.
    public static func choices(recent: [Workout], now: Date) -> [Choice] {
        let recordedTypes = Set(recent.map(\.activityType))
        let samples = WorkoutActivityType.known
            .filter { !recordedTypes.contains($0) }
            .map { Choice(workout: .sample($0, endingAt: now), isSample: true) }
        return recent.map { Choice(workout: $0, isSample: false) } + samples
    }
}
