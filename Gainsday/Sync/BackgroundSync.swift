import BackgroundTasks
import Foundation
import SyncCore
import UIKit

/// Syncs without the app open: Health wakes the app when a workout is saved, and a
/// background refresh task is a safety net for missed wakes. A pass that finds the
/// phone locked finishes once it's unlocked, or at the latest on the next app open.
extension SyncCoordinator {
    /// Listed in `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    nonisolated static let appRefreshTaskID = "app.gainsday.ios.refresh"

    /// Call during launch: Health delivers a background launch only to an observer
    /// that is registered promptly.
    func startBackgroundSync() {
        health.observeWorkouts { [weak self] finished in
            Task { @MainActor in
                await self?.syncInBackground()
                finished()
            }
        }
        Task {
            await enableBackgroundDelivery()
        }
        Task {
            await finishPassesOnUnlock()
        }
    }

    /// Asks Health to wake the app for new workouts. Fails quietly until Health
    /// access has been asked for, so setup calls it again.
    func enableBackgroundDelivery() async {
        try? await health.enableBackgroundDelivery()
    }

    /// The background refresh task's work: a catch-up pass, after asking for the next one.
    func refreshInBackground() async {
        scheduleAppRefresh()
        await syncInBackground()
    }

    /// Asks the system for a background refresh later. It fails in the Simulator and
    /// when Background App Refresh is off, and then app opens still catch up.
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.appRefreshTaskID)
        request.earliestBeginDate = clock.now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// A pass started by Health or the system rather than the user. While the phone
    /// is locked, Health can't be read, so the pass waits for the unlock.
    private func syncInBackground() async {
        guard UIApplication.shared.isProtectedDataAvailable else {
            isWaitingForUnlock = true
            scheduleAppRefresh()
            return
        }
        await sync()
    }

    private func finishPassesOnUnlock() async {
        for await _ in NotificationCenter.default.signals(named: UIApplication.protectedDataDidBecomeAvailableNotification)
        where isWaitingForUnlock {
            await sync()
        }
    }
}
