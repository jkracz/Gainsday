import Foundation

/// Copies of one workout recorded by several apps, e.g. the Apple Watch and Strava,
/// merged into one logical workout: same activity type, overlapping times, different
/// sources.
struct WorkoutCluster: Hashable, Sendable {
    /// The member whose values the event shows. Its UUID is the cluster's identity.
    var preferred: Workout
    /// Every member, the preferred one first.
    var members: [Workout]

    var memberIDs: Set<UUID> { Set(members.map(\.id)) }

    /// From the earliest member start to the latest member end.
    var interval: DateInterval {
        DateInterval(start: members.map(\.start).min()!, end: members.map(\.end).max()!)
    }

    /// Groups workouts into clusters, oldest first. A workout joins the first cluster
    /// with a member it's a copy of, unless its source already has a member there.
    static func clusters(of workouts: [Workout]) -> [WorkoutCluster] {
        var groups: [[Workout]] = []
        for workout in workouts.sorted(by: { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }) {
            if let index = groups.firstIndex(where: { $0.contains { $0.isCopy(of: workout) } && !$0.contains { $0.source.bundleIdentifier == workout.source.bundleIdentifier } }) {
                groups[index].append(workout)
            } else {
                groups.append([workout])
            }
        }
        return groups.map { group in
            let members = group.sorted(by: Workout.isPreferred)
            return WorkoutCluster(preferred: members[0], members: members)
        }
    }
}

extension Workout {
    /// Whether the two could be copies of the same workout recorded by different apps.
    func isCopy(of other: Workout) -> Bool {
        activityType == other.activityType && start < other.end && other.start < end
            && source.bundleIdentifier != other.source.bundleIdentifier
    }

    /// Whether `a` should supply a cluster's values over `b`: Apple's own copy
    /// (the Watch or the Fitness app) first, then the earliest start, then the
    /// lowest UUID, so every device picks the same one.
    static func isPreferred(_ a: Workout, over b: Workout) -> Bool {
        (a.source.isApple ? 0 : 1, a.start, a.id.uuidString) < (b.source.isApple ? 0 : 1, b.start, b.id.uuidString)
    }
}

extension WorkoutSourceApp {
    /// Apple Watch workouts come from `com.apple.health.<device UUID>`, iPhone ones
    /// from `com.apple.health` or Apple's other apps.
    var isApple: Bool {
        bundleIdentifier.hasPrefix("com.apple.")
    }
}

extension SyncEngine {
    /// The ledger entry for the cluster: one covering any member, or else one for an
    /// overlapping workout of the same type, i.e. a copy synced in an earlier pass.
    func existingEntry(for cluster: WorkoutCluster) async throws -> LedgerEntry? {
        for member in cluster.members {
            if let entry = try await resolvedEntry(forWorkout: member.id) {
                return entry
            }
        }
        let candidates = try await ledger.entries(in: cluster.interval)
            .sorted { ($0.workoutStart, $0.id.uuidString) < ($1.workoutStart, $1.id.uuidString) }
        for candidate in candidates {
            // Only a copy of a workout still in Health counts: the same app never records one workout twice.
            let synced = try await healthWorkouts(in: candidate)
            if synced.contains(where: { member in cluster.members.contains { $0.isCopy(of: member) } }),
               !synced.contains(where: { member in cluster.members.contains { $0.source.bundleIdentifier == member.source.bundleIdentifier } }) {
                return try await resolvedEntry(forWorkout: candidate.workoutID)
            }
        }
        return nil
    }

    /// The entry's cluster members that are still in Health.
    func healthWorkouts(in entry: LedgerEntry) async throws -> [Workout] {
        // Members overlap the entry's times, and a workout rarely lasts longer than a day.
        let window = DateInterval(start: entry.workoutStart.addingTimeInterval(-24 * 60 * 60), end: entry.workoutEnd)
        return try await workouts.workouts(in: window).filter { entry.covers($0.id) }
    }

    /// Records the cluster's members in the entry that already holds the workout, so
    /// a copy that arrives late never makes a second event. When the newcomer is
    /// preferred over every allowed member still in Health, e.g. the Watch's copy
    /// arriving after Strava's, it becomes the cluster's identity and the event shows
    /// its values.
    func join(_ cluster: WorkoutCluster, to entry: LedgerEntry, settings: Settings, composer: EventComposer) async throws -> SyncAction {
        var entry = try await correctExternalIdentifier(of: entry)
        let reason: SkipReason = entry.state == .tombstoned ? .tombstoned : .alreadySynced
        guard !cluster.memberIDs.isSubset(of: entry.memberIDs) else {
            return .skip(workoutID: cluster.preferred.id, reason)
        }
        let earlier = settings.splitBySource(try await healthWorkouts(in: entry)).allowed
        entry.memberIDs.formUnion(cluster.memberIDs)
        if cluster.preferred.id != entry.workoutID,
           earlier.allSatisfy({ Workout.isPreferred(cluster.preferred, over: $0) }) {
            entry.takeIdentity(from: cluster.preferred)
            return try await rewrite(entry, for: cluster.preferred, composer: composer)
        }
        entry.updatedAt = clock.now
        try await ledger.save(entry)
        return .skip(workoutID: cluster.preferred.id, reason)
    }
}

extension LedgerEntry {
    /// Makes the workout the cluster's identity, keeping every other member.
    mutating func takeIdentity(from workout: Workout) {
        workoutID = workout.id
        memberIDs.insert(workout.id)
        workoutStart = workout.start
        workoutEnd = workout.end
        activityType = workout.activityType
    }
}
