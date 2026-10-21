import Foundation

extension LedgerEntry {
    /// The entry to keep when iCloud merges leave several for one workout: a live
    /// entry over a tombstone, then the most recently updated, then the lowest id.
    /// Every device picks the same one.
    public static func survivor(of entries: [LedgerEntry]) -> LedgerEntry? {
        entries.min { a, b in
            let aKey = (a.state == .tombstoned ? 1 : 0, -a.updatedAt.timeIntervalSinceReferenceDate, a.id.uuidString)
            let bKey = (b.state == .tombstoned ? 1 : 0, -b.updatedAt.timeIntervalSinceReferenceDate, b.id.uuidString)
            return aKey < bKey
        }
    }
}

extension SyncEngine {
    /// The workout's single ledger entry, or nil if it has none. Duplicates are
    /// collapsed into the survivor, which keeps every cluster member they covered.
    func resolvedEntry(forWorkout workoutID: UUID) async throws -> LedgerEntry? {
        let entries = try await ledger.entries(forWorkout: workoutID)
        guard var survivor = LedgerEntry.survivor(of: entries) else { return nil }
        let others = entries.filter { $0.id != survivor.id }
        guard !others.isEmpty else { return survivor }

        let members = others.reduce(survivor.memberIDs) { $0.union($1.memberIDs) }
        if members != survivor.memberIDs {
            survivor.memberIDs = members
            try await ledger.save(survivor)
        }
        for other in others {
            try await ledger.delete(entryID: other.id)
        }
        return survivor
    }
}
