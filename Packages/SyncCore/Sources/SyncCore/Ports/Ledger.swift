import Foundation

/// Stores ledger entries (SwiftData with CloudKit in the app).
public protocol Ledger: Sendable {
    /// Every entry covering the workout, as the cluster or as a member. There can
    /// be more than one after an iCloud merge.
    func entries(forWorkout workoutID: UUID) async throws -> [LedgerEntry]

    /// Entries whose workout overlaps `interval`.
    func entries(in interval: DateInterval) async throws -> [LedgerEntry]

    /// Entries with `needsLinking` set.
    func entriesNeedingLinking() async throws -> [LedgerEntry]

    /// Inserts the entry, or replaces the entry with the same `id`.
    func save(_ entry: LedgerEntry) async throws

    func delete(entryID: UUID) async throws
}
