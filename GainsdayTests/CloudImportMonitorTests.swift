import Foundation
import Testing
@testable import Gainsday

@MainActor @Suite("Cloud import monitor")
struct CloudImportMonitorTests {
    let defaults = UserDefaults(suiteName: "CloudImportMonitorTests-\(UUID().uuidString)")!

    @Test("With no iCloud account there is nothing to import, so the first pass doesn't wait")
    func noAccountDoesNotWait() async {
        let monitor = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), hasICloudAccount: { false })

        #expect(await monitor.waitForInitialImport(timeout: .seconds(60)))
    }

    @Test("Before the first import finishes, waiting gives up after the timeout")
    func waitingTimesOut() async {
        let monitor = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), hasICloudAccount: { true })

        #expect(await monitor.waitForInitialImport(timeout: .milliseconds(300)) == false)
    }

    @Test("An import finishing during the wait ends it, and later launches don't wait again")
    func importEndsWaitAndIsRemembered() async {
        let monitor = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), hasICloudAccount: { true })

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            monitor.markImportFinished()
        }

        #expect(await monitor.waitForInitialImport(timeout: .seconds(60)))
        let nextLaunch = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), hasICloudAccount: { true })
        #expect(await nextLaunch.waitForInitialImport(timeout: .milliseconds(1)))
    }

    @Test("Only the first pass after installing waits: once a wait has timed out, later passes and launches go ahead at once")
    func onlyFirstPassWaits() async {
        let monitor = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), hasICloudAccount: { true })
        #expect(await monitor.waitForInitialImport(timeout: .milliseconds(100)) == false)

        let clock = ContinuousClock()
        let started = clock.now
        let laterPass = await monitor.waitForInitialImport(timeout: .seconds(60))
        let nextLaunch = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), hasICloudAccount: { true })
        let afterRelaunch = await nextLaunch.waitForInitialImport(timeout: .seconds(60))

        #expect(laterPass == false)
        #expect(afterRelaunch == false)
        #expect(clock.now - started < .seconds(5))
    }
}
