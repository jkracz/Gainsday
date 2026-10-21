import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Sync runner")
struct SyncRunnerTests {
    @Test("A background pass and a foreground pass that overlap create one event")
    func overlappingPassesCreateOneEvent() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        let health = GatedWorkoutSource(harness.workouts)
        let runner = harness.runner(reading: health)

        async let background = runner.syncChanges()
        await health.waitForReaders(1)
        async let foreground = runner.syncChanges()
        try await Task.sleep(for: .milliseconds(50))
        await health.open()
        _ = try await (background, foreground)

        let events = await harness.calendar.allEvents
        let entries = await harness.ledger.allEntries
        let mostConcurrentReads = await health.mostConcurrentReads
        #expect(events.count == 1)
        #expect(entries.count == 1)
        #expect(mostConcurrentReads == 1)
    }

    @Test("Wakes that arrive during a pass share one later pass, which picks up the workout that woke them")
    func wakesDuringAPassShareOneLaterPass() async throws {
        let first = SyncHarness.run(minutesAgo: 60)
        let late = SyncHarness.run(minutesAgo: 1)
        let harness = SyncHarness(workouts: [first])
        let health = GatedWorkoutSource(harness.workouts)
        let runner = harness.runner(reading: health)

        async let appOpen = runner.syncChanges()
        await health.waitForReaders(1)
        await harness.workouts.add(late)
        async let wake = runner.syncChanges()
        async let repeatedWake = runner.syncChanges()
        try await Task.sleep(for: .milliseconds(50))
        await health.open()
        _ = try await (appOpen, wake, repeatedWake)

        let events = await harness.calendar.allEvents
        let readCount = await health.readCount
        #expect(events.map(\.content.start) == [first.start, late.start])
        #expect(readCount == 2)
    }

    @Test("A backfill that overlaps a background pass waits for it, so the workout gets one event")
    func backfillWaitsForRunningPass() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        let health = GatedWorkoutSource(harness.workouts)
        let runner = harness.runner(reading: health)

        async let background = runner.syncChanges()
        await health.waitForReaders(1)
        async let backfill = runner.backfill(SyncHarness.lastDays(1), mode: .commit)
        try await Task.sleep(for: .milliseconds(50))
        await health.open()
        let backfillResult = try await backfill
        _ = try await background

        let events = await harness.calendar.allEvents
        #expect(events.count == 1)
        #expect(backfillResult.actions == [.skip(workoutID: workout.id, .alreadySynced)])
    }

    @Test("An undo waits for a running pass, then sticks")
    func undoWaitsForRunningPass() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        _ = try await harness.engine.run(.changes(since: nil))
        let entry = try #require(await harness.activityLog.entries.first)
        let health = GatedWorkoutSource(harness.workouts)
        let runner = harness.runner(reading: health)

        async let background = runner.syncChanges()
        await health.waitForReaders(1)
        async let undo = runner.undo(entryID: entry.id)
        try await Task.sleep(for: .milliseconds(50))
        let eventsDuringPass = await harness.calendar.allEvents
        await health.open()
        _ = try await (background, undo)

        let events = await harness.calendar.allEvents
        let states = await harness.ledger.allEntries.map(\.state)
        #expect(eventsDuringPass.count == 1)
        #expect(events.isEmpty)
        #expect(states == [.tombstoned])
    }

    @Test("Listing the events a workout can be matched to waits for a running pass, since it can fix the ledger")
    func matchCandidatesWaitForRunningPass() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        _ = try await harness.engine.run(.changes(since: nil))
        let entry = try #require(await harness.activityLog.entries.first)
        let health = GatedWorkoutSource(harness.workouts)
        let runner = harness.runner(reading: health)

        async let background = runner.syncChanges()
        await health.waitForReaders(1)
        let listed = Flag()
        let candidates = Task {
            _ = try await runner.matchCandidates(forEntryID: entry.id)
            await listed.set()
        }
        try await Task.sleep(for: .milliseconds(50))
        let listedDuringPass = await listed.isSet
        await health.open()
        _ = try await (background, candidates.value)

        #expect(listedDuringPass == false)
        #expect(await listed.isSet)
    }

    @Test("A pass while the phone is locked keeps the anchor and notifies nothing, so the pass after unlock syncs the workout")
    func lockedPassIsFinishedAfterUnlock() async throws {
        let workout = SyncHarness.run()
        let harness = SyncHarness(workouts: [workout])
        let anchors = InMemoryAnchorStore()
        let runner = harness.runner(reading: harness.workouts, anchors: anchors)
        await harness.workouts.setLocked(true)

        await #expect(throws: WorkoutSourceError.locked) { try await runner.syncChanges() }
        let anchorWhileLocked = await anchors.anchor
        let notified = await harness.notifier.notifiedProblems()
        #expect(anchorWhileLocked == nil)
        #expect(notified.isEmpty)

        await harness.workouts.setLocked(false)
        _ = try await runner.syncChanges()

        let events = await harness.calendar.allEvents
        #expect(events.map(\.content.start) == [workout.start])
    }
}

extension SyncHarness {
    /// A runner over this harness's fakes, reading Health through `health`.
    func runner(reading health: any WorkoutSource, anchors: InMemoryAnchorStore = InMemoryAnchorStore()) -> SyncRunner {
        var engine = engine
        engine.workouts = health
        return SyncRunner(engine: engine, anchors: anchors)
    }
}

/// Holds every Health read until `open()`, so a test can start a second pass while
/// the first is still reading.
actor GatedWorkoutSource: WorkoutSource {
    private let source: InMemoryWorkoutSource
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var readers = 0
    private(set) var mostConcurrentReads = 0
    private(set) var readCount = 0

    init(_ source: InMemoryWorkoutSource) {
        self.source = source
    }

    /// Lets held and later reads through.
    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }

    /// Returns once `count` reads are held at the gate.
    func waitForReaders(_ count: Int) async {
        while waiting.count < count {
            await Task.yield()
        }
    }

    func changes(since anchor: WorkoutAnchor?) async throws -> WorkoutChanges {
        readers += 1
        readCount += 1
        mostConcurrentReads = max(mostConcurrentReads, readers)
        defer { readers -= 1 }
        if !isOpen {
            await withCheckedContinuation { waiting.append($0) }
        }
        return try await source.changes(since: anchor)
    }

    func workouts(in interval: DateInterval) async throws -> [Workout] {
        try await source.workouts(in: interval)
    }

    func recentWorkouts(limit: Int) async throws -> [Workout] {
        try await source.recentWorkouts(limit: limit)
    }
}

private actor Flag {
    private(set) var isSet = false

    func set() {
        isSet = true
    }
}
