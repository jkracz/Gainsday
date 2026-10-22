import SwiftUI
import SyncCore

/// The last things Gainsday did and why, with Undo.
struct ActivityLogView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @State private var confirming: ActivityLogEntry?
    @State private var undoFailed = false
    /// Undo refused because the user edited the event, which is theirs now.
    @State private var undoRefusedForEdit = false
    @State private var matching: ActivityLogEntry?
    @State private var addFailed = false
    /// Why a held workout wasn't added, when the engine said.
    @State private var notAddedReason: SkipReason?

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
                    .contextMenu {
                        if entry.canMatchToEvent {
                            RequiresFullAccess {
                                Button("Match to an Event…", systemImage: "calendar.badge.checkmark") { matching = entry }
                                    .disabled(coordinator.isSyncing)
                                if entry.canAddAsSeparateEvent {
                                    Button("Add as Separate Event", systemImage: "calendar.badge.plus") {
                                        Task { await addSeparateEvent(entry) }
                                    }
                                    .disabled(coordinator.isSyncing)
                                }
                            }
                        }
                    }
                }
            } footer: {
                if coordinator.activityLog.contains(where: \.isAwaitingReview) {
                    Text("Touch and hold a workout waiting for your review to match it to your plan or add it as its own event.")
                } else if coordinator.activityLog.contains(where: \.canMatchToEvent) {
                    Text("If you planned a workout in your calendar but it got its own event, touch and hold the workout to match it to your plan.")
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
        .sheet(item: $matching) { entry in
            MatchEventView(entry: entry)
        }
        .confirmationDialog(
            confirming?.undo.map { Text($0.confirmationTitle) } ?? Text(verbatim: ""),
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { entry in
            if let choices = entry.undo?.plannedEventChoices {
                ForEach(choices, id: \.self) { choice in
                    Button {
                        Task { await undo(entry, choice: choice) }
                    } label: {
                        Text(choice.confirmationButton)
                    }
                }
            } else if let kind = entry.undo {
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
        .alert("Couldn't Add the Event", isPresented: $addFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            if let notAddedReason {
                Text(notAddedReason.logDescription)
            } else {
                Text("The workout may have changed in Health. Try again later.")
            }
        }
        .alert("Couldn't Undo", isPresented: $undoFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            if undoRefusedForEdit {
                Text("You changed this event in your calendar, so it's yours now and Gainsday won't delete it.")
            } else {
                Text("The event may have changed or been deleted. Check your calendar, then try again.")
            }
        }
    }

    private func addSeparateEvent(_ entry: ActivityLogEntry) async {
        do {
            try await coordinator.addSeparateEvent(for: entry)
        } catch {
            if case ManualMatchError.notAdded(let reason) = error {
                notAddedReason = reason
            } else {
                notAddedReason = nil
            }
            addFailed = true
        }
    }

    private func undo(_ entry: ActivityLogEntry, choice: ActivityLogEntry.PlannedEventUndoChoice? = nil) async {
        do {
            try await coordinator.undo(entry, choice: choice)
        } catch {
            undoRefusedForEdit = error as? UndoError == .eventEditedByUser
            undoFailed = true
            // The entry can't be undone any more.
            await coordinator.refreshActivityLog()
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
            } else if entry.reviewedAt != nil {
                Text("Reviewed")
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
