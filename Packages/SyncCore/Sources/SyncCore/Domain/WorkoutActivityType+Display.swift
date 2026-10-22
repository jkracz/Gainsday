import Foundation

extension WorkoutActivityType {
    /// Every type with a name and emoji, in the order the app lists them.
    public static let known: [WorkoutActivityType] = [
        .running, .walking, .hiking, .cycling, .swimming, .rowing, .elliptical,
        .traditionalStrengthTraining, .functionalStrengthTraining,
        .highIntensityIntervalTraining, .yoga, .other,
    ]

    /// The name written by `{type}`. English only in v1, like the rest of the event text.
    public var name: String {
        switch self {
        case .cycling: "Cycling"
        case .elliptical: "Elliptical"
        case .functionalStrengthTraining: "Functional Strength Training"
        case .hiking: "Hiking"
        case .rowing: "Rowing"
        case .running: "Running"
        case .swimming: "Swimming"
        case .traditionalStrengthTraining: "Strength Training"
        case .walking: "Walking"
        case .yoga: "Yoga"
        case .highIntensityIntervalTraining: "HIIT"
        default: "Workout"
        }
    }

    /// The emoji written by `{emoji}`.
    public var emoji: String {
        switch self {
        case .cycling: "🚴"
        case .hiking: "🥾"
        case .rowing: "🚣"
        case .running: "🏃"
        case .swimming: "🏊"
        case .functionalStrengthTraining, .traditionalStrengthTraining: "🏋️"
        case .walking: "🚶"
        case .yoga: "🧘"
        default: "💪"
        }
    }
}
