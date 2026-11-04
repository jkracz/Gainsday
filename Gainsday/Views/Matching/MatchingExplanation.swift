import SwiftUI
import SyncCore

/// What matching does, shown before the user turns it on: an example planned event
/// before and after a workout updates it, then what's kept and what's left alone.
/// `matchingExplanationSheet` shows it from setup's "See how", and the first time
/// matching is turned on anywhere.
struct MatchingExplanation: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        let example = Example(settings: coordinator.settings)
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(Text("Before"))
            ExampleEventCard(content: example.planned, isHighlighted: false)
            SectionLabel(Text("After your workout"))
            ExampleEventCard(content: example.updated, isHighlighted: true)
            VStack(alignment: .leading, spacing: 12) {
                Check(text: "Your title and notes stay. The workout is added below them.")
                Check(text: "The event moves to when you actually worked out.")
                Check(text: "Only clear matches. Events with guests are never changed.")
            }
            .padding(.top, 8)
        }
    }

    /// A planned morning run today, and the same event after a run that started a little late.
    private struct Example {
        let planned: EventContent
        let updated: EventContent

        init(settings: Settings) {
            let clock = SystemClock()
            let start = clock.calendar.date(bySettingHour: 7, minute: 0, second: 0, of: clock.now) ?? clock.now
            planned = EventContent(
                title: String(localized: "Morning Run"),
                start: start,
                end: start.addingTimeInterval(45 * 60),
                notes: String(localized: "Easy pace by the river")
            )
            // The sample run lasts 28 minutes, so it starts at 7:12.
            let workout = Workout.sample(.running, endingAt: start.addingTimeInterval(40 * 60))
            updated = MatchingExample.updating(planned, with: workout, settings: settings, clock: clock)
        }
    }
}

private struct Check: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color(.ink))
        }
    }
}

/// An event as it would look in Calendar: its title, times and notes.
struct ExampleEventCard: View {
    let content: EventContent
    var isHighlighted = false
    var tint = WorkoutActivityType.running.tint

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: content.title)
                    .font(.headline)
                    .foregroundStyle(Color(.ink))
                Text(content.start..<max(content.start, content.end), format: .interval.hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(Color(.inkSecondary))
                if let notes = content.notes, !notes.isEmpty {
                    Text(verbatim: notes)
                        .font(.footnote)
                        .foregroundStyle(Color(.ink))
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .card(padding: 14)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 20).strokeBorder(Color(.volt), lineWidth: 2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Asks before turning matching on: the explanation, then Turn On or Not Now.
private struct MatchingExplanationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let turnOn: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Update planned events")
                            .font(.title2.bold())
                            .foregroundStyle(Color(.ink))
                        Text("When a workout matches an event you planned, Gainsday updates that event instead of adding another.")
                            .foregroundStyle(Color(.inkSecondary))
                    }
                    MatchingExplanation()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color(.canvas))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .safeAreaBar(edge: .bottom) {
                Button("Turn On") {
                    MatchingExplanation.hasTurnedOnMatching = true
                    turnOn()
                    dismiss()
                }
                .buttonStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }
}

extension MatchingExplanation {
    private static let turnedOnKey = "hasTurnedOnMatching"

    /// Whether the user has turned matching on after seeing the explanation, on this device.
    static var hasTurnedOnMatching: Bool {
        get { UserDefaults.standard.bool(forKey: turnedOnKey) }
        set { UserDefaults.standard.set(newValue, forKey: turnedOnKey) }
    }
}

extension View {
    /// Shows the matching explanation in a sheet. "Turn On" calls `turnOn`; "Not Now" only closes it.
    func matchingExplanationSheet(isPresented: Binding<Bool>, turnOn: @escaping () -> Void) -> some View {
        sheet(isPresented: isPresented) {
            MatchingExplanationSheet(turnOn: turnOn)
        }
    }
}

/// The switch for matching, for Settings. Turning it on the first time shows the
/// explanation, and matching only turns on if the user agrees there.
struct MatchingToggle<Label: View>: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @State private var isExplaining = false
    @ViewBuilder let label: Label

    var body: some View {
        Toggle(isOn: Binding(
            get: { coordinator.settings.matchingEnabled },
            set: { isOn in
                if isOn, !MatchingExplanation.hasTurnedOnMatching {
                    isExplaining = true
                } else {
                    coordinator.updateSettings { $0.matchingEnabled = isOn }
                }
            }
        )) {
            label
        }
        .matchingExplanationSheet(isPresented: $isExplaining) {
            coordinator.updateSettings { $0.matchingEnabled = true }
        }
    }
}
