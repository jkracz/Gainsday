#if DEBUG
import Foundation
import SyncCore

/// Debug builds only. What `-seedDemoData` writes for a demo, relative to now, so
/// a recording always shows a recent week: workouts over the past ten days, one of
/// them finishing today, and a planned "Run" event that today's run matches.
struct DemoSeedPlan: Equatable {
    struct WorkoutSpec: Equatable {
        var activityType: WorkoutActivityType
        var isIndoor = false
        var start: Date
        var end: Date
        var distanceMeters: Double?
        var activeEnergyKilocalories: Double
        var averageHeartRate: Double
        var elevationAscendedMeters: Double?
    }

    struct PlannedEventSpec: Equatable {
        var title: String
        var start: Date
        var end: Date
    }

    /// Oldest first. The last one finishes today.
    let workouts: [WorkoutSpec]
    /// Overlaps today's run, so matching updates it instead of adding a separate event.
    let plannedRun: PlannedEventSpec

    init(now: Date, calendar: Calendar = .current) {
        func at(daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        func workout(
            _ type: WorkoutActivityType, daysAgo: Int, at hour: Int, _ minute: Int, minutes: Double,
            km: Double? = nil, kcal: Double, bpm: Double, climb: Double? = nil, indoor: Bool = false
        ) -> WorkoutSpec {
            let start = at(daysAgo: daysAgo, hour, minute)
            return WorkoutSpec(
                activityType: type, isIndoor: indoor, start: start, end: start.addingTimeInterval(minutes * 60),
                distanceMeters: km.map { $0 * 1000 }, activeEnergyKilocalories: kcal, averageHeartRate: bpm,
                elevationAscendedMeters: climb
            )
        }

        // Today's run finishes a few minutes before seeding, so it's already in Health.
        let todayEnd = now.addingTimeInterval(-10 * 60)
        let today = WorkoutSpec(
            activityType: .running, start: todayEnd.addingTimeInterval(-32 * 60), end: todayEnd,
            distanceMeters: 5_240, activeEnergyKilocalories: 365, averageHeartRate: 154, elevationAscendedMeters: 38
        )
        workouts = [
            workout(.running, daysAgo: 10, at: 7, 10, minutes: 34, km: 6.1, kcal: 410, bpm: 149, climb: 41),
            workout(.traditionalStrengthTraining, daysAgo: 9, at: 18, 0, minutes: 45, kcal: 260, bpm: 118, indoor: true),
            workout(.cycling, daysAgo: 8, at: 17, 30, minutes: 72, km: 31.8, kcal: 690, bpm: 136, climb: 310),
            workout(.running, daysAgo: 6, at: 6, 45, minutes: 52, km: 10.0, kcal: 705, bpm: 157, climb: 64),
            workout(.walking, daysAgo: 5, at: 12, 30, minutes: 28, km: 2.4, kcal: 120, bpm: 98),
            workout(.cycling, daysAgo: 3, at: 7, 0, minutes: 58, km: 24.2, kcal: 540, bpm: 132, climb: 185),
            workout(.traditionalStrengthTraining, daysAgo: 2, at: 18, 15, minutes: 50, kcal: 290, bpm: 121, indoor: true),
            workout(.running, daysAgo: 1, at: 7, 15, minutes: 41, km: 8.1, kcal: 560, bpm: 151, climb: 52),
            today,
        ]

        // Planned on the quarter hour before the run started, as people tend to.
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: today.start)
        components.minute = components.minute! - components.minute! % 15
        let plannedStart = calendar.date(from: components)!
        plannedRun = PlannedEventSpec(title: "Run", start: plannedStart, end: plannedStart.addingTimeInterval(45 * 60))
    }
}
#endif
