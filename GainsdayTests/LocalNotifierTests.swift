import Foundation
import Synchronization
import SyncCore
import Testing
import UserNotifications
@testable import Gainsday

@Suite("Local notifier")
struct LocalNotifierTests {
    /// Records requests instead of showing them, or fails as if notifications were off.
    final class FakeCenter: NotificationScheduling {
        let added = Mutex<[UNNotificationRequest]>([])
        let removed = Mutex<[String]>([])
        let notificationsAllowed: Bool

        init(notificationsAllowed: Bool = true) {
            self.notificationsAllowed = notificationsAllowed
        }

        func add(_ request: UNNotificationRequest) async throws {
            guard notificationsAllowed else { throw UNError(.notificationsNotAllowed) }
            added.withLock { $0.append(request) }
        }

        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
            removed.withLock { $0.append(contentsOf: identifiers) }
        }

        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    }

    let center = FakeCenter()
    let defaults = UserDefaults(suiteName: "LocalNotifierTests.\(UUID().uuidString)")!

    @Test("A problem is shown straight away with its own text, under a stable identifier")
    func showsProblem() async throws {
        let notifier = LocalNotifier(center: center, defaults: defaults)

        await notifier.notify(.calendarAccessRevoked)

        let request = try #require(center.added.withLock { $0.first })
        #expect(request.identifier == "problem.calendarAccessRevoked")
        #expect(request.trigger == nil)
        #expect(request.content.title == "Calendar Access Is Off")
        #expect(request.content.body.contains("Settings"))
    }

    @Test("Notified problems are remembered across launches")
    func remembersNotifiedProblems() async {
        await LocalNotifier(center: center, defaults: defaults).notify(.destinationCalendarMissing)

        let relaunched = LocalNotifier(center: center, defaults: defaults)

        #expect(await relaunched.notifiedProblems() == [.destinationCalendarMissing])
    }

    @Test("Withdrawing a problem removes its notification and forgets it")
    func withdrawsProblem() async {
        let notifier = LocalNotifier(center: center, defaults: defaults)
        await notifier.notify(.calendarAccessRevoked)
        await notifier.notify(.healthAccessRevoked)

        await notifier.withdraw(.calendarAccessRevoked)

        #expect(center.removed.withLock { $0 } == ["problem.calendarAccessRevoked"])
        #expect(await notifier.notifiedProblems() == [.healthAccessRevoked])
    }

    @Test("When notifications are off, the problem isn't recorded, so it's shown once they're on")
    func notificationsOff() async {
        let notifier = LocalNotifier(center: FakeCenter(notificationsAllowed: false), defaults: defaults)

        await notifier.notify(.calendarAccessRevoked)

        #expect(await notifier.notifiedProblems().isEmpty)
    }

    @Test("Every problem has its own title and identifier")
    func distinctProblems() {
        let titles = Set(Problem.allCases.map { LocalNotifier.content(for: $0).title })
        let identifiers = Set(Problem.allCases.map(LocalNotifier.identifier))

        #expect(titles.count == Problem.allCases.count)
        #expect(identifiers.count == Problem.allCases.count)
    }
}
