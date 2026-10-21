import Foundation
import SyncCore

/// An activity log held in memory.
public actor InMemoryActivityLogStore: ActivityLogStore {
    /// The log, newest first.
    public private(set) var entries: [ActivityLogEntry]

    public init(entries: [ActivityLogEntry] = []) {
        self.entries = entries
    }

    public func load() async throws -> [ActivityLogEntry] {
        entries
    }

    public func save(_ entries: [ActivityLogEntry]) async throws {
        self.entries = entries
    }
}
