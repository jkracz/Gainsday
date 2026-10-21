import SwiftUI
import SyncCore

/// One-time setup on each install: what Gainsday does, then Health access, a
/// destination calendar and Start Syncing. The steps are listed in `SetupStep`.
struct SetupView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @State private var model = SetupModel()

    var body: some View {
        NavigationStack(path: $model.path) {
            screen(for: .welcome)
                .navigationDestination(for: SetupStep.self) { step in
                    screen(for: step)
                }
        }
        .environment(model)
        .task {
            // Keep the list current if the user adds or removes a calendar elsewhere.
            for await _ in coordinator.calendar.changes() where model.calendars != nil && !model.isAddOnly {
                await model.refreshCalendars(coordinator)
            }
        }
        .onChange(of: coordinator.settings.destinationCalendar) {
            // Settings restored from iCloud can arrive after the list has loaded.
            if model.selectedCalendar == nil { model.selectRestoredCalendar(coordinator) }
        }
    }

    @ViewBuilder
    private func screen(for step: SetupStep) -> some View {
        switch step {
        case .welcome: WelcomeStep()
        case .health: HealthStep()
        case .calendar: CalendarStep()
        case .start: StartStep()
        }
    }
}
