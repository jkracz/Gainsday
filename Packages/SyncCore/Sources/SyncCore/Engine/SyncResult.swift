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
public enum SkipReason: Hashable, Sendable {
    case typeDisabled
    case tooShort
    case beforeSyncStartDate
    case tombstoned
    case alreadySynced
    case sourceNotAllowed
}

/// One action a pass took, or planned to take in a backfill preview. Each one
/// becomes an activity log entry.
public enum SyncAction: Hashable, Sendable {
    case create(workoutID: UUID, EventDraft)
    case update(workoutID: UUID, eventID: String, EventContent)
    case delete(workoutID: UUID, eventID: String)
    case skip(workoutID: UUID, SkipReason)
    case release(workoutID: UUID, eventID: String)
    case holdForReview(workoutID: UUID)
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
