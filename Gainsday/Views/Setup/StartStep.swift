import SwiftUI
import SyncCore

/// The last step: which workout types to add, then Start Syncing.
struct StartStep: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(SetupModel.self) private var model

    var body: some View {
        SetupStepLayout(
            title: "Ready to Sync",
            systemImage: "checkmark.circle.fill",
            message: "Choose which workouts to add. You can change this later in Settings.",
            buttonTitle: "Start Syncing",
            buttonDisabled: model.selectedCalendar == nil || coordinator.settings.enabledTypes.isEmpty || model.isStarting,
            action: { await model.startSyncing(coordinator) }
        ) {
            Section {
                if let calendar = model.selectedCalendar {
                    LabeledContent("Calendar") {
                        Text(verbatim: calendar.title)
                    }
                }
                WorkoutTypesLink()
            } footer: {
                if let restored = coordinator.settings.syncStartDate {
                    Text("Workouts you started since \(restored, format: .dateTime.day().month().year()) are added, as before.")
                } else {
                    Text("Workouts you start from now on are added. Earlier workouts are left out.")
                }
            }
        }
    }
}
