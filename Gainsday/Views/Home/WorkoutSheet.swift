import SwiftUI
import SyncCore

/// A workout's calendar event, history and available actions.
struct WorkoutSheet: View {
    /// Falls back to this snapshot if the workout leaves the activity log.
    let opened: FeedItem
    let workout: Workout?
    /// Defers removal through the feed's undo toast.
    let remove: (ActivityLogEntry) -> Void

    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var event: CalendarEvent?
    @State private var matching: ActivityLogEntry?
    @State private var confirming: ActivityLogEntry?
    @State private var undoFailed = false
    @State private var undoRefusedForEdit = false
    @State private var addFailed = false
    @State private var notAddedReason: SkipReason?

    private var item: FeedItem {
        FeedItem.items(from: coordinator.activityLog).first { $0.id == opened.id } ?? opened
    }
    private var entry: ActivityLogEntry { item.current }
    private var canAct: Bool { coordinator.hasFullCalendarAccess && !coordinator.isSyncing }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let event {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(Text("In your calendar"))
                            ExampleEventCard(content: event.content, tint: entry.activityType?.tint ?? Color(.workoutOther))
                        }
                    }
                    actions
                    if item.history.count > 1 {
                        history
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color(.canvas))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task(id: EventSource(entryID: entry.id, hasFullAccess: coordinator.hasFullCalendarAccess)) { await loadEvent() }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let type = entry.activityType {
                HStack(spacing: 6) {
                    Circle().fill(type.tint).frame(width: 8, height: 8)
                    Text(verbatim: type.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.ink))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(type.tint.opacity(0.14), in: .capsule)
            }
            Text(verbatim: entry.title)
                .font(.largeTitle.bold())
                .foregroundStyle(Color(.ink))
            subtitle
                .font(.subheadline)
                .foregroundStyle(Color(.inkSecondary))
            HStack(spacing: 8) {
                item.status.badge
                Text(entry.action.logDescription)
                    .font(.footnote)
                    .foregroundStyle(Color(.inkSecondary))
            }
        }
    }

    private var subtitle: Text {
        let day = Calendar.current.isDateInToday(item.date) ? Text("Today")
            : Calendar.current.isDateInYesterday(item.date) ? Text("Yesterday")
            : Text(item.date, format: .dateTime.weekday().day().month())
        guard let workout else {
            return Text("\(day) · \(Text(item.date, format: .dateTime.hour().minute()))")
        }
        let times = Text(workout.start..<max(workout.start, workout.end), format: .interval.hour().minute())
        return Text("\(day) · \(times) · \(Text(verbatim: workout.source.name))")
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                if item.status.isInCalendar {
                    ActionRow(title: "Open in Calendar", systemImage: "calendar", color: Color(.danger)) {
                        if let url = URL(string: "calshow:\(Int(item.date.timeIntervalSinceReferenceDate))") { openURL(url) }
                    }
                }
                if entry.canMatchToEvent {
                    ActionRow(title: "Match to a Planned Event", systemImage: "checkmark", color: Color.accentColor) {
                        matching = entry
                    }
                    .disabled(!canAct)
                }
                if entry.canAddAsSeparateEvent {
                    ActionRow(title: "Add as Separate Event", systemImage: "calendar.badge.plus", color: Color(.info)) {
                        Task { await addSeparateEvent() }
                    }
                    .disabled(!canAct)
                }
                if entry.canUndo, let kind = entry.undo {
                    if kind == .removeCreatedEvent {
                        ActionRow(title: "Remove from Calendar", systemImage: "trash", color: Color(.danger), isDestructive: true) {
                            remove(entry)
                            dismiss()
                        }
                        .disabled(!canAct)
                    } else {
                        ActionRow(title: kind.confirmationButton, systemImage: "arrow.uturn.backward", color: Color(.inkSecondary)) {
                            confirming = entry
                        }
                        .disabled(!canAct)
                    }
                }
            }
            .background(Color(.card), in: .rect(cornerRadius: 20))

            if entry.canUndo || entry.canMatchToEvent, !coordinator.hasFullCalendarAccess {
                FullAccessNotice()
            } else if entry.canUndo, entry.undo == .removeCreatedEvent {
                Text("Removing it means this workout won't be added again.")
                    .font(.footnote)
                    .foregroundStyle(Color(.inkSecondary))
                    .padding(.horizontal, 4)
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(Text("History"))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(item.history) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.action.logDescription)
                                .font(.subheadline)
                                .foregroundStyle(Color(.ink))
                            Text(entry.date, format: .dateTime.weekday().day().month().hour().minute())
                                .font(.caption)
                                .foregroundStyle(Color(.inkSecondary))
                        }
                        Spacer()
                        if entry.undoneAt != nil {
                            Text("Undone")
                                .font(.subheadline)
                                .foregroundStyle(Color(.inkSecondary))
                        } else if entry.id != item.current.id, entry.canUndo {
                            Button("Undo") { confirming = entry }
                                .font(.subheadline.weight(.semibold))
                                .disabled(!canAct)
                        }
                    }
                }
            }
            .card()
        }
    }

    /// Reloads the event when its entry or read access changes.
    private struct EventSource: Hashable {
        var entryID: UUID
        var hasFullAccess: Bool
    }

    private func loadEvent() async {
        guard coordinator.hasFullCalendarAccess, item.status.isInCalendar, let id = entry.eventID else {
            event = nil
            return
        }
        event = try? await coordinator.calendar.event(withID: id)
    }

    private func addSeparateEvent() async {
        do {
            try await coordinator.addSeparateEvent(for: entry)
            dismiss()
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
            dismiss()
        } catch {
            undoRefusedForEdit = error as? UndoError == .eventEditedByUser
            undoFailed = true
            // Undo can release a user-edited event before throwing.
            await coordinator.refreshActivityLog()
        }
    }
}

/// A workout action with a tinted icon.
private struct ActionRow: View {
    let title: Text
    let systemImage: String
    let color: Color
    var isDestructive = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(title: LocalizedStringResource, systemImage: String, color: Color, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.color = color
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.14), in: .rect(cornerRadius: 8))
                    .accessibilityHidden(true)
                title
                    .foregroundStyle(isDestructive ? Color(.danger) : Color(.ink))
                Spacer()
                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.inkTertiary))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(.rect)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}
