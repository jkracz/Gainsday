import Foundation

/// One thing the app did, as shown in the activity log.
///
/// Each entry wraps the `SyncAction` a pass took, plus what the log needs to show it
/// and, when the action can be reversed, how to undo it.
public struct ActivityLogEntry: Identifiable, Hashable, Codable, Sendable {
    /// About how many entries the log keeps. Older ones are dropped.
    public static let capacity = 50

    public var id: UUID
    /// When the action was taken.
    public var date: Date
    public var action: SyncAction
    /// What to call the workout or event in the log, e.g. the event title.
    public var title: String
    public var activityType: WorkoutActivityType?
    public var workoutStart: Date?
    /// The event the action was about, when there is one.
    public var eventID: String?
    /// How to reverse the action, or nil when it can't be undone.
    public var undo: Undo?
    /// When the user undid the action, or nil if they haven't.
    public var undoneAt: Date?

    public init(
        id: UUID = UUID(),
        date: Date,
        action: SyncAction,
        title: String,
        activityType: WorkoutActivityType? = nil,
        workoutStart: Date? = nil,
        eventID: String? = nil,
        undo: Undo? = nil,
        undoneAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.action = action
        self.title = title
        self.activityType = activityType
        self.workoutStart = workoutStart
        self.eventID = eventID
        self.undo = undo
        self.undoneAt = undoneAt
    }

    public var workoutID: UUID { action.workoutID }

    /// Whether the user can undo this entry now.
    public var canUndo: Bool { undo != nil && undoneAt == nil }
}

extension ActivityLogEntry {
    /// How to reverse an action.
    public enum Undo: Hashable, Codable, Sendable {
        /// Undo a create: delete the event and tombstone the workout, so it isn't created again.
        case removeCreatedEvent
        /// Undo an update: put back what the event held before, and leave it alone afterwards.
        case restoreEvent(EventContent)
        /// Undo a delete: create the event again as it was, and leave it alone afterwards.
        case recreateEvent(EventDraft)
        /// Undo a match the user made from the log: put the planned event back as it was
        /// and add the workout's separate event again. The create entry it was matched
        /// from can be undone again afterwards. [v1.1]
        case separateFromPlannedEvent(EventDraft, createEntryID: UUID)
        /// Undo an update to a planned event: put back the event as the user planned it,
        /// and let go of it. The user chooses what happens to the workout. [v1.1]
        case restorePlannedEvent(EventContent)
    }

    /// What happens to the workout once an update to a planned event is undone. [v1.1]
    public enum PlannedEventUndoChoice: Hashable, Codable, Sendable {
        /// The workout gets its own event, as if no plan had matched.
        case separateEvent
        /// The workout is left out of the calendar for good.
        case dropWorkout
    }
}

extension SyncAction {
    /// The workout the action was about.
    public var workoutID: UUID {
        switch self {
        case .create(let workoutID, _), .update(let workoutID, _, _), .delete(let workoutID, _),
             .skip(let workoutID, _), .release(let workoutID, _), .holdForReview(let workoutID),
             .relink(let workoutID, _), .adopt(let workoutID, _, _, _), .removeWorkoutSection(let workoutID, _, _):
            workoutID
        }
    }
}
