import SwiftUI
import SyncCore

/// One-time setup: grant Health access, pick a destination calendar, start syncing.
struct SetupView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @State private var healthRequested = false
    @State private var calendars: [CalendarInfo]?
    @State private var selectedCalendarID: String?
    @State private var calendarAccessDenied = false
    @State private var isStarting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Allow Health Access", systemImage: healthRequested ? "checkmark.circle.fill" : "heart") {
                        Task { await requestHealthAccess() }
                    }
                    .disabled(healthRequested || !coordinator.health.isHealthDataAvailable)
                } header: {
                    Text("Health")
                } footer: {
                    if !coordinator.health.isHealthDataAvailable {
                        Text("Health isn't available on this device, so Gainsday can't read your workouts.")
                    } else if healthRequested {
                        // HealthKit never says whether read access was granted.
                        Text("If workouts don't show up, open the Health app, tap your profile, then Apps, and check what Gainsday can read.")
                    } else {
                        Text("Gainsday reads your workouts. It never writes to Health.")
                    }
                }

                Section {
                    if let calendars {
                        Picker("Calendar", selection: $selectedCalendarID) {
                            Text("None").tag(String?.none)
                            ForEach(calendars) { calendar in
                                Text(verbatim: calendar.title).tag(Optional(calendar.id))
                            }
                        }
                    } else {
                        Button("Choose a Calendar", systemImage: "calendar") {
                            Task { await loadCalendars() }
                        }
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    if calendarAccessDenied {
                        Text("Turn on full calendar access for Gainsday in Settings, then try again.")
                    } else {
                        Text("Full access lets Gainsday see the events it already added, so it never adds a workout twice.")
                    }
                }

                Section {
                    WorkoutTypesLink()
                } footer: {
                    Text("You can change these later in Settings.")
                }

                Section {
                    Button("Start Syncing") {
                        Task { await startSyncing() }
                    }
                    .disabled(!healthRequested || selectedCalendar == nil || coordinator.settings.enabledTypes.isEmpty || isStarting)
                } footer: {
                    if let restored = coordinator.settings.syncStartDate {
                        Text("Workouts you started since \(restored, format: .dateTime.day().month().year()) are added, as before.")
                    } else {
                        Text("Workouts you start from now on are added. Earlier workouts are left out.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(verbatim: errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Set Up Gainsday")
            .task {
                // Keep the list current if the user adds or removes a calendar elsewhere.
                for await _ in coordinator.calendar.changes() where calendars != nil {
                    await refreshCalendars()
                }
            }
            .onChange(of: coordinator.settings.destinationCalendar) {
                // Settings restored from iCloud can arrive after the list has loaded.
                if selectedCalendar == nil { selectRestoredCalendar() }
            }
        }
    }

    private var selectedCalendar: CalendarInfo? {
        calendars?.first { $0.id == selectedCalendarID }
    }

    private func requestHealthAccess() async {
        do {
            try await coordinator.health.requestAuthorization()
            healthRequested = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadCalendars() async {
        do {
            calendarAccessDenied = !(try await coordinator.calendar.requestFullAccess())
            guard !calendarAccessDenied else { return }
            await refreshCalendars()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reloads the list, keeping the selection if that calendar still exists.
    private func refreshCalendars() async {
        do {
            calendars = try await coordinator.calendar.writableCalendars()
            if selectedCalendar == nil { selectRestoredCalendar() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Preselects the calendar restored from iCloud after a reinstall, if it's in the list.
    private func selectRestoredCalendar() {
        let restoredID = coordinator.settings.destinationCalendar?.id
        selectedCalendarID = calendars?.first { $0.id == restoredID }?.id
    }

    private func startSyncing() async {
        guard let selectedCalendar else { return }
        isStarting = true
        await coordinator.finishSetup(destination: selectedCalendar)
        isStarting = false
    }
}
