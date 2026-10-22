import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Matching by hand keeps the user's edits")
struct ManualMatchEditTests {
    @Test("Matching by hand refuses when the user edited the separate event, and lets go of it")
    func editedSeparateEventIsReleased() async throws {
        let workout = SyncHarness.run(from: (10, 10), to: (11, 5))
        let (harness, created, separate) = try await SyncHarness.withSeparateEvent(for: [workout])
        var edited = separate
        edited.content.notes = (edited.content.notes ?? "") + "\nLegs felt heavy"
        await harness.calendar.put(edited)
        let planned = SyncHarness.planned("Run", from: (10, 0), to: (11, 0), notes: "Bring gels")
        await harness.calendar.put(planned)

        await #expect(throws: ManualMatchError.eventEditedByUser) {
            try await harness.engine.match(entryID: created.id, toEventID: planned.id)
        }

        #expect(Set(await harness.calendar.allEvents) == [edited, planned])
        #expect(await harness.ledger.allEntries.map(\.state) == [.released])
        let log = await harness.activityLog.entries
        #expect(log.map(\.id) == [created.id])
        #expect(log[0].canMatchToEvent == false)
        #expect(log[0].canUndo == false)
    }
}
