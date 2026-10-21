import Foundation
import SyncCore

/// Stands in for the on-device model until matching planned events is built.
nonisolated struct UnavailableMatchJudge: MatchJudge {
    func availability() async -> MatchJudgeAvailability {
        .unavailable
    }

    func judge(_ workout: Workout, candidates: [CalendarEvent]) async throws -> MatchJudgement {
        MatchJudgement(chosenIndex: nil, confidence: 0)
    }
}
