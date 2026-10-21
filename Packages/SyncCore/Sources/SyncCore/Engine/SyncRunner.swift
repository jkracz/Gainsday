import Foundation

/// Runs sync passes one at a time, so a background wake, an app open, a backfill and
/// an Undo that overlap never read the same Health changes twice and create no duplicates.
public actor SyncRunner {
    private let engine: SyncEngine
    private let anchors: any WorkoutAnchorStore
    /// Finishes when the last queued pass has finished.
    private var queueTail: Task<Void, Never>?
    /// A changes pass that is queued but hasn't started. Callers join it rather
    /// than queue another, since it will read every change they could.
    private var waitingChangesPass: Task<SyncResult, any Error>?

    public init(engine: SyncEngine, anchors: any WorkoutAnchorStore) {
        self.engine = engine
        self.anchors = anchors
    }

    /// Runs a pass over the Health changes since the stored anchor, then stores the
    /// next anchor. The pass starts after this call, so it sees every change made
    /// before it, but waits for any pass already running.
    public func syncChanges() async throws -> SyncResult {
        if let waitingChangesPass {
            return try await waitingChangesPass.value
        }
        let pass = enqueue { try await self.changesPass() }
        waitingChangesPass = pass
        return try await pass.value
    }

    private func changesPass() async throws -> SyncResult {
        waitingChangesPass = nil
        let result = try await engine.run(.changes(since: anchors.load()))
        if let anchor = result.nextAnchor {
            await anchors.save(anchor)
        }
        return result
    }

    /// Backfills `interval` once any pass already running has finished.
    public func backfill(_ interval: DateInterval, mode: BackfillMode) async throws -> SyncResult {
        try await enqueue { try await self.engine.run(.backfill(interval, mode)) }.value
    }

    /// Undoes an activity log entry once any pass already running has finished.
    @discardableResult
    public func undo(entryID: UUID) async throws -> ActivityLogEntry {
        try await enqueue { try await self.engine.undo(entryID: entryID) }.value
    }

    /// Undoes an update to a planned event, doing what the user chose with the workout,
    /// once any pass already running has finished.
    @discardableResult
    public func undo(entryID: UUID, choice: ActivityLogEntry.PlannedEventUndoChoice) async throws -> ActivityLogEntry {
        try await enqueue { try await self.engine.undo(entryID: entryID, choice: choice) }.value
    }

    /// The events an activity log entry's workout can be matched to, once any pass already
    /// running has finished. Listing them can collapse duplicate ledger entries and fix
    /// an event's identifier, so it never runs alongside a pass. [v1.1]
    public func matchCandidates(forEntryID entryID: UUID) async throws -> [CalendarEvent] {
        try await enqueue { try await self.engine.matchCandidates(forEntryID: entryID) }.value
    }

    /// Matches an activity log entry's workout to a planned event once any pass already
    /// running has finished. [v1.1]
    @discardableResult
    public func match(entryID: UUID, toEventID eventID: String) async throws -> ActivityLogEntry {
        try await enqueue { try await self.engine.match(entryID: entryID, toEventID: eventID) }.value
    }

    /// Adds a workout held for review as its own event once any pass already running
    /// has finished. [v1.1]
    @discardableResult
    public func addSeparateEvent(entryID: UUID) async throws -> ActivityLogEntry {
        try await enqueue { try await self.engine.addSeparateEvent(entryID: entryID) }.value
    }

    /// Starts `pass` once every pass queued before it has finished.
    private func enqueue<Value: Sendable>(_ pass: @escaping @Sendable () async throws -> Value) -> Task<Value, any Error> {
        let previous = queueTail
        let task = Task {
            await previous?.value
            return try await pass()
        }
        queueTail = Task { _ = try? await task.value }
        return task
    }
}
