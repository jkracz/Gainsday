import SwiftUI
import SyncCore

/// What syncs. Every setting is backed up to iCloud, so a reinstall restores it.
struct SettingsView: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        Form {
            Section {
                WorkoutTypesLink()
                SourcesLink()
                Picker("Minimum Duration", selection: minimumDuration) {
                    ForEach(durationChoices, id: \.self) { seconds in
                        Text(Self.label(forMinimum: seconds)).tag(seconds)
                    }
                }
            } header: {
                Text("Filters")
            } footer: {
                Text("Shorter workouts aren't added to your calendar.")
            }

            Section {
                TemplateEditorLink()
            } header: {
                Text("Events")
            }
        }
        .navigationTitle("Settings")
    }

    private var minimumDuration: Binding<TimeInterval> {
        Binding {
            coordinator.settings.minimumDuration
        } set: { seconds in
            coordinator.updateSettings { $0.minimumDuration = seconds }
        }
    }

    /// The offered minimums, keeping a restored value that isn't one of them.
    private var durationChoices: [TimeInterval] {
        let minutes: [TimeInterval] = [0, 5, 10, 15, 20, 30, 45, 60]
        return Set(minutes.map { $0 * 60 } + [coordinator.settings.minimumDuration]).sorted()
    }

    private static func label(forMinimum seconds: TimeInterval) -> String {
        guard seconds > 0 else { return String(localized: "No Minimum") }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}
