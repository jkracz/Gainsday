import Foundation

/// Keeps the Health query anchor between passes (UserDefaults in the app, on this
/// device only).
public protocol WorkoutAnchorStore: Sendable {
    func load() async -> WorkoutAnchor?
    func save(_ anchor: WorkoutAnchor) async
}
