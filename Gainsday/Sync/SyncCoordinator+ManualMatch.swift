import Foundation
import SyncCore

/// "Match to an event…": matching a logged workout to a plan that synced too late. [v1.1]
extension SyncCoordinator {
    /// The events the entry's workout can be matched to. Never events with guests.
    func matchCandidates(for entry: ActivityLogEntry) async throws -> [CalendarEvent] {
        try await engine.matchCandidates(forEntryID: entry.id)
    }

    /// Adopts the event for the entry's workout and removes its separate event. It counts
    /// as a pass, so it never runs alongside one.
    func match(_ entry: ActivityLogEntry, to event: CalendarEvent) async throws {
        runningPasses += 1
        defer { runningPasses -= 1 }
        try await runner.match(entryID: entry.id, toEventID: event.id)
        await refreshActivityLog()
    }
}
