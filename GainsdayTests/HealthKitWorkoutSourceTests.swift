import Foundation
import Testing
@testable import Gainsday

@Suite("HealthKit workout source")
struct HealthKitWorkoutSourceTests {
    let source = HealthKitWorkoutSource(isHealthDataAvailable: false)

    @Test("Reports when Health isn't available on this device")
    func reportsUnavailable() {
        #expect(!source.isHealthDataAvailable)
    }

    @Test("Asking for access fails clearly when Health isn't available")
    func authorizationFailsWhenUnavailable() async {
        await #expect(throws: HealthKitWorkoutSource.Unavailable.self) {
            try await source.requestAuthorization()
        }
    }

    @Test("Reading workouts fails clearly when Health isn't available")
    func readsFailWhenUnavailable() async {
        await #expect(throws: HealthKitWorkoutSource.Unavailable.self) {
            _ = try await source.changes(since: nil)
        }
        await #expect(throws: HealthKitWorkoutSource.Unavailable.self) {
            _ = try await source.workouts(in: DateInterval(start: .distantPast, end: .now))
        }
        await #expect(throws: HealthKitWorkoutSource.Unavailable.self) {
            _ = try await source.recentWorkouts(limit: 1)
        }
    }
}
