import Foundation

/// Finds the problems the user has to fix, and notifies each one once until it's
/// resolved. Normal passes stay silent.
extension SyncEngine {
    /// Notifies about a problem unless it has already been notified.
    public func report(_ problem: Problem) async {
        guard await !notifier.notifiedProblems().contains(problem) else { return }
        await notifier.notify(problem)
    }

    /// Withdraws a notified problem once it's been seen to be fixed.
    func resolve(_ problem: Problem) async {
        guard await notifier.notifiedProblems().contains(problem) else { return }
        await notifier.withdraw(problem)
    }

    /// Checks calendar access and the destination before Health is read, so a pass
    /// that can't write anything doesn't move the anchor.
    func checkCalendar(_ destination: CalendarReference) async throws {
        switch await calendar.accessMode() {
        case .none:
            await report(.calendarAccessRevoked)
            throw CalendarStoreError.accessDenied
        case .full:
            await resolve(.calendarAccessRevoked)
            guard try await calendar.writableCalendars().contains(where: { $0.id == destination.id }) else {
                await report(.destinationCalendarMissing)
                throw CalendarStoreError.calendarNotFound(id: destination.id)
            }
            await resolve(.destinationCalendarMissing)
        case .addOnly:
            // Add-only access can't list calendars. Whether the destination exists
            // shows up when an event is created instead.
            await resolve(.calendarAccessRevoked)
        }
    }

    /// Creates an event, reporting the problem if access or the calendar is gone.
    func createEvent(_ draft: EventDraft) async throws -> CalendarEvent {
        do {
            let event = try await calendar.create(draft)
            await resolve(.destinationCalendarMissing)
            return event
        } catch CalendarStoreError.accessDenied {
            await report(.calendarAccessRevoked)
            throw CalendarStoreError.accessDenied
        } catch CalendarStoreError.calendarNotFound(let id) {
            await report(.destinationCalendarMissing)
            throw CalendarStoreError.calendarNotFound(id: id)
        }
    }

    /// Reads Health changes, reporting the problem if Health access is off.
    func readChanges(since anchor: WorkoutAnchor?) async throws -> WorkoutChanges {
        do {
            let changes = try await workouts.changes(since: anchor)
            await resolve(.healthAccessRevoked)
            return changes
        } catch WorkoutSourceError.accessDenied {
            await report(.healthAccessRevoked)
            throw WorkoutSourceError.accessDenied
        }
    }
}
