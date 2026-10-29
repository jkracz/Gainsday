import CloudKit
import Foundation
import SwiftData
import SyncCore
import Testing
@testable import Gainsday

@Suite("SwiftData ledger")
struct SwiftDataLedgerTests {
    let container: ModelContainer
    let ledger: SwiftDataLedger

    init() throws {
        container = try SwiftDataLedger.makeContainer(inMemory: true)
        ledger = SwiftDataLedger(modelContainer: container)
    }

    static func entry(workoutID: UUID = UUID(), memberIDs: Set<UUID> = [], start: Date, minutes: Double = 30) -> LedgerEntry {
        LedgerEntry(
            workoutID: workoutID,
            memberIDs: memberIDs,
            workoutStart: start,
            workoutEnd: start.addingTimeInterval(minutes * 60),
            state: .owned,
            eventExternalIdentifier: "event-1",
            calendarID: "workouts",
            writtenFingerprint: EventContent(title: "🏃 Running", start: start, end: start.addingTimeInterval(minutes * 60), notes: "Notes").fingerprint,
            createdAt: start,
            updatedAt: start,
            activityType: .running
        )
    }

    @Test("An entry comes back exactly as it was saved")
    func roundTrip() async throws {
        var entry = Self.entry(memberIDs: [UUID()], start: .now)
        entry.needsLinking = true
        entry.needsHealthFollowUp = true

        try await ledger.save(entry)

        #expect(try await ledger.entries(forWorkout: entry.workoutID) == [entry])
    }

    @Test("An entry is stored with a fingerprint of what the app wrote, never the event's text")
    func storesFingerprintOnly() async throws {
        let entry = Self.entry(start: .now)

        try await ledger.save(entry)

        let records = try ModelContext(container).fetch(FetchDescriptor<LedgerRecord>())
        #expect(records.map(\.written) == [nil])
        #expect(records.map(\.writtenFingerprint) == [entry.writtenFingerprint?.storageValue])
    }

    @Test("A record an earlier version stored with the event's text is read with its fingerprint, and the text is scrubbed on first use")
    func migratesAndScrubsLegacyRecord() async throws {
        let (legacy, content) = try Self.insertLegacyRecord(into: container)

        let entries = try await ledger.entries(forWorkout: legacy.workoutID)

        #expect(entries.map(\.writtenFingerprint) == [content.fingerprint])
        let records = try ModelContext(container).fetch(FetchDescriptor<LedgerRecord>())
        #expect(records.map(\.written) == [nil])
        #expect(records.map(\.writtenFingerprint) == [content.fingerprint.storageValue])
        #expect(records.map(\.updatedAt) == [legacy.updatedAt])
    }

    @Test("A legacy record iCloud brings in after first use is read with its fingerprint, and its text is scrubbed once the import finishes, without waiting for a relaunch")
    @MainActor func scrubsLateImportWhenImportFinishes() async throws {
        let monitor = CloudImportMonitor(
            defaults: UserDefaults(suiteName: "SwiftDataLedgerTests-\(UUID().uuidString)")!,
            center: NotificationCenter(),
            accountStatus: { .available }
        )
        let ledger = ledger
        monitor.afterEachImport = { await ledger.importFinished() }
        _ = try await ledger.entries(in: DateInterval(start: .distantPast, end: .distantFuture))
        let (legacy, content) = try Self.insertLegacyRecord(into: container)

        #expect(try await ledger.entry(withID: legacy.entryID)?.writtenFingerprint == content.fingerprint)
        await monitor.importFinished()

        let records = try ModelContext(container).fetch(FetchDescriptor<LedgerRecord>())
        #expect(records.map(\.written) == [nil])
        #expect(records.map(\.writtenFingerprint) == [content.fingerprint.storageValue])
        #expect(records.map(\.updatedAt) == [legacy.updatedAt])
    }

    /// A record as an earlier version wrote it: the event's content as JSON, and no fingerprint.
    static func insertLegacyRecord(into container: ModelContainer) throws -> (LedgerRecord, EventContent) {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let content = EventContent(title: "🏃 Running · 10.02 km", start: start, end: start.addingTimeInterval(1800), notes: "Avg heart rate: 152 bpm")
        let context = ModelContext(container)
        let record = LedgerRecord(entry(start: start))
        record.writtenFingerprint = nil
        record.written = try JSONEncoder().encode(content)
        context.insert(record)
        try context.save()
        return (record, content)
    }

    @Test("An entry is found by any member of its cluster")
    func findsByMember() async throws {
        let strava = UUID()
        let entry = Self.entry(memberIDs: [strava], start: .now)
        try await ledger.save(entry)

        #expect(try await ledger.entries(forWorkout: strava).map(\.id) == [entry.id])
        #expect(try await ledger.entries(forWorkout: UUID()).isEmpty)
    }

    @Test("Only entries waiting for full access to link their event or apply a Health change are listed as needing linking")
    func findsEntriesNeedingLinking() async throws {
        var pending = Self.entry(start: .now)
        pending.needsLinking = true
        var followUp = Self.entry(start: .now)
        followUp.needsHealthFollowUp = true
        try await ledger.save(pending)
        try await ledger.save(followUp)
        try await ledger.save(Self.entry(start: .now))

        #expect(Set(try await ledger.entriesNeedingLinking()) == [pending, followUp])
    }

    @Test("Saving an entry with the same id replaces it")
    func saveReplaces() async throws {
        var entry = Self.entry(start: .now)
        try await ledger.save(entry)

        entry.state = .tombstoned
        try await ledger.save(entry)

        #expect(try await ledger.entries(forWorkout: entry.workoutID).map(\.state) == [.tombstoned])
    }

    @Test("An entry that failed to save isn't returned later, so a retry doesn't take the workout as synced")
    func failedSaveIsRolledBack() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ledger-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try ModelContainer(for: LedgerRecord.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let readOnly = ModelConfiguration(url: url, allowsSave: false, cloudKitDatabase: .none)
        let ledger = SwiftDataLedger(modelContainer: try ModelContainer(for: LedgerRecord.self, configurations: readOnly))
        let entry = Self.entry(start: .now)

        await #expect(throws: (any Error).self) { try await ledger.save(entry) }

        #expect(try await ledger.entries(forWorkout: entry.workoutID).isEmpty)
        #expect(try await ledger.entries(in: DateInterval(start: .distantPast, end: .distantFuture)).isEmpty)
    }

    @Test("Entries are found by overlapping time, and can be deleted")
    func timeRangeAndDelete() async throws {
        let morning = Date(timeIntervalSince1970: 1_790_000_000)
        let early = Self.entry(start: morning)
        let late = Self.entry(start: morning.addingTimeInterval(4 * 60 * 60))
        try await ledger.save(early)
        try await ledger.save(late)

        let firstHour = DateInterval(start: morning, duration: 60 * 60)
        #expect(try await ledger.entries(in: firstHour).map(\.id) == [early.id])

        try await ledger.delete(entryID: early.id)
        #expect(try await ledger.entries(in: firstHour).isEmpty)
    }
}
