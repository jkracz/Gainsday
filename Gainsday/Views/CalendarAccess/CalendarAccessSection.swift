import SwiftUI
import SyncCore

/// How much calendar access Gainsday has, and what add-only access leaves out.
struct CalendarAccessSection: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        Section {
            LabeledContent("Calendar Access", value: accessName)
            RequiresFullAccess {
                Label("Update events when Health replaces a workout", systemImage: "arrow.triangle.2.circlepath")
                Label("Remove events when you delete a workout in Health", systemImage: "trash")
            }
        } header: {
            Text("Calendar")
        } footer: {
            if coordinator.hasFullCalendarAccess {
                Text("Events you edit or delete yourself are left alone.")
            } else {
                Text("With add-only access, Gainsday adds events but can't see them, so it can't keep them in step with Health. With full access, it finds the events it already added, so none are added twice.")
            }
        }
    }

    private var accessName: String {
        switch coordinator.calendarAccess {
        case .full: String(localized: "Full")
        case .addOnly: String(localized: "Add Only")
        case .none: String(localized: "None")
        }
    }
}
