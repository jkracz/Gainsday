import Foundation

/// Stores the activity log on this device only. The log isn't synced to iCloud.
///
/// The engine decides what goes in the log and caps it; the store only keeps it.
public protocol ActivityLogStore: Sendable {
    /// The stored log, newest first.
    func load() async throws -> [ActivityLogEntry]

    /// Replaces the stored log.
    func save(_ entries: [ActivityLogEntry]) async throws
}
