import SwiftUI

/// Says what Gainsday reads and writes before anything asks for permission.
struct WelcomeStep: View {
    @Environment(SetupModel.self) private var model

    var body: some View {
        SetupStepLayout(
            title: "Welcome to Gainsday",
            systemImage: "figure.run.circle.fill",
            message: "Gainsday copies your workouts from Apple Health into a calendar you choose.",
            buttonTitle: "Continue",
            action: { model.showStep(after: .welcome) }
        ) {
            Section {
                SetupPoint(
                    title: "Reads your workouts from Health",
                    systemImage: "heart.fill",
                    detail: "The type, the time and stats such as distance, energy and heart rate. It never writes to Health."
                )
                SetupPoint(
                    title: "Adds events to one calendar",
                    systemImage: "calendar",
                    detail: "One event per workout, in the calendar you choose. It only changes events it added itself."
                )
                SetupPoint(
                    title: "No server, no account",
                    systemImage: "lock.fill",
                    detail: "Everything happens on this iPhone. Your settings and the list of events it added are backed up to your own iCloud."
                )
            } footer: {
                Text("Next, Gainsday asks for access to Health and your calendar.")
            }
        }
    }
}
