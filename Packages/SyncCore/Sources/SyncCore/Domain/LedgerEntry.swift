import Foundation

/// The per-workout record of which event belongs to which workout.
///
/// Entries sync through the user's private iCloud, so the same workout can end up
/// with duplicate entries after a merge. The engine must resolve them deterministically.
public struct LedgerEntry: Identifiable, Hashable, Codable, Sendable {
    public enum State: String, Codable, Sendable {
        /// An event the app created for the workout.
        case owned
        /// A user-created planned event that the app updated with the workout.
        case adopted
        /// An owned or adopted event the user edited. The app never touches it again.
        case released
        /// Never create an event for this workout again.
        case tombstoned
    }

    /// The entry's own identity, distinct from the workout's, so duplicates can coexist.
    public var id: UUID
    /// The cluster's identity: the preferred member's UUID.
    public var workoutID: UUID
    /// Every workout UUID in the cluster, including `workoutID`.
    public var memberIDs: Set<UUID>
    public var workoutStart: Date
    public var workoutEnd: Date
    public var state: State
    /// The event's `calendarItemExternalIdentifier`.
    public var eventExternalIdentifier: String?
    public var calendarID: String?
    /// A digest of what the app last wrote, used to detect user edits. The ledger
    /// syncs to iCloud, so it never keeps the text itself, which holds Health data.
    public var writtenFingerprint: ContentFingerprint?
    /// For adopted events: the event before the app updated it, i.e. the user's own
    /// plan, with no workout section.
    public var preUpdate: EventContent?
    public var createdAt: Date
    public var updatedAt: Date
    /// The cluster's activity type, so a replacement can be told apart from a
    /// different workout. Nil for entries written before it was recorded.
    public var activityType: WorkoutActivityType?
    /// Set when the event was created with add-only access, so the app has never seen
    /// it in the calendar and its identifier may be missing or out of date. The first
    /// pass with full access finds the event and clears it.
    public var needsLinking: Bool
    /// Set when Health deleted or replaced the workout while the app had add-only
    /// access, so its event couldn't be changed. The first pass with full access
    /// applies the change, and clears it.
    public var needsHealthFollowUp: Bool

    public init(
        id: UUID = UUID(),
        workoutID: UUID,
        memberIDs: Set<UUID> = [],
        workoutStart: Date,
        workoutEnd: Date,
        state: State,
        eventExternalIdentifier: String? = nil,
        calendarID: String? = nil,
        writtenFingerprint: ContentFingerprint? = nil,
        preUpdate: EventContent? = nil,
        createdAt: Date,
        updatedAt: Date,
        activityType: WorkoutActivityType? = nil,
        needsLinking: Bool = false,
        needsHealthFollowUp: Bool = false
    ) {
        self.id = id
        self.workoutID = workoutID
        self.memberIDs = memberIDs.union([workoutID])
        self.workoutStart = workoutStart
        self.workoutEnd = workoutEnd
        self.state = state
        self.eventExternalIdentifier = eventExternalIdentifier
        self.calendarID = calendarID
        self.writtenFingerprint = writtenFingerprint
        self.preUpdate = preUpdate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activityType = activityType
        self.needsLinking = needsLinking
        self.needsHealthFollowUp = needsHealthFollowUp
    }

    /// Whether this entry is about the given workout, either as the cluster or as a member.
    ///
    /// Checks `workoutID` directly, because a decoded or edited entry can lack it in `memberIDs`.
    public func covers(_ workoutID: UUID) -> Bool {
        self.workoutID == workoutID || memberIDs.contains(workoutID)
    }
}
