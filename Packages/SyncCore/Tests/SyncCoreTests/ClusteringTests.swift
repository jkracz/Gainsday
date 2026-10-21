import Foundation
import SyncCore
import SyncCoreTesting
import Testing

@Suite("Clustering")
struct ClusteringTests {
    @Test("Watch and Strava copies of one run make a single event with the Watch's values")
    func watchAndStravaMakeOneEvent() async throws {
        let watchRun = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let stravaRun = SyncHarness.stravaCopy(of: watchRun)
        let harness = SyncHarness(workouts: [stravaRun, watchRun])

        let result = try await harness.engine.run(.changes(since: nil))

        let event = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(event.content.start == watchRun.start)
        #expect(event.content.end == watchRun.end)
        #expect(event.content.notes?.contains("3.11 mi") == true) // the Watch's 5 km, not Strava's 5.12
        #expect(event.content.notes?.hasSuffix(watchRun.shortID) == true)
        #expect(result.actions.count == 1)
        guard case .create(let workoutID, _) = result.actions.first else {
            Issue.record("Expected a create, got \(result.actions)")
            return
        }
        #expect(workoutID == watchRun.id)
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.workoutID == watchRun.id)
        #expect(entry.memberIDs == [watchRun.id, stravaRun.id])
    }

    @Test("A Strava copy arriving in a later pass adds nothing and joins the Watch's cluster")
    func lateStravaCopyAddsNothing() async throws {
        let watchRun = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let harness = SyncHarness(workouts: [watchRun])
        let first = try await harness.engine.run(.changes(since: nil))
        let event = try #require(await harness.calendar.allEvents.first)

        let stravaRun = SyncHarness.stravaCopy(of: watchRun)
        await harness.workouts.add(stravaRun)
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        #expect(second.actions == [.skip(workoutID: stravaRun.id, .alreadySynced)])
        #expect(await harness.calendar.allEvents == [event])
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.workoutID == watchRun.id)
        #expect(entry.memberIDs == [watchRun.id, stravaRun.id])
    }

    @Test("With a Strava-only allowlist, the Watch copy is ignored and the event shows Strava's values")
    func stravaOnlyAllowlistIgnoresWatch() async throws {
        let watchRun = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let stravaRun = SyncHarness.stravaCopy(of: watchRun)
        var settings = SyncHarness.defaultSettings
        settings.sourceAllowlist = [SyncHarness.strava.bundleIdentifier]
        let harness = SyncHarness(workouts: [watchRun, stravaRun], settings: settings)

        let result = try await harness.engine.run(.changes(since: nil))

        let event = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(event.content.start == stravaRun.start)
        #expect(event.content.notes?.contains("3.18 mi") == true) // Strava's 5.12 km
        #expect(event.content.notes?.hasSuffix(stravaRun.shortID) == true)
        #expect(result.actions.first == .skip(workoutID: watchRun.id, .sourceNotAllowed))
        #expect(result.actions.count == 2)
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(entry.workoutID == stravaRun.id)
        #expect(entry.covers(watchRun.id) == false)
    }

    @Test("A Watch copy the allowlist leaves out never replaces a deleted Strava workout's event")
    func disallowedCopyIsNotAReplacement() async throws {
        let watchRun = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let stravaRun = SyncHarness.stravaCopy(of: watchRun)
        var settings = SyncHarness.defaultSettings
        settings.sourceAllowlist = [SyncHarness.strava.bundleIdentifier]
        let harness = SyncHarness(workouts: [stravaRun], settings: settings)
        let first = try await harness.engine.run(.changes(since: nil))
        let event = try #require(await harness.calendar.allEvents.first)

        await harness.workouts.delete(stravaRun.id)
        await harness.workouts.add(watchRun)
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        #expect(second.actions == [
            .skip(workoutID: watchRun.id, .sourceNotAllowed),
            .delete(workoutID: stravaRun.id, eventID: event.id),
        ])
        #expect(await harness.calendar.allEvents.isEmpty)
    }
}

extension SyncHarness {
    static let strava = WorkoutSourceApp(bundleIdentifier: "com.strava.stravaride", name: "Strava")

    /// Strava's copy of a workout: it starts and ends a little later and measures a different distance.
    static func stravaCopy(of workout: Workout) -> Workout {
        Workout(
            activityType: workout.activityType,
            start: workout.start.addingTimeInterval(20),
            end: workout.end.addingTimeInterval(45),
            source: strava,
            metrics: WorkoutMetrics(distanceMeters: 5_120, averageHeartRate: 148)
        )
    }
}
