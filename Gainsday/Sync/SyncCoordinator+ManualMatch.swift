import Foundation
import SyncCore

/// Settling a logged workout by hand: "Match to an event…" for a plan that synced too
/// late or a workout held for review, and "Add as separate event" for a held one. [v1.1]
extension SyncCoordinator {
    /// The events the entry's workout can be matched to. Never events with guests.
    /// Listing them can fix the ledger, so it waits for any running pass.
    func matchCandidates(for entry: ActivityLogEntry) async throws -> [CalendarEvent] {
        try await withTimeout(Self.passTimeout) { try await self.runner.matchCandidates(forEntryID: entry.id) }
    }

    /// Adopts the event for the entry's workout and removes its separate event. It counts
    /// as a pass, so it never runs alongside one.
    func match(_ entry: ActivityLogEntry, to event: CalendarEvent) async throws {
        runningPasses += 1
        defer { runningPasses -= 1 }
        try await withTimeout(Self.passTimeout) { try await self.runner.match(entryID: entry.id, toEventID: event.id) }
        await refreshActivityLog()
    }

    /// Adds a workout held for review as its own event.
    func addSeparateEvent(for entry: ActivityLogEntry) async throws {
        runningPasses += 1
        defer { runningPasses -= 1 }
        try await withTimeout(Self.passTimeout) { try await self.runner.addSeparateEvent(entryID: entry.id) }
        await refreshActivityLog()
    }
}
