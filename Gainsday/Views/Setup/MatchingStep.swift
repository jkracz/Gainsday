import SwiftUI
import SyncCore

/// Asks whether workouts may update the events the user planned, with "Not Now"
/// chosen unless settings restored from iCloud already turned matching on.
struct MatchingStep: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(SetupModel.self) private var model

    private var enablesMatching: Bool {
        model.showsMatchingOn(coordinator.settings)
    }

    var body: some View {
        SetupStepLayout(
            title: "Planned Events",
            systemImage: "calendar.badge.checkmark",
            message: "When a workout matches an event you planned, Gainsday can update that event instead of adding another.",
            buttonTitle: "Continue",
            action: {
                // Keeps what the user saw, even if restored settings arrive later.
                model.enablesMatching = enablesMatching
                model.showStep(after: .matching)
            }
        ) {
            Section {
                ChoiceRow(title: "Update Planned Events", isSelected: enablesMatching) {
                    model.enablesMatching = true
                }
                ChoiceRow(title: "Not Now", isSelected: !enablesMatching) {
                    model.enablesMatching = false
                }
            }
            MatchingExplanation()
        }
    }
}

/// One of the step's answers, with a checkmark on the chosen one.
private struct ChoiceRow: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
