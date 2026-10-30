import Foundation

/// What matching would do to a planned event, for the explanation the user sees
/// before turning matching on. It uses the same code as a sync pass, so the "after"
/// shown is exactly what the user would get. [v1.1]
public enum MatchingExample {
    /// The planned event as a sync pass would update it with the workout.
    public static func updating(_ planned: EventContent, with workout: Workout, settings: Settings, clock: any Clock) -> EventContent {
        EventComposer(settings: settings, clock: clock).adoptedContent(updating: planned, with: workout)
    }
}
