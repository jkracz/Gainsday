import SwiftUI
import SyncCore

/// The last step: which workout types to add, whether to add the past week, then Start Syncing.
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
            @Bindable var model = model
            Section {
                if let calendar = model.selectedCalendar {
                    LabeledContent("Calendar") {
                        Text(verbatim: calendar.title)
                    }
                }
                WorkoutTypesLink()
            }

            Section {
                Toggle("Add the Past 7 Days", isOn: $model.addsPastWeek)
            } footer: {
                if let restored = coordinator.settings.syncStartDate {
                    Text("Workouts you started since \(restored, format: .dateTime.day().month().year()) are added, as before.")
                } else if model.addsPastWeek {
                    Text("Your workouts from the past 7 days are added too, so your calendar isn't empty. You can add others later.")
                } else {
                    Text("Workouts you start from now on are added. Earlier workouts are left out.")
                }
            }
        }
    }
}
