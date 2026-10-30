import Foundation

public enum CalendarStoreError: Error, Hashable, Sendable {
    /// The operation needs full access, but the app has add-only access. Read
    /// operations report this rather than returning empty results.
    case requiresFullAccess
    /// The app has no calendar access.
    case accessDenied
    case calendarNotFound(id: String)
    case eventNotFound(id: String)
}

/// Reads and writes calendar events (EventKit in the app).
public protocol CalendarStore: Sendable {
    func accessMode() async -> AccessMode

    func writableCalendars() async throws -> [CalendarInfo]

    /// Events overlapping `interval` in the given calendars.
    /// Throws `CalendarStoreError.requiresFullAccess` in add-only mode.
    func events(in interval: DateInterval, calendarIDs: Set<String>) async throws -> [CalendarEvent]

    /// The event with this external identifier, or nil if it no longer exists.
    /// Throws `CalendarStoreError.requiresFullAccess` in add-only mode.
    func event(withID id: String) async throws -> CalendarEvent?

    /// Creates an event and returns it as stored, including its identifier. A draft for
    /// `CalendarReference.defaultCalendarID` goes to the default calendar. In add-only
    /// mode the returned event's `calendarID` is the draft's, since the app can't see
    /// which calendar that was.
    func create(_ draft: EventDraft) async throws -> CalendarEvent

    /// Replaces an event's content. Throws `CalendarStoreError.requiresFullAccess` in add-only mode.
    func update(eventID: String, to content: EventContent) async throws -> CalendarEvent

    /// Throws `CalendarStoreError.requiresFullAccess` in add-only mode.
    func delete(eventID: String) async throws

    /// Asks calendar accounts to fetch remote changes. Best effort.
    func refreshSources() async

    /// The calendar new events go to by default, or nil if there's none or the app can't tell.
    func defaultCalendarID() async -> String?
}
