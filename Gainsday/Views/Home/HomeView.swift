import SwiftUI
import SyncCore

/// Sync status, weekly totals and the workout feed.
struct HomeView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var workouts: [UUID: Workout] = [:]
    @State private var calendarColors: [String: CalendarColor] = [:]
    @State private var selected: FeedItem?
    @State private var matching: ActivityLogEntry?
    @State private var isAddingPast = false
    @State private var removal = PendingRemoval()

    private var items: [FeedItem] {
        FeedItem.items(from: coordinator.activityLog).filter { !removal.hiddenIDs.contains($0.current.id) }
    }

    var body: some View {
        let items = items
        let shown = items.filter { $0.status != .skipped }
        let skipped = items.filter { $0.status == .skipped }
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    SyncStatusLine(color: destinationColor)
                    HomeBanners()
                    WeekStrip(items: shown, workouts: workouts)
                    ForEach(shown.filter { $0.status == .needsReview }) { item in
                        ReviewCard(item: item) { matching = item.current }
                    }
                    ForEach(days(of: shown), id: \.self) { day in
                        SectionLabel(dayTitle(day))
                            .padding(.top, 4)
                        ForEach(shown.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { item in
                            Button { selected = item } label: {
                                FeedCard(item: item, workout: workouts[item.id])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !skipped.isEmpty {
                        NavigationLink {
                            SkippedView(items: skipped)
                        } label: {
                            SkippedRow(items: skipped)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 80)
            }
            .overlay {
                if shown.isEmpty, skipped.isEmpty {
                    ContentUnavailableView(
                        "No Workouts Yet",
                        systemImage: "figure.run",
                        description: Text("Workouts you finish appear here and in your calendar.")
                    )
                }
            }
            .background(Color(.canvas))
            .refreshable { await coordinator.sync() }
            .navigationTitle("Gainsday")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Add Past Workouts", systemImage: "plus") { isAddingPast = true }
                    NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
                }
            }
            .overlay(alignment: .bottom) {
                if let entry = removal.entry {
                    UndoToast(title: entry.title) { removal.cancel() }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: removal.entry)
        }
        .tint(Color.accentColor)
        .sheet(item: $selected) { item in
            WorkoutSheet(opened: item, workout: workouts[item.id]) { entry in
                removal.start(entry, coordinator: coordinator)
            }
        }
        .sheet(item: $matching) { entry in
            MatchEventView(entry: entry)
        }
        .sheet(isPresented: $isAddingPast) {
            NavigationStack {
                BackfillView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isAddingPast = false }
                        }
                    }
            }
        }
        .alert("Couldn't Remove", isPresented: $removal.failed) {
            Button("OK", role: .cancel) {}
        } message: {
            if removal.refusedForEdit {
                Text("You changed this event in your calendar, so it's yours now and Gainsday won't delete it.")
            } else {
                Text("The event may have changed or been deleted. Check your calendar, then try again.")
            }
        }
        .task(id: coordinator.activityLog) { await loadWorkouts() }
        .task(id: coordinator.calendarAccess) {
            calendarColors = await coordinator.calendar.calendarColors()
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app shouldn't lose a removal the user meant.
            if phase != .active { removal.commitNow(coordinator: coordinator) }
        }
    }

    private var destinationColor: CalendarColor? {
        coordinator.settings.destinationCalendar.flatMap { calendarColors[$0.id] }
    }

    private func days(of items: [FeedItem]) -> [Date] {
        var days: [Date] = []
        for item in items {
            let day = Calendar.current.startOfDay(for: item.date)
            if days.last != day { days.append(day) }
        }
        return days
    }

    private func dayTitle(_ day: Date) -> Text {
        if Calendar.current.isDateInToday(day) { return Text("Today") }
        if Calendar.current.isDateInYesterday(day) { return Text("Yesterday") }
        return Text(day, format: .dateTime.weekday(.wide).day().month())
    }

    private func loadWorkouts() async {
        // Without Health access, cards show without stats.
        let recent = (try? await coordinator.health.recentWorkouts(limit: 100)) ?? []
        workouts = Dictionary(recent.map { ($0.id, $0) }) { first, _ in first }
    }
}

/// Defers event removal until the undo period ends or the app leaves the foreground.
@Observable
final class PendingRemoval {
    private(set) var entry: ActivityLogEntry?
    /// Entries kept out of the feed: the pending one, and any still being removed.
    private(set) var hiddenIDs: Set<UUID> = []
    var failed = false
    private(set) var refusedForEdit = false
    private var timer: Task<Void, Never>?
    static let delay: Duration = .seconds(4)

    func start(_ entry: ActivityLogEntry, coordinator: SyncCoordinator) {
        commitNow(coordinator: coordinator)
        self.entry = entry
        hiddenIDs.insert(entry.id)
        timer = Task {
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            commitNow(coordinator: coordinator)
        }
    }

    func cancel() {
        if let entry { hiddenIDs.remove(entry.id) }
        stopTimer()
    }

    func commitNow(coordinator: SyncCoordinator) {
        guard let entry else { return }
        stopTimer()
        Task {
            defer { hiddenIDs.remove(entry.id) }
            do {
                try await coordinator.undo(entry)
            } catch {
                refusedForEdit = error as? UndoError == .eventEditedByUser
                failed = true
                // Undo can release a user-edited event before throwing.
                await coordinator.refreshActivityLog()
            }
        }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        entry = nil
    }
}

/// A removal confirmation with an undo action.
private struct UndoToast: View {
    let title: String
    let undo: () -> Void

    var body: some View {
        HStack {
            Text("Removed “\(title)”")
                .lineLimit(1)
                .foregroundStyle(.white)
            Spacer()
            Button("Undo", action: undo)
                .fontWeight(.semibold)
                .foregroundStyle(Color(.volt))
        }
        .font(.subheadline)
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
        .background(Color(white: 0.15), in: .capsule)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}
