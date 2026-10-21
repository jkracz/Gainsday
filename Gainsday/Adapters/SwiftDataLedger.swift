import Foundation
import SwiftData
import SyncCore

/// One ledger entry as stored by SwiftData and synced to the user's private iCloud.
///
/// CloudKit needs every property to be optional or have a default, and allows no
/// unique constraints, so the same workout can end up with several records.
@Model
nonisolated final class LedgerRecord {
    var entryID: UUID = UUID()
    var workoutID: UUID = UUID()
    /// Member UUID strings separated by commas, so a predicate can search them.
    var memberIDs: String = ""
    var workoutStart: Date = Date.distantPast
    var workoutEnd: Date = Date.distantPast
    var state: String = LedgerEntry.State.owned.rawValue
    var eventExternalIdentifier: String?
    var calendarID: String?
    /// JSON-encoded `EventContent`.
    var written: Data?
    /// JSON-encoded `EventContent`.
    var preUpdate: Data?
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast
    /// The `WorkoutActivityType` raw value.
    var activityType: Int?
    var needsLinking: Bool = false

    init(_ entry: LedgerEntry) {
        update(from: entry)
    }

    func update(from entry: LedgerEntry) {
        entryID = entry.id
        workoutID = entry.workoutID
        memberIDs = entry.memberIDs.map(\.uuidString).sorted().joined(separator: ",")
        workoutStart = entry.workoutStart
        workoutEnd = entry.workoutEnd
        state = entry.state.rawValue
        eventExternalIdentifier = entry.eventExternalIdentifier
        calendarID = entry.calendarID
        written = entry.written.flatMap { try? JSONEncoder().encode($0) }
        preUpdate = entry.preUpdate.flatMap { try? JSONEncoder().encode($0) }
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
        activityType = entry.activityType.map { Int($0.rawValue) }
        needsLinking = entry.needsLinking
    }

    var entry: LedgerEntry {
        LedgerEntry(
            id: entryID,
            workoutID: workoutID,
            memberIDs: Set(memberIDs.split(separator: ",").compactMap { UUID(uuidString: String($0)) }),
            workoutStart: workoutStart,
            workoutEnd: workoutEnd,
            // An unknown state comes from a newer app version; leaving the workout alone is safest.
            state: LedgerEntry.State(rawValue: state) ?? .released,
            eventExternalIdentifier: eventExternalIdentifier,
            calendarID: calendarID,
            written: written.flatMap { try? JSONDecoder().decode(EventContent.self, from: $0) },
            preUpdate: preUpdate.flatMap { try? JSONDecoder().decode(EventContent.self, from: $0) },
            createdAt: createdAt,
            updatedAt: updatedAt,
            activityType: activityType.flatMap { UInt(exactly: $0) }.map(WorkoutActivityType.init(rawValue:)),
            needsLinking: needsLinking
        )
    }
}

/// The ledger, stored with SwiftData in the user's private iCloud database.
@ModelActor
actor SwiftDataLedger: Ledger {
    /// The iCloud-backed container, using the first iCloud container in the entitlements.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration(cloudKitDatabase: .automatic)
        return try ModelContainer(for: LedgerRecord.self, configurations: configuration)
    }

    func entries(forWorkout workoutID: UUID) async throws -> [LedgerEntry] {
        let memberID = workoutID.uuidString
        let descriptor = FetchDescriptor<LedgerRecord>(
            predicate: #Predicate { $0.workoutID == workoutID || $0.memberIDs.contains(memberID) }
        )
        return try modelContext.fetch(descriptor).map(\.entry).filter { $0.covers(workoutID) }
    }

    func entries(in interval: DateInterval) async throws -> [LedgerEntry] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<LedgerRecord>(
            predicate: #Predicate { $0.workoutStart < end && $0.workoutEnd > start }
        )
        return try modelContext.fetch(descriptor).map(\.entry)
    }

    func entriesNeedingLinking() async throws -> [LedgerEntry] {
        let descriptor = FetchDescriptor<LedgerRecord>(predicate: #Predicate { $0.needsLinking })
        return try modelContext.fetch(descriptor).map(\.entry)
    }

    func save(_ entry: LedgerEntry) async throws {
        if let record = try record(withID: entry.id) {
            record.update(from: entry)
        } else {
            modelContext.insert(LedgerRecord(entry))
        }
        try modelContext.save()
    }

    func delete(entryID: UUID) async throws {
        guard let record = try record(withID: entryID) else { return }
        modelContext.delete(record)
        try modelContext.save()
    }

    private func record(withID entryID: UUID) throws -> LedgerRecord? {
        var descriptor = FetchDescriptor<LedgerRecord>(predicate: #Predicate { $0.entryID == entryID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
