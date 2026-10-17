import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Sync engine")
struct SyncEngineTests {
    @Test("A pass with no Health changes writes nothing and returns the next anchor")
    func quietPass() async throws {
        let harness = SyncHarness()

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions.isEmpty)
        #expect(result.nextAnchor != nil)
        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await harness.ledger.allEntries.isEmpty)
    }

    @Test("A backfill preview writes nothing")
    func backfillPreviewWritesNothing() async throws {
        let harness = SyncHarness(workouts: [SyncHarness.run()])
        let lastWeek = DateInterval(start: SyncHarness.now.addingTimeInterval(-7 * 24 * 60 * 60), end: SyncHarness.now)

        let result = try await harness.engine.run(.backfill(lastWeek, .preview))

        #expect(result.nextAnchor == nil)
        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await harness.ledger.allEntries.isEmpty)
    }
}
