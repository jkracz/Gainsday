import Foundation
import Observation
import SyncCore
import UserNotifications

/// Wires the sync engine to the real adapters, runs passes and keeps the state the UI shows.
@Observable
final class SyncCoordinator {
    struct Pass {
        var finishedAt: Date
        var createdCount: Int
    }

    private(set) var settings = Settings()
    private(set) var hasLoaded = false
    /// Health and calendar permissions don't survive a reinstall, though settings
    /// restored from iCloud do, so setup runs once on every install.
    private(set) var hasFinishedSetupOnThisDevice = UserDefaults.standard.bool(forKey: setupKey)
    /// Set while the app waits for a pass or backfill. Shown as "Syncing…".
    var isSyncing = false
    var lastPass: Pass?
    var lastError: String?

    let health: HealthKitWorkoutSource
    let calendar: EventKitCalendarStore
    private let settingsStore: CloudSettingsStore
    private let anchors: AnchorStore
    let cloudImport = CloudImportMonitor()
    let clock = SystemClock()
    private let notifier = LocalNotifier()
    let engine: SyncEngine
    /// Keeps passes from overlapping, so they can't create duplicates.
    let passes = PassRunner()
    /// Long enough for the iCloud import wait plus a normal pass.
    static let passTimeout: Duration = .seconds(90)
    private static let setupKey = "hasFinishedSetupOnThisDevice"

    var isSetUp: Bool {
        hasFinishedSetupOnThisDevice && settings.destinationCalendar != nil && settings.syncStartDate != nil
    }

    init(ledger: any Ledger) {
        health = HealthKitWorkoutSource()
        calendar = EventKitCalendarStore()
        settingsStore = CloudSettingsStore()
        anchors = AnchorStore()
        engine = SyncEngine(
            workouts: health,
            calendar: calendar,
            ledger: ledger,
            settings: settingsStore,
            judge: UnavailableMatchJudge(),
            clock: clock,
            notifier: notifier
        )
        UNUserNotificationCenter.current().delegate = notifier
    }

    func load() async {
        settings = await settingsStore.load()
        // The setup flag can come back from a device backup, and access can be revoked
        // in Settings. Either way, setup has to ask again before syncing can work.
        if hasFinishedSetupOnThisDevice, await calendar.accessMode() == .none {
            await engine.report(.calendarAccessRevoked)
            forgetSetup()
        }
        hasLoaded = true
    }

    /// Reloads settings whenever iCloud delivers a change, since settings restored
    /// after a reinstall can arrive after the app has opened.
    func watchCloudSettings() async {
        for await _ in settingsStore.externalChanges() {
            await load()
        }
    }

    /// Saves the destination and starts syncing workouts from now on. A sync start
    /// date restored from iCloud is kept, so a reinstall doesn't skip workouts.
    func finishSetup(destination: CalendarInfo) async {
        settings.destinationCalendar = CalendarReference(id: destination.id, title: destination.title)
        settings.syncStartDate = settings.syncStartDate ?? clock.now
        await settingsStore.save(settings)
        UserDefaults.standard.set(true, forKey: Self.setupKey)
        hasFinishedSetupOnThisDevice = true
        await notifier.requestAuthorization()
        await sync()
    }

    /// Changes settings now and backs them up to iCloud.
    func updateSettings(_ change: (inout Settings) -> Void) {
        change(&settings)
        Task { await settingsStore.save(settings) }
    }

    /// Runs a catch-up pass from the stored anchor. Does nothing before setup, or
    /// while another pass is running, so overlapping triggers create no duplicates.
    /// Shows an error if the pass takes longer than `passTimeout`.
    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await passes.run(timeout: Self.passTimeout) { await self.runPass() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// A pass that runs past its timeout still records its result when it finishes.
    private func runPass() async {
        await load()
        guard isSetUp else { return }
        // After a reinstall, give the ledger a chance to come back from iCloud first.
        _ = await cloudImport.waitForInitialImport()
        do {
            let result = try await engine.run(.changes(since: anchors.load()))
            if let anchor = result.nextAnchor {
                anchors.save(anchor)
            }
            let createdCount = result.actions.count { if case .create = $0 { true } else { false } }
            lastPass = Pass(finishedAt: clock.now, createdCount: createdCount)
            lastError = nil
        } catch CalendarStoreError.calendarNotFound(let id) where id == settings.destinationCalendar?.id {
            // The destination was deleted. Setup lets the user choose another.
            forgetSetup()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func forgetSetup() {
        UserDefaults.standard.removeObject(forKey: Self.setupKey)
        hasFinishedSetupOnThisDevice = false
    }
}
