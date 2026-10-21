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

    public init(
        workouts: any WorkoutSource,
        calendar: any CalendarStore,
        ledger: any Ledger,
        settings: any SettingsStore,
        judge: any MatchJudge,
        clock: any Clock,
        notifier: any ProblemNotifier
    ) {
        self.workouts = workouts
        self.calendar = calendar
        self.ledger = ledger
        self.settings = settings
        self.judge = judge
        self.clock = clock
        self.notifier = notifier
    }

    /// Runs one sync pass.
    ///
    /// The sync rules are added feature by feature. For now a changes pass first follows
    /// Health deletes and replacements (see `followDeletions`), then creates an owned
    /// event for each new workout since the sync start date that the ledger doesn't
    /// know yet. Backfill reads its inputs and takes no actions.
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
            let composer = EventComposer(settings: settings, clock: clock)
            let (allowed, notAllowed) = settings.splitBySource(changes.added)
            var actions = notAllowed.map { SyncAction.skip(workoutID: $0.id, .sourceNotAllowed) }
            let followed = try await followDeletions(
                in: WorkoutChanges(added: allowed, deletedIDs: changes.deletedIDs, anchor: changes.anchor),
                settings: settings,
                composer: composer
            )
            actions += followed.actions
            for cluster in WorkoutCluster.clusters(of: followed.remaining) {
                actions.append(try await sync(cluster, to: destination.id, settings: settings, composer: composer))
            }
            return SyncResult(actions: actions, nextAnchor: changes.anchor)
        case .backfill(let interval, _):
            _ = try await workouts.workouts(in: interval)
            return SyncResult(actions: [])
        }
    }

    private func sync(_ cluster: WorkoutCluster, to calendarID: String, settings: Settings, composer: EventComposer) async throws -> SyncAction {
        let workout = cluster.preferred
        if let reason = settings.skipReason(for: workout) {
            return .skip(workoutID: workout.id, reason)
        }
        if let entry = try await existingEntry(for: cluster) {
            return try await join(cluster, to: entry, settings: settings, composer: composer)
        }
        if let relinked = try await relinkEarlierEvent(for: cluster, in: calendarID, composer: composer) {
            return relinked
        }

        let draft = EventDraft(calendarID: calendarID, content: composer.content(for: workout), availability: .free)
        let event = try await createEvent(draft)
        let now = clock.now
        do {
            try await ledger.save(LedgerEntry(
                workoutID: workout.id,
                memberIDs: cluster.memberIDs,
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
