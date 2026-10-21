import Foundation

/// What started a sync pass.
public enum SyncTrigger: Hashable, Sendable {
    /// Background delivery or app open: process Health changes since `anchor`.
    case changes(since: WorkoutAnchor?)
    /// Backfill a date range, either previewing what would be written or writing it.
    case backfill(DateInterval, BackfillMode)
}

public enum BackfillMode: Hashable, Sendable {
    case preview
    case commit
}

/// Why a workout was left alone.
public enum SkipReason: Hashable, Codable, Sendable {
    case typeDisabled
    case tooShort
    case beforeSyncStartDate
    case tombstoned
    case alreadySynced
    case sourceNotAllowed
    /// Updating or deleting the event needs full calendar access, and the app has add-only access.
    case requiresFullAccess
}

/// One action a pass took, or planned to take in a backfill preview. Each one
/// becomes an activity log entry.
public enum SyncAction: Hashable, Codable, Sendable {
    case create(workoutID: UUID, EventDraft)
    case update(workoutID: UUID, eventID: String, EventContent)
    case delete(workoutID: UUID, eventID: String)
    case skip(workoutID: UUID, SkipReason)
    case release(workoutID: UUID, eventID: String)
    case holdForReview(workoutID: UUID)
    /// An event the app wrote earlier, found in the calendar and recorded in the ledger
    /// again instead of being duplicated, e.g. after a reinstall.
    case relink(workoutID: UUID, eventID: String)
    /// A planned event the user made, updated with the workout and adopted, instead of
    /// adding a separate event. [v1.1]
    case adopt(workoutID: UUID, eventID: String, EventContent, decidedBy: MatchDecider)
    /// An adopted event whose workout was deleted in Health, with the workout section
    /// taken out and everything else left as the user had it. [v1.1]
    case removeWorkoutSection(workoutID: UUID, eventID: String, EventContent)
}

public struct SyncResult: Hashable, Sendable {
    public var actions: [SyncAction]
    /// The anchor to store once the pass has finished, or nil when the trigger
    /// didn't read Health changes.
    public var nextAnchor: WorkoutAnchor?

    public init(actions: [SyncAction] = [], nextAnchor: WorkoutAnchor? = nil) {
        self.actions = actions
        self.nextAnchor = nextAnchor
    }
}
