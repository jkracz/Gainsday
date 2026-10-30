import CloudKit
import Foundation
import SyncCore
import Testing
@testable import Gainsday

@MainActor @Suite("Cloud import monitor")
struct CloudImportMonitorTests {
    let defaults = UserDefaults(suiteName: "CloudImportMonitorTests-\(UUID().uuidString)")!

    @Test("With no iCloud account there is nothing to import, so the first pass doesn't wait")
    func noAccountDoesNotWait() async {
        let monitor = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), accountStatus: { .noAccount })

        #expect(await monitor.waitForInitialImport(timeout: .seconds(60)))
    }

    @Test("Before the first import finishes, waiting gives up after the timeout")
    func waitingTimesOut() async {
        let monitor = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), accountStatus: { .available })

        #expect(await monitor.waitForInitialImport(timeout: .milliseconds(300)) == false)
    }

    @Test("An import finishing during the wait ends it, and later launches don't wait again")
    func importEndsWaitAndIsRemembered() async {
        let monitor = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), accountStatus: { .available })

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            monitor.markImportFinished()
        }

        #expect(await monitor.waitForInitialImport(timeout: .seconds(60)))
        let nextLaunch = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), accountStatus: { .available })
        #expect(await nextLaunch.waitForInitialImport(timeout: .milliseconds(1)))
    }

    @Test("Only the first pass after installing waits: once a wait has timed out, later passes and launches go ahead at once")
    func onlyFirstPassWaits() async {
        let monitor = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), accountStatus: { .available })
        #expect(await monitor.waitForInitialImport(timeout: .milliseconds(100)) == false)

        let clock = ContinuousClock()
        let started = clock.now
        let laterPass = await monitor.waitForInitialImport(timeout: .seconds(60))
        let nextLaunch = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), accountStatus: { .available })
        let afterRelaunch = await nextLaunch.waitForInitialImport(timeout: .seconds(60))

        #expect(laterPass == false)
        #expect(afterRelaunch == false)
        #expect(clock.now - started < .seconds(5))
    }

    @Test("In add-only mode nothing is written while the first import is unresolved, on this pass or later ones, since duplicates can't be spotted")
    func addOnlyWaitsForImport() async {
        let monitor = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), accountStatus: { .available })

        #expect(await monitor.isSafeToWrite(with: .addOnly, timeout: .milliseconds(100)) == false)
        #expect(await monitor.isSafeToWrite(with: .addOnly, timeout: .seconds(60)) == false)

        monitor.markImportFinished()
        #expect(await monitor.isSafeToWrite(with: .addOnly, timeout: .seconds(60)))
    }

    @Test("With full access a pass goes ahead after the timeout, since the footer scan stops duplicates")
    func fullAccessGoesAhead() async {
        let monitor = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), accountStatus: { .available })

        #expect(await monitor.isSafeToWrite(with: .full, timeout: .milliseconds(100)))
    }

    @Test("A fresh setup in add-only mode with no iCloud account goes ahead, since there's nothing to import")
    func addOnlyWithoutAccountGoesAhead() async {
        let monitor = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), accountStatus: { .noAccount })

        #expect(await monitor.isSafeToWrite(with: .addOnly, timeout: .seconds(60)))
    }

    @Test(
        "In add-only mode an iCloud account that can't be confirmed missing still blocks writes until the import, since its ledger may be on the way",
        arguments: [CKAccountStatus.temporarilyUnavailable, .couldNotDetermine, .restricted]
    )
    func addOnlyWaitsWhenAccountIsUnconfirmed(status: CKAccountStatus) async {
        let monitor = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), accountStatus: { status })

        #expect(await monitor.waitForInitialImport(timeout: .milliseconds(100)) == false)
        #expect(await monitor.isSafeToWrite(with: .addOnly, timeout: .milliseconds(100)) == false)
    }

    @Test("In add-only mode an iCloud account check that fails blocks writes until the import, rather than taking it as no account")
    func addOnlyWaitsWhenAccountCheckFails() async {
        let monitor = CloudImportMonitor(defaults: defaults, center: NotificationCenter(), accountStatus: { throw CKError(.networkUnavailable) })

        #expect(await monitor.waitForInitialImport(timeout: .milliseconds(100)) == false)
        #expect(await monitor.isSafeToWrite(with: .addOnly, timeout: .milliseconds(100)) == false)
    }
}
