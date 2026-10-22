/// The screens of setup, in the order they're shown.
///
/// To add a step, add a case where it belongs, give it a screen in `SetupView.screen(for:)`,
/// and keep any choice it makes in `SetupModel`, for `startSyncing` to apply.
nonisolated enum SetupStep: CaseIterable, Hashable {
    /// What Gainsday reads and writes, shown before any permission prompt.
    case welcome
    case health
    case calendar
    /// Whether workouts update the events the user planned. Skipped with add-only access.
    case matching
    /// Workout types and the 7-day backfill, then Start Syncing.
    case start

    /// The step after this one, or nil for the last.
    var next: SetupStep? {
        let steps = Self.allCases
        guard let index = steps.firstIndex(of: self), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }
}
