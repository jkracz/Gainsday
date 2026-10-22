import Foundation
import SyncCore
import UserNotifications

/// The parts of `UNUserNotificationCenter` the notifier uses, so tests can stand in for it.
nonisolated protocol NotificationScheduling: Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: NotificationScheduling {}

/// Shows problems as local notifications. Each problem has a stable identifier, so
/// a repeat replaces rather than stacks. The problems already notified are kept in
/// UserDefaults on this device, so each one notifies once until it's resolved.
nonisolated final class LocalNotifier: NSObject, ProblemNotifier, UNUserNotificationCenterDelegate {
    private static let key = "notifiedProblems"
    private let center: any NotificationScheduling
    // UserDefaults is thread-safe but not marked Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(center: any NotificationScheduling = UNUserNotificationCenter.current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
    }

    /// Asks to show notifications. Answers after the first are remembered by the system.
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// The notification text for each problem. A new kind of problem needs one line here.
    static func content(for problem: Problem) -> (title: String, body: String) {
        switch problem {
        case .calendarAccessRevoked: (String(localized: "Calendar Access Is Off"), String(localized: "Gainsday can't add your workouts to your calendar. Turn calendar access back on in Settings."))
        case .destinationCalendarMissing: (String(localized: "Workout Calendar Is Gone"), String(localized: "The calendar Gainsday adds workouts to was deleted. Open Gainsday to choose another."))
        case .healthAccessRevoked: (String(localized: "Health Access Is Off"), String(localized: "Gainsday can't read your workouts. Turn Health access back on in Settings."))
        case .matchWaitingForReview: (String(localized: "Workout Waiting for Review"), String(localized: "Gainsday couldn't tell whether a workout belongs to one of your planned events, so it hasn't added it yet. Open the activity log to review it."))
        }
    }

    static func identifier(for problem: Problem) -> String {
        "problem.\(problem.rawValue)"
    }

    func notifiedProblems() async -> Set<Problem> {
        Set((defaults.stringArray(forKey: Self.key) ?? []).compactMap(Problem.init(rawValue:)))
    }

    func notify(_ problem: Problem) async {
        let (title, body) = Self.content(for: problem)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: Self.identifier(for: problem), content: content, trigger: nil))
        } catch {
            // Notifications are off. Leave the problem unrecorded so it's shown if they're turned on.
            return
        }
        await save(notifiedProblems().union([problem]))
    }

    func withdraw(_ problem: Problem) async {
        let identifiers = [Self.identifier(for: problem)]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        await save(notifiedProblems().subtracting([problem]))
    }

    private func save(_ problems: Set<Problem>) {
        defaults.set(problems.map(\.rawValue).sorted(), forKey: Self.key)
    }

    /// Shows problems as banners even while the app is open, since a sync on app
    /// open is when most of them are found.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
