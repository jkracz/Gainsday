import Foundation

/// Ready-made templates the user can start from. Only Detailed shows heart rate
/// and calories, so sensitive metrics stay out unless the user picks it.
public enum StarterTemplate: String, CaseIterable, Sendable {
    case minimal
    case detailed
    case runner

    public var template: EventTemplate {
        switch self {
        case .minimal:
            EventTemplate(title: "{emoji} {type}", notes: "{duration}")
        case .detailed:
            EventTemplate(
                title: "{emoji} {type} · {distance} · {duration}",
                notes: """
                Time: {start}–{end}
                Duration: {duration}
                Distance: {distance}
                Pace: {pace}
                Avg heart rate: {avgHR}
                Max heart rate: {maxHR}
                Energy: {calories}
                Elevation gain: {elevation}
                """
            )
        case .runner:
            EventTemplate(
                title: "{emoji} {type} · {distance} · {pace}",
                notes: """
                Distance: {distance}
                Time: {duration}
                Pace: {pace}
                Elevation gain: {elevation}
                """
            )
        }
    }
}
