import Foundation

/// What happens when a workout matches an event the user planned. [v1.1]
public enum MatchMode: String, Codable, Sendable {
    /// Move the planned event to the workout's times and add the workout to its notes.
    case updatePlannedEvent
    /// Leave the plan alone and add a separate event, even when one matches.
    case createSeparateEvent
}

/// Who decided that a workout matches a planned event, as the activity log shows it. [v1.1]
public enum MatchDecider: String, Hashable, Codable, Sendable {
    /// The built-in and user keyword rules.
    case rules
    /// The on-device model, asked about a case the rules found unclear.
    case model
    /// The user, who chose the event with "Match to an event…" in the activity log.
    case user
}

extension SyncAction {
    /// Who decided the match, for an adopted planned event.
    public var matchDecider: MatchDecider? {
        if case .adopt(_, _, _, let decider) = self { decider } else { nil }
    }
}

/// Words in an event title that say which kind of workout was planned. [v1.1]
///
/// A keyword is one or more whole words, matched case- and accent-insensitively.
/// "Gym" is left out on purpose: a gym session can be a run, a ride or weights.
/// Keywords are English, like the rest of the event text.
public enum MatchKeywords {
    public static let builtIn: [WorkoutActivityType: [String]] = [
        .running: ["run", "runs", "running", "jog", "jogging", "tempo", "fartlek", "parkrun", "5k", "10k", "half marathon", "marathon"],
        .walking: ["walk", "walks", "walking", "stroll"],
        .hiking: ["hike", "hikes", "hiking", "trek", "trekking"],
        .cycling: ["ride", "rides", "riding", "cycle", "cycling", "bike", "biking", "spin", "spinning", "mtb"],
        .swimming: ["swim", "swims", "swimming", "pool"],
        .rowing: ["row", "rowing", "erg"],
        .elliptical: ["elliptical", "cross trainer"],
        .traditionalStrengthTraining: strength,
        .functionalStrengthTraining: strength + ["functional", "crossfit", "wod", "kettlebell", "kettlebells"],
        .highIntensityIntervalTraining: ["hiit", "tabata", "bootcamp", "circuit", "circuits"],
        .yoga: ["yoga", "vinyasa", "hatha", "ashtanga"],
    ]

    private static let strength = [
        "lift", "lifting", "weights", "weightlifting", "strength", "squat", "squats", "deadlift", "deadlifts",
        "bench press", "powerlifting", "leg day", "upper body", "lower body",
    ]
}
