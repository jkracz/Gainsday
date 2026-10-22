import Foundation
import SyncCore

/// A ledger held in memory. Like the iCloud-backed one, it allows several entries
/// for the same workout.
public actor InMemoryLedger: Ledger {
    private var storedEntries: [UUID: LedgerEntry] = [:]
    private var saveError: (any Error)?
    private var savesBeforeFailing = 0

    public init(entries: [LedgerEntry] = []) {
        for entry in entries {
            storedEntries[entry.id] = entry
        }
    }

    /// Every entry, sorted by creation date.
    public var allEntries: [LedgerEntry] {
        storedEntries.values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    public func entries(forWorkout workoutID: UUID) async throws -> [LedgerEntry] {
        allEntries.filter { $0.covers(workoutID) }
    }

    public func entries(in interval: DateInterval) async throws -> [LedgerEntry] {
        allEntries.filter { $0.workoutStart < interval.end && $0.workoutEnd > interval.start }
    }

    public func entriesNeedingLinking() async throws -> [LedgerEntry] {
        allEntries.filter { $0.needsLinking || $0.needsHealthFollowUp }
    }

    /// Makes every later save throw `error`, as a full disk or store failure would,
    /// after letting `successes` more saves through.
    public func failSaves(with error: any Error, afterSucceeding successes: Int = 0) {
        saveError = error
        savesBeforeFailing = successes
    }

    /// Lets saves succeed again.
    public func resumeSaves() {
        saveError = nil
    }

    public func save(_ entry: LedgerEntry) async throws {
        if let saveError {
            guard savesBeforeFailing > 0 else { throw saveError }
            savesBeforeFailing -= 1
        }
        storedEntries[entry.id] = entry
    }

    public func delete(entryID: UUID) async throws {
        storedEntries[entryID] = nil
    }
}
