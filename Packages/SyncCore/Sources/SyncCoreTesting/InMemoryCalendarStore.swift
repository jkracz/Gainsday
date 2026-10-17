import Foundation
import SyncCore

/// Calendars and events held in memory. It can simulate full, add-only or no access.
public actor InMemoryCalendarStore: CalendarStore {
    public private(set) var calendars: [CalendarInfo]
    private var storedEvents: [String: CalendarEvent] = [:]
    private var nextEventNumber = 1
    private var mode: AccessMode
    private let clock: any Clock
    public private(set) var refreshCount = 0

    public init(calendars: [CalendarInfo] = [], events: [CalendarEvent] = [], accessMode: AccessMode = .full, clock: any Clock) {
        self.calendars = calendars
        self.mode = accessMode
        self.clock = clock
        for event in events {
            storedEvents[event.id] = event
        }
    }

    /// Every event in the store, regardless of access mode, sorted by start.
    public var allEvents: [CalendarEvent] {
        storedEvents.values.sorted { ($0.content.start, $0.id) < ($1.content.start, $1.id) }
    }

    public func setAccessMode(_ mode: AccessMode) {
        self.mode = mode
    }

    /// Puts an event in the store as if the user had created or edited it.
    public func put(_ event: CalendarEvent) {
        storedEvents[event.id] = event
    }

    /// Removes an event as if the user had deleted it.
    public func remove(eventID: String) {
        storedEvents[eventID] = nil
    }

    /// Changes an event's external identifier, as a server sync can.
    public func changeIdentifier(of eventID: String, to newID: String) {
        guard var event = storedEvents.removeValue(forKey: eventID) else { return }
        event.id = newID
        storedEvents[newID] = event
    }

    public func accessMode() async -> AccessMode {
        mode
    }

    public func writableCalendars() async throws -> [CalendarInfo] {
        guard mode != .none else { throw CalendarStoreError.accessDenied }
        return calendars.filter(\.allowsContentModifications)
    }

    public func events(in interval: DateInterval, calendarIDs: Set<String>) async throws -> [CalendarEvent] {
        try requireFullAccess()
        return allEvents.filter { event in
            calendarIDs.contains(event.calendarID)
                && event.content.start < interval.end
                && event.content.end > interval.start
        }
    }

    public func event(withID id: String) async throws -> CalendarEvent? {
        try requireFullAccess()
        return storedEvents[id]
    }

    public func create(_ draft: EventDraft) async throws -> CalendarEvent {
        guard mode != .none else { throw CalendarStoreError.accessDenied }
        guard let calendar = calendars.first(where: { $0.id == draft.calendarID }) else {
            throw CalendarStoreError.calendarNotFound(id: draft.calendarID)
        }
        let event = CalendarEvent(
            id: "event-\(nextEventNumber)",
            calendarID: draft.calendarID,
            content: draft.content,
            availability: calendar.supportsAvailability ? draft.availability : .notSupported,
            lastModified: clock.now
        )
        nextEventNumber += 1
        storedEvents[event.id] = event
        return event
    }

    public func update(eventID: String, to content: EventContent) async throws -> CalendarEvent {
        try requireFullAccess()
        guard var event = storedEvents[eventID] else { throw CalendarStoreError.eventNotFound(id: eventID) }
        event.content = content
        event.lastModified = clock.now
        storedEvents[eventID] = event
        return event
    }

    public func delete(eventID: String) async throws {
        try requireFullAccess()
        guard storedEvents.removeValue(forKey: eventID) != nil else {
            throw CalendarStoreError.eventNotFound(id: eventID)
        }
    }

    public func refreshSources() async {
        refreshCount += 1
    }

    private func requireFullAccess() throws {
        switch mode {
        case .full: return
        case .addOnly: throw CalendarStoreError.requiresFullAccess
        case .none: throw CalendarStoreError.accessDenied
        }
    }
}
