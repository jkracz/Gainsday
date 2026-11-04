import SwiftUI

struct ContentView: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        if !coordinator.hasLoaded {
            ProgressView()
        } else if coordinator.isSetUp {
            HomeView()
        } else {
            SetupView()
        }
    }
}
