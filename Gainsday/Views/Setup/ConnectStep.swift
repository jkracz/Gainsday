import SwiftUI
import SyncCore
import UIKit

/// Health and calendar permissions with a destination calendar picker.
struct ConnectStep: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(SetupModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        SetupScreen(
            step: .connect,
            title: "Connect",
            subtitle: Text("Two permissions. Nothing leaves your iPhone."),
            buttonTitle: "Continue",
            buttonDisabled: !model.healthRequested || model.selectedCalendar == nil,
            action: { model.showStep(after: .connect) }
        ) {
            HealthCard()
            CalendarCard()
            if model.calendars != nil, !model.isAddOnly {
                HStack(spacing: 4) {
                    Text("No workouts calendar?")
                        .foregroundStyle(Color(.inkSecondary))
                    Button("Make one in Calendar") {
                        if let url = URL(string: "calshow://") { openURL(url) }
                    }
                    .fontWeight(.semibold)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            // Reinstalls can retain calendar permission.
            if model.calendars == nil, await coordinator.calendar.accessMode() == .full {
                await model.refreshCalendars(coordinator)
            }
        }
    }
}

/// A permission description with a trailing control.
private struct PermissionRow<Trailing: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let systemImage: String
    let color: Color
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.14), in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color(.ink))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color(.inkSecondary))
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

private struct GrantedCheck: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.title2)
            .foregroundStyle(.white, Color(.positive))
            .accessibilityLabel(Text("Allowed"))
    }
}

private struct HealthCard: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(SetupModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PermissionRow(title: "Apple Health", detail: "Reads workouts and their stats", systemImage: "heart.fill", color: Color(.danger)) {
                if !coordinator.health.isHealthDataAvailable {
                    EmptyView()
                } else if model.healthRequested {
                    GrantedCheck()
                } else {
                    Button("Allow") {
                        Task { _ = await model.requestHealthAccess(coordinator) }
                    }
                    .buttonStyle(.secondary)
                }
            }
            if !coordinator.health.isHealthDataAvailable {
                Text("Health isn't available on this device, so Gainsday can't read your workouts.")
                    .font(.footnote)
                    .foregroundStyle(Color(.danger))
            } else if model.healthRequested {
                // HealthKit never says whether read access was granted.
                Text("Workouts missing later? Check Health → your profile → Apps → Gainsday.")
                    .font(.footnote)
                    .foregroundStyle(Color(.inkSecondary))
            }
        }
        .card()
    }
}

private struct CalendarCard: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(SetupModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PermissionRow(title: "Calendar", detail: "Adds one event per workout", systemImage: "calendar", color: Color(.danger)) {
                if model.calendars != nil {
                    GrantedCheck()
                } else {
                    Button("Allow") {
                        Task { await model.requestCalendarAccess(coordinator) }
                    }
                    .buttonStyle(.secondary)
                }
            }

            if model.isAddOnly {
                Divider()
                CalendarChoice(title: CalendarReference.defaultCalendar.displayTitle, color: nil, isSelected: true) {}
                Text("With add-only access, iOS picks your default calendar. Change it in Settings → Apps → Calendar.")
                    .font(.footnote)
                    .foregroundStyle(Color(.inkSecondary))
            } else if let calendars = model.calendars {
                Divider()
                SectionLabel(Text("Add workouts to"))
                Text("Pick one only you can see. Events can't be marked private.")
                    .font(.footnote)
                    .foregroundStyle(Color(.inkSecondary))
                VStack(spacing: 4) {
                    ForEach(calendars) { calendar in
                        CalendarChoice(
                            title: calendar.title,
                            color: model.calendarColors[calendar.id],
                            isSelected: model.selectedCalendarID == calendar.id
                        ) {
                            model.selectedCalendarID = calendar.id
                        }
                    }
                }
            } else if model.calendarAccessDenied {
                Button("Turn On in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.subheadline.weight(.semibold))
            } else {
                Button("Add events only, without full access") {
                    Task { await model.requestAddOnlyAccess(coordinator) }
                }
                .font(.footnote)
                .foregroundStyle(Color(.inkSecondary))
            }
        }
        .card()
    }
}

/// A selectable calendar row.
private struct CalendarChoice: View {
    let title: String
    let color: CalendarColor?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Color(.inkTertiary))
                    .frame(width: 10, height: 10)
                Text(verbatim: title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Color(.ink))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color(.buttonLabel), Color(.buttonFill))
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.ink), lineWidth: 2)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
