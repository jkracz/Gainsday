import Foundation
import SyncCore
import Testing
@testable import Gainsday

/// Issue #26: SwiftData's `@ModelActor` runs its work on whichever thread calls it,
/// so a main-actor caller would put ledger fetches and saves on the main thread.
@MainActor @Suite("SwiftData ledger threading")
struct SwiftDataLedgerThreadingTests {
    @Test("Ledger work stays off the main thread when the app creates and calls it on main")
    func offMainFromMainActor() async throws {
        // MyApp creates the ledger on the main thread.
        let ledger = SwiftDataLedger(modelContainer: try SwiftDataLedger.makeContainer(inMemory: true))

        #expect(await ledger.isOnMainThread() == false)
        try await ledger.save(SwiftDataLedgerTests.entry(start: .now))
        #expect(await ledger.isOnMainThread() == false)
    }
}
