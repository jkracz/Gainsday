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

    private var types: [WorkoutActivityType] {
        WorkoutActivityType.listed(enabled: coordinator.settings.enabledTypes)
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

extension WorkoutActivityType {
    /// Keeps enabled types unknown to this version after the named types and Other.
    static func listed(enabled: Set<WorkoutActivityType>) -> [WorkoutActivityType] {
        let named = known.filter { $0 != .other }.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        let unnamed = enabled.subtracting(known)
        return named + [.other] + unnamed.sorted { $0.rawValue < $1.rawValue }
    }
}
