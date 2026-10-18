import EventKit
import Foundation
import SyncCore

/// Reads and writes calendar events with EventKit. Events are identified by their
/// `calendarItemExternalIdentifier`.
actor EventKitCalendarStore: CalendarStore {
    private let store = EKEventStore()

    /// Shows the full calendar access prompt if the user hasn't answered it yet.
    func requestFullAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func accessMode() async -> AccessMode {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .full
        case .writeOnly: .addOnly
        default: .none
        }
    }

    func writableCalendars() async throws -> [CalendarInfo] {
        guard await accessMode() != .none else { throw CalendarStoreError.accessDenied }
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map(Self.calendarInfo)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func events(in interval: DateInterval, calendarIDs: Set<String>) async throws -> [CalendarEvent] {
        try await requireFullAccess()
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return store.events(matching: predicate).map(Self.calendarEvent)
    }

    func event(withID id: String) async throws -> CalendarEvent? {
        try await requireFullAccess()
        return ekEvent(withID: id).map(Self.calendarEvent)
    }

    func create(_ draft: EventDraft) async throws -> CalendarEvent {
        guard await accessMode() != .none else { throw CalendarStoreError.accessDenied }
        guard let calendar = store.calendar(withIdentifier: draft.calendarID) else {
            throw CalendarStoreError.calendarNotFound(id: draft.calendarID)
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        apply(draft.content, to: event)
        if draft.availability == .free, calendar.supportedEventAvailabilities.contains(.free) {
            event.availability = .free
        }
        try store.save(event, span: .thisEvent, commit: true)
        return Self.calendarEvent(event)
    }

    func update(eventID: String, to content: EventContent) async throws -> CalendarEvent {
        try await requireFullAccess()
        guard let event = ekEvent(withID: eventID) else { throw CalendarStoreError.eventNotFound(id: eventID) }
        apply(content, to: event)
        try store.save(event, span: .thisEvent, commit: true)
        return Self.calendarEvent(event)
    }

    func delete(eventID: String) async throws {
        try await requireFullAccess()
        guard let event = ekEvent(withID: eventID) else { throw CalendarStoreError.eventNotFound(id: eventID) }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    func refreshSources() async {
        store.refreshSourcesIfNecessary()
    }

    private func requireFullAccess() async throws {
        switch await accessMode() {
        case .full: return
        case .addOnly: throw CalendarStoreError.requiresFullAccess
        case .none: throw CalendarStoreError.accessDenied
        }
    }

    /// Looks up by external identifier, falling back to the local identifier used
    /// for events that had no external identifier yet when they were created.
    private func ekEvent(withID id: String) -> EKEvent? {
        store.calendarItems(withExternalIdentifier: id).lazy.compactMap { $0 as? EKEvent }.first
            ?? store.calendarItem(withIdentifier: id) as? EKEvent
    }

    private func apply(_ content: EventContent, to event: EKEvent) {
        event.title = content.title
        event.startDate = content.start
        event.endDate = content.end
        event.notes = content.notes
    }

    private static func calendarInfo(_ calendar: EKCalendar) -> CalendarInfo {
        CalendarInfo(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            allowsContentModifications: calendar.allowsContentModifications,
            supportsAvailability: calendar.supportedEventAvailabilities.contains(.free)
        )
    }

    private static func calendarEvent(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier,
            calendarID: event.calendar.calendarIdentifier,
            content: EventContent(title: event.title ?? "", start: event.startDate, end: event.endDate, notes: event.notes),
            availability: availability(event.availability),
            isAllDay: event.isAllDay,
            attendeeCount: event.attendees?.count ?? 0,
            isDeclinedByUser: event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false,
            lastModified: event.lastModifiedDate
        )
    }

    private static func availability(_ availability: EKEventAvailability) -> EventAvailability {
        switch availability {
        case .free: .free
        case .notSupported: .notSupported
        default: .busy
        }
    }
}
