import SwiftUI
import SyncCore

/// Renders the template being edited with a recent workout, or sample data for
/// types the user hasn't recorded, using the same renderer and clock as sync.
struct TemplatePreviewSection: View {
    var template: EventTemplate

    @Environment(SyncCoordinator.self) private var coordinator
    @State private var choices = TemplatePreview.choices(recent: [], now: SystemClock().now)
    @State private var selectedID: TemplatePreview.Choice.ID?
    private let clock = SystemClock()

    private var choice: TemplatePreview.Choice? {
        choices.first { $0.id == selectedID } ?? choices.first
    }

    var body: some View {
        Section {
            Picker("Workout", selection: $selectedID) {
                ForEach(choices) { choice in
                    label(for: choice).tag(Optional(choice.id))
                }
            }
            if let workout = choice?.workout {
                let rendered = TemplateRenderer(locale: clock.locale, calendar: clock.calendar).render(template, for: workout)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: rendered.title)
                        .font(.headline)
                    if !rendered.notes.isEmpty {
                        Text(verbatim: rendered.notes)
                    }
                    if coordinator.settings.footerEnabled {
                        Label {
                            Text(verbatim: Footer.line(for: workout.id))
                        } icon: {
                            Image(systemName: "lock.fill")
                        }
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.tertiary)
                        .accessibilityHint(Text("Added by Gainsday. It isn't part of your template."))
                    }
                }
                .textSelection(.enabled)
                .padding(.vertical, 4)
            }
        } header: {
            Text("Preview")
        } footer: {
            if coordinator.settings.footerEnabled {
                Text("Gainsday adds the last line itself, so it can recognise its events. It isn't part of your template.")
            }
        }
        .task { await loadRecentWorkouts() }
    }

    private func label(for choice: TemplatePreview.Choice) -> Text {
        let type = choice.workout.activityType
        let name = "\(type.emoji) \(type.name)"
        if choice.isSample {
            return Text("\(name) · Sample")
        }
        return Text(verbatim: "\(name) · \(choice.workout.start.formatted(.dateTime.day().month().hour().minute()))")
    }

    private func loadRecentWorkouts() async {
        // Without Health access there are no recent workouts, so the preview uses samples.
        let recent = (try? await coordinator.health.recentWorkouts(limit: 20)) ?? []
        choices = TemplatePreview.choices(recent: recent, now: clock.now)
        if selectedID == nil || !choices.contains(where: { $0.id == selectedID }) {
            selectedID = choices.first?.id
        }
    }
}
