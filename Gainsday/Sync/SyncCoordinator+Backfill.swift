import Foundation
import SyncCore

/// Backfill: fill in past workouts, after a preview of what would be written.
extension SyncCoordinator {
    /// What a backfill writes: new events, and planned events updated with a workout.
    nonisolated struct BackfillCounts: Equatable {
        var newEventCount = 0
        var plannedEventCount = 0

        init(newEventCount: Int = 0, plannedEventCount: Int = 0) {
            self.newEventCount = newEventCount
            self.plannedEventCount = plannedEventCount
        }

        init(_ result: SyncResult) {
            for action in result.actions {
                switch action {
                case .create: newEventCount += 1
                case .adopt: plannedEventCount += 1
                default: break
                }
            }
        }

        /// Whether the backfill writes anything, so it's worth committing.
        var hasWrites: Bool { newEventCount + plannedEventCount > 0 }
    }

    struct BackfillPreview {
        /// The range the preview covered. Commit this same range so the result matches.
        var interval: DateInterval
        var counts: BackfillCounts
    }

    /// What a backfill of `interval` would write. Writes nothing.
    func previewBackfill(_ interval: DateInterval) async throws -> BackfillPreview {
        let result = try await runBackfill(interval, mode: .preview)
        return BackfillPreview(interval: interval, counts: BackfillCounts(result))
    }

    /// Backfills `interval` and returns what it wrote.
    @discardableResult
    func backfill(_ interval: DateInterval) async throws -> BackfillCounts {
        let result = try await runBackfill(interval, mode: .commit)
        let counts = BackfillCounts(result)
        lastPass = Pass(finishedAt: clock.now)
        // The sync start date may have moved back.
        await load()
        await refreshActivityLog()
        return counts
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

    /// Runs a backfill pass once no other pass is running. A long range takes longer
    /// than a catch-up pass, so it gets twice the time before showing an error.
    private func runBackfill(_ interval: DateInterval, mode: BackfillMode) async throws -> SyncResult {
        runningPasses += 1
        defer { runningPasses -= 1 }
        return try await withTimeout(Self.passTimeout * 2) {
            // After a reinstall, give the ledger a chance to come back from iCloud first.
            guard await self.cloudImport.isSafeToWrite(with: self.calendar.accessMode()) else {
                throw WaitingForICloudImport()
            }
            return try await self.runner.backfill(interval, mode: mode)
        }
    }
}
