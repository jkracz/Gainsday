import SwiftUI
import SyncCore

/// Recommends a calendar just for workouts, asks for calendar access and lets the user pick one.
struct CalendarStep: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(SetupModel.self) private var model

    var body: some View {
        SetupStepLayout(
            title: "Calendar",
            systemImage: "calendar",
            message: "Choose the calendar Gainsday adds your workouts to. It never creates calendars.",
            buttonTitle: "Continue",
            buttonDisabled: model.selectedCalendar == nil,
            action: { model.showStep(after: .calendar) }
        ) {
            Section {
                SetupPoint(
                    title: "Use a calendar just for workouts",
                    systemImage: "star.fill",
                    detail: "Make one in the Calendar app, such as “Workouts”, and don't share it. Then you can hide or share your workouts on their own."
                )
                SetupPoint(
                    title: "Events can't be marked private",
                    systemImage: "eye.fill",
                    detail: "Anyone who can see the calendar you choose can see your workouts, so pick one only you can see."
                )
            }

            if let calendars = model.calendars {
                Section("Your Calendars") {
                    ForEach(calendars) { calendar in
                        CalendarRow(calendar: calendar)
                    }
                }
            } else {
                Section {
                    Button("Allow Calendar Access", systemImage: "calendar.badge.checkmark") {
                        Task { await model.requestCalendarAccess(coordinator) }
                    }
                } footer: {
                    if model.calendarAccessDenied {
                        Text("Turn on full calendar access for Gainsday in Settings, then try again.")
                    } else {
                        Text("Full access lets Gainsday see the events it already added, so it never adds a workout twice.")
                    }
                }
            }
        }
    }
}

/// A calendar the user can pick, with a checkmark on the chosen one.
private struct CalendarRow: View {
    @Environment(SetupModel.self) private var model
    let calendar: CalendarInfo

    var body: some View {
        Button {
            model.selectedCalendarID = calendar.id
        } label: {
            HStack {
                Text(verbatim: calendar.title)
                    .foregroundStyle(.primary)
                Spacer()
                if model.selectedCalendarID == calendar.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(model.selectedCalendarID == calendar.id ? .isSelected : [])
    }
}
