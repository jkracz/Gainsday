import Foundation
import SyncCore

/// Keeps the activity log in a JSON file on this device only. The log isn't synced
/// to iCloud, and the file is left out of device backups.
actor FileActivityLogStore: ActivityLogStore {
    private var url: URL

    init(url: URL = .applicationSupportDirectory.appending(path: "ActivityLog.json")) {
        self.url = url
    }

    func load() async throws -> [ActivityLogEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        // The log is disposable: if it can't be read, e.g. after a format change, start over.
        return (try? JSONDecoder().decode([ActivityLogEntry].self, from: data)) ?? []
    }

    func save(_ entries: [ActivityLogEntry]) async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
        // An atomic write replaces the file, so mark it again each time.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
