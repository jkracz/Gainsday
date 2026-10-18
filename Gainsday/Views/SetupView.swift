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
                    .disabled(healthRequested)
                } header: {
                    Text("Health")
                } footer: {
                    Text("Gainsday reads your workouts. It never writes to Health.")
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
                    Button("Start Syncing") {
                        Task { await startSyncing() }
                    }
                    .disabled(!healthRequested || selectedCalendar == nil || isStarting)
                } footer: {
                    Text("Workouts you start from now on are added. Earlier workouts are left out.")
                }

                if let errorMessage {
                    Section {
                        Text(verbatim: errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Set Up Gainsday")
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
            let writable = try await coordinator.calendar.writableCalendars()
            calendars = writable
            // Preselect the calendar restored from iCloud after a reinstall.
            if let restored = coordinator.settings.destinationCalendar {
                selectedCalendarID = writable.first { $0.id == restored.id }?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startSyncing() async {
        guard let selectedCalendar else { return }
        isStarting = true
        await coordinator.finishSetup(destination: selectedCalendar)
        isStarting = false
    }
}
