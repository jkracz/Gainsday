import SwiftUI
import SyncCore

/// Every setting on one screen, each row saying its current value. Explanations live
/// on the screens the rows open. Every setting is backed up to iCloud, so a reinstall
/// restores it.
struct SettingsView: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        Form {
            Section("Calendar") {
                SettingsRow(title: "Calendar", systemImage: "calendar", color: Color(.danger)) {
                    Text(verbatim: coordinator.settings.destinationCalendar?.displayTitle ?? "")
                }
                SettingsLink(title: "Access", systemImage: "lock.fill", color: Color(.workoutOther), value: Text(accessName)) {
                    CalendarAccessView()
                }
            }

            Section("What Syncs") {
                SettingsLink(title: "Workout Types", systemImage: "bolt.fill", color: Color(.workoutRun), value: Text(typesSummary)) {
                    WorkoutTypesView()
                }
                SettingsLink(title: "Apps", systemImage: "square.grid.2x2.fill", color: Color(.workoutSwim), value: Text(sourcesSummary)) {
                    SourcesView()
                }
                SettingsRow(title: "Shortest Workout", systemImage: "clock.fill", color: Color(.workoutOther)) {
                    Picker("Shortest Workout", selection: minimumDuration) {
                        ForEach(durationChoices, id: \.self) { seconds in
                            Text(Self.label(forMinimum: seconds)).tag(seconds)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(Color(.inkSecondary))
                }
            }

            Section("Events") {
                SettingsLink(title: "Event Template", systemImage: "textformat", color: Color(.workoutCycle), value: Text(templateSummary)) {
                    TemplateEditorView()
                }
                SettingsLink(title: "Planned Events", systemImage: "checkmark", color: Color(.workoutStrength), value: Text(matchingSummary)) {
                    MatchingSettingsView()
                }
            }

            Section {
                SettingsLink(title: "Add Past Workouts", systemImage: "plus", color: Color(.workoutCycle), value: nil) {
                    BackfillView()
                }
                SettingsLink(title: "Privacy & About", systemImage: "info", color: Color(.workoutOther), value: nil) {
                    AboutView()
                }
            } footer: {
                Text("Settings back up to your iCloud.")
                    .frame(maxWidth: .infinity)
            }
        }
        .canvasBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var accessName: LocalizedStringResource {
        switch coordinator.calendarAccess {
        case .full: "Full"
        case .addOnly: "Add Only"
        case .none: "None"
        }
    }

    private var typesSummary: LocalizedStringResource {
        let count = coordinator.settings.enabledTypes.count
        return count == 0 ? "None" : "\(count) on"
    }

    private var sourcesSummary: LocalizedStringResource {
        guard let allowlist = coordinator.settings.sourceAllowlist else { return "All Apps" }
        return allowlist.isEmpty ? "None" : "\(allowlist.count) on"
    }

    private var templateSummary: LocalizedStringResource {
        guard let starter = StarterTemplate.allCases.first(where: { $0.template == coordinator.settings.template }) else {
            return coordinator.settings.template == .default ? "Default" : "Custom"
        }
        return starter.displayName
    }

    private var matchingSummary: LocalizedStringResource {
        guard coordinator.hasFullCalendarAccess, coordinator.settings.matchingEnabled else { return "Off" }
        switch coordinator.settings.matchMode {
        case .updatePlannedEvent: return "Update"
        case .createSeparateEvent: return "Separate"
        }
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
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// A settings row: a coloured tile, a title and whatever sits on the right.
private struct SettingsRow<Trailing: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: systemImage, color: color)
            Text(title)
                .foregroundStyle(Color(.ink))
            Spacer()
            trailing
                .foregroundStyle(Color(.inkSecondary))
        }
        .listRowBackground(Color(.card))
    }
}

/// A settings row that opens another screen, with the setting's value beside the chevron.
private struct SettingsLink<Destination: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color
    let value: Text?
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingsRow(title: title, systemImage: systemImage, color: color) {
                value
            }
        }
        .listRowBackground(Color(.card))
    }
}

/// How much calendar access Gainsday has, and what it allows.
private struct CalendarAccessView: View {
    var body: some View {
        Form {
            CalendarAccessSection()
        }
        .canvasBackground()
        .navigationTitle("Calendar Access")
    }
}

/// What Gainsday reads, writes and keeps, and that nothing else leaves the phone.
private struct AboutView: View {
    var body: some View {
        Form {
            Section {
                Label("Reads your workouts from Health, and never writes to it.", systemImage: "heart.fill")
                Label("Adds one event per workout to the calendar you chose, and only changes events it added or you matched.", systemImage: "calendar")
                Label("No server, no account and no analytics. Everything happens on this iPhone.", systemImage: "lock.fill")
                Label("Your settings, and the list of events it added, are backed up to your own iCloud.", systemImage: "icloud.fill")
            }
            .listRowBackground(Color(.card))

            Section {
                Link(destination: URL(string: "https://github.com/jkracz/Gainsday")!) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            } footer: {
                Text("Gainsday is open source, so you can check this for yourself.")
            }
            .listRowBackground(Color(.card))
        }
        .canvasBackground()
        .navigationTitle("Privacy & About")
    }
}
