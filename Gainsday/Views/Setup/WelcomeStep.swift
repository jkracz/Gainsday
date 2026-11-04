import SwiftUI
import SyncCore

/// Says what Gainsday reads and writes before anything asks for permission.
struct WelcomeStep: View {
    @Environment(SetupModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                CalendarDayHero()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your workouts, on your calendar.")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color(.ink))
                    Text("Gainsday copies workouts from Apple Health into a calendar you choose.")
                        .foregroundStyle(Color(.inkSecondary))
                }
                VStack(alignment: .leading, spacing: 14) {
                    Promise(systemImage: "heart.fill", text: "Reads workouts from Health. Never writes.")
                    Promise(systemImage: "calendar", text: "One event per workout, in a calendar you pick.")
                    Promise(systemImage: "lock.fill", text: "No account or server. Backed up to your iCloud.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.canvas))
        .toolbarVisibility(.hidden, for: .navigationBar)
        .safeAreaBar(edge: .bottom) {
            Button("Get Started") { model.showStep(after: .welcome) }
                .buttonStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
    }
}

/// A privacy promise with an icon.
private struct Promise: View {
    let systemImage: String
    let text: LocalizedStringKey

    var body: some View {
        Label {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.ink))
        } icon: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.onVolt)
                .frame(width: 30, height: 30)
                .background(Color(.volt), in: .circle)
        }
        .labelStyle(PromiseLabelStyle())
    }
}

private struct PromiseLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
            configuration.title
        }
    }
}

/// A sample calendar day containing workout events.
private struct CalendarDayHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Date.now, format: .dateTime.weekday(.wide))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.danger))
                    .textCase(.uppercase)
                Spacer()
                Text(Date.now, format: .dateTime.day())
                    .font(.title.bold())
                    .foregroundStyle(Color(.ink))
            }
            HeroEvent(time: "7:00", type: .running, title: Text("Morning Run · 6.2 km"))
            HeroEvent(time: "12:30", type: .walking, title: Text("Walk · 28 min"))
            HeroEvent(time: "18:15", type: .traditionalStrengthTraining, title: Text("Strength · 50 min"))
        }
        .card()
        .accessibilityHidden(true)
    }
}

private struct HeroEvent: View {
    let time: String
    let type: WorkoutActivityType
    let title: Text

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color(.inkTertiary))
                .frame(width: 40, alignment: .leading)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(type.tint)
                    .frame(width: 4)
                title
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.ink))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.leading, 6)
            .frame(maxWidth: .infinity)
            .background(type.tint.opacity(0.14), in: .rect(cornerRadius: 10))
        }
    }
}
