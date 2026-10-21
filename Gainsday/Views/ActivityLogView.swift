import SwiftUI
import SyncCore

/// The last things Gainsday did and why, with Undo.
struct ActivityLogView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @State private var confirming: ActivityLogEntry?
    @State private var undoFailed = false

    private var canUndo: Bool { coordinator.hasFullCalendarAccess && !coordinator.isSyncing }

    var body: some View {
        List {
            // Undo stays greyed out until the user grants full access.
            if !coordinator.hasFullCalendarAccess, coordinator.activityLog.contains(where: \.canUndo) {
                Section {
                    FullAccessNotice()
                }
            }
            Section {
                ForEach(coordinator.activityLog) { entry in
                    ActivityLogRow(entry: entry, canUndo: canUndo) {
                        confirming = entry
                    }
                }
            }
        }
        .overlay {
            if coordinator.activityLog.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Workouts Gainsday adds, updates or skips appear here.")
                )
            }
        }
        .navigationTitle("Activity")
        .confirmationDialog(
            confirming?.undo.map { Text($0.confirmationTitle) } ?? Text(verbatim: ""),
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { entry in
            if let kind = entry.undo {
                Button(role: kind == .removeCreatedEvent ? .destructive : nil) {
                    Task { await undo(entry) }
                } label: {
                    Text(kind.confirmationButton)
                }
            }
        } message: { entry in
            if let kind = entry.undo {
                Text(kind.confirmationMessage)
            }
        }
        .alert("Couldn't Undo", isPresented: $undoFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The event may have changed or been deleted. Check your calendar, then try again.")
        }
    }

    private func undo(_ entry: ActivityLogEntry) async {
        do {
            try await coordinator.undo(entry)
        } catch {
            undoFailed = true
        }
    }
}

/// One log entry: what happened to which workout, and an Undo button when it can be reversed.
private struct ActivityLogRow: View {
    let entry: ActivityLogEntry
    let canUndo: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.title)
                    .font(.headline)
                Text(entry.action.logDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let start = entry.workoutStart {
                    Text(start, format: .dateTime.weekday().day().month().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if entry.undoneAt != nil {
                Text("Undone")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if entry.canUndo {
                Button("Undo", action: onUndo)
                    .buttonStyle(.borderless)
                    .disabled(!canUndo)
            }
        }
    }
}
