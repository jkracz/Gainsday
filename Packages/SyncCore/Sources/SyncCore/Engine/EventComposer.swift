import Foundation

/// Builds the title and notes of an owned event.
///
/// For now this writes a fixed default title and notes. The template renderer
/// will replace it with the user's templates.
struct EventComposer {
    var locale: Locale
    var footerEnabled: Bool

    func content(for workout: Workout) -> EventContent {
        EventContent(
            title: "\(workout.activityType.emoji) \(workout.activityType.name)",
            start: workout.start,
            end: workout.end,
            notes: footerEnabled ? Footer.appending(to: notes(for: workout), workoutID: workout.id) : notes(for: workout)
        )
    }

    private func notes(for workout: Workout) -> String {
        var lines = ["Duration: \(formattedDuration(workout.duration))"]
        if let meters = workout.metrics.distanceMeters {
            lines.append("Distance: \(formattedDistance(meters))")
        }
        return lines.joined(separator: "\n")
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale)
        )
    }

    private func formattedDistance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(
            .measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...2)))
                .locale(locale)
        )
    }
}

extension WorkoutActivityType {
    var name: String {
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

    var emoji: String {
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
