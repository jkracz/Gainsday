import Foundation
import SyncCore
import Testing
@testable import Gainsday

@Suite("SwiftData ledger")
struct SwiftDataLedgerTests {
    let ledger: SwiftDataLedger

    init() throws {
        ledger = SwiftDataLedger(modelContainer: try SwiftDataLedger.makeContainer(inMemory: true))
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
            written: EventContent(title: "🏃 Running", start: start, end: start.addingTimeInterval(minutes * 60), notes: "Notes"),
            createdAt: start,
            updatedAt: start,
            activityType: .running
        )
    }

    @Test("An entry comes back exactly as it was saved")
    func roundTrip() async throws {
        let entry = Self.entry(memberIDs: [UUID()], start: .now)

        try await ledger.save(entry)

        #expect(try await ledger.entries(forWorkout: entry.workoutID) == [entry])
    }

    @Test("An entry is found by any member of its cluster")
    func findsByMember() async throws {
        let strava = UUID()
        let entry = Self.entry(memberIDs: [strava], start: .now)
        try await ledger.save(entry)

        #expect(try await ledger.entries(forWorkout: strava).map(\.id) == [entry.id])
        #expect(try await ledger.entries(forWorkout: UUID()).isEmpty)
    }

    @Test("Saving an entry with the same id replaces it")
    func saveReplaces() async throws {
        var entry = Self.entry(start: .now)
        try await ledger.save(entry)

        entry.state = .tombstoned
        try await ledger.save(entry)

        #expect(try await ledger.entries(forWorkout: entry.workoutID).map(\.state) == [.tombstoned])
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
