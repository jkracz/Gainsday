import Foundation
import SyncCore
import Testing
@testable import Gainsday

@Suite("File activity log store")
struct FileActivityLogStoreTests {
    let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString)/ActivityLog.json")

    static func entry() -> ActivityLogEntry {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let content = EventContent(title: "🏃 Running", start: start, end: start.addingTimeInterval(1_800), notes: "Notes")
        return ActivityLogEntry(
            date: start,
            action: .create(workoutID: UUID(), EventDraft(calendarID: "workouts", content: content)),
            title: content.title,
            activityType: .running,
            workoutStart: start,
            eventID: "event-1",
            undo: .removeCreatedEvent
        )
    }

    @Test("A saved log comes back exactly as it was")
    func roundTrip() async throws {
        let store = FileActivityLogStore(url: url)
        var skipped = Self.entry()
        skipped.action = .skip(workoutID: UUID(), .tooShort)
        skipped.undo = nil
        let entries = [Self.entry(), skipped]

        try await store.save(entries)

        #expect(try await FileActivityLogStore(url: url).load() == entries)
    }

    @Test("With no file yet the log is empty")
    func emptyWithoutFile() async throws {
        #expect(try await FileActivityLogStore(url: url).load().isEmpty)
    }

    @Test("The log file is left out of device backups")
    func excludedFromBackup() async throws {
        try await FileActivityLogStore(url: url).save([Self.entry()])

        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
}
