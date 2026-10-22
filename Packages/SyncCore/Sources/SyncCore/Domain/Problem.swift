import Foundation

/// Something the user has to fix before syncing can work. The app stays silent
/// otherwise: these are the only things it notifies about, each one once until
/// it's resolved.
///
/// Adding a kind is one case here, plus its notification text in the app's notifier.
public enum Problem: String, CaseIterable, Codable, Sendable {
    case calendarAccessRevoked
    case destinationCalendarMissing
    case healthAccessRevoked
    /// [v1.1] A workout the rules and the model couldn't match is waiting for the user's
    /// review. Unlike the others, it notifies again for every pass that holds a workout.
    case matchWaitingForReview
}
