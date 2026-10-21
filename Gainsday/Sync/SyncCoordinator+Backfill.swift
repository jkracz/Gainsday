import Foundation
import SyncCore

/// Backfill: fill in past workouts, after a preview of what would be written.
extension SyncCoordinator {
    struct BackfillPreview {
        /// The range the preview covered. Commit this same range so the result matches.
        var interval: DateInterval
        var newEventCount: Int
    }

    /// What a backfill of `interval` would create. Writes nothing.
    func previewBackfill(_ interval: DateInterval) async throws -> BackfillPreview {
        let result = try await runBackfill(interval, mode: .preview)
        return BackfillPreview(interval: interval, newEventCount: result.createdCount)
    }

    /// Backfills `interval` and returns how many events it created.
    @discardableResult
    func backfill(_ interval: DateInterval) async throws -> Int {
        let result = try await runBackfill(interval, mode: .commit)
        lastPass = Pass(finishedAt: clock.now, createdCount: result.createdCount)
        // The sync start date may have moved back.
        await load()
        await refreshActivityLog()
        return result.createdCount
    }

    /// The backfill setup offers by default: the past 7 days.
    func backfillPastWeek() async {
        let now = clock.now
        do {
            try await backfill(DateInterval(start: now.addingTimeInterval(-7 * 24 * 60 * 60), end: now))
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Runs a backfill pass once no other pass is running.
    private func runBackfill(_ interval: DateInterval, mode: BackfillMode) async throws -> SyncResult {
        while isSyncing {
            try await Task.sleep(for: .milliseconds(200))
        }
        isSyncing = true
        defer { isSyncing = false }
        // After a reinstall, give the ledger a chance to come back from iCloud first.
        _ = await cloudImport.waitForInitialImport()
        return try await engine.run(.backfill(interval, mode))
    }
}

private extension SyncResult {
    var createdCount: Int {
        actions.count { if case .create = $0 { true } else { false } }
    }
}
