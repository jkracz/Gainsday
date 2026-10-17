import SwiftData
import SwiftUI

@main struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: SyncCoordinator

    init() {
        let container: ModelContainer
        do {
            container = try SwiftDataLedger.makeContainer()
        } catch {
            // Syncing without the ledger would create duplicates, so don't run at all.
            fatalError("Couldn't open the ledger: \(error)")
        }
        _coordinator = State(initialValue: SyncCoordinator(ledger: SwiftDataLedger(modelContainer: container)))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .task { await coordinator.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Catch up on every app open.
            if phase == .active {
                Task { await coordinator.sync() }
            }
        }
    }
}
