import SwiftUI
import SyncCore

/// What matching does, shown before the user turns it on: an example planned event
/// before and after a workout updates it, then what's kept and what's left alone.
/// Setup shows it as a step, and `matchingExplanationSheet` shows it the first time
/// matching is turned on anywhere else.
struct MatchingExplanation: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        let example = Example(settings: coordinator.settings)
        Section("Before") {
            ExampleEventCard(content: example.planned)
        }
        Section("After Your Workout") {
            ExampleEventCard(content: example.updated)
        }
        Section {
            SetupPoint(
                title: "Your title and notes stay",
                systemImage: "text.badge.checkmark",
                detail: "The event moves to when you actually worked out, and the workout's details are added below your notes."
            )
            SetupPoint(
                title: "Only clear matches",
                systemImage: "questionmark.circle",
                detail: "If Gainsday isn't sure which event is the plan, or the event has guests, it leaves your events alone and adds its own."
            )
        } footer: {
            Text("You can change this later in Settings.")
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

/// An event as it would look in Calendar: its title, times and notes.
private struct ExampleEventCard: View {
    let content: EventContent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.tint)
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: content.title)
                    .font(.headline)
                Text(content.start..<content.end, format: .interval.hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let notes = content.notes, !notes.isEmpty {
                    Text(verbatim: notes)
                        .font(.footnote)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Asks before turning matching on: the explanation, then Turn On or Not Now.
private struct MatchingExplanationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let turnOn: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("When a workout matches an event you planned, Gainsday can update that event instead of adding another.")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                MatchingExplanation()
            }
            .navigationTitle("Update Planned Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    MatchingExplanation.hasTurnedOnMatching = true
                    turnOn()
                    dismiss()
                } label: {
                    Text("Turn On")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
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
