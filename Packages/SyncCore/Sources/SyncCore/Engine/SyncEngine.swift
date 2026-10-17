import Foundation

/// Runs sync passes: reads workouts, decides what to write, writes it through the
/// ports and reports every action taken or planned.
public struct SyncEngine: Sendable {
    public var workouts: any WorkoutSource
    public var calendar: any CalendarStore
    public var ledger: any Ledger
    public var settings: any SettingsStore
    public var judge: any MatchJudge
    public var clock: any Clock

    public init(
        workouts: any WorkoutSource,
        calendar: any CalendarStore,
        ledger: any Ledger,
        settings: any SettingsStore,
        judge: any MatchJudge,
        clock: any Clock
    ) {
        self.workouts = workouts
        self.calendar = calendar
        self.ledger = ledger
        self.settings = settings
        self.judge = judge
        self.clock = clock
    }

    /// Runs one sync pass.
    ///
    /// The sync rules (eligibility, clustering, dedupe and the event lifecycle)
    /// are added feature by feature. For now a pass reads its inputs and takes no actions.
    public func run(_ trigger: SyncTrigger) async throws -> SyncResult {
        switch trigger {
        case .changes(let anchor):
            let changes = try await workouts.changes(since: anchor)
            return SyncResult(actions: [], nextAnchor: changes.anchor)
        case .backfill(let interval, _):
            _ = try await workouts.workouts(in: interval)
            return SyncResult(actions: [])
        }
    }
}
