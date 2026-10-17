import Foundation
import SyncCore
import Testing

@Suite("Domain")
struct DomainTests {
    @Test("The short id is the first 8 hex characters of the workout UUID, lowercased")
    func shortID() throws {
        let id = try #require(UUID(uuidString: "A1B2C3D4-E5F6-4789-8ABC-DEF012345678"))

        #expect(id.shortID == "a1b2c3d4")
    }

    @Test("A per-type template override wins over the global template")
    func templateResolution() {
        let runner = EventTemplate(title: "{type} · {pace}", notes: "")
        let settings = Settings(templateOverrides: [.running: runner])

        #expect(settings.template(for: .running) == runner)
        #expect(settings.template(for: .cycling) == .default)
    }

    @Test("A ledger entry covers its cluster identity and every member")
    func ledgerEntryCoversMembers() {
        let watch = UUID()
        let strava = UUID()
        let entry = LedgerEntry(
            workoutID: watch,
            memberIDs: [strava],
            workoutStart: .distantPast,
            workoutEnd: .distantPast,
            state: .owned,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )

        #expect(entry.covers(watch))
        #expect(entry.covers(strava))
        #expect(!entry.covers(UUID()))
    }

    @Test("A ledger entry covers its cluster identity even when memberIDs lacks it")
    func ledgerEntryCoversClusterWithoutMembers() {
        let watch = UUID()
        var entry = LedgerEntry(
            workoutID: watch,
            workoutStart: .distantPast,
            workoutEnd: .distantPast,
            state: .owned,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
        entry.memberIDs = []

        #expect(entry.covers(watch))
    }
}
