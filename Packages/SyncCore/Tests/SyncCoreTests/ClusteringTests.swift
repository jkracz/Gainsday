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

    @Test("A Watch copy arriving after Strava's updates the event in place with the Watch's values")
    func lateWatchCopyTakesOverEvent() async throws {
        let watchRun = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let stravaRun = SyncHarness.stravaCopy(of: watchRun)
        let harness = SyncHarness(workouts: [stravaRun])
        let first = try await harness.engine.run(.changes(since: nil))
        let event = try #require(await harness.calendar.allEvents.first)

        await harness.workouts.add(watchRun)
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        let updated = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(updated.id == event.id)
        #expect(updated.content.start == watchRun.start)
        #expect(updated.content.notes?.contains("3.11 mi") == true)
        #expect(updated.content.notes?.hasSuffix(watchRun.shortID) == true)
        #expect(second.actions == [.update(workoutID: watchRun.id, eventID: event.id, updated.content)])
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.workoutID == watchRun.id)
        #expect(entry.memberIDs == [watchRun.id, stravaRun.id])
        #expect(entry.workoutStart == watchRun.start)
        #expect(entry.written == updated.content)
    }

    @Test("A late Watch copy leaves an event the user edited alone and releases it")
    func lateWatchCopyReleasesEditedEvent() async throws {
        let watchRun = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let stravaRun = SyncHarness.stravaCopy(of: watchRun)
        let harness = SyncHarness(workouts: [stravaRun])
        let first = try await harness.engine.run(.changes(since: nil))
        var edited = try #require(await harness.calendar.allEvents.first)
        edited.content.title = "Tempo run with Sam"
        await harness.calendar.put(edited)

        await harness.workouts.add(watchRun)
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        #expect(second.actions == [.release(workoutID: watchRun.id, eventID: edited.id)])
        #expect(await harness.calendar.allEvents == [edited])
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(entry.state == .released)
        #expect(entry.memberIDs == [watchRun.id, stravaRun.id])
    }

    @Test("Deleting the Watch copy in Health rewrites the event with the Strava copy that's left")
    func deletingPreferredCopyRewritesEvent() async throws {
        let watchRun = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let stravaRun = SyncHarness.stravaCopy(of: watchRun)
        let harness = SyncHarness(workouts: [watchRun, stravaRun])
        let first = try await harness.engine.run(.changes(since: nil))
        let event = try #require(await harness.calendar.allEvents.first)

        await harness.workouts.delete(watchRun.id)
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        let updated = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(updated.id == event.id)
        #expect(updated.content.start == stravaRun.start)
        #expect(updated.content.notes?.contains("3.18 mi") == true)
        #expect(updated.content.notes?.hasSuffix(stravaRun.shortID) == true)
        #expect(second.actions == [.update(workoutID: stravaRun.id, eventID: event.id, updated.content)])
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(entry.workoutID == stravaRun.id)
        #expect(entry.memberIDs == [stravaRun.id])
        #expect(entry.written == updated.content)
    }

    @Test("Deleting the Strava copy in Health leaves the Watch's event as it is")
    func deletingOtherCopyKeepsEvent() async throws {
        let watchRun = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let stravaRun = SyncHarness.stravaCopy(of: watchRun)
        let harness = SyncHarness(workouts: [watchRun, stravaRun])
        let first = try await harness.engine.run(.changes(since: nil))
        let event = try #require(await harness.calendar.allEvents.first)

        await harness.workouts.delete(stravaRun.id)
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        #expect(second.actions.isEmpty)
        #expect(await harness.calendar.allEvents == [event])
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(entry.workoutID == watchRun.id)
        #expect(entry.memberIDs == [watchRun.id])
    }

    @Test("After a reinstall, an event whose footer names the Strava copy is re-linked to the cluster, not duplicated")
    func reinstallFindsFooterOfAnyMember() async throws {
        let watchRun = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let stravaRun = SyncHarness.stravaCopy(of: watchRun, lateBy: 3 * 60)
        let earlier = try await SyncHarness.eventLeftByEarlierInstall(for: stravaRun)
        let harness = SyncHarness(workouts: [watchRun, stravaRun])
        await harness.calendar.put(earlier)

        let result = try await harness.engine.run(.changes(since: nil))

        #expect(result.actions == [.relink(workoutID: watchRun.id, eventID: earlier.id)])
        #expect(await harness.calendar.allEvents == [earlier])
        let entry = try #require(await harness.ledger.allEntries.first)
        #expect(await harness.ledger.allEntries.count == 1)
        #expect(entry.workoutID == watchRun.id)
        #expect(entry.memberIDs == [watchRun.id, stravaRun.id])
        #expect(entry.activityType == .running)
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

    @Test("After switching to a Strava-only allowlist, a late Strava copy takes over the Watch's event")
    func allowedLateCopyTakesOverFromDisallowedOne() async throws {
        let watchRun = SyncHarness.run(minutes: 30, minutesAgo: 10)
        let harness = SyncHarness(workouts: [watchRun])
        let first = try await harness.engine.run(.changes(since: nil))
        let event = try #require(await harness.calendar.allEvents.first)
        var settings = SyncHarness.defaultSettings
        settings.sourceAllowlist = [SyncHarness.strava.bundleIdentifier]
        await harness.settings.save(settings)

        let stravaRun = SyncHarness.stravaCopy(of: watchRun)
        await harness.workouts.add(stravaRun)
        let second = try await harness.engine.run(.changes(since: first.nextAnchor))

        let updated = try #require(await harness.calendar.allEvents.first)
        #expect(await harness.calendar.allEvents.count == 1)
        #expect(updated.id == event.id)
        #expect(updated.content.notes?.hasSuffix(stravaRun.shortID) == true)
        #expect(second.actions == [.update(workoutID: stravaRun.id, eventID: event.id, updated.content)])
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
    static func stravaCopy(of workout: Workout, lateBy delay: TimeInterval = 20) -> Workout {
        Workout(
            activityType: workout.activityType,
            start: workout.start.addingTimeInterval(delay),
            end: workout.end.addingTimeInterval(delay + 25),
            source: strava,
            metrics: WorkoutMetrics(distanceMeters: 5_120, averageHeartRate: 148)
        )
    }
}
