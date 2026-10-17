import Foundation
import SyncCore
import SyncCoreTesting

/// A sync engine wired to in-memory fakes. Tests arrange the fakes, run a pass,
/// then assert on the resulting calendar, ledger and actions.
struct SyncHarness {
    static let now = Date(timeIntervalSince1970: 1_790_000_000) // 21 Sep 2026, 14:13 UTC
    static let destination = CalendarInfo(id: "workouts", title: "Workouts")
    static let watch = WorkoutSourceApp(bundleIdentifier: "com.apple.health", name: "Apple Watch")

    let clock: FixedClock
    let workouts: InMemoryWorkoutSource
    let calendar: InMemoryCalendarStore
    let ledger: InMemoryLedger
    let settings: InMemorySettingsStore
    let judge: StubMatchJudge
    let engine: SyncEngine

    init(
        workouts: [Workout] = [],
        settings: Settings = Settings(
            enabledTypes: [.running, .cycling, .traditionalStrengthTraining],
            destinationCalendar: CalendarReference(id: destination.id, title: destination.title),
            syncStartDate: now.addingTimeInterval(-7 * 24 * 60 * 60)
        ),
        accessMode: AccessMode = .full
    ) {
        clock = FixedClock(now: Self.now)
        self.workouts = InMemoryWorkoutSource(workouts: workouts)
        calendar = InMemoryCalendarStore(calendars: [Self.destination], accessMode: accessMode, clock: clock)
        ledger = InMemoryLedger()
        self.settings = InMemorySettingsStore(settings)
        judge = StubMatchJudge()
        engine = SyncEngine(
            workouts: self.workouts,
            calendar: calendar,
            ledger: ledger,
            settings: self.settings,
            judge: judge,
            clock: clock
        )
    }

    /// A workout that ended `minutesAgo` before now.
    static func run(minutes: Double = 30, minutesAgo: Double = 10) -> Workout {
        let end = now.addingTimeInterval(-minutesAgo * 60)
        return Workout(
            activityType: .running,
            start: end.addingTimeInterval(-minutes * 60),
            end: end,
            source: watch,
            metrics: WorkoutMetrics(distanceMeters: 5_000, averageHeartRate: 150)
        )
    }
}
