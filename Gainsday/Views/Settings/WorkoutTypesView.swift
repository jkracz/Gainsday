import SwiftUI
import SyncCore

/// Turns individual workout types on or off.
struct WorkoutTypesView: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        List {
            Section {
                ForEach(types, id: \.self) { type in
                    Toggle(type.displayName, isOn: isEnabled(type))
                }
            } footer: {
                Text("Turning a type on adds workouts you finish from now on.")
            }
        }
        .navigationTitle("Workout Types")
    }

    /// The known types, plus any enabled type this version doesn't name, sorted by name.
    private var types: [WorkoutActivityType] {
        let enabled = coordinator.settings.enabledTypes
        let extra = enabled.subtracting(WorkoutActivityType.known)
        return (WorkoutActivityType.known + extra).sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func isEnabled(_ type: WorkoutActivityType) -> Binding<Bool> {
        Binding {
            coordinator.settings.enabledTypes.contains(type)
        } set: { isOn in
            coordinator.updateSettings { settings in
                if isOn {
                    settings.enabledTypes.insert(type)
                } else {
                    settings.enabledTypes.remove(type)
                }
            }
        }
    }
}

/// A row that opens the workout type list and says how many are on.
struct WorkoutTypesLink: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        NavigationLink {
            WorkoutTypesView()
        } label: {
            LabeledContent("Workout Types", value: summary)
        }
    }

    private var summary: String {
        let count = coordinator.settings.enabledTypes.count
        return count == 0 ? String(localized: "None") : String(localized: "\(count) on")
    }
}
