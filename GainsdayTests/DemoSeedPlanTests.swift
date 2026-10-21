#if DEBUG
import Foundation
import SyncCore
import Testing
@testable import Gainsday

@Suite("Demo seed plan")
struct DemoSeedPlanTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
    /// 20 Oct 2026, 19:07 in Los Angeles.
    let now = Date(timeIntervalSince1970: 1_792_548_420)

    @Test("Workouts cover the past ten days, oldest first, and are all over before now")
    func workoutsCoverPastTenDays() {
        let plan = DemoSeedPlan(now: now, calendar: calendar)

        let tenDaysAgo = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -10, to: now)!)
        #expect(plan.workouts.allSatisfy { $0.start >= tenDaysAgo && $0.start < $0.end && $0.end < now })
        #expect(plan.workouts.map(\.start) == plan.workouts.map(\.start).sorted())
        #expect(Set(plan.workouts.map(\.activityType)).isSuperset(of: [.running, .cycling, .traditionalStrengthTraining]))
    }

    @Test("One run finishes today, and the backfill's past week includes it")
    func oneRunFinishesToday() {
        let plan = DemoSeedPlan(now: now, calendar: calendar)

        let today = plan.workouts.filter { calendar.isDate($0.end, inSameDayAs: now) }
        #expect(today.count == 1)
        #expect(today.first?.activityType == .running)
        #expect(today.first.map { $0.start > now.addingTimeInterval(-7 * 24 * 60 * 60) } == true)
    }

    @Test("The planned Run overlaps today's run, so matching picks it")
    func plannedRunOverlapsTodaysRun() throws {
        let plan = DemoSeedPlan(now: now, calendar: calendar)
        let run = try #require(plan.workouts.last)

        #expect(plan.plannedRun.title == "Run")
        #expect(plan.plannedRun.start <= run.start && run.start < plan.plannedRun.end)
        #expect(calendar.component(.minute, from: plan.plannedRun.start) % 15 == 0)
        #expect(calendar.component(.second, from: plan.plannedRun.start) == 0)
    }
}
#endif
