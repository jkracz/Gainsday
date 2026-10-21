import SwiftUI

/// Explains what's read from Health, then shows Health's permission sheet.
struct HealthStep: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(SetupModel.self) private var model

    var body: some View {
        SetupStepLayout(
            title: "Health",
            systemImage: "heart.fill",
            message: "Health asks which data Gainsday can read. Allow workouts, so they can be added to your calendar.",
            buttonTitle: "Continue",
            buttonDisabled: !coordinator.health.isHealthDataAvailable,
            action: {
                if await model.requestHealthAccess(coordinator) {
                    model.showStep(after: .health)
                }
            }
        ) {
            Section {
                SetupPoint(
                    title: "Workouts",
                    systemImage: "figure.run",
                    detail: "When each workout started and ended, and its type."
                )
                SetupPoint(
                    title: "Workout stats",
                    systemImage: "chart.bar.fill",
                    detail: "Distance, energy, heart rate and elevation, for the event's notes."
                )
            } footer: {
                if !coordinator.health.isHealthDataAvailable {
                    Text("Health isn't available on this device, so Gainsday can't read your workouts.")
                } else if model.healthRequested {
                    // HealthKit never says whether read access was granted.
                    Text("If workouts don't show up, open the Health app, tap your profile, then Apps, and check what Gainsday can read.")
                } else {
                    Text("Gainsday reads your workouts. It never writes to Health.")
                }
            }
        }
    }
}
