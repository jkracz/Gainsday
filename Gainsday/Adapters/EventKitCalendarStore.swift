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

    /// Shows the add-only access prompt if the user hasn't answered it yet. With this
    /// access the app can add events but can't see any, not even its own.
    func requestAddOnlyAccess() async throws -> Bool {
        try await store.requestWriteOnlyAccessToEvents()
    }

    /// Fires when calendars or events change, in this app or elsewhere.
    nonisolated func changes() -> AsyncStream<Void> {
        NotificationCenter.default.signals(named: .EKEventStoreChanged)
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
        let mode = await accessMode()
        guard mode != .none else { throw CalendarStoreError.accessDenied }
        guard let calendar = calendar(withID: draft.calendarID) else {
            throw CalendarStoreError.calendarNotFound(id: draft.calendarID)
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        apply(draft.content, to: event)
        if draft.availability == .free, calendar.supportedEventAvailabilities.contains(.free) {
            event.availability = .free
        }
        try store.save(event, span: .thisEvent, commit: true)
        var created = Self.calendarEvent(event)
        if mode == .addOnly {
            // The event's calendar is a stand-in that says nothing about where it went.
            created.calendarID = draft.calendarID
        }
        return created
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

    func defaultCalendarID() async -> String? {
        guard await accessMode() == .full else { return nil }
        return store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    /// With add-only access, `defaultCalendarForNewEvents` is a stand-in calendar that
    /// saves to the user's default calendar. The calendar picked in `EKCalendarChooser`
    /// is the same stand-in, and only sends events to the pick through the store that
    /// showed the chooser, until the app quits. So add-only mode uses the default calendar.
    private func calendar(withID id: String) -> EKCalendar? {
        id == CalendarReference.defaultCalendarID ? store.defaultCalendarForNewEvents : store.calendar(withIdentifier: id)
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

    /// Times are written in whole seconds, as the fingerprint compares them, so a
    /// store that rounds rather than truncates can't make an event look edited.
    private func apply(_ content: EventContent, to event: EKEvent) {
        event.title = content.title
        event.startDate = content.start.truncatedToSecond
        event.endDate = content.end.truncatedToSecond
        event.notes = content.notes
    }

    static func calendarInfo(_ calendar: EKCalendar) -> CalendarInfo {
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
            lastModified: event.lastModifiedDate,
            isRecurring: event.hasRecurrenceRules
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

nonisolated private extension Date {
    /// The same instant without its fraction of a second, matching `ContentFingerprint`.
    var truncatedToSecond: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}
