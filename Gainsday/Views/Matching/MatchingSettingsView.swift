import SwiftUI
import SyncCore

/// How workouts are matched to events the user planned. Matching reads the user's
/// calendars, so with add-only access everything here is greyed out. [v1.1]
struct MatchingSettingsView: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        Form {
            Section {
                RequiresFullAccess {
                    Toggle("Match Planned Workouts", isOn: matchingEnabled)
                }
            } footer: {
                Text("When a workout matches an event you planned, such as \"Run with Sam\", Gainsday uses that event instead of adding another.")
            }

            // With add-only access every setting stays in view, greyed out, so the user
            // can see what full access would allow.
            if !hasFullAccess || coordinator.settings.matchingEnabled {
                if hasFullAccess {
                    matchingDetails
                } else {
                    matchingDetails
                        .disabled(true)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Planned Workouts")
    }

    /// What happens on a match and how plans are found.
    @ViewBuilder
    private var matchingDetails: some View {
        Section {
            Picker("When a Workout Matches", selection: matchMode) {
                Text("Update Planned Event").tag(MatchMode.updatePlannedEvent)
                Text("Create Separate Event").tag(MatchMode.createSeparateEvent)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if updatesPlans {
                Toggle("Also Rename", isOn: renameMatchedEvents)
            }
        } header: {
            Text("When a Workout Matches")
        } footer: {
            Text(modeFooter)
        }

        // Separate events never look for a plan, so nothing is ever unclear either.
        if updatesPlans {
            Section {
                SearchCalendarsLink()
                Picker("Time Window", selection: matchWindow) {
                    ForEach(windowChoices, id: \.self) { seconds in
                        Text(Self.label(forWindow: seconds)).tag(seconds)
                    }
                }
                MatchKeywordsLink()
            } header: {
                Text("Finding Plans")
            } footer: {
                Text("A plan that doesn't overlap the workout must start within the time window of it, on the same day.")
            }

            UnclearMatchSettingsSection()
        }
    }

    private var hasFullAccess: Bool {
        coordinator.hasFullCalendarAccess
    }

    private var updatesPlans: Bool {
        coordinator.settings.matchMode == .updatePlannedEvent
    }

    private var modeFooter: LocalizedStringKey {
        switch coordinator.settings.matchMode {
        case .updatePlannedEvent:
            "The planned event moves to the workout's times and gains its details. Its title stays yours unless Also Rename is on."
        case .createSeparateEvent:
            "Planned events are never changed. The workout is added as its own event."
        }
    }

    private var matchingEnabled: Binding<Bool> {
        Binding {
            coordinator.settings.matchingEnabled
        } set: { isOn in
            setMatchingEnabled(isOn)
        }
    }

    /// Turns matching on or off. #21 hooks in here to show its opt-in explanation the
    /// first time matching is turned on.
    private func setMatchingEnabled(_ isOn: Bool) {
        coordinator.updateSettings { $0.matchingEnabled = isOn }
    }

    private var matchMode: Binding<MatchMode> {
        Binding {
            coordinator.settings.matchMode
        } set: { mode in
            coordinator.updateSettings { $0.matchMode = mode }
        }
    }

    private var renameMatchedEvents: Binding<Bool> {
        Binding {
            coordinator.settings.renameMatchedEvents
        } set: { isOn in
            coordinator.updateSettings { $0.renameMatchedEvents = isOn }
        }
    }

    private var matchWindow: Binding<TimeInterval> {
        Binding {
            coordinator.settings.matchWindow
        } set: { seconds in
            coordinator.updateSettings { $0.matchWindow = seconds }
        }
    }

    /// The offered windows, keeping a restored value that isn't one of them.
    private var windowChoices: [TimeInterval] {
        let minutes: [TimeInterval] = [15, 30, 45, 60, 90, 120, 180]
        return Set(minutes.map { $0 * 60 } + [coordinator.settings.matchWindow]).sorted()
    }

    private static func label(forWindow seconds: TimeInterval) -> String {
        let duration = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return String(localized: "± \(duration)")
    }
}

/// A row in Settings that opens the matching settings and says whether matching is on.
struct MatchingSettingsLink: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        NavigationLink {
            MatchingSettingsView()
        } label: {
            LabeledContent("Planned Workouts", value: summary)
        }
    }

    private var summary: String {
        guard coordinator.hasFullCalendarAccess, coordinator.settings.matchingEnabled else { return String(localized: "Off") }
        switch coordinator.settings.matchMode {
        case .updatePlannedEvent: return String(localized: "Update")
        case .createSeparateEvent: return String(localized: "Separate")
        }
    }
}
