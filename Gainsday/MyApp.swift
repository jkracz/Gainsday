import SwiftData
import SwiftUI

@main struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: SyncCoordinator

    init() {
        // Listen for the ledger's first iCloud import before the container starts CloudKit.
        let cloudImport = CloudImportMonitor()
        let container: ModelContainer
        do {
            container = try SwiftDataLedger.makeContainer()
        } catch {
            // Syncing without the ledger would create duplicates, so don't run at all.
            fatalError("Couldn't open the ledger: \(error)")
        }
        let ledger = SwiftDataLedger(modelContainer: container)
        // Records from earlier versions can arrive with any import, so scrub after each.
        cloudImport.afterEachImport = { await ledger.importFinished() }
        let coordinator = SyncCoordinator(ledger: ledger, cloudImport: cloudImport)
        coordinator.startBackgroundSync()
        _coordinator = State(initialValue: coordinator)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .task { await coordinator.load() }
                .task { await coordinator.watchCloudSettings() }
                #if DEBUG
                .task { await DemoSeeder.runIfRequested() }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            // Catch up on every app open.
            if phase == .active {
                Task { await coordinator.sync() }
            } else if phase == .background {
                coordinator.scheduleAppRefresh()
            }
        }
        .backgroundTask(.appRefresh(SyncCoordinator.appRefreshTaskID)) {
            await coordinator.refreshInBackground()
        }
    }
}
