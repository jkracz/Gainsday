import SwiftUI
import SyncCore

/// Picks the event the user planned for a logged workout, when the plan reached the
/// phone too late to be matched. [v1.1]
struct MatchEventView: View {
    let entry: ActivityLogEntry
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [CalendarEvent]?
    @State private var calendarTitles: [String: String] = [:]
    @State private var isMatching = false
    @State private var matchFailed = false

    var body: some View {
        NavigationStack {
            List {
                if let candidates, !candidates.isEmpty {
                    Section {
                        ForEach(candidates) { event in
                            Button {
                                Task { await match(event) }
                            } label: {
                                CandidateRow(event: event, calendarTitle: calendarTitles[event.calendarID])
                            }
                            .disabled(isMatching)
                        }
                    } header: {
                        Text("Planned Near This Workout")
                    } footer: {
                        Text("The event moves to the workout's times and gains the workout in its notes, and the workout's separate event is removed. You can undo this in the activity log.")
                    }
                }
            }
            .overlay {
                if candidates == nil {
                    ProgressView()
                } else if candidates?.isEmpty == true {
                    ContentUnavailableView(
                        "No Events to Match",
                        systemImage: "calendar",
                        description: Text("Events you planned near this workout appear here. Events with guests aren't listed, since changing them could email every guest.")
                    )
                }
            }
            .navigationTitle("Match to an Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .task { await load() }
            .alert("Couldn't Match", isPresented: $matchFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The event or the workout may have changed. Check your calendar, then try again.")
            }
        }
    }

    private func load() async {
        let calendars = (try? await coordinator.calendar.writableCalendars()) ?? []
        calendarTitles = Dictionary(calendars.map { ($0.id, $0.title) }) { first, _ in first }
        candidates = (try? await coordinator.matchCandidates(for: entry)) ?? []
    }

    private func match(_ event: CalendarEvent) async {
        isMatching = true
        defer { isMatching = false }
        do {
            try await coordinator.match(entry, to: event)
            dismiss()
        } catch {
            matchFailed = true
        }
    }
}

/// A planned event: its title, times and calendar.
private struct CandidateRow: View {
    let event: CalendarEvent
    let calendarTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: event.content.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(event.content.start..<max(event.content.start, event.content.end), format: .interval.hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let calendarTitle {
                Text(verbatim: calendarTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
