import Foundation
import FoundationModels
import SyncCore
import Testing
@testable import Gainsday

@Suite("On-device match judge")
struct OnDeviceMatchJudgeTests {
    static let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")

    @Test("iOS 26 rate-limit and missing-model errors mean the model can't answer now, and other errors don't")
    func mapsIOS26Errors() {
        #expect(OnDeviceMatchJudge.reason(for: LanguageModelSession.GenerationError.rateLimited(Self.context)) == .rateLimited)
        #expect(OnDeviceMatchJudge.reason(for: LanguageModelSession.GenerationError.concurrentRequests(Self.context)) == .rateLimited)
        #expect(OnDeviceMatchJudge.reason(for: LanguageModelSession.GenerationError.assetsUnavailable(Self.context)) == .unavailable)
        #expect(OnDeviceMatchJudge.reason(for: LanguageModelSession.GenerationError.guardrailViolation(Self.context)) == nil)
        #expect(OnDeviceMatchJudge.reason(for: URLError(.timedOut)) == nil)
    }

    @Test("iOS 27 rate-limit errors mean the model can't answer now, and other errors don't")
    func mapsIOS27Errors() throws {
        guard #available(iOS 27, *) else { return }
        #expect(OnDeviceMatchJudge.reason(for: LanguageModelSession.Error.concurrentRequests) == .rateLimited)
        #expect(OnDeviceMatchJudge.reason(for: LanguageModelError.guardrailViolation(.init(debugDescription: "test"))) == nil)
    }

    @Test("The prompt numbers the planned events from 0, with only their titles and times")
    func promptListsCandidates() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let workout = Workout(
            activityType: .traditionalStrengthTraining,
            start: start,
            end: start.addingTimeInterval(55 * 60),
            source: WorkoutSourceApp(bundleIdentifier: "com.apple.health", name: "Apple Watch")
        )
        let gym = CalendarEvent(
            id: "gym",
            calendarID: "personal",
            content: EventContent(title: "Gym w/ Alex", start: start, end: start.addingTimeInterval(3600), notes: "Locker code 1234")
        )
        let lunch = CalendarEvent(
            id: "lunch",
            calendarID: "personal",
            content: EventContent(title: "Lunch", start: start, end: start.addingTimeInterval(1800))
        )

        let prompt = OnDeviceMatchJudge.prompt(for: workout, candidates: [gym, lunch])

        let lines = prompt.components(separatedBy: "\n")
        #expect(lines.count == 4)
        #expect(lines[0].hasPrefix("Workout: Strength Training, "))
        #expect(lines[2].hasPrefix("0: \"Gym w/ Alex\", "))
        #expect(lines[3].hasPrefix("1: \"Lunch\", "))
        #expect(!prompt.contains("Locker code"))
    }
}
