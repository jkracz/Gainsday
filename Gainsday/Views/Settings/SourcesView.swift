import SwiftUI
import SyncCore

/// Chooses which apps' workouts are synced. By default every app is, and copies of
/// one workout recorded by several apps become one event.
struct SourcesView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @State private var recentSources: [WorkoutSourceApp] = []

    var body: some View {
        List {
            Section {
                Toggle("Every App", isOn: allowsEveryApp)
            } footer: {
                Text("When several apps record the same workout, it's added once, using the Apple Watch's copy if there is one.")
            }
            if coordinator.settings.sourceAllowlist != nil {
                Section {
                    if sources.isEmpty {
                        Text("No workouts in Health yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sources, id: \.bundleIdentifier) { source in
                        Toggle(source.name, isOn: isAllowed(source))
                    }
                } header: {
                    Text("Apps")
                } footer: {
                    Text("Only workouts from the apps you turn on are added.")
                }
            }
        }
        .navigationTitle("Sources")
        .task {
            let workouts = (try? await coordinator.health.recentWorkouts(limit: 200)) ?? []
            recentSources = workouts.map(\.source)
        }
    }

    /// Apps seen in recent workouts, plus any allowed app that hasn't recorded one lately, by name.
    private var sources: [WorkoutSourceApp] {
        var byID: [String: WorkoutSourceApp] = [:]
        for source in recentSources where byID[source.bundleIdentifier] == nil {
            byID[source.bundleIdentifier] = source
        }
        for id in coordinator.settings.sourceAllowlist ?? [] where byID[id] == nil {
            byID[id] = WorkoutSourceApp(bundleIdentifier: id, name: id)
        }
        return byID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var allowsEveryApp: Binding<Bool> {
        Binding {
            coordinator.settings.sourceAllowlist == nil
        } set: { isOn in
            // Start a new list with every app on, so nothing changes until the user turns one off.
            let everyApp = Set(sources.map(\.bundleIdentifier))
            coordinator.updateSettings { $0.sourceAllowlist = isOn ? nil : everyApp }
        }
    }

    private func isAllowed(_ source: WorkoutSourceApp) -> Binding<Bool> {
        Binding {
            coordinator.settings.sourceAllowlist?.contains(source.bundleIdentifier) ?? true
        } set: { isOn in
            coordinator.updateSettings { settings in
                if isOn {
                    settings.sourceAllowlist?.insert(source.bundleIdentifier)
                } else {
                    settings.sourceAllowlist?.remove(source.bundleIdentifier)
                }
            }
        }
    }
}

/// A row that opens the source list and says how many apps are allowed.
struct SourcesLink: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        NavigationLink {
            SourcesView()
        } label: {
            LabeledContent("Sources", value: summary)
        }
    }

    private var summary: String {
        guard let allowlist = coordinator.settings.sourceAllowlist else { return String(localized: "Every App") }
        return allowlist.isEmpty ? String(localized: "None") : String(localized: "\(allowlist.count) on")
    }
}
