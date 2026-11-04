import SwiftUI
import SyncCore

/// The last step: which workout types to add, whether to add the past week and to
/// update planned events, then Start Syncing.
struct ReadyStep: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(SetupModel.self) private var model
    @State private var isExplainingMatching = false

    var body: some View {
        @Bindable var model = model
        SetupScreen(
            step: .ready,
            title: "Ready to sync",
            subtitle: subtitle,
            buttonTitle: "Start Syncing",
            buttonDisabled: model.selectedCalendar == nil || coordinator.settings.enabledTypes.isEmpty || model.isStarting,
            action: { await model.startSyncing(coordinator) }
        ) {
            WorkoutTypeChips()

            VStack(spacing: 0) {
                Toggle(isOn: $model.addsPastWeek) {
                    ToggleText(title: "Add the past 7 days", detail: pastWeekDetail)
                }
                .padding(.vertical, 12)
                // Matching reads the user's events, which add-only access can't.
                if !model.isAddOnly {
                    Divider()
                    Toggle(isOn: matching) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update planned events")
                                .font(.headline)
                                .foregroundStyle(Color(.ink))
                            Text("Fill in the run you planned instead of adding a copy.")
                                .font(.subheadline)
                                .foregroundStyle(Color(.inkSecondary))
                            Button("See how") { isExplainingMatching = true }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .tint(Color(.volt))
            .card(padding: 16)
        }
        .matchingExplanationSheet(isPresented: $isExplainingMatching) {
            model.enablesMatching = true
        }
    }

    private var subtitle: Text {
        let calendar = model.selectedCalendar?.title ?? ""
        return Text("Choose what lands in \(Text(verbatim: calendar).bold().foregroundStyle(Color(.ink))).")
    }

    private var pastWeekDetail: LocalizedStringKey {
        if let restored = coordinator.settings.syncStartDate {
            "Workouts since \(restored.formatted(.dateTime.day().month().year())) are added, as before."
        } else if model.addsPastWeek {
            "So your calendar isn't empty. Add more later."
        } else {
            "Only workouts you start from now on."
        }
    }

    /// Turning it on the first time explains matching first, as Settings does.
    private var matching: Binding<Bool> {
        Binding {
            model.showsMatchingOn(coordinator.settings)
        } set: { isOn in
            if isOn, !MatchingExplanation.hasTurnedOnMatching {
                isExplainingMatching = true
            } else {
                model.enablesMatching = isOn
            }
        }
    }
}

private struct ToggleText: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(.ink))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Color(.inkSecondary))
        }
    }
}

/// Every workout type as a chip to tap on or off, coloured when it's on.
struct WorkoutTypeChips: View {
    @Environment(SyncCoordinator.self) private var coordinator

    private var enabled: Set<WorkoutActivityType> { coordinator.settings.enabledTypes }

    var body: some View {
        let types = WorkoutActivityType.listed(enabled: enabled)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(Text("Workout types · \(enabled.count) on"))
                Spacer()
                Button("Select All") {
                    coordinator.updateSettings { $0.enabledTypes.formUnion(types) }
                }
                .font(.footnote.weight(.semibold))
                .disabled(Set(types).isSubset(of: enabled))
            }
            FlowLayout(spacing: 8) {
                ForEach(types, id: \.self) { type in
                    TypeChip(type: type, isOn: enabled.contains(type)) {
                        coordinator.updateSettings { settings in
                            if settings.enabledTypes.contains(type) {
                                settings.enabledTypes.remove(type)
                            } else {
                                settings.enabledTypes.insert(type)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TypeChip: View {
    let type: WorkoutActivityType
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isOn {
                    Circle().fill(type.tint).frame(width: 8, height: 8)
                }
                Text(verbatim: type.displayName)
                    .font(.subheadline.weight(isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Color(.ink) : Color(.inkSecondary))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(isOn ? type.tint.opacity(0.16) : Color.clear, in: .capsule)
            .overlay {
                if !isOn { Capsule().strokeBorder(Color(.hairline), lineWidth: 1.5) }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
