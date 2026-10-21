import Foundation

/// Runs sync passes one at a time, so a background wake, an app open and a backfill
/// that overlap never read the same Health changes twice and create no duplicates.
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

    /// Starts `pass` once every pass queued before it has finished.
    private func enqueue(_ pass: @escaping @Sendable () async throws -> SyncResult) -> Task<SyncResult, any Error> {
        let previous = queueTail
        let task = Task {
            await previous?.value
            return try await pass()
        }
        queueTail = Task { _ = try? await task.value }
        return task
    }
}
