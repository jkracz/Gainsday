import Foundation

/// How much calendar access the user granted.
public enum AccessMode: String, Codable, Sendable {
    /// Read and write access.
    case full
    /// EventKit write-only access: the app can add events but not read, update or delete them.
    case addOnly
    /// No access, or access was revoked.
    case none
}

/// A calendar on the phone that events can be written to or searched.
public struct CalendarInfo: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var title: String
    public var allowsContentModifications: Bool
    public var supportsAvailability: Bool

    public init(id: String, title: String, allowsContentModifications: Bool = true, supportsAvailability: Bool = true) {
        self.id = id
        self.title = title
        self.allowsContentModifications = allowsContentModifications
        self.supportsAvailability = supportsAvailability
    }
}

/// A calendar as stored in settings: by identifier, with the title kept as a
/// fallback for re-resolving it when the identifier changes.
public struct CalendarReference: Hashable, Codable, Sendable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

extension CalendarReference {
    /// Stands for whichever calendar the user's settings send new events to. With
    /// add-only access iOS doesn't let the app choose a calendar, or even see which
    /// one this is, so it's the only destination there is.
    public static let defaultCalendarID = "gainsday.default-calendar"
    /// The UI shows its own name for it: the title is only a fallback.
    public static let defaultCalendar = CalendarReference(id: defaultCalendarID, title: "Default Calendar")

    public var isDefaultCalendar: Bool { id == Self.defaultCalendarID }
}

/// Whether an event blocks the user's time.
public enum EventAvailability: String, Codable, Sendable {
    case busy
    case free
    case notSupported
}

/// The fields of an event the app writes and compares against the ledger snapshot.
public struct EventContent: Hashable, Codable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var notes: String?

    public init(title: String, start: Date, end: Date, notes: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
    }
}

/// An event to be created in a calendar.
public struct EventDraft: Hashable, Codable, Sendable {
    public var calendarID: String
    public var content: EventContent
    public var availability: EventAvailability

    public init(calendarID: String, content: EventContent, availability: EventAvailability = .free) {
        self.calendarID = calendarID
        self.content = content
        self.availability = availability
    }
}

/// An event read from a calendar.
public struct CalendarEvent: Identifiable, Hashable, Codable, Sendable {
    /// The event's `calendarItemExternalIdentifier`. It can change after the first
    /// server sync, so the engine re-reads it and fixes the ledger.
    public var id: String
    public var calendarID: String
    public var content: EventContent
    public var availability: EventAvailability
    public var isAllDay: Bool
    public var attendeeCount: Int
    public var isDeclinedByUser: Bool
    public var lastModified: Date?
    /// Whether the event is an occurrence of a repeating event. Occurrences share one
    /// external identifier, so the app can't update one of them on its own.
    public var isRecurring: Bool

    public init(
        id: String,
        calendarID: String,
        content: EventContent,
        availability: EventAvailability = .busy,
        isAllDay: Bool = false,
        attendeeCount: Int = 0,
        isDeclinedByUser: Bool = false,
        lastModified: Date? = nil,
        isRecurring: Bool = false
    ) {
        self.id = id
        self.calendarID = calendarID
        self.content = content
        self.availability = availability
        self.isAllDay = isAllDay
        self.attendeeCount = attendeeCount
        self.isDeclinedByUser = isDeclinedByUser
        self.lastModified = lastModified
        self.isRecurring = isRecurring
    }
}
