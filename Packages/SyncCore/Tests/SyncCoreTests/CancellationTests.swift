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
}

/// A calendar that cancels the pass using it as soon as it has created an event, the
/// way background expiry can arrive at any point.
private struct CancellingCalendarStore: CalendarStore {
    let base: InMemoryCalendarStore

    init(_ base: InMemoryCalendarStore) {
        self.base = base
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
    func delete(eventID: String) async throws { try await base.delete(eventID: eventID) }
    func refreshSources() async { await base.refreshSources() }
    func defaultCalendarID() async -> String? { await base.defaultCalendarID() }

    func create(_ draft: EventDraft) async throws -> CalendarEvent {
        let event = try await base.create(draft)
        withUnsafeCurrentTask { $0?.cancel() }
        return event
    }
}
