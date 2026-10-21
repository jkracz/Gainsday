import FoundationModels
import SwiftUI
import SyncCore

/// How matches the keyword rules find unclear are decided: by the on-device model, and
/// failing that with a separate event or by holding the workout for review. [v1.1]
/// A section of its own, so the matching settings screen can embed it.
struct UnclearMatchSettingsSection: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        Section {
            Toggle("Use On-Device Model", isOn: modelEnabled)
            Toggle("Hold Unclear Matches for Review", isOn: holdsForReview)
        } header: {
            Text("Unclear Matches")
        } footer: {
            Text(footer)
        }
    }

    private var footer: LocalizedStringResource {
        guard SystemLanguageModel.default.isAvailable || !coordinator.settings.matchModelEnabled else {
            return "Apple Intelligence isn't available on this iPhone right now, so unclear matches are decided as if the model were off. Otherwise Apple's on-device model decides when titles like \"Gym w/ Alex\" don't say what was planned, and nothing leaves your iPhone."
        }
        return "Apple's on-device model decides when titles like \"Gym w/ Alex\" don't say what was planned, and nothing leaves your iPhone. Whatever it can't decide gets a separate event, or waits for your review with a notification."
    }

    private var modelEnabled: Binding<Bool> {
        Binding {
            coordinator.settings.matchModelEnabled
        } set: { isOn in
            coordinator.updateSettings { $0.matchModelEnabled = isOn }
        }
    }

    private var holdsForReview: Binding<Bool> {
        Binding {
            coordinator.settings.holdUnclearMatchesForReview
        } set: { isOn in
            coordinator.updateSettings { $0.holdUnclearMatchesForReview = isOn }
        }
    }
}
