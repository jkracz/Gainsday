import Foundation

/// Tells the user when a pass held a workout for their review. [v1.1]
extension SyncEngine {
    /// Notifies once for a pass that held any workouts. Each such pass notifies, since
    /// every held workout is new to review. The notification's stable identifier makes
    /// a repeat replace the earlier one rather than stack.
    func notifyHeldWorkouts(in result: SyncResult) async -> SyncResult {
        if result.actions.contains(where: \.isHeldForReview) {
            await notifier.notify(.matchWaitingForReview)
        }
        return result
    }
}

private extension SyncAction {
    var isHeldForReview: Bool {
        if case .holdForReview = self { true } else { false }
    }
}
