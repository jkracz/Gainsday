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
    /// What the app last wrote, used to detect user edits.
    public var written: EventContent?
    /// For adopted events: the event before the app updated it.
    public var preUpdate: EventContent?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        workoutID: UUID,
        memberIDs: Set<UUID> = [],
        workoutStart: Date,
        workoutEnd: Date,
        state: State,
        eventExternalIdentifier: String? = nil,
        calendarID: String? = nil,
        written: EventContent? = nil,
        preUpdate: EventContent? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.workoutID = workoutID
        self.memberIDs = memberIDs.union([workoutID])
        self.workoutStart = workoutStart
        self.workoutEnd = workoutEnd
        self.state = state
        self.eventExternalIdentifier = eventExternalIdentifier
        self.calendarID = calendarID
        self.written = written
        self.preUpdate = preUpdate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Whether this entry is about the given workout, either as the cluster or as a member.
    public func covers(_ workoutID: UUID) -> Bool {
        memberIDs.contains(workoutID)
    }
}
