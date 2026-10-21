import Foundation

/// Runs sync passes: reads workouts, decides what to write, writes it through the
/// ports and reports every action taken or planned.
public struct SyncEngine: Sendable {
    public var workouts: any WorkoutSource
    public var calendar: any CalendarStore
    public var ledger: any Ledger
    public var settings: any SettingsStore
    public var judge: any MatchJudge
    public var clock: any Clock
    public var notifier: any ProblemNotifier
    public var activityLog: any ActivityLogStore

    public init(
        workouts: any WorkoutSource,
        calendar: any CalendarStore,
        ledger: any Ledger,
        settings: any SettingsStore,
        judge: any MatchJudge,
        clock: any Clock,
        notifier: any ProblemNotifier,
        activityLog: any ActivityLogStore
    ) {
        self.workouts = workouts
        self.calendar = calendar
        self.ledger = ledger
        self.settings = settings
        self.judge = judge
        self.clock = clock
        self.notifier = notifier
        self.activityLog = activityLog
    }

    /// Runs one sync pass.
    ///
    /// The sync rules are added feature by feature. For now a changes pass first follows
    /// Health deletes and replacements (see `followDeletions`), then creates an owned
    /// event for each new workout since the sync start date that the ledger doesn't
    /// know yet. Backfill syncs the workouts in its range the same way (see `backfill`).
    /// The actions of a changes pass or a backfill commit are recorded in the activity
    /// log (see `ActivityRecorder`).
    public func run(_ trigger: SyncTrigger) async throws -> SyncResult {
        switch trigger {
        case .changes(let anchor):
            let settings = await settings.load()
            guard let destination = settings.destinationCalendar, settings.syncStartDate != nil else {
                // Setup isn't finished: leave Health unread so the anchor doesn't move.
                return SyncResult()
            }
            try await checkCalendar(destination)
            let changes = try await readChanges(since: anchor)
            let recorder = try await ActivityRecorder(engine: self, added: changes.added, deletedIDs: changes.deletedIDs)
            let composer = EventComposer(settings: settings, clock: clock)
            let followed = try await followDeletions(in: changes, settings: settings, composer: composer)
            let added = try await syncAdded(followed.remaining, to: destination.id, settings: settings, composer: composer)
            return await recorder.record(SyncResult(actions: followed.actions + added, nextAnchor: changes.anchor))
        case .backfill(let interval, let mode):
            return try await backfill(interval, mode: mode)
        }
    }

    func sync(_ workout: Workout, to calendarID: String, settings: Settings, composer: EventComposer) async throws -> SyncAction {
        if let reason = settings.skipReason(for: workout) {
            return .skip(workoutID: workout.id, reason)
        }
        if let entry = try await resolvedEntry(forWorkout: workout.id) {
            try await correctExternalIdentifier(of: entry)
            return .skip(workoutID: workout.id, entry.state == .tombstoned ? .tombstoned : .alreadySynced)
        }
        if let relinked = try await relinkEarlierEvent(for: workout, in: calendarID, composer: composer) {
            return relinked
        }

        let draft = EventDraft(calendarID: calendarID, content: composer.content(for: workout), availability: .free)
        let event = try await createEvent(draft)
        let now = clock.now
        do {
            try await ledger.save(LedgerEntry(
                workoutID: workout.id,
                workoutStart: workout.start,
                workoutEnd: workout.end,
                state: .owned,
                eventExternalIdentifier: event.id,
                calendarID: event.calendarID,
                written: event.content,
                createdAt: now,
                updatedAt: now,
                activityType: workout.activityType
            ))
        } catch {
            // An event with no ledger entry would be created again next pass, so undo it
            // when possible. The save error is the one worth reporting.
            try? await calendar.delete(eventID: event.id)
            throw error
        }
        return .create(workoutID: workout.id, draft)
    }
}
