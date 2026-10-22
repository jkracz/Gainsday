import Foundation
import FoundationModels
import SyncCore

/// Decides unclear matches with Apple's on-device model, so nothing leaves the phone.
/// On iPhones without Apple Intelligence, or while the model is off or downloading,
/// it reports itself unavailable and the engine falls back.
actor OnDeviceMatchJudge: MatchJudge {
    /// How long to stop asking after the model says it's rate-limited.
    private static let rateLimitPause: TimeInterval = 5 * 60
    private var rateLimitedUntil: Date?

    func availability() async -> MatchJudgeAvailability {
        if let rateLimitedUntil, Date() < rateLimitedUntil {
            return .rateLimited
        }
        return SystemLanguageModel.default.isAvailable ? .available : .unavailable
    }

    func judge(_ workout: Workout, candidates: [CalendarEvent]) async throws -> MatchJudgement {
        // A session handles one request at a time, so each judgement gets its own.
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let answer = try await session.respond(to: Self.prompt(for: workout, candidates: candidates), generating: Judgement.self).content
            return MatchJudgement(chosenIndex: answer.chosenIndex, confidence: Double(min(max(answer.confidence, 0), 100)) / 100)
        } catch {
            guard let reason = Self.reason(for: error) else {
                // A refusal, a guardrail, or an answer that couldn't be read: no confident answer.
                return MatchJudgement(chosenIndex: nil, confidence: 0)
            }
            if reason == .rateLimited {
                rateLimitedUntil = Date().addingTimeInterval(Self.rateLimitPause)
            }
            throw reason
        }
    }

    /// The answer the model fills in.
    @Generable
    struct Judgement {
        @Guide(description: "The number of the planned event that is the plan for this workout, or nil if none of them is.")
        var chosenIndex: Int?
        @Guide(description: "How sure you are, from 0 (guessing) to 100 (certain).", .range(0...100))
        var confidence: Int
    }

    static let instructions = """
        You decide which calendar event, if any, a person planned for a workout they just finished. \
        The events are on the same day as the workout and close to it in time. \
        Choose an event only if its title describes this kind of workout, for example "Gym w/ Alex" for strength training. \
        Events about meetings, meals, errands or other kinds of workouts are not the plan. \
        If you are unsure, say so with a low confidence.
        """

    /// The workout and its numbered candidates, with titles and times only.
    static func prompt(for workout: Workout, candidates: [CalendarEvent]) -> String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "en_US_POSIX"))
        let workoutLine = "Workout: \(workout.activityType.name), \(workout.start.formatted(time)) to \(workout.end.formatted(time))"
        let eventLines = candidates.enumerated().map { index, event in
            "\(index): \"\(event.content.title)\", \(event.content.start.formatted(time)) to \(event.content.end.formatted(time))"
        }
        return ([workoutLine, "Planned events:"] + eventLines).joined(separator: "\n")
    }

    /// Whether an error means the model can't answer right now, for both the iOS 26 and
    /// the iOS 27 error types. Nil for any other error.
    static func reason(for error: any Error) -> MatchJudgeError? {
        if #available(iOS 27, *) {
            switch error {
            case LanguageModelError.rateLimited, LanguageModelSession.Error.concurrentRequests:
                return .rateLimited
            case SystemLanguageModel.Error.assetsUnavailable:
                return .unavailable
            default:
                break
            }
        }
        switch error as? LanguageModelSession.GenerationError {
        case .rateLimited, .concurrentRequests:
            return .rateLimited
        case .assetsUnavailable:
            return .unavailable
        default:
            return nil
        }
    }
}
