import Foundation
import Observation
import SyncCore

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
    private(set) var isSyncing = false
    private(set) var lastPass: Pass?
    private(set) var lastError: String?
    /// The activity log, newest first.
    private(set) var activityLog: [ActivityLogEntry] = []

    let health: HealthKitWorkoutSource
    let calendar: EventKitCalendarStore
    private let settingsStore: CloudSettingsStore
    private let anchors: AnchorStore
    private let activityLogStore: FileActivityLogStore
    private let clock = SystemClock()
    private let engine: SyncEngine
    private static let setupKey = "hasFinishedSetupOnThisDevice"

    var isSetUp: Bool {
        hasFinishedSetupOnThisDevice && settings.destinationCalendar != nil && settings.syncStartDate != nil
    }

    init(ledger: any Ledger) {
        health = HealthKitWorkoutSource()
        calendar = EventKitCalendarStore()
        settingsStore = CloudSettingsStore()
        anchors = AnchorStore()
        activityLogStore = FileActivityLogStore()
        engine = SyncEngine(
            workouts: health,
            calendar: calendar,
            ledger: ledger,
            settings: settingsStore,
            judge: UnavailableMatchJudge(),
            clock: clock,
            activityLog: activityLogStore
        )
    }

    func load() async {
        settings = await settingsStore.load()
        await refreshActivityLog()
        // The setup flag can come back from a device backup, and access can be revoked
        // in Settings. Either way, setup has to ask again before syncing can work.
        if hasFinishedSetupOnThisDevice, await calendar.accessMode() == .none {
            UserDefaults.standard.removeObject(forKey: Self.setupKey)
            hasFinishedSetupOnThisDevice = false
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
        await sync()
    }

    /// Runs a catch-up pass from the stored anchor. Does nothing before setup, or
    /// while another pass is running, so overlapping triggers create no duplicates.
    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        await load()
        guard isSetUp else { return }
        do {
            let result = try await engine.run(.changes(since: anchors.load()))
            if let anchor = result.nextAnchor {
                anchors.save(anchor)
            }
            let createdCount = result.actions.count { if case .create = $0 { true } else { false } }
            lastPass = Pass(finishedAt: clock.now, createdCount: createdCount)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refreshActivityLog()
    }

    /// Undoes an activity log entry. It counts as a pass, so it never runs alongside one.
    func undo(_ entry: ActivityLogEntry) async throws {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        try await engine.undo(entryID: entry.id)
        await refreshActivityLog()
    }

    private func refreshActivityLog() async {
        activityLog = (try? await activityLogStore.load()) ?? []
    }
}
