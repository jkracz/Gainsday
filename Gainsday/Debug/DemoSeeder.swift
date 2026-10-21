#if DEBUG
import EventKit
import Foundation
import HealthKit
import os
import SyncCore
import UIKit

/// Debug builds only. Launching with `-seedDemoData` writes `DemoSeedPlan`'s workouts to
/// Health and its planned run to the "Calendar" calendar, and makes a "Workouts"
/// calendar to add them to. Seeding again replaces what the last run wrote.
///
/// Release builds have none of this: the app never writes to Health and never
/// creates calendars. Writing also needs the Health write usage string, which only
/// a demo build passes to xcodebuild: see `usageDescriptionKey`.
enum DemoSeeder {
    static let launchArgument = "-seedDemoData"
    /// Adds one more workout, ending now, and leaves everything else alone.
    static let workoutNowLaunchArgument = "-seedDemoWorkoutNow"
    /// Marks every sample the seeder writes, so the next run can delete them.
    static let markerKey = "GainsdayDemoSeed"
    static let workoutsCalendarTitle = "Workouts"
    private static let plannedEventIDKey = "demoSeedPlannedEventID"
    private static let log = Logger(subsystem: "app.gainsday.ios", category: "DemoSeeder")

    static func runIfRequested() async {
        if ProcessInfo.processInfo.arguments.contains(workoutNowLaunchArgument) {
            await addWorkoutEndingNow()
        }
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }
        let plan = DemoSeedPlan(now: Date())
        do {
            try await seedHealth(plan)
            try seedCalendar(plan)
            log.notice("Demo data seeded: \(plan.workouts.count) workouts, planned run at \(plan.plannedRun.start)")
        } catch {
            log.error("Demo seeding failed: \(error)")
        }
    }

    // MARK: Health

    private static let shareTypes: Set<HKSampleType> = [
        .workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceCycling),
    ]

    /// The write usage string isn't in the project, so no build ships it by accident.
    /// Demo builds pass it on the command line, and HealthKit crashes without it.
    static let usageDescriptionKey = "NSHealthUpdateUsageDescription"

    /// Asks only to write, so setup's Health step still asks to read.
    private static func seedHealth(_ plan: DemoSeedPlan) async throws {
        let store = try await authorizedStore()
        let marker = HKQuery.predicateForObjects(withMetadataKey: markerKey)
        for type in shareTypes {
            _ = try await store.deleteObjects(of: type, predicate: marker)
        }
        for spec in plan.workouts {
            try await save(spec, to: store)
        }
    }

    private static func addWorkoutEndingNow() async {
        do {
            let store = try await authorizedStore()
            try await save(DemoSeedPlan.workoutEndingNow(Date()), to: store)
            log.notice("Demo workout added, ending now")
        } catch {
            log.error("Demo workout not added: \(error)")
        }
    }

    struct CantWrite: Error, CustomStringConvertible {
        var description: String
    }

    private static func authorizedStore() async throws -> HKHealthStore {
        guard Bundle.main.object(forInfoDictionaryKey: usageDescriptionKey) != nil else {
            throw CantWrite(description: "build with INFOPLIST_KEY_\(usageDescriptionKey)=...")
        }
        let store = HKHealthStore()
        try await store.requestAuthorization(toShare: shareTypes, read: [])
        guard store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
            throw CantWrite(description: "writing workouts to Health wasn't allowed")
        }
        return store
    }

    /// Uses a workout builder, so the workout's statistics carry distance, energy and heart rate.
    private static func save(_ spec: DemoSeedPlan.WorkoutSpec, to store: HKHealthStore) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = HKWorkoutActivityType(rawValue: spec.activityType.rawValue) ?? .other
        configuration.locationType = spec.isIndoor ? .indoor : .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        let tag: [String: Any] = [markerKey: true]

        var samples = [HKQuantitySample(
            type: HKQuantityType(.activeEnergyBurned),
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: spec.activeEnergyKilocalories),
            start: spec.start, end: spec.end, metadata: tag
        )]
        if let distance = spec.distanceMeters {
            let type = HKQuantityType(spec.activityType == .cycling ? .distanceCycling : .distanceWalkingRunning)
            samples.append(HKQuantitySample(
                type: type, quantity: HKQuantity(unit: .meter(), doubleValue: distance),
                start: spec.start, end: spec.end, metadata: tag
            ))
        }
        // One reading a minute, wandering around the average.
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let minutes = Int(spec.end.timeIntervalSince(spec.start) / 60)
        for minute in 0..<minutes {
            let time = spec.start.addingTimeInterval(Double(minute) * 60 + 30)
            let value = spec.averageHeartRate + 9 * sin(Double(minute) / 4)
            samples.append(HKQuantitySample(
                type: HKQuantityType(.heartRate), quantity: HKQuantity(unit: bpm, doubleValue: value.rounded()),
                start: time, end: time, metadata: tag
            ))
        }

        var metadata = tag
        if let climb = spec.elevationAscendedMeters {
            metadata[HKMetadataKeyElevationAscended] = HKQuantity(unit: .meter(), doubleValue: climb)
        }
        try await builder.beginCollection(at: spec.start)
        try await builder.addSamples(samples)
        try await builder.addMetadata(metadata)
        try await builder.endCollection(at: spec.end)
        _ = try await builder.finishWorkout()
    }

    // MARK: Calendar

    /// Needs full calendar access, which `xcrun simctl privacy <udid> grant calendar
    /// app.gainsday.ios` gives without a prompt.
    private static func seedCalendar(_ plan: DemoSeedPlan) throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            log.error("Demo calendar seeding skipped: grant full calendar access first")
            return
        }
        let store = EKEventStore()
        try makeWorkoutsCalendar(in: store)

        if let previousID = UserDefaults.standard.string(forKey: plannedEventIDKey),
           let previous = store.event(withIdentifier: previousID) {
            try store.remove(previous, span: .thisEvent, commit: true)
        }
        let planned = store.calendars(for: .event).first { $0.title == "Calendar" && $0.allowsContentModifications }
            ?? store.defaultCalendarForNewEvents
        let event = EKEvent(eventStore: store)
        event.calendar = planned
        event.title = plan.plannedRun.title
        event.notes = "Easy 5k, keep it conversational."
        event.startDate = plan.plannedRun.start
        event.endDate = plan.plannedRun.end
        try store.save(event, span: .thisEvent, commit: true)
        UserDefaults.standard.set(event.eventIdentifier, forKey: plannedEventIDKey)
    }

    /// The app never creates calendars. This Debug-only path makes the calendar a
    /// user would make in the Calendar app, so the demo can choose it.
    private static func makeWorkoutsCalendar(in store: EKEventStore) throws {
        guard !store.calendars(for: .event).contains(where: { $0.title == workoutsCalendarTitle }),
              let local = store.sources.first(where: { $0.sourceType == .local }) else { return }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = workoutsCalendarTitle
        calendar.source = local
        calendar.cgColor = UIColor.systemOrange.cgColor
        try store.saveCalendar(calendar, commit: true)
    }
}
#endif
