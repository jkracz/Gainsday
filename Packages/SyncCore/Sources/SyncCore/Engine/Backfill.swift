import Foundation

/// Fills in past workouts. A backfill goes through the same eligibility, dedupe and
/// create path as a changes pass, so repeating it creates nothing new.
extension SyncEngine {
    /// Syncs the workouts that started in `interval`. Choosing a backfill range opts in
    /// to it, so the sync start date moves back to the range's start if that's earlier.
    ///
    /// A preview runs the exact same pass against copies of the calendar and ledger that
    /// keep their writes to themselves. It writes nothing, and a commit straight after it
    /// takes the actions it listed. Only a commit is recorded in the activity log.
    func backfill(_ interval: DateInterval, mode: BackfillMode) async throws -> SyncResult {
        var settings = await settings.load()
        guard let destination = settings.destinationCalendar, let syncStartDate = settings.syncStartDate else {
            return SyncResult()
        }
        try await checkCalendar(destination)
        let found = try await workouts.workouts(in: interval)
        if interval.start < syncStartDate {
            settings.syncStartDate = interval.start
        }

        var engine = self
        switch mode {
        case .preview:
            engine.calendar = DryRunCalendarStore(calendar)
            engine.ledger = DryRunLedger(ledger)
        case .commit:
            if settings.syncStartDate != syncStartDate {
                await self.settings.save(settings)
            }
        }
        let composer = EventComposer(settings: settings, clock: clock)
        let result = SyncResult(actions: try await engine.syncAdded(found, to: destination.id, settings: settings, composer: composer))
        switch mode {
        case .preview:
            return result
        case .commit:
            return await notifyHeldWorkouts(in: ActivityRecorder(engine: self, added: found).record(result))
        }
    }

    /// Syncs workouts Health added, oldest first. Workouts from apps the allowlist
    /// leaves out are skipped, and copies of one workout recorded by several apps
    /// share one event.
    func syncAdded(_ added: [Workout], to calendarID: String, settings: Settings, composer: EventComposer) async throws -> [SyncAction] {
        let (allowed, notAllowed) = settings.splitBySource(added)
        var actions = notAllowed.sorted { $0.start < $1.start }.map { SyncAction.skip(workoutID: $0.id, .sourceNotAllowed) }
        for cluster in WorkoutCluster.clusters(of: allowed) {
            actions.append(try await sync(cluster, to: calendarID, settings: settings, composer: composer))
        }
        return actions
    }
}

/// A calendar for previews: reads come from the real calendar plus the events this
/// copy pretended to create, and writes never reach the real one.
private actor DryRunCalendarStore: CalendarStore {
    private let base: any CalendarStore
    private var created: [CalendarEvent] = []
    private var deletedIDs: Set<String> = []

    init(_ base: any CalendarStore) {
        self.base = base
    }

    func accessMode() async -> AccessMode {
        await base.accessMode()
    }

    func writableCalendars() async throws -> [CalendarInfo] {
        try await base.writableCalendars()
    }

    func events(in interval: DateInterval, calendarIDs: Set<String>) async throws -> [CalendarEvent] {
        // An event this copy updated is in `created`, so its real version is left out.
        let pretendIDs = Set(created.map(\.id))
        let real = try await base.events(in: interval, calendarIDs: calendarIDs).filter { !pretendIDs.contains($0.id) }
        let pretend = created.filter {
            calendarIDs.contains($0.calendarID) && $0.content.start < interval.end && $0.content.end > interval.start
        }
        return (real + pretend).filter { !deletedIDs.contains($0.id) }
    }

    func event(withID id: String) async throws -> CalendarEvent? {
        guard !deletedIDs.contains(id) else { return nil }
        if let event = created.first(where: { $0.id == id }) { return event }
        return try await base.event(withID: id)
    }

    func create(_ draft: EventDraft) async throws -> CalendarEvent {
        let event = CalendarEvent(id: "preview-\(created.count + 1)", calendarID: draft.calendarID, content: draft.content, availability: draft.availability)
        created.append(event)
        return event
    }

    func update(eventID: String, to content: EventContent) async throws -> CalendarEvent {
        guard var event = try await event(withID: eventID) else { throw CalendarStoreError.eventNotFound(id: eventID) }
        event.content = content
        created.removeAll { $0.id == eventID }
        created.append(event)
        return event
    }

    func delete(eventID: String) async throws {
        deletedIDs.insert(eventID)
    }

    func refreshSources() async {}

    func defaultCalendarID() async -> String? {
        await base.defaultCalendarID()
    }
}

/// A ledger for previews: the real entries overlaid with this copy's saves and deletes.
private actor DryRunLedger: Ledger {
    private let base: any Ledger
    /// Saved entries by id, or nil for a deleted one.
    private var overlay: [UUID: LedgerEntry?] = [:]

    init(_ base: any Ledger) {
        self.base = base
    }

    func entries(forWorkout workoutID: UUID) async throws -> [LedgerEntry] {
        overlaid(try await base.entries(forWorkout: workoutID)).filter { $0.covers(workoutID) }
    }

    func entries(in interval: DateInterval) async throws -> [LedgerEntry] {
        overlaid(try await base.entries(in: interval))
            .filter { $0.workoutStart < interval.end && $0.workoutEnd > interval.start }
    }

    func entriesNeedingLinking() async throws -> [LedgerEntry] {
        overlaid(try await base.entriesNeedingLinking()).filter(\.needsLinking)
    }

    func save(_ entry: LedgerEntry) async throws {
        overlay[entry.id] = .some(entry)
    }

    func delete(entryID: UUID) async throws {
        overlay[entryID] = .some(nil)
    }

    /// The real entries with this copy's changes applied, plus the entries it added.
    private func overlaid(_ real: [LedgerEntry]) -> [LedgerEntry] {
        let realIDs = Set(real.map(\.id))
        let changed = real.compactMap { entry in overlay[entry.id] ?? entry }
        let added = overlay.values.compactMap { $0 }.filter { !realIDs.contains($0.id) }
        return changed + added
    }
}
