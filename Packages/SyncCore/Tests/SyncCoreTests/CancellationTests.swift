import Foundation
import SyncCore
import SyncCoreTesting
import Testing

/// A background task that runs out of time cancels its pass. The pass has to stop
/// before the system ends the app, but never between an event and its ledger entry.
@Suite("Cancelling a pass")
struct CancellationTests {
    @Test("A pass cancelled while adding a workout finishes that workout, with its ledger entry, and adds no more")
    func stopsBetweenWorkouts() async throws {
        let harness = SyncHarness(workouts: [SyncHarness.run(minutesAgo: 120), SyncHarness.run(minutesAgo: 10)])
        var engine = harness.engine
        engine.calendar = CancellingCalendarStore(harness.calendar)

        let pass = Task { try await engine.run(.changes(since: nil)) }
        let result = await pass.result

        #expect(throws: CancellationError.self) { try result.get() }
        let events = await harness.calendar.allEvents
        #expect(events.count == 1)
        #expect(await harness.ledger.allEntries.map(\.eventExternalIdentifier) == events.map(\.id))
    }

    @Test("A cancelled backfill adds nothing after the workout it was adding")
    func backfillStopsBetweenWorkouts() async throws {
        let harness = SyncHarness(workouts: [SyncHarness.run(minutesAgo: 120), SyncHarness.run(minutesAgo: 10)])
        var engine = harness.engine
        engine.calendar = CancellingCalendarStore(harness.calendar)
        let day = DateInterval(start: SyncHarness.now.addingTimeInterval(-24 * 60 * 60), end: SyncHarness.now)

        let backfill = Task { try await engine.run(.backfill(day, .commit)) }
        let result = await backfill.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(await harness.ledger.allEntries.count == 1)
    }

    @Test("Cancelling the caller of a runner pass cancels the pass, which writes nothing and keeps the anchor")
    func runnerForwardsCancellation() async throws {
        let harness = SyncHarness(workouts: [SyncHarness.run()])
        let health = GatedWorkoutSource(harness.workouts)
        let anchors = InMemoryAnchorStore()
        let runner = harness.runner(reading: health, anchors: anchors)

        let caller = Task { try await runner.syncChanges() }
        await health.waitForReaders(1)
        caller.cancel()
        await health.open()
        let result = await caller.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(await harness.calendar.allEvents.isEmpty)
        #expect(await anchors.anchor == nil)
    }

    @Test("A cancelled pass logs the workout it finished, with its Undo, and a retry logs the rest")
    func cancelledPassLogsFinishedWork() async throws {
        let harness = SyncHarness(workouts: [SyncHarness.run(minutesAgo: 120), SyncHarness.run(minutesAgo: 10)])
        var engine = harness.engine
        engine.calendar = CancellingCalendarStore(harness.calendar)

        let result = await Task { try await engine.run(.changes(since: nil)) }.result
        #expect(throws: CancellationError.self) { try result.get() }
        var log = await harness.activityLog.entries
        let created = await harness.calendar.allEvents
        #expect(log.count == 1)
        #expect(log.first?.undo == .removeCreatedEvent)
        #expect(log.first?.eventID == created.first?.id)

        _ = try await harness.engine.run(.changes(since: nil))
        log = await harness.activityLog.entries
        #expect(await harness.calendar.allEvents.count == 2)
        #expect(log.count == 2)
        #expect(log.allSatisfy { if case .create = $0.action { $0.canUndo } else { false } })
    }

    @Test("A cancelled backfill logs the workout it finished, with its Undo")
    func cancelledBackfillLogsFinishedWork() async throws {
        let harness = SyncHarness(workouts: [SyncHarness.run(minutesAgo: 120), SyncHarness.run(minutesAgo: 10)])
        var engine = harness.engine
        engine.calendar = CancellingCalendarStore(harness.calendar)
        let day = DateInterval(start: SyncHarness.now.addingTimeInterval(-24 * 60 * 60), end: SyncHarness.now)

        let result = await Task { try await engine.run(.backfill(day, .commit)) }.result

        #expect(throws: CancellationError.self) { try result.get() }
        let log = await harness.activityLog.entries
        #expect(log.count == 1)
        #expect(log.first?.undo == .removeCreatedEvent)
    }

    @Test("A pass cancelled while following Health deletes finishes that workout, logs it, and deletes no more")
    func stopsBetweenDeletions() async throws {
        let workouts = [SyncHarness.run(minutesAgo: 120), SyncHarness.run(minutesAgo: 10)]
        let harness = SyncHarness(workouts: workouts)
        let first = try await harness.engine.run(.changes(since: nil))
        for workout in workouts {
            await harness.workouts.delete(workout.id)
        }
        var engine = harness.engine
        engine.calendar = CancellingCalendarStore(harness.calendar, cancelsAfter: .delete)

        let result = await Task { try await engine.run(.changes(since: first.nextAnchor)) }.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(await harness.ledger.allEntries.count == 1)
        let log = await harness.activityLog.entries
        guard case .delete = log.first?.action else {
            Issue.record("Expected the finished delete to be logged first, got \(log.map(\.action))")
            return
        }
        #expect(log.first?.canUndo == true)
    }

    @Test("A pass cancelled while catching up add-only Health deletes after upgrading finishes that workout, logs it, and deletes no more")
    func stopsBetweenAddOnlyFollowUps() async throws {
        let workouts = [SyncHarness.run(minutesAgo: 120), SyncHarness.run(minutesAgo: 10)]
        let harness = SyncHarness(workouts: workouts, accessMode: .addOnly)
        let first = try await harness.engine.run(.changes(since: nil))
        for workout in workouts {
            await harness.workouts.delete(workout.id)
        }
        let skipped = try await harness.engine.run(.changes(since: first.nextAnchor))
        await harness.calendar.setAccessMode(.full)
        var engine = harness.engine
        engine.calendar = CancellingCalendarStore(harness.calendar, cancelsAfter: .delete)

        let result = await Task { try await engine.run(.changes(since: skipped.nextAnchor)) }.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(await harness.ledger.allEntries.count == 1)
        guard case .delete = await harness.activityLog.entries.first?.action else {
            Issue.record("Expected the finished delete to be logged first")
            return
        }
    }
}

/// A calendar that cancels the pass using it as soon as it has created an event, or
/// deleted one, the way background expiry can arrive at any point.
private struct CancellingCalendarStore: CalendarStore {
    enum Write { case create, delete }

    let base: InMemoryCalendarStore
    let cancelsAfter: Write

    init(_ base: InMemoryCalendarStore, cancelsAfter: Write = .create) {
        self.base = base
        self.cancelsAfter = cancelsAfter
    }

    func accessMode() async -> AccessMode { await base.accessMode() }
    func writableCalendars() async throws -> [CalendarInfo] { try await base.writableCalendars() }
    func events(in interval: DateInterval, calendarIDs: Set<String>) async throws -> [CalendarEvent] {
        try await base.events(in: interval, calendarIDs: calendarIDs)
    }
    func event(withID id: String) async throws -> CalendarEvent? { try await base.event(withID: id) }
    func update(eventID: String, to content: EventContent) async throws -> CalendarEvent {
        try await base.update(eventID: eventID, to: content)
    }
    func refreshSources() async { await base.refreshSources() }
    func defaultCalendarID() async -> String? { await base.defaultCalendarID() }

    func create(_ draft: EventDraft) async throws -> CalendarEvent {
        let event = try await base.create(draft)
        if cancelsAfter == .create {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return event
    }

    func delete(eventID: String) async throws {
        try await base.delete(eventID: eventID)
        if cancelsAfter == .delete {
            withUnsafeCurrentTask { $0?.cancel() }
        }
    }
}
