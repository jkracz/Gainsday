import SwiftUI
import SyncCore

/// Where workouts are going, and how the last sync went.
struct StatusView: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Calendar", value: coordinator.settings.destinationCalendar?.displayTitle ?? "")
                    if let syncStartDate = coordinator.settings.syncStartDate {
                        LabeledContent("Workouts Since") {
                            Text(syncStartDate, format: .dateTime.day().month().hour().minute())
                        }
                    }
                } footer: {
                    SyncTimingFooter()
                }

                Section {
                    TemplateEditorLink()
                    NavigationLink("Add Past Workouts") { BackfillView() }
                    NavigationLink("Activity") {
                        ActivityLogView()
                    }
                }

                if !coordinator.hasFullCalendarAccess {
                    CalendarAccessSection()
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
                    }
                    if coordinator.isWaitingForICloudImport, let waiting = WaitingForICloudImport().errorDescription {
                        Text(verbatim: waiting)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Added Today", value: coordinator.activityLog.addedEventCount(on: coordinator.clock.now, in: coordinator.clock.calendar), format: .number)
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
