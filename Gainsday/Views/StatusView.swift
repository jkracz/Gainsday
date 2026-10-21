import SwiftUI
import SyncCore

/// Where workouts are going, and how the last sync went.
struct StatusView: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Calendar", value: coordinator.settings.destinationCalendar?.title ?? "")
                    if let syncStartDate = coordinator.settings.syncStartDate {
                        LabeledContent("Workouts Since") {
                            Text(syncStartDate, format: .dateTime.day().month().hour().minute())
                        }
                    }
                } footer: {
                    Text("Workouts you finish appear in this calendar when you open Gainsday.")
                }

                Section {
                    NavigationLink("Event Template") { TemplateEditorView() }
                }

                Section("Last Sync") {
                    if coordinator.isSyncing {
                        LabeledContent("Syncing…") {
                            ProgressView()
                        }
                    } else if let pass = coordinator.lastPass {
                        LabeledContent("Finished") {
                            Text(pass.finishedAt, format: .dateTime.hour().minute())
                        }
                        LabeledContent("New Events", value: pass.createdCount, format: .number)
                    }
                    if let error = coordinator.lastError {
                        Text(verbatim: error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .refreshable { await coordinator.sync() }
            .toolbar {
                NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
            }
            .navigationTitle("Gainsday")
        }
    }
}
