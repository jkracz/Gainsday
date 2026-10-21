import SwiftUI
import SyncCore

/// Chooses the calendars searched for planned events. Calendars that aren't selected
/// are never read. With none picked, the destination and default calendars are. [v1.1]
struct SearchCalendarsView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @State private var calendars: [CalendarInfo] = []
    @State private var defaultID: String?

    var body: some View {
        List {
            Section {
                ForEach(calendars) { calendar in
                    Button {
                        toggle(calendar)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(verbatim: calendar.title)
                                if let role = role(of: calendar) {
                                    Text(role)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selectedIDs.contains(calendar.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("Selected")
                            }
                        }
                        .contentShape(.rect)
                    }
                    .foregroundStyle(.primary)
                }
            } footer: {
                Text("Calendars you don't select are never read. With none selected, Gainsday searches your destination and default calendars.")
            }
            if isPicked {
                Section {
                    Button("Use Destination and Default Calendars") {
                        coordinator.updateSettings { $0.searchCalendars = nil }
                    }
                }
            }
        }
        .navigationTitle("Search Calendars")
        .task {
            calendars = (try? await coordinator.calendar.writableCalendars()) ?? []
            defaultID = await coordinator.calendar.defaultCalendarID()
        }
    }

    private var isPicked: Bool {
        !(coordinator.settings.searchCalendars ?? []).isEmpty
    }

    /// The calendars searched now: the user's pick, or the destination and default calendars.
    private var selectedIDs: Set<String> {
        if isPicked {
            return Set(coordinator.settings.searchCalendars?.map(\.id) ?? [])
        }
        return Set([coordinator.settings.destinationCalendar?.id, defaultID].compactMap(\.self))
    }

    private func role(of calendar: CalendarInfo) -> String? {
        if calendar.id == coordinator.settings.destinationCalendar?.id {
            return String(localized: "Destination")
        }
        return calendar.id == defaultID ? String(localized: "Default") : nil
    }

    /// Starts from what's searched now, so picking one calendar doesn't silently drop the
    /// defaults. Deselecting the last one goes back to the defaults.
    private func toggle(_ calendar: CalendarInfo) {
        var picked = isPicked
            ? coordinator.settings.searchCalendars ?? []
            : calendars.filter { selectedIDs.contains($0.id) }.map(Self.reference)
        if picked.contains(where: { $0.id == calendar.id }) {
            picked.removeAll { $0.id == calendar.id }
        } else {
            picked.append(Self.reference(calendar))
        }
        let searched = picked.isEmpty ? nil : picked
        coordinator.updateSettings { $0.searchCalendars = searched }
    }

    private static func reference(_ calendar: CalendarInfo) -> CalendarReference {
        CalendarReference(id: calendar.id, title: calendar.title)
    }
}

/// A row that opens the search calendar list and says which are searched.
struct SearchCalendarsLink: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        NavigationLink {
            SearchCalendarsView()
        } label: {
            LabeledContent("Search Calendars", value: summary)
        }
    }

    private var summary: String {
        let picked = coordinator.settings.searchCalendars ?? []
        return picked.isEmpty ? String(localized: "Automatic") : String(localized: "\(picked.count) selected")
    }
}
